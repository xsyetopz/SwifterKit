#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"
#if SWIFTERKIT_ENABLE_NETWORKING
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <NetworkingDriverKit/IOUserNetworkPacketPoller.h>
    #include <NetworkingDriverKit/NetworkingDriverKit.h>
    #include <time.h>

    #include "SwifterKitRuntimeNetworkMetadata.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

// Queue and batch contract:
// - A receive batch takes every empty packet it needs before it copies a frame. A batch the Rx
//   submission queue cannot supply delivers nothing. Frames the Rx completion queue refuses
//   return to their pool and the batch reports kIOReturnNoSpace.
// - A completion batch names distinct pending transmits. Any unknown or repeated ID fails the
//   whole batch before a packet changes. Each packet records its status, timestamp, and trace
//   event. Then the batch returns through the Tx completion queue at once.
// - Queue enables, purges, and services run under networkLock, except the service, which drains
//   the Tx submission queue through DrainNetworkTransmits and takes the lock itself.
//
// Interface-command contract:
// - processInterfaceCommand runs on the default queue. With a host connected, it queues a
//   required interfaceCommand event. It polls every millisecond, without the lock, for Swift's
//   answer. The answer arrives through the user client on its own queue.
// - It returns once, at the first of: Swift's status, kInterfaceCommandTimeoutNanoseconds, the
//   host detaching, or the network stopping. A late or repeated answer fails with
//   kIOReturnNotFound. With no host connected it returns kIOReturnUnsupported at once.

namespace {
    // Short, because the family's ioctl and this service's default queue wait meanwhile.
    constexpr uint64_t kInterfaceCommandTimeoutNanoseconds = 2'000'000'000ULL;

    uint64_t Now() {
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    }
}  // namespace

// Copies the name `IOUserNetworkEthernet::getBSDName` returns, or answers with no bytes while it
// returns nullptr, before the interface registers.
kern_return_t SwifterKitRuntimeService::NetworkBSDName(OSData** response) {
    const char* name = getBSDName();
    *response = name == nullptr ? OSData::withCapacity(0) : OSData::withBytes(name, strlen(name));
    return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::NetworkPacketCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength) {
    const auto command = static_cast<SwifterKitRuntimeOpcode>(opcode);
    switch (command) {
        case SwifterKitRuntimeOpcode::NetworkReceivePackets:
            return NetworkReceivePackets(payload, payloadLength);
        case SwifterKitRuntimeOpcode::NetworkCompleteTransmits:
            return NetworkCompleteTransmits(payload, payloadLength);
        default:
            break;
    }
    uint32_t reserved = 1;
    if (command == SwifterKitRuntimeOpcode::NetworkServiceTransmitQueue) {
        if (payloadLength == sizeof(reserved))
            memcpy(&reserved, payload, sizeof(reserved));
        if (reserved != 0)
            return kIOReturnBadArgument;
        DrainNetworkTransmits();
        return kIOReturnSuccess;
    }
    kern_return_t result = kIOReturnUnsupported;
    IOLockLock(ivars->networkLock);
    if (ivars->networkStopping || ivars->networkTxSubmission == nullptr) {
        result = kIOReturnNotReady;
    } else if (command == SwifterKitRuntimeOpcode::NetworkSetQueueEnabled) {
        SwifterKitNetworkQueueEnable request = {
            .queue = kSwifterKitNetworkQueueCount,
            .enabled = 2};
        if (payloadLength == sizeof(request))
            memcpy(&request, payload, sizeof(request));
        // The check misses setEnable() through an element. Its suggested const fails to build.
        // NOLINTNEXTLINE(misc-const-correctness)
        IOUserNetworkPacketQueue* queues[kSwifterKitNetworkQueueCount] = {
            ivars->networkTxSubmission,
            ivars->networkTxCompletion,
            ivars->networkRxSubmission,
            ivars->networkRxCompletion};
        result = request.queue < kSwifterKitNetworkQueueCount && request.enabled <= 1
                     ? queues[request.queue]->setEnable(request.enabled == 1)
                     : kIOReturnBadArgument;
    } else if (command == SwifterKitRuntimeOpcode::NetworkPurgeTransmitQueue) {
        if (payloadLength == sizeof(reserved))
            memcpy(&reserved, payload, sizeof(reserved));
        result = reserved == 0 ? kIOReturnSuccess : kIOReturnBadArgument;
        if (result == kIOReturnSuccess)
            ivars->networkTxSubmission->purgePackets();
    } else if (command == SwifterKitRuntimeOpcode::NetworkCompleteInterfaceCommand) {
        SwifterKitNetworkCompletion answer = {};
        if (payloadLength != sizeof(answer)) {
            result = kIOReturnBadArgument;
        } else {
            memcpy(&answer, payload, sizeof(answer));
            const bool matches = answer.requestID != 0
                                 && answer.requestID == ivars->networkCommandID
                                 && !ivars->networkCommandAnswered;
            if (matches) {
                ivars->networkCommandAnswered = true;
                ivars->networkCommandStatus = answer.status;
            }
            result = matches ? kIOReturnSuccess : kIOReturnNotFound;
        }
    }
    IOLockUnlock(ivars->networkLock);
    return result;
}

kern_return_t SwifterKitRuntimeService::NetworkReceivePackets(
    const uint8_t* payload,
    uint32_t payloadLength) {
    SwifterKitNetworkBatchHeader batch = {};
    if (payloadLength < sizeof(batch))
        return kIOReturnBadArgument;
    memcpy(&batch, payload, sizeof(batch));
    if (batch.count == 0 || batch.count > kSwifterKitNetworkMaximumBatch || batch.reserved != 0)
        return kIOReturnBadArgument;
    SwifterKitNetworkReceivePacket entries[kSwifterKitNetworkMaximumBatch] = {};
    const uint8_t* frames[kSwifterKitNetworkMaximumBatch] = {};
    uint32_t offset = sizeof(batch);
    for (uint32_t index = 0; index < batch.count; ++index) {
        if (payloadLength - offset < sizeof(entries[index]))
            return kIOReturnBadArgument;
        memcpy(&entries[index], payload + offset, sizeof(entries[index]));
        offset += sizeof(entries[index]);
        if (!SwifterKitIsValidReceivePacket(entries[index], kSwifterKitEthernetPacketBufferSize)
            || payloadLength - offset < entries[index].length)
            return kIOReturnBadArgument;
        frames[index] = payload + offset;
        offset += entries[index].length;
    }
    if (offset != payloadLength)
        return kIOReturnBadArgument;

    IOUserNetworkPacket* packets[kSwifterKitNetworkMaximumBatch] = {};
    IOUserNetworkPacketPoller* poller = nullptr;
    uint32_t delivered = 0;
    kern_return_t result = kIOReturnSuccess;
    IOLockLock(ivars->networkLock);
    if (ivars->networkStopping || ivars->networkRxSubmission == nullptr)
        result = kIOReturnNotReady;
    uint32_t taken = result == kIOReturnSuccess
                         ? ivars->networkRxSubmission->DequeuePackets(packets, batch.count)
                         : 0;
    if (result == kIOReturnSuccess && taken != batch.count)
        result = kIOReturnNoResources;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < batch.count; ++index)
        result = SwifterKitFillReceivePacket(
            packets[index],
            entries[index],
            frames[index],
            kSwifterKitEthernetPacketBufferSize);
    if (result == kIOReturnSuccess) {
        if ((ivars->networkTapMode & kSwifterKitEthernetTapInput) != 0)
            for (uint32_t index = 0; index < batch.count; ++index)
                bpfTapInputPacket(kSwifterKitEthernetDataLinkType, packets[index], nullptr, 0);
        delivered = ivars->networkRxCompletion->EnqueuePackets(packets, batch.count);
        result = delivered == batch.count ? kIOReturnSuccess : kIOReturnNoSpace;
        taken = batch.count;
    }
    for (uint32_t index = delivered; index < taken; ++index)
        SwifterKitReturnNetworkPacket(packets[index]);
    uint32_t bytes = 0;
    for (uint32_t index = 0; index < delivered; ++index)
        bytes += entries[index].length;
    if (delivered != 0 && ivars->networkPoller != nullptr) {
        poller = ivars->networkPoller;
        poller->retain();
    }
    IOLockUnlock(ivars->networkLock);
    // The poller may call back into the network queue, so it hears of the frames unlocked.
    if (poller != nullptr) {
        (void)poller->updatePacketCounters(delivered, bytes);
        poller->release();
    }
    return result;
}

kern_return_t SwifterKitRuntimeService::NetworkCompleteTransmits(
    const uint8_t* payload,
    uint32_t payloadLength) {
    SwifterKitNetworkBatchHeader batch = {};
    if (payloadLength < sizeof(batch))
        return kIOReturnBadArgument;
    memcpy(&batch, payload, sizeof(batch));
    SwifterKitNetworkTransmitCompletion entries[kSwifterKitNetworkMaximumBatch] = {};
    if (batch.count == 0 || batch.count > kSwifterKitNetworkMaximumBatch || batch.reserved != 0
        || payloadLength != sizeof(batch) + batch.count * sizeof(entries[0]))
        return kIOReturnBadArgument;
    memcpy(entries, payload + sizeof(batch), batch.count * sizeof(entries[0]));
    for (uint32_t index = 0; index < batch.count; ++index)
        if (entries[index].requestID == 0
            || (entries[index].flags & ~kSwifterKitNetworkCompletionFlags) != 0
            || ((entries[index].flags & kSwifterKitNetworkPacketHasTimestamp) == 0
                && entries[index].timestamp != 0)
            || ((entries[index].flags & kSwifterKitNetworkPacketHasTraceEvent) == 0
                && entries[index].traceEvent != 0))
            return kIOReturnBadArgument;

    IOUserNetworkPacket* packets[kSwifterKitNetworkMaximumBatch] = {};
    kern_return_t result = kIOReturnSuccess;
    IOLockLock(ivars->networkLock);
    if (ivars->networkStopping || ivars->networkTxCompletion == nullptr)
        result = kIOReturnNotReady;
    // Every ID must name a distinct pending transmit before any packet leaves its slot.
    // The check misses the `*slots[index] = {}` write below. Its suggested const fails to build.
    // NOLINTNEXTLINE(misc-const-correctness)
    SwifterKitNetworkPendingTransmit* slots[kSwifterKitNetworkMaximumBatch] = {};
    for (uint32_t index = 0; result == kIOReturnSuccess && index < batch.count; ++index) {
        for (auto& pending : ivars->networkTransmits)
            if (pending.packet != nullptr && pending.requestID == entries[index].requestID)
                slots[index] = &pending;
        for (uint32_t earlier = 0; earlier < index; ++earlier)
            if (slots[earlier] == slots[index])
                slots[index] = nullptr;
        if (slots[index] == nullptr)
            result = kIOReturnNotFound;
    }
    for (uint32_t index = 0; result == kIOReturnSuccess && index < batch.count; ++index) {
        packets[index] = slots[index]->packet;
        *slots[index] = {};
        SwifterKitCompleteTransmitPacket(
            packets[index],
            entries[index].status,
            entries[index].flags,
            entries[index].timestamp,
            entries[index].traceEvent);
    }
    if (result == kIOReturnSuccess) {
        result = ivars->networkTxCompletion->enqueuePackets(packets, batch.count, 0);
        for (uint32_t index = 0; index < batch.count; ++index) {
            if (result != kIOReturnSuccess)
                SwifterKitReturnNetworkPacket(packets[index]);
            packets[index]->release();
        }
    }
    IOLockUnlock(ivars->networkLock);
    return result;
}

kern_return_t SwifterKitRuntimeService::processInterfaceCommand(ifdrv_t* command) {
    if (command == nullptr || ivars == nullptr || ivars->networkLock == nullptr
        || ivars->eventLock == nullptr)
        return kIOReturnBadArgument;
    IOLockLock(ivars->eventLock);
    const bool connected = ivars->eventClient != nullptr;
    IOLockUnlock(ivars->eventLock);
    if (!connected)
        return kIOReturnUnsupported;

    struct __attribute__((packed)) {
        SwifterKitNetworkEventHeader header;
        SwifterKitNetworkInterfaceCommand request;
    } event = {};
    static_assert(sizeof(event.request.name) == sizeof(command->ifd_name));
    memcpy(event.request.name, command->ifd_name, sizeof(event.request.name));
    event.request.name[sizeof(event.request.name) - 1] = 0;
    event.request.command = command->ifd_cmd;
    event.request.length = command->ifd_len;

    IOLockLock(ivars->networkLock);
    kern_return_t result = ivars->networkStopping    ? kIOReturnNotReady
                           : ivars->networkCommandID ? kIOReturnBusy
                                                     : kIOReturnSuccess;
    uint32_t requestID = 0;
    if (result == kIOReturnSuccess) {
        requestID = ivars->nextNetworkCommandID;
        ivars->nextNetworkCommandID = requestID == UINT32_MAX ? 1 : requestID + 1;
        ivars->networkCommandID = requestID;
        ivars->networkCommandAnswered = false;
        ivars->networkCommandStatus = kIOReturnTimeout;
    }
    IOLockUnlock(ivars->networkLock);
    if (result != kIOReturnSuccess)
        return result;

    event.header = {
        kSwifterKitNetworkEventInterfaceCommand,
        requestID,
        0,
        static_cast<uint32_t>(sizeof(event.request))};
    result = EnqueueRequiredEvent(kSwifterKitEventNetwork, &event, sizeof(event));
    const uint64_t deadline = Now() + kInterfaceCommandTimeoutNanoseconds;
    while (result == kIOReturnSuccess) {
        IOLockLock(ivars->eventLock);
        const bool attached = ivars->eventClient != nullptr;
        IOLockUnlock(ivars->eventLock);
        IOLockLock(ivars->networkLock);
        const bool answered = ivars->networkCommandAnswered;
        const bool stopping = ivars->networkStopping;
        const int32_t status = ivars->networkCommandStatus;
        IOLockUnlock(ivars->networkLock);
        if (answered)
            result = status;
        else if (!attached || stopping)
            result = kIOReturnAborted;
        else if (Now() >= deadline)
            result = kIOReturnTimeout;
        else {
            IOSleep(1);
            continue;
        }
        break;
    }
    // Answered or not, the request ends here, so a later answer finds nothing.
    IOLockLock(ivars->networkLock);
    ivars->networkCommandID = 0;
    ivars->networkCommandAnswered = false;
    IOLockUnlock(ivars->networkLock);
    return result;
}
#endif
