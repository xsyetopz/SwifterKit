#include "SwifterKitRuntimeVideoBooleanControl.h"
#include "SwifterKitRuntimeVideoCustomProperty.h"
#include "SwifterKitRuntimeVideoDirectionControl.h"
#include "SwifterKitRuntimeVideoLevelControl.h"
#include "SwifterKitRuntimeVideoSelectorControl.h"
#include "SwifterKitRuntimeVideoSliderControl.h"
#include "SwifterKitRuntimeVideoStereoPanControl.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeService.h"

namespace {
    struct CallbackState {
        SwifterKitRuntimeService* service;
        uint32_t identifier;
    };

    bool InitializeState(
        CallbackState* state,
        SwifterKitRuntimeService* service,
        uint32_t identifier) {
        if (state == nullptr || service == nullptr || identifier == 0)
            return false;
        state->service = service;
        state->identifier = identifier;
        service->retain();
        return true;
    }

    void ReleaseState(CallbackState* state) {
        if (state != nullptr)
            OSSafeReleaseNULL(state->service);
    }

    uint32_t FloatBits(float value) {
        return __builtin_bit_cast(uint32_t, value);
    }
}  // namespace

struct SwifterKitRuntimeVideoBooleanControl_IVars : CallbackState {};
struct SwifterKitRuntimeVideoDirectionControl_IVars : CallbackState {};
struct SwifterKitRuntimeVideoLevelControl_IVars : CallbackState {};
struct SwifterKitRuntimeVideoSelectorControl_IVars : CallbackState {};
struct SwifterKitRuntimeVideoSliderControl_IVars : CallbackState {};
struct SwifterKitRuntimeVideoStereoPanControl_IVars : CallbackState {};
struct SwifterKitRuntimeVideoCustomProperty_IVars : CallbackState {};

bool SwifterKitRuntimeVideoBooleanControl::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    bool value,
    IOUserVideoObjectPropertyElement element,
    IOUserVideoObjectPropertyScope scope,
    IOUserVideoClassID classID) {
    if (!super::init(driver, isSettable, value, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoBooleanControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoBooleanControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeVideoBooleanControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoBooleanControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoBooleanControl::HandleChangeControlValue(bool value) {
    const uint32_t rawValue = value ? 1 : 0;
    const kern_return_t result =
        ivars->service->VideoControlValueEvent(ivars->identifier, 1, &rawValue, 1);
    return result == kIOReturnSuccess ? super::HandleChangeControlValue(value) : result;
}

bool SwifterKitRuntimeVideoDirectionControl::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    bool value,
    IOUserVideoObjectPropertyElement element,
    IOUserVideoObjectPropertyScope scope,
    IOUserVideoClassID classID) {
    if (!super::init(driver, isSettable, value, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoDirectionControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoDirectionControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeVideoDirectionControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoDirectionControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoDirectionControl::HandleChangeControlValue(bool value) {
    const uint32_t rawValue = value ? 1 : 0;
    const kern_return_t result =
        ivars->service->VideoControlValueEvent(ivars->identifier, 7, &rawValue, 1);
    return result == kIOReturnSuccess ? super::HandleChangeControlValue(value) : result;
}

bool SwifterKitRuntimeVideoLevelControl::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    float value,
    IOUserVideoLevelControlRange range,
    IOUserVideoObjectPropertyElement element,
    IOUserVideoObjectPropertyScope scope,
    IOUserVideoClassID classID) {
    if (!super::init(driver, isSettable, value, range, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoLevelControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoLevelControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeVideoLevelControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoLevelControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoLevelControl::HandleChangeDecibelValue(float value) {
    const uint32_t bits = FloatBits(value);
    const kern_return_t result =
        ivars->service->VideoControlValueEvent(ivars->identifier, 2, &bits, 1);
    return result == kIOReturnSuccess ? super::HandleChangeDecibelValue(value) : result;
}

kern_return_t SwifterKitRuntimeVideoLevelControl::HandleChangeScalarValue(float value) {
    const uint32_t bits = FloatBits(value);
    const kern_return_t result =
        ivars->service->VideoControlValueEvent(ivars->identifier, 3, &bits, 1);
    return result == kIOReturnSuccess ? super::HandleChangeScalarValue(value) : result;
}

bool SwifterKitRuntimeVideoSelectorControl::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    IOUserVideoObjectPropertyElement element,
    IOUserVideoObjectPropertyScope scope,
    IOUserVideoClassID classID) {
    if (!super::init(driver, isSettable, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoSelectorControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoSelectorControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeVideoSelectorControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoSelectorControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoSelectorControl::HandleChangeSelectedValues(
    const IOUserVideoSelectorValue* values,
    size_t count) {
    if (values == nullptr || count == 0 || count > 32)
        return kIOReturnBadArgument;
    const kern_return_t result = ivars->service->VideoControlValueEvent(
        ivars->identifier,
        4,
        values,
        static_cast<uint32_t>(count));
    return result == kIOReturnSuccess ? super::HandleChangeSelectedValues(values, count) : result;
}

bool SwifterKitRuntimeVideoSliderControl::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    uint32_t value,
    IOUserVideoSliderRange range,
    IOUserVideoObjectPropertyElement element,
    IOUserVideoObjectPropertyScope scope,
    IOUserVideoClassID classID) {
    if (!super::init(driver, isSettable, value, range, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoSliderControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoSliderControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeVideoSliderControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoSliderControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoSliderControl::HandleChangeControlValue(uint32_t value) {
    const kern_return_t result =
        ivars->service->VideoControlValueEvent(ivars->identifier, 5, &value, 1);
    return result == kIOReturnSuccess ? super::HandleChangeControlValue(value) : result;
}

bool SwifterKitRuntimeVideoStereoPanControl::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    float value,
    IOUserVideoObjectPropertyElement leftChannel,
    IOUserVideoObjectPropertyElement rightChannel,
    IOUserVideoObjectPropertyElement element,
    IOUserVideoObjectPropertyScope scope,
    IOUserVideoClassID classID) {
    if (!super::init(driver, isSettable, value, leftChannel, rightChannel, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoStereoPanControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoStereoPanControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeVideoStereoPanControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoStereoPanControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoStereoPanControl::HandleChangeControlValue(float value) {
    const uint32_t bits = FloatBits(value);
    const kern_return_t result =
        ivars->service->VideoControlValueEvent(ivars->identifier, 6, &bits, 1);
    return result == kIOReturnSuccess ? super::HandleChangeControlValue(value) : result;
}

bool SwifterKitRuntimeVideoCustomProperty::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    IOUserVideoObjectPropertyAddress address,
    bool isSettable,
    IOUserVideoCustomPropertyDataType qualifierType,
    IOUserVideoCustomPropertyDataType dataType) {
    if (!super::init(driver, address, isSettable, qualifierType, dataType))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoCustomProperty_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoCustomProperty_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeVideoCustomProperty::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoCustomProperty_IVars, 1);
    super::free();
}

kern_return_t
    SwifterKitRuntimeVideoCustomProperty::HandleChangeCustomPropertyDataValueWithQualifier(
        OSObject* qualifier,
        OSObject* value) {
    auto* qualifierString = OSDynamicCast(OSString, qualifier);
    auto* valueString = OSDynamicCast(OSString, value);
    if (qualifierString == nullptr || valueString == nullptr)
        return kIOReturnBadArgument;
    const kern_return_t result = ivars->service->VideoCustomPropertyEvent(
        ivars->identifier,
        reinterpret_cast<const uint8_t*>(qualifierString->getCStringNoCopy()),
        static_cast<uint32_t>(qualifierString->getLength()),
        reinterpret_cast<const uint8_t*>(valueString->getCStringNoCopy()),
        static_cast<uint32_t>(valueString->getLength()));
    return result == kIOReturnSuccess
               ? super::HandleChangeCustomPropertyDataValueWithQualifier(qualifier, value)
               : result;
}
#endif
