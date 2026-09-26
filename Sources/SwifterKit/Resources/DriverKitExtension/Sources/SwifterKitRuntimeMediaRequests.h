#ifndef SwifterKitRuntimeMediaRequests_h
#define SwifterKitRuntimeMediaRequests_h

// The host-request table shared by the audio and video runtimes: box acquisitions and clock
// sample-rate changes that Swift must answer exactly once (see the contract in
// SwifterKitRuntimeAudioRequests.cpp). The templates take a family struct that names the runtime
// box and clock-device classes, schema values, and the service ivars fields of the family's
// request table as member pointers. Like SwifterKitRuntimeMediaControls.h, this header includes
// neither framework.

#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOTimerDispatchSource.h>
#include <DriverKit/OSAction.h>
#include <time.h>

#include "SwifterKitRuntimeMediaControls.h"

// kRequestLock guards kRequests, kNextRequestID, and kRequestsStopped, and is never held while
// calling the family framework.
inline uint64_t SwifterKitUptimeNanoseconds() {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

// Removes a pending request. With `request` null, the request's reference is released too.
template<typename Family, typename State>
bool SwifterKitTakeRequest(
    State* state,
    uint32_t requestID,
    typename Family::PendingRequest* request) {
    bool found = false;
    IOLockLock(state->*Family::kRequestLock);
    for (auto& entry : state->*Family::kRequests) {
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
    IOLockUnlock(state->*Family::kRequestLock);
    return found;
}

// Creates the timeout timer; `createAction` creates the family's timer action.
template<typename Family, typename State, typename CreateAction>
kern_return_t
    SwifterKitStartRequests(State* state, IODispatchQueue* queue, CreateAction createAction) {
    IOTimerDispatchSource*& timer = state->*Family::kRequestTimer;
    OSAction*& action = state->*Family::kRequestTimerAction;
    kern_return_t result =
        queue != nullptr ? IOTimerDispatchSource::Create(queue, &timer) : kIOReturnNotReady;
    if (result == kIOReturnSuccess)
        result = createAction(&action);
    if (result == kIOReturnSuccess)
        result = timer->SetHandler(action);
    if (result == kIOReturnSuccess)
        result = timer->SetEnableWithCompletion(true, nullptr);
    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(timer);
        OSSafeReleaseNULL(action);
    }
    IOLockLock(state->*Family::kRequestLock);
    state->*Family::kRequestsStopped = result != kIOReturnSuccess;
    IOLockUnlock(state->*Family::kRequestLock);
    return result;
}

// Stops new requests, ends the pending ones through `reject`, and cancels the timer.
template<typename Family, typename State, typename Reject>
void SwifterKitStopRequests(State* state, Reject reject) {
    IOLockLock(state->*Family::kRequestLock);
    state->*Family::kRequestsStopped = true;
    IOLockUnlock(state->*Family::kRequestLock);
    reject();
    IOTimerDispatchSource*& timer = state->*Family::kRequestTimer;
    OSAction*& action = state->*Family::kRequestTimerAction;
    if (timer != nullptr)
        (void)timer->Cancel(nullptr);
    if (action != nullptr)
        (void)action->Cancel(nullptr);
    OSSafeReleaseNULL(timer);
    OSSafeReleaseNULL(action);
}

// Records a request that retains `object` and arms the timer for its deadline. On success
// `assigned` names the request, and the caller queues the event that tells Swift about it.
template<typename Family, typename State>
kern_return_t SwifterKitBeginRequest(
    State* state,
    OSObject* object,
    uint32_t kind,
    uint32_t index,
    uint64_t value,
    uint64_t previous,
    uint32_t* assigned) {
    IOLockLock(state->eventLock);
    const bool attached = state->eventClient != nullptr;
    IOLockUnlock(state->eventLock);
    if (!attached)
        return kIOReturnNotAttached;
    const uint64_t deadline = SwifterKitUptimeNanoseconds() + Family::kRequestTimeout;
    bool arm = true;
    IOLockLock(state->*Family::kRequestLock);
    typename Family::PendingRequest* slot = nullptr;
    for (auto& entry : state->*Family::kRequests) {
        if (entry.requestID != 0)
            arm = false;
        else if (slot == nullptr)
            slot = &entry;
    }
    IOTimerDispatchSource* const& timer = state->*Family::kRequestTimer;
    if (state->*Family::kRequestsStopped || timer == nullptr)
        slot = nullptr;
    if (slot != nullptr) {
        uint32_t& next = state->*Family::kNextRequestID;
        const uint32_t requestID = next == 0 ? 1 : next;
        next = requestID == UINT32_MAX ? 1 : requestID + 1;
        object->retain();
        *slot = {object, requestID, kind, index, value, previous, deadline};
        *assigned = requestID;
    }
    IOLockUnlock(state->*Family::kRequestLock);
    if (slot == nullptr)
        return timer == nullptr ? kIOReturnNotAttached : kIOReturnNoResources;
    // An earlier pending request already armed the timer for an earlier deadline.
    return arm ? timer->WakeAtTime(kIOTimerClockUptimeRaw, deadline, Family::kRequestLeeway)
               : kIOReturnSuccess;
}

// Ends a request: a box keeps or restores its acquired state, a clock device reports or undoes
// its rate. Answers run on the work queue and user-client threads, so this takes no lock.
template<typename Family>
kern_return_t SwifterKitApplyRequest(
    OSObject* object,
    uint32_t kind,
    uint64_t value,
    uint64_t previous,
    bool accept,
    int32_t failure) {
    auto* box = SwifterKitDynamicCast<typename Family::RuntimeBox>(object);
    auto* clock = SwifterKitDynamicCast<typename Family::RuntimeClockDevice>(object);
    if (kind == Family::kBoxRequest && box != nullptr) {
        // HandleChangeAcquireBox already applied the requested state; a rejection restores it.
        const kern_return_t result = box->SetIsAcquired(accept ? value != 0 : value == 0);
        const kern_return_t failed = box->SetAcquisitionFailure(
            accept         ? kIOReturnSuccess
            : failure != 0 ? failure
                           : kIOReturnError);
        return result == kIOReturnSuccess ? failed : result;
    }
    if (kind == Family::kClockRequest && clock != nullptr)
        return clock->FinishSampleRateRequest(
            __builtin_bit_cast(double, value),
            __builtin_bit_cast(double, previous),
            accept);
    return kIOReturnBadArgument;
}

// Rejects and releases each taken request with `failure`.
template<typename Family, size_t Count>
void SwifterKitEndRequests(typename Family::PendingRequest (&requests)[Count], int32_t failure) {
    for (auto& request : requests) {
        if (request.requestID != 0)
            (void)SwifterKitApplyRequest<Family>(
                request.object,
                request.kind,
                request.value,
                request.previous,
                false,
                failure);
        OSSafeReleaseNULL(request.object);
    }
}

template<typename Family, typename State>
void SwifterKitRejectRequests(State* state, int32_t failure) {
    typename Family::PendingRequest taken[Family::kPendingRequestCount] = {};
    IOLockLock(state->*Family::kRequestLock);
    for (uint32_t index = 0; index < Family::kPendingRequestCount; ++index) {
        taken[index] = (state->*Family::kRequests)[index];
        (state->*Family::kRequests)[index] = {};
    }
    IOLockUnlock(state->*Family::kRequestLock);
    SwifterKitEndRequests<Family>(taken, failure);
}

// Times out the expired requests and re-arms the timer for the next deadline. `rejectAll` runs
// when the timer cannot be re-armed, so no request is stranded.
template<typename Family, typename State, typename RejectAll>
void SwifterKitExpireRequests(State* state, RejectAll rejectAll) {
    const uint64_t now = SwifterKitUptimeNanoseconds();
    typename Family::PendingRequest expired[Family::kPendingRequestCount] = {};
    uint64_t next = 0;
    IOLockLock(state->*Family::kRequestLock);
    for (uint32_t index = 0; index < Family::kPendingRequestCount; ++index) {
        auto& entry = (state->*Family::kRequests)[index];
        if (entry.requestID == 0)
            continue;
        if (entry.deadline <= now) {
            expired[index] = entry;
            entry = {};
        } else if (next == 0 || entry.deadline < next) {
            next = entry.deadline;
        }
    }
    IOTimerDispatchSource* timer =
        state->*Family::kRequestsStopped ? nullptr : state->*Family::kRequestTimer;
    IOLockUnlock(state->*Family::kRequestLock);
    if (next != 0 && timer != nullptr
        && timer->WakeAtTime(kIOTimerClockUptimeRaw, next, Family::kRequestLeeway)
               != kIOReturnSuccess)
        rejectAll();
    SwifterKitEndRequests<Family>(expired, kIOReturnTimeout);
}

#endif
