#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOKitKeys.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOService.h>
#include <DriverKit/IOServiceNotificationDispatchSource.h>
#include <DriverKit/IOServiceStateNotificationDispatchSource.h>
#include <DriverKit/OSAction.h>
#include <DriverKit/OSCollections.h>
#include <string.h>

#include "SwifterKitRuntimeDispatchProtocol.h"
#include "SwifterKitRuntimeDispatchSources.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceProperties.h"
#include "SwifterKitRuntimeServiceProtocol.h"
#include "SwifterKitRuntimeServiceState.h"

// Watch contract:
// - Swift holds at most kSwifterKitMaximumServiceWatches watches. A service watch owns an
//   IOServiceNotificationDispatchSource for a matching dictionary that names IOProviderClass. A
//   system-state watch owns an IOServiceStateNotificationDispatchSource on the system state
//   notification service for 1...kSwifterKitMaximumWatchedStateItems item names.
// - Each action's reference holds the watch ID, never the slot index, so a notification that
//   races a cancel is dropped instead of being reported against a reused slot.
// - A dext sees another service only as an IOService proxy that DeliverNotifications retains
//   for the block, so a service event carries the notification kind, registry entry ID, and
//   registry name. A state event carries the item name and a copy of its dictionary, read after
//   StateNotificationBegin re-arms the source; a value too large for one event is left out.
// - Events are lossy; each carries the watch's sequence number, counted from 1, so Swift can
//   detect drops. Payloads are validated here again after Swift validates them.
// - Watches belong to the connected host: DetachEventClient and Stop cancel every watch.
// - Slots change only under dispatchLock; sources are created, enabled, and cancelled after it
//   is dropped.

namespace {
    SwifterKitServiceWatch* FindWatch(SwifterKitRuntimeService_IVars* state, uint32_t watchID) {
        for (auto& slot : state->watches) {
            if (watchID != 0 && slot.watchID == watchID) {
                return &slot;
            }
        }
        return nullptr;
    }

    // Returns the watch's next sequence number, or 0 when the watch is gone.
    uint64_t NextSequence(SwifterKitRuntimeService_IVars* state, uint32_t watchID) {
        IOLockLock(state->dispatchLock);
        SwifterKitServiceWatch* slot = FindWatch(state, watchID);
        const uint64_t sequence = slot == nullptr ? 0 : ++slot->sequence;
        IOLockUnlock(state->dispatchLock);
        return sequence;
    }

    // Releases the watch's references without cancelling its source.
    void DropWatch(SwifterKitServiceWatch* watch) {
        OSSafeReleaseNULL(watch->source);
        OSSafeReleaseNULL(watch->action);
        OSSafeReleaseNULL(watch->stateService);
        OSSafeReleaseNULL(watch->items);
        *watch = {};
    }

    void ReleaseWatch(SwifterKitServiceWatch* watch) {
        if (watch->source != nullptr) {
            (void)watch->source->Cancel(nullptr);
        }
        if (watch->action != nullptr) {
            (void)watch->action->Cancel(nullptr);
        }
        DropWatch(watch);
    }

    // Moves the slot holding watchID into taken and empties the slot.
    bool TakeWatch(
        SwifterKitRuntimeService_IVars* state,
        uint32_t watchID,
        SwifterKitServiceWatch* taken) {
        IOLockLock(state->dispatchLock);
        SwifterKitServiceWatch* slot = FindWatch(state, watchID);
        if (slot != nullptr) {
            *taken = *slot;
            *slot = {};
        }
        IOLockUnlock(state->dispatchLock);
        return slot != nullptr;
    }

    // Stores watch in a free slot under a new identifier and returns the identifier, or 0 when
    // every slot is in use. The action's reference is set before the slot becomes visible.
    uint32_t ReserveWatch(
        SwifterKitRuntimeService_IVars* state,
        const SwifterKitServiceWatch& watch) {
        uint32_t watchID = 0;
        IOLockLock(state->dispatchLock);
        for (auto& slot : state->watches) {
            if (slot.watchID != 0) {
                continue;
            }
            do {
                watchID = state->nextWatchID;
                state->nextWatchID = watchID == UINT32_MAX ? 1 : watchID + 1;
            } while (FindWatch(state, watchID) != nullptr);
            SwifterKitSetActionIdentifier(watch.action, watchID);
            // The slot owns its own references: a concurrent cancel or stop may release them
            // while the command still enables the source.
            watch.source->retain();
            watch.action->retain();
            if (watch.stateService != nullptr) {
                watch.stateService->retain();
                watch.items->retain();
            }
            slot = watch;
            slot.watchID = watchID;
            break;
        }
        IOLockUnlock(state->dispatchLock);
        return watchID;
    }

    kern_return_t DecodeMatching(const uint8_t* payload, uint32_t length, OSDictionary** matching) {
        OSObject* value = nullptr;
        const kern_return_t result = SwifterKitDecodeProperty(payload, length, &value);
        if (result != kIOReturnSuccess) {
            return result;
        }
        *matching = OSDynamicCast(OSDictionary, value);
        const OSString* providerClass =
            *matching == nullptr
                ? nullptr
                : OSDynamicCast(OSString, (*matching)->getObject(kIOProviderClassKey));
        if (providerClass == nullptr || providerClass->getLength() == 0) {
            *matching = nullptr;
            value->release();
            return kIOReturnBadArgument;
        }
        return kIOReturnSuccess;
    }

    kern_return_t DecodeItems(const uint8_t* payload, uint32_t length, OSArray** items) {
        OSObject* value = nullptr;
        const kern_return_t result = SwifterKitDecodeProperty(payload, length, &value);
        if (result != kIOReturnSuccess) {
            return result;
        }
        *items = OSDynamicCast(OSArray, value);
        bool valid = *items != nullptr && (*items)->getCount() != 0
                     && (*items)->getCount() <= kSwifterKitMaximumWatchedStateItems;
        for (uint32_t index = 0; valid && index < (*items)->getCount(); index += 1) {
            const OSString* name = OSDynamicCast(OSString, (*items)->getObject(index));
            valid = name != nullptr
                    && SwifterKitIsPropertyName(
                        reinterpret_cast<const uint8_t*>(name->getCStringNoCopy()),
                        static_cast<uint32_t>(name->getLength()));
        }
        if (!valid) {
            *items = nullptr;
            value->release();
            return kIOReturnBadArgument;
        }
        return kIOReturnSuccess;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::WatchCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->dispatchLock == nullptr) {
        return kIOReturnNotReady;
    }
    const auto kind = static_cast<SwifterKitRuntimeOpcode>(opcode);
    if (kind == SwifterKitRuntimeOpcode::WatchCancel) {
        const uint32_t watchID = SwifterKitReadIdentifier(payload, payloadLength);
        SwifterKitServiceWatch taken = {};
        if (watchID == 0) {
            return kIOReturnBadArgument;
        }
        if (!TakeWatch(ivars, watchID, &taken)) {
            return kIOReturnNotFound;
        }
        ReleaseWatch(&taken);
        return kIOReturnSuccess;
    }
    if (kind != SwifterKitRuntimeOpcode::WatchServices
        && kind != SwifterKitRuntimeOpcode::WatchSystemState) {
        return kIOReturnUnsupported;
    }

    SwifterKitServiceWatch watch = {};
    OSDictionary* matching = nullptr;
    IODispatchQueue* queue = nullptr;
    kern_return_t result = kind == SwifterKitRuntimeOpcode::WatchServices
                               ? DecodeMatching(payload, payloadLength, &matching)
                               : DecodeItems(payload, payloadLength, &watch.items);
    if (result == kIOReturnSuccess) {
        result = CopyDispatchQueue(kIOServiceDefaultQueueName, &queue);
    }
    if (result == kIOReturnSuccess && kind == SwifterKitRuntimeOpcode::WatchServices) {
        IOServiceNotificationDispatchSource* source = nullptr;
        result = IOServiceNotificationDispatchSource::Create(matching, 0, queue, &source);
        watch.source = source;
        if (result == kIOReturnSuccess) {
            result = CreateActionServicesChanged(sizeof(uint32_t), &watch.action);
        }
        if (result == kIOReturnSuccess) {
            result = source->SetHandler(watch.action);
        }
    } else if (result == kIOReturnSuccess) {
        IOServiceStateNotificationDispatchSource* source = nullptr;
        result = CopySystemStateNotificationService(&watch.stateService);
        if (result == kIOReturnSuccess && watch.stateService == nullptr) {
            result = kIOReturnNotFound;
        }
        if (result == kIOReturnSuccess) {
            result = IOServiceStateNotificationDispatchSource::Create(
                watch.stateService,
                watch.items,
                queue,
                &source);
        }
        watch.source = source;
        if (result == kIOReturnSuccess) {
            result = CreateActionSystemStateChanged(sizeof(uint32_t), &watch.action);
        }
        if (result == kIOReturnSuccess) {
            result = source->SetHandler(watch.action);
        }
    }
    OSSafeReleaseNULL(queue);
    OSSafeReleaseNULL(matching);

    uint32_t watchID = 0;
    if (result == kIOReturnSuccess) {
        watchID = ReserveWatch(ivars, watch);
        result = watchID == 0 ? kIOReturnNoResources : kIOReturnSuccess;
    }
    if (result == kIOReturnSuccess) {
        result = SwifterKitEnableSource(watch.source);
    }
    if (result == kIOReturnSuccess) {
        const SwifterKitDispatchIdentifier reply = {.identifier = watchID, .reserved = 0};
        *response = OSData::withBytes(&reply, sizeof(reply));
        result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }
    if (result != kIOReturnSuccess && watchID == 0) {
        ReleaseWatch(&watch);
    } else {
        // Free the slot on failure unless a concurrent cancel or stop already took it.
        SwifterKitServiceWatch taken = {};
        if (result != kIOReturnSuccess && TakeWatch(ivars, watchID, &taken)) {
            ReleaseWatch(&taken);
        }
        DropWatch(&watch);
    }
    return result;
}

void SwifterKitRuntimeService::ServicesChanged_Impl(OSAction* action) {
    const uint32_t watchID = SwifterKitActionIdentifier(action);
    if (ivars == nullptr || ivars->dispatchLock == nullptr || watchID == 0) {
        return;
    }
    IOLockLock(ivars->dispatchLock);
    const SwifterKitServiceWatch* slot = FindWatch(ivars, watchID);
    auto* source = slot == nullptr
                       ? nullptr
                       : OSDynamicCast(IOServiceNotificationDispatchSource, slot->source);
    if (source != nullptr) {
        source->retain();
    }
    IOLockUnlock(ivars->dispatchLock);
    if (source == nullptr) {
        return;
    }

    (void)source->DeliverNotifications(^(uint64_t type, IOService* service, uint64_t) {
      if (service == nullptr
          || (type != kIOServiceNotificationTypeMatched
              && type != kIOServiceNotificationTypeTerminated)) {
          return;
      }
      uint8_t bytes[sizeof(SwifterKitServiceWatchEvent) + kSwifterKitPropertyNameMaximumLength] =
          {};
      SwifterKitServiceWatchEvent event = {
          .watchID = watchID,
          .kind = static_cast<uint32_t>(
              type == kIOServiceNotificationTypeMatched ? SwifterKitServiceWatchKind::Matched
                                                        : SwifterKitServiceWatchKind::Terminated),
          .sequence = 0,
          .registryEntryID = 0,
          .nameLength = 0,
          .reserved = 0,
      };
      uint64_t registryEntryID = 0;
      (void)service->GetRegistryEntryID(&registryEntryID);
      event.registryEntryID = registryEntryID;
      OSString* name = nullptr;
      if (service->CopyName(&name) == kIOReturnSuccess && name != nullptr) {
          const size_t length = name->getLength();
          event.nameLength = static_cast<uint32_t>(
              length < kSwifterKitPropertyNameMaximumLength ? length
                                                            : kSwifterKitPropertyNameMaximumLength);
          memcpy(bytes + sizeof(event), name->getCStringNoCopy(), event.nameLength);
      }
      OSSafeReleaseNULL(name);
      event.sequence = NextSequence(ivars, watchID);
      if (event.sequence == 0) {
          return;
      }
      memcpy(bytes, &event, sizeof(event));
      (void)EnqueueEvent(kSwifterKitEventWatchServices, bytes, sizeof(event) + event.nameLength);
    });
    source->release();
}

void SwifterKitRuntimeService::SystemStateChanged_Impl(OSAction* action) {
    const uint32_t watchID = SwifterKitActionIdentifier(action);
    if (ivars == nullptr || ivars->dispatchLock == nullptr || watchID == 0) {
        return;
    }
    IOLockLock(ivars->dispatchLock);
    const SwifterKitServiceWatch* slot = FindWatch(ivars, watchID);
    auto* source = slot == nullptr
                       ? nullptr
                       : OSDynamicCast(IOServiceStateNotificationDispatchSource, slot->source);
    IOService* system = source == nullptr ? nullptr : slot->stateService;
    const OSArray* items = source == nullptr ? nullptr : slot->items;
    if (source != nullptr) {
        source->retain();
        system->retain();
        items->retain();
    }
    IOLockUnlock(ivars->dispatchLock);
    if (source == nullptr) {
        return;
    }

    // Re-arm before reading, so a change made while the items are read notifies again.
    if (source->StateNotificationBegin() == kIOReturnSuccess) {
        for (uint32_t index = 0; index < items->getCount(); index += 1) {
            auto* name = OSDynamicCast(OSString, items->getObject(index));
            OSDictionary* value = nullptr;
            OSData* event = OSData::withCapacity(256);
            if (name == nullptr || event == nullptr) {
                OSSafeReleaseNULL(event);
                continue;
            }
            (void)system->StateNotificationItemCopy(name, &value);
            SwifterKitSystemStateEvent header = {
                .watchID = watchID,
                .nameLength = static_cast<uint32_t>(name->getLength()),
                .sequence = NextSequence(ivars, watchID),
            };
            bool valid = header.sequence != 0 && event->appendBytes(&header, sizeof(header))
                         && event->appendBytes(name->getCStringNoCopy(), header.nameLength);
            if (valid && value != nullptr) {
                // A value too large for one event travels without its dictionary.
                const size_t prefix = event->getLength();
                if (SwifterKitEncodeProperty(value, event, kSwifterKitMaximumEventPayloadLength)
                    != kIOReturnSuccess) {
                    OSData* truncated = OSData::withBytes(event->getBytesNoCopy(), prefix);
                    OSSafeReleaseNULL(event);
                    event = truncated;
                    valid = event != nullptr;
                }
            }
            if (valid) {
                (void)EnqueueEvent(
                    kSwifterKitEventWatchSystemState,
                    event->getBytesNoCopy(),
                    static_cast<uint32_t>(event->getLength()));
            }
            OSSafeReleaseNULL(value);
            OSSafeReleaseNULL(event);
        }
    }
    items->release();
    system->release();
    source->release();
}

void SwifterKitRuntimeService::StopWatches() {
    if (ivars == nullptr || ivars->dispatchLock == nullptr) {
        return;
    }
    for (uint32_t index = 0; index < kSwifterKitMaximumServiceWatches; index += 1) {
        IOLockLock(ivars->dispatchLock);
        SwifterKitServiceWatch taken = ivars->watches[index];
        ivars->watches[index] = {};
        IOLockUnlock(ivars->dispatchLock);
        ReleaseWatch(&taken);
    }
}
