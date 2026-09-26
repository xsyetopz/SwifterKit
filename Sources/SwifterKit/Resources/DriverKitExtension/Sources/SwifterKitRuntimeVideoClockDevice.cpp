#include "SwifterKitRuntimeVideoClockDevice.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeVideoDeviceState.h"
    #include "SwifterKitRuntimeVideoProtocol.h"

namespace {
    constexpr uint64_t kClockSampleRateChangeAction = 0x53574B56434C4F43ULL;
}  // namespace

struct SwifterKitRuntimeVideoClockDevice_IVars {
    SwifterKitRuntimeService* service = nullptr;
    uint32_t index = 0;
    uint64_t pendingSampleRateBits = 0;
};

bool SwifterKitRuntimeVideoClockDevice::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t index,
    OSString* deviceUID,
    OSString* modelUID,
    OSString* manufacturerUID) {
    if (driver == nullptr || service == nullptr || index >= kSwifterKitVideoObjectTableCount
        || !super::init(driver, deviceUID, modelUID, manufacturerUID))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoClockDevice_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->service = service;
    ivars->index = index;
    service->retain();
    return true;
}

void SwifterKitRuntimeVideoClockDevice::free() {
    if (ivars != nullptr)
        OSSafeReleaseNULL(ivars->service);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoClockDevice_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoClockDevice::Configure(
    const SwifterKitVideoClockConfiguration* configuration) {
    if (ivars == nullptr || configuration == nullptr
        || configuration->rateCount > kSwifterKitVideoMaximumSampleRates)
        return kIOReturnBadArgument;
    OSString* name = OSString::withCString(configuration->name);
    kern_return_t result = name == nullptr ? kIOReturnNoMemory : SetName(name);
    OSSafeReleaseNULL(name);
    if (result == kIOReturnSuccess)
        result = SetTransportType(static_cast<IOUserVideoTransportType>(configuration->transport));
    if (result == kIOReturnSuccess)
        result = SetAvailableSampleRates(
            kSwifterKitVideoClockSampleRates + configuration->rateStart,
            configuration->rateCount);
    if (result == kIOReturnSuccess)
        result = SetSampleRate(configuration->initialSampleRate);
    if (result == kIOReturnSuccess)
        result = SetClockDomain(configuration->clockDomain);
    if (result == kIOReturnSuccess)
        result = SetClockAlgorithm(
            static_cast<IOUserVideoClockAlgorithm>(configuration->clockAlgorithm));
    if (result == kIOReturnSuccess)
        result = SetClockIsStable(configuration->clockIsStable);
    if (result == kIOReturnSuccess)
        result = SetIsHidden(configuration->isHidden);
    if (result == kIOReturnSuccess)
        result = SetInputLatency(configuration->inputLatency);
    if (result == kIOReturnSuccess)
        result = SetOutputLatency(configuration->outputLatency);
    return result;
}

bool SwifterKitRuntimeVideoClockDevice::IsAvailableSampleRate(double sampleRate) {
    double rates[kSwifterKitVideoMaximumSampleRates] = {};
    const size_t count = GetAvailableSampleRates(rates, kSwifterKitVideoMaximumSampleRates);
    for (size_t index = 0; index < count && index < kSwifterKitVideoMaximumSampleRates; ++index)
        if (rates[index] == sampleRate)
            return true;
    return false;
}

kern_return_t SwifterKitRuntimeVideoClockDevice::RequestSampleRate(double sampleRate) {
    if (ivars == nullptr || !IsAvailableSampleRate(sampleRate))
        return kIOReturnBadArgument;
    __atomic_store_n(
        &ivars->pendingSampleRateBits,
        __builtin_bit_cast(uint64_t, sampleRate),
        __ATOMIC_RELEASE);
    return RequestDeviceConfigurationChange(kClockSampleRateChangeAction, nullptr);
}

kern_return_t SwifterKitRuntimeVideoClockDevice::StartIO(IOUserVideoStartStopFlags flags) {
    const kern_return_t result = super::StartIO(flags);
    if (result == kIOReturnSuccess)
        (void)ivars->service->VideoObjectEvent(
            kSwifterKitVideoObjectEventClockStarted,
            ivars->index,
            static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeVideoClockDevice::StopIO(IOUserVideoStartStopFlags flags) {
    (void)ivars->service->VideoObjectEvent(
        kSwifterKitVideoObjectEventClockStopped,
        ivars->index,
        static_cast<uint64_t>(flags));
    return super::StopIO(flags);
}

kern_return_t SwifterKitRuntimeVideoClockDevice::PerformDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction == kSwifterKitVideoStructureChangeAction) {
        SwifterKitVideoStructureChange change = {};
        if (!SwifterKitReadVideoStructureChange(changeInfo, &change) || change.value > UINT32_MAX)
            return kIOReturnBadArgument;
        const auto value = static_cast<uint32_t>(change.value);
        switch (change.selector) {
            case kSwifterKitVideoChangeInputLatency:
                return SetInputLatency(value);
            case kSwifterKitVideoChangeOutputLatency:
                return SetOutputLatency(value);
            default:
                return kIOReturnBadArgument;
        }
    }
    if (changeAction != kClockSampleRateChangeAction)
        return super::PerformDeviceConfigurationChange(changeAction, changeInfo);
    const double sampleRate = __builtin_bit_cast(
        double,
        __atomic_exchange_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_ACQUIRE));
    kern_return_t result =
        IsAvailableSampleRate(sampleRate) ? SetSampleRate(sampleRate) : kIOReturnBadArgument;
    if (result == kIOReturnSuccess)
        result = ivars->service->VideoObjectEvent(
            kSwifterKitVideoObjectEventClockRateChanged,
            ivars->index,
            __builtin_bit_cast(uint64_t, sampleRate));
    return result;
}

kern_return_t SwifterKitRuntimeVideoClockDevice::AbortDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    if (changeAction == kClockSampleRateChangeAction)
        __atomic_store_n(&ivars->pendingSampleRateBits, 0, __ATOMIC_RELEASE);
    return super::AbortDeviceConfigurationChange(changeAction, changeInfo);
}

kern_return_t SwifterKitRuntimeVideoClockDevice::HandleChangeSampleRate(double sampleRate) {
    if (ivars == nullptr || !IsAvailableSampleRate(sampleRate))
        return kIOReturnBadArgument;
    // IOUserVideoClockDevice.iig: on success the sample rate must already be updated. The clock
    // takes the requested rate before the request is queued, and a rejection from
    // videoCompleteRequest restores the previous rate. Without a host the framework default
    // applies.
    const double previous = GetSampleRate();
    // Nothing changes, so there is nothing for Swift to accept or reject.
    if (previous == sampleRate)
        return kIOReturnSuccess;
    kern_return_t result = SetSampleRate(sampleRate);
    if (result != kIOReturnSuccess)
        return result;
    result = ivars->service->BeginVideoRequest(
        this,
        kSwifterKitVideoObjectEventClockRequest,
        ivars->index,
        __builtin_bit_cast(uint64_t, sampleRate),
        __builtin_bit_cast(uint64_t, previous));
    if (result == kIOReturnNotAttached)
        return super::HandleChangeSampleRate(sampleRate);
    if (result != kIOReturnSuccess)
        (void)SetSampleRate(previous);
    return result;
}

kern_return_t SwifterKitRuntimeVideoClockDevice::FinishSampleRateRequest(
    double requested,
    double previous,
    bool accept) {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    if (accept)
        return ivars->service->VideoObjectEvent(
            kSwifterKitVideoObjectEventClockRateChanged,
            ivars->index,
            __builtin_bit_cast(uint64_t, requested));
    // Outside the callback the rate changes only through a device configuration change, and a
    // later change must not be undone.
    return GetSampleRate() == requested && IsAvailableSampleRate(previous)
               ? RequestSampleRate(previous)
               : kIOReturnSuccess;
}

void SwifterKitRuntimeVideoClockDevice::StreamFormatChanged(IOUserVideoObjectID streamID) {
    super::StreamFormatChanged(streamID);
    if (ivars != nullptr)
        (void)ivars->service->VideoObjectEvent(
            kSwifterKitVideoObjectEventClockFormatChanged,
            ivars->index,
            streamID);
}
#endif
