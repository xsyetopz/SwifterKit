#ifndef SwifterKitRuntimeMediaMembers_h
#define SwifterKitRuntimeMediaMembers_h

// Device member-command and service device-command plumbing shared by the audio and video
// runtimes.
// The member templates take a per-file family struct that names that family's control classes,
// wire structs, and schema tables (see SwifterKitRuntimeAudioMembers.cpp and
// SwifterKitRuntimeVideoMembers.cpp).
// The service templates take one that names the family's opcodes and event headers (see
// SwifterKitRuntimeAudio.cpp and SwifterKitRuntimeVideo.cpp).
// Like SwifterKitRuntimeMediaControls.h, this header includes neither framework.
// Callers validate each request's reserved fields and hold the family lock. These templates call
// only the device.

#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSString.h>
#include <string.h>

#include "SwifterKitRuntimeMediaObjects.h"

// A fixed-size request in place, or null when the length does not match exactly.
template<typename Type>
const Type* SwifterKitMemberPayload(const uint8_t* payload, uint32_t payloadLength) {
    return payload != nullptr && payloadLength == sizeof(Type)
               ? reinterpret_cast<const Type*>(payload)
               : nullptr;
}

// A variable-length request's header in place, or null when the payload is shorter than it.
template<typename Header>
const Header* SwifterKitMemberHeader(const uint8_t* payload, uint32_t payloadLength) {
    return payload != nullptr && payloadLength >= sizeof(Header)
               ? reinterpret_cast<const Header*>(payload)
               : nullptr;
}

template<typename Family, typename Device>
kern_return_t SwifterKitCopyDeviceState(Device* device, OSData** response) {
    typename Family::DeviceState state = {};
    state.objectID = device->GetObjectID();
    state.canBeDefaultInput = device->CanBeDefaultInputDevice() != 0 ? 1 : 0;
    state.canBeDefaultOutput = device->CanBeDefaultOutputDevice() != 0 ? 1 : 0;
    state.canBeDefaultSystemOutput = device->CanBeDefaultSystemOutputDevice() != 0 ? 1 : 0;
    state.inputSafetyOffset = device->GetInputSafetyOffset();
    state.outputSafetyOffset = device->GetOutputSafetyOffset();
    uint32_t left = 0;
    uint32_t right = 0;
    uint64_t times[4] = {};
    device->GetPreferredChannelsForStereo(&left, &right);
    device->GetCurrentClientIOTime(true, &times[0], &times[1]);
    device->GetCurrentClientIOTime(false, &times[2], &times[3]);
    state.preferredLeft = left;
    state.preferredRight = right;
    state.inputSampleTime = times[0];
    state.inputHostTime = times[1];
    state.outputSampleTime = times[2];
    state.outputHostTime = times[3];
    return SwifterKitBytesResponse(&state, sizeof(state), response);
}

// Validates a channel-layout header and its label words, then sets the input or output layout.
template<typename Family, typename Device>
kern_return_t SwifterKitSetPreferredChannelLayout(
    Device* device,
    const uint8_t* payload,
    uint32_t payloadLength) {
    const auto* header =
        SwifterKitMemberHeader<typename Family::ChannelLayoutHeader>(payload, payloadLength);
    if (header == nullptr || header->isInput > 1 || header->count == 0
        || header->count > Family::kMaximumChannelLabels
        || payloadLength != sizeof(*header) + header->count * sizeof(uint32_t))
        return kIOReturnBadArgument;
    typename Family::ChannelLabel labels[Family::kMaximumChannelLabels] = {};
    for (uint32_t index = 0; index < header->count; ++index) {
        uint32_t label = 0;
        memcpy(&label, payload + sizeof(*header) + index * sizeof(label), sizeof(label));
        labels[index] = static_cast<typename Family::ChannelLabel>(label);
    }
    return header->isInput != 0 ? device->SetPreferredInputChannelLayout(labels, header->count)
                                : device->SetPreferredOutputChannelLayout(labels, header->count);
}

// The configured control the host names by `identifier`, or null when there is none.
template<typename Family, typename IVars>
auto* SwifterKitFindMemberControl(IVars* ivars, uint32_t identifier, uint32_t* index) {
    return SwifterKitFindByIdentifier(Family::kControls, Family::kControlCount, identifier, index)
                   != nullptr
               ? ivars->controls[*index]
               : nullptr;
}

// Replies with the control's info and selector items. `describe(info, control)` fills the fields
// only one family has.
template<typename Family, typename IVars, typename Describe>
kern_return_t SwifterKitCopyControlInfo(
    IVars* ivars,
    uint32_t identifier,
    OSData** response,
    Describe describe) {
    uint32_t index = 0;
    auto* control = SwifterKitFindMemberControl<Family>(ivars, identifier, &index);
    if (control == nullptr)
        return kIOReturnNotFound;
    typename Family::ControlInfo info = {};
    info.objectID = control->GetObjectID();
    info.kind = Family::kControls[index].kind;
    info.scope = static_cast<uint32_t>(control->GetControlScope());
    info.element = static_cast<uint32_t>(control->GetControlElement());
    info.isSettable = control->GetIsSettable() ? 1 : 0;
    info.isAttached = ivars->controlDetached[index] ? 0 : 1;
    describe(info, control);
    if (auto* slider = SwifterKitDynamicCast<typename Family::SliderControl>(control)) {
        const typename Family::SliderRange range = slider->GetRange();
        info.sliderMinimum = range.m_min;
        info.sliderMaximum = range.m_max;
    }
    if (auto* pan = SwifterKitDynamicCast<typename Family::StereoPanControl>(control)) {
        typename Family::PropertyElement left = 0;
        typename Family::PropertyElement right = 0;
        pan->GetPanningChannels(&left, &right);
        info.panLeft = left;
        info.panRight = right;
    }
    constexpr uint32_t kItems = Family::kMaximumSelectorItems;
    typename Family::SelectorDescription items[kItems] = {};
    if (auto* selector = SwifterKitDynamicCast<typename Family::SelectorControl>(control)) {
        const size_t count = selector->GetControlValuesCount();
        info.itemCount = static_cast<uint32_t>(
            selector->GetControlValueDescriptions(items, count < kItems ? count : kItems));
    }
    OSData* data =
        OSData::withCapacity(sizeof(info) + info.itemCount * (8 + Family::kNameMaximumLength));
    bool appended = data != nullptr && data->appendBytes(&info, sizeof(info));
    for (uint32_t item = 0; appended && item < info.itemCount; ++item) {
        const char* name = items[item].m_name ? items[item].m_name->getCStringNoCopy() : "";
        const size_t length = strnlen(name, Family::kNameMaximumLength + 1);
        const uint32_t header[2] = {items[item].m_value, static_cast<uint32_t>(length)};
        appended = length <= Family::kNameMaximumLength && data->appendBytes(header, sizeof(header))
                   && data->appendBytes(name, length);
    }
    if (!appended) {
        OSSafeReleaseNULL(data);
        return kIOReturnNoMemory;
    }
    *response = data;
    return kIOReturnSuccess;
}

template<typename Family, typename IVars, typename Request>
kern_return_t SwifterKitSetControlProperty(IVars* ivars, const Request* request) {
    uint32_t index = 0;
    if (request == nullptr)
        return kIOReturnBadArgument;
    const auto* control = SwifterKitFindMemberControl<Family>(ivars, request->identifier, &index);
    if (control == nullptr)
        return kIOReturnNotFound;
    const auto low = static_cast<uint32_t>(request->value);
    const auto high = static_cast<uint32_t>(request->value >> 32U);
    if (request->selector == Family::kControlPropertySliderRange) {
        auto* slider = SwifterKitDynamicCast<typename Family::SliderControl>(control);
        if (slider == nullptr || low > high)
            return kIOReturnBadArgument;
        return slider->SetRange(typename Family::SliderRange {low, high});
    }
    if (request->selector == Family::kControlPropertyPanningChannels) {
        auto* pan = SwifterKitDynamicCast<typename Family::StereoPanControl>(control);
        if (pan == nullptr || low == high)
            return kIOReturnBadArgument;
        return pan->SetPanningChannels(low, high);
    }
    return kIOReturnBadArgument;
}

// Removes the selector items whose values are the `count` 32-bit words at `values`, which need
// not be aligned. Every value must name an item.
template<typename Family, typename IVars>
kern_return_t SwifterKitRemoveSelectorItems(
    IVars* ivars,
    uint32_t identifier,
    uint32_t count,
    const uint8_t* values) {
    uint32_t index = 0;
    const auto* control = SwifterKitFindMemberControl<Family>(ivars, identifier, &index);
    if (control == nullptr)
        return kIOReturnNotFound;
    auto* selector = SwifterKitDynamicCast<typename Family::SelectorControl>(control);
    if (selector == nullptr)
        return kIOReturnBadArgument;
    constexpr uint32_t kItems = Family::kMaximumSelectorItems;
    typename Family::SelectorDescription items[kItems] = {};
    const size_t available = selector->GetControlValueDescriptions(items, kItems);
    typename Family::SelectorDescription removed[kItems] = {};
    for (uint32_t value = 0; value < count; ++value) {
        uint32_t wanted = 0;
        memcpy(&wanted, values + value * sizeof(wanted), sizeof(wanted));
        size_t match = available;
        for (size_t item = 0; item < available; ++item)
            if (items[item].m_value == wanted)
                match = item;
        if (match == available)
            return kIOReturnNotFound;
        removed[value] = items[match];
    }
    return selector->RemoveControlValueDescriptions(removed, count);
}

// Replies with the custom property's info. `owner(index)` gives the wire owner.
template<typename Family, typename IVars, typename Owner>
kern_return_t SwifterKitCopyCustomPropertyInfo(
    IVars* ivars,
    uint32_t identifier,
    Owner owner,
    OSData** response) {
    uint32_t index = 0;
    if (SwifterKitFindByIdentifier(
            Family::kCustomProperties,
            Family::kCustomPropertyCount,
            identifier,
            &index)
            == nullptr
        || ivars->customProperties[index] == nullptr)
        return kIOReturnNotFound;
    auto* property = ivars->customProperties[index];
    const auto info = property->GetCustomPropertyInfo();
    const typename Family::CustomPropertyInfo wire = {
        property->GetObjectID(),
        static_cast<uint32_t>(info.mSelector),
        static_cast<uint32_t>(info.mPropertyDataType),
        static_cast<uint32_t>(info.mQualifierDataType),
        owner(index),
        0};
    return SwifterKitBytesResponse(&wire, sizeof(wire), response);
}

// Applies a stream-attachment or safety-offset change inside PerformDeviceConfigurationChange,
// where IOUserAudioDevice.iig and IOUserVideoDevice.iig allow AddStream, RemoveStream, and the
// safety-offset setters.
template<typename Family, typename Device, typename IVars, typename Change>
kern_return_t SwifterKitApplyStructureChange(Device* device, IVars* ivars, const Change& change) {
    if (change.value > UINT32_MAX)
        return kIOReturnBadArgument;
    const auto value = static_cast<uint32_t>(change.value);
    switch (change.selector) {
        case Family::kChangeStreamAttachment: {
            if (change.index >= Family::kStreamCount || value > 1
                || ivars->streams[change.index] == nullptr)
                return kIOReturnBadArgument;
            const bool attach = value != 0;
            if (ivars->streamDetached[change.index] != attach)
                return kIOReturnSuccess;
            auto* stream = ivars->streams[change.index];
            const kern_return_t result =
                attach ? device->AddStream(stream) : device->RemoveStream(stream);
            if (result == kIOReturnSuccess)
                ivars->streamDetached[change.index] = !attach;
            return result;
        }
        case Family::kChangeInputSafetyOffset:
            return device->SetInputSafetyOffset(value);
        case Family::kChangeOutputSafetyOffset:
            return device->SetOutputSafetyOffset(value);
        default:
            return kIOReturnBadArgument;
    }
}

// Builds a control-value event and hands it to `enqueue(bytes, length)`, which must deliver it.
template<typename Family, typename Enqueue>
kern_return_t SwifterKitEnqueueControlValueEvent(
    uint32_t identifier,
    uint32_t kind,
    const uint32_t* values,
    uint32_t count,
    Enqueue enqueue) {
    using Header = typename Family::ControlEventHeader;
    constexpr uint32_t kItems = Family::kMaximumSelectorItems;
    if (identifier == 0 || kind < Family::kValueFirst || kind > Family::kValueLast
        || values == nullptr || count == 0 || count > kItems
        || (kind != Family::kValueSelector && count != 1))
        return kIOReturnBadArgument;
    uint8_t payload[sizeof(Header) + kItems * sizeof(uint32_t)] = {};
    const Header header = {Family::kEventControlChanged, identifier, kind, count, 0};
    memcpy(payload, &header, sizeof(header));
    memcpy(payload + sizeof(header), values, count * sizeof(uint32_t));
    return enqueue(payload, sizeof(header) + count * sizeof(uint32_t));
}

// Builds a custom-property event and hands it to `enqueue(bytes, length)`, which must deliver it.
template<typename Family, typename Enqueue>
kern_return_t SwifterKitEnqueueCustomPropertyEvent(
    uint32_t identifier,
    const uint8_t* qualifier,
    uint32_t qualifierLength,
    const uint8_t* value,
    uint32_t valueLength,
    Enqueue enqueue) {
    using Header = typename Family::CustomPropertyEventHeader;
    constexpr uint32_t kQualifier = Family::kNameMaximumLength;
    constexpr uint32_t kValue = Family::kCustomPropertyValueMaximumLength;
    if (identifier == 0 || qualifier == nullptr || qualifierLength == 0
        || qualifierLength > kQualifier || value == nullptr || valueLength > kValue)
        return kIOReturnBadArgument;
    uint8_t payload[sizeof(Header) + kQualifier + kValue] = {};
    const Header header =
        {Family::kEventCustomPropertyChanged, identifier, qualifierLength, valueLength, 0};
    memcpy(payload, &header, sizeof(header));
    memcpy(payload + sizeof(header), qualifier, qualifierLength);
    memcpy(payload + sizeof(header) + qualifierLength, value, valueLength);
    return enqueue(payload, sizeof(header) + qualifierLength + valueLength);
}

// The device commands both families share: timestamps, sample-rate requests, control values, and
// custom properties. The caller holds the family lock. Any other opcode is unsupported.
template<typename Family, typename Device>
kern_return_t SwifterKitDeviceCommand(
    Device* device,
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (opcode == Family::kUpdateTimestamp) {
        const auto* timestamp =
            SwifterKitMemberPayload<typename Family::Timestamp>(payload, payloadLength);
        return timestamp != nullptr ? device->UpdateTimestamp(timestamp) : kIOReturnBadArgument;
    }
    if (opcode == Family::kRequestSampleRate) {
        if (payload == nullptr || payloadLength != sizeof(uint64_t))
            return kIOReturnBadArgument;
        uint64_t bits = 0;
        memcpy(&bits, payload, sizeof(bits));
        return device->RequestSampleRate(__builtin_bit_cast(double, bits));
    }
    if (opcode == Family::kGetControl) {
        const auto* request =
            SwifterKitMemberPayload<typename Family::ControlGet>(payload, payloadLength);
        return request != nullptr ? device->CopyControl(request, response) : kIOReturnBadArgument;
    }
    if (opcode == Family::kSetControl) {
        const auto* request =
            SwifterKitMemberHeader<typename Family::ControlValueHeader>(payload, payloadLength);
        if (request == nullptr)
            return kIOReturnBadArgument;
        const uint64_t expected =
            sizeof(*request) + static_cast<uint64_t>(request->valueCount) * sizeof(uint32_t);
        return expected == payloadLength
                   ? device->SetControl(
                         request,
                         reinterpret_cast<const uint32_t*>(payload + sizeof(*request)))
                   : kIOReturnBadArgument;
    }
    if (opcode != Family::kGetCustomProperty && opcode != Family::kSetCustomProperty)
        return kIOReturnUnsupported;
    const auto* request =
        SwifterKitMemberHeader<typename Family::CustomPropertyHeader>(payload, payloadLength);
    if (request == nullptr)
        return kIOReturnBadArgument;
    const uint64_t expected =
        sizeof(*request) + static_cast<uint64_t>(request->qualifierLength) + request->valueLength;
    if (expected != payloadLength)
        return kIOReturnBadArgument;
    if (opcode == Family::kGetCustomProperty)
        return device->CopyCustomProperty(request, payload + sizeof(*request), response);
    return device->SetCustomProperty(request, payload + sizeof(*request));
}

#endif
