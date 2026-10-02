#include "SwifterKitRuntimeAudioDevice.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioDeviceState.h"
    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeMediaMembers.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"

// Device, stream, control, and custom-property contract (opcodes 0x0A20-0x0A29):
// - MemberCommand runs under audioLock, like every other device command, and validates each
//   payload length, reserved field, index, and selector before calling AudioDriverKit.
// - Streams and controls start attached to the device. Custom properties start on the device
//   and may move to the driver only through a detached state. propertyPlacement stores 0 for
//   the device, 1 for detached, and 2 for the driver, so zeroed ivars mean "as configured".
// - RemoveControlsAndProperties removes only attached controls and removes each custom
//   property from the owner that holds it.
namespace {
    constexpr uint8_t kPlacementDevice = 0;
    constexpr uint8_t kPlacementDetached = 1;
    constexpr uint8_t kPlacementDriver = 2;

    // The AudioDriverKit classes, wire structs, and schema values the
    // SwifterKitRuntimeMediaMembers.h member templates operate on.
    struct AudioMemberFamily {
        using DeviceState = SwifterKitAudioDeviceState;
        using ChannelLayoutHeader = SwifterKitAudioChannelLayoutHeader;
        using ChannelLabel = IOUserAudioChannelLabel;
        using ControlInfo = SwifterKitAudioControlInfo;
        using CustomPropertyInfo = SwifterKitAudioCustomPropertyInfo;
        using SliderControl = IOUserAudioSliderControl;
        using StereoPanControl = IOUserAudioStereoPanControl;
        using SelectorControl = IOUserAudioSelectorControl;
        using SliderRange = IOUserAudioSliderRange;
        using PropertyElement = IOUserAudioObjectPropertyElement;
        using SelectorDescription = IOUserAudioSelectorValueDescription;

        static constexpr uint32_t kMaximumChannelLabels = kSwifterKitAudioMaximumChannelLabels;
        static constexpr uint32_t kMaximumSelectorItems = kSwifterKitAudioMaximumSelectorItems;
        static constexpr uint32_t kNameMaximumLength = kSwifterKitAudioNameMaximumLength;
        static constexpr uint32_t kControlPropertySliderRange =
            kSwifterKitAudioControlPropertySliderRange;
        static constexpr uint32_t kControlPropertyPanningChannels =
            kSwifterKitAudioControlPropertyPanningChannels;
        static constexpr uint32_t kChangeStreamAttachment = kSwifterKitAudioChangeStreamAttachment;
        static constexpr uint32_t kChangeInputSafetyOffset =
            kSwifterKitAudioChangeInputSafetyOffset;
        static constexpr uint32_t kChangeOutputSafetyOffset =
            kSwifterKitAudioChangeOutputSafetyOffset;

        static constexpr uint32_t kStreamCount = kSwifterKitAudioStreamCount;
        static constexpr uint32_t kControlCount = kSwifterKitAudioControlCount;
        static constexpr const auto* kControls = kSwifterKitAudioControls;
        static constexpr uint32_t kCustomPropertyCount = kSwifterKitAudioCustomPropertyCount;
        static constexpr const auto* kCustomProperties = kSwifterKitAudioCustomProperties;
    };

    uint32_t WireOwner(uint8_t placement) {
        return placement == kPlacementDevice   ? kSwifterKitAudioOwnerDevice
               : placement == kPlacementDriver ? kSwifterKitAudioOwnerDriver
                                               : kSwifterKitAudioOwnerDetached;
    }

    SwifterKitAudioStreamFormat WireFormat(const IOUserAudioStreamBasicDescription& format) {
        return {
            __builtin_bit_cast(uint64_t, format.mSampleRate),
            static_cast<uint32_t>(format.mFormatID),
            static_cast<uint32_t>(format.mFormatFlags),
            format.mBytesPerPacket,
            format.mFramesPerPacket,
            format.mBytesPerFrame,
            format.mChannelsPerFrame,
            format.mBitsPerChannel,
            0};
    }

    // Bytes for frames of the stream's widest format, or zero when out of range.
    uint64_t RingBufferBytes(uint32_t index, uint32_t frames) {
        if (index >= kSwifterKitAudioStreamCount)
            return 0;
        const auto& config = kSwifterKitAudioStreams[index];
        uint32_t bytesPerFrame = 0;
        for (uint32_t format = 0; format < config.formatCount; ++format) {
            const uint32_t candidate =
                kSwifterKitAudioFormats[config.formatStart + format].bytesPerFrame;
            bytesPerFrame = candidate > bytesPerFrame ? candidate : bytesPerFrame;
        }
        const uint64_t size = static_cast<uint64_t>(bytesPerFrame) * frames;
        return size <= kSwifterKitAudioMaximumRingBufferSize ? size : 0;
    }
}  // namespace

void SwifterKitRuntimeAudioDevice::RemoveControlsAndProperties() {
    if (ivars == nullptr)
        return;
    for (uint32_t index = 0; index < kSwifterKitAudioControlCount; ++index)
        if (ivars->controls[index] != nullptr && !ivars->controlDetached[index]) {
            (void)RemoveControl(ivars->controls[index]);
            ivars->controlDetached[index] = true;
        }
    for (uint32_t index = 0; index < kSwifterKitAudioCustomPropertyCount; ++index) {
        auto* property = ivars->customProperties[index];
        if (property == nullptr)
            continue;
        switch (ivars->propertyPlacement[index]) {
            case kPlacementDevice:
                (void)RemoveCustomProperty(property);
                break;
            case kPlacementDriver:
                (void)static_cast<IOUserAudioDriver*>(ivars->service)
                    ->RemoveCustomProperty(property);
                break;
            default:
                break;
        }
        ivars->propertyPlacement[index] = kPlacementDetached;
    }
}

kern_return_t SwifterKitRuntimeAudioDevice::MemberCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || response == nullptr)
        return kIOReturnBadArgument;
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::AudioGetDeviceState:
            return payloadLength == 0 ? SwifterKitCopyDeviceState<AudioMemberFamily>(this, response)
                                      : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::AudioSetDeviceProperty:
            return SetDeviceProperty(
                SwifterKitMemberPayload<SwifterKitAudioMemberValue>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::AudioSetPreferredChannelLayout:
            return SwifterKitSetPreferredChannelLayout<AudioMemberFamily>(
                this,
                payload,
                payloadLength);
        case SwifterKitRuntimeOpcode::AudioGetStreamState:
            return CopyStreamState(
                SwifterKitMemberPayload<SwifterKitAudioMemberRequest>(payload, payloadLength),
                response);
        case SwifterKitRuntimeOpcode::AudioSetStreamProperty:
            return SetStreamProperty(
                SwifterKitMemberPayload<SwifterKitAudioMemberProperty>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::AudioGetControlInfo:
            return CopyControlInfo(
                SwifterKitMemberPayload<SwifterKitAudioMemberRequest>(payload, payloadLength),
                response);
        case SwifterKitRuntimeOpcode::AudioSetControlProperty:
            return SetControlProperty(
                SwifterKitMemberPayload<SwifterKitAudioMemberProperty>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::AudioRemoveSelectorItems: {
            if (payload == nullptr || payloadLength < sizeof(SwifterKitAudioSelectorRemoval))
                return kIOReturnBadArgument;
            const auto* header = reinterpret_cast<const SwifterKitAudioSelectorRemoval*>(payload);
            if (header->count == 0 || header->count > kSwifterKitAudioMaximumSelectorItems
                || payloadLength != sizeof(*header) + header->count * sizeof(uint32_t))
                return kIOReturnBadArgument;
            return RemoveSelectorItems(
                header,
                reinterpret_cast<const uint32_t*>(payload + sizeof(*header)));
        }
        case SwifterKitRuntimeOpcode::AudioGetCustomPropertyInfo: {
            const auto* request =
                SwifterKitMemberPayload<SwifterKitAudioMemberRequest>(payload, payloadLength);
            if (request == nullptr || request->reserved != 0)
                return kIOReturnBadArgument;
            return SwifterKitCopyCustomPropertyInfo<AudioMemberFamily>(
                ivars,
                request->identifier,
                [this](uint32_t index) { return WireOwner(ivars->propertyPlacement[index]); },
                response);
        }
        case SwifterKitRuntimeOpcode::AudioSetMemberAttachment:
            return SetMemberAttachment(
                SwifterKitMemberPayload<SwifterKitAudioMemberAttachment>(payload, payloadLength));
        default:
            return kIOReturnUnsupported;
    }
}

kern_return_t SwifterKitRuntimeAudioDevice::SetDeviceProperty(
    const SwifterKitAudioMemberValue* request) {
    if (request == nullptr || request->reserved != 0)
        return kIOReturnBadArgument;
    const uint64_t value = request->value;
    const bool isFlag =
        request->selector <= kSwifterKitAudioDevicePropertyCanBeDefaultSystemOutput
        || request->selector == kSwifterKitAudioDevicePropertyWantsStreamFormatsRestored;
    if ((isFlag && value > 1)
        || (!isFlag && request->selector != kSwifterKitAudioDevicePropertyPreferredStereoChannels
            && value > UINT32_MAX))
        return kIOReturnBadArgument;
    const auto low = static_cast<uint32_t>(value);
    const auto high = static_cast<uint32_t>(value >> 32U);
    switch (request->selector) {
        case kSwifterKitAudioDevicePropertyCanBeDefaultInput:
            return SetCanBeDefaultInputDevice(value != 0);
        case kSwifterKitAudioDevicePropertyCanBeDefaultOutput:
            return SetCanBeDefaultOutputDevice(value != 0);
        case kSwifterKitAudioDevicePropertyCanBeDefaultSystemOutput:
            return SetCanBeDefaultSystemOutputDevice(value != 0);
        case kSwifterKitAudioDevicePropertyInputSafetyOffset:
            return SwifterKitRequestAudioMemberChange(
                this,
                kSwifterKitAudioChangeInputSafetyOffset,
                0,
                low);
        case kSwifterKitAudioDevicePropertyOutputSafetyOffset:
            return SwifterKitRequestAudioMemberChange(
                this,
                kSwifterKitAudioChangeOutputSafetyOffset,
                0,
                low);
        case kSwifterKitAudioDevicePropertyPreferredStereoChannels:
            if (low == 0 || high == 0 || low == high)
                return kIOReturnBadArgument;
            return SetPreferredChannelsForStereo(low, high);
        case kSwifterKitAudioDevicePropertyWantsStreamFormatsRestored:
    #if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5
            SetWantsStreamFormatsRestored(value != 0);
            return kIOReturnSuccess;
    #else
            // DriverKit SDKs before 25.5 do not declare SetWantsStreamFormatsRestored.
            return kIOReturnUnsupported;
    #endif
        default:
            return kIOReturnBadArgument;
    }
}

kern_return_t SwifterKitRuntimeAudioDevice::CopyStreamState(
    const SwifterKitAudioMemberRequest* request,
    OSData** response) {
    if (request == nullptr || request->reserved != 0
        || request->identifier >= kSwifterKitAudioStreamCount)
        return kIOReturnBadArgument;
    auto* stream = ivars->streams[request->identifier];
    if (stream == nullptr)
        return kIOReturnNotReady;
    IOUserAudioStreamBasicDescription formats[kSwifterKitAudioMaximumStreamFormats];
    const size_t available = stream->GetNumberAvailableStreamFormats();
    const auto count = static_cast<uint32_t>(stream->GetAvailableStreamFormats(
        formats,
        available < kSwifterKitAudioMaximumStreamFormats ? available
                                                         : kSwifterKitAudioMaximumStreamFormats));
    uint64_t memoryLength = 0;
    const OSSharedPtr<IOMemoryDescriptor> memory = stream->GetIOMemoryDescriptor();
    if (memory && memory->GetLength(&memoryLength) != kIOReturnSuccess)
        memoryLength = 0;
    const SwifterKitAudioStreamState state = {
        stream->GetObjectID(),
        static_cast<uint32_t>(stream->GetStreamDirection()),
        static_cast<uint32_t>(stream->GetTerminalType()),
        stream->GetStartingChannel(),
        stream->GetLatency(),
        stream->GetStreamIsActive() ? 1U : 0U,
        ivars->streamDetached[request->identifier] ? 0U : 1U,
        count > kSwifterKitAudioMaximumStreamFormats ? kSwifterKitAudioMaximumStreamFormats : count,
        memoryLength};
    SwifterKitAudioStreamFormat wire[kSwifterKitAudioMaximumStreamFormats + 1] = {
        WireFormat(stream->GetCurrentStreamFormat())};
    for (uint32_t index = 0; index < state.formatCount; ++index)
        wire[index + 1] = WireFormat(formats[index]);
    OSData* data = OSData::withCapacity(sizeof(state) + (state.formatCount + 1) * sizeof(wire[0]));
    if (data == nullptr)
        return kIOReturnNoMemory;
    if (!data->appendBytes(&state, sizeof(state))
        || !data->appendBytes(wire, (state.formatCount + 1) * sizeof(wire[0]))) {
        data->release();
        return kIOReturnNoMemory;
    }
    *response = data;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeAudioDevice::SetStreamProperty(
    const SwifterKitAudioMemberProperty* request) {
    if (request == nullptr || request->identifier >= kSwifterKitAudioStreamCount)
        return kIOReturnBadArgument;
    const uint32_t index = request->identifier;
    auto* stream = ivars->streams[index];
    if (stream == nullptr)
        return kIOReturnNotReady;
    const uint64_t value = request->value;
    if (value > UINT32_MAX
        || (request->selector == kSwifterKitAudioStreamPropertyIsActive && value > 1))
        return kIOReturnBadArgument;
    const auto word = static_cast<uint32_t>(value);
    switch (request->selector) {
        case kSwifterKitAudioStreamPropertyIsActive:
            return stream->SetStreamIsActive(word != 0);
        case kSwifterKitAudioStreamPropertyLatency:
            return stream->SetLatency(word);
        case kSwifterKitAudioStreamPropertyStartingChannel:
            return word == 0 ? kIOReturnBadArgument : stream->SetStartingChannel(word);
        case kSwifterKitAudioStreamPropertyTerminalType:
            return stream->SetTerminalType(static_cast<IOUserAudioStreamTerminalType>(word));
        case kSwifterKitAudioStreamPropertyCurrentFormat: {
            IOUserAudioStreamBasicDescription formats[kSwifterKitAudioMaximumStreamFormats];
            const size_t count =
                stream->GetAvailableStreamFormats(formats, kSwifterKitAudioMaximumStreamFormats);
            return word < count ? stream->SetCurrentStreamFormat(&formats[word])
                                : kIOReturnBadArgument;
        }
        case kSwifterKitAudioStreamPropertyRingBufferFrameCapacity:
            return ResizeStreamMemory(index, word);
        default:
            return kIOReturnBadArgument;
    }
}

kern_return_t SwifterKitRuntimeAudioDevice::ResizeStreamMemory(uint32_t index, uint32_t frames) {
    if (frames < kSwifterKitAudioZeroTimestampPeriod || frames > kSwifterKitAudioMaximumFrameCount
        || RingBufferBytes(index, frames) == 0)
        return kIOReturnBadArgument;
    // IOUserAudioStream.iig: SetIOMemoryDescriptor belongs in PerformDeviceConfigurationChange.
    uint64_t expected = 0;
    const uint64_t pending = static_cast<uint64_t>(index) << 32U | frames;
    if (!__atomic_compare_exchange_n(
            &ivars->pendingRingBuffer,
            &expected,
            pending,
            false,
            __ATOMIC_ACQ_REL,
            __ATOMIC_ACQUIRE))
        return kIOReturnBusy;
    const kern_return_t result =
        RequestDeviceConfigurationChange(kSwifterKitAudioRingBufferChangeAction, nullptr);
    if (result != kIOReturnSuccess)
        __atomic_store_n(&ivars->pendingRingBuffer, 0, __ATOMIC_RELEASE);
    return result;
}

kern_return_t SwifterKitRuntimeAudioDevice::ApplyRingBufferChange() {
    const uint64_t pending = __atomic_exchange_n(&ivars->pendingRingBuffer, 0, __ATOMIC_ACQ_REL);
    const auto index = static_cast<uint32_t>(pending >> 32U);
    const uint64_t size = RingBufferBytes(index, static_cast<uint32_t>(pending));
    if (pending == 0 || size == 0 || ivars->streams[index] == nullptr)
        return kIOReturnBadArgument;
    IOBufferMemoryDescriptor* descriptor = nullptr;
    IOMemoryMap* map = nullptr;
    kern_return_t result =
        IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut, size, 0, &descriptor);
    if (result == kIOReturnSuccess)
        result = descriptor->CreateMapping(0, 0, 0, size, 0, &map);
    if (result == kIOReturnSuccess)
        result = ivars->streams[index]->SetIOMemoryDescriptor(descriptor);
    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(map);
        OSSafeReleaseNULL(descriptor);
        return result;
    }
    // Only the swap is locked. No AudioDriverKit call runs under ringLock.
    IOLockLock(ivars->ringLock);
    const IOMemoryMap* oldMap = ivars->maps[index];
    const IOBufferMemoryDescriptor* oldDescriptor = ivars->descriptors[index];
    ivars->maps[index] = map;
    ivars->descriptors[index] = descriptor;
    IOLockUnlock(ivars->ringLock);
    OSSafeReleaseNULL(oldMap);
    OSSafeReleaseNULL(oldDescriptor);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeAudioDevice::ReadStream(
    const SwifterKitAudioTransferHeader* transfer,
    OSData** response) {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    IOLockLock(ivars->ringLock);
    const kern_return_t result = ReadMappedStream(transfer, response);
    IOLockUnlock(ivars->ringLock);
    return result;
}

kern_return_t SwifterKitRuntimeAudioDevice::WriteStream(
    const SwifterKitAudioTransferHeader* transfer,
    const uint8_t* bytes) {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    IOLockLock(ivars->ringLock);
    const kern_return_t result = WriteMappedStream(transfer, bytes);
    IOLockUnlock(ivars->ringLock);
    return result;
}

kern_return_t SwifterKitRuntimeAudioDevice::CopyControlInfo(
    const SwifterKitAudioMemberRequest* request,
    OSData** response) {
    if (request == nullptr || request->reserved != 0)
        return kIOReturnBadArgument;
    return SwifterKitCopyControlInfo<AudioMemberFamily>(
        ivars,
        request->identifier,
        response,
        [](SwifterKitAudioControlInfo&, IOUserAudioControl*) {});
}

kern_return_t SwifterKitRuntimeAudioDevice::SetControlProperty(
    const SwifterKitAudioMemberProperty* request) {
    return SwifterKitSetControlProperty<AudioMemberFamily>(ivars, request);
}

kern_return_t SwifterKitRuntimeAudioDevice::RemoveSelectorItems(
    const SwifterKitAudioSelectorRemoval* request,
    const uint32_t* values) {
    return SwifterKitRemoveSelectorItems<AudioMemberFamily>(
        ivars,
        request->identifier,
        request->count,
        reinterpret_cast<const uint8_t*>(values));
}

kern_return_t SwifterKitRuntimeAudioDevice::SetMemberAttachment(
    const SwifterKitAudioMemberAttachment* request) {
    if (request == nullptr || request->reserved != 0
        || request->owner > kSwifterKitAudioOwnerDriver)
        return kIOReturnBadArgument;
    const bool attach = request->owner != kSwifterKitAudioOwnerDetached;
    uint32_t index = request->identifier;
    if (request->kind == kSwifterKitAudioMemberStream) {
        if (index >= kSwifterKitAudioStreamCount || request->owner == kSwifterKitAudioOwnerDriver)
            return kIOReturnBadArgument;
        if (ivars->streams[index] == nullptr)
            return kIOReturnNotReady;
        if (ivars->streamDetached[index] != attach)
            return kIOReturnSuccess;
        return SwifterKitRequestAudioMemberChange(
            this,
            kSwifterKitAudioChangeStreamAttachment,
            index,
            attach ? 1 : 0);
    }
    if (request->kind == kSwifterKitAudioMemberControl) {
        if (request->owner == kSwifterKitAudioOwnerDriver)
            return kIOReturnBadArgument;
        if (SwifterKitFindMemberControl<AudioMemberFamily>(ivars, request->identifier, &index)
            == nullptr)
            return kIOReturnNotFound;
        if (ivars->controlDetached[index] != attach)
            return kIOReturnSuccess;
        const kern_return_t result =
            attach ? AddControl(ivars->controls[index]) : RemoveControl(ivars->controls[index]);
        if (result == kIOReturnSuccess)
            ivars->controlDetached[index] = !attach;
        return result;
    }
    if (request->kind != kSwifterKitAudioMemberCustomProperty)
        return kIOReturnBadArgument;
    if (SwifterKitFindByIdentifier(
            kSwifterKitAudioCustomProperties,
            kSwifterKitAudioCustomPropertyCount,
            request->identifier,
            &index)
            == nullptr
        || ivars->customProperties[index] == nullptr)
        return kIOReturnNotFound;
    const uint8_t current = ivars->propertyPlacement[index];
    const uint8_t wanted = request->owner == kSwifterKitAudioOwnerDevice   ? kPlacementDevice
                           : request->owner == kSwifterKitAudioOwnerDriver ? kPlacementDriver
                                                                           : kPlacementDetached;
    if (current == wanted)
        return kIOReturnSuccess;
    if (current != kPlacementDetached && wanted != kPlacementDetached)
        return kIOReturnBusy;
    auto* property = ivars->customProperties[index];
    auto* driver = static_cast<IOUserAudioDriver*>(ivars->service);
    const uint8_t owner = wanted == kPlacementDetached ? current : wanted;
    kern_return_t result = kIOReturnSuccess;
    if (owner == kPlacementDevice)
        result = attach ? AddCustomProperty(property) : RemoveCustomProperty(property);
    else
        result =
            attach ? driver->AddCustomProperty(property) : driver->RemoveCustomProperty(property);
    if (result == kIOReturnSuccess)
        ivars->propertyPlacement[index] = wanted;
    return result;
}
kern_return_t SwifterKitRuntimeAudioDevice::ApplyMemberChange(OSObject* changeInfo) {
    SwifterKitAudioMemberChange change = {};
    if (!SwifterKitReadAudioMemberChange(changeInfo, &change))
        return kIOReturnBadArgument;
    return SwifterKitApplyStructureChange<AudioMemberFamily>(this, ivars, change);
}
#endif
