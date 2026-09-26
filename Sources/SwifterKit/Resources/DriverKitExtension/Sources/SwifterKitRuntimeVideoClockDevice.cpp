#include "SwifterKitRuntimeVideoClockDevice.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeService.h"
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
        (void)ivars->service->VideoObjectEvent(3, ivars->index, static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeVideoClockDevice::StopIO(IOUserVideoStartStopFlags flags) {
    (void)ivars->service->VideoObjectEvent(4, ivars->index, static_cast<uint64_t>(flags));
    return super::StopIO(flags);
}

kern_return_t SwifterKitRuntimeVideoClockDevice::PerformDeviceConfigurationChange(
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
        result = ivars->service->VideoObjectEvent(
            5,
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
    // Swift answers through videoCompleteRequest; without a host the change proceeds at once.
    const kern_return_t result = ivars->service->BeginVideoRequest(
        this,
        kSwifterKitVideoEventClockRequest,
        ivars->index,
        __builtin_bit_cast(uint64_t, sampleRate));
    return result == kIOReturnNotAttached ? RequestSampleRate(sampleRate) : result;
}

void SwifterKitRuntimeVideoClockDevice::StreamFormatChanged(IOUserVideoObjectID streamID) {
    super::StreamFormatChanged(streamID);
    if (ivars != nullptr)
        (void)ivars->service->VideoObjectEvent(8, ivars->index, streamID);
}
#endif
