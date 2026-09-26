#include "SwifterKitRuntimeAudioBooleanControl.h"
#include "SwifterKitRuntimeAudioCustomProperty.h"
#include "SwifterKitRuntimeAudioLevelControl.h"
#include "SwifterKitRuntimeAudioSelectorControl.h"
#include "SwifterKitRuntimeAudioSliderControl.h"
#include "SwifterKitRuntimeAudioStereoPanControl.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeMediaControls.h"
    #include "SwifterKitRuntimeService.h"

struct SwifterKitRuntimeAudioBooleanControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeAudioLevelControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeAudioSelectorControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeAudioSliderControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeAudioStereoPanControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeAudioCustomProperty_IVars : SwifterKitMediaCallbackState {};

bool SwifterKitRuntimeAudioBooleanControl::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    bool value,
    IOUserAudioObjectPropertyElement element,
    IOUserAudioObjectPropertyScope scope,
    IOUserAudioClassID classID) {
    return super::init(driver, isSettable, value, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeAudioBooleanControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioBooleanControl::HandleChangeControlValue(bool value) {
    const uint32_t rawValue = value ? 1 : 0;
    const kern_return_t result = ivars->service->AudioControlValueEvent(
        ivars->identifier,
        kSwifterKitAudioValueBoolean,
        &rawValue,
        1);
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
    return super::init(driver, isSettable, value, range, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeAudioLevelControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioLevelControl::HandleChangeDecibelValue(float value) {
    const uint32_t bits = SwifterKitBitsFromFloat(value);
    const kern_return_t result = ivars->service->AudioControlValueEvent(
        ivars->identifier,
        kSwifterKitAudioValueDecibels,
        &bits,
        1);
    return result == kIOReturnSuccess ? super::HandleChangeDecibelValue(value) : result;
}

kern_return_t SwifterKitRuntimeAudioLevelControl::HandleChangeScalarValue(float value) {
    const uint32_t bits = SwifterKitBitsFromFloat(value);
    const kern_return_t result = ivars->service->AudioControlValueEvent(
        ivars->identifier,
        kSwifterKitAudioValueScalar,
        &bits,
        1);
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
    return super::init(driver, isSettable, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeAudioSelectorControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioSelectorControl::HandleChangeSelectedValues(
    const IOUserAudioSelectorValue* values,
    size_t count) {
    if (values == nullptr || count == 0 || count > kSwifterKitAudioMaximumSelectorItems)
        return kIOReturnBadArgument;
    const kern_return_t result = ivars->service->AudioControlValueEvent(
        ivars->identifier,
        kSwifterKitAudioValueSelector,
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
    return super::init(driver, isSettable, value, range, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeAudioSliderControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioSliderControl::HandleChangeControlValue(uint32_t value) {
    const kern_return_t result = ivars->service->AudioControlValueEvent(
        ivars->identifier,
        kSwifterKitAudioValueSlider,
        &value,
        1);
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
    return super::init(
               driver,
               isSettable,
               value,
               leftChannel,
               rightChannel,
               element,
               scope,
               classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeAudioStereoPanControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioStereoPanControl::HandleChangeControlValue(float value) {
    const uint32_t bits = SwifterKitBitsFromFloat(value);
    const kern_return_t result = ivars->service->AudioControlValueEvent(
        ivars->identifier,
        kSwifterKitAudioValueStereoPan,
        &bits,
        1);
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
    return super::init(driver, address, isSettable, qualifierType, dataType)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeAudioCustomProperty::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t
    SwifterKitRuntimeAudioCustomProperty::HandleChangeCustomPropertyDataValueWithQualifier(
        OSObject* qualifier,
        OSObject* value) {
    const kern_return_t result = SwifterKitReportCustomPropertyChange(
        ivars,
        &SwifterKitRuntimeService::AudioCustomPropertyEvent,
        qualifier,
        value);
    return result == kIOReturnSuccess
               ? super::HandleChangeCustomPropertyDataValueWithQualifier(qualifier, value)
               : result;
}
#endif
