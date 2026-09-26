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
    constexpr uint64_t kMaximumRingBufferBytes = 16'777'216;

    template<typename Type>
    const Type* Payload(const uint8_t* payload, uint32_t payloadLength) {
        return payload != nullptr && payloadLength == sizeof(Type)
                   ? reinterpret_cast<const Type*>(payload)
                   : nullptr;
    }

    bool FindControl(uint32_t identifier, uint32_t* index) {
        for (uint32_t candidate = 0; candidate < kSwifterKitAudioControlCount; ++candidate)
            if (kSwifterKitAudioControls[candidate].identifier == identifier) {
                *index = candidate;
                return true;
            }
        return false;
    }

    bool FindProperty(uint32_t identifier, uint32_t* index) {
        for (uint32_t candidate = 0; candidate < kSwifterKitAudioCustomPropertyCount; ++candidate)
            if (kSwifterKitAudioCustomProperties[candidate].identifier == identifier) {
                *index = candidate;
                return true;
            }
        return false;
    }

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

    kern_return_t Respond(const void* bytes, uint32_t length, OSData** response) {
        OSData* data = OSData::withBytes(bytes, length);
        if (data == nullptr)
            return kIOReturnNoMemory;
        *response = data;
        return kIOReturnSuccess;
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
        if (ivars->propertyPlacement[index] == kPlacementDevice)
            (void)RemoveCustomProperty(property);
        else if (ivars->propertyPlacement[index] == kPlacementDriver)
            (void)static_cast<IOUserAudioDriver*>(ivars->service)->RemoveCustomProperty(property);
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
        case SwifterKitRuntimeOpcode::AudioGetDeviceState: {
            if (payloadLength != 0)
                return kIOReturnBadArgument;
            SwifterKitAudioDeviceState state = {};
            state.objectID = GetObjectID();
            state.canBeDefaultInput = CanBeDefaultInputDevice() != 0 ? 1 : 0;
            state.canBeDefaultOutput = CanBeDefaultOutputDevice() != 0 ? 1 : 0;
            state.canBeDefaultSystemOutput = CanBeDefaultSystemOutputDevice() != 0 ? 1 : 0;
            state.inputSafetyOffset = GetInputSafetyOffset();
            state.outputSafetyOffset = GetOutputSafetyOffset();
            uint32_t left = 0;
            uint32_t right = 0;
            uint64_t times[4] = {};
            GetPreferredChannelsForStereo(&left, &right);
            GetCurrentClientIOTime(true, &times[0], &times[1]);
            GetCurrentClientIOTime(false, &times[2], &times[3]);
            state.preferredLeft = left;
            state.preferredRight = right;
            state.inputSampleTime = times[0];
            state.inputHostTime = times[1];
            state.outputSampleTime = times[2];
            state.outputHostTime = times[3];
            return Respond(&state, sizeof(state), response);
        }
        case SwifterKitRuntimeOpcode::AudioSetDeviceProperty:
            return SetDeviceProperty(Payload<SwifterKitAudioMemberValue>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::AudioSetPreferredChannelLayout: {
            if (payload == nullptr || payloadLength < sizeof(SwifterKitAudioChannelLayoutHeader))
                return kIOReturnBadArgument;
            const auto* header =
                reinterpret_cast<const SwifterKitAudioChannelLayoutHeader*>(payload);
            if (header->isInput > 1 || header->count == 0
                || header->count > kSwifterKitAudioMaximumChannelLabels
                || payloadLength != sizeof(*header) + header->count * sizeof(uint32_t))
                return kIOReturnBadArgument;
            IOUserAudioChannelLabel labels[kSwifterKitAudioMaximumChannelLabels] = {};
            for (uint32_t index = 0; index < header->count; ++index) {
                uint32_t label = 0;
                memcpy(&label, payload + sizeof(*header) + index * sizeof(label), sizeof(label));
                labels[index] = static_cast<IOUserAudioChannelLabel>(label);
            }
            return header->isInput != 0 ? SetPreferredInputChannelLayout(labels, header->count)
                                        : SetPreferredOutputChannelLayout(labels, header->count);
        }
        case SwifterKitRuntimeOpcode::AudioGetStreamState:
            return CopyStreamState(
                Payload<SwifterKitAudioMemberRequest>(payload, payloadLength),
                response);
        case SwifterKitRuntimeOpcode::AudioSetStreamProperty:
            return SetStreamProperty(
                Payload<SwifterKitAudioMemberProperty>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::AudioGetControlInfo:
            return CopyControlInfo(
                Payload<SwifterKitAudioMemberRequest>(payload, payloadLength),
                response);
        case SwifterKitRuntimeOpcode::AudioSetControlProperty:
            return SetControlProperty(
                Payload<SwifterKitAudioMemberProperty>(payload, payloadLength));
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
            const auto* request = Payload<SwifterKitAudioMemberRequest>(payload, payloadLength);
            uint32_t index = 0;
            if (request == nullptr || request->reserved != 0)
                return kIOReturnBadArgument;
            if (!FindProperty(request->identifier, &index)
                || ivars->customProperties[index] == nullptr)
                return kIOReturnNotFound;
            auto* property = ivars->customProperties[index];
            const IOUserAudioCustomPropertyInfo info = property->GetCustomPropertyInfo();
            const SwifterKitAudioCustomPropertyInfo wire = {
                property->GetObjectID(),
                static_cast<uint32_t>(info.mSelector),
                static_cast<uint32_t>(info.mPropertyDataType),
                static_cast<uint32_t>(info.mQualifierDataType),
                WireOwner(ivars->propertyPlacement[index]),
                0};
            return Respond(&wire, sizeof(wire), response);
        }
        case SwifterKitRuntimeOpcode::AudioSetMemberAttachment:
            return SetMemberAttachment(
                Payload<SwifterKitAudioMemberAttachment>(payload, payloadLength));
        default:
            return kIOReturnUnsupported;
    }
}

kern_return_t SwifterKitRuntimeAudioDevice::SetDeviceProperty(
    const SwifterKitAudioMemberValue* request) {
    if (request == nullptr || request->reserved != 0)
        return kIOReturnBadArgument;
    const uint64_t value = request->value;
    const bool isFlag = request->selector <= 3 || request->selector == 7;
    if ((isFlag && value > 1) || (!isFlag && request->selector != 6 && value > UINT32_MAX))
        return kIOReturnBadArgument;
    const auto low = static_cast<uint32_t>(value);
    const auto high = static_cast<uint32_t>(value >> 32);
    switch (request->selector) {
        case 1:
            return SetCanBeDefaultInputDevice(value != 0);
        case 2:
            return SetCanBeDefaultOutputDevice(value != 0);
        case 3:
            return SetCanBeDefaultSystemOutputDevice(value != 0);
        case 4:
            return SetInputSafetyOffset(low);
        case 5:
            return SetOutputSafetyOffset(low);
        case 6:
            if (low == 0 || high == 0 || low == high)
                return kIOReturnBadArgument;
            return SetPreferredChannelsForStereo(low, high);
        case 7:
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
    IOUserAudioStreamBasicDescription formats[16] = {};
    const size_t available = stream->GetNumberAvailableStreamFormats();
    const auto count = static_cast<uint32_t>(
        stream->GetAvailableStreamFormats(formats, available < 16 ? available : 16));
    uint64_t memoryLength = 0;
    OSSharedPtr<IOMemoryDescriptor> memory = stream->GetIOMemoryDescriptor();
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
        count > 16 ? 16 : count,
        memoryLength};
    SwifterKitAudioStreamFormat wire[17] = {WireFormat(stream->GetCurrentStreamFormat())};
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
    if (value > UINT32_MAX || (request->selector == 1 && value > 1))
        return kIOReturnBadArgument;
    const auto word = static_cast<uint32_t>(value);
    switch (request->selector) {
        case 1:
            return stream->SetStreamIsActive(word != 0);
        case 2:
            return stream->SetLatency(word);
        case 3:
            return word == 0 ? kIOReturnBadArgument : stream->SetStartingChannel(word);
        case 4:
            return stream->SetTerminalType(static_cast<IOUserAudioStreamTerminalType>(word));
        case 5: {
            IOUserAudioStreamBasicDescription formats[16] = {};
            const size_t count = stream->GetAvailableStreamFormats(formats, 16);
            return word < count ? stream->SetCurrentStreamFormat(&formats[word])
                                : kIOReturnBadArgument;
        }
        case 6:
            return ResizeStreamMemory(index, word);
        default:
            return kIOReturnBadArgument;
    }
}

kern_return_t SwifterKitRuntimeAudioDevice::ResizeStreamMemory(uint32_t index, uint32_t frames) {
    if (frames < kSwifterKitAudioZeroTimestampPeriod || frames > 1'048'576)
        return kIOReturnBadArgument;
    const auto& config = kSwifterKitAudioStreams[index];
    uint32_t bytesPerFrame = 0;
    for (uint32_t format = 0; format < config.formatCount; ++format) {
        const uint32_t candidate =
            kSwifterKitAudioFormats[config.formatStart + format].bytesPerFrame;
        bytesPerFrame = candidate > bytesPerFrame ? candidate : bytesPerFrame;
    }
    const uint64_t size = static_cast<uint64_t>(bytesPerFrame) * frames;
    if (size == 0 || size > kMaximumRingBufferBytes)
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
    OSSafeReleaseNULL(ivars->maps[index]);
    OSSafeReleaseNULL(ivars->descriptors[index]);
    ivars->maps[index] = map;
    ivars->descriptors[index] = descriptor;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeAudioDevice::CopyControlInfo(
    const SwifterKitAudioMemberRequest* request,
    OSData** response) {
    uint32_t index = 0;
    if (request == nullptr || request->reserved != 0)
        return kIOReturnBadArgument;
    if (!FindControl(request->identifier, &index) || ivars->controls[index] == nullptr)
        return kIOReturnNotFound;
    auto* control = ivars->controls[index];
    SwifterKitAudioControlInfo info = {};
    info.objectID = control->GetObjectID();
    info.kind = kSwifterKitAudioControls[index].kind;
    info.scope = static_cast<uint32_t>(control->GetControlScope());
    info.element = static_cast<uint32_t>(control->GetControlElement());
    info.isSettable = control->GetIsSettable() ? 1 : 0;
    info.isAttached = ivars->controlDetached[index] ? 0 : 1;
    if (auto* slider = OSDynamicCast(IOUserAudioSliderControl, control)) {
        const IOUserAudioSliderRange range = slider->GetRange();
        info.sliderMinimum = range.m_min;
        info.sliderMaximum = range.m_max;
    }
    if (auto* pan = OSDynamicCast(IOUserAudioStereoPanControl, control)) {
        IOUserAudioObjectPropertyElement left = 0;
        IOUserAudioObjectPropertyElement right = 0;
        pan->GetPanningChannels(&left, &right);
        info.panLeft = left;
        info.panRight = right;
    }
    IOUserAudioSelectorValueDescription items[kSwifterKitAudioMaximumSelectorItems] = {};
    if (auto* selector = OSDynamicCast(IOUserAudioSelectorControl, control)) {
        const size_t count = selector->GetControlValuesCount();
        info.itemCount = static_cast<uint32_t>(selector->GetControlValueDescriptions(
            items,
            count < kSwifterKitAudioMaximumSelectorItems ? count
                                                         : kSwifterKitAudioMaximumSelectorItems));
    }
    OSData* data = OSData::withCapacity(sizeof(info) + info.itemCount * (8 + 255));
    bool appended = data != nullptr && data->appendBytes(&info, sizeof(info));
    for (uint32_t item = 0; appended && item < info.itemCount; ++item) {
        const char* name = items[item].m_name ? items[item].m_name->getCStringNoCopy() : "";
        const size_t length = strnlen(name, 256);
        const uint32_t header[2] = {items[item].m_value, static_cast<uint32_t>(length)};
        appended = length <= 255 && data->appendBytes(header, sizeof(header))
                   && data->appendBytes(name, length);
    }
    if (!appended) {
        OSSafeReleaseNULL(data);
        return kIOReturnNoMemory;
    }
    *response = data;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeAudioDevice::SetControlProperty(
    const SwifterKitAudioMemberProperty* request) {
    uint32_t index = 0;
    if (request == nullptr)
        return kIOReturnBadArgument;
    if (!FindControl(request->identifier, &index) || ivars->controls[index] == nullptr)
        return kIOReturnNotFound;
    const auto low = static_cast<uint32_t>(request->value);
    const auto high = static_cast<uint32_t>(request->value >> 32);
    auto* control = ivars->controls[index];
    if (request->selector == 1) {
        auto* slider = OSDynamicCast(IOUserAudioSliderControl, control);
        if (slider == nullptr || low > high)
            return kIOReturnBadArgument;
        return slider->SetRange(IOUserAudioSliderRange {low, high});
    }
    if (request->selector == 2) {
        auto* pan = OSDynamicCast(IOUserAudioStereoPanControl, control);
        if (pan == nullptr || low == high)
            return kIOReturnBadArgument;
        return pan->SetPanningChannels(low, high);
    }
    return kIOReturnBadArgument;
}

kern_return_t SwifterKitRuntimeAudioDevice::RemoveSelectorItems(
    const SwifterKitAudioSelectorRemoval* request,
    const uint32_t* values) {
    uint32_t index = 0;
    if (!FindControl(request->identifier, &index) || ivars->controls[index] == nullptr)
        return kIOReturnNotFound;
    auto* selector = OSDynamicCast(IOUserAudioSelectorControl, ivars->controls[index]);
    if (selector == nullptr)
        return kIOReturnBadArgument;
    IOUserAudioSelectorValueDescription items[kSwifterKitAudioMaximumSelectorItems] = {};
    const size_t available =
        selector->GetControlValueDescriptions(items, kSwifterKitAudioMaximumSelectorItems);
    IOUserAudioSelectorValueDescription removed[kSwifterKitAudioMaximumSelectorItems] = {};
    for (uint32_t value = 0; value < request->count; ++value) {
        uint32_t wanted = 0;
        memcpy(&wanted, values + value, sizeof(wanted));
        size_t match = available;
        for (size_t item = 0; item < available; ++item)
            if (items[item].m_value == wanted)
                match = item;
        if (match == available)
            return kIOReturnNotFound;
        removed[value] = items[match];
    }
    return selector->RemoveControlValueDescriptions(removed, request->count);
}

kern_return_t SwifterKitRuntimeAudioDevice::SetMemberAttachment(
    const SwifterKitAudioMemberAttachment* request) {
    if (request == nullptr || request->reserved != 0
        || request->owner > kSwifterKitAudioOwnerDriver)
        return kIOReturnBadArgument;
    const bool attach = request->owner != kSwifterKitAudioOwnerDetached;
    uint32_t index = request->identifier;
    if (request->kind == 1) {
        if (index >= kSwifterKitAudioStreamCount || request->owner == kSwifterKitAudioOwnerDriver)
            return kIOReturnBadArgument;
        if (ivars->streams[index] == nullptr)
            return kIOReturnNotReady;
        if (ivars->streamDetached[index] != attach)
            return kIOReturnSuccess;
        const kern_return_t result =
            attach ? AddStream(ivars->streams[index]) : RemoveStream(ivars->streams[index]);
        if (result == kIOReturnSuccess)
            ivars->streamDetached[index] = !attach;
        return result;
    }
    if (request->kind == 2) {
        if (request->owner == kSwifterKitAudioOwnerDriver)
            return kIOReturnBadArgument;
        if (!FindControl(request->identifier, &index) || ivars->controls[index] == nullptr)
            return kIOReturnNotFound;
        if (ivars->controlDetached[index] != attach)
            return kIOReturnSuccess;
        const kern_return_t result =
            attach ? AddControl(ivars->controls[index]) : RemoveControl(ivars->controls[index]);
        if (result == kIOReturnSuccess)
            ivars->controlDetached[index] = !attach;
        return result;
    }
    if (request->kind != 3)
        return kIOReturnBadArgument;
    if (!FindProperty(request->identifier, &index) || ivars->customProperties[index] == nullptr)
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
#endif
