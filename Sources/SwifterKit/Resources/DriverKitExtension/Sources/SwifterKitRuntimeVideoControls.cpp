#include "SwifterKitRuntimeVideoDevice.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeMediaControls.h"
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
    // The VideoDriverKit classes and schema values the SwifterKitRuntimeMediaControls.h
    // templates operate on, including the direction control only VideoDriverKit declares.
    struct VideoControlFamily {
        using Control = IOUserVideoControl;
        using BooleanControl = IOUserVideoBooleanControl;
        using DirectionControl = IOUserVideoDirectionControl;
        using LevelControl = IOUserVideoLevelControl;
        using SelectorControl = IOUserVideoSelectorControl;
        using SliderControl = IOUserVideoSliderControl;
        using StereoPanControl = IOUserVideoStereoPanControl;
        using RuntimeBooleanControl = SwifterKitRuntimeVideoBooleanControl;
        using RuntimeDirectionControl = SwifterKitRuntimeVideoDirectionControl;
        using RuntimeLevelControl = SwifterKitRuntimeVideoLevelControl;
        using RuntimeSelectorControl = SwifterKitRuntimeVideoSelectorControl;
        using RuntimeSliderControl = SwifterKitRuntimeVideoSliderControl;
        using RuntimeStereoPanControl = SwifterKitRuntimeVideoStereoPanControl;
        using RuntimeCustomProperty = SwifterKitRuntimeVideoCustomProperty;
        using LevelRange = IOUserVideoLevelControlRange;
        using SliderRange = IOUserVideoSliderRange;
        using SelectorDescription = IOUserVideoSelectorValueDescription;
        using Scope = IOUserVideoObjectPropertyScope;
        using ClassID = IOUserVideoClassID;
        using PropertyAddress = IOUserVideoObjectPropertyAddress;
        using CustomPropertyDataType = IOUserVideoCustomPropertyDataType;
        using ControlValueHeader = SwifterKitVideoControlValueHeader;

        static constexpr uint32_t kControlBoolean = kSwifterKitVideoControlBoolean;
        static constexpr uint32_t kControlDirection = kSwifterKitVideoControlDirection;
        static constexpr uint32_t kControlLevel = kSwifterKitVideoControlLevel;
        static constexpr uint32_t kControlSelector = kSwifterKitVideoControlSelector;
        static constexpr uint32_t kControlSlider = kSwifterKitVideoControlSlider;
        static constexpr uint32_t kControlStereoPan = kSwifterKitVideoControlStereoPan;
        static constexpr uint32_t kValueBoolean = kSwifterKitVideoValueBoolean;
        static constexpr uint32_t kValueDirection = kSwifterKitVideoValueDirection;
        static constexpr uint32_t kValueDecibels = kSwifterKitVideoValueDecibels;
        static constexpr uint32_t kValueScalar = kSwifterKitVideoValueScalar;
        static constexpr uint32_t kValueSelector = kSwifterKitVideoValueSelector;
        static constexpr uint32_t kValueSlider = kSwifterKitVideoValueSlider;
        static constexpr uint32_t kValueStereoPan = kSwifterKitVideoValueStereoPan;
        static constexpr uint32_t kMaximumSelectorItems = kSwifterKitVideoMaximumSelectorItems;
        static constexpr uint32_t kNameMaximumLength = kSwifterKitVideoNameMaximumLength;
        static constexpr uint32_t kCustomPropertyValueMaximumLength =
            kSwifterKitVideoCustomPropertyValueMaximumLength;

        static constexpr uint32_t kControlCount = kSwifterKitVideoControlCount;
        static constexpr const auto* kControls = kSwifterKitVideoControls;
        static constexpr const auto* kSelectors = kSwifterKitVideoSelectors;
        static constexpr const auto* kInitialSelections = kSwifterKitVideoInitialSelections;
        static constexpr uint32_t kCustomPropertyCount = kSwifterKitVideoCustomPropertyCount;
        static constexpr const auto* kCustomProperties = kSwifterKitVideoCustomProperties;
        static constexpr const auto* kCustomPropertyValues = kSwifterKitVideoCustomPropertyValues;
    };
}  // namespace

kern_return_t SwifterKitRuntimeVideoDevice::ConfigureControls() {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    kern_return_t result = kIOReturnSuccess;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitVideoControlCount;
         ++index) {
        const auto& config = kSwifterKitVideoControls[index];
        IOUserVideoControl* control = nullptr;
        result =
            SwifterKitMakeConfiguredControl<VideoControlFamily>(ivars->service, config, &control);
        result = SwifterKitNameControl(result, control, config.name);
        // IOUserVideoControl.iig documents _SetOwningDeviceID only as "Sets the control's owning
        // device". It says nothing about AddControl setting the owner. ConfigureControls sets
        // the owner explicitly before the control becomes visible.
        if (result == kIOReturnSuccess)
            control->_SetOwningDeviceID(GetObjectID());
        if (result == kIOReturnSuccess)
            result = AddControl(control);
        if (result == kIOReturnSuccess)
            ivars->controls[index] = control;
        else
            OSSafeReleaseNULL(control);
    }

    if (result != kIOReturnSuccess)
        return result;
    return SwifterKitAddConfiguredCustomProperties<VideoControlFamily>(
        ivars->service,
        this,
        [this](uint32_t index, SwifterKitRuntimeVideoCustomProperty* property) {
            ivars->customProperties[index] = property;
            ivars->customPropertyOwners[index] = kSwifterKitVideoOwnerDevice;
        });
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyControl(
    const SwifterKitVideoControlGet* request,
    OSData** response) {
    return SwifterKitCopyControl<VideoControlFamily>(ivars, request, response);
}

kern_return_t SwifterKitRuntimeVideoDevice::SetControl(
    const SwifterKitVideoControlValueHeader* request,
    const uint32_t* values) {
    return SwifterKitSetControl<VideoControlFamily>(ivars, request, values);
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyCustomProperty(
    const SwifterKitVideoCustomPropertyHeader* request,
    const uint8_t* bytes,
    OSData** response) {
    return SwifterKitCopyCustomProperty<VideoControlFamily>(ivars, request, bytes, response);
}

kern_return_t SwifterKitRuntimeVideoDevice::SetCustomProperty(
    const SwifterKitVideoCustomPropertyHeader* request,
    const uint8_t* bytes) {
    return SwifterKitSetCustomProperty<VideoControlFamily>(ivars, request, bytes);
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
    // A property that was never created has no owner to leave.
    for (uint32_t index = 0; index < kSwifterKitVideoCustomPropertyCount; ++index)
        if (ivars->customProperties[index] != nullptr)
            (void)SetCustomPropertyOwner(
                kSwifterKitVideoCustomProperties[index].identifier,
                kSwifterKitVideoOwnerDetached);
}
#endif
