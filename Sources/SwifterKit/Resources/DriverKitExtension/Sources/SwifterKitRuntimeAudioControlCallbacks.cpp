#include "SwifterKitRuntimeAudioBooleanControl.h"
#include "SwifterKitRuntimeAudioCustomProperty.h"
#include "SwifterKitRuntimeAudioLevelControl.h"
#include "SwifterKitRuntimeAudioSelectorControl.h"
#include "SwifterKitRuntimeAudioSliderControl.h"
#include "SwifterKitRuntimeAudioStereoPanControl.h"

#if SWIFTERKIT_ENABLE_AUDIO
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

struct SwifterKitRuntimeAudioBooleanControl_IVars : CallbackState {};
struct SwifterKitRuntimeAudioLevelControl_IVars : CallbackState {};
struct SwifterKitRuntimeAudioSelectorControl_IVars : CallbackState {};
struct SwifterKitRuntimeAudioSliderControl_IVars : CallbackState {};
struct SwifterKitRuntimeAudioStereoPanControl_IVars : CallbackState {};
struct SwifterKitRuntimeAudioCustomProperty_IVars : CallbackState {};

bool SwifterKitRuntimeAudioBooleanControl::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    bool value,
    IOUserAudioObjectPropertyElement element,
    IOUserAudioObjectPropertyScope scope,
    IOUserAudioClassID classID) {
    if (!super::init(driver, isSettable, value, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioBooleanControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioBooleanControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeAudioBooleanControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioBooleanControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioBooleanControl::HandleChangeControlValue(bool value) {
    const uint32_t rawValue = value ? 1 : 0;
    const kern_return_t result =
        ivars->service->AudioControlValueEvent(ivars->identifier, 1, &rawValue, 1);
    return result == kIOReturnSuccess ? super::HandleChangeControlValue(value) : result;
}

bool SwifterKitRuntimeAudioLevelControl::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    float value,
    IOUserAudioLevelControlRange range,
    IOUserAudioObjectPropertyElement element,
    IOUserAudioObjectPropertyScope scope,
    IOUserAudioClassID classID) {
    if (!super::init(driver, isSettable, value, range, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioLevelControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioLevelControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeAudioLevelControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioLevelControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioLevelControl::HandleChangeDecibelValue(float value) {
    const uint32_t bits = FloatBits(value);
    const kern_return_t result =
        ivars->service->AudioControlValueEvent(ivars->identifier, 2, &bits, 1);
    return result == kIOReturnSuccess ? super::HandleChangeDecibelValue(value) : result;
}

kern_return_t SwifterKitRuntimeAudioLevelControl::HandleChangeScalarValue(float value) {
    const uint32_t bits = FloatBits(value);
    const kern_return_t result =
        ivars->service->AudioControlValueEvent(ivars->identifier, 3, &bits, 1);
    return result == kIOReturnSuccess ? super::HandleChangeScalarValue(value) : result;
}

bool SwifterKitRuntimeAudioSelectorControl::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    IOUserAudioObjectPropertyElement element,
    IOUserAudioObjectPropertyScope scope,
    IOUserAudioClassID classID) {
    if (!super::init(driver, isSettable, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioSelectorControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioSelectorControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeAudioSelectorControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioSelectorControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioSelectorControl::HandleChangeSelectedValues(
    const IOUserAudioSelectorValue* values,
    size_t count) {
    if (values == nullptr || count == 0 || count > 32)
        return kIOReturnBadArgument;
    const kern_return_t result = ivars->service->AudioControlValueEvent(
        ivars->identifier,
        4,
        values,
        static_cast<uint32_t>(count));
    return result == kIOReturnSuccess ? super::HandleChangeSelectedValues(values, count) : result;
}

bool SwifterKitRuntimeAudioSliderControl::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    uint32_t value,
    IOUserAudioSliderRange range,
    IOUserAudioObjectPropertyElement element,
    IOUserAudioObjectPropertyScope scope,
    IOUserAudioClassID classID) {
    if (!super::init(driver, isSettable, value, range, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioSliderControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioSliderControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeAudioSliderControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioSliderControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioSliderControl::HandleChangeControlValue(uint32_t value) {
    const kern_return_t result =
        ivars->service->AudioControlValueEvent(ivars->identifier, 5, &value, 1);
    return result == kIOReturnSuccess ? super::HandleChangeControlValue(value) : result;
}

bool SwifterKitRuntimeAudioStereoPanControl::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    float value,
    IOUserAudioObjectPropertyElement leftChannel,
    IOUserAudioObjectPropertyElement rightChannel,
    IOUserAudioObjectPropertyElement element,
    IOUserAudioObjectPropertyScope scope,
    IOUserAudioClassID classID) {
    if (!super::init(driver, isSettable, value, leftChannel, rightChannel, element, scope, classID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioStereoPanControl_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioStereoPanControl_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeAudioStereoPanControl::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioStereoPanControl_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioStereoPanControl::HandleChangeControlValue(float value) {
    const uint32_t bits = FloatBits(value);
    const kern_return_t result =
        ivars->service->AudioControlValueEvent(ivars->identifier, 6, &bits, 1);
    return result == kIOReturnSuccess ? super::HandleChangeControlValue(value) : result;
}

bool SwifterKitRuntimeAudioCustomProperty::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    IOUserAudioObjectPropertyAddress address,
    bool isSettable,
    IOUserAudioCustomPropertyDataType qualifierType,
    IOUserAudioCustomPropertyDataType dataType) {
    if (!super::init(driver, address, isSettable, qualifierType, dataType))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioCustomProperty_IVars, 1);
    if (!InitializeState(ivars, service, identifier)) {
        IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioCustomProperty_IVars, 1);
        return false;
    }
    return true;
}

void SwifterKitRuntimeAudioCustomProperty::free() {
    ReleaseState(ivars);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioCustomProperty_IVars, 1);
    super::free();
}

kern_return_t
    SwifterKitRuntimeAudioCustomProperty::HandleChangeCustomPropertyDataValueWithQualifier(
        OSObject* qualifier,
        OSObject* value) {
    auto* qualifierString = OSDynamicCast(OSString, qualifier);
    auto* valueString = OSDynamicCast(OSString, value);
    if (qualifierString == nullptr || valueString == nullptr)
        return kIOReturnBadArgument;
    const kern_return_t result = ivars->service->AudioCustomPropertyEvent(
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
