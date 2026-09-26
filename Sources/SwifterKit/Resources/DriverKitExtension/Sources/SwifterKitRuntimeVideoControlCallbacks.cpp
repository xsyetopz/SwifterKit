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

    #include "SwifterKitRuntimeMediaControls.h"
    #include "SwifterKitRuntimeService.h"

struct SwifterKitRuntimeVideoBooleanControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeVideoDirectionControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeVideoLevelControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeVideoSelectorControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeVideoSliderControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeVideoStereoPanControl_IVars : SwifterKitMediaCallbackState {};
struct SwifterKitRuntimeVideoCustomProperty_IVars : SwifterKitMediaCallbackState {};

bool SwifterKitRuntimeVideoBooleanControl::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t identifier,
    bool isSettable,
    bool value,
    IOUserVideoObjectPropertyElement element,
    IOUserVideoObjectPropertyScope scope,
    IOUserVideoClassID classID) {
    return super::init(driver, isSettable, value, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeVideoBooleanControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoBooleanControl::HandleChangeControlValue(bool value) {
    const uint32_t rawValue = value ? 1 : 0;
    const kern_return_t result = ivars->service->VideoControlValueEvent(
        ivars->identifier,
        kSwifterKitVideoValueBoolean,
        &rawValue,
        1);
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
    return super::init(driver, isSettable, value, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeVideoDirectionControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoDirectionControl::HandleChangeControlValue(bool value) {
    const uint32_t rawValue = value ? 1 : 0;
    const kern_return_t result = ivars->service->VideoControlValueEvent(
        ivars->identifier,
        kSwifterKitVideoValueDirection,
        &rawValue,
        1);
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
    return super::init(driver, isSettable, value, range, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeVideoLevelControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoLevelControl::HandleChangeDecibelValue(float value) {
    const uint32_t bits = SwifterKitBitsFromFloat(value);
    const kern_return_t result = ivars->service->VideoControlValueEvent(
        ivars->identifier,
        kSwifterKitVideoValueDecibels,
        &bits,
        1);
    return result == kIOReturnSuccess ? super::HandleChangeDecibelValue(value) : result;
}

kern_return_t SwifterKitRuntimeVideoLevelControl::HandleChangeScalarValue(float value) {
    const uint32_t bits = SwifterKitBitsFromFloat(value);
    const kern_return_t result = ivars->service->VideoControlValueEvent(
        ivars->identifier,
        kSwifterKitVideoValueScalar,
        &bits,
        1);
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
    return super::init(driver, isSettable, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeVideoSelectorControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoSelectorControl::HandleChangeSelectedValues(
    const IOUserVideoSelectorValue* values,
    size_t count) {
    if (values == nullptr || count == 0 || count > kSwifterKitVideoMaximumSelectorItems)
        return kIOReturnBadArgument;
    const kern_return_t result = ivars->service->VideoControlValueEvent(
        ivars->identifier,
        kSwifterKitVideoValueSelector,
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
    return super::init(driver, isSettable, value, range, element, scope, classID)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeVideoSliderControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoSliderControl::HandleChangeControlValue(uint32_t value) {
    const kern_return_t result = ivars->service->VideoControlValueEvent(
        ivars->identifier,
        kSwifterKitVideoValueSlider,
        &value,
        1);
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

void SwifterKitRuntimeVideoStereoPanControl::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoStereoPanControl::HandleChangeControlValue(float value) {
    const uint32_t bits = SwifterKitBitsFromFloat(value);
    const kern_return_t result = ivars->service->VideoControlValueEvent(
        ivars->identifier,
        kSwifterKitVideoValueStereoPan,
        &bits,
        1);
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
    return super::init(driver, address, isSettable, qualifierType, dataType)
           && SwifterKitAttachCallbackState(ivars, service, identifier);
}

void SwifterKitRuntimeVideoCustomProperty::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t
    SwifterKitRuntimeVideoCustomProperty::HandleChangeCustomPropertyDataValueWithQualifier(
        OSObject* qualifier,
        OSObject* value) {
    const kern_return_t result = SwifterKitReportCustomPropertyChange(
        ivars,
        &SwifterKitRuntimeService::VideoCustomPropertyEvent,
        qualifier,
        value);
    return result == kIOReturnSuccess
               ? super::HandleChangeCustomPropertyDataValueWithQualifier(qualifier, value)
               : result;
}
#endif
