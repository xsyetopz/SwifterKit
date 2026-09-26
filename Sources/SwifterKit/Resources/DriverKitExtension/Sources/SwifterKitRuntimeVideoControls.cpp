#include "SwifterKitRuntimeVideoDevice.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeVideoBooleanControl.h"
    #include "SwifterKitRuntimeVideoCustomProperty.h"
    #include "SwifterKitRuntimeVideoDeviceState.h"
    #include "SwifterKitRuntimeVideoDirectionControl.h"
    #include "SwifterKitRuntimeVideoLevelControl.h"
    #include "SwifterKitRuntimeVideoProtocol.h"
    #include "SwifterKitRuntimeVideoSelectorControl.h"
    #include "SwifterKitRuntimeVideoSliderControl.h"
    #include "SwifterKitRuntimeVideoStereoPanControl.h"

namespace {
    const SwifterKitVideoControlConfiguration* FindControl(uint32_t identifier, uint32_t* index) {
        for (uint32_t candidate = 0; candidate < kSwifterKitVideoControlCount; ++candidate) {
            if (kSwifterKitVideoControls[candidate].identifier == identifier) {
                *index = candidate;
                return &kSwifterKitVideoControls[candidate];
            }
        }
        return nullptr;
    }

    const SwifterKitVideoCustomPropertyConfiguration* FindProperty(
        uint32_t identifier,
        uint32_t* index) {
        for (uint32_t candidate = 0; candidate < kSwifterKitVideoCustomPropertyCount; ++candidate) {
            if (kSwifterKitVideoCustomProperties[candidate].identifier == identifier) {
                *index = candidate;
                return &kSwifterKitVideoCustomProperties[candidate];
            }
        }
        return nullptr;
    }

    float FloatValue(uint32_t bits) {
        return __builtin_bit_cast(float, bits);
    }

    OSString* StringFromBytes(const uint8_t* bytes, uint32_t length, uint32_t maximum) {
        if (bytes == nullptr || length > maximum)
            return nullptr;
        char storage[kSwifterKitVideoCustomPropertyValueMaximumLength + 1] = {};
        memcpy(storage, bytes, length);
        return OSString::withCString(storage);
    }
}  // namespace

kern_return_t SwifterKitRuntimeVideoDevice::ConfigureControls() {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    kern_return_t result = kIOReturnSuccess;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitVideoControlCount;
         ++index) {
        const auto& config = kSwifterKitVideoControls[index];
        IOUserVideoControl* control = nullptr;
        const auto scope = static_cast<IOUserVideoObjectPropertyScope>(config.scope);
        const auto classID = static_cast<IOUserVideoClassID>(config.classID);
        switch (config.kind) {
            case kSwifterKitVideoControlBoolean: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeVideoBooleanControl);
                if (typed != nullptr
                    && !typed->init(
                        ivars->service,
                        ivars->service,
                        config.identifier,
                        config.isSettable,
                        config.value != 0,
                        config.element,
                        scope,
                        classID))
                    OSSafeReleaseNULL(typed);
                control = typed;
                break;
            }
            case kSwifterKitVideoControlDirection: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeVideoDirectionControl);
                if (typed != nullptr
                    && !typed->init(
                        ivars->service,
                        ivars->service,
                        config.identifier,
                        config.isSettable,
                        config.value != 0,
                        config.element,
                        scope,
                        classID))
                    OSSafeReleaseNULL(typed);
                control = typed;
                break;
            }
            case kSwifterKitVideoControlLevel: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeVideoLevelControl);
                if (typed != nullptr
                    && !typed->init(
                        ivars->service,
                        ivars->service,
                        config.identifier,
                        config.isSettable,
                        FloatValue(config.value),
                        {FloatValue(config.minimum), FloatValue(config.maximum)},
                        config.element,
                        scope,
                        classID))
                    OSSafeReleaseNULL(typed);
                control = typed;
                break;
            }
            case kSwifterKitVideoControlSelector: {
                auto* selector = OSTypeAlloc(SwifterKitRuntimeVideoSelectorControl);
                if (selector != nullptr
                    && !selector->init(
                        ivars->service,
                        ivars->service,
                        config.identifier,
                        config.isSettable,
                        config.element,
                        scope,
                        classID))
                    OSSafeReleaseNULL(selector);
                control = selector;
                IOUserVideoSelectorValueDescription
                    descriptions[kSwifterKitVideoMaximumSelectorItems] = {};
                for (uint32_t item = 0; selector != nullptr && item < config.selectorCount;
                     ++item) {
                    const auto& source = kSwifterKitVideoSelectors[config.selectorStart + item];
                    descriptions[item].m_value = source.value;
                    descriptions[item].m_name =
                        OSSharedPtr(OSString::withCString(source.name), OSNoRetain);
                    if (descriptions[item].m_name.get() == nullptr)
                        result = kIOReturnNoMemory;
                }
                if (result == kIOReturnSuccess && selector != nullptr)
                    result =
                        selector->AddControlValueDescriptions(descriptions, config.selectorCount);
                if (result == kIOReturnSuccess && selector != nullptr)
                    result = selector->SetCurrentSelectedValues(
                        &kSwifterKitVideoInitialSelections[config.initialStart],
                        config.initialCount);
                break;
            }
            case kSwifterKitVideoControlSlider: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeVideoSliderControl);
                if (typed != nullptr
                    && !typed->init(
                        ivars->service,
                        ivars->service,
                        config.identifier,
                        config.isSettable,
                        config.value,
                        {config.minimum, config.maximum},
                        config.element,
                        scope,
                        classID))
                    OSSafeReleaseNULL(typed);
                control = typed;
                break;
            }
            case kSwifterKitVideoControlStereoPan: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeVideoStereoPanControl);
                if (typed != nullptr
                    && !typed->init(
                        ivars->service,
                        ivars->service,
                        config.identifier,
                        config.isSettable,
                        FloatValue(config.value),
                        config.auxiliary0,
                        config.auxiliary1,
                        config.element,
                        scope,
                        classID))
                    OSSafeReleaseNULL(typed);
                control = typed;
                break;
            }
            default:
                result = kIOReturnBadArgument;
                break;
        }
        if (result == kIOReturnSuccess && control == nullptr)
            result = kIOReturnNoMemory;
        OSString* name = result == kIOReturnSuccess ? OSString::withCString(config.name) : nullptr;
        if (result == kIOReturnSuccess)
            result = name == nullptr ? kIOReturnNoMemory : control->SetName(name);
        OSSafeReleaseNULL(name);
        // IOUserVideoControl.iig documents _SetOwningDeviceID only as "Sets the control's owning
        // device" and says nothing about AddControl setting it, so the owner is set explicitly
        // before the control becomes visible.
        if (result == kIOReturnSuccess)
            control->_SetOwningDeviceID(GetObjectID());
        if (result == kIOReturnSuccess)
            result = AddControl(control);
        if (result == kIOReturnSuccess)
            ivars->controls[index] = control;
        else
            OSSafeReleaseNULL(control);
    }

    for (uint32_t index = 0;
         result == kIOReturnSuccess && index < kSwifterKitVideoCustomPropertyCount;
         ++index) {
        const auto& config = kSwifterKitVideoCustomProperties[index];
        IOUserVideoObjectPropertyAddress address = {
            config.selector,
            static_cast<IOUserVideoObjectPropertyScope>(config.scope),
            config.element};
        auto* property = OSTypeAlloc(SwifterKitRuntimeVideoCustomProperty);
        if (property != nullptr
            && !property->init(
                ivars->service,
                ivars->service,
                config.identifier,
                address,
                config.isSettable,
                IOUserVideoCustomPropertyDataType::String,
                IOUserVideoCustomPropertyDataType::String))
            OSSafeReleaseNULL(property);
        if (property == nullptr)
            result = kIOReturnNoMemory;
        for (uint32_t item = 0; result == kIOReturnSuccess && item < config.valueCount; ++item) {
            const auto& source = kSwifterKitVideoCustomPropertyValues[config.valueStart + item];
            OSString* qualifier = OSString::withCString(source.qualifier);
            OSString* value = OSString::withCString(source.value);
            result = qualifier == nullptr || value == nullptr
                         ? kIOReturnNoMemory
                         : property->SetQualifierAndDataValue(qualifier, value);
            OSSafeReleaseNULL(qualifier);
            OSSafeReleaseNULL(value);
        }
        if (result == kIOReturnSuccess)
            result = AddCustomProperty(property);
        if (result == kIOReturnSuccess) {
            ivars->customProperties[index] = property;
            ivars->customPropertyOwners[index] = kSwifterKitVideoOwnerDevice;
        } else
            OSSafeReleaseNULL(property);
    }
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyControl(
    const SwifterKitVideoControlGet* request,
    OSData** response) {
    if (request == nullptr || response == nullptr || ivars == nullptr)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = FindControl(request->identifier, &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    uint32_t values[kSwifterKitVideoMaximumSelectorItems] = {};
    uint32_t count = 1;
    auto* control = ivars->controls[index];
    switch (request->kind) {
        case kSwifterKitVideoValueBoolean: {
            auto* typed = OSDynamicCast(IOUserVideoBooleanControl, control);
            if (config->kind != kSwifterKitVideoControlBoolean || typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = typed->GetControlValue() ? 1 : 0;
            break;
        }
        case kSwifterKitVideoValueDirection: {
            auto* typed = OSDynamicCast(IOUserVideoDirectionControl, control);
            if (config->kind != kSwifterKitVideoControlDirection || typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = typed->GetControlValue() ? 1 : 0;
            break;
        }
        case kSwifterKitVideoValueDecibels:
        case kSwifterKitVideoValueScalar: {
            auto* typed = OSDynamicCast(IOUserVideoLevelControl, control);
            if (config->kind != kSwifterKitVideoControlLevel || typed == nullptr)
                return kIOReturnBadArgument;
            const float value = request->kind == kSwifterKitVideoValueDecibels
                                    ? typed->GetDecibelValue()
                                    : typed->GetScalarValue();
            values[0] = __builtin_bit_cast(uint32_t, value);
            break;
        }
        case kSwifterKitVideoValueSelector: {
            auto* typed = OSDynamicCast(IOUserVideoSelectorControl, control);
            if (config->kind != kSwifterKitVideoControlSelector || typed == nullptr)
                return kIOReturnBadArgument;
            count = static_cast<uint32_t>(
                typed->GetCurrentSelectedValues(values, kSwifterKitVideoMaximumSelectorItems));
            if (count == 0 || count > kSwifterKitVideoMaximumSelectorItems)
                return kIOReturnError;
            break;
        }
        case kSwifterKitVideoValueSlider: {
            auto* typed = OSDynamicCast(IOUserVideoSliderControl, control);
            if (config->kind != kSwifterKitVideoControlSlider || typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = typed->GetControlValue();
            break;
        }
        case kSwifterKitVideoValueStereoPan: {
            auto* typed = OSDynamicCast(IOUserVideoStereoPanControl, control);
            if (config->kind != kSwifterKitVideoControlStereoPan || typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = __builtin_bit_cast(uint32_t, typed->GetControlValue());
            break;
        }
        default:
            return kIOReturnBadArgument;
    }
    const SwifterKitVideoControlValueHeader header = {request->identifier, request->kind, count, 0};
    OSData* data = OSData::withCapacity(sizeof(header) + count * sizeof(uint32_t));
    if (data == nullptr)
        return kIOReturnNoMemory;
    const bool appended = data->appendBytes(&header, sizeof(header))
                          && data->appendBytes(values, count * sizeof(uint32_t));
    if (!appended) {
        data->release();
        return kIOReturnNoMemory;
    }
    *response = data;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeVideoDevice::SetControl(
    const SwifterKitVideoControlValueHeader* request,
    const uint32_t* values) {
    if (request == nullptr || values == nullptr || request->reserved != 0
        || request->valueCount == 0 || request->valueCount > kSwifterKitVideoMaximumSelectorItems
        || ivars == nullptr)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = FindControl(request->identifier, &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    if (!config->isSettable)
        return kIOReturnNotPermitted;
    auto* control = ivars->controls[index];
    switch (request->kind) {
        case kSwifterKitVideoValueBoolean: {
            auto* typed = OSDynamicCast(IOUserVideoBooleanControl, control);
            return config->kind == kSwifterKitVideoControlBoolean && typed != nullptr
                           && request->valueCount == 1 && values[0] <= 1
                       ? typed->SetControlValue(values[0] != 0)
                       : kIOReturnBadArgument;
        }
        case kSwifterKitVideoValueDirection: {
            auto* typed = OSDynamicCast(IOUserVideoDirectionControl, control);
            return config->kind == kSwifterKitVideoControlDirection && typed != nullptr
                           && request->valueCount == 1 && values[0] <= 1
                       ? typed->SetControlValue(values[0] != 0)
                       : kIOReturnBadArgument;
        }
        case kSwifterKitVideoValueDecibels:
        case kSwifterKitVideoValueScalar: {
            auto* typed = OSDynamicCast(IOUserVideoLevelControl, control);
            if (config->kind != kSwifterKitVideoControlLevel || typed == nullptr
                || request->valueCount != 1)
                return kIOReturnBadArgument;
            const float value = FloatValue(values[0]);
            if (!__builtin_isfinite(value))
                return kIOReturnBadArgument;
            if (request->kind == kSwifterKitVideoValueDecibels) {
                if (value < FloatValue(config->minimum) || value > FloatValue(config->maximum))
                    return kIOReturnBadArgument;
                return typed->SetDecibelValue(value);
            }
            return value >= 0 && value <= 1 ? typed->SetScalarValue(value) : kIOReturnBadArgument;
        }
        case kSwifterKitVideoValueSelector: {
            auto* typed = OSDynamicCast(IOUserVideoSelectorControl, control);
            if (config->kind != kSwifterKitVideoControlSelector || typed == nullptr)
                return kIOReturnBadArgument;
            for (uint32_t item = 0; item < request->valueCount; ++item) {
                bool found = false;
                for (uint32_t candidate = 0; candidate < config->selectorCount; ++candidate)
                    found = found
                            || values[item]
                                   == kSwifterKitVideoSelectors[config->selectorStart + candidate]
                                          .value;
                if (!found)
                    return kIOReturnBadArgument;
                for (uint32_t prior = 0; prior < item; ++prior)
                    if (values[prior] == values[item])
                        return kIOReturnBadArgument;
            }
            return typed->SetCurrentSelectedValues(values, request->valueCount);
        }
        case kSwifterKitVideoValueSlider: {
            auto* typed = OSDynamicCast(IOUserVideoSliderControl, control);
            return config->kind == kSwifterKitVideoControlSlider && typed != nullptr
                           && request->valueCount == 1 && values[0] >= config->minimum
                           && values[0] <= config->maximum
                       ? typed->SetControlValue(values[0])
                       : kIOReturnBadArgument;
        }
        case kSwifterKitVideoValueStereoPan: {
            auto* typed = OSDynamicCast(IOUserVideoStereoPanControl, control);
            const float value = FloatValue(values[0]);
            return config->kind == kSwifterKitVideoControlStereoPan && typed != nullptr
                           && request->valueCount == 1 && __builtin_isfinite(value) && value >= -1
                           && value <= 1
                       ? typed->SetControlValue(value)
                       : kIOReturnBadArgument;
        }
        default:
            return kIOReturnBadArgument;
    }
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyCustomProperty(
    const SwifterKitVideoCustomPropertyHeader* request,
    const uint8_t* bytes,
    OSData** response) {
    if (request == nullptr || response == nullptr || request->reserved != 0
        || request->valueLength != 0 || request->qualifierLength == 0)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    if (FindProperty(request->identifier, &index) == nullptr)
        return kIOReturnNotFound;
    OSString* qualifier =
        StringFromBytes(bytes, request->qualifierLength, kSwifterKitVideoNameMaximumLength);
    OSObject* output = nullptr;
    kern_return_t result =
        qualifier == nullptr ? kIOReturnBadArgument
                             : ivars->customProperties[index]->GetCustomPropertyValueWithQualifier(
                                   qualifier,
                                   &output);
    auto* string = OSDynamicCast(OSString, output);
    if (result == kIOReturnSuccess
        && (string == nullptr
            || string->getLength() > kSwifterKitVideoCustomPropertyValueMaximumLength))
        result = kIOReturnBadArgument;
    if (result == kIOReturnSuccess) {
        *response = OSData::withBytes(string->getCStringNoCopy(), string->getLength());
        if (*response == nullptr)
            result = kIOReturnNoMemory;
    }
    OSSafeReleaseNULL(output);
    OSSafeReleaseNULL(qualifier);
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::SetCustomProperty(
    const SwifterKitVideoCustomPropertyHeader* request,
    const uint8_t* bytes) {
    if (request == nullptr || request->reserved != 0 || request->qualifierLength == 0
        || request->valueLength > kSwifterKitVideoCustomPropertyValueMaximumLength)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = FindProperty(request->identifier, &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    if (!config->isSettable)
        return kIOReturnNotPermitted;
    OSString* qualifier =
        StringFromBytes(bytes, request->qualifierLength, kSwifterKitVideoNameMaximumLength);
    OSString* value = StringFromBytes(
        bytes + request->qualifierLength,
        request->valueLength,
        kSwifterKitVideoCustomPropertyValueMaximumLength);
    const kern_return_t result =
        qualifier == nullptr || value == nullptr
            ? kIOReturnBadArgument
            : ivars->customProperties[index]->SetQualifierAndDataValue(qualifier, value);
    OSSafeReleaseNULL(value);
    OSSafeReleaseNULL(qualifier);
    return result;
}
kern_return_t SwifterKitRuntimeVideoDevice::SetCustomPropertyOwner(
    uint32_t identifier,
    uint32_t owner) {
    if (ivars == nullptr || identifier == 0 || owner > kSwifterKitVideoOwnerDriver)
        return kIOReturnBadArgument;
    for (uint32_t index = 0; index < kSwifterKitVideoCustomPropertyCount; ++index) {
        IOUserVideoCustomProperty* property = ivars->customProperties[index];
        if (kSwifterKitVideoCustomProperties[index].identifier != identifier)
            continue;
        if (property == nullptr)
            return kIOReturnNotReady;
        uint8_t& current = ivars->customPropertyOwners[index];
        if (current == owner)
            return kIOReturnSuccess;
        // A property moves between owners only through the detached state.
        if (current != kSwifterKitVideoOwnerDetached && owner != kSwifterKitVideoOwnerDetached)
            return kIOReturnBusy;
        kern_return_t result = kIOReturnSuccess;
        if (owner == kSwifterKitVideoOwnerDevice)
            result = AddCustomProperty(property);
        else if (owner == kSwifterKitVideoOwnerDriver)
            result = ivars->service->AddCustomProperty(property);
        else if (current == kSwifterKitVideoOwnerDevice)
            result = RemoveCustomProperty(property);
        else
            result = ivars->service->RemoveCustomProperty(property);
        if (result == kIOReturnSuccess)
            current = static_cast<uint8_t>(owner);
        return result;
    }
    return kIOReturnNotFound;
}

void SwifterKitRuntimeVideoDevice::RemoveControlsAndProperties() {
    if (ivars == nullptr)
        return;
    for (uint32_t index = 0; index < kSwifterKitVideoControlCount; ++index)
        if (ivars->controls[index] != nullptr && !ivars->controlDetached[index]) {
            (void)RemoveControl(ivars->controls[index]);
            ivars->controlDetached[index] = true;
        }
    for (uint32_t index = 0; index < kSwifterKitVideoCustomPropertyCount; ++index)
        (void)SetCustomPropertyOwner(
            kSwifterKitVideoCustomProperties[index].identifier,
            kSwifterKitVideoOwnerDetached);
}
#endif
