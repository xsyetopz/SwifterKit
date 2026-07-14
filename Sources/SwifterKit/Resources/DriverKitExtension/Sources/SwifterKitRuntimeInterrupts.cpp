#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_INTERRUPTS

    #include <DriverKit/IODispatchQueue.h>
    #include <DriverKit/IOInterruptDispatchSource.h>
    #include <DriverKit/IOReturn.h>
    #include <DriverKit/OSAction.h>
    #include <DriverKit/OSData.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    constexpr uint32_t kMaximumInterruptSources = 32;

    bool HasReservedBytes(const SwifterKitInterruptCommandHeader* header) {
        return header->reserved[0] != 0 || header->reserved[1] != 0 || header->reserved[2] != 0;
    }

    int32_t FindInterruptSlot(uint32_t index) {
        for (uint32_t slot = 0; slot < kSwifterKitInterruptSourceCount; ++slot) {
            if ((kSwifterKitInterruptIndices[slot] & kIOInterruptSourceIndexMask) == index) {
                return static_cast<int32_t>(slot);
            }
        }
        return -1;
    }

    OSData* DataWithUInt64(uint64_t value) {
        return OSData::withBytes(&value, sizeof(value));
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartInterrupts(IOService* provider) {
    if (provider == nullptr || ivars == nullptr || kSwifterKitInterruptSourceCount == 0
        || kSwifterKitInterruptSourceCount > kMaximumInterruptSources
        || ivars->interruptProvider != nullptr) {
        return kIOReturnBadArgument;
    }

    provider->retain();
    ivars->interruptProvider = provider;
    kern_return_t result =
        IODispatchQueue::Create("SwifterKit Interrupts", 0, 0, &ivars->interruptQueue);
    if (result != kIOReturnSuccess || ivars->interruptQueue == nullptr) {
        StopInterrupts();
        return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
    }

    for (uint32_t slot = 0; slot < kSwifterKitInterruptSourceCount; ++slot) {
        result = IOInterruptDispatchSource::Create(
            provider,
            kSwifterKitInterruptIndices[slot],
            ivars->interruptQueue,
            &ivars->interruptSources[slot]);
        if (result != kIOReturnSuccess || ivars->interruptSources[slot] == nullptr) {
            StopInterrupts();
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }

        result = CreateActionInterruptOccurred(sizeof(uint32_t), &ivars->interruptActions[slot]);
        if (result != kIOReturnSuccess || ivars->interruptActions[slot] == nullptr) {
            StopInterrupts();
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        auto* reference = static_cast<uint32_t*>(ivars->interruptActions[slot]->GetReference());
        if (reference == nullptr) {
            StopInterrupts();
            return kIOReturnNoMemory;
        }
        *reference = slot;

        result = ivars->interruptSources[slot]->SetHandler(ivars->interruptActions[slot]);
        if (result == kIOReturnSuccess) {
            result = ivars->interruptSources[slot]->SetEnableWithCompletion(true, nullptr);
        }
        if (result != kIOReturnSuccess) {
            StopInterrupts();
            return result;
        }
    }
    return kIOReturnSuccess;
}

void SwifterKitRuntimeService::StopInterrupts() {
    if (ivars == nullptr) {
        return;
    }
    for (uint32_t slot = 0; slot < kMaximumInterruptSources; ++slot) {
        if (ivars->interruptSources[slot] != nullptr) {
            (void)ivars->interruptSources[slot]->SetEnableWithCompletion(false, nullptr);
            (void)ivars->interruptSources[slot]->Cancel(nullptr);
            OSSafeReleaseNULL(ivars->interruptSources[slot]);
        }
        if (ivars->interruptActions[slot] != nullptr) {
            (void)ivars->interruptActions[slot]->Cancel(nullptr);
            OSSafeReleaseNULL(ivars->interruptActions[slot]);
        }
    }
    OSSafeReleaseNULL(ivars->interruptQueue);
    OSSafeReleaseNULL(ivars->interruptProvider);
}

void SwifterKitRuntimeService::InterruptOccurred_Impl(
    OSAction* action,
    uint64_t count,
    uint64_t time) {
    if (action == nullptr || ivars == nullptr) {
        return;
    }
    const auto* reference = static_cast<const uint32_t*>(action->GetReference());
    if (reference == nullptr || *reference >= kSwifterKitInterruptSourceCount) {
        return;
    }

    const SwifterKitInterruptEvent event = {
        .index = kSwifterKitInterruptIndices[*reference] & kIOInterruptSourceIndexMask,
        .reserved = 0,
        .count = count,
        .time = time,
    };
    (void)EnqueueEvent(0x0100, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::InterruptCommand(
    uint32_t opcode,
    const SwifterKitInterruptCommandHeader* header,
    OSData** response) {
    if (header == nullptr || response == nullptr || ivars == nullptr
        || ivars->interruptProvider == nullptr || HasReservedBytes(header)
        || header->index > kIOInterruptSourceIndexMask) {
        return kIOReturnBadArgument;
    }
    *response = nullptr;

    const int32_t slot = FindInterruptSlot(header->index);
    if (slot < 0 || ivars->interruptSources[slot] == nullptr) {
        return kIOReturnNotFound;
    }

    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::InterruptSetEnabled:
            if (header->enabled > 1) {
                return kIOReturnBadArgument;
            }
            return ivars->interruptSources[slot]->SetEnableWithCompletion(
                header->enabled != 0,
                nullptr);
        case SwifterKitRuntimeOpcode::InterruptGetType: {
            if (header->enabled != 0) {
                return kIOReturnBadArgument;
            }
            uint64_t type = 0;
            const kern_return_t result = IOInterruptDispatchSource::GetInterruptType(
                ivars->interruptProvider,
                header->index,
                &type);
            if (result == kIOReturnSuccess) {
                *response = DataWithUInt64(type);
                return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
            }
            return result;
        }
        case SwifterKitRuntimeOpcode::InterruptGetLast: {
            if (header->enabled != 0) {
                return kIOReturnBadArgument;
            }
            struct Snapshot {
                uint64_t count;
                uint64_t time;
            } snapshot = {};
            static_assert(sizeof(Snapshot) == 16);
            const kern_return_t result =
                ivars->interruptSources[slot]->GetLastInterrupt(&snapshot.count, &snapshot.time);
            if (result == kIOReturnSuccess) {
                *response = OSData::withBytes(&snapshot, sizeof(snapshot));
                return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
            }
            return result;
        }
        default:
            return kIOReturnUnsupported;
    }
}

#endif
