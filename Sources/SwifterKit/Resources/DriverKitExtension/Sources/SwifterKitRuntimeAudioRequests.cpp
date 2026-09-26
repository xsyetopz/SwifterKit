#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IODispatchQueue.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOTimerDispatchSource.h>
    #include <DriverKit/OSAction.h>
    #include <time.h>

    #include "SwifterKitRuntimeAudioBox.h"
    #include "SwifterKitRuntimeAudioClockDevice.h"
    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

// Audio request contract:
// - HandleChangeAcquireBox and a clock device's HandleChangeSampleRate run on the driver work
//   queue and must return at once. Each records a pending request in a table of
//   kSwifterKitAudioPendingRequestCount entries, queues a required audioObject event, and
//   returns success; a full table fails the callback with kIOReturnNoResources.
// - A request ends exactly once, at the first of: Swift answers its ID through
//   audioCompleteRequest; kAudioRequestTimeoutNanoseconds elapse (rejected with
//   kIOReturnTimeout); the host detaches or the audio runtime stops (rejected with
//   kIOReturnAborted).
// - Accepting a box request calls SetIsAcquired; rejecting it calls SetAcquisitionFailure.
//   Accepting a sample-rate request starts a device configuration change; rejecting it leaves
//   the rate unchanged.
// - Without a registered host the callbacks apply the framework default at once.
// - The table changes only under audioRequestLock, which is never held while calling
//   AudioDriverKit; answers are applied under audioLock after dropping it.
namespace {
    constexpr uint64_t kAudioRequestTimeoutNanoseconds = 10'000'000'000ULL;
    constexpr uint64_t kAudioRequestLeewayNanoseconds = 100'000'000ULL;

    uint64_t Now() {
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    }

    bool TakeRequest(
        SwifterKitRuntimeService_IVars* state,
        uint32_t requestID,
        SwifterKitAudioPendingRequest* request) {
        bool found = false;
        IOLockLock(state->audioRequestLock);
        for (auto& entry : state->audioRequests) {
            if (requestID != 0 && entry.requestID == requestID) {
                if (request != nullptr)
                    *request = entry;
                entry = {};
                found = true;
                break;
            }
        }
        IOLockUnlock(state->audioRequestLock);
        return found;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartDevice(
    IOUserAudioObjectID objectID,
    IOUserAudioStartStopFlags flags) {
    const kern_return_t result = super::StartDevice(objectID, flags);
    if (result == kIOReturnSuccess)
        (void)AudioObjectEvent(1, objectID, static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeService::StopDevice(
    IOUserAudioObjectID objectID,
    IOUserAudioStartStopFlags flags) {
    (void)AudioObjectEvent(2, objectID, static_cast<uint64_t>(flags));
    return super::StopDevice(objectID, flags);
}

kern_return_t
    SwifterKitRuntimeService::AudioObjectEvent(uint32_t kind, uint32_t index, uint64_t value) {
    const SwifterKitAudioObjectEvent event = {kind, index, 0, 0, value};
    return EnqueueEvent(kSwifterKitEventAudioObject, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::StartAudioRequests() {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return kIOReturnNotReady;
    // The timer shares the driver work queue with the callbacks that create requests.
    OSSharedPtr<IODispatchQueue> queue = GetWorkQueue();
    kern_return_t result =
        queue ? IOTimerDispatchSource::Create(queue.get(), &ivars->audioRequestTimer)
              : kIOReturnNotReady;
    if (result == kIOReturnSuccess)
        result = CreateActionAudioRequestTimerOccurred(0, &ivars->audioRequestTimerAction);
    if (result == kIOReturnSuccess)
        result = ivars->audioRequestTimer->SetHandler(ivars->audioRequestTimerAction);
    if (result == kIOReturnSuccess)
        result = ivars->audioRequestTimer->SetEnableWithCompletion(true, nullptr);
    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(ivars->audioRequestTimer);
        OSSafeReleaseNULL(ivars->audioRequestTimerAction);
    }
    IOLockLock(ivars->audioRequestLock);
    ivars->audioRequestsStopped = result != kIOReturnSuccess;
    IOLockUnlock(ivars->audioRequestLock);
    return result;
}

void SwifterKitRuntimeService::StopAudioRequests() {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return;
    IOLockLock(ivars->audioRequestLock);
    ivars->audioRequestsStopped = true;
    IOLockUnlock(ivars->audioRequestLock);
    RejectAudioRequests(kIOReturnAborted);
    if (ivars->audioRequestTimer != nullptr)
        (void)ivars->audioRequestTimer->Cancel(nullptr);
    if (ivars->audioRequestTimerAction != nullptr)
        (void)ivars->audioRequestTimerAction->Cancel(nullptr);
    OSSafeReleaseNULL(ivars->audioRequestTimer);
    OSSafeReleaseNULL(ivars->audioRequestTimerAction);
}

kern_return_t
    SwifterKitRuntimeService::BeginAudioRequest(uint32_t kind, uint32_t index, uint64_t value) {
    if (ivars == nullptr || ivars->eventLock == nullptr || ivars->audioRequestLock == nullptr)
        return kIOReturnNotReady;
    IOLockLock(ivars->eventLock);
    const bool attached = ivars->eventClient != nullptr;
    IOLockUnlock(ivars->eventLock);
    if (!attached)
        return kIOReturnNotAttached;
    const uint64_t deadline = Now() + kAudioRequestTimeoutNanoseconds;
    uint32_t requestID = 0;
    bool arm = true;
    IOLockLock(ivars->audioRequestLock);
    SwifterKitAudioPendingRequest* slot = nullptr;
    for (auto& entry : ivars->audioRequests) {
        if (entry.requestID != 0)
            arm = false;
        else if (slot == nullptr)
            slot = &entry;
    }
    if (ivars->audioRequestsStopped || ivars->audioRequestTimer == nullptr)
        slot = nullptr;
    if (slot != nullptr) {
        requestID = ivars->nextAudioRequestID == 0 ? 1 : ivars->nextAudioRequestID;
        ivars->nextAudioRequestID = requestID == UINT32_MAX ? 1 : requestID + 1;
        *slot = {requestID, kind, index, value, deadline};
    }
    IOLockUnlock(ivars->audioRequestLock);
    if (slot == nullptr)
        return ivars->audioRequestTimer == nullptr ? kIOReturnNotAttached : kIOReturnNoResources;
    // An earlier pending request already armed the timer for an earlier deadline.
    kern_return_t result = arm ? ivars->audioRequestTimer->WakeAtTime(
                                     kIOTimerClockUptimeRaw,
                                     deadline,
                                     kAudioRequestLeewayNanoseconds)
                               : kIOReturnSuccess;
    const SwifterKitAudioObjectEvent event = {kind, index, requestID, 0, value};
    if (result == kIOReturnSuccess)
        result = EnqueueRequiredEvent(kSwifterKitEventAudioObject, &event, sizeof(event));
    if (result != kIOReturnSuccess)
        (void)TakeRequest(ivars, requestID, nullptr);
    return result;
}

kern_return_t SwifterKitRuntimeService::CompleteAudioRequest(
    uint32_t requestID,
    bool accept,
    int32_t failure) {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return kIOReturnNotReady;
    SwifterKitAudioPendingRequest request = {};
    if (!TakeRequest(ivars, requestID, &request))
        return kIOReturnNotFound;
    return ApplyAudioRequest(request.kind, request.index, request.value, accept, failure);
}

kern_return_t SwifterKitRuntimeService::ApplyAudioRequest(
    uint32_t kind,
    uint32_t index,
    uint64_t value,
    bool accept,
    int32_t failure) {
    if (ivars == nullptr || ivars->audioLock == nullptr
        || index >= kSwifterKitAudioObjectTableCount)
        return kIOReturnBadArgument;
    kern_return_t result = kIOReturnNotFound;
    IOLockLock(ivars->audioLock);
    if (kind == kSwifterKitAudioEventBoxRequest && ivars->audioBoxes[index] != nullptr) {
        SwifterKitRuntimeAudioBox* box = ivars->audioBoxes[index];
        result = box->SetAcquisitionFailure(
            accept         ? kIOReturnSuccess
            : failure != 0 ? failure
                           : kIOReturnError);
        if (accept && result == kIOReturnSuccess)
            result = box->SetIsAcquired(value != 0);
    } else if (
        kind == kSwifterKitAudioEventClockRequest && ivars->audioClockDevices[index] != nullptr) {
        result = accept ? ivars->audioClockDevices[index]->RequestSampleRate(
                              __builtin_bit_cast(double, value))
                        : kIOReturnSuccess;
    }
    IOLockUnlock(ivars->audioLock);
    return result;
}

void SwifterKitRuntimeService::RejectAudioRequests(int32_t failure) {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return;
    SwifterKitAudioPendingRequest taken[kSwifterKitAudioPendingRequestCount] = {};
    IOLockLock(ivars->audioRequestLock);
    for (uint32_t index = 0; index < kSwifterKitAudioPendingRequestCount; ++index) {
        taken[index] = ivars->audioRequests[index];
        ivars->audioRequests[index] = {};
    }
    IOLockUnlock(ivars->audioRequestLock);
    for (const auto& request : taken)
        if (request.requestID != 0)
            (void)ApplyAudioRequest(request.kind, request.index, request.value, false, failure);
}

void SwifterKitRuntimeService::AudioRequestTimerOccurred_Impl(OSAction*, uint64_t) {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return;
    const uint64_t now = Now();
    SwifterKitAudioPendingRequest expired[kSwifterKitAudioPendingRequestCount] = {};
    uint64_t next = 0;
    IOLockLock(ivars->audioRequestLock);
    for (uint32_t index = 0; index < kSwifterKitAudioPendingRequestCount; ++index) {
        auto& entry = ivars->audioRequests[index];
        if (entry.requestID == 0)
            continue;
        if (entry.deadline <= now) {
            expired[index] = entry;
            entry = {};
        } else if (next == 0 || entry.deadline < next) {
            next = entry.deadline;
        }
    }
    IOTimerDispatchSource* timer = ivars->audioRequestsStopped ? nullptr : ivars->audioRequestTimer;
    IOLockUnlock(ivars->audioRequestLock);
    if (next != 0 && timer != nullptr
        && timer->WakeAtTime(kIOTimerClockUptimeRaw, next, kAudioRequestLeewayNanoseconds)
               != kIOReturnSuccess)
        // A deadline that cannot be re-armed must not strand its request.
        RejectAudioRequests(kIOReturnTimeout);
    for (const auto& request : expired)
        if (request.requestID != 0)
            (void)ApplyAudioRequest(
                request.kind,
                request.index,
                request.value,
                false,
                kIOReturnTimeout);
}
#endif
