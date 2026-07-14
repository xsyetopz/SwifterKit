#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"
#if SWIFTERKIT_ENABLE_NETWORKING
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <NetworkingDriverKit/NetworkingDriverKit.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

void SwifterKitRuntimeService::NetworkTxPacketAvailable_Impl(OSAction*) {
    if (ivars == nullptr || ivars->networkLock == nullptr)
        return;
    IOLockLock(ivars->networkLock);
    if (ivars->networkStopping || ivars->networkTxSubmission == nullptr) {
        IOLockUnlock(ivars->networkLock);
        return;
    }
    IOUserNetworkPacket* packets[8] = {};
    uint32_t count = ivars->networkTxSubmission->DequeuePackets(packets, 8);
    for (uint32_t index = 0; index < count; ++index) {
        IOUserNetworkPacket* packet = packets[index];
        SwifterKitNetworkPendingTransmit* pending = nullptr;
        for (auto& candidate : ivars->networkTransmits) {
            if (candidate.packet == nullptr) {
                pending = &candidate;
                break;
            }
        }
        uint32_t length = packet->getDataLength();
        uint64_t address = packet->getDataVirtualAddress();
        uint16_t offset = packet->getDataOffset();
        if (pending == nullptr || length == 0 || length > kSwifterKitEthernetPacketBufferSize
            || address == 0) {
            (void)ivars->networkPool->deallocatePacket(packet);
            continue;
        }
        uint32_t identifier = 0;
        for (uint32_t attempt = 0; attempt <= 64 && identifier == 0; ++attempt) {
            uint32_t candidate = ivars->nextNetworkRequestID++;
            if (candidate == 0)
                candidate = ivars->nextNetworkRequestID++;
            bool inUse = false;
            for (const auto& active : ivars->networkTransmits)
                if (active.packet != nullptr && active.requestID == candidate) {
                    inUse = true;
                    break;
                }
            if (!inUse)
                identifier = candidate;
        }
        if (identifier == 0) {
            (void)ivars->networkPool->deallocatePacket(packet);
            continue;
        }
        packet->retain();
        *pending = {identifier, packet};
        SwifterKitNetworkEventHeader header = {2, identifier, length, length};
        OSData* event = OSData::withCapacity(sizeof(header) + length);
        const void* bytes = reinterpret_cast<const void*>(address + offset);
        bool ready = event != nullptr && event->appendBytes(&header, sizeof(header))
                     && event->appendBytes(bytes, length);
        kern_return_t result = ready ? EnqueueRequiredEvent(
                                           0x0900,
                                           event->getBytesNoCopy(),
                                           static_cast<uint32_t>(event->getLength()))
                                     : kIOReturnNoMemory;
        OSSafeReleaseNULL(event);
        if (result != kIOReturnSuccess) {
            pending->requestID = 0;
            OSSafeReleaseNULL(pending->packet);
            (void)ivars->networkPool->deallocatePacket(packet);
        }
    }
    IOLockUnlock(ivars->networkLock);
}

kern_return_t SwifterKitRuntimeService::NetworkCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength) {
    if (ivars == nullptr || payload == nullptr || ivars->networkLock == nullptr)
        return kIOReturnBadArgument;
    IOLockLock(ivars->networkLock);
    if (ivars->networkStopping || ivars->networkPool == nullptr) {
        IOLockUnlock(ivars->networkLock);
        return kIOReturnNotReady;
    }
    kern_return_t result = kIOReturnUnsupported;
    if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkReceive)) {
        if (payloadLength < sizeof(SwifterKitNetworkReceiveHeader))
            result = kIOReturnBadArgument;
        else {
            const auto* header = reinterpret_cast<const SwifterKitNetworkReceiveHeader*>(payload);
            if (header->length == 0 || header->length > kSwifterKitEthernetPacketBufferSize
                || payloadLength != sizeof(*header) + header->length || header->reserved[0] != 0
                || header->reserved[1] != 0 || header->reserved[2] != 0)
                result = kIOReturnBadArgument;
            else {
                IOUserNetworkPacket* packet = nullptr;
                result = ivars->networkRxSubmission->DequeuePacket(&packet);
                if (result == kIOReturnSuccess && packet != nullptr) {
                    uint64_t address = packet->getDataVirtualAddress();
                    uint16_t offset = packet->getDataOffset();
                    result = address == 0 ? kIOReturnNotReady : kIOReturnSuccess;
                    if (result == kIOReturnSuccess) {
                        memcpy(
                            reinterpret_cast<void*>(address + offset),
                            payload + sizeof(*header),
                            header->length);
                        result = packet->setDataLength(header->length);
                    }
                    if (result == kIOReturnSuccess)
                        result = packet->setLinkHeaderLength(header->linkHeaderLength);
                    if (result == kIOReturnSuccess)
                        result = ivars->networkRxCompletion->EnqueuePacket(packet);
                    if (result != kIOReturnSuccess)
                        (void)ivars->networkPool->deallocatePacket(packet);
                } else if (result == kIOReturnSuccess)
                    result = kIOReturnNoResources;
            }
        }
    } else if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkCompleteTransmit)) {
        if (payloadLength != sizeof(SwifterKitNetworkCompletion))
            result = kIOReturnBadArgument;
        else {
            const auto* completion = reinterpret_cast<const SwifterKitNetworkCompletion*>(payload);
            IOUserNetworkPacket* packet = nullptr;
            for (auto& pending : ivars->networkTransmits)
                if (pending.requestID == completion->requestID && pending.packet != nullptr) {
                    packet = pending.packet;
                    pending = {};
                    break;
                }
            if (packet == nullptr)
                result = kIOReturnNotFound;
            else {
                result = completion->status == 0 ? ivars->networkTxCompletion->EnqueuePacket(packet)
                                                 : kIOReturnAborted;
                if (result != kIOReturnSuccess)
                    (void)ivars->networkPool->deallocatePacket(packet);
                packet->release();
                if (completion->status != 0)
                    result = kIOReturnSuccess;
            }
        }
    } else if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkReportLink)) {
        if (payloadLength != sizeof(SwifterKitNetworkLink))
            result = kIOReturnBadArgument;
        else {
            const auto* link = reinterpret_cast<const SwifterKitNetworkLink*>(payload);
            result = link->status == kIOUserNetworkLinkStatusInactive
                             || link->status == kIOUserNetworkLinkStatusActive
                         ? reportLinkStatus(link->status, link->media)
                         : kIOReturnBadArgument;
        }
    }
    IOLockUnlock(ivars->networkLock);
    return result;
}
#endif
