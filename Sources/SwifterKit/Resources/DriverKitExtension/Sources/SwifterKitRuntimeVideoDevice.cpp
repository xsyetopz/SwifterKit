#include "SwifterKitRuntimeVideoDevice.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSArray.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeMappedMemory.h"
    #include "SwifterKitRuntimeMediaMembers.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeVideoDeviceState.h"
    #include "SwifterKitRuntimeVideoStream.h"

namespace {
    constexpr uint64_t kSampleRateChangeAction = 0x53574B564944454FULL;

    // The schema values SwifterKitApplyStructureChange in SwifterKitRuntimeMediaMembers.h reads.
    struct VideoStructureFamily {
        static constexpr uint32_t kChangeStreamAttachment = kSwifterKitVideoChangeStreamAttachment;
        static constexpr uint32_t kChangeInputSafetyOffset =
            kSwifterKitVideoChangeInputSafetyOffset;
        static constexpr uint32_t kChangeOutputSafetyOffset =
            kSwifterKitVideoChangeOutputSafetyOffset;
        static constexpr uint32_t kStreamCount = kSwifterKitVideoStreamCount;
    };

    IOUserVideoStreamBasicDescription NativeFormat(
        const SwifterKitVideoFormatConfiguration& format) {
        return {
            format.frameRate,
            format.frameTimeValue,
            format.frameTimeScale,
            static_cast<IOUserVideoFormatID>(format.codec),
            format.codecFlags,
            format.width,
            format.height,
            0,
            0};
    }

    bool IsSupportedSampleRate(double sampleRate) {
        // A count of zero still renders a one-element array, so iterate by the generated count.
        // NOLINTNEXTLINE(modernize-loop-convert)
        for (uint32_t index = 0; index < kSwifterKitVideoSampleRateCount; ++index)
            if (kSwifterKitVideoSampleRates[index] == sampleRate)
                return true;
        return false;
    }

    bool IsValidRange(uint32_t offset, uint32_t length, uint64_t capacity) {
        return length > 0 && offset <= capacity && length <= capacity - offset;
    }
}  // namespace

bool SwifterKitRuntimeVideoDevice::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    OSString* deviceUID,
    OSString* modelUID,
    OSString* manufacturerUID) {
    if (driver == nullptr || service == nullptr
        || !super::init(driver, deviceUID, modelUID, manufacturerUID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoDevice_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->bufferLock = IOLockAlloc();
    if (ivars->bufferLock == nullptr)
        return false;
    ivars->service = service;
    service->retain();
    return true;
}

void SwifterKitRuntimeVideoDevice::free() {
    if (ivars != nullptr) {
        for (uint32_t stream = 0; stream < kSwifterKitVideoStreamCount; ++stream) {
            OSSafeReleaseNULL(ivars->streams[stream]);
            for (uint32_t buffer = 0; buffer < kSwifterKitVideoStreams[stream].bufferCount;
                 ++buffer) {
                OSSafeReleaseNULL(ivars->buffers[stream][buffer]);
                OSSafeReleaseNULL(ivars->dataMaps[stream][buffer]);
                OSSafeReleaseNULL(ivars->controlMaps[stream][buffer]);
                OSSafeReleaseNULL(ivars->dataDescriptors[stream][buffer]);
                OSSafeReleaseNULL(ivars->controlDescriptors[stream][buffer]);
            }
        }
        for (uint32_t index = 0; index < kSwifterKitVideoControlCount; ++index)
            OSSafeReleaseNULL(ivars->controls[index]);
        for (uint32_t index = 0; index < kSwifterKitVideoCustomPropertyCount; ++index)
            OSSafeReleaseNULL(ivars->customProperties[index]);
        OSSafeReleaseNULL(ivars->service);
        if (ivars->bufferLock != nullptr)
            IOLockFree(ivars->bufferLock);
    }
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoDevice_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoDevice::Configure() {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    OSString* name = OSString::withCString(kSwifterKitVideoDeviceName);
    kern_return_t result = name == nullptr ? kIOReturnNoMemory : SetName(name);
    OSSafeReleaseNULL(name);
    if (result == kIOReturnSuccess)
        result = SetTransportType(static_cast<IOUserVideoTransportType>(kSwifterKitVideoTransport));
    if (result == kIOReturnSuccess)
        result =
            SetAvailableSampleRates(kSwifterKitVideoSampleRates, kSwifterKitVideoSampleRateCount);
    if (result == kIOReturnSuccess)
        result = SetSampleRate(kSwifterKitVideoInitialSampleRate);

    for (uint32_t streamIndex = 0;
         result == kIOReturnSuccess && streamIndex < kSwifterKitVideoStreamCount;
         ++streamIndex) {
        const auto& config = kSwifterKitVideoStreams[streamIndex];
        ivars->dataCapacity[streamIndex] = config.dataBufferCapacity;
        ivars->controlCapacity[streamIndex] = config.controlBufferCapacity;
        for (uint32_t bufferIndex = 0; bufferIndex < config.bufferCount; ++bufferIndex)
            ivars->bufferIDs[streamIndex][bufferIndex] = bufferIndex;
        OSArray* bufferList = OSArray::withCapacity(config.bufferCount);
        result = bufferList == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        for (uint32_t bufferIndex = 0;
             result == kIOReturnSuccess && bufferIndex < config.bufferCount;
             ++bufferIndex) {
            result = IOBufferMemoryDescriptor::Create(
                kIOMemoryDirectionInOut,
                config.dataBufferCapacity,
                0,
                &ivars->dataDescriptors[streamIndex][bufferIndex]);
            if (result == kIOReturnSuccess)
                result = IOBufferMemoryDescriptor::Create(
                    kIOMemoryDirectionInOut,
                    config.controlBufferCapacity,
                    0,
                    &ivars->controlDescriptors[streamIndex][bufferIndex]);
            if (result == kIOReturnSuccess)
                result = ivars->dataDescriptors[streamIndex][bufferIndex]->CreateMapping(
                    0,
                    0,
                    0,
                    config.dataBufferCapacity,
                    0,
                    &ivars->dataMaps[streamIndex][bufferIndex]);
            if (result == kIOReturnSuccess)
                result = ivars->controlDescriptors[streamIndex][bufferIndex]->CreateMapping(
                    0,
                    0,
                    0,
                    config.controlBufferCapacity,
                    0,
                    &ivars->controlMaps[streamIndex][bufferIndex]);
            if (result == kIOReturnSuccess) {
                ivars->buffers[streamIndex][bufferIndex] =
                    IOUserVideoBuffer::Create(
                        ivars->service,
                        static_cast<IOUserVideoStreamDirection>(config.direction),
                        ivars->dataDescriptors[streamIndex][bufferIndex],
                        ivars->controlDescriptors[streamIndex][bufferIndex],
                        bufferIndex)
                        .detach();
                result = ivars->buffers[streamIndex][bufferIndex] != nullptr
                                 && bufferList->setObject(ivars->buffers[streamIndex][bufferIndex])
                             ? kIOReturnSuccess
                             : kIOReturnNoMemory;
            }
        }

        OSString* identifier =
            result == kIOReturnSuccess ? OSString::withCString(config.identifier) : nullptr;
        if (result == kIOReturnSuccess) {
            auto* stream = OSTypeAlloc(SwifterKitRuntimeVideoStream);
            if (stream != nullptr
                && !stream->init(
                    ivars->service,
                    ivars->service,
                    streamIndex,
                    identifier,
                    static_cast<IOUserVideoStreamDirection>(config.direction),
                    bufferList))
                OSSafeReleaseNULL(stream);
            ivars->streams[streamIndex] = stream;
            result = stream == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
        OSSafeReleaseNULL(identifier);
        OSSafeReleaseNULL(bufferList);

        IOUserVideoStreamBasicDescription formats[kSwifterKitVideoMaximumStreamFormats];
        for (uint32_t formatIndex = 0; formatIndex < config.formatCount; ++formatIndex)
            formats[formatIndex] =
                NativeFormat(kSwifterKitVideoFormats[config.formatStart + formatIndex]);
        if (result == kIOReturnSuccess)
            result =
                ivars->streams[streamIndex]->SetAvailableStreamFormats(formats, config.formatCount);
        if (result == kIOReturnSuccess)
            result = ivars->streams[streamIndex]->SetCurrentStreamFormat(
                &formats[config.initialFormatIndex]);
        if (result == kIOReturnSuccess)
            result = AddStream(ivars->streams[streamIndex]);
    }
    if (result == kIOReturnSuccess)
        result = ConfigureControls();
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::ReadBuffer(
    const SwifterKitVideoTransferHeader* transfer,
    OSData** response) {
    if (transfer == nullptr || response == nullptr
        || transfer->length > kSwifterKitVideoMaximumReadLength
        || transfer->streamIndex >= kSwifterKitVideoStreamCount)
        return kIOReturnBadArgument;
    const auto& config = kSwifterKitVideoStreams[transfer->streamIndex];
    if (transfer->bufferIndex >= config.bufferCount
        || transfer->plane > kSwifterKitVideoPlaneControl)
        return kIOReturnBadArgument;
    // A buffer-capacity change swaps the maps under bufferLock.
    IOLockLock(ivars->bufferLock);
    IOMemoryMap* map = transfer->plane == kSwifterKitVideoPlaneData
                           ? ivars->dataMaps[transfer->streamIndex][transfer->bufferIndex]
                           : ivars->controlMaps[transfer->streamIndex][transfer->bufferIndex];
    kern_return_t result = kIOReturnBadArgument;
    if (map != nullptr && map->GetAddress() != 0
        && IsValidRange(transfer->byteOffset, transfer->length, map->GetLength())) {
        *response = OSData::withBytes(
            SwifterKitMappedPointer<const uint8_t>(map->GetAddress() + map->GetOffset())
                + transfer->byteOffset,
            transfer->length);
        result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }
    IOLockUnlock(ivars->bufferLock);
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::WriteBuffer(
    const SwifterKitVideoTransferHeader* transfer,
    const uint8_t* bytes) {
    if (transfer == nullptr || bytes == nullptr
        || transfer->length > kSwifterKitVideoMaximumWriteLength
        || transfer->streamIndex >= kSwifterKitVideoStreamCount)
        return kIOReturnBadArgument;
    const auto& config = kSwifterKitVideoStreams[transfer->streamIndex];
    if (transfer->bufferIndex >= config.bufferCount
        || transfer->plane > kSwifterKitVideoPlaneControl)
        return kIOReturnBadArgument;
    IOLockLock(ivars->bufferLock);
    IOMemoryMap* map = transfer->plane == kSwifterKitVideoPlaneData
                           ? ivars->dataMaps[transfer->streamIndex][transfer->bufferIndex]
                           : ivars->controlMaps[transfer->streamIndex][transfer->bufferIndex];
    const bool valid = map != nullptr && map->GetAddress() != 0
                       && IsValidRange(transfer->byteOffset, transfer->length, map->GetLength());
    if (valid)
        memcpy(
            SwifterKitMappedPointer(map->GetAddress() + map->GetOffset()) + transfer->byteOffset,
            bytes,
            transfer->length);
    IOLockUnlock(ivars->bufferLock);
    return valid ? kIOReturnSuccess : kIOReturnBadArgument;
}

kern_return_t SwifterKitRuntimeVideoDevice::EnqueueOutput(
    uint32_t streamIndex,
    const SwifterKitVideoQueueEntry* entry) {
    IOStreamBufferQueueEntry native = {};
    const kern_return_t result = NativeEntry(streamIndex, entry, &native);
    return result == kIOReturnSuccess ? ivars->streams[streamIndex]->enqueueOutputEntry(&native)
                                      : result;
}

// Validates an output entry against the live buffer sizes and translates its buffer index into
// the buffer's current IOStreamBufferID.
kern_return_t SwifterKitRuntimeVideoDevice::NativeEntry(
    uint32_t streamIndex,
    const SwifterKitVideoQueueEntry* entry,
    IOStreamBufferQueueEntry* native) {
    if (entry == nullptr || native == nullptr || streamIndex >= kSwifterKitVideoStreamCount)
        return kIOReturnBadArgument;
    const auto& config = kSwifterKitVideoStreams[streamIndex];
    if (config.direction != 0 || entry->reserved[0] != 0 || entry->reserved[1] != 0
        || entry->reserved[2] != 0 || entry->bufferID >= config.bufferCount)
        return kIOReturnBadArgument;
    IOLockLock(ivars->bufferLock);
    const uint32_t dataCapacity = ivars->dataCapacity[streamIndex];
    const uint32_t controlCapacity = ivars->controlCapacity[streamIndex];
    const uint32_t bufferID = ivars->bufferIDs[streamIndex][entry->bufferID];
    const bool detached = ivars->bufferDetached[streamIndex][entry->bufferID];
    IOLockUnlock(ivars->bufferLock);
    if (detached)
        return kIOReturnNotAttached;
    if (!IsValidRange(entry->dataOffset, entry->dataLength, dataCapacity)
        || (entry->controlLength > 0
            && !IsValidRange(entry->controlOffset, entry->controlLength, controlCapacity)))
        return kIOReturnBadArgument;
    *native = {
        bufferID,
        entry->dataOffset,
        entry->dataLength,
        entry->controlOffset,
        entry->controlLength,
        {0, 0, 0}};
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeVideoDevice::DequeueInput(uint32_t streamIndex, OSData** response) {
    if (response == nullptr || streamIndex >= kSwifterKitVideoStreamCount
        || kSwifterKitVideoStreams[streamIndex].direction != kSwifterKitVideoDirectionInput)
        return kIOReturnBadArgument;
    IOStreamBufferQueueEntry entry = {};
    const kern_return_t result = ivars->streams[streamIndex]->dequeueInputEntry(&entry);
    if (result != kIOReturnSuccess)
        return result;
    // The host names buffers by IOStreamBufferID; Swift names them by index.
    const auto& config = kSwifterKitVideoStreams[streamIndex];
    uint32_t bufferIndex = config.bufferCount;
    IOLockLock(ivars->bufferLock);
    for (uint32_t index = 0; index < config.bufferCount; ++index)
        if (ivars->bufferIDs[streamIndex][index] == entry.bufferID)
            bufferIndex = index;
    const uint32_t dataCapacity = ivars->dataCapacity[streamIndex];
    const uint32_t controlCapacity = ivars->controlCapacity[streamIndex];
    IOLockUnlock(ivars->bufferLock);
    if (bufferIndex >= config.bufferCount
        || !IsValidRange(entry.dataOffset, entry.dataLength, dataCapacity)
        || (entry.controlLength > 0
            && !IsValidRange(entry.controlOffset, entry.controlLength, controlCapacity)))
        return kIOReturnError;
    const SwifterKitVideoQueueEntry wire = {
        bufferIndex,
        entry.dataOffset,
        entry.dataLength,
        entry.controlOffset,
        entry.controlLength,
        {0, 0, 0}};
    *response = OSData::withBytes(&wire, sizeof(wire));
    return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeVideoDevice::NotifyOutput(uint32_t streamIndex) {
    return streamIndex < kSwifterKitVideoStreamCount
                   && kSwifterKitVideoStreams[streamIndex].direction == 0
               ? ivars->streams[streamIndex]->SendOutputBufferNotification()
               : kIOReturnBadArgument;
}

kern_return_t SwifterKitRuntimeVideoDevice::UpdateTimestamp(
    const SwifterKitVideoTimestamp* timestamp) {
    if (timestamp == nullptr)
        return kIOReturnBadArgument;
    UpdateCurrentZeroTimestamp(timestamp->sampleTime, timestamp->hostTime);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeVideoDevice::RequestSampleRate(double sampleRate) {
    if (!IsSupportedSampleRate(sampleRate))
        return kIOReturnBadArgument;
    __atomic_store_n(
        &ivars->pendingSampleRateBits,
        __builtin_bit_cast(uint64_t, sampleRate),
        __ATOMIC_RELEASE);
    return RequestDeviceConfigurationChange(kSampleRateChangeAction, nullptr);
}

kern_return_t SwifterKitRuntimeVideoDevice::StartIO(IOUserVideoStartStopFlags flags) {
    const kern_return_t result = super::StartIO(flags);
    if (result == kIOReturnSuccess)
        (void)ivars->service->VideoControlEvent(
            kSwifterKitVideoEventStarted,
            static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::StopIO(IOUserVideoStartStopFlags flags) {
    (void)ivars->service->VideoControlEvent(
        kSwifterKitVideoEventStopped,
        static_cast<uint64_t>(flags));
    return super::StopIO(flags);
}

kern_return_t SwifterKitRuntimeVideoDevice::PerformDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction == kSwifterKitVideoMemberChangeAction)
        return ApplyMemberChange();
    if (changeAction == kSwifterKitVideoStructureChangeAction)
        return ApplyStructureChange(changeInfo);
    if (changeAction != kSampleRateChangeAction)
        return super::PerformDeviceConfigurationChange(changeAction, changeInfo);
    const double sampleRate = __builtin_bit_cast(
        double,
        __atomic_exchange_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_ACQUIRE));
    const kern_return_t result =
        IsSupportedSampleRate(sampleRate) ? SetSampleRate(sampleRate) : kIOReturnBadArgument;
    if (result == kIOReturnSuccess)
        (void)ivars->service->VideoControlEvent(
            kSwifterKitVideoEventSampleRateChanged,
            __builtin_bit_cast(uint64_t, sampleRate));
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::ApplyStructureChange(OSObject* changeInfo) {
    SwifterKitVideoStructureChange change = {};
    if (!SwifterKitReadVideoStructureChange(changeInfo, &change))
        return kIOReturnBadArgument;
    return SwifterKitApplyStructureChange<VideoStructureFamily>(this, ivars, change);
}

kern_return_t SwifterKitRuntimeVideoDevice::AbortDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction == kSampleRateChangeAction)
        __atomic_store_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_RELEASE);
    if (changeAction == kSwifterKitVideoMemberChangeAction) {
        IOLockLock(ivars->bufferLock);
        ivars->pendingChangeKind = 0;
        IOLockUnlock(ivars->bufferLock);
    }
    return super::AbortDeviceConfigurationChange(changeAction, changeInfo);
}

void SwifterKitRuntimeVideoDevice::StreamFormatChanged(IOUserVideoObjectID streamID) {
    super::StreamFormatChanged(streamID);
    if (ivars != nullptr)
        (void)ivars->service->VideoObjectEvent(
            kSwifterKitVideoObjectEventDeviceFormatChanged,
            0,
            streamID);
}

kern_return_t SwifterKitRuntimeVideoDevice::HandleChangeSampleRate(double sampleRate) {
    if (!IsSupportedSampleRate(sampleRate))
        return kIOReturnBadArgument;
    const kern_return_t result = SetSampleRate(sampleRate);
    if (result == kIOReturnSuccess)
        (void)ivars->service->VideoControlEvent(
            kSwifterKitVideoEventSampleRateChanged,
            __builtin_bit_cast(uint64_t, sampleRate));
    return result;
}
kern_return_t SwifterKitRuntimeVideoDevice::NotifyBufferQueue(
    uint32_t kind,
    uint32_t streamIndex,
    uint64_t changeAction) {
    // The stream's own SendBufferQueueChange takes no change action.
    if (ivars == nullptr || kind < kSwifterKitVideoNotifyBufferQueueChange
        || kind > kSwifterKitVideoNotifyStreamBufferQueueChange
        || streamIndex >= kSwifterKitVideoStreamCount
        || (kind == kSwifterKitVideoNotifyStreamBufferQueueChange && changeAction != 0))
        return kIOReturnBadArgument;
    IOUserVideoStream* stream = ivars->streams[streamIndex];
    if (stream == nullptr)
        return kIOReturnNotReady;
    if (kind == kSwifterKitVideoNotifyStreamBufferQueueChange)
        return stream->SendBufferQueueChange();
    return kind == kSwifterKitVideoNotifyBufferQueueChange
               ? ivars->service->BufferQueueChange(
                     GetObjectID(),
                     changeAction,
                     stream->GetObjectID())
               : ivars->service->OutputBufferNotification(
                     GetObjectID(),
                     changeAction,
                     stream->GetObjectID());
}
#endif
