#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"
#if SWIFTERKIT_ENABLE_NETWORKING
    #include <DriverKit/IODataQueueDispatchSource.h>
    #include <DriverKit/IOLib.h>
    #include <NetworkingDriverKit/IOUserNetworkPacketPoller.h>
    #include <NetworkingDriverKit/NetworkingDriverKit.h>
    #include <net/ethernet.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    // Wake-on-magic-packet support is advertised as an assist so the stack can toggle it.
    constexpr uint32_t kAdvertisedHardwareAssists =
        kSwifterKitEthernetHardwareAssists
        | (kSwifterKitEthernetWakeOnMagicPacket ? kIOUserNetworkHWAssistWOMP : 0U);
    constexpr uint32_t kPendingTransmitCapacity =
        sizeof(SwifterKitRuntimeService_IVars::networkTransmits)
        / sizeof(SwifterKitNetworkPendingTransmit);

    // The caller holds networkLock. Pending packets go back to the pool in one batch.
    void ReturnPendingTransmits(SwifterKitRuntimeService_IVars* state) {
        if (state->networkPool == nullptr)
            return;
        IOUserNetworkPacket* packets[kPendingTransmitCapacity] = {};
        uint32_t count = 0;
        for (auto& pending : state->networkTransmits) {
            if (pending.packet != nullptr) {
                packets[count++] = pending.packet;
                pending = {};
            }
        }
        if (count != 0)
            (void)state->networkPool->deallocatePackets(packets, count);
        for (uint32_t index = 0; index < count; ++index)
            packets[index]->release();
    }

    // Creates one pool and confirms the family sized it as configured.
    kern_return_t CreateNetworkPool(
        IOService* owner,
        const char* name,
        uint32_t packetCount,
        IOUserNetworkPacketBufferPool** pool) {
        IOUserNetworkPacketBufferPoolOptions options = {};
        options.packetCount = packetCount;
        options.bufferCount =
            kSwifterKitEthernetBufferCount == 0 ? packetCount : kSwifterKitEthernetBufferCount;
        options.bufferSize = kSwifterKitEthernetPacketBufferSize;
        options.maxBuffersPerPacket = 1;
        options.memorySegmentSize = kSwifterKitEthernetMemorySegmentSize;
        options.poolFlags = kSwifterKitEthernetPoolFlags | PoolFlagMapToDext;
        options.dmaSpecification.maxAddressBits = kSwifterKitEthernetDMAAddressBits;
        kern_return_t result =
            IOUserNetworkPacketBufferPool::CreateWithOptions(owner, name, &options, pool);
        uint32_t count = 0;
        if (result == kIOReturnSuccess)
            result = (*pool)->GetPacketCount(&count);
        if (result == kIOReturnSuccess && count < options.packetCount)
            result = kIOReturnNoResources;
        if (result == kIOReturnSuccess)
            result = (*pool)->GetBufferCount(&count);
        if (result == kIOReturnSuccess && count < options.bufferCount)
            result = kIOReturnNoResources;
        return result;
    }

    // Each poll tick drains transmit work; the poller runs on the network queue.
    IOReturn NetworkPoll(OSObject* target, IOUserNetworkPacketPoller*, void*) {
        auto* service = OSDynamicCast(SwifterKitRuntimeService, target);
        if (service != nullptr)
            service->DrainNetworkTransmits();
        return kIOReturnSuccess;
    }

    IOReturn NetworkPollerEvent(
        OSObject* target,
        IOUserNetworkPacketPoller*,
        IOOptionBits event,
        void*) {
        auto* service = OSDynamicCast(SwifterKitRuntimeService, target);
        const uint32_t type = event & kIOUserNetworkPacketPollerEventTypeMask;
        if (service != nullptr
            && (type == kIOUserNetworkPacketPollerEventPollStart
                || type == kIOUserNetworkPacketPollerEventPollStop))
            (void)service->NetworkControlEvent(
                13,
                type == kIOUserNetworkPacketPollerEventPollStart ? 1 : 0);
        return kIOReturnSuccess;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartNetwork() {
    if (ivars == nullptr || ivars->networkPool != nullptr)
        return kIOReturnNotReady;
    kern_return_t result = CopyDispatchQueue("Default", &ivars->networkQueue);
    IODataQueueDispatchSource* dataQueue = nullptr;
    if (result == kIOReturnSuccess)
        result = CreateNetworkPool(
            this,
            "SwifterKitEthernet",
            kSwifterKitEthernetPacketCount,
            &ivars->networkPool);
    if (result == kIOReturnSuccess && kSwifterKitEthernetRxPacketCount != 0)
        result = CreateNetworkPool(
            this,
            "SwifterKitEthernetRx",
            kSwifterKitEthernetRxPacketCount,
            &ivars->networkRxPool);
    else if (result == kIOReturnSuccess) {
        ivars->networkRxPool = ivars->networkPool;
        ivars->networkRxPool->retain();
    }
    if (result == kIOReturnSuccess)
        result = CreateActionNetworkTxPacketAvailable(0, &ivars->networkTxAction);
    // A transmit service class needs the DriverKit 24 Create; earlier systems use the plain one.
    bool classified = false;
    if (result == kIOReturnSuccess
        && kSwifterKitEthernetTxServiceClass != kIOUserNetworkPacketServiceClassNone) {
        if (__builtin_available(driverkit 24.0, *)) {
            classified = true;
            result = IOUserNetworkTxSubmissionQueue::Create(
                ivars->networkPool,
                this,
                kSwifterKitEthernetTxServiceClass,
                kSwifterKitEthernetQueueCapacity,
                0,
                ivars->networkQueue,
                &ivars->networkTxSubmission);
        }
    }
    if (result == kIOReturnSuccess && !classified)
        result = IOUserNetworkTxSubmissionQueue::Create(
            ivars->networkPool,
            this,
            kSwifterKitEthernetQueueCapacity,
            0,
            ivars->networkQueue,
            &ivars->networkTxSubmission);
    if (result == kIOReturnSuccess)
        result = IOUserNetworkTxCompletionQueue::Create(
            ivars->networkPool,
            this,
            kSwifterKitEthernetQueueCapacity,
            0,
            ivars->networkQueue,
            &ivars->networkTxCompletion);
    if (result == kIOReturnSuccess)
        result = IOUserNetworkRxSubmissionQueue::Create(
            ivars->networkRxPool,
            this,
            kSwifterKitEthernetQueueCapacity,
            0,
            ivars->networkQueue,
            &ivars->networkRxSubmission);
    if (result == kIOReturnSuccess)
        result = IOUserNetworkRxCompletionQueue::Create(
            ivars->networkRxPool,
            this,
            kSwifterKitEthernetQueueCapacity,
            0,
            ivars->networkQueue,
            &ivars->networkRxCompletion);
    if (result == kIOReturnSuccess)
        result = ivars->networkTxSubmission->CopyDataQueue(&dataQueue);
    if (result == kIOReturnSuccess)
        result = dataQueue->SetDataAvailableHandler(ivars->networkTxAction);
    if (result == kIOReturnSuccess)
        result = SetWakeOnMagicPacketSupport(kSwifterKitEthernetWakeOnMagicPacket);
    if (result == kIOReturnSuccess && kSwifterKitEthernetSoftwareVLAN)
        result = SetSoftwareVlanSupport(true);
    if (result == kIOReturnSuccess && kSwifterKitEthernetTxHeadroom != 0)
        result = SetTxPacketHeadroom(kSwifterKitEthernetTxHeadroom);
    if (result == kIOReturnSuccess && kSwifterKitEthernetTxTailroom != 0)
        result = SetTxPacketTailroom(kSwifterKitEthernetTxTailroom);
    if (result == kIOReturnSuccess && kSwifterKitEthernetPolling) {
        ivars->networkPoller = IOUserNetworkPacketPoller::poller(
            this,
            ivars->networkQueue,
            NetworkPoll,
            NetworkPollerEvent);
        IOUserNetworkPacketPollerParameters parameters = {};
        parameters.dataRate = kSwifterKitEthernetPollDataRate;
        parameters.pollInterval = kSwifterKitEthernetPollInterval;
        result = ivars->networkPoller == nullptr
                     ? kIOReturnNoMemory
                     : ivars->networkPoller->setPollerParameters(&parameters);
    }
    for (uint32_t index = 0; index < 6; ++index)
        ivars->networkAddress[index] = kSwifterKitEthernetAddress[index];
    IOUserNetworkPacketQueue* queues[] = {
        ivars->networkTxSubmission,
        ivars->networkTxCompletion,
        ivars->networkRxSubmission,
        ivars->networkRxCompletion};
    // The family reads the address back through getHardwareAddress.
    if (result == kIOReturnSuccess)
        result = registerEthernetInterface(queues, 4, ivars->networkPool, ivars->networkRxPool);
    if (result == kIOReturnSuccess && kSwifterKitEthernetPacketTap)
        result = bpfAttach(kSwifterKitEthernetDataLinkType, kSwifterKitEthernetHeaderLength);
    if (result == kIOReturnSuccess && kSwifterKitEthernetPolling
        && kSwifterKitEthernetPollingEnabled)
        ivars->networkPoller->enable();
    OSSafeReleaseNULL(dataQueue);
    if (result != kIOReturnSuccess)
        StopNetwork();
    return result;
}

// Returns transmits Swift has not completed to the pool, the same outcome as a
// failed completion. The host that received them is gone.
void SwifterKitRuntimeService::AbortNetworkTransmits() {
    if (ivars == nullptr || ivars->networkLock == nullptr)
        return;
    IOLockLock(ivars->networkLock);
    ReturnPendingTransmits(ivars);
    IOLockUnlock(ivars->networkLock);
}

void SwifterKitRuntimeService::StopNetwork() {
    if (ivars == nullptr)
        return;
    // disable() waits for a running poll, which takes networkLock, so it runs unlocked.
    if (ivars->networkLock != nullptr) {
        IOLockLock(ivars->networkLock);
        ivars->networkStopping = true;
        IOLockUnlock(ivars->networkLock);
    }
    if (ivars->networkPoller != nullptr)
        ivars->networkPoller->disable();
    if (ivars->networkLock != nullptr) {
        IOLockLock(ivars->networkLock);
        if (ivars->networkTxCompletion != nullptr)
            (void)ivars->networkTxCompletion->setEnable(false);
        if (ivars->networkTxSubmission != nullptr)
            (void)ivars->networkTxSubmission->setEnable(false);
        if (ivars->networkRxCompletion != nullptr)
            (void)ivars->networkRxCompletion->setEnable(false);
        if (ivars->networkRxSubmission != nullptr)
            (void)ivars->networkRxSubmission->setEnable(false);
        ReturnPendingTransmits(ivars);
        IOLockUnlock(ivars->networkLock);
    }
    OSSafeReleaseNULL(ivars->networkTxAction);
    OSSafeReleaseNULL(ivars->networkRxCompletion);
    OSSafeReleaseNULL(ivars->networkRxSubmission);
    OSSafeReleaseNULL(ivars->networkTxCompletion);
    OSSafeReleaseNULL(ivars->networkTxSubmission);
    OSSafeReleaseNULL(ivars->networkPoller);
    OSSafeReleaseNULL(ivars->networkRxPool);
    OSSafeReleaseNULL(ivars->networkPool);
    OSSafeReleaseNULL(ivars->networkQueue);
}

kern_return_t SwifterKitRuntimeService::NetworkControlEvent(
    uint32_t kind,
    uint32_t value,
    const void* bytes,
    uint32_t byteCount) {
    if (byteCount != 0 && bytes == nullptr)
        return kIOReturnBadArgument;
    const SwifterKitNetworkEventHeader header = {kind, 0, value, byteCount};
    OSData* event = OSData::withCapacity(sizeof(header) + byteCount);
    if (event == nullptr || !event->appendBytes(&header, sizeof(header))
        || (byteCount != 0 && !event->appendBytes(bytes, byteCount))) {
        OSSafeReleaseNULL(event);
        return kIOReturnNoMemory;
    }
    const kern_return_t result = EnqueueRequiredEvent(
        kSwifterKitEventNetwork,
        event->getBytesNoCopy(),
        static_cast<uint32_t>(event->getLength()));
    event->release();
    return result;
}

kern_return_t SwifterKitRuntimeService::getSupportedMediaArray(MediaWord* media, uint32_t* count) {
    if (media == nullptr || count == nullptr)
        return kIOReturnBadArgument;
    memcpy(media, kSwifterKitEthernetMedia, sizeof(uint32_t) * kSwifterKitEthernetMediaCount);
    *count = kSwifterKitEthernetMediaCount;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::setInterfaceEnable(bool enable) {
    if (ivars == nullptr || ivars->networkLock == nullptr)
        return kIOReturnNotReady;
    IOLockLock(ivars->networkLock);
    if (ivars->networkStopping || ivars->networkTxSubmission == nullptr
        || ivars->networkTxCompletion == nullptr || ivars->networkRxSubmission == nullptr
        || ivars->networkRxCompletion == nullptr) {
        IOLockUnlock(ivars->networkLock);
        return kIOReturnNotReady;
    }
    kern_return_t result = kIOReturnSuccess;
    if (enable) {
        result = ivars->networkTxCompletion->setEnable(true);
        if (result == kIOReturnSuccess)
            result = ivars->networkTxSubmission->setEnable(true);
        if (result == kIOReturnSuccess)
            result = ivars->networkRxCompletion->setEnable(true);
        if (result == kIOReturnSuccess)
            result = ivars->networkRxSubmission->setEnable(true);
        if (result == kIOReturnSuccess)
            result = NetworkControlEvent(1, 1);
        if (result != kIOReturnSuccess) {
            (void)ivars->networkTxCompletion->setEnable(false);
            (void)ivars->networkTxSubmission->setEnable(false);
            (void)ivars->networkRxCompletion->setEnable(false);
            (void)ivars->networkRxSubmission->setEnable(false);
        }
    } else {
        kern_return_t current = ivars->networkTxCompletion->setEnable(false);
        if (result == kIOReturnSuccess)
            result = current;
        current = ivars->networkTxSubmission->setEnable(false);
        if (result == kIOReturnSuccess)
            result = current;
        current = ivars->networkRxCompletion->setEnable(false);
        if (result == kIOReturnSuccess)
            result = current;
        current = ivars->networkRxSubmission->setEnable(false);
        if (result == kIOReturnSuccess)
            result = current;
        current = NetworkControlEvent(1, 0);
        if (result == kIOReturnSuccess)
            result = current;
    }
    ivars->networkEnabled = result == kIOReturnSuccess && enable;
    IOLockUnlock(ivars->networkLock);
    return result;
}

kern_return_t SwifterKitRuntimeService::setPromiscuousModeEnable(bool enable) {
    return NetworkControlEvent(3, enable ? 1 : 0);
}
kern_return_t SwifterKitRuntimeService::setMulticastAddresses(
    const ether_addr_t* addresses,
    uint32_t count) {
    if (count > 1024 || (count != 0 && addresses == nullptr))
        return kIOReturnBadArgument;
    return NetworkControlEvent(4, count, addresses, count * sizeof(*addresses));
}
kern_return_t SwifterKitRuntimeService::setAllMulticastModeEnable(bool enable) {
    return NetworkControlEvent(5, enable ? 1 : 0);
}
kern_return_t SwifterKitRuntimeService::setMaxTransferUnit(uint32_t mtu) {
    return mtu >= kSwifterKitEthernetMinimumMTU && mtu <= kSwifterKitEthernetMTU
               ? NetworkControlEvent(7, mtu)
               : kIOReturnBadArgument;
}
uint32_t SwifterKitRuntimeService::getMaxTransferUnit() {
    return kSwifterKitEthernetMTU;
}
kern_return_t SwifterKitRuntimeService::setHardwareAssists(uint32_t assists) {
    return (assists & ~kAdvertisedHardwareAssists) == 0 ? NetworkControlEvent(8, assists)
                                                        : kIOReturnUnsupported;
}
uint32_t SwifterKitRuntimeService::getHardwareAssists() {
    return kAdvertisedHardwareAssists;
}
// The stack changes the assists in mask; Swift sees only those bits. A wake-on-magic-packet
// change is also delivered as its own event.
kern_return_t SwifterKitRuntimeService::setHardwareAssists(uint32_t assists, uint32_t mask) {
    if ((mask & ~kAdvertisedHardwareAssists) != 0)
        return kIOReturnUnsupported;
    const uint32_t changed = assists & mask;
    kern_return_t result = NetworkControlEvent(12, changed, &mask, sizeof(mask));
    if (result == kIOReturnSuccess && (mask & kIOUserNetworkHWAssistWOMP) != 0)
        result = NetworkControlEvent(6, (changed & kIOUserNetworkHWAssistWOMP) != 0 ? 1 : 0);
    return result;
}
uint32_t SwifterKitRuntimeService::getFeatureFlags() {
    return super::getFeatureFlags() | kSwifterKitEthernetFeatureFlags;
}
kern_return_t SwifterKitRuntimeService::getTSOOptions(IOUserNetworkTSOOptions* options) {
    if (options == nullptr)
        return kIOReturnBadArgument;
    if constexpr (kSwifterKitEthernetTSOMSS4 == 0 && kSwifterKitEthernetTSOMSS6 == 0)
        return kIOReturnUnsupported;
    else {
        *options = {};
        options->mss4 = kSwifterKitEthernetTSOMSS4;
        options->mss6 = kSwifterKitEthernetTSOMSS6;
        return kIOReturnSuccess;
    }
}
uint32_t SwifterKitRuntimeService::getInterfaceSubFamily() {
    if constexpr (kSwifterKitEthernetSubFamily != 0)
        return kSwifterKitEthernetSubFamily;
    else
        return super::getInterfaceSubFamily();
}
const char* SwifterKitRuntimeService::getBSDNamePrefix() {
    if constexpr (kSwifterKitEthernetBSDNamePrefix[0] != '\0')
        return kSwifterKitEthernetBSDNamePrefix;
    else
        return super::getBSDNamePrefix();
}
int32_t SwifterKitRuntimeService::getBSDUnitNumber() {
    if constexpr (kSwifterKitEthernetBSDUnitNumber >= 0)
        return kSwifterKitEthernetBSDUnitNumber;
    else
        return super::getBSDUnitNumber();
}
uint16_t SwifterKitRuntimeService::getTxDataOffset() {
    return kSwifterKitEthernetTxDataOffset;
}
// The tap mode gates bpfTapInputPacket and bpfTapOutputPacket in the packet paths.
int SwifterKitRuntimeService::bpfTap(uint32_t dataLinkType, uint32_t mode) {
    if (ivars == nullptr || ivars->networkLock == nullptr
        || dataLinkType != kSwifterKitEthernetDataLinkType)
        return 0;
    const uint32_t tapMode = mode & (kSwifterKitEthernetTapInput | kSwifterKitEthernetTapOutput);
    IOLockLock(ivars->networkLock);
    ivars->networkTapMode = tapMode;
    IOLockUnlock(ivars->networkLock);
    (void)NetworkControlEvent(14, tapMode);
    return 0;
}
// The handoff is one nicproxy_info_t whose len covers its record buffer; one event carries it.
void SwifterKitRuntimeService::hwConfigNicProxyData(nicproxy_info_t* handoff) {
    if (handoff == nullptr || handoff->len < sizeof(nicproxy_info_t)
        || handoff->len
               > kSwifterKitMaximumEventPayloadLength - sizeof(SwifterKitNetworkEventHeader))
        return;
    (void)NetworkControlEvent(15, handoff->len, handoff, handoff->len);
}

MediaWord SwifterKitRuntimeService::getInitialMedia() {
    return kSwifterKitEthernetInitialMedia;
}
kern_return_t SwifterKitRuntimeService::handleChosenMedia(MediaWord media) {
    return NetworkControlEvent(9, media);
}
// The family reaches this from SetPowerState, which SwifterKitRuntimeServicePower acknowledges
// through super once Swift answers. The Swift notification is best effort: super always runs,
// exactly once, and its result is returned, so a full event queue never stalls the transition.
kern_return_t SwifterKitRuntimeService::setPowerState(unsigned long state, IOService* device) {
    (void)NetworkControlEvent(10, static_cast<uint32_t>(state));
    return super::setPowerState(state, device);
}
kern_return_t SwifterKitRuntimeService::getHardwareAddress(ether_addr_t* address) {
    if (address == nullptr || ivars == nullptr || ivars->networkLock == nullptr)
        return kIOReturnBadArgument;
    IOLockLock(ivars->networkLock);
    const kern_return_t result = ivars->networkStopping ? kIOReturnNotReady : kIOReturnSuccess;
    if (result == kIOReturnSuccess)
        memcpy(address->octet, ivars->networkAddress, 6);
    IOLockUnlock(ivars->networkLock);
    return result;
}
kern_return_t SwifterKitRuntimeService::setHardwareAddress(ether_addr_t* address) {
    if (address == nullptr || (address->octet[0] & 1) != 0 || ivars == nullptr
        || ivars->networkLock == nullptr)
        return kIOReturnBadArgument;
    IOLockLock(ivars->networkLock);
    kern_return_t result =
        ivars->networkStopping ? kIOReturnNotReady : NetworkControlEvent(11, 1, address->octet, 6);
    if (result == kIOReturnSuccess)
        memcpy(ivars->networkAddress, address->octet, 6);
    IOLockUnlock(ivars->networkLock);
    return result;
}
#endif
