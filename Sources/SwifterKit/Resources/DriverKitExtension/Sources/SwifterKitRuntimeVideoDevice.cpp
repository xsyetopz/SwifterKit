#include "SwifterKitRuntimeVideoDevice.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSArray.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeVideoDeviceState.h"
    #include "SwifterKitRuntimeVideoStream.h"

namespace {
    constexpr uint64_t kSampleRateChangeAction = 0x53574B564944454FULL;

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

        IOUserVideoStreamBasicDescription formats[16] = {};
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
    if (transfer == nullptr || response == nullptr || transfer->length > 65464
        || transfer->streamIndex >= kSwifterKitVideoStreamCount)
        return kIOReturnBadArgument;
    const auto& config = kSwifterKitVideoStreams[transfer->streamIndex];
    if (transfer->bufferIndex >= config.bufferCount || transfer->plane > 1)
        return kIOReturnBadArgument;
    IOMemoryMap* map = transfer->plane == 0
                           ? ivars->dataMaps[transfer->streamIndex][transfer->bufferIndex]
                           : ivars->controlMaps[transfer->streamIndex][transfer->bufferIndex];
    if (map == nullptr || map->GetAddress() == 0
        || !IsValidRange(transfer->byteOffset, transfer->length, map->GetLength()))
        return kIOReturnBadArgument;
    *response = OSData::withBytes(
        reinterpret_cast<const uint8_t*>(map->GetAddress() + map->GetOffset())
            + transfer->byteOffset,
        transfer->length);
    return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeVideoDevice::WriteBuffer(
    const SwifterKitVideoTransferHeader* transfer,
    const uint8_t* bytes) {
    if (transfer == nullptr || bytes == nullptr || transfer->length > 65432
        || transfer->streamIndex >= kSwifterKitVideoStreamCount)
        return kIOReturnBadArgument;
    const auto& config = kSwifterKitVideoStreams[transfer->streamIndex];
    if (transfer->bufferIndex >= config.bufferCount || transfer->plane > 1)
        return kIOReturnBadArgument;
    IOMemoryMap* map = transfer->plane == 0
                           ? ivars->dataMaps[transfer->streamIndex][transfer->bufferIndex]
                           : ivars->controlMaps[transfer->streamIndex][transfer->bufferIndex];
    if (map == nullptr || map->GetAddress() == 0
        || !IsValidRange(transfer->byteOffset, transfer->length, map->GetLength()))
        return kIOReturnBadArgument;
    memcpy(
        reinterpret_cast<uint8_t*>(map->GetAddress() + map->GetOffset()) + transfer->byteOffset,
        bytes,
        transfer->length);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeVideoDevice::EnqueueOutput(
    uint32_t streamIndex,
    const SwifterKitVideoQueueEntry* entry) {
    if (entry == nullptr || streamIndex >= kSwifterKitVideoStreamCount)
        return kIOReturnBadArgument;
    const auto& config = kSwifterKitVideoStreams[streamIndex];
    if (config.direction != 0 || entry->reserved[0] != 0 || entry->reserved[1] != 0
        || entry->reserved[2] != 0 || entry->bufferID >= config.bufferCount
        || !IsValidRange(entry->dataOffset, entry->dataLength, config.dataBufferCapacity)
        || (entry->controlLength > 0
            && !IsValidRange(
                entry->controlOffset,
                entry->controlLength,
                config.controlBufferCapacity)))
        return kIOReturnBadArgument;
    IOStreamBufferQueueEntry native = {
        entry->bufferID,
        entry->dataOffset,
        entry->dataLength,
        entry->controlOffset,
        entry->controlLength,
        {0, 0, 0}};
    return ivars->streams[streamIndex]->enqueueOutputEntry(&native);
}

kern_return_t SwifterKitRuntimeVideoDevice::DequeueInput(uint32_t streamIndex, OSData** response) {
    if (response == nullptr || streamIndex >= kSwifterKitVideoStreamCount
        || kSwifterKitVideoStreams[streamIndex].direction != 1)
        return kIOReturnBadArgument;
    IOStreamBufferQueueEntry entry = {};
    const kern_return_t result = ivars->streams[streamIndex]->dequeueInputEntry(&entry);
    if (result != kIOReturnSuccess)
        return result;
    const auto& config = kSwifterKitVideoStreams[streamIndex];
    if (entry.bufferID >= config.bufferCount
        || !IsValidRange(entry.dataOffset, entry.dataLength, config.dataBufferCapacity)
        || (entry.controlLength > 0
            && !IsValidRange(
                entry.controlOffset,
                entry.controlLength,
                config.controlBufferCapacity)))
        return kIOReturnError;
    const SwifterKitVideoQueueEntry wire = {
        entry.bufferID,
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
        (void)ivars->service->VideoControlEvent(1, static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::StopIO(IOUserVideoStartStopFlags flags) {
    (void)ivars->service->VideoControlEvent(2, static_cast<uint64_t>(flags));
    return super::StopIO(flags);
}

kern_return_t SwifterKitRuntimeVideoDevice::PerformDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction != kSampleRateChangeAction)
        return super::PerformDeviceConfigurationChange(changeAction, changeInfo);
    const double sampleRate = __builtin_bit_cast(
        double,
        __atomic_exchange_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_ACQUIRE));
    const kern_return_t result =
        IsSupportedSampleRate(sampleRate) ? SetSampleRate(sampleRate) : kIOReturnBadArgument;
    if (result == kIOReturnSuccess)
        (void)ivars->service->VideoControlEvent(3, __builtin_bit_cast(uint64_t, sampleRate));
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::AbortDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction == kSampleRateChangeAction)
        __atomic_store_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_RELEASE);
    return super::AbortDeviceConfigurationChange(changeAction, changeInfo);
}

kern_return_t SwifterKitRuntimeVideoDevice::HandleChangeSampleRate(double sampleRate) {
    if (!IsSupportedSampleRate(sampleRate))
        return kIOReturnBadArgument;
    const kern_return_t result = SetSampleRate(sampleRate);
    if (result == kIOReturnSuccess)
        (void)ivars->service->VideoControlEvent(3, __builtin_bit_cast(uint64_t, sampleRate));
    return result;
}
#endif
