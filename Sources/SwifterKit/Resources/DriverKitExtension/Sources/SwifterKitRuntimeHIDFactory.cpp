#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_HID_DEVICE_FACTORY
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSCollections.h>

    #include "SwifterKitRuntimeHIDDevice.h"
    #include "SwifterKitRuntimeHIDShared.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeUserClient.h"

// The HID device factory root: an IOUserService on IOUserResources that creates and terminates
// SwifterKitRuntimeHIDDevice children for the event client.
//
// Lifetime: a slot holds a device from IOService::Create until Swift terminates it, the device
// stops, the event client detaches, or the root stops. A slot's handle is never reused while the
// root lives. The root never calls into a device while it holds hidLock, because a device's
// Stop calls back into HIDFactoryDeviceStopped.
//
// Every device's get-report table and its terminated event fit the required-event queue.
static_assert(
    kSwifterKitMaximumQueuedRequiredEvents
    > kSwifterKitHIDMaximumDevices * (kSwifterKitHIDFactoryMaximumPendingReports + 1));

namespace {
    // Clears slot, handing back the device reference it held. The caller holds hidLock.
    SwifterKitRuntimeHIDDevice* ClearSlot(SwifterKitHIDFactorySlot& slot) {
        SwifterKitRuntimeHIDDevice* device = slot.device;
        OSSafeReleaseNULL(slot.configuration);
        slot = {};
        return device;
    }

    // Aborts a device's requests and terminates it, consuming the reference the caller holds.
    void TerminateDevice(SwifterKitRuntimeHIDDevice* device) {
        device->AbortRequests();
        (void)device->Terminate(0);
        device->release();
    }

    bool ReadHandle(const uint8_t* payload, uint32_t payloadLength, uint32_t* handle) {
        SwifterKitHIDFactoryHandle prefix = {};
        if (payload == nullptr || payloadLength < sizeof(prefix)) {
            return false;
        }
        memcpy(&prefix, payload, sizeof(prefix));
        if (prefix.handle == 0 || prefix.reserved != 0) {
            return false;
        }
        *handle = prefix.handle;
        return true;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::HIDCommand(
    [[maybe_unused]] uint32_t opcode,
    [[maybe_unused]] const uint8_t* payload,
    [[maybe_unused]] uint32_t payloadLength,
    [[maybe_unused]] OSData** response) {
    return kIOReturnUnsupported;
}

void SwifterKitRuntimeService::AbortHIDRequests() {
    if (ivars == nullptr || ivars->hidLock == nullptr) {
        return;
    }
    SwifterKitRuntimeHIDDevice* devices[kSwifterKitHIDMaximumDevices] = {};
    IORecursiveLockLock(ivars->hidLock);
    for (uint32_t index = 0; index < kSwifterKitHIDMaximumDevices; ++index) {
        // Clearing the slot IOService::Create is filling makes Create terminate its device once
        // it returns.
        devices[index] = ClearSlot(ivars->hidDevices[index]);
    }
    IORecursiveLockUnlock(ivars->hidLock);
    for (SwifterKitRuntimeHIDDevice* device : devices) {
        if (device != nullptr) {
            TerminateDevice(device);
        }
    }
}

void SwifterKitRuntimeService::StopHID() {
    if (ivars == nullptr || ivars->hidLock == nullptr) {
        return;
    }
    IORecursiveLockLock(ivars->hidLock);
    ivars->hidDevicesStopped = true;
    IORecursiveLockUnlock(ivars->hidLock);
    AbortHIDRequests();
}

kern_return_t SwifterKitRuntimeService::HIDFactoryAttachDevice(
    IOService* device,
    uint32_t* handle,
    OSData** configuration) {
    if (device == nullptr || handle == nullptr || configuration == nullptr || ivars == nullptr
        || ivars->hidLock == nullptr) {
        return kIOReturnBadArgument;
    }
    kern_return_t result = kIOReturnNotFound;
    IORecursiveLockLock(ivars->hidLock);
    for (auto& slot : ivars->hidDevices) {
        const bool created = slot.device != nullptr && slot.device == device;
        const bool creating =
            slot.device == nullptr && slot.handle != 0 && slot.handle == ivars->hidCreatingHandle;
        if (!slot.attached && slot.configuration != nullptr && (created || creating)) {
            slot.attached = true;
            *handle = slot.handle;
            *configuration = slot.configuration;
            slot.configuration = nullptr;
            result = kIOReturnSuccess;
            break;
        }
    }
    IORecursiveLockUnlock(ivars->hidLock);
    return result;
}

void SwifterKitRuntimeService::HIDFactoryDeviceStopped(uint32_t handle) {
    if (ivars == nullptr || ivars->hidLock == nullptr || handle == 0) {
        return;
    }
    const SwifterKitRuntimeHIDDevice* device = nullptr;
    bool found = false;
    IORecursiveLockLock(ivars->hidLock);
    for (auto& slot : ivars->hidDevices) {
        if (slot.handle == handle && slot.attached) {
            device = ClearSlot(slot);
            found = true;
            break;
        }
    }
    IORecursiveLockUnlock(ivars->hidLock);
    if (!found || device == nullptr) {
        // Swift or the root ended this device, or IOService::Create has not returned it yet and
        // finds its slot gone.
        return;
    }
    device->release();
    const SwifterKitHIDFactoryHandle event = {.handle = handle, .reserved = 0};
    (void)EnqueueRequiredEvent(kSwifterKitEventHIDFactoryDeviceTerminated, &event, sizeof(event));
}

namespace {
    kern_return_t CreateDevice(
        SwifterKitRuntimeService* root,
        SwifterKitRuntimeService_IVars* state,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        SwifterKitHIDFactoryConfiguration parsed = {};
        if (!SwifterKitHIDParseFactoryDevice(payload, payloadLength, &parsed)) {
            return kIOReturnBadArgument;
        }
        OSData* configuration = OSData::withBytes(payload, payloadLength);
        if (configuration == nullptr) {
            return kIOReturnNoMemory;
        }
        IORecursiveLockLock(state->hidLock);
        kern_return_t result = kIOReturnNoSpace;
        uint32_t handle = 0;
        if (state->hidDevicesStopped) {
            result = kIOReturnNotReady;
        } else if (state->hidCreatingHandle != 0) {
            result = kIOReturnBusy;
        } else {
            for (auto& slot : state->hidDevices) {
                if (slot.handle == 0) {
                    handle = state->nextHIDDeviceHandle++;
                    if (state->nextHIDDeviceHandle == 0) {
                        state->nextHIDDeviceHandle = 1;
                    }
                    slot = {.handle = handle, .configuration = configuration};
                    state->hidCreatingHandle = handle;
                    configuration = nullptr;
                    result = kIOReturnSuccess;
                    break;
                }
            }
        }
        IORecursiveLockUnlock(state->hidLock);
        OSSafeReleaseNULL(configuration);
        if (result != kIOReturnSuccess) {
            return result;
        }

        IOService* service = nullptr;
        result = root->Create(root, "HIDDeviceProperties", &service);
        auto* device = OSDynamicCast(SwifterKitRuntimeHIDDevice, service);

        SwifterKitRuntimeHIDDevice* orphan = nullptr;
        IORecursiveLockLock(state->hidLock);
        state->hidCreatingHandle = 0;
        SwifterKitHIDFactorySlot* slot = nullptr;
        for (auto& candidate : state->hidDevices) {
            if (candidate.handle == handle) {
                slot = &candidate;
            }
        }
        if (result == kIOReturnSuccess && device != nullptr && slot != nullptr) {
            slot->device = device;
            service = nullptr;
        } else {
            // A cleared slot means the client detached, the root stopped, or the device failed
            // to start while Create ran.
            result = result != kIOReturnSuccess ? result
                     : slot == nullptr          ? kIOReturnAborted
                                                : kIOReturnError;
            if (slot != nullptr) {
                orphan = ClearSlot(*slot);
            }
        }
        IORecursiveLockUnlock(state->hidLock);
        if (orphan != nullptr) {
            TerminateDevice(orphan);
        }
        if (service != nullptr) {
            (void)service->Terminate(0);
            service->release();
        }
        if (result != kIOReturnSuccess) {
            return result;
        }
        const SwifterKitHIDFactoryHandle reply = {.handle = handle, .reserved = 0};
        *response = OSData::withBytes(&reply, sizeof(reply));
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }

    // Returns a retained device for handle, or with take, removes it from its slot.
    SwifterKitRuntimeHIDDevice*
        CopyDevice(SwifterKitRuntimeService_IVars* state, uint32_t handle, bool take) {
        SwifterKitRuntimeHIDDevice* device = nullptr;
        IORecursiveLockLock(state->hidLock);
        for (auto& slot : state->hidDevices) {
            if (slot.handle == handle && slot.device != nullptr) {
                if (take) {
                    device = ClearSlot(slot);
                } else {
                    device = slot.device;
                    device->retain();
                }
                break;
            }
        }
        IORecursiveLockUnlock(state->hidLock);
        return device;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::HIDFactoryCommand(
    IOService* client,
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (response == nullptr || (payloadLength != 0 && payload == nullptr) || ivars == nullptr
        || ivars->hidLock == nullptr || ivars->eventLock == nullptr) {
        return kIOReturnBadArgument;
    }
    IOLockLock(ivars->eventLock);
    const IOService* eventClient = ivars->eventClient;
    IOLockUnlock(ivars->eventLock);
    if (eventClient == nullptr) {
        return kIOReturnNotReady;
    }
    if (client != eventClient) {
        return kIOReturnNotPermitted;
    }

    const auto code = static_cast<SwifterKitRuntimeOpcode>(opcode);
    if (code == SwifterKitRuntimeOpcode::HIDFactoryCreateDevice) {
        return CreateDevice(this, ivars, payload, payloadLength, response);
    }
    uint32_t handle = 0;
    if (!ReadHandle(payload, payloadLength, &handle)) {
        return kIOReturnBadArgument;
    }
    const uint8_t* body = payload + sizeof(SwifterKitHIDFactoryHandle);
    const uint32_t bodyLength = payloadLength - sizeof(SwifterKitHIDFactoryHandle);
    switch (code) {
        case SwifterKitRuntimeOpcode::HIDFactoryTerminateDevice:
        case SwifterKitRuntimeOpcode::HIDFactoryGetRuntimeStatistics:
            if (bodyLength != 0) {
                return kIOReturnBadArgument;
            }
            break;
        case SwifterKitRuntimeOpcode::HIDFactorySubmitInputReport:
            if (bodyLength < sizeof(SwifterKitHIDReportHeader)) {
                return kIOReturnBadArgument;
            }
            break;
        case SwifterKitRuntimeOpcode::HIDFactoryCompleteGetReport:
            break;
        default:
            return kIOReturnUnsupported;
    }

    const bool take = code == SwifterKitRuntimeOpcode::HIDFactoryTerminateDevice;
    SwifterKitRuntimeHIDDevice* device = CopyDevice(ivars, handle, take);
    if (device == nullptr) {
        return kIOReturnNotFound;
    }
    kern_return_t result = kIOReturnSuccess;
    if (take) {
        TerminateDevice(device);
        return result;
    }
    switch (code) {
        case SwifterKitRuntimeOpcode::HIDFactorySubmitInputReport: {
            const auto* header = reinterpret_cast<const SwifterKitHIDReportHeader*>(body);
            result =
                header->reportLength != bodyLength - sizeof(SwifterKitHIDReportHeader)
                    ? kIOReturnBadArgument
                    : device->SubmitInputReport(header, body + sizeof(SwifterKitHIDReportHeader));
            break;
        }
        case SwifterKitRuntimeOpcode::HIDFactoryCompleteGetReport:
            result = device->CompleteGetReport(body, bodyLength);
            break;
        default: {
            SwifterKitHIDRuntimeStatistics statistics = {};
            result = device->CopyStatistics(&statistics);
            if (result == kIOReturnSuccess) {
                *response = OSData::withBytes(&statistics, sizeof(statistics));
                result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
            }
            break;
        }
    }
    device->release();
    return result;
}
#endif
