#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>

#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

// Event queue contract:
// - Lossy events (notifications Swift may miss) and required events (requests
//   Swift must answer) use separate queues with separate fixed capacities, so
//   lossy traffic can never consume required capacity.
// - CopyNextEvent returns every queued required event before any lossy event.
//   Order is FIFO within each class; it is not preserved across classes.
// - A full queue rejects the event with kIOReturnNoSpace. A rejected or
//   unallocatable lossy event increments lossyEventDrops. A rejected required
//   event is answered by its call site with a defined failure status.
// - Both arrays are allocated at their full capacity in init(), so appending
//   under eventLock never allocates.

namespace {
    kern_return_t EnqueueInto(
        const SwifterKitRuntimeService_IVars* state,
        OSArray* queue,
        uint32_t capacity,
        uint32_t type,
        const void* payload,
        uint32_t payloadLength) {
        if (state == nullptr || state->eventLock == nullptr || queue == nullptr
            || (payloadLength != 0 && payload == nullptr)
            || payloadLength > kSwifterKitRuntimeMaximumMessageSize - sizeof(type)) {
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
        IOLockUnlock(state->eventLock);
        event->release();
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

auto SwifterKitRuntimeService::CopyNextEvent(OSData** event) -> kern_return_t {
    if (event == nullptr || ivars == nullptr || ivars->eventLock == nullptr
        || ivars->events == nullptr || ivars->requiredEvents == nullptr) {
        return kIOReturnNotReady;
    }

    IOLockLock(ivars->eventLock);
    *event = TakeFirst(ivars->requiredEvents);
    if (*event == nullptr) {
        *event = TakeFirst(ivars->events);
    }
    IOLockUnlock(ivars->eventLock);
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
