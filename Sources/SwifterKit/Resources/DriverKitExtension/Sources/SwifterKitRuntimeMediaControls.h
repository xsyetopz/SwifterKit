#ifndef SwifterKitRuntimeMediaControls_h
#define SwifterKitRuntimeMediaControls_h

// Control and custom-property plumbing shared by the audio and video runtimes. AudioDriverKit and
// VideoDriverKit declare parallel control classes, so the templates here take a family struct that
// names that family's classes and schema tables (see SwifterKitRuntimeAudioControls.cpp and
// SwifterKitRuntimeVideoControls.cpp). This header includes neither framework: the audio runtime
// builds against SDKs without VideoDriverKit, and the video runtime builds without audio.

#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSString.h>
#include <string.h>

#include "SwifterKitRuntimeService.h"

// OSTypeAlloc and OSDynamicCast paste the class name into g<Name>MetaClass unless the SDK is built
// with DRIVERKIT_FIX_OSTYPEID, so they cannot take a template parameter. IIG gives every class the
// sGetMetaClass() that the fixed OSTypeID uses, and these helpers reach the metaclass the same way.
template<typename Type>
Type* SwifterKitAllocate() {
    OSObject* object = nullptr;
    return OSObjectAllocate(Type::sGetMetaClass(), &object) == kIOReturnSuccess
               ? static_cast<Type*>(object)
               : nullptr;
}

template<typename Type>
Type* SwifterKitDynamicCast(const OSMetaClassBase* object) {
    return static_cast<Type*>(OSMetaClassBase::safeMetaCast(object, Type::sGetMetaClass()));
}

inline float SwifterKitFloatFromBits(uint32_t bits) {
    return __builtin_bit_cast(float, bits);
}

inline uint32_t SwifterKitBitsFromFloat(float value) {
    return __builtin_bit_cast(uint32_t, value);
}

// What every SwifterKit control and custom-property subclass keeps: the retained service that
// reports host changes, and the schema identifier the host addresses the object by.
struct SwifterKitMediaCallbackState {
    SwifterKitRuntimeService* service;
    uint32_t identifier;
};

// Allocates a subclass's ivars and retains `service`; on failure ivars stays null.
template<typename IVars>
bool SwifterKitAttachCallbackState(
    IVars*& ivars,
    SwifterKitRuntimeService* service,
    uint32_t identifier) {
    ivars = IONewZero(IVars, 1);
    if (ivars == nullptr || service == nullptr || identifier == 0) {
        IOSafeDeleteNULL(ivars, IVars, 1);
        return false;
    }
    ivars->service = service;
    ivars->identifier = identifier;
    service->retain();
    return true;
}

template<typename IVars>
void SwifterKitDetachCallbackState(IVars*& ivars) {
    if (ivars != nullptr)
        OSSafeReleaseNULL(ivars->service);
    IOSafeDeleteNULL(ivars, IVars, 1);
}

using SwifterKitCustomPropertyEvent = kern_return_t (SwifterKitRuntimeService::*)(
    uint32_t identifier,
    const uint8_t* qualifier,
    uint32_t qualifierLength,
    const uint8_t* value,
    uint32_t valueLength);

// Reports a string custom-property change through the family's service `event`.
inline kern_return_t SwifterKitReportCustomPropertyChange(
    const SwifterKitMediaCallbackState* state,
    SwifterKitCustomPropertyEvent event,
    const OSObject* qualifier,
    const OSObject* value) {
    const auto* qualifierString = OSDynamicCast(OSString, qualifier);
    const auto* valueString = OSDynamicCast(OSString, value);
    if (qualifierString == nullptr || valueString == nullptr)
        return kIOReturnBadArgument;
    return (state->service->*event)(
        state->identifier,
        reinterpret_cast<const uint8_t*>(qualifierString->getCStringNoCopy()),
        static_cast<uint32_t>(qualifierString->getLength()),
        reinterpret_cast<const uint8_t*>(valueString->getCStringNoCopy()),
        static_cast<uint32_t>(valueString->getLength()));
}

template<typename Entry>
const Entry* SwifterKitFindByIdentifier(
    const Entry* entries,
    uint32_t count,
    uint32_t identifier,
    uint32_t* index) {
    for (uint32_t candidate = 0; candidate < count; ++candidate) {
        if (entries[candidate].identifier == identifier) {
            *index = candidate;
            return &entries[candidate];
        }
    }
    return nullptr;
}

template<typename Family>
OSString* SwifterKitStringFromBytes(const uint8_t* bytes, uint32_t length, uint32_t maximum) {
    if (bytes == nullptr || length > maximum)
        return nullptr;
    char storage[Family::kCustomPropertyValueMaximumLength + 1] = {};
    memcpy(storage, bytes, length);
    return OSString::withCString(storage);
}

// Allocates and initializes a control subclass. `values` are the init arguments that differ by
// control kind, between isSettable and element.
template<typename Control, typename Family, typename Configuration, typename... Values>
Control* SwifterKitMakeControl(
    SwifterKitRuntimeService* service,
    const Configuration& config,
    Values... values) {
    auto* control = SwifterKitAllocate<Control>();
    if (control != nullptr
        && !control->init(
            service,
            service,
            config.identifier,
            config.isSettable,
            values...,
            config.element,
            static_cast<typename Family::Scope>(config.scope),
            static_cast<typename Family::ClassID>(config.classID)))
        OSSafeReleaseNULL(control);
    return control;
}

template<typename Family, typename Selector, typename Configuration>
kern_return_t SwifterKitDescribeSelector(Selector* selector, const Configuration& config) {
    kern_return_t result = kIOReturnSuccess;
    typename Family::SelectorDescription descriptions[Family::kMaximumSelectorItems] = {};
    for (uint32_t item = 0; item < config.selectorCount; ++item) {
        const auto& source = Family::kSelectors[config.selectorStart + item];
        descriptions[item].m_value = source.value;
        descriptions[item].m_name = OSSharedPtr(OSString::withCString(source.name), OSNoRetain);
        if (descriptions[item].m_name.get() == nullptr)
            result = kIOReturnNoMemory;
    }
    if (result == kIOReturnSuccess)
        result = selector->AddControlValueDescriptions(descriptions, config.selectorCount);
    if (result == kIOReturnSuccess)
        result = selector->SetCurrentSelectedValues(
            &Family::kInitialSelections[config.initialStart],
            config.initialCount);
    return result;
}

// Creates the configured control. A family with a direction control (VideoDriverKit) declares
// DirectionControl and its kinds; other families reject that kind as unknown.
template<typename Family, typename Configuration>
kern_return_t SwifterKitMakeConfiguredControl(
    SwifterKitRuntimeService* service,
    const Configuration& config,
    typename Family::Control** control) {
    switch (config.kind) {
        case Family::kControlBoolean:
            *control = SwifterKitMakeControl<typename Family::RuntimeBooleanControl, Family>(
                service,
                config,
                config.value != 0);
            return kIOReturnSuccess;
        case Family::kControlLevel:
            *control = SwifterKitMakeControl<typename Family::RuntimeLevelControl, Family>(
                service,
                config,
                SwifterKitFloatFromBits(config.value),
                typename Family::LevelRange {
                    SwifterKitFloatFromBits(config.minimum),
                    SwifterKitFloatFromBits(config.maximum)});
            return kIOReturnSuccess;
        case Family::kControlSelector: {
            auto* selector = SwifterKitMakeControl<typename Family::RuntimeSelectorControl, Family>(
                service,
                config);
            *control = selector;
            return selector == nullptr ? kIOReturnSuccess
                                       : SwifterKitDescribeSelector<Family>(selector, config);
        }
        case Family::kControlSlider:
            *control = SwifterKitMakeControl<typename Family::RuntimeSliderControl, Family>(
                service,
                config,
                config.value,
                typename Family::SliderRange {config.minimum, config.maximum});
            return kIOReturnSuccess;
        case Family::kControlStereoPan:
            *control = SwifterKitMakeControl<typename Family::RuntimeStereoPanControl, Family>(
                service,
                config,
                SwifterKitFloatFromBits(config.value),
                config.auxiliary0,
                config.auxiliary1);
            return kIOReturnSuccess;
        default:
            if constexpr (requires { typename Family::RuntimeDirectionControl; }) {
                if (config.kind == Family::kControlDirection) {
                    *control =
                        SwifterKitMakeControl<typename Family::RuntimeDirectionControl, Family>(
                            service,
                            config,
                            config.value != 0);
                    return kIOReturnSuccess;
                }
            }
            return kIOReturnBadArgument;
    }
}

// Names a newly created control, or reports why it could not be created.
template<typename Control>
kern_return_t SwifterKitNameControl(kern_return_t result, Control* control, const char* name) {
    if (result == kIOReturnSuccess && control == nullptr)
        result = kIOReturnNoMemory;
    OSString* string = result == kIOReturnSuccess ? OSString::withCString(name) : nullptr;
    if (result == kIOReturnSuccess)
        result = string == nullptr ? kIOReturnNoMemory : control->SetName(string);
    OSSafeReleaseNULL(string);
    return result;
}

// Creates a string-valued custom property holding its configured qualifier and value pairs.
template<typename Family, typename Configuration>
kern_return_t SwifterKitMakeConfiguredCustomProperty(
    SwifterKitRuntimeService* service,
    const Configuration& config,
    typename Family::RuntimeCustomProperty** property) {
    const typename Family::PropertyAddress address = {
        config.selector,
        static_cast<typename Family::Scope>(config.scope),
        config.element};
    auto* created = SwifterKitAllocate<typename Family::RuntimeCustomProperty>();
    if (created != nullptr
        && !created->init(
            service,
            service,
            config.identifier,
            address,
            config.isSettable,
            Family::CustomPropertyDataType::String,
            Family::CustomPropertyDataType::String))
        OSSafeReleaseNULL(created);
    *property = created;
    kern_return_t result = created == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    for (uint32_t item = 0; result == kIOReturnSuccess && item < config.valueCount; ++item) {
        const auto& source = Family::kCustomPropertyValues[config.valueStart + item];
        OSString* qualifier = OSString::withCString(source.qualifier);
        OSString* value = OSString::withCString(source.value);
        result = qualifier == nullptr || value == nullptr
                     ? kIOReturnNoMemory
                     : created->SetQualifierAndDataValue(qualifier, value);
        OSSafeReleaseNULL(qualifier);
        OSSafeReleaseNULL(value);
    }
    return result;
}

// Casts `control` when its configuration has `kind`; null otherwise.
template<typename Typed, typename Control, typename Configuration>
Typed* SwifterKitControlOfKind(Control* control, const Configuration& config, uint32_t kind) {
    auto* typed = SwifterKitDynamicCast<Typed>(control);
    return config.kind == kind ? typed : nullptr;
}

template<typename Family, typename Configuration>
kern_return_t SwifterKitReadControlValues(
    typename Family::Control* control,
    const Configuration& config,
    uint32_t kind,
    uint32_t* values,
    uint32_t* count) {
    switch (kind) {
        case Family::kValueBoolean: {
            auto* typed = SwifterKitControlOfKind<typename Family::BooleanControl>(
                control,
                config,
                Family::kControlBoolean);
            if (typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = typed->GetControlValue() ? 1 : 0;
            return kIOReturnSuccess;
        }
        case Family::kValueDecibels:
        case Family::kValueScalar: {
            auto* typed = SwifterKitControlOfKind<typename Family::LevelControl>(
                control,
                config,
                Family::kControlLevel);
            if (typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = SwifterKitBitsFromFloat(
                kind == Family::kValueDecibels ? typed->GetDecibelValue()
                                               : typed->GetScalarValue());
            return kIOReturnSuccess;
        }
        case Family::kValueSelector: {
            auto* typed = SwifterKitControlOfKind<typename Family::SelectorControl>(
                control,
                config,
                Family::kControlSelector);
            if (typed == nullptr)
                return kIOReturnBadArgument;
            *count = static_cast<uint32_t>(
                typed->GetCurrentSelectedValues(values, Family::kMaximumSelectorItems));
            return *count == 0 || *count > Family::kMaximumSelectorItems ? kIOReturnError
                                                                         : kIOReturnSuccess;
        }
        case Family::kValueSlider: {
            auto* typed = SwifterKitControlOfKind<typename Family::SliderControl>(
                control,
                config,
                Family::kControlSlider);
            if (typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = typed->GetControlValue();
            return kIOReturnSuccess;
        }
        case Family::kValueStereoPan: {
            auto* typed = SwifterKitControlOfKind<typename Family::StereoPanControl>(
                control,
                config,
                Family::kControlStereoPan);
            if (typed == nullptr)
                return kIOReturnBadArgument;
            values[0] = SwifterKitBitsFromFloat(typed->GetControlValue());
            return kIOReturnSuccess;
        }
        default:
            if constexpr (requires { typename Family::DirectionControl; }) {
                if (kind == Family::kValueDirection) {
                    auto* typed = SwifterKitControlOfKind<typename Family::DirectionControl>(
                        control,
                        config,
                        Family::kControlDirection);
                    if (typed == nullptr)
                        return kIOReturnBadArgument;
                    values[0] = typed->GetControlValue() ? 1 : 0;
                    return kIOReturnSuccess;
                }
            }
            return kIOReturnBadArgument;
    }
}

// Answers a control-value request with the value header and the current values.
template<typename Family, typename IVars, typename Request>
kern_return_t SwifterKitCopyControl(IVars* ivars, const Request* request, OSData** response) {
    if (request == nullptr || response == nullptr || ivars == nullptr)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = SwifterKitFindByIdentifier(
        Family::kControls,
        Family::kControlCount,
        request->identifier,
        &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    uint32_t values[Family::kMaximumSelectorItems] = {};
    uint32_t count = 1;
    const kern_return_t result = SwifterKitReadControlValues<Family>(
        ivars->controls[index],
        *config,
        request->kind,
        values,
        &count);
    if (result != kIOReturnSuccess)
        return result;
    const typename Family::ControlValueHeader header = {
        request->identifier,
        request->kind,
        count,
        0};
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

// Returns whether `values` are distinct items of the selector's configured list.
template<typename Family, typename Configuration>
bool SwifterKitSelectionIsValid(
    const Configuration& config,
    const uint32_t* values,
    uint32_t count) {
    for (uint32_t item = 0; item < count; ++item) {
        bool found = false;
        for (uint32_t candidate = 0; candidate < config.selectorCount; ++candidate)
            found =
                found || values[item] == Family::kSelectors[config.selectorStart + candidate].value;
        if (!found)
            return false;
        for (uint32_t prior = 0; prior < item; ++prior)
            if (values[prior] == values[item])
                return false;
    }
    return true;
}

template<typename Family, typename Configuration>
kern_return_t SwifterKitWriteControlValues(
    typename Family::Control* control,
    const Configuration& config,
    uint32_t kind,
    const uint32_t* values,
    uint32_t count) {
    switch (kind) {
        case Family::kValueBoolean: {
            auto* typed = SwifterKitControlOfKind<typename Family::BooleanControl>(
                control,
                config,
                Family::kControlBoolean);
            return typed != nullptr && count == 1 && values[0] <= 1
                       ? typed->SetControlValue(values[0] != 0)
                       : kIOReturnBadArgument;
        }
        case Family::kValueDecibels:
        case Family::kValueScalar: {
            auto* typed = SwifterKitControlOfKind<typename Family::LevelControl>(
                control,
                config,
                Family::kControlLevel);
            if (typed == nullptr || count != 1)
                return kIOReturnBadArgument;
            const float value = SwifterKitFloatFromBits(values[0]);
            if (!__builtin_isfinite(value))
                return kIOReturnBadArgument;
            if (kind == Family::kValueDecibels) {
                if (value < SwifterKitFloatFromBits(config.minimum)
                    || value > SwifterKitFloatFromBits(config.maximum))
                    return kIOReturnBadArgument;
                return typed->SetDecibelValue(value);
            }
            return value >= 0 && value <= 1 ? typed->SetScalarValue(value) : kIOReturnBadArgument;
        }
        case Family::kValueSelector: {
            auto* typed = SwifterKitControlOfKind<typename Family::SelectorControl>(
                control,
                config,
                Family::kControlSelector);
            if (typed == nullptr || !SwifterKitSelectionIsValid<Family>(config, values, count))
                return kIOReturnBadArgument;
            return typed->SetCurrentSelectedValues(values, count);
        }
        case Family::kValueSlider: {
            auto* typed = SwifterKitControlOfKind<typename Family::SliderControl>(
                control,
                config,
                Family::kControlSlider);
            return typed != nullptr && count == 1 && values[0] >= config.minimum
                           && values[0] <= config.maximum
                       ? typed->SetControlValue(values[0])
                       : kIOReturnBadArgument;
        }
        case Family::kValueStereoPan: {
            auto* typed = SwifterKitControlOfKind<typename Family::StereoPanControl>(
                control,
                config,
                Family::kControlStereoPan);
            const float value = SwifterKitFloatFromBits(values[0]);
            return typed != nullptr && count == 1 && __builtin_isfinite(value) && value >= -1
                           && value <= 1
                       ? typed->SetControlValue(value)
                       : kIOReturnBadArgument;
        }
        default:
            if constexpr (requires { typename Family::DirectionControl; }) {
                if (kind == Family::kValueDirection) {
                    auto* typed = SwifterKitControlOfKind<typename Family::DirectionControl>(
                        control,
                        config,
                        Family::kControlDirection);
                    return typed != nullptr && count == 1 && values[0] <= 1
                               ? typed->SetControlValue(values[0] != 0)
                               : kIOReturnBadArgument;
                }
            }
            return kIOReturnBadArgument;
    }
}

template<typename Family, typename IVars, typename Request>
kern_return_t SwifterKitSetControl(IVars* ivars, const Request* request, const uint32_t* values) {
    if (request == nullptr || values == nullptr || request->reserved != 0
        || request->valueCount == 0 || request->valueCount > Family::kMaximumSelectorItems
        || ivars == nullptr)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = SwifterKitFindByIdentifier(
        Family::kControls,
        Family::kControlCount,
        request->identifier,
        &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    if (!config->isSettable)
        return kIOReturnNotPermitted;
    return SwifterKitWriteControlValues<Family>(
        ivars->controls[index],
        *config,
        request->kind,
        values,
        request->valueCount);
}

// Answers a custom-property read with the value stored for the request's qualifier.
template<typename Family, typename IVars, typename Request>
kern_return_t SwifterKitCopyCustomProperty(
    IVars* ivars,
    const Request* request,
    const uint8_t* bytes,
    OSData** response) {
    if (request == nullptr || response == nullptr || request->reserved != 0
        || request->valueLength != 0 || request->qualifierLength == 0)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    if (SwifterKitFindByIdentifier(
            Family::kCustomProperties,
            Family::kCustomPropertyCount,
            request->identifier,
            &index)
        == nullptr)
        return kIOReturnNotFound;
    OSString* qualifier = SwifterKitStringFromBytes<Family>(
        bytes,
        request->qualifierLength,
        Family::kNameMaximumLength);
    OSObject* output = nullptr;
    kern_return_t result =
        qualifier == nullptr ? kIOReturnBadArgument
                             : ivars->customProperties[index]->GetCustomPropertyValueWithQualifier(
                                   qualifier,
                                   &output);
    const auto* string = OSDynamicCast(OSString, output);
    if (result == kIOReturnSuccess
        && (string == nullptr || string->getLength() > Family::kCustomPropertyValueMaximumLength))
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

template<typename Family, typename IVars, typename Request>
kern_return_t
    SwifterKitSetCustomProperty(IVars* ivars, const Request* request, const uint8_t* bytes) {
    if (request == nullptr || request->reserved != 0 || request->qualifierLength == 0
        || request->valueLength > Family::kCustomPropertyValueMaximumLength)
        return kIOReturnBadArgument;
    uint32_t index = 0;
    const auto* config = SwifterKitFindByIdentifier(
        Family::kCustomProperties,
        Family::kCustomPropertyCount,
        request->identifier,
        &index);
    if (config == nullptr)
        return kIOReturnNotFound;
    if (!config->isSettable)
        return kIOReturnNotPermitted;
    OSString* qualifier = SwifterKitStringFromBytes<Family>(
        bytes,
        request->qualifierLength,
        Family::kNameMaximumLength);
    OSString* value = SwifterKitStringFromBytes<Family>(
        bytes + request->qualifierLength,
        request->valueLength,
        Family::kCustomPropertyValueMaximumLength);
    const kern_return_t result =
        qualifier == nullptr || value == nullptr
            ? kIOReturnBadArgument
            : ivars->customProperties[index]->SetQualifierAndDataValue(qualifier, value);
    OSSafeReleaseNULL(value);
    OSSafeReleaseNULL(qualifier);
    return result;
}

#endif
