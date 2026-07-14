#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"
#if SWIFTERKIT_ENABLE_NETWORKING
    #include <DriverKit/IODataQueueDispatchSource.h>
    #include <DriverKit/IOLib.h>
    #include <NetworkingDriverKit/NetworkingDriverKit.h>
    #include <net/ethernet.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

kern_return_t SwifterKitRuntimeService::StartNetwork() {
    if (ivars == nullptr || ivars->networkPool != nullptr)
        return kIOReturnNotReady;
    kern_return_t result = CopyDispatchQueue("Default", &ivars->networkQueue);
    IODataQueueDispatchSource* dataQueue = nullptr;
    IOUserNetworkPacketBufferPoolOptions options = {};
    options.packetCount = kSwifterKitEthernetPacketCount;
    options.bufferCount = kSwifterKitEthernetPacketCount;
    options.bufferSize = kSwifterKitEthernetPacketBufferSize;
    options.maxBuffersPerPacket = 1;
    options.poolFlags = PoolFlagMapToDext;
    options.dmaSpecification.maxAddressBits = 64;
    if (result == kIOReturnSuccess)
        result = IOUserNetworkPacketBufferPool::CreateWithOptions(
            this,
            "SwifterKitEthernet",
            &options,
            &ivars->networkPool);
    if (result == kIOReturnSuccess)
        result = CreateActionNetworkTxPacketAvailable(0, &ivars->networkTxAction);
    if (result == kIOReturnSuccess)
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
            ivars->networkPool,
            this,
            kSwifterKitEthernetQueueCapacity,
            0,
            ivars->networkQueue,
            &ivars->networkRxSubmission);
    if (result == kIOReturnSuccess)
        result = IOUserNetworkRxCompletionQueue::Create(
            ivars->networkPool,
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
    ether_addr_t address = {};
    for (uint32_t index = 0; index < 6; ++index) {
        address.octet[index] = kSwifterKitEthernetAddress[index];
        ivars->networkAddress[index] = address.octet[index];
    }
    IOUserNetworkPacketQueue* queues[] = {
        ivars->networkTxSubmission,
        ivars->networkTxCompletion,
        ivars->networkRxSubmission,
        ivars->networkRxCompletion};
    if (result == kIOReturnSuccess)
        result = RegisterEthernetInterface(address, ivars->networkPool, queues, 4);
    OSSafeReleaseNULL(dataQueue);
    if (result != kIOReturnSuccess)
        StopNetwork();
    return result;
}

void SwifterKitRuntimeService::StopNetwork() {
    if (ivars == nullptr)
        return;
    if (ivars->networkLock != nullptr) {
        IOLockLock(ivars->networkLock);
        ivars->networkStopping = true;
        if (ivars->networkTxCompletion != nullptr)
            (void)ivars->networkTxCompletion->setEnable(false);
        if (ivars->networkTxSubmission != nullptr)
            (void)ivars->networkTxSubmission->setEnable(false);
        if (ivars->networkRxCompletion != nullptr)
            (void)ivars->networkRxCompletion->setEnable(false);
        if (ivars->networkRxSubmission != nullptr)
            (void)ivars->networkRxSubmission->setEnable(false);
        for (auto& pending : ivars->networkTransmits) {
            if (pending.packet != nullptr) {
                (void)ivars->networkPool->deallocatePacket(pending.packet);
                OSSafeReleaseNULL(pending.packet);
                pending.requestID = 0;
            }
        }
        IOLockUnlock(ivars->networkLock);
    }
    OSSafeReleaseNULL(ivars->networkTxAction);
    OSSafeReleaseNULL(ivars->networkRxCompletion);
    OSSafeReleaseNULL(ivars->networkRxSubmission);
    OSSafeReleaseNULL(ivars->networkTxCompletion);
    OSSafeReleaseNULL(ivars->networkTxSubmission);
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
        0x0900,
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
    return mtu <= kSwifterKitEthernetMTU ? NetworkControlEvent(7, mtu) : kIOReturnBadArgument;
}
uint32_t SwifterKitRuntimeService::getMaxTransferUnit() {
    return kSwifterKitEthernetMTU;
}
kern_return_t SwifterKitRuntimeService::setHardwareAssists(uint32_t assists) {
    return (assists & ~kSwifterKitEthernetHardwareAssists) == 0 ? NetworkControlEvent(8, assists)
                                                                : kIOReturnUnsupported;
}
uint32_t SwifterKitRuntimeService::getHardwareAssists() {
    return kSwifterKitEthernetHardwareAssists;
}

MediaWord SwifterKitRuntimeService::getInitialMedia() {
    return kSwifterKitEthernetInitialMedia;
}
kern_return_t SwifterKitRuntimeService::handleChosenMedia(MediaWord media) {
    return NetworkControlEvent(9, media);
}
kern_return_t SwifterKitRuntimeService::setPowerState(unsigned long state, IOService* device) {
    kern_return_t result = NetworkControlEvent(10, static_cast<uint32_t>(state));
    return result == kIOReturnSuccess ? super::setPowerState(state, device) : result;
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
