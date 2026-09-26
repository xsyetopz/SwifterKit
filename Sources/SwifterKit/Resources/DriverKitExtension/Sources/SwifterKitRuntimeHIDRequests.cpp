#include <DriverKit/IOLib.h>
#include <DriverKit/OSCollections.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

#if SWIFTERKIT_HID_DEVICE
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>

    #include "SwifterKitRuntimeServiceProperties.h"
#endif

// IOHIDDevice requests the host makes of a generated IOUserHIDDevice or IOUserUSBHostHIDDevice
// and Swift answers: get-report completion, property changes, and USB HID device control.
//
// Completion ownership: getReport returns success only after it records the request and queues
// a required event. From then on CompleteReport runs exactly once, when Swift answers through
// hidCompleteGetReport or, with kIOReturnAborted, when the host detaches or the service stops.
// An error return leaves completion to the caller.
#if SWIFTERKIT_HID_DEVICE
namespace {
    constexpr uint32_t kMaximumEventPayload =
        kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize - sizeof(uint32_t);
    // Swift answers with a command header and a completion header before the report bytes.
    constexpr uint32_t kMaximumAnsweredReport =
        kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize
        - sizeof(SwifterKitRuntimeCommandHeader) - sizeof(SwifterKitHIDReportCompletion);

    bool AnswersReportType(IOHIDReportType reportType) {
        switch (reportType) {
            case kIOHIDReportTypeInput:
                return (kSwifterKitHIDAnsweredReportTypes & kSwifterKitHIDGetReportInput) != 0;
            case kIOHIDReportTypeOutput:
                return (kSwifterKitHIDAnsweredReportTypes & kSwifterKitHIDGetReportOutput) != 0;
            case kIOHIDReportTypeFeature:
                return (kSwifterKitHIDAnsweredReportTypes & kSwifterKitHIDGetReportFeature) != 0;
            default:
                return false;
        }
    }

    kern_return_t
        CopyIntoDescriptor(IOMemoryDescriptor* report, const uint8_t* bytes, uint32_t length) {
        IOMemoryMap* map = nullptr;
        kern_return_t result = report->CreateMapping(0, 0, 0, length, 0, &map);
        if (result == kIOReturnSuccess && (map == nullptr || map->GetAddress() == 0)) {
            result = kIOReturnNoMemory;
        }
        if (result == kIOReturnSuccess) {
            memcpy(
                reinterpret_cast<void*>(static_cast<uintptr_t>(map->GetAddress())),
                bytes,
                length);
        }
        OSSafeReleaseNULL(map);
        return result;
    }

    // Takes the pending request with requestID out of the table, or every request when
    // requestID is zero. The caller holds hidLock.
    uint32_t TakeRequests(
        SwifterKitRuntimeService_IVars* state,
        uint32_t requestID,
        SwifterKitHIDPendingReport* taken) {
        uint32_t count = 0;
        for (auto& slot : state->hidRequests) {
            if (slot.requestID != 0 && (requestID == 0 || slot.requestID == requestID)) {
                taken[count++] = slot;
                slot = {};
            }
        }
        return count;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::getReport(
    IOMemoryDescriptor* report,
    IOHIDReportType reportType,
    IOOptionBits options,
    uint32_t completionTimeout,
    OSAction* action) {
    if (!AnswersReportType(reportType)) {
    #if SWIFTERKIT_HID_USB_DEVICE
        return super::getReport(report, reportType, options, completionTimeout, action);
    #else
        return kIOReturnUnsupported;
    #endif
    }
    if (report == nullptr || action == nullptr || ivars == nullptr || ivars->hidLock == nullptr
        || ivars->eventLock == nullptr) {
        return kIOReturnBadArgument;
    }
    uint64_t length = 0;
    kern_return_t result = report->GetLength(&length);
    if (result != kIOReturnSuccess || length == 0 || length > kMaximumAnsweredReport) {
        return kIOReturnBadArgument;
    }
    IOLockLock(ivars->eventLock);
    const bool attached = ivars->eventClient != nullptr;
    IOLockUnlock(ivars->eventLock);
    if (!attached) {
        return kIOReturnNotReady;
    }

    SwifterKitHIDGetReportRequest event = {
        .requestID = 0,
        .reportType = static_cast<uint32_t>(reportType),
        .options = static_cast<uint32_t>(options),
        .capacity = static_cast<uint32_t>(length),
        .timeout = completionTimeout,
        .reserved = 0,
    };
    IORecursiveLockLock(ivars->hidLock);
    for (auto& slot : ivars->hidRequests) {
        if (slot.requestID == 0) {
            event.requestID = ivars->nextHIDRequestID++;
            if (ivars->nextHIDRequestID == 0) {
                ivars->nextHIDRequestID = 1;
            }
            action->retain();
            report->retain();
            slot = {
                .requestID = event.requestID,
                .capacity = event.capacity,
                .action = action,
                .report = report,
            };
            break;
        }
    }
    IORecursiveLockUnlock(ivars->hidLock);
    if (event.requestID == 0) {
        return kIOReturnNoResources;
    }

    result = EnqueueRequiredEvent(kSwifterKitEventHIDGetReportRequest, &event, sizeof(event));
    if (result != kIOReturnSuccess) {
        SwifterKitHIDPendingReport taken[1] = {};
        IORecursiveLockLock(ivars->hidLock);
        const uint32_t count = TakeRequests(ivars, event.requestID, taken);
        IORecursiveLockUnlock(ivars->hidLock);
        if (count == 1) {
            OSSafeReleaseNULL(taken[0].action);
            OSSafeReleaseNULL(taken[0].report);
        }
    }
    return result;
}

void SwifterKitRuntimeService::AbortHIDRequests() {
    if (ivars == nullptr || ivars->hidLock == nullptr) {
        return;
    }
    SwifterKitHIDPendingReport taken[kSwifterKitHIDMaximumPendingReports] = {};
    IORecursiveLockLock(ivars->hidLock);
    const uint32_t count = TakeRequests(ivars, 0, taken);
    IORecursiveLockUnlock(ivars->hidLock);
    for (uint32_t index = 0; index < count; ++index) {
        CompleteReport(taken[index].action, kIOReturnAborted, 0);
        OSSafeReleaseNULL(taken[index].action);
        OSSafeReleaseNULL(taken[index].report);
    }
}

void SwifterKitRuntimeService::StopHID() {
    AbortHIDRequests();
}

void SwifterKitRuntimeService::setProperty(OSObject* key, OSObject* value) {
    const OSString* name = OSDynamicCast(OSString, key);
    if (name != nullptr && value != nullptr) {
        OSDictionary* change = OSDictionary::withCapacity(1);
        OSData* payload = OSData::withCapacity(64);
        if (change != nullptr && payload != nullptr && change->setObject(name, value)
            && SwifterKitEncodeProperty(change, payload, kMaximumEventPayload)
                   == kIOReturnSuccess) {
            (void)EnqueueEvent(
                kSwifterKitEventHIDProperties,
                payload->getBytesNoCopy(),
                static_cast<uint32_t>(payload->getLength()));
        }
        OSSafeReleaseNULL(payload);
        OSSafeReleaseNULL(change);
    }
    super::setProperty(key, value);
}

kern_return_t SwifterKitRuntimeService::CompleteHIDGetReport(
    const uint8_t* payload,
    uint32_t payloadLength) {
    SwifterKitRuntimeService_IVars* state = ivars;
    {
        if (state == nullptr || state->hidLock == nullptr
            || payloadLength < sizeof(SwifterKitHIDReportCompletion)) {
            return kIOReturnBadArgument;
        }
        SwifterKitHIDReportCompletion completion = {};
        memcpy(&completion, payload, sizeof(completion));
        if (completion.requestID == 0 || completion.reserved != 0
            || completion.length != payloadLength - sizeof(completion)
            || (completion.status != kIOReturnSuccess && completion.length != 0)) {
            return kIOReturnBadArgument;
        }
        SwifterKitHIDPendingReport taken[1] = {};
        IORecursiveLockLock(state->hidLock);
        for (const auto& slot : state->hidRequests) {
            if (slot.requestID == completion.requestID && completion.length > slot.capacity) {
                IORecursiveLockUnlock(state->hidLock);
                return kIOReturnBadArgument;
            }
        }
        const uint32_t count = TakeRequests(state, completion.requestID, taken);
        IORecursiveLockUnlock(state->hidLock);
        if (count == 0) {
            return kIOReturnNotFound;
        }
        kern_return_t result = kIOReturnSuccess;
        IOReturn status = completion.status;
        uint32_t length = completion.length;
        if (status == kIOReturnSuccess && length != 0) {
            result = CopyIntoDescriptor(taken[0].report, payload + sizeof(completion), length);
            if (result != kIOReturnSuccess) {
                status = result;
                length = 0;
            }
        }
        CompleteReport(taken[0].action, status, length);
        OSSafeReleaseNULL(taken[0].action);
        OSSafeReleaseNULL(taken[0].report);
        return result;
    }
}

    #if SWIFTERKIT_HID_USB_DEVICE
namespace {
    kern_return_t
        ReadDescriptor(IOBufferMemoryDescriptor* buffer, uint32_t length, OSData** response) {
        IOMemoryMap* map = nullptr;
        kern_return_t result = buffer->CreateMapping(kIOMemoryMapReadOnly, 0, 0, length, 0, &map);
        if (result == kIOReturnSuccess && (map == nullptr || map->GetAddress() == 0)) {
            result = kIOReturnNoMemory;
        }
        if (result == kIOReturnSuccess) {
            *response = OSData::withBytes(
                reinterpret_cast<const void*>(static_cast<uintptr_t>(map->GetAddress())),
                length);
            result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
        OSSafeReleaseNULL(map);
        return result;
    }
}  // namespace
    #endif

kern_return_t SwifterKitRuntimeService::HIDCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (response == nullptr || (payloadLength != 0 && payload == nullptr)) {
        return kIOReturnBadArgument;
    }
    const auto code = static_cast<SwifterKitRuntimeOpcode>(opcode);
    if (code == SwifterKitRuntimeOpcode::HIDCompleteGetReport) {
        return CompleteHIDGetReport(payload, payloadLength);
    }
    #if SWIFTERKIT_HID_USB_DEVICE
    if (code == SwifterKitRuntimeOpcode::HIDDeviceReset) {
        if (payloadLength != 0) {
            return kIOReturnBadArgument;
        }
        reset();
        return kIOReturnSuccess;
    }
    if (code == SwifterKitRuntimeOpcode::HIDDeviceGetReport) {
        SwifterKitHIDReportRequest request = {};
        if (payloadLength != sizeof(request)) {
            return kIOReturnBadArgument;
        }
        memcpy(&request, payload, sizeof(request));
        if (request.timestamp != 0 || request.reserved != 0 || request.reportType > 2
            || request.reportID > 0xFF || (request.options & 0xFFU) != 0 || request.length == 0
            || request.length > kMaximumAnsweredReport) {
            return kIOReturnBadArgument;
        }
        IOBufferMemoryDescriptor* buffer = nullptr;
        kern_return_t result =
            IOBufferMemoryDescriptor::Create(kIOMemoryDirectionIn, request.length, 0, &buffer);
        if (result != kIOReturnSuccess || buffer == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        (void)buffer->SetLength(request.length);
        uint32_t transferred = 0;
        result = IOUserUSBHostHIDDevice::getReport(
            buffer,
            static_cast<IOHIDReportType>(request.reportType),
            request.options | request.reportID,
            request.timeout,
            &transferred);
        if (result == kIOReturnSuccess) {
            result = transferred > request.length ? kIOReturnOverrun
                                                  : ReadDescriptor(buffer, transferred, response);
        }
        buffer->release();
        return result;
    }
    SwifterKitHIDDeviceSetting setting = {};
    if (payloadLength != sizeof(setting)) {
        return kIOReturnBadArgument;
    }
    memcpy(&setting, payload, sizeof(setting));
    if (setting.value > 0xFFFF) {
        return kIOReturnBadArgument;
    }
    const auto value = static_cast<uint16_t>(setting.value);
    switch (code) {
        case SwifterKitRuntimeOpcode::HIDDeviceSetProtocol:
            return setting.kind != 0 || value > 1 ? kIOReturnBadArgument : setProtocol(value);
        case SwifterKitRuntimeOpcode::HIDDeviceSetIdle:
            return setting.kind != 0 ? kIOReturnBadArgument : setIdle(value);
        case SwifterKitRuntimeOpcode::HIDDeviceSetIdlePolicy:
            return setting.kind > USBIdlePolicyTypePipe
                       ? kIOReturnBadArgument
                       : setIdlePolicy(static_cast<USBIdlePolicyType>(setting.kind), value);
        default:
            return kIOReturnUnsupported;
    }
    #else
    return kIOReturnUnsupported;
    #endif
}
#endif
