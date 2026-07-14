#include "SwifterKitRuntimeAudioDevice.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioBooleanControl.h"
    #include "SwifterKitRuntimeAudioCustomProperty.h"
    #include "SwifterKitRuntimeAudioDeviceState.h"
    #include "SwifterKitRuntimeAudioLevelControl.h"
    #include "SwifterKitRuntimeAudioSelectorControl.h"
    #include "SwifterKitRuntimeAudioSliderControl.h"
    #include "SwifterKitRuntimeAudioStereoPanControl.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"

namespace {
    const SwifterKitAudioControlConfiguration* FindControl(uint32_t identifier, uint32_t* index) {
        for (uint32_t candidate = 0; candidate < kSwifterKitAudioControlCount; ++candidate) {
            if (kSwifterKitAudioControls[candidate].identifier == identifier) {
                *index = candidate;
                return &kSwifterKitAudioControls[candidate];
            }
        }
        return nullptr;
    }

    const SwifterKitAudioCustomPropertyConfiguration* FindProperty(
        uint32_t identifier,
        uint32_t* index) {
        for (uint32_t candidate = 0; candidate < kSwifterKitAudioCustomPropertyCount; ++candidate) {
            if (kSwifterKitAudioCustomProperties[candidate].identifier == identifier) {
                *index = candidate;
                return &kSwifterKitAudioCustomProperties[candidate];
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
        char storage[4097] = {};
        memcpy(storage, bytes, length);
        return OSString::withCString(storage);
    }
}  // namespace

kern_return_t SwifterKitRuntimeAudioDevice::ConfigureControls() {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    kern_return_t result = kIOReturnSuccess;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitAudioControlCount;
         ++index) {
        const auto& config = kSwifterKitAudioControls[index];
        IOUserAudioControl* control = nullptr;
        const auto scope = static_cast<IOUserAudioObjectPropertyScope>(config.scope);
        const auto classID = static_cast<IOUserAudioClassID>(config.classID);
        switch (config.kind) {
            case 1: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeAudioBooleanControl);
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
            case 2: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeAudioLevelControl);
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
            case 3: {
                auto* selector = OSTypeAlloc(SwifterKitRuntimeAudioSelectorControl);
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
                IOUserAudioSelectorValueDescription descriptions[32] = {};
                for (uint32_t item = 0; selector != nullptr && item < config.selectorCount;
                     ++item) {
                    const auto& source = kSwifterKitAudioSelectors[config.selectorStart + item];
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
                        &kSwifterKitAudioInitialSelections[config.initialStart],
                        config.initialCount);
                break;
            }
            case 4: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeAudioSliderControl);
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
            case 5: {
                auto* typed = OSTypeAlloc(SwifterKitRuntimeAudioStereoPanControl);
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
        if (result == kIOReturnSuccess)
            result = AddControl(control);
        if (result == kIOReturnSuccess)
            ivars->controls[index] = control;
        else
            OSSafeReleaseNULL(control);
    }

    for (uint32_t index = 0;
         result == kIOReturnSuccess && index < kSwifterKitAudioCustomPropertyCount;
         ++index) {
        const auto& config = kSwifterKitAudioCustomProperties[index];
        IOUserAudioObjectPropertyAddress address = {
            config.selector,
            static_cast<IOUserAudioObjectPropertyScope>(config.scope),
            config.element};
        auto* property = OSTypeAlloc(SwifterKitRuntimeAudioCustomProperty);
        if (property != nullptr
            && !property->init(
                ivars->service,
                ivars->service,
                config.identifier,
                address,
                config.isSettable,
                IOUserAudioCustomPropertyDataType::String,
                IOUserAudioCustomPropertyDataType::String))
            OSSafeReleaseNULL(property);
        if (property == nullptr)
            result = kIOReturnNoMemory;
        for (uint32_t item = 0; result == kIOReturnSuccess && item < config.valueCount; ++item) {
            const auto& source = kSwifterKitAudioCustomPropertyValues[config.valueStart + item];
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
        if (result == kIOReturnSuccess)
            ivars->customProperties[index] = property;
        else
            OSSafeReleaseNULL(property);
    }
    return result;
}

kern_return_t SwifterKitRuntimeAudioDevice::CopyControl(
    const SwifterKitAudioControlGet* request,
    OSData** response) {
    if (request == nullptr || response == nullptr || ivars == nullptr)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = FindControl(request->identifier, &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    uint32_t values[32] = {};
    uint32_t count = 1;
    auto* control = ivars->controls[index];
    switch (request->kind) {
        case 1: {
            auto* typed = OSDynamicCast(IOUserAudioBooleanControl, control);
            if (config->kind != 1 || typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = typed->GetControlValue() ? 1 : 0;
            break;
        }
        case 2:
        case 3: {
            auto* typed = OSDynamicCast(IOUserAudioLevelControl, control);
            if (config->kind != 2 || typed == nullptr)
                return kIOReturnBadArgument;
            const float value =
                request->kind == 2 ? typed->GetDecibelValue() : typed->GetScalarValue();
            values[0] = __builtin_bit_cast(uint32_t, value);
            break;
        }
        case 4: {
            auto* typed = OSDynamicCast(IOUserAudioSelectorControl, control);
            if (config->kind != 3 || typed == nullptr)
                return kIOReturnBadArgument;
            count = static_cast<uint32_t>(typed->GetCurrentSelectedValues(values, 32));
            if (count == 0 || count > 32)
                return kIOReturnError;
            break;
        }
        case 5: {
            auto* typed = OSDynamicCast(IOUserAudioSliderControl, control);
            if (config->kind != 4 || typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = typed->GetControlValue();
            break;
        }
        case 6: {
            auto* typed = OSDynamicCast(IOUserAudioStereoPanControl, control);
            if (config->kind != 5 || typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = __builtin_bit_cast(uint32_t, typed->GetControlValue());
            break;
        }
        default:
            return kIOReturnBadArgument;
    }
    const SwifterKitAudioControlValueHeader header = {request->identifier, request->kind, count, 0};
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

kern_return_t SwifterKitRuntimeAudioDevice::SetControl(
    const SwifterKitAudioControlValueHeader* request,
    const uint32_t* values) {
    if (request == nullptr || values == nullptr || request->reserved != 0
        || request->valueCount == 0 || request->valueCount > 32 || ivars == nullptr)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = FindControl(request->identifier, &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    if (!config->isSettable)
        return kIOReturnNotPermitted;
    auto* control = ivars->controls[index];
    switch (request->kind) {
        case 1: {
            auto* typed = OSDynamicCast(IOUserAudioBooleanControl, control);
            return config->kind == 1 && typed != nullptr && request->valueCount == 1
                           && values[0] <= 1
                       ? typed->SetControlValue(values[0] != 0)
                       : kIOReturnBadArgument;
        }
        case 2:
        case 3: {
            auto* typed = OSDynamicCast(IOUserAudioLevelControl, control);
            if (config->kind != 2 || typed == nullptr || request->valueCount != 1)
                return kIOReturnBadArgument;
            const float value = FloatValue(values[0]);
            if (!__builtin_isfinite(value))
                return kIOReturnBadArgument;
            if (request->kind == 2) {
                if (value < FloatValue(config->minimum) || value > FloatValue(config->maximum))
                    return kIOReturnBadArgument;
                return typed->SetDecibelValue(value);
            }
            return value >= 0 && value <= 1 ? typed->SetScalarValue(value) : kIOReturnBadArgument;
        }
        case 4: {
            auto* typed = OSDynamicCast(IOUserAudioSelectorControl, control);
            if (config->kind != 3 || typed == nullptr)
                return kIOReturnBadArgument;
            for (uint32_t item = 0; item < request->valueCount; ++item) {
                bool found = false;
                for (uint32_t candidate = 0; candidate < config->selectorCount; ++candidate)
                    found = found
                            || values[item]
                                   == kSwifterKitAudioSelectors[config->selectorStart + candidate]
                                          .value;
                if (!found)
                    return kIOReturnBadArgument;
                for (uint32_t prior = 0; prior < item; ++prior)
                    if (values[prior] == values[item])
                        return kIOReturnBadArgument;
            }
            return typed->SetCurrentSelectedValues(values, request->valueCount);
        }
        case 5: {
            auto* typed = OSDynamicCast(IOUserAudioSliderControl, control);
            return config->kind == 4 && typed != nullptr && request->valueCount == 1
                           && values[0] >= config->minimum && values[0] <= config->maximum
                       ? typed->SetControlValue(values[0])
                       : kIOReturnBadArgument;
        }
        case 6: {
            auto* typed = OSDynamicCast(IOUserAudioStereoPanControl, control);
            const float value = FloatValue(values[0]);
            return config->kind == 5 && typed != nullptr && request->valueCount == 1
                           && __builtin_isfinite(value) && value >= -1 && value <= 1
                       ? typed->SetControlValue(value)
                       : kIOReturnBadArgument;
        }
        default:
            return kIOReturnBadArgument;
    }
}

kern_return_t SwifterKitRuntimeAudioDevice::CopyCustomProperty(
    const SwifterKitAudioCustomPropertyHeader* request,
    const uint8_t* bytes,
    OSData** response) {
    if (request == nullptr || response == nullptr || request->reserved != 0
        || request->valueLength != 0 || request->qualifierLength == 0)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    if (FindProperty(request->identifier, &index) == nullptr)
        return kIOReturnNotFound;
    OSString* qualifier = StringFromBytes(bytes, request->qualifierLength, 255);
    OSObject* output = nullptr;
    kern_return_t result =
        qualifier == nullptr ? kIOReturnBadArgument
                             : ivars->customProperties[index]->GetCustomPropertyValueWithQualifier(
                                   qualifier,
                                   &output);
    auto* string = OSDynamicCast(OSString, output);
    if (result == kIOReturnSuccess && (string == nullptr || string->getLength() > 4096))
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

kern_return_t SwifterKitRuntimeAudioDevice::SetCustomProperty(
    const SwifterKitAudioCustomPropertyHeader* request,
    const uint8_t* bytes) {
    if (request == nullptr || request->reserved != 0 || request->qualifierLength == 0
        || request->valueLength > 4096)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = FindProperty(request->identifier, &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    if (!config->isSettable)
        return kIOReturnNotPermitted;
    OSString* qualifier = StringFromBytes(bytes, request->qualifierLength, 255);
    OSString* value = StringFromBytes(bytes + request->qualifierLength, request->valueLength, 4096);
    const kern_return_t result =
        qualifier == nullptr || value == nullptr
            ? kIOReturnBadArgument
            : ivars->customProperties[index]->SetQualifierAndDataValue(qualifier, value);
    OSSafeReleaseNULL(value);
    OSSafeReleaseNULL(qualifier);
    return result;
}
#endif
