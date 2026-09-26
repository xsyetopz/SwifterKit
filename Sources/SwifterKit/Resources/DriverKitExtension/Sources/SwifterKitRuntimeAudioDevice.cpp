#include "SwifterKitRuntimeAudioDevice.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioDeviceState.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"

namespace {
    constexpr uint64_t kSampleRateChangeAction = 0x53574B415544494FULL;

    IOUserAudioStreamBasicDescription NativeFormat(
        const SwifterKitAudioFormatConfiguration& format) {
        return {
            format.sampleRate,
            static_cast<IOUserAudioFormatID>(format.formatID),
            static_cast<IOUserAudioFormatFlags>(format.formatFlags),
            format.bytesPerPacket,
            format.framesPerPacket,
            format.bytesPerFrame,
            format.channelsPerFrame,
            format.bitsPerChannel,
            0};
    }

    bool IsSupportedSampleRate(double sampleRate) {
        for (uint32_t index = 0; index < kSwifterKitAudioSampleRateCount; ++index)
            if (kSwifterKitAudioSampleRates[index] == sampleRate)
                return true;
        return false;
    }
}  // namespace

bool SwifterKitRuntimeAudioDevice::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    bool supportsPrewarming,
    OSString* deviceUID,
    OSString* modelUID,
    OSString* manufacturerUID,
    uint32_t zeroTimestampPeriod) {
    if (driver == nullptr || service == nullptr
        || !super::init(
            driver,
            supportsPrewarming,
            deviceUID,
            modelUID,
            manufacturerUID,
            zeroTimestampPeriod))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioDevice_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->service = service;
    service->retain();
    return true;
}

void SwifterKitRuntimeAudioDevice::free() {
    if (ivars != nullptr) {
        for (uint32_t index = 0; index < kSwifterKitAudioStreamCount; ++index) {
            OSSafeReleaseNULL(ivars->maps[index]);
            OSSafeReleaseNULL(ivars->streams[index]);
            OSSafeReleaseNULL(ivars->descriptors[index]);
        }
        for (uint32_t index = 0; index < kSwifterKitAudioControlCount; ++index)
            OSSafeReleaseNULL(ivars->controls[index]);
        for (uint32_t index = 0; index < kSwifterKitAudioCustomPropertyCount; ++index)
            OSSafeReleaseNULL(ivars->customProperties[index]);
        OSSafeReleaseNULL(ivars->service);
    }
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioDevice_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioDevice::Configure() {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    OSString* name = OSString::withCString(kSwifterKitAudioDeviceName);
    kern_return_t result = name == nullptr ? kIOReturnNoMemory : SetName(name);
    OSSafeReleaseNULL(name);
    if (result == kIOReturnSuccess)
        result = SetTransportType(static_cast<IOUserAudioTransportType>(kSwifterKitAudioTransport));
    if (result == kIOReturnSuccess)
        result =
            SetAvailableSampleRates(kSwifterKitAudioSampleRates, kSwifterKitAudioSampleRateCount);
    if (result == kIOReturnSuccess)
        result = SetSampleRate(kSwifterKitAudioInitialSampleRate);

    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitAudioStreamCount;
         ++index) {
        const auto& config = kSwifterKitAudioStreams[index];
        uint32_t maximumBytesPerFrame = 0;
        IOUserAudioStreamBasicDescription formats[16] = {};
        for (uint32_t formatIndex = 0; formatIndex < config.formatCount; ++formatIndex) {
            const auto& source = kSwifterKitAudioFormats[config.formatStart + formatIndex];
            formats[formatIndex] = NativeFormat(source);
            if (source.bytesPerFrame > maximumBytesPerFrame)
                maximumBytesPerFrame = source.bytesPerFrame;
        }
        const uint64_t bufferSize =
            static_cast<uint64_t>(maximumBytesPerFrame) * config.ringBufferFrameCapacity;
        result = IOBufferMemoryDescriptor::Create(
            kIOMemoryDirectionInOut,
            bufferSize,
            0,
            &ivars->descriptors[index]);
        if (result == kIOReturnSuccess)
            result = ivars->descriptors[index]
                         ->CreateMapping(0, 0, 0, bufferSize, 0, &ivars->maps[index]);
        if (result == kIOReturnSuccess) {
            ivars->streams[index] = IOUserAudioStream::Create(
                                        ivars->service,
                                        static_cast<IOUserAudioStreamDirection>(config.direction),
                                        ivars->descriptors[index])
                                        .detach();
            result = ivars->streams[index] == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
        name = result == kIOReturnSuccess ? OSString::withCString(config.name) : nullptr;
        if (result == kIOReturnSuccess)
            result = name == nullptr ? kIOReturnNoMemory : ivars->streams[index]->SetName(name);
        OSSafeReleaseNULL(name);
        if (result == kIOReturnSuccess)
            result = ivars->streams[index]->SetAvailableStreamFormats(formats, config.formatCount);
        if (result == kIOReturnSuccess)
            result =
                ivars->streams[index]->SetCurrentStreamFormat(&formats[config.initialFormatIndex]);
        if (result == kIOReturnSuccess)
            result = AddStream(ivars->streams[index]);
    }

    if (result == kIOReturnSuccess)
        result = ConfigureControls();
    if (result != kIOReturnSuccess)
        return result;
    auto state = ivars;
    return SetIOOperationHandler(^kern_return_t(
        IOUserAudioObjectID,
        IOUserAudioIOOperation operation,
        uint32_t frameCount,
        uint64_t sampleTime,
        uint64_t hostTime) {
      const uint64_t writing = __atomic_add_fetch(&state->sequence, 1, __ATOMIC_ACQ_REL);
      __atomic_store_n(&state->operation, operation, __ATOMIC_RELAXED);
      __atomic_store_n(&state->frameCount, frameCount, __ATOMIC_RELAXED);
      __atomic_store_n(&state->sampleTime, sampleTime, __ATOMIC_RELAXED);
      __atomic_store_n(&state->hostTime, hostTime, __ATOMIC_RELAXED);
      __atomic_store_n(&state->sequence, writing + 1, __ATOMIC_RELEASE);
      return kIOReturnSuccess;
    });
}

kern_return_t SwifterKitRuntimeAudioDevice::ReadStream(
    const SwifterKitAudioTransferHeader* transfer,
    OSData** response) {
    if (transfer == nullptr || response == nullptr || transfer->length > 65512
        || transfer->streamIndex >= kSwifterKitAudioStreamCount)
        return kIOReturnBadArgument;
    IOMemoryMap* map = ivars->maps[transfer->streamIndex];
    if (map == nullptr || map->GetAddress() == 0 || transfer->length == 0
        || transfer->byteOffset >= map->GetLength() || transfer->length > map->GetLength())
        return kIOReturnBadArgument;
    OSData* data = OSData::withCapacity(transfer->length);
    if (data == nullptr)
        return kIOReturnNoMemory;
    const uint64_t remaining = map->GetLength() - transfer->byteOffset;
    const uint64_t firstLength = transfer->length < remaining ? transfer->length : remaining;
    const auto* base = reinterpret_cast<const uint8_t*>(map->GetAddress() + map->GetOffset());
    bool appended = data->appendBytes(base + transfer->byteOffset, firstLength);
    if (appended && firstLength < transfer->length)
        appended = data->appendBytes(base, transfer->length - firstLength);
    if (!appended) {
        data->release();
        return kIOReturnNoMemory;
    }
    *response = data;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeAudioDevice::WriteStream(
    const SwifterKitAudioTransferHeader* transfer,
    const uint8_t* bytes) {
    if (transfer == nullptr || bytes == nullptr || transfer->length > 65472
        || transfer->streamIndex >= kSwifterKitAudioStreamCount)
        return kIOReturnBadArgument;
    IOMemoryMap* map = ivars->maps[transfer->streamIndex];
    if (map == nullptr || map->GetAddress() == 0 || transfer->length == 0
        || transfer->byteOffset >= map->GetLength() || transfer->length > map->GetLength())
        return kIOReturnBadArgument;
    const uint64_t remaining = map->GetLength() - transfer->byteOffset;
    const uint64_t firstLength = transfer->length < remaining ? transfer->length : remaining;
    auto* base = reinterpret_cast<uint8_t*>(map->GetAddress() + map->GetOffset());
    memcpy(base + transfer->byteOffset, bytes, firstLength);
    if (firstLength < transfer->length)
        memcpy(base, bytes + firstLength, transfer->length - firstLength);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeAudioDevice::CopyIOState(OSData** response) {
    if (response == nullptr || ivars == nullptr)
        return kIOReturnBadArgument;
    SwifterKitAudioIOState state = {};
    for (uint32_t attempt = 0; attempt < 4; ++attempt) {
        state.sequence = __atomic_load_n(&ivars->sequence, __ATOMIC_ACQUIRE);
        if ((state.sequence & 1) != 0)
            continue;
        state.operation = __atomic_load_n(&ivars->operation, __ATOMIC_RELAXED);
        state.frameCount = __atomic_load_n(&ivars->frameCount, __ATOMIC_RELAXED);
        state.sampleTime = __atomic_load_n(&ivars->sampleTime, __ATOMIC_RELAXED);
        state.hostTime = __atomic_load_n(&ivars->hostTime, __ATOMIC_RELAXED);
        if (state.sequence == __atomic_load_n(&ivars->sequence, __ATOMIC_ACQUIRE)) {
            *response = OSData::withBytes(&state, sizeof(state));
            return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
    }
    return kIOReturnBusy;
}

kern_return_t SwifterKitRuntimeAudioDevice::UpdateTimestamp(
    const SwifterKitAudioTimestamp* timestamp) {
    if (timestamp == nullptr)
        return kIOReturnBadArgument;
    UpdateCurrentZeroTimestamp(timestamp->sampleTime, timestamp->hostTime);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeAudioDevice::RequestSampleRate(double sampleRate) {
    if (!IsSupportedSampleRate(sampleRate))
        return kIOReturnBadArgument;
    __atomic_store_n(
        &ivars->pendingSampleRateBits,
        __builtin_bit_cast(uint64_t, sampleRate),
        __ATOMIC_RELEASE);
    return RequestDeviceConfigurationChange(kSampleRateChangeAction, nullptr);
}

kern_return_t SwifterKitRuntimeAudioDevice::StartIO(IOUserAudioStartStopFlags flags) {
    const kern_return_t result = super::StartIO(flags);
    if (result == kIOReturnSuccess)
        (void)ivars->service->AudioControlEvent(1, static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeAudioDevice::StopIO(IOUserAudioStartStopFlags flags) {
    (void)ivars->service->AudioControlEvent(2, static_cast<uint64_t>(flags));
    return super::StopIO(flags);
}

kern_return_t SwifterKitRuntimeAudioDevice::PerformDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction != kSampleRateChangeAction)
        return super::PerformDeviceConfigurationChange(changeAction, changeInfo);
    const uint64_t sampleRateBits =
        __atomic_exchange_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_ACQUIRE);
    const double sampleRate = __builtin_bit_cast(double, sampleRateBits);
    kern_return_t result =
        IsSupportedSampleRate(sampleRate) ? SetSampleRate(sampleRate) : kIOReturnBadArgument;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitAudioStreamCount;
         ++index)
        result = ivars->streams[index]->DeviceSampleRateChanged(sampleRate);
    if (result == kIOReturnSuccess)
        result = ivars->service->AudioControlEvent(3, __builtin_bit_cast(uint64_t, sampleRate));
    return result;
}

kern_return_t SwifterKitRuntimeAudioDevice::AbortDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction == kSampleRateChangeAction)
        __atomic_store_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_RELEASE);
    return super::AbortDeviceConfigurationChange(changeAction, changeInfo);
}

kern_return_t SwifterKitRuntimeAudioDevice::HandleChangeSampleRate(double sampleRate) {
    if (!IsSupportedSampleRate(sampleRate))
        return kIOReturnBadArgument;
    kern_return_t result = SetSampleRate(sampleRate);
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitAudioStreamCount;
         ++index)
        result = ivars->streams[index]->DeviceSampleRateChanged(sampleRate);
    if (result == kIOReturnSuccess)
        result = ivars->service->AudioControlEvent(3, __builtin_bit_cast(uint64_t, sampleRate));
    return result;
}
#endif
