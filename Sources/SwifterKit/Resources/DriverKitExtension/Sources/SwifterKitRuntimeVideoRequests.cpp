#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IODispatchQueue.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOTimerDispatchSource.h>
    #include <DriverKit/OSAction.h>
    #include <VideoDriverKit/VideoDriverKit.h>
    #include <time.h>

    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeVideoBox.h"
    #include "SwifterKitRuntimeVideoClockDevice.h"
    #include "SwifterKitRuntimeVideoProtocol.h"

// Video request contract, the same as the audio one:
// - HandleChangeAcquireBox and a clock device's HandleChangeSampleRate run on the driver work
//   queue and must return at once. Each records a pending request in a table of
//   kSwifterKitVideoPendingRequestCount entries, queues a required videoObject event, and
//   returns success; a full table fails the callback with kIOReturnNoResources.
// - A request ends exactly once, at the first of: Swift answers its ID through
//   videoCompleteRequest; kVideoRequestTimeoutNanoseconds elapse (rejected with
//   kIOReturnTimeout); the host detaches or the video runtime stops (rejected with
//   kIOReturnAborted).
// - HandleChangeAcquireBox sets the requested acquired state before it reports success.
//   Accepting the request keeps that state; rejecting it restores the previous state and calls
//   SetAcquisitionFailure. Accepting a sample-rate request starts a device configuration change;
//   rejecting it leaves the rate unchanged.
// - Without a registered host or a timeout timer, the callbacks apply the framework default at
//   once.
// - Each request retains its box or clock device, so an answer needs no videoLock: answers run
//   on the work queue (timeouts) and user-client threads, and holding videoLock across
//   VideoDriverKit calls on the work queue could deadlock with VideoCommand. The table changes
//   only under videoRequestLock, which is never held while calling VideoDriverKit.
namespace {
    constexpr uint64_t kVideoRequestTimeoutNanoseconds = 10'000'000'000ULL;
    constexpr uint64_t kVideoRequestLeewayNanoseconds = 100'000'000ULL;

    uint64_t Now() {
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    }

    bool TakeRequest(
        SwifterKitRuntimeService_IVars* state,
        uint32_t requestID,
        SwifterKitVideoPendingRequest* request) {
        bool found = false;
        IOLockLock(state->videoRequestLock);
        for (auto& entry : state->videoRequests) {
            if (requestID != 0 && entry.requestID == requestID) {
                if (request != nullptr)
                    *request = entry;
                else
                    OSSafeReleaseNULL(entry.object);
                entry = {};
                found = true;
                break;
            }
        }
        IOLockUnlock(state->videoRequestLock);
        return found;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartDevice(
    IOUserVideoObjectID objectID,
    IOUserVideoStartStopFlags flags) {
    const kern_return_t result = super::StartDevice(objectID, flags);
    if (result == kIOReturnSuccess)
        (void)VideoObjectEvent(1, objectID, static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeService::StopDevice(
    IOUserVideoObjectID objectID,
    IOUserVideoStartStopFlags flags) {
    (void)VideoObjectEvent(2, objectID, static_cast<uint64_t>(flags));
    return super::StopDevice(objectID, flags);
}

kern_return_t
    SwifterKitRuntimeService::VideoObjectEvent(uint32_t kind, uint32_t index, uint64_t value) {
    const SwifterKitVideoObjectEvent event = {kind, index, 0, 0, value};
    return EnqueueEvent(kSwifterKitEventVideoObject, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::StartVideoRequests() {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return kIOReturnNotReady;
    // The timer shares the driver work queue with the callbacks that create requests.
    OSSharedPtr<IODispatchQueue> queue = GetWorkQueue();
    kern_return_t result =
        queue ? IOTimerDispatchSource::Create(queue.get(), &ivars->videoRequestTimer)
              : kIOReturnNotReady;
    if (result == kIOReturnSuccess)
        result = CreateActionVideoRequestTimerOccurred(0, &ivars->videoRequestTimerAction);
    if (result == kIOReturnSuccess)
        result = ivars->videoRequestTimer->SetHandler(ivars->videoRequestTimerAction);
    if (result == kIOReturnSuccess)
        result = ivars->videoRequestTimer->SetEnableWithCompletion(true, nullptr);
    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(ivars->videoRequestTimer);
        OSSafeReleaseNULL(ivars->videoRequestTimerAction);
    }
    IOLockLock(ivars->videoRequestLock);
    ivars->videoRequestsStopped = result != kIOReturnSuccess;
    IOLockUnlock(ivars->videoRequestLock);
    return result;
}

void SwifterKitRuntimeService::StopVideoRequests() {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return;
    IOLockLock(ivars->videoRequestLock);
    ivars->videoRequestsStopped = true;
    IOLockUnlock(ivars->videoRequestLock);
    RejectVideoRequests(kIOReturnAborted);
    if (ivars->videoRequestTimer != nullptr)
        (void)ivars->videoRequestTimer->Cancel(nullptr);
    if (ivars->videoRequestTimerAction != nullptr)
        (void)ivars->videoRequestTimerAction->Cancel(nullptr);
    OSSafeReleaseNULL(ivars->videoRequestTimer);
    OSSafeReleaseNULL(ivars->videoRequestTimerAction);
}

kern_return_t SwifterKitRuntimeService::BeginVideoRequest(
    OSObject* object,
    uint32_t kind,
    uint32_t index,
    uint64_t value) {
    if (ivars == nullptr || ivars->eventLock == nullptr || ivars->videoRequestLock == nullptr
        || object == nullptr)
        return kIOReturnNotReady;
    IOLockLock(ivars->eventLock);
    const bool attached = ivars->eventClient != nullptr;
    IOLockUnlock(ivars->eventLock);
    if (!attached)
        return kIOReturnNotAttached;
    const uint64_t deadline = Now() + kVideoRequestTimeoutNanoseconds;
    uint32_t requestID = 0;
    bool arm = true;
    IOLockLock(ivars->videoRequestLock);
    SwifterKitVideoPendingRequest* slot = nullptr;
    for (auto& entry : ivars->videoRequests) {
        if (entry.requestID != 0)
            arm = false;
        else if (slot == nullptr)
            slot = &entry;
    }
    if (ivars->videoRequestsStopped || ivars->videoRequestTimer == nullptr)
        slot = nullptr;
    if (slot != nullptr) {
        requestID = ivars->nextVideoRequestID == 0 ? 1 : ivars->nextVideoRequestID;
        ivars->nextVideoRequestID = requestID == UINT32_MAX ? 1 : requestID + 1;
        object->retain();
        *slot = {object, requestID, kind, index, value, deadline};
    }
    IOLockUnlock(ivars->videoRequestLock);
    if (slot == nullptr)
        return ivars->videoRequestTimer == nullptr ? kIOReturnNotAttached : kIOReturnNoResources;
    // An earlier pending request already armed the timer for an earlier deadline.
    kern_return_t result = arm ? ivars->videoRequestTimer->WakeAtTime(
                                     kIOTimerClockUptimeRaw,
                                     deadline,
                                     kVideoRequestLeewayNanoseconds)
                               : kIOReturnSuccess;
    const SwifterKitVideoObjectEvent event = {kind, index, requestID, 0, value};
    if (result == kIOReturnSuccess)
        result = EnqueueRequiredEvent(kSwifterKitEventVideoObject, &event, sizeof(event));
    if (result != kIOReturnSuccess)
        (void)TakeRequest(ivars, requestID, nullptr);
    return result;
}

kern_return_t SwifterKitRuntimeService::CompleteVideoRequest(
    uint32_t requestID,
    bool accept,
    int32_t failure) {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return kIOReturnNotReady;
    SwifterKitVideoPendingRequest request = {};
    if (!TakeRequest(ivars, requestID, &request))
        return kIOReturnNotFound;
    const kern_return_t result =
        ApplyVideoRequest(request.object, request.kind, request.value, accept, failure);
    OSSafeReleaseNULL(request.object);
    return result;
}

kern_return_t SwifterKitRuntimeService::ApplyVideoRequest(
    OSObject* object,
    uint32_t kind,
    uint64_t value,
    bool accept,
    int32_t failure) {
    auto* box = OSDynamicCast(SwifterKitRuntimeVideoBox, object);
    auto* clock = OSDynamicCast(SwifterKitRuntimeVideoClockDevice, object);
    if (kind == kSwifterKitVideoEventBoxRequest && box != nullptr) {
        // HandleChangeAcquireBox already applied the requested state; a rejection restores it.
        kern_return_t result = box->SetIsAcquired(accept ? value != 0 : value == 0);
        const kern_return_t failed = box->SetAcquisitionFailure(
            accept         ? kIOReturnSuccess
            : failure != 0 ? failure
                           : kIOReturnError);
        return result == kIOReturnSuccess ? failed : result;
    }
    if (kind == kSwifterKitVideoEventClockRequest && clock != nullptr)
        return accept ? clock->RequestSampleRate(__builtin_bit_cast(double, value))
                      : kIOReturnSuccess;
    return kIOReturnBadArgument;
}

void SwifterKitRuntimeService::RejectVideoRequests(int32_t failure) {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return;
    SwifterKitVideoPendingRequest taken[kSwifterKitVideoPendingRequestCount] = {};
    IOLockLock(ivars->videoRequestLock);
    for (uint32_t index = 0; index < kSwifterKitVideoPendingRequestCount; ++index) {
        taken[index] = ivars->videoRequests[index];
        ivars->videoRequests[index] = {};
    }
    IOLockUnlock(ivars->videoRequestLock);
    for (auto& request : taken) {
        if (request.requestID != 0)
            (void)ApplyVideoRequest(request.object, request.kind, request.value, false, failure);
        OSSafeReleaseNULL(request.object);
    }
}

void SwifterKitRuntimeService::VideoRequestTimerOccurred_Impl(OSAction*, uint64_t) {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return;
    const uint64_t now = Now();
    SwifterKitVideoPendingRequest expired[kSwifterKitVideoPendingRequestCount] = {};
    uint64_t next = 0;
    IOLockLock(ivars->videoRequestLock);
    for (uint32_t index = 0; index < kSwifterKitVideoPendingRequestCount; ++index) {
        auto& entry = ivars->videoRequests[index];
        if (entry.requestID == 0)
            continue;
        if (entry.deadline <= now) {
            expired[index] = entry;
            entry = {};
        } else if (next == 0 || entry.deadline < next) {
            next = entry.deadline;
        }
    }
    IOTimerDispatchSource* timer = ivars->videoRequestsStopped ? nullptr : ivars->videoRequestTimer;
    IOLockUnlock(ivars->videoRequestLock);
    if (next != 0 && timer != nullptr
        && timer->WakeAtTime(kIOTimerClockUptimeRaw, next, kVideoRequestLeewayNanoseconds)
               != kIOReturnSuccess)
        // A deadline that cannot be re-armed must not strand its request.
        RejectVideoRequests(kIOReturnTimeout);
    for (auto& request : expired) {
        if (request.requestID != 0)
            (void)ApplyVideoRequest(
                request.object,
                request.kind,
                request.value,
                false,
                kIOReturnTimeout);
        OSSafeReleaseNULL(request.object);
    }
}
#endif
