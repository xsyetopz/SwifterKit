#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeMappedMemory.h"
#include "SwifterKitRuntimeService.h"
#if SWIFTERKIT_ENABLE_NETWORKING
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <NetworkingDriverKit/IOUserNetworkPacketPoller.h>
    #include <NetworkingDriverKit/NetworkingDriverKit.h>

    #include "SwifterKitRuntimeNetworkMetadata.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

void SwifterKitRuntimeService::NetworkTxPacketAvailable_Impl(OSAction*) {
    DrainNetworkTransmits();
}

// Moves submitted frames to Swift. The data-available handler and each poll tick call this.
void SwifterKitRuntimeService::DrainNetworkTransmits() {
    if (ivars == nullptr || ivars->networkLock == nullptr)
        return;
    IOLockLock(ivars->networkLock);
    if (ivars->networkStopping || ivars->networkTxSubmission == nullptr) {
        IOLockUnlock(ivars->networkLock);
        return;
    }
    IOUserNetworkPacket* packets[8] = {};
    const uint32_t count = ivars->networkTxSubmission->DequeuePackets(packets, 8);
    for (uint32_t index = 0; index < count; ++index) {
        IOUserNetworkPacket* packet = packets[index];
        SwifterKitNetworkPendingTransmit* pending = nullptr;
        for (auto& candidate : ivars->networkTransmits) {
            if (candidate.packet == nullptr) {
                pending = &candidate;
                break;
            }
        }
        const uint32_t length = packet->getDataLength();
        const uint64_t address = packet->getDataVirtualAddress();
        const uint16_t offset = packet->getDataOffset();
        SwifterKitNetworkTransmitMetadata metadata = {};
        if (pending == nullptr || length == 0 || length > kSwifterKitEthernetPacketBufferSize
            || length > kSwifterKitMaximumEventPayloadLength - sizeof(SwifterKitNetworkEventHeader)
                            - sizeof(metadata)
            || address == 0) {
            SwifterKitReturnNetworkPacket(packet);
            continue;
        }
        SwifterKitReadTransmitMetadata(packet, &metadata);
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
            SwifterKitReturnNetworkPacket(packet);
            continue;
        }
        packet->retain();
        *pending = {identifier, packet};
        const uint32_t dataLength = static_cast<uint32_t>(sizeof(metadata)) + length;
        SwifterKitNetworkEventHeader header = {
            kSwifterKitNetworkEventTransmit,
            identifier,
            length,
            dataLength};
        OSData* event = OSData::withCapacity(sizeof(header) + dataLength);
        const void* bytes = SwifterKitMappedPointer<const void>(address + offset);
        const bool ready = event != nullptr && event->appendBytes(&header, sizeof(header))
                           && event->appendBytes(&metadata, sizeof(metadata))
                           && event->appendBytes(bytes, length);
        const kern_return_t result = ready ? EnqueueRequiredEvent(
                                                 kSwifterKitEventNetwork,
                                                 event->getBytesNoCopy(),
                                                 static_cast<uint32_t>(event->getLength()))
                                           : kIOReturnNoMemory;
        OSSafeReleaseNULL(event);
        if (result != kIOReturnSuccess) {
            pending->requestID = 0;
            OSSafeReleaseNULL(pending->packet);
            SwifterKitReturnNetworkPacket(packet);
        } else if ((ivars->networkTapMode & kSwifterKitEthernetTapOutput) != 0)
            bpfTapOutputPacket(kSwifterKitEthernetDataLinkType, packet, nullptr, 0);
    }
    IOLockUnlock(ivars->networkLock);
}

kern_return_t SwifterKitRuntimeService::NetworkCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength) {
    if (ivars == nullptr || payload == nullptr || ivars->networkLock == nullptr)
        return kIOReturnBadArgument;
    if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkSetPolling)
        || opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkSetPollerParameters))
        return NetworkPollerCommand(opcode, payload, payloadLength);
    if ((opcode & 0xFFF0U) == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkReceivePackets))
        return NetworkPacketCommand(opcode, payload, payloadLength);
    IOLockLock(ivars->networkLock);
    if (ivars->networkStopping || ivars->networkPool == nullptr) {
        IOLockUnlock(ivars->networkLock);
        return kIOReturnNotReady;
    }
    kern_return_t result = kIOReturnUnsupported;
    uint32_t receivedLength = 0;
    IOUserNetworkPacketPoller* poller = nullptr;
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
                    const uint64_t address = packet->getDataVirtualAddress();
                    const uint16_t offset = packet->getDataOffset();
                    result = address == 0 ? kIOReturnNotReady : kIOReturnSuccess;
                    if (result == kIOReturnSuccess) {
                        memcpy(
                            SwifterKitMappedPointer<void>(address + offset),
                            payload + sizeof(*header),
                            header->length);
                        result = packet->setDataLength(header->length);
                    }
                    if (result == kIOReturnSuccess)
                        result = packet->setLinkHeaderLength(header->linkHeaderLength);
                    if (result == kIOReturnSuccess
                        && (ivars->networkTapMode & kSwifterKitEthernetTapInput) != 0)
                        bpfTapInputPacket(kSwifterKitEthernetDataLinkType, packet, nullptr, 0);
                    if (result == kIOReturnSuccess)
                        result = ivars->networkRxCompletion->EnqueuePacket(packet);
                    if (result != kIOReturnSuccess)
                        (void)ivars->networkRxPool->deallocatePacket(packet);
                    else if (ivars->networkPoller != nullptr) {
                        receivedLength = header->length;
                        poller = ivars->networkPoller;
                        poller->retain();
                    }
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
                // A failed transmit returns through the completion queue with its status.
                SwifterKitCompleteTransmitPacket(packet, completion->status, 0, 0, 0);
                result = ivars->networkTxCompletion->EnqueuePacket(packet);
                if (result != kIOReturnSuccess)
                    SwifterKitReturnNetworkPacket(packet);
                packet->release();
            }
        }
    } else if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkReportLink)) {
        if (payloadLength != sizeof(SwifterKitNetworkLink))
            result = kIOReturnBadArgument;
        else {
            const auto* link = reinterpret_cast<const SwifterKitNetworkLink*>(payload);
            const uint32_t base =
                link->status
                & ~static_cast<uint32_t>(
                    kIOUserNetworkLinkStatusWakeSameNet | kIOUserNetworkLinkStatusForceNotify);
            result =
                base == kIOUserNetworkLinkStatusInactive || base == kIOUserNetworkLinkStatusActive
                    ? reportLinkStatus(link->status, link->media)
                    : kIOReturnBadArgument;
        }
    } else if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkReportLinkQuality)) {
        int32_t quality = 0;
        if (payloadLength == sizeof(quality))
            memcpy(&quality, payload, sizeof(quality));
        result = payloadLength == sizeof(quality) && quality >= kIOUserNetworkLinkQualityOff
                         && quality <= kIOUserNetworkLinkQualityGood
                     ? reportLinkQuality(static_cast<LinkQuality>(quality))
                     : kIOReturnBadArgument;
    } else if (
        opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkReportDataBandwidths)) {
        const auto* rates = reinterpret_cast<const SwifterKitNetworkBandwidths*>(payload);
        result = payloadLength == sizeof(*rates) && rates->effectiveInput <= rates->maximumInput
                         && rates->effectiveOutput <= rates->maximumOutput
                     ? reportDataBandwidths(
                           rates->maximumInput,
                           rates->maximumOutput,
                           rates->effectiveInput,
                           rates->effectiveOutput)
                     : kIOReturnBadArgument;
    } else if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkAddHardwareCounts)) {
        const auto* input = reinterpret_cast<const SwifterKitNetworkHardwareCounts*>(payload);
        IOUserNetworkHardwareCounts counts = {};
        if (payloadLength == sizeof(*input)) {
            counts.packets_in = input->packetsIn;
            counts.bytes_in = input->bytesIn;
            counts.multicasts_in = input->multicastsIn;
            counts.errors_in = input->errorsIn;
            counts.packets_out = input->packetsOut;
            counts.bytes_out = input->bytesOut;
            counts.multicasts_out = input->multicastsOut;
            counts.errors_out = input->errorsOut;
            counts.collisions = input->collisions;
            counts.dropped = input->dropped;
            counts.no_protocol = input->noProtocol;
            result = addHardwareCountsWithInterfaceStatistics(&counts);
        } else
            result = kIOReturnBadArgument;
    } else if (
        opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkReportNICProxyLimits)) {
        nicproxy_limits_info_t limits = {};
        static_assert(sizeof(limits) == 16);
        if (payloadLength != sizeof(limits))
            result = kIOReturnBadArgument;
        else if ((kSwifterKitEthernetFeatureFlags & kIOUserNetworkFeatureFlagNicProxy) == 0)
            result = kIOReturnUnsupported;
        else {
            memcpy(&limits, payload, sizeof(limits));
            result = reportNicProxyLimits(limits);
        }
    }
    IOLockUnlock(ivars->networkLock);
    // The poller may call back into the network queue, so it hears of the frame unlocked.
    if (poller != nullptr) {
        (void)poller->updatePacketCounters(1, receivedLength);
        poller->release();
    }
    return result;
}

// enable() and disable() wait for a running poll, which takes networkLock, so the poller is
// retained under the lock and driven after it is dropped.
kern_return_t SwifterKitRuntimeService::NetworkPollerCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength) {
    IOLockLock(ivars->networkLock);
    IOUserNetworkPacketPoller* poller = ivars->networkStopping ? nullptr : ivars->networkPoller;
    kern_return_t result = ivars->networkStopping ? kIOReturnNotReady : kIOReturnUnsupported;
    if (poller != nullptr)
        poller->retain();
    IOLockUnlock(ivars->networkLock);
    if (poller == nullptr)
        return result;
    result = kIOReturnBadArgument;
    if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::NetworkSetPolling)) {
        uint32_t enabled = 2;
        if (payloadLength == sizeof(enabled))
            memcpy(&enabled, payload, sizeof(enabled));
        if (enabled <= 1) {
            if (enabled == 1)
                poller->enable();
            else
                poller->disable();
            result = kIOReturnSuccess;
        }
    } else if (payloadLength == sizeof(SwifterKitNetworkPollerParameters)) {
        const auto* input = reinterpret_cast<const SwifterKitNetworkPollerParameters*>(payload);
        if (input->dataRate != 0 && input->pollInterval <= kSwifterKitEthernetMaximumPollInterval) {
            IOUserNetworkPacketPollerParameters parameters = {};
            parameters.dataRate = input->dataRate;
            parameters.pollInterval = input->pollInterval;
            result = poller->setPollerParameters(&parameters);
        }
    }
    poller->release();
    return result;
}
#endif
