#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>

#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"
#include "SwifterKitRuntimeUserClient.h"

// Event queue contract:
// - Lossy events (notifications Swift may miss) and required events (requests
//   Swift must answer) use separate queues with separate fixed capacities, so
//   lossy traffic can never consume required capacity.
// - CopyNextEvent returns every queued required event before any lossy event.
//   Order is FIFO within each class; it is not preserved across classes.
// - An event must fit in one poll response (runtime header, type, payload), so
//   oversize events are rejected here rather than lost when Swift polls them.
// - A full queue rejects the event with kIOReturnNoSpace. A rejected or
//   unallocatable lossy event increments lossyEventDrops. A rejected required
//   event is answered by its call site with a defined failure status.
// - Both arrays are allocated at their full capacity in init(), so appending
//   under eventLock never allocates.
//
// Notification contract (no lost wakeup, no notification storm):
// - A host registers once through kSwifterKitSelectorEventNotification. Its user
//   client keeps the OSAction; the service keeps the user client in eventClient.
// - eventNotificationArmed changes only under eventLock. A poll that finds both
//   queues empty arms it. An enqueue that succeeds while it is armed clears it and,
//   after dropping eventLock, sends exactly one AsyncCompletion. Registration arms
//   it, or notifies at once when either queue already holds an event.
// - So after the host's last empty poll, the first queued event sends one
//   notification, and later events send none until the host drains to empty
//   again. The host must register before its first drain.
// - A second registration replaces the previous client and action. When the
//   registered client stops (IOServiceClose or host exit), crashes, or the service
//   stops, DetachEventClient releases it, empties both queues, and then answers
//   every tracked request. Emptying first means a request
//   queued concurrently is still answered; at worst its stale event reaches the
//   next host, whose completion for it then fails.
// - A registration from a different user client first detaches the previous
//   client through DetachEventClient, so its tracked requests are answered as
//   when a host departs. Requests queued meanwhile wait for the new client.
// - Taking a required event frees required capacity, so CopyNextEvent then
//   retries USB completions the full required queue rejected earlier, after
//   dropping eventLock (DeliverUSBCompletions takes usbLock, then eventLock).
// - Requests that arrive while no host is registered wait in the queues for the
//   next host, as they do before the first host connects.

namespace {
    // A poll response carries the runtime header, the event type, and the payload.
    constexpr uint32_t kMaximumEventPayloadLength =
        kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize - sizeof(uint32_t);

    // Takes the registered client for one notification when the flag is armed.
    // The caller holds eventLock and sends the notification after dropping it.
    SwifterKitRuntimeUserClient* TakeNotificationTarget(SwifterKitRuntimeService_IVars* state) {
        if (!state->eventNotificationArmed || state->eventClient == nullptr) {
            return nullptr;
        }
        state->eventNotificationArmed = false;
        state->eventClient->retain();
        return state->eventClient;
    }

    void SendNotification(SwifterKitRuntimeUserClient* client) {
        if (client != nullptr) {
            client->NotifyEventsPending();
            client->release();
        }
    }

    kern_return_t EnqueueInto(
        SwifterKitRuntimeService_IVars* state,
        OSArray* queue,
        uint32_t capacity,
        uint32_t type,
        const void* payload,
        uint32_t payloadLength) {
        if (state == nullptr || state->eventLock == nullptr || queue == nullptr
            || (payloadLength != 0 && payload == nullptr)
            || payloadLength > kMaximumEventPayloadLength) {
            return kIOReturnBadArgument;
        }

        OSData* event = OSData::withCapacity(sizeof(type) + payloadLength);
        if (event == nullptr || !event->appendBytes(&type, sizeof(type))
            || (payloadLength != 0 && !event->appendBytes(payload, payloadLength))) {
            OSSafeReleaseNULL(event);
            return kIOReturnNoMemory;
        }

        IOLockLock(state->eventLock);
        const bool hasSpace = queue->getCount() < capacity;
        const bool added = hasSpace && queue->setObject(event);
        SwifterKitRuntimeUserClient* target = added ? TakeNotificationTarget(state) : nullptr;
        IOLockUnlock(state->eventLock);
        event->release();
        SendNotification(target);
        return added ? kIOReturnSuccess : kIOReturnNoSpace;
    }

    OSData* TakeFirst(OSArray* queue) {
        if (queue->getCount() == 0) {
            return nullptr;
        }
        auto* event = OSDynamicCast(OSData, queue->getObject(0));
        if (event != nullptr) {
            event->retain();
        }
        queue->removeObject(0);
        return event;
    }
}  // namespace

auto SwifterKitRuntimeService::AttachEventClient(IOService* client) -> kern_return_t {
    auto* userClient = OSDynamicCast(SwifterKitRuntimeUserClient, client);
    if (userClient == nullptr || ivars == nullptr || ivars->eventLock == nullptr
        || ivars->events == nullptr || ivars->requiredEvents == nullptr) {
        return kIOReturnBadArgument;
    }

    userClient->retain();
    IOLockLock(ivars->eventLock);
    // A different registered client is replaced: detach it as a departed host,
    // which empties both queues and answers its requests, before registering.
    // Loop, because another registration can land while eventLock is dropped.
    while (ivars->eventClient != nullptr && ivars->eventClient != userClient) {
        IOService* replaced = ivars->eventClient;
        IOLockUnlock(ivars->eventLock);
        DetachEventClient(replaced);
        IOLockLock(ivars->eventLock);
    }
    const SwifterKitRuntimeUserClient* previous = ivars->eventClient;
    ivars->eventClient = userClient;
    ivars->eventNotificationArmed = true;
    const bool pending = ivars->requiredEvents->getCount() != 0 || ivars->events->getCount() != 0;
    SwifterKitRuntimeUserClient* target = pending ? TakeNotificationTarget(ivars) : nullptr;
    IOLockUnlock(ivars->eventLock);
    OSSafeReleaseNULL(previous);
    SendNotification(target);
    return kIOReturnSuccess;
}

void SwifterKitRuntimeService::DetachEventClient(IOService* client) {
    if (ivars == nullptr || ivars->eventLock == nullptr) {
        return;
    }

    IOLockLock(ivars->eventLock);
    const SwifterKitRuntimeUserClient* detached = ivars->eventClient;
    if (detached == nullptr || (client != nullptr && client != detached)) {
        IOLockUnlock(ivars->eventLock);
        return;
    }
    ivars->eventClient = nullptr;
    ivars->eventNotificationArmed = false;
    if (ivars->requiredEvents != nullptr) {
        ivars->requiredEvents->flushCollection();
    }
    if (ivars->events != nullptr) {
        ivars->events->flushCollection();
    }
    IOLockUnlock(ivars->eventLock);
    detached->release();

    // Answer the tracked DriverKit requests the departed host can no longer
    // complete, through the paths the service uses when it stops. Family locks
    // are taken after eventLock is released; NetworkTxPacketAvailable holds
    // networkLock while it enqueues, so the reverse order could deadlock.
    // A pending power change is acknowledged, and the host's timers and watches are
    // cancelled. Serial, HID, MIDI, interrupt, audio, video, and SCSI peripheral events
    // leave no DriverKit request outstanding, so those families answer nothing.
    (void)AnswerPowerState(0);
    StopTimers();
    StopWatches();
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
    StopBlockStorage();
#endif
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
    StopSCSI();
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
    AbortNetworkTransmits();
#endif
}

auto SwifterKitRuntimeService::CopyNextEvent(OSData** event) -> kern_return_t {
    if (event == nullptr || ivars == nullptr || ivars->eventLock == nullptr
        || ivars->events == nullptr || ivars->requiredEvents == nullptr) {
        return kIOReturnNotReady;
    }

    IOLockLock(ivars->eventLock);
    *event = TakeFirst(ivars->requiredEvents);
    [[maybe_unused]] const bool tookRequired = *event != nullptr;
    if (*event == nullptr) {
        *event = TakeFirst(ivars->events);
    }
    if (*event == nullptr) {
        ivars->eventNotificationArmed = true;
    }
    IOLockUnlock(ivars->eventLock);
#if SWIFTERKIT_ENABLE_USB
    // Retry completions that the required queue rejected earlier, now that
    // this poll freed required capacity. A host that only takes events sends no
    // USB command, so the command-path retries alone would never run.
    if (tookRequired) {
        DeliverUSBCompletions();
    }
#endif
    return kIOReturnSuccess;
}

auto SwifterKitRuntimeService::EnqueueEvent(
    uint32_t type,
    const void* payload,
    uint32_t payloadLength) -> kern_return_t {
    if (ivars == nullptr || ivars->eventLock == nullptr) {
        return kIOReturnBadArgument;
    }
    const kern_return_t result = EnqueueInto(
        ivars,
        ivars->events,
        kSwifterKitMaximumQueuedLossyEvents,
        type,
        payload,
        payloadLength);
    if (result == kIOReturnNoSpace || result == kIOReturnNoMemory) {
        IOLockLock(ivars->eventLock);
        ivars->lossyEventDrops += 1;
        IOLockUnlock(ivars->eventLock);
    }
    return result;
}

auto SwifterKitRuntimeService::EnqueueRequiredEvent(
    uint32_t type,
    const void* payload,
    uint32_t payloadLength) -> kern_return_t {
    if (ivars == nullptr) {
        return kIOReturnBadArgument;
    }
    return EnqueueInto(
        ivars,
        ivars->requiredEvents,
        kSwifterKitMaximumQueuedRequiredEvents,
        type,
        payload,
        payloadLength);
}
