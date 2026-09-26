#include "SwifterKitRuntimeAudioClockDevice.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioDeviceState.h"
    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeMediaObjects.h"
    #include "SwifterKitRuntimeService.h"

namespace {
    constexpr uint64_t kClockSampleRateChangeAction = 0x53574B434C4F434BULL;

    // The AudioDriverKit types and schema values the SwifterKitRuntimeMediaObjects.h clock
    // templates operate on.
    struct AudioClockFamily {
        using TransportType = IOUserAudioTransportType;
        using ClockAlgorithm = IOUserAudioClockAlgorithm;

        static constexpr uint32_t kMaximumSampleRates = kSwifterKitAudioMaximumSampleRates;
        static constexpr const auto* kClockSampleRates = kSwifterKitAudioClockSampleRates;
    };
}  // namespace

struct SwifterKitRuntimeAudioClockDevice_IVars {
    SwifterKitRuntimeService* service = nullptr;
    uint32_t index = 0;
    uint64_t pendingSampleRateBits = 0;
};

bool SwifterKitRuntimeAudioClockDevice::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t index,
    bool supportsPrewarming,
    OSString* deviceUID,
    OSString* modelUID,
    OSString* manufacturerUID,
    uint32_t zeroTimestampPeriod) {
    if (driver == nullptr || service == nullptr || index >= kSwifterKitAudioObjectTableCount
        || !super::init(
            driver,
            supportsPrewarming,
            deviceUID,
            modelUID,
            manufacturerUID,
            zeroTimestampPeriod))
        return false;
    return SwifterKitAttachObjectState(ivars, service, index);
}

void SwifterKitRuntimeAudioClockDevice::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioClockDevice::Configure(
    const SwifterKitAudioClockConfiguration* configuration) {
    if (ivars == nullptr || configuration == nullptr)
        return kIOReturnBadArgument;
    const kern_return_t result =
        SwifterKitConfigureClockDevice<AudioClockFamily>(this, configuration);
    #if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5
    if (result == kIOReturnSuccess && configuration->wantsControlsRestored >= 0)
        SetWantsControlsRestored(configuration->wantsControlsRestored != 0);
    #endif
    return result;
}

bool SwifterKitRuntimeAudioClockDevice::IsAvailableSampleRate(double sampleRate) {
    return SwifterKitIsAvailableSampleRate<AudioClockFamily>(this, sampleRate);
}

kern_return_t SwifterKitRuntimeAudioClockDevice::RequestSampleRate(double sampleRate) {
    if (ivars == nullptr || !IsAvailableSampleRate(sampleRate))
        return kIOReturnBadArgument;
    return SwifterKitRequestSampleRateChange(
        this,
        &ivars->pendingSampleRateBits,
        kClockSampleRateChangeAction,
        sampleRate);
}

kern_return_t SwifterKitRuntimeAudioClockDevice::StartIO(IOUserAudioStartStopFlags flags) {
    const kern_return_t result = super::StartIO(flags);
    if (result == kIOReturnSuccess)
        (void)ivars->service->AudioObjectEvent(
            kSwifterKitAudioObjectEventClockStarted,
            ivars->index,
            static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeAudioClockDevice::StopIO(IOUserAudioStartStopFlags flags) {
    (void)ivars->service->AudioObjectEvent(
        kSwifterKitAudioObjectEventClockStopped,
        ivars->index,
        static_cast<uint64_t>(flags));
    return super::StopIO(flags);
}

kern_return_t SwifterKitRuntimeAudioClockDevice::PerformDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction == kSwifterKitAudioMemberChangeAction) {
        SwifterKitAudioMemberChange change = {};
        if (!SwifterKitReadAudioMemberChange(changeInfo, &change) || change.value > UINT32_MAX)
            return kIOReturnBadArgument;
        const auto value = static_cast<uint32_t>(change.value);
        switch (change.selector) {
            case kSwifterKitAudioChangeInputLatency:
                return SetInputLatency(value);
            case kSwifterKitAudioChangeOutputLatency:
                return SetOutputLatency(value);
            case kSwifterKitAudioChangeZeroTimeStampPeriod:
                return SetZeroTimeStampPeriod(value);
            default:
                return kIOReturnBadArgument;
        }
    }
    if (changeAction != kClockSampleRateChangeAction)
        return super::PerformDeviceConfigurationChange(changeAction, changeInfo);
    return SwifterKitApplySampleRateChange<AudioClockFamily>(
        this,
        &ivars->pendingSampleRateBits,
        [this](uint64_t sampleRateBits) {
            return ivars->service->AudioObjectEvent(
                kSwifterKitAudioObjectEventClockRateChanged,
                ivars->index,
                sampleRateBits);
        });
}

kern_return_t SwifterKitRuntimeAudioClockDevice::AbortDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction == kClockSampleRateChangeAction)
        __atomic_store_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_RELEASE);
    return super::AbortDeviceConfigurationChange(changeAction, changeInfo);
}

kern_return_t SwifterKitRuntimeAudioClockDevice::HandleChangeSampleRate(double sampleRate) {
    if (ivars == nullptr || !IsAvailableSampleRate(sampleRate))
        return kIOReturnBadArgument;
    // IOUserAudioClockDevice.iig: on success the sample rate must already be updated. The clock
    // takes the requested rate before the request is queued, and a rejection from
    // audioCompleteRequest restores the previous rate. Without a host the framework default
    // applies.
    const double previous = GetSampleRate();
    // Nothing changes, so there is nothing for Swift to accept or reject.
    if (previous == sampleRate)
        return kIOReturnSuccess;
    kern_return_t result = SetSampleRate(sampleRate);
    if (result != kIOReturnSuccess)
        return result;
    result = ivars->service->BeginAudioRequest(
        this,
        kSwifterKitAudioObjectEventClockRequest,
        ivars->index,
        __builtin_bit_cast(uint64_t, sampleRate),
        __builtin_bit_cast(uint64_t, previous));
    if (result == kIOReturnNotAttached)
        return super::HandleChangeSampleRate(sampleRate);
    if (result != kIOReturnSuccess)
        (void)SetSampleRate(previous);
    return result;
}

kern_return_t SwifterKitRuntimeAudioClockDevice::FinishSampleRateRequest(
    double requested,
    double previous,
    bool accept) {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    if (accept)
        return ivars->service->AudioObjectEvent(
            kSwifterKitAudioObjectEventClockRateChanged,
            ivars->index,
            __builtin_bit_cast(uint64_t, requested));
    // Outside the callback the rate changes only through a device configuration change, and a
    // later change must not be undone.
    return GetSampleRate() == requested && IsAvailableSampleRate(previous)
               ? RequestSampleRate(previous)
               : kIOReturnSuccess;
}
#endif
