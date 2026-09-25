#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOService.h>
#include <DriverKit/IOTimerDispatchSource.h>
#include <DriverKit/OSAction.h>
#include <time.h>

#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceProtocol.h"
#include "SwifterKitRuntimeServiceState.h"

// Power-state contract:
// - DriverKit calls SetPowerState on the default queue before it changes the power state. The
//   extension queues a required servicePowerState event for Swift and acknowledges the change by
//   passing the call to super exactly once, at the first of: Swift completes the request ID;
//   kPowerStateTimeoutNanoseconds elapse; the host detaches or crashes; the service stops; or a
//   newer SetPowerState supersedes it.
// - It acknowledges at once when no host is registered, the service has stopped, the timeout
//   cannot be armed, or the event cannot be queued.
// - DriverKit's acknowledgement carries no status, so every path acknowledges the same way.
// - The pending request changes only under eventLock; the acknowledgement is sent after dropping
//   it. The timer, its action, and SetPowerState all run on the default queue, as does Stop.

namespace {
    // Below DriverKit's own acknowledgement deadline, so the system never times the change out.
    constexpr uint64_t kPowerStateTimeoutNanoseconds = 10'000'000'000ULL;
    constexpr uint64_t kPowerStateTimerLeewayNanoseconds = 100'000'000ULL;

    uint64_t Now() {
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    }

    void ReleasePowerTimer(SwifterKitRuntimeService_IVars* state) {
        if (state->powerTimer != nullptr) {
            (void)state->powerTimer->Cancel(nullptr);
        }
        if (state->powerTimerAction != nullptr) {
            (void)state->powerTimerAction->Cancel(nullptr);
        }
        OSSafeReleaseNULL(state->powerTimer);
        OSSafeReleaseNULL(state->powerTimerAction);
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::SetPowerState_Impl(uint32_t powerFlags) {
    if (ivars == nullptr || ivars->eventLock == nullptr) {
        return SetPowerState(powerFlags, SUPERDISPATCH);
    }
    // DriverKit sends one change at a time, so an unanswered request is superseded.
    (void)AnswerPowerState(0);

    kern_return_t result = kIOReturnSuccess;
    if (ivars->powerTimer == nullptr) {
        IODispatchQueue* queue = nullptr;
        result = CopyDispatchQueue(kIOServiceDefaultQueueName, &queue);
        if (result == kIOReturnSuccess) {
            result = IOTimerDispatchSource::Create(queue, &ivars->powerTimer);
        }
        OSSafeReleaseNULL(queue);
        if (result == kIOReturnSuccess) {
            result = CreateActionPowerStateTimerOccurred(0, &ivars->powerTimerAction);
        }
        if (result == kIOReturnSuccess) {
            result = ivars->powerTimer->SetHandler(ivars->powerTimerAction);
        }
        if (result != kIOReturnSuccess) {
            ReleasePowerTimer(ivars);
        }
    }

    const uint64_t deadline = Now() + kPowerStateTimeoutNanoseconds;
    IOLockLock(ivars->eventLock);
    const bool forward =
        result == kIOReturnSuccess && !ivars->powerStopped && ivars->eventClient != nullptr;
    const uint32_t requestID = ivars->nextPowerRequestID;
    if (forward) {
        ivars->nextPowerRequestID = requestID == UINT32_MAX ? 1 : requestID + 1;
        ivars->powerPending = true;
        ivars->powerRequestID = requestID;
        ivars->powerFlags = powerFlags;
        ivars->powerDeadline = deadline;
    }
    IOLockUnlock(ivars->eventLock);
    if (!forward) {
        return SetPowerState(powerFlags, SUPERDISPATCH);
    }

    const SwifterKitServicePowerStateEvent event = {
        .requestID = requestID,
        .powerFlags = powerFlags,
    };
    result = ivars->powerTimer->WakeAtTime(
        kIOTimerClockUptimeRaw,
        deadline,
        kPowerStateTimerLeewayNanoseconds);
    if (result == kIOReturnSuccess) {
        result = EnqueueRequiredEvent(kSwifterKitEventServicePowerState, &event, sizeof(event));
    }
    if (result != kIOReturnSuccess) {
        // Acknowledge now, unless a detach or completion already did.
        (void)AnswerPowerState(requestID);
    }
    return kIOReturnSuccess;
}

void SwifterKitRuntimeService::PowerStateTimerOccurred_Impl(OSAction*, uint64_t) {
    if (ivars == nullptr || ivars->eventLock == nullptr) {
        return;
    }
    IOLockLock(ivars->eventLock);
    const bool pending = ivars->powerPending;
    const uint32_t requestID = ivars->powerRequestID;
    const uint64_t deadline = ivars->powerDeadline;
    IOLockUnlock(ivars->eventLock);
    if (!pending) {
        return;
    }
    if (Now() >= deadline) {
        (void)AnswerPowerState(requestID);
    } else if (
        ivars->powerTimer == nullptr
        || ivars->powerTimer
                   ->WakeAtTime(kIOTimerClockUptimeRaw, deadline, kPowerStateTimerLeewayNanoseconds)
               != kIOReturnSuccess) {
        // A timer that fired early and cannot be re-armed must not strand the change.
        (void)AnswerPowerState(requestID);
    }
}

kern_return_t SwifterKitRuntimeService::AnswerPowerState(uint32_t requestID) {
    if (ivars == nullptr || ivars->eventLock == nullptr) {
        return kIOReturnNotReady;
    }
    IOLockLock(ivars->eventLock);
    const bool matches =
        ivars->powerPending && (requestID == 0 || requestID == ivars->powerRequestID);
    const uint32_t powerFlags = ivars->powerFlags;
    if (matches) {
        ivars->powerPending = false;
        ivars->powerRequestID = 0;
    }
    IOLockUnlock(ivars->eventLock);
    if (!matches) {
        return kIOReturnNotFound;
    }
    return SetPowerState(powerFlags, SUPERDISPATCH);
}

void SwifterKitRuntimeService::StopPower() {
    if (ivars == nullptr || ivars->eventLock == nullptr) {
        return;
    }
    IOLockLock(ivars->eventLock);
    ivars->powerStopped = true;
    IOLockUnlock(ivars->eventLock);
    (void)AnswerPowerState(0);
    ReleasePowerTimer(ivars);
}
