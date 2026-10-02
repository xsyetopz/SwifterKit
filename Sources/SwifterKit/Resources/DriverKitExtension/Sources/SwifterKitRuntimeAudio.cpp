#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioDevice.h"
    #include "SwifterKitRuntimeMediaMembers.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    // The opcodes, wire structs, and schema values the SwifterKitRuntimeMediaMembers.h service
    // templates operate on.
    struct AudioCommandFamily {
        using Timestamp = SwifterKitAudioTimestamp;
        using ControlGet = SwifterKitAudioControlGet;
        using ControlValueHeader = SwifterKitAudioControlValueHeader;
        using CustomPropertyHeader = SwifterKitAudioCustomPropertyHeader;
        using ControlEventHeader = SwifterKitAudioControlEventHeader;
        using CustomPropertyEventHeader = SwifterKitAudioCustomPropertyEventHeader;

        static constexpr uint32_t kUpdateTimestamp =
            static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioUpdateTimestamp);
        static constexpr uint32_t kRequestSampleRate =
            static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioRequestSampleRate);
        static constexpr uint32_t kGetControl =
            static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetControl);
        static constexpr uint32_t kSetControl =
            static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioSetControl);
        static constexpr uint32_t kGetCustomProperty =
            static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetCustomProperty);
        static constexpr uint32_t kSetCustomProperty =
            static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioSetCustomProperty);

        static constexpr uint32_t kValueFirst = kSwifterKitAudioValueBoolean;
        static constexpr uint32_t kValueLast = kSwifterKitAudioValueStereoPan;
        static constexpr uint32_t kValueSelector = kSwifterKitAudioValueSelector;
        static constexpr uint32_t kMaximumSelectorItems = kSwifterKitAudioMaximumSelectorItems;
        static constexpr uint32_t kNameMaximumLength = kSwifterKitAudioNameMaximumLength;
        static constexpr uint32_t kCustomPropertyValueMaximumLength =
            kSwifterKitAudioCustomPropertyValueMaximumLength;
        static constexpr uint32_t kEventControlChanged = kSwifterKitAudioEventControlChanged;
        static constexpr uint32_t kEventCustomPropertyChanged =
            kSwifterKitAudioEventCustomPropertyChanged;
    };
}  // namespace

kern_return_t SwifterKitRuntimeService::StartAudio() {
    if (ivars == nullptr || ivars->audioDevice != nullptr)
        return kIOReturnNotReady;
    OSString* deviceUID = OSString::withCString(kSwifterKitAudioDeviceUID);
    OSString* modelUID = OSString::withCString(kSwifterKitAudioModelUID);
    OSString* manufacturerUID = OSString::withCString(kSwifterKitAudioManufacturerUID);
    auto* device = OSTypeAlloc(SwifterKitRuntimeAudioDevice);
    kern_return_t result = deviceUID == nullptr || modelUID == nullptr || manufacturerUID == nullptr
                                   || device == nullptr
                               ? kIOReturnNoMemory
                               : kIOReturnSuccess;
    if (result == kIOReturnSuccess)
        result = SetTransportType(static_cast<IOUserAudioTransportType>(kSwifterKitAudioTransport));
    if (result == kIOReturnSuccess
        && !device->init(
            this,
            this,
            kSwifterKitAudioSupportsPrewarming,
            deviceUID,
            modelUID,
            manufacturerUID,
            kSwifterKitAudioZeroTimestampPeriod))
        result = kIOReturnNoMemory;
    if (result == kIOReturnSuccess)
        result = device->Configure();
    if (result == kIOReturnSuccess)
        result = AddObject(device);
    if (result == kIOReturnSuccess) {
        IOLockLock(ivars->audioLock);
        ivars->audioDevice = device;
        IOLockUnlock(ivars->audioLock);
    } else
        OSSafeReleaseNULL(device);
    OSSafeReleaseNULL(deviceUID);
    OSSafeReleaseNULL(modelUID);
    OSSafeReleaseNULL(manufacturerUID);
    if (result == kIOReturnSuccess)
        result = StartAudioObjects();
    return result;
}

void SwifterKitRuntimeService::StopAudio() {
    if (ivars == nullptr || ivars->audioLock == nullptr)
        return;
    // Boxes release the device before it leaves the driver.
    StopAudioObjects();
    IOLockLock(ivars->audioLock);
    SwifterKitRuntimeAudioDevice* device = ivars->audioDevice;
    ivars->audioDevice = nullptr;
    if (device != nullptr) {
        device->RemoveControlsAndProperties();
        (void)RemoveObject(device);
    }
    IOLockUnlock(ivars->audioLock);
    OSSafeReleaseNULL(device);
}

kern_return_t SwifterKitRuntimeService::AudioControlEvent(uint32_t kind, uint64_t value) {
    const SwifterKitAudioEvent event = {kind, 0, value};
    return EnqueueEvent(kSwifterKitEventAudio, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::AudioStreamFormatEvent(
    uint32_t streamIndex,
    const IOUserAudioStreamBasicDescription* format) {
    if (streamIndex >= kSwifterKitAudioStreamCount || format == nullptr || format->mReserved != 0)
        return kIOReturnBadArgument;
    const auto& stream = kSwifterKitAudioStreams[streamIndex];
    bool supported = false;
    for (uint32_t index = 0; index < stream.formatCount; ++index) {
        const auto& candidate = kSwifterKitAudioFormats[stream.formatStart + index];
        supported = supported
                    || (format->mSampleRate == candidate.sampleRate
                        && static_cast<uint32_t>(format->mFormatID) == candidate.formatID
                        && static_cast<uint32_t>(format->mFormatFlags) == candidate.formatFlags
                        && format->mBytesPerPacket == candidate.bytesPerPacket
                        && format->mFramesPerPacket == candidate.framesPerPacket
                        && format->mBytesPerFrame == candidate.bytesPerFrame
                        && format->mChannelsPerFrame == candidate.channelsPerFrame
                        && format->mBitsPerChannel == candidate.bitsPerChannel);
    }
    if (!supported)
        return kIOReturnBadArgument;
    const SwifterKitAudioStreamFormatEvent event = {
        kSwifterKitAudioEventStreamFormatChanged,
        streamIndex,
        format->mSampleRate,
        static_cast<uint32_t>(format->mFormatID),
        static_cast<uint32_t>(format->mFormatFlags),
        format->mBytesPerPacket,
        format->mFramesPerPacket,
        format->mBytesPerFrame,
        format->mChannelsPerFrame,
        format->mBitsPerChannel,
        0};
    return EnqueueRequiredEvent(kSwifterKitEventAudio, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::AudioStreamActiveEvent(
    uint32_t streamIndex,
    bool isActive) {
    if (streamIndex >= kSwifterKitAudioStreamCount)
        return kIOReturnBadArgument;
    const SwifterKitAudioStreamEvent event = {
        kSwifterKitAudioEventStreamActiveChanged,
        streamIndex,
        isActive ? 1ULL : 0ULL};
    return EnqueueRequiredEvent(kSwifterKitEventAudio, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::AudioControlValueEvent(
    uint32_t identifier,
    uint32_t kind,
    const uint32_t* values,
    uint32_t count) {
    return SwifterKitEnqueueControlValueEvent<AudioCommandFamily>(
        identifier,
        kind,
        values,
        count,
        [this](const void* bytes, uint32_t length) {
            return EnqueueRequiredEvent(kSwifterKitEventAudio, bytes, length);
        });
}

kern_return_t SwifterKitRuntimeService::AudioCustomPropertyEvent(
    uint32_t identifier,
    const uint8_t* qualifier,
    uint32_t qualifierLength,
    const uint8_t* value,
    uint32_t valueLength) {
    return SwifterKitEnqueueCustomPropertyEvent<AudioCommandFamily>(
        identifier,
        qualifier,
        qualifierLength,
        value,
        valueLength,
        [this](const void* bytes, uint32_t length) {
            return EnqueueRequiredEvent(kSwifterKitEventAudio, bytes, length);
        });
}

kern_return_t SwifterKitRuntimeService::AudioCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->audioLock == nullptr || response == nullptr)
        return kIOReturnBadArgument;
    *response = nullptr;
    if (opcode >= static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetObjectInfo)
        && opcode <= static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioCompleteRequest))
        return AudioObjectCommand(opcode, payload, payloadLength, response);
    IOLockLock(ivars->audioLock);
    SwifterKitRuntimeAudioDevice* device = ivars->audioDevice;
    kern_return_t result = device == nullptr ? kIOReturnNotReady : kIOReturnUnsupported;
    if (device != nullptr
        && (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioReadStream)
            || opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioWriteStream))) {
        if (payload == nullptr || payloadLength < sizeof(SwifterKitAudioTransferHeader))
            result = kIOReturnBadArgument;
        else {
            const auto* transfer = reinterpret_cast<const SwifterKitAudioTransferHeader*>(payload);
            const uint32_t expectedLength =
                opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioWriteStream)
                    ? sizeof(*transfer) + transfer->length
                    : sizeof(*transfer);
            if (transfer->reserved0 != 0 || transfer->reserved1 != 0
                || payloadLength != expectedLength)
                result = kIOReturnBadArgument;
            else if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioReadStream))
                result = device->ReadStream(transfer, response);
            else
                result = device->WriteStream(transfer, payload + sizeof(*transfer));
        }
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetIOState)) {
        result = payloadLength == 0 ? device->CopyIOState(response) : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode >= static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetDeviceState)
        && opcode <= static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioSetMemberAttachment)) {
        result = device->MemberCommand(opcode, payload, payloadLength, response);
    } else if (device != nullptr) {
        result = SwifterKitDeviceCommand<AudioCommandFamily>(
            device,
            opcode,
            payload,
            payloadLength,
            response);
    }
    IOLockUnlock(ivars->audioLock);
    return result;
}
#endif
