#include <DriverKit/IOLib.h>
#include <DriverKit/OSCollections.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

#if SWIFTERKIT_HID_DEVICE
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <HIDDriverKit/IOHIDDeviceKeys.h>

    #include "SwifterKitRuntimeServiceProperties.h"
#endif

// The IOUserHIDDevice and IOUserUSBHostHIDDevice (IOHIDDevice) side of the runtime. Event
// services live in SwifterKitRuntimeHIDEvents.cpp.
#if SWIFTERKIT_HID_DEVICE
namespace {
    // An IOUserUSBHostHIDDevice opens its interface itself, so the runtime leaves it alone.
    #if SWIFTERKIT_ENABLE_USB && !SWIFTERKIT_HID_USB_DEVICE
    kern_return_t OpenUSBProvider(
        SwifterKitRuntimeService* service,
        IOService* provider,
        SwifterKitRuntimeService_IVars* state) {
        if (service == nullptr || state == nullptr)
            return kIOReturnBadArgument;
        return service->StartUSB(provider);
    }

    [[maybe_unused]] void CloseUSBProvider(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state) {
        if (service != nullptr && state != nullptr)
            service->StopUSB();
    }
    #endif

    #if SWIFTERKIT_ENABLE_PCI
    kern_return_t OpenPCIProvider(
        SwifterKitRuntimeService* service,
        IOService* provider,
        SwifterKitRuntimeService_IVars* state) {
        if (service == nullptr || provider == nullptr || state == nullptr)
            return kIOReturnBadArgument;
        state->pciDevice = OSDynamicCast(IOPCIDevice, provider);
        if (state->pciDevice == nullptr)
            return kIOReturnBadArgument;
        state->pciDevice->retain();
        const kern_return_t result = state->pciDevice->Open(service, 0);
        if (result != kIOReturnSuccess)
            OSSafeReleaseNULL(state->pciDevice);
        return result;
    }

    [[maybe_unused]] void ClosePCIProvider(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state) {
        if (service != nullptr && state != nullptr && state->pciDevice != nullptr) {
            state->pciDevice->Close(service, 0);
            OSSafeReleaseNULL(state->pciDevice);
        }
    }
    #endif

    [[maybe_unused]] void SetNumber(OSDictionary* dictionary, const char* key, uint32_t value) {
        OSNumber* number = OSNumber::withNumber(value, 32);
        if (number != nullptr) {
            OSDictionarySetValue(dictionary, key, number);
            number->release();
        }
    }

    [[maybe_unused]] void SetString(OSDictionary* dictionary, const char* key, const char* value) {
        OSString* string = OSString::withCString(value);
        if (string != nullptr) {
            OSDictionarySetValue(dictionary, key, string);
            string->release();
        }
    }

    [[maybe_unused]] void AddPrimaryUsagePair(OSDictionary* description) {
        OSArray* pairs = OSArray::withCapacity(1);
        OSDictionary* pair = OSDictionary::withCapacity(2);
        if (pairs != nullptr && pair != nullptr) {
            SetNumber(pair, kIOHIDDeviceUsagePageKey, kSwifterKitHIDPrimaryUsagePage);
            SetNumber(pair, kIOHIDDeviceUsageKey, kSwifterKitHIDPrimaryUsage);
            if (pairs->setObject(pair)) {
                OSDictionarySetValue(description, kIOHIDDeviceUsagePairsKey, pairs);
            }
        }
        OSSafeReleaseNULL(pair);
        OSSafeReleaseNULL(pairs);
    }

    kern_return_t
        CopyDescriptorBytes(IOMemoryDescriptor* descriptor, uint32_t length, OSData* destination) {
        IOMemoryMap* map = nullptr;
        kern_return_t result =
            descriptor->CreateMapping(kIOMemoryMapReadOnly, 0, 0, length, 0, &map);
        if (result != kIOReturnSuccess || map == nullptr) {
            return result;
        }

        const uint64_t address = map->GetAddress();
        if (address == 0
            || !destination->appendBytes(
                reinterpret_cast<const void*>(static_cast<uintptr_t>(address)),
                length)) {
            result = kIOReturnNoMemory;
        }
        map->release();
        return result;
    }

    bool AcceptsHostReportType(IOHIDReportType reportType) {
        switch (reportType) {
            case kIOHIDReportTypeOutput:
                return (kSwifterKitHIDAcceptedHostReportTypes & kSwifterKitHIDHostReportOutput)
                       != 0;
            case kIOHIDReportTypeFeature:
                return (kSwifterKitHIDAcceptedHostReportTypes & kSwifterKitHIDHostReportFeature)
                       != 0;
            default:
                return false;
        }
    }
}  // namespace

bool SwifterKitRuntimeService::handleStart(IOService* provider) {
    if (!super::handleStart(provider)) {
        return false;
    }
    if (StartReporting() != kIOReturnSuccess) {
        StopReporting();
        return false;
    }
    bool opened = true;
    #if SWIFTERKIT_ENABLE_USB && !SWIFTERKIT_HID_USB_DEVICE
    opened = OpenUSBProvider(this, provider, ivars) == kIOReturnSuccess;
    #elif SWIFTERKIT_ENABLE_PCI
    opened = OpenPCIProvider(this, provider, ivars) == kIOReturnSuccess;
    #endif
    if (!opened) {
        return false;
    }
    #if SWIFTERKIT_ENABLE_MEMORY
    if (StartMemory(provider) != kIOReturnSuccess) {
        #if SWIFTERKIT_ENABLE_USB && !SWIFTERKIT_HID_USB_DEVICE
        CloseUSBProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
        #endif
        return false;
    }
    #endif
    #if SWIFTERKIT_ENABLE_INTERRUPTS
    if (StartInterrupts(provider) != kIOReturnSuccess) {
        #if SWIFTERKIT_ENABLE_MEMORY
        StopMemory();
        #endif
        #if SWIFTERKIT_ENABLE_USB && !SWIFTERKIT_HID_USB_DEVICE
        CloseUSBProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
        #endif
        return false;
    }
    #endif
    return true;
}

OSDictionary* SwifterKitRuntimeService::newDeviceDescription() {
    #if SWIFTERKIT_HID_USB_DEVICE
    // The superclass reads the interface's descriptors; configured properties override them.
    OSDictionary* description = super::newDeviceDescription();
    if (description == nullptr || kSwifterKitHIDDevicePropertiesLength == 0) {
        return description;
    }
    OSObject* decoded = nullptr;
    if (SwifterKitDecodeProperty(
            kSwifterKitHIDDeviceProperties,
            kSwifterKitHIDDevicePropertiesLength,
            &decoded)
        == kIOReturnSuccess) {
        const OSDictionary* overrides = OSDynamicCast(OSDictionary, decoded);
        if (overrides != nullptr) {
            overrides->iterateObjects(^bool(OSObject* key, OSObject* value) {
              const OSString* name = OSDynamicCast(OSString, key);
              if (name != nullptr) {
                  description->setObject(name, value);
              }
              return true;
            });
        }
    }
    OSSafeReleaseNULL(decoded);
    return description;
    #else
    OSDictionary* description = OSDictionary::withCapacity(14);
    if (description == nullptr) {
        return nullptr;
    }

    OSDictionarySetValue(description, "RegisterService", kOSBooleanTrue);
    OSDictionarySetValue(description, "HIDDefaultBehavior", kOSBooleanTrue);
    SetString(description, kIOHIDTransportKey, kSwifterKitHIDTransport);
    SetNumber(description, kIOHIDVendorIDKey, kSwifterKitHIDVendorID);
    SetNumber(description, kIOHIDProductIDKey, kSwifterKitHIDProductID);
    SetNumber(description, kIOHIDVersionNumberKey, kSwifterKitHIDVersionNumber);
    SetNumber(description, kIOHIDCountryCodeKey, kSwifterKitHIDCountryCode);
    SetNumber(description, kIOHIDLocationIDKey, kSwifterKitHIDLocationID);
    SetString(description, kIOHIDManufacturerKey, kSwifterKitHIDManufacturer);
    SetString(description, kIOHIDProductKey, kSwifterKitHIDProduct);
    SetString(description, kIOHIDSerialNumberKey, kSwifterKitHIDSerialNumber);
    SetNumber(description, kIOHIDPrimaryUsagePageKey, kSwifterKitHIDPrimaryUsagePage);
    SetNumber(description, kIOHIDPrimaryUsageKey, kSwifterKitHIDPrimaryUsage);
    AddPrimaryUsagePair(description);
    return description;
    #endif
}

OSData* SwifterKitRuntimeService::newReportDescriptor() {
    if (kSwifterKitHIDReportDescriptorLength == 0) {
    #if SWIFTERKIT_HID_USB_DEVICE
        return super::newReportDescriptor();
    #else
        return nullptr;
    #endif
    }
    return OSData::withBytes(kSwifterKitHIDReportDescriptor, kSwifterKitHIDReportDescriptorLength);
}

kern_return_t SwifterKitRuntimeService::SubmitHIDInputReport(
    const SwifterKitHIDReportHeader* header,
    const uint8_t* bytes) {
    if (ivars == nullptr || ivars->eventLock == nullptr) {
        return kIOReturnNotReady;
    }

    IOLockLock(ivars->eventLock);
    ivars->hidInputReportAttempts += 1;
    IOLockUnlock(ivars->eventLock);

    if (header == nullptr || bytes == nullptr || header->reportLength == 0
        || header->reportType != kIOHIDReportTypeInput || header->reserved != 0) {
        IOLockLock(ivars->eventLock);
        ivars->hidInputReportFailures += 1;
        IOLockUnlock(ivars->eventLock);
        return kIOReturnBadArgument;
    }

    IOBufferMemoryDescriptor* buffer = nullptr;
    kern_return_t result =
        IOBufferMemoryDescriptor::Create(kIOMemoryDirectionIn, header->reportLength, 0, &buffer);
    if (result != kIOReturnSuccess || buffer == nullptr) {
        IOLockLock(ivars->eventLock);
        ivars->hidInputReportFailures += 1;
        IOLockUnlock(ivars->eventLock);
        return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
    }
    (void)buffer->SetLength(header->reportLength);

    IOMemoryMap* map = nullptr;
    result = buffer->CreateMapping(0, 0, 0, header->reportLength, 0, &map);
    if (result == kIOReturnSuccess && map != nullptr && map->GetAddress() != 0) {
        memcpy(
            reinterpret_cast<void*>(static_cast<uintptr_t>(map->GetAddress())),
            bytes,
            header->reportLength);
        // The superclass delivers the report, so a USB HID device does not echo it to Swift.
        result = super::handleReport(
            header->timestamp,
            buffer,
            header->reportLength,
            kIOHIDReportTypeInput,
            header->options);
    } else if (result == kIOReturnSuccess) {
        result = kIOReturnNoMemory;
    }

    OSSafeReleaseNULL(map);
    buffer->release();

    IOLockLock(ivars->eventLock);
    if (result == kIOReturnSuccess) {
        ivars->hidInputReportSuccesses += 1;
    } else {
        ivars->hidInputReportFailures += 1;
    }
    IOLockUnlock(ivars->eventLock);
    return result;
}

kern_return_t SwifterKitRuntimeService::CopyHIDRuntimeStatistics(
    SwifterKitHIDRuntimeStatistics* statistics) {
    if (statistics == nullptr || ivars == nullptr || ivars->eventLock == nullptr) {
        return kIOReturnBadArgument;
    }

    IOLockLock(ivars->eventLock);
    *statistics = {
        .inputReportAttempts = ivars->hidInputReportAttempts,
        .inputReportSuccesses = ivars->hidInputReportSuccesses,
        .inputReportFailures = ivars->hidInputReportFailures,
    };
    IOLockUnlock(ivars->eventLock);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::setReport(
    IOMemoryDescriptor* report,
    IOHIDReportType reportType,
    IOOptionBits options,
    [[maybe_unused]] uint32_t completionTimeout,
    OSAction* action) {
    if (!AcceptsHostReportType(reportType)) {
    #if SWIFTERKIT_HID_USB_DEVICE
        return super::setReport(report, reportType, options, completionTimeout, action);
    #else
        return kIOReturnUnsupported;
    #endif
    }
    if (report == nullptr || ivars == nullptr || ivars->events == nullptr
        || ivars->eventLock == nullptr) {
        return kIOReturnBadArgument;
    }

    uint64_t length64 = 0;
    kern_return_t result = report->GetLength(&length64);
    if (result != kIOReturnSuccess || length64 == 0
        || length64 > kSwifterKitRuntimeMaximumMessageSize - sizeof(SwifterKitHIDReportHeader)
                          - sizeof(uint32_t)) {
        return kIOReturnBadArgument;
    }

    const SwifterKitHIDReportHeader header = {
        .timestamp = 0,
        .reportType = static_cast<uint32_t>(reportType),
        .options = static_cast<uint32_t>(options),
        .reportLength = static_cast<uint32_t>(length64),
        .reserved = 0,
    };
    OSData* payload = OSData::withCapacity(sizeof(header) + header.reportLength);
    if (payload == nullptr || !payload->appendBytes(&header, sizeof(header))) {
        OSSafeReleaseNULL(payload);
        return kIOReturnNoMemory;
    }

    result = CopyDescriptorBytes(report, header.reportLength, payload);
    if (result == kIOReturnSuccess) {
        result = EnqueueEvent(
            kSwifterKitEventHIDReport,
            payload->getBytesNoCopy(),
            static_cast<uint32_t>(payload->getLength()));
    }
    payload->release();
    // Completion ownership: Swift observes host reports and never answers them, so an accepted
    // report completes here, exactly once, as soon as it is queued. An error return leaves
    // completion to the caller.
    if (result == kIOReturnSuccess && action != nullptr) {
        CompleteReport(action, kIOReturnSuccess, header.reportLength);
    }
    return result;
}

    #if SWIFTERKIT_HID_USB_DEVICE
// Delivers the device's input reports to Swift as hidInputReport events when configured, then
// lets the superclass hand them to HID clients.
kern_return_t SwifterKitRuntimeService::handleReport(
    uint64_t timestamp,
    IOMemoryDescriptor* report,
    uint32_t reportLength,
    IOHIDReportType reportType,
    IOOptionBits options) {
    if (kSwifterKitHIDDeliversDeviceInputReports && report != nullptr && reportLength != 0
        && reportLength <= kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize
                               - sizeof(uint32_t) - sizeof(SwifterKitHIDReportHeader)) {
        const SwifterKitHIDReportHeader header = {
            .timestamp = timestamp,
            .reportType = static_cast<uint32_t>(reportType),
            .options = static_cast<uint32_t>(options),
            .reportLength = reportLength,
            .reserved = 0,
        };
        OSData* payload = OSData::withCapacity(sizeof(header) + reportLength);
        if (payload != nullptr && payload->appendBytes(&header, sizeof(header))
            && CopyDescriptorBytes(report, reportLength, payload) == kIOReturnSuccess) {
            (void)EnqueueEvent(
                kSwifterKitEventHIDInputReport,
                payload->getBytesNoCopy(),
                static_cast<uint32_t>(payload->getLength()));
        }
        OSSafeReleaseNULL(payload);
    }
    return super::handleReport(timestamp, report, reportLength, reportType, options);
}
    #endif
#endif
