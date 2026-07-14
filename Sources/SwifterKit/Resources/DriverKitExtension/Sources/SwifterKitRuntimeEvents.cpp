#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>

#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

namespace {
    constexpr uint32_t kMaximumQueuedEvents = 64;
}

auto SwifterKitRuntimeService::CopyNextEvent(OSData** event) -> kern_return_t {
    if (event == nullptr || ivars == nullptr || ivars->eventLock == nullptr
        || ivars->events == nullptr) {
        return kIOReturnNotReady;
    }

    *event = nullptr;
    IOLockLock(ivars->eventLock);
    if (ivars->events->getCount() != 0) {
        *event = OSDynamicCast(OSData, ivars->events->getObject(0));
        if (*event != nullptr) {
            (*event)->retain();
        }
        ivars->events->removeObject(0);
    }
    IOLockUnlock(ivars->eventLock);
    return kIOReturnSuccess;
}

auto SwifterKitRuntimeService::EnqueueEvent(
    uint32_t type,
    const void* payload,
    uint32_t payloadLength) -> kern_return_t {
    if (ivars == nullptr || ivars->eventLock == nullptr || ivars->events == nullptr
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

    IOLockLock(ivars->eventLock);
    const bool hasSpace = ivars->events->getCount() < kMaximumQueuedEvents;
    const bool added = hasSpace && ivars->events->setObject(event);
    IOLockUnlock(ivars->eventLock);
    event->release();
    return added ? kIOReturnSuccess : kIOReturnNoSpace;
}

auto SwifterKitRuntimeService::EnqueueRequiredEvent(
    uint32_t type,
    const void* payload,
    uint32_t payloadLength) -> kern_return_t {
    if (ivars == nullptr || ivars->eventLock == nullptr || ivars->events == nullptr
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

    IOLockLock(ivars->eventLock);
    const bool hasSpace = ivars->events->getCount() < kMaximumQueuedEvents;
    const bool added = hasSpace && ivars->events->setObject(event);
    IOLockUnlock(ivars->eventLock);
    event->release();
    return added ? kIOReturnSuccess : kIOReturnNoSpace;
}
