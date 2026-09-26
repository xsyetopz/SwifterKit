#include <DriverKit/IOLib.h>
#include <DriverKit/OSCollections.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

#if SWIFTERKIT_HID_EVENT_SERVICE
    #include <HIDDriverKit/IOHIDElement.h>
    #include <HIDDriverKit/IOHIDInterface.h>

    #include "SwifterKitRuntimeServiceProperties.h"
#endif

// The IOUserHIDEventService and IOUserHIDEventDriver side of the runtime: the provider
// IOHIDInterface's reports and element values reach Swift as events, and the host's LED and
// property changes are forwarded. hidLock serializes element access and dispatch between the
// service queue and Swift's commands; see SwifterKitRuntimeHIDElements.cpp and
// SwifterKitRuntimeHIDDispatch.cpp.
#if SWIFTERKIT_HID_EVENT_SERVICE
namespace {
    constexpr uint32_t kMaximumEventPayload =
        kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize - sizeof(uint32_t);

    void DeliverReport(
        SwifterKitRuntimeService* service,
        uint64_t timestamp,
        const uint8_t* report,
        uint32_t reportLength,
        IOHIDReportType type,
        uint32_t reportID) {
        if (report == nullptr || reportLength == 0
            || reportLength > kMaximumEventPayload - sizeof(SwifterKitHIDReportHeader)) {
            return;
        }
        const SwifterKitHIDReportHeader header = {
            .timestamp = timestamp,
            .reportType = static_cast<uint32_t>(type),
            .options = reportID,
            .reportLength = reportLength,
            .reserved = 0,
        };
        OSData* payload = OSData::withCapacity(sizeof(header) + reportLength);
        if (payload != nullptr && payload->appendBytes(&header, sizeof(header))
            && payload->appendBytes(report, reportLength)) {
            (void)service->EnqueueEvent(
                kSwifterKitEventHIDInputReport,
                payload->getBytesNoCopy(),
                static_cast<uint32_t>(payload->getLength()));
        }
        OSSafeReleaseNULL(payload);
    }

    bool IsInputElement(IOHIDElement* element) {
        const uint32_t type = element->getType();
        return type >= kIOHIDElementTypeInput_Misc && type <= kIOHIDElementTypeInput_NULL;
    }

    // Sends the input elements this report updated, at most kSwifterKitHIDMaximumEventValues
    // per event.
    void DeliverElementValues(
        SwifterKitRuntimeService* service,
        const OSArray* elements,
        uint64_t timestamp,
        uint32_t reportID) {
        if (elements == nullptr) {
            return;
        }
        struct __attribute__((packed)) Batch {
            SwifterKitHIDElementValuesHeader header;
            SwifterKitHIDElementValueUpdate values[kSwifterKitHIDMaximumEventValues];
        };
        auto* batch = static_cast<Batch*>(IOMallocZero(sizeof(Batch)));
        if (batch == nullptr) {
            return;
        }
        batch->header = {.timestamp = timestamp, .reportID = reportID, .count = 0};
        const auto flush = [&]() {
            if (batch->header.count != 0) {
                (void)service->EnqueueEvent(
                    kSwifterKitEventHIDElementValues,
                    batch,
                    static_cast<uint32_t>(
                        sizeof(batch->header)
                        + batch->header.count * sizeof(SwifterKitHIDElementValueUpdate)));
                batch->header.count = 0;
            }
        };
        for (uint32_t index = 0; index < elements->getCount(); ++index) {
            auto* element = OSDynamicCast(IOHIDElement, elements->getObject(index));
            if (element == nullptr || !IsInputElement(element) || element->getReportID() != reportID
                || element->getTimeStamp() != timestamp) {
                continue;
            }
            batch->values[batch->header.count++] = {
                .cookie = element->getCookie(),
                .value = element->getValue(0),
            };
            if (batch->header.count == kSwifterKitHIDMaximumEventValues) {
                flush();
            }
        }
        flush();
        IOFree(batch, sizeof(Batch));
    }
}  // namespace

bool SwifterKitRuntimeService::handleStart(IOService* provider) {
    if (ivars == nullptr || !super::handleStart(provider)) {
        return false;
    }
    IORecursiveLockLock(ivars->hidLock);
    ivars->hidInterface = OSDynamicCast(IOHIDInterface, provider);
    if (ivars->hidInterface != nullptr) {
        ivars->hidInterface->retain();
    }
    IORecursiveLockUnlock(ivars->hidLock);
    if (ivars->hidInterface == nullptr || StartReporting() != kIOReturnSuccess) {
        StopReporting();
        StopHID();
        return false;
    }
    #if SWIFTERKIT_ENABLE_MEMORY
    if (StartMemory(provider) != kIOReturnSuccess) {
        StopHID();
        return false;
    }
    #endif
    return true;
}

void SwifterKitRuntimeService::StopHID() {
    if (ivars == nullptr || ivars->hidLock == nullptr) {
        return;
    }
    IORecursiveLockLock(ivars->hidLock);
    OSSafeReleaseNULL(ivars->hidInterface);
    IORecursiveLockUnlock(ivars->hidLock);
}

// Event services receive no host get-report requests.
void SwifterKitRuntimeService::AbortHIDRequests() {}

kern_return_t SwifterKitRuntimeService::processReport_Impl(
    uint64_t timestamp,
    uint64_t report,
    uint32_t reportLength,
    IOHIDReportType type,
    uint32_t reportID) {
    // The superclass updates the interface's element values and then calls handleReport; the
    // lock keeps Swift's element reads and dispatches out of that window.
    IORecursiveLockLock(ivars->hidLock);
    const kern_return_t result =
        processReport(timestamp, report, reportLength, type, reportID, SUPERDISPATCH);
    IORecursiveLockUnlock(ivars->hidLock);
    return result;
}

void SwifterKitRuntimeService::handleReport(
    uint64_t timestamp,
    uint8_t* report,
    uint32_t reportLength,
    IOHIDReportType type,
    uint32_t reportID) {
    IORecursiveLockLock(ivars->hidLock);
    if ((kSwifterKitHIDEventDelivery & kSwifterKitHIDDeliverReports) != 0) {
        DeliverReport(this, timestamp, report, reportLength, type, reportID);
    }
    if ((kSwifterKitHIDEventDelivery & kSwifterKitHIDDeliverElementValues) != 0) {
        DeliverElementValues(this, getElements(), timestamp, reportID);
    }
    super::handleReport(timestamp, report, reportLength, type, reportID);
    IORecursiveLockUnlock(ivars->hidLock);
}

kern_return_t
    SwifterKitRuntimeService::SetLEDState_Impl(uint32_t usagePage, uint32_t usage, bool on) {
    const SwifterKitHIDLEDState event = {
        .usagePage = usagePage,
        .usage = usage,
        .on = on ? 1U : 0U,
        .reserved = 0,
    };
    (void)EnqueueEvent(kSwifterKitEventHIDLEDState, &event, sizeof(event));
    IORecursiveLockLock(ivars->hidLock);
    const kern_return_t result = SetLEDState(usagePage, usage, on, SUPERDISPATCH);
    IORecursiveLockUnlock(ivars->hidLock);
    return result;
}

kern_return_t SwifterKitRuntimeService::SetProperties_Impl(OSDictionary* properties) {
    OSData* payload = properties == nullptr ? nullptr : OSData::withCapacity(256);
    if (payload != nullptr
        && SwifterKitEncodeProperty(properties, payload, kMaximumEventPayload)
               == kIOReturnSuccess) {
        (void)EnqueueEvent(
            kSwifterKitEventHIDProperties,
            payload->getBytesNoCopy(),
            static_cast<uint32_t>(payload->getLength()));
    }
    OSSafeReleaseNULL(payload);
    return SetProperties(properties, SUPERDISPATCH);
}

kern_return_t SwifterKitRuntimeService::HIDCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (response == nullptr || (payloadLength != 0 && payload == nullptr)) {
        return kIOReturnBadArgument;
    }
    if (opcode >= static_cast<uint32_t>(SwifterKitRuntimeOpcode::HIDCopyElements)
        && opcode <= static_cast<uint32_t>(SwifterKitRuntimeOpcode::HIDInterfaceProcessReport)) {
        return HIDElementCommand(opcode, payload, payloadLength, response);
    }
    if (opcode >= static_cast<uint32_t>(SwifterKitRuntimeOpcode::HIDDispatchKeyboard)
        && opcode <= static_cast<uint32_t>(SwifterKitRuntimeOpcode::HIDSetEventDriverCategories)) {
        return HIDDispatchCommand(opcode, payload, payloadLength, response);
    }
    return kIOReturnUnsupported;
}

    #if SWIFTERKIT_HID_EVENT_DRIVER
// IOUserHIDEventDriver parses only the configured categories, so the rest stay with Swift, and
// Swift can pause a parsed category's events at run time with hidSetEventDriverCategories.
namespace {
    // The category bits come from RuntimeSchema+HID.swift.
    constexpr uint32_t kKeyboard = kSwifterKitHIDEventDriverCategoryKeyboard;
    constexpr uint32_t kPointer = kSwifterKitHIDEventDriverCategoryPointer;
    constexpr uint32_t kScroll = kSwifterKitHIDEventDriverCategoryScroll;
    constexpr uint32_t kLED = kSwifterKitHIDEventDriverCategoryLED;
    constexpr uint32_t kDigitizer = kSwifterKitHIDEventDriverCategoryDigitizer;
    constexpr uint32_t kProximity = kSwifterKitHIDEventDriverCategoryProximity;
    constexpr uint32_t kGameController = kSwifterKitHIDEventDriverCategoryGameController;
    constexpr uint32_t kRemaining = kSwifterKitHIDEventDriverCategoryRemaining;

    constexpr bool Parses(uint32_t category) {
        return (kSwifterKitHIDEventDriverCategories & category) != 0;
    }

    bool Handles(const SwifterKitRuntimeService_IVars* state, uint32_t category) {
        return state != nullptr && (state->hidEventDriverHandling & category) != 0;
    }
}  // namespace

bool SwifterKitRuntimeService::parseKeyboardElement(IOHIDElement* element) {
    return Parses(kKeyboard) && super::parseKeyboardElement(element);
}

bool SwifterKitRuntimeService::parsePointerElement(IOHIDElement* element) {
    return Parses(kPointer) && super::parsePointerElement(element);
}

bool SwifterKitRuntimeService::parseScrollElement(IOHIDElement* element) {
    return Parses(kScroll) && super::parseScrollElement(element);
}

bool SwifterKitRuntimeService::parseLEDElement(IOHIDElement* element) {
    return Parses(kLED) && super::parseLEDElement(element);
}

bool SwifterKitRuntimeService::parseDigitizerElement(IOHIDElement* element) {
    return Parses(kDigitizer) && super::parseDigitizerElement(element);
}

bool SwifterKitRuntimeService::parseProximityElement(IOHIDElement* element) {
    return Parses(kProximity) && super::parseProximityElement(element);
}

bool SwifterKitRuntimeService::parseGameControllerElement(IOHIDElement* element) {
    return Parses(kGameController) && super::parseGameControllerElement(element);
}

bool SwifterKitRuntimeService::parseRemainingElement(IOHIDElement* element) {
    return Parses(kRemaining) && super::parseRemainingElement(element);
}

void SwifterKitRuntimeService::handleKeyboardReport(uint64_t timestamp, uint32_t reportID) {
    if (Handles(ivars, kKeyboard)) {
        super::handleKeyboardReport(timestamp, reportID);
    }
}

void SwifterKitRuntimeService::handleRelativePointerReport(uint64_t timestamp, uint32_t reportID) {
    if (Handles(ivars, kPointer)) {
        super::handleRelativePointerReport(timestamp, reportID);
    }
}

void SwifterKitRuntimeService::handleAbsolutePointerReport(uint64_t timestamp, uint32_t reportID) {
    if (Handles(ivars, kPointer)) {
        super::handleAbsolutePointerReport(timestamp, reportID);
    }
}

void SwifterKitRuntimeService::handleScrollReport(uint64_t timestamp, uint32_t reportID) {
    if (Handles(ivars, kScroll)) {
        super::handleScrollReport(timestamp, reportID);
    }
}

void SwifterKitRuntimeService::handleDigitizerReport(uint64_t timestamp, uint32_t reportID) {
    if (Handles(ivars, kDigitizer)) {
        super::handleDigitizerReport(timestamp, reportID);
    }
}

void SwifterKitRuntimeService::handleProximityReport(uint64_t timestamp, uint32_t reportID) {
    if (Handles(ivars, kProximity)) {
        super::handleProximityReport(timestamp, reportID);
    }
}

void SwifterKitRuntimeService::handleGameControllerReport(uint64_t timestamp, uint32_t reportID) {
    if (Handles(ivars, kGameController)) {
        super::handleGameControllerReport(timestamp, reportID);
    }
}
    #endif
#endif
