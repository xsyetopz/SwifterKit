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
    #include "SwifterKitRuntimeMediaControls.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"

namespace {
    // The AudioDriverKit classes and schema values the SwifterKitRuntimeMediaControls.h
    // templates operate on.
    struct AudioControlFamily {
        using Control = IOUserAudioControl;
        using BooleanControl = IOUserAudioBooleanControl;
        using LevelControl = IOUserAudioLevelControl;
        using SelectorControl = IOUserAudioSelectorControl;
        using SliderControl = IOUserAudioSliderControl;
        using StereoPanControl = IOUserAudioStereoPanControl;
        using RuntimeBooleanControl = SwifterKitRuntimeAudioBooleanControl;
        using RuntimeLevelControl = SwifterKitRuntimeAudioLevelControl;
        using RuntimeSelectorControl = SwifterKitRuntimeAudioSelectorControl;
        using RuntimeSliderControl = SwifterKitRuntimeAudioSliderControl;
        using RuntimeStereoPanControl = SwifterKitRuntimeAudioStereoPanControl;
        using RuntimeCustomProperty = SwifterKitRuntimeAudioCustomProperty;
        using LevelRange = IOUserAudioLevelControlRange;
        using SliderRange = IOUserAudioSliderRange;
        using SelectorDescription = IOUserAudioSelectorValueDescription;
        using Scope = IOUserAudioObjectPropertyScope;
        using ClassID = IOUserAudioClassID;
        using PropertyAddress = IOUserAudioObjectPropertyAddress;
        using CustomPropertyDataType = IOUserAudioCustomPropertyDataType;
        using ControlValueHeader = SwifterKitAudioControlValueHeader;

        static constexpr uint32_t kControlBoolean = kSwifterKitAudioControlBoolean;
        static constexpr uint32_t kControlLevel = kSwifterKitAudioControlLevel;
        static constexpr uint32_t kControlSelector = kSwifterKitAudioControlSelector;
        static constexpr uint32_t kControlSlider = kSwifterKitAudioControlSlider;
        static constexpr uint32_t kControlStereoPan = kSwifterKitAudioControlStereoPan;
        static constexpr uint32_t kValueBoolean = kSwifterKitAudioValueBoolean;
        static constexpr uint32_t kValueDecibels = kSwifterKitAudioValueDecibels;
        static constexpr uint32_t kValueScalar = kSwifterKitAudioValueScalar;
        static constexpr uint32_t kValueSelector = kSwifterKitAudioValueSelector;
        static constexpr uint32_t kValueSlider = kSwifterKitAudioValueSlider;
        static constexpr uint32_t kValueStereoPan = kSwifterKitAudioValueStereoPan;
        static constexpr uint32_t kMaximumSelectorItems = kSwifterKitAudioMaximumSelectorItems;
        static constexpr uint32_t kNameMaximumLength = kSwifterKitAudioNameMaximumLength;
        static constexpr uint32_t kCustomPropertyValueMaximumLength =
            kSwifterKitAudioCustomPropertyValueMaximumLength;

        static constexpr uint32_t kControlCount = kSwifterKitAudioControlCount;
        static constexpr const auto* kControls = kSwifterKitAudioControls;
        static constexpr const auto* kSelectors = kSwifterKitAudioSelectors;
        static constexpr const auto* kInitialSelections = kSwifterKitAudioInitialSelections;
        static constexpr uint32_t kCustomPropertyCount = kSwifterKitAudioCustomPropertyCount;
        static constexpr const auto* kCustomProperties = kSwifterKitAudioCustomProperties;
        static constexpr const auto* kCustomPropertyValues = kSwifterKitAudioCustomPropertyValues;
    };
}  // namespace

kern_return_t SwifterKitRuntimeAudioDevice::ConfigureControls() {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    kern_return_t result = kIOReturnSuccess;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitAudioControlCount;
         ++index) {
        const auto& config = kSwifterKitAudioControls[index];
        IOUserAudioControl* control = nullptr;
        result =
            SwifterKitMakeConfiguredControl<AudioControlFamily>(ivars->service, config, &control);
        result = SwifterKitNameControl(result, control, config.name);
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
        SwifterKitRuntimeAudioCustomProperty* property = nullptr;
        result = SwifterKitMakeConfiguredCustomProperty<AudioControlFamily>(
            ivars->service,
            kSwifterKitAudioCustomProperties[index],
            &property);
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
    return SwifterKitCopyControl<AudioControlFamily>(ivars, request, response);
}

kern_return_t SwifterKitRuntimeAudioDevice::SetControl(
    const SwifterKitAudioControlValueHeader* request,
    const uint32_t* values) {
    return SwifterKitSetControl<AudioControlFamily>(ivars, request, values);
}

kern_return_t SwifterKitRuntimeAudioDevice::CopyCustomProperty(
    const SwifterKitAudioCustomPropertyHeader* request,
    const uint8_t* bytes,
    OSData** response) {
    return SwifterKitCopyCustomProperty<AudioControlFamily>(ivars, request, bytes, response);
}

kern_return_t SwifterKitRuntimeAudioDevice::SetCustomProperty(
    const SwifterKitAudioCustomPropertyHeader* request,
    const uint8_t* bytes) {
    return SwifterKitSetCustomProperty<AudioControlFamily>(ivars, request, bytes);
}
#endif
