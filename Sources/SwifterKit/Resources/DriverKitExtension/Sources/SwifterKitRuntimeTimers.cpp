#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOService.h>
#include <DriverKit/IOTimerDispatchSource.h>
#include <DriverKit/OSAction.h>
#include <DriverKit/OSData.h>
#include <string.h>
#include <time.h>

#include "SwifterKitRuntimeDispatchProtocol.h"
#include "SwifterKitRuntimeDispatchSources.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

// Timer contract:
// - Swift runs at most kSwifterKitMaximumTimers timers. Each owns an IOTimerDispatchSource on the
//   default queue and an OSAction whose reference holds the timer ID, never the slot index. A
//   firing that races a cancel is dropped instead of being reported against a reused slot.
// - Each firing queues a lossy kSwifterKitEventTimer event carrying the timer's firing count, so
//   Swift can tell how many firings it missed. A one-shot timer frees its slot when it fires. A
//   repeating timer re-arms at its previous deadline plus its interval, skipping whole periods
//   that already passed. A stalled queue never causes a burst of firings.
// - Durations are validated here again after Swift validates them.
// - Timers belong to the connected host: DetachEventClient and Stop cancel every timer.
// - Slots change only under dispatchLock. Sources are armed, cancelled, and released after it is
//   dropped.

namespace {
    uint64_t Now() {
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    }

    bool IsValid(const SwifterKitTimerStart& request) {
        return request.delay <= kSwifterKitTimerMaximumNanoseconds
               && request.leeway <= kSwifterKitTimerMaximumNanoseconds
               && (request.interval == 0
                   || (request.interval >= kSwifterKitTimerMinimumIntervalNanoseconds
                       && request.interval <= kSwifterKitTimerMaximumNanoseconds));
    }

    SwifterKitTimerSlot* FindTimer(SwifterKitRuntimeService_IVars* state, uint32_t timerID) {
        for (auto& slot : state->timers) {
            if (timerID != 0 && slot.timerID == timerID) {
                return &slot;
            }
        }
        return nullptr;
    }

    // Returns an unused nonzero identifier. The caller holds dispatchLock.
    uint32_t NextTimerID(SwifterKitRuntimeService_IVars* state) {
        uint32_t timerID = 0;
        do {
            timerID = state->nextTimerID;
            state->nextTimerID = timerID == UINT32_MAX ? 1 : timerID + 1;
        } while (FindTimer(state, timerID) != nullptr);
        return timerID;
    }

    // Empties the slot holding timerID and returns its source and action to the caller.
    bool TakeTimer(
        SwifterKitRuntimeService_IVars* state,
        uint32_t timerID,
        IOTimerDispatchSource** source,
        OSAction** action) {
        IOLockLock(state->dispatchLock);
        SwifterKitTimerSlot* slot = FindTimer(state, timerID);
        if (slot != nullptr) {
            *source = slot->source;
            *action = slot->action;
            *slot = {};
        }
        IOLockUnlock(state->dispatchLock);
        return slot != nullptr;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::TimerCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->dispatchLock == nullptr) {
        return kIOReturnNotReady;
    }
    if (static_cast<SwifterKitRuntimeOpcode>(opcode) == SwifterKitRuntimeOpcode::TimerCancel) {
        const uint32_t timerID = SwifterKitReadIdentifier(payload, payloadLength);
        IOTimerDispatchSource* source = nullptr;
        OSAction* action = nullptr;
        if (timerID == 0) {
            return kIOReturnBadArgument;
        }
        if (!TakeTimer(ivars, timerID, &source, &action)) {
            return kIOReturnNotFound;
        }
        SwifterKitReleaseSource(source, action);
        return kIOReturnSuccess;
    }
    if (static_cast<SwifterKitRuntimeOpcode>(opcode) != SwifterKitRuntimeOpcode::TimerStart) {
        return kIOReturnUnsupported;
    }

    SwifterKitTimerStart request = {};
    if (payload == nullptr || payloadLength != sizeof(request)) {
        return kIOReturnBadArgument;
    }
    memcpy(&request, payload, sizeof(request));
    if (!IsValid(request)) {
        return kIOReturnBadArgument;
    }

    IODispatchQueue* queue = nullptr;
    IOTimerDispatchSource* source = nullptr;
    OSAction* action = nullptr;
    kern_return_t result = CopyDispatchQueue(kIOServiceDefaultQueueName, &queue);
    if (result == kIOReturnSuccess) {
        result = IOTimerDispatchSource::Create(queue, &source);
    }
    OSSafeReleaseNULL(queue);
    if (result == kIOReturnSuccess) {
        result = CreateActionTimerFired(sizeof(uint32_t), &action);
    }
    if (result == kIOReturnSuccess) {
        result = source->SetHandler(action);
    }

    uint32_t timerID = 0;
    const uint64_t deadline = Now() + request.delay;
    if (result == kIOReturnSuccess) {
        IOLockLock(ivars->dispatchLock);
        SwifterKitTimerSlot* slot = nullptr;
        for (auto& candidate : ivars->timers) {
            if (candidate.timerID == 0) {
                slot = &candidate;
                break;
            }
        }
        if (slot == nullptr) {
            result = kIOReturnNoResources;
        } else {
            timerID = NextTimerID(ivars);
            SwifterKitSetActionIdentifier(action, timerID);
            // The slot owns its own references: a concurrent cancel or stop may release them
            // while this command still enables and arms the source.
            source->retain();
            action->retain();
            *slot = {
                .timerID = timerID,
                .interval = request.interval,
                .leeway = request.leeway,
                .deadline = deadline,
                .fireCount = 0,
                .source = source,
                .action = action,
            };
        }
        IOLockUnlock(ivars->dispatchLock);
    }
    if (result == kIOReturnSuccess) {
        result = SwifterKitEnableSource(source);
    }
    if (result == kIOReturnSuccess) {
        result = source->WakeAtTime(kIOTimerClockUptimeRaw, deadline, request.leeway);
    }
    if (result == kIOReturnSuccess) {
        const SwifterKitDispatchIdentifier reply = {.identifier = timerID, .reserved = 0};
        *response = OSData::withBytes(&reply, sizeof(reply));
        result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }
    if (result != kIOReturnSuccess && timerID == 0) {
        SwifterKitReleaseSource(source, action);
    } else {
        // Free the slot on failure unless a concurrent cancel or stop already took it.
        IOTimerDispatchSource* reserved = nullptr;
        OSAction* reservedAction = nullptr;
        if (result != kIOReturnSuccess && TakeTimer(ivars, timerID, &reserved, &reservedAction)) {
            SwifterKitReleaseSource(reserved, reservedAction);
        }
        OSSafeReleaseNULL(source);
        OSSafeReleaseNULL(action);
    }
    return result;
}

void SwifterKitRuntimeService::TimerFired_Impl(OSAction* action, uint64_t) {
    const uint32_t timerID = SwifterKitActionIdentifier(action);
    if (ivars == nullptr || ivars->dispatchLock == nullptr || timerID == 0) {
        return;
    }
    const uint64_t now = Now();
    IOTimerDispatchSource* rearm = nullptr;
    IOTimerDispatchSource* finished = nullptr;
    OSAction* finishedAction = nullptr;
    uint64_t deadline = 0;
    uint64_t leeway = 0;

    IOLockLock(ivars->dispatchLock);
    SwifterKitTimerSlot* slot = FindTimer(ivars, timerID);
    if (slot == nullptr) {
        IOLockUnlock(ivars->dispatchLock);
        return;
    }
    slot->fireCount += 1;
    const SwifterKitTimerEvent event = {
        .timerID = timerID,
        .reserved = 0,
        .fireCount = slot->fireCount,
        .timestamp = now,
    };
    if (slot->interval == 0) {
        finished = slot->source;
        finishedAction = slot->action;
        *slot = {};
    } else {
        slot->deadline += slot->interval;
        if (slot->deadline <= now) {
            slot->deadline += ((now - slot->deadline) / slot->interval + 1) * slot->interval;
        }
        deadline = slot->deadline;
        leeway = slot->leeway;
        rearm = slot->source;
        rearm->retain();
    }
    IOLockUnlock(ivars->dispatchLock);

    (void)EnqueueEvent(kSwifterKitEventTimer, &event, sizeof(event));
    if (rearm != nullptr) {
        const kern_return_t result = rearm->WakeAtTime(kIOTimerClockUptimeRaw, deadline, leeway);
        rearm->release();
        // A repeating timer that cannot be re-armed stops, so a later cancel reports it missing.
        if (result != kIOReturnSuccess && TakeTimer(ivars, timerID, &finished, &finishedAction)) {
            SwifterKitReleaseSource(finished, finishedAction);
        }
        return;
    }
    SwifterKitReleaseSource(finished, finishedAction);
}

void SwifterKitRuntimeService::StopTimers() {
    if (ivars == nullptr || ivars->dispatchLock == nullptr) {
        return;
    }
    for (uint32_t index = 0; index < kSwifterKitMaximumTimers; index += 1) {
        IOLockLock(ivars->dispatchLock);
        IOTimerDispatchSource* source = ivars->timers[index].source;
        OSAction* action = ivars->timers[index].action;
        ivars->timers[index] = {};
        IOLockUnlock(ivars->dispatchLock);
        SwifterKitReleaseSource(source, action);
    }
}
