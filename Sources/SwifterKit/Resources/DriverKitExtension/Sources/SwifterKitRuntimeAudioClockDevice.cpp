#include "SwifterKitRuntimeAudioClockDevice.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeService.h"

namespace {
    constexpr uint64_t kClockSampleRateChangeAction = 0x53574B434C4F434BULL;
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
    ivars = IONewZero(SwifterKitRuntimeAudioClockDevice_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->service = service;
    ivars->index = index;
    service->retain();
    return true;
}

void SwifterKitRuntimeAudioClockDevice::free() {
    if (ivars != nullptr)
        OSSafeReleaseNULL(ivars->service);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioClockDevice_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioClockDevice::Configure(
    const SwifterKitAudioClockConfiguration* configuration) {
    if (ivars == nullptr || configuration == nullptr
        || configuration->rateCount > kSwifterKitAudioMaximumSampleRates)
        return kIOReturnBadArgument;
    OSString* name = OSString::withCString(configuration->name);
    kern_return_t result = name == nullptr ? kIOReturnNoMemory : SetName(name);
    OSSafeReleaseNULL(name);
    if (result == kIOReturnSuccess)
        result = SetTransportType(static_cast<IOUserAudioTransportType>(configuration->transport));
    if (result == kIOReturnSuccess)
        result = SetAvailableSampleRates(
            kSwifterKitAudioClockSampleRates + configuration->rateStart,
            configuration->rateCount);
    if (result == kIOReturnSuccess)
        result = SetSampleRate(configuration->initialSampleRate);
    if (result == kIOReturnSuccess)
        result = SetClockDomain(configuration->clockDomain);
    if (result == kIOReturnSuccess)
        result = SetClockAlgorithm(
            static_cast<IOUserAudioClockAlgorithm>(configuration->clockAlgorithm));
    if (result == kIOReturnSuccess)
        result = SetClockIsStable(configuration->clockIsStable);
    if (result == kIOReturnSuccess)
        result = SetIsHidden(configuration->isHidden);
    if (result == kIOReturnSuccess)
        result = SetInputLatency(configuration->inputLatency);
    if (result == kIOReturnSuccess)
        result = SetOutputLatency(configuration->outputLatency);
    #if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5
    if (result == kIOReturnSuccess && configuration->wantsControlsRestored >= 0)
        SetWantsControlsRestored(configuration->wantsControlsRestored != 0);
    #endif
    return result;
}

bool SwifterKitRuntimeAudioClockDevice::IsAvailableSampleRate(double sampleRate) {
    double rates[kSwifterKitAudioMaximumSampleRates] = {};
    const size_t count = GetAvailableSampleRates(rates, kSwifterKitAudioMaximumSampleRates);
    for (size_t index = 0; index < count && index < kSwifterKitAudioMaximumSampleRates; ++index)
        if (rates[index] == sampleRate)
            return true;
    return false;
}

kern_return_t SwifterKitRuntimeAudioClockDevice::RequestSampleRate(double sampleRate) {
    if (ivars == nullptr || !IsAvailableSampleRate(sampleRate))
        return kIOReturnBadArgument;
    __atomic_store_n(
        &ivars->pendingSampleRateBits,
        __builtin_bit_cast(uint64_t, sampleRate),
        __ATOMIC_RELEASE);
    return RequestDeviceConfigurationChange(kClockSampleRateChangeAction, nullptr);
}

kern_return_t SwifterKitRuntimeAudioClockDevice::StartIO(IOUserAudioStartStopFlags flags) {
    const kern_return_t result = super::StartIO(flags);
    if (result == kIOReturnSuccess)
        (void)ivars->service->AudioObjectEvent(3, ivars->index, static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeAudioClockDevice::StopIO(IOUserAudioStartStopFlags flags) {
    (void)ivars->service->AudioObjectEvent(4, ivars->index, static_cast<uint64_t>(flags));
    return super::StopIO(flags);
}

kern_return_t SwifterKitRuntimeAudioClockDevice::PerformDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction != kClockSampleRateChangeAction)
        return super::PerformDeviceConfigurationChange(changeAction, changeInfo);
    const double sampleRate = __builtin_bit_cast(
        double,
        __atomic_exchange_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_ACQUIRE));
    kern_return_t result =
        IsAvailableSampleRate(sampleRate) ? SetSampleRate(sampleRate) : kIOReturnBadArgument;
    if (result == kIOReturnSuccess)
        result = ivars->service->AudioObjectEvent(
            5,
            ivars->index,
            __builtin_bit_cast(uint64_t, sampleRate));
    return result;
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
    // Swift answers through audioCompleteRequest; without a host the change proceeds at once.
    const kern_return_t result = ivars->service->BeginAudioRequest(
        kSwifterKitAudioEventClockRequest,
        ivars->index,
        __builtin_bit_cast(uint64_t, sampleRate));
    return result == kIOReturnNotAttached ? RequestSampleRate(sampleRate) : result;
}
#endif
