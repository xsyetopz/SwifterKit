#include <DriverKit/IOLib.h>
#include <DriverKit/OSCollections.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

#if SWIFTERKIT_ENABLE_HID
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <HIDDriverKit/IOHIDDeviceKeys.h>
#endif

#if SWIFTERKIT_ENABLE_HID
namespace {
    #if SWIFTERKIT_ENABLE_USB
    kern_return_t OpenUSBProvider(
        SwifterKitRuntimeService* service,
        IOService* provider,
        SwifterKitRuntimeService_IVars* state) {
        if (service == nullptr || provider == nullptr || state == nullptr)
            return kIOReturnBadArgument;
        state->usbInterface = OSDynamicCast(IOUSBHostInterface, provider);
        if (state->usbInterface == nullptr)
            return kIOReturnBadArgument;
        state->usbInterface->retain();
        const kern_return_t result = state->usbInterface->Open(service, 0, nullptr);
        if (result != kIOReturnSuccess)
            OSSafeReleaseNULL(state->usbInterface);
        return result;
    }

    [[maybe_unused]] void CloseUSBProvider(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state) {
        if (service != nullptr && state != nullptr && state->usbInterface != nullptr) {
            (void)state->usbInterface->Close(service, 0);
            OSSafeReleaseNULL(state->usbInterface);
        }
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

    void SetNumber(OSDictionary* dictionary, const char* key, uint32_t value) {
        OSNumber* number = OSNumber::withNumber(value, 32);
        if (number != nullptr) {
            OSDictionarySetValue(dictionary, key, number);
            number->release();
        }
    }

    void SetString(OSDictionary* dictionary, const char* key, const char* value) {
        OSString* string = OSString::withCString(value);
        if (string != nullptr) {
            OSDictionarySetValue(dictionary, key, string);
            string->release();
        }
    }

    void AddPrimaryUsagePair(OSDictionary* description) {
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
    bool opened = true;
    #if SWIFTERKIT_ENABLE_USB
    opened = OpenUSBProvider(this, provider, ivars) == kIOReturnSuccess;
    #elif SWIFTERKIT_ENABLE_PCI
    opened = OpenPCIProvider(this, provider, ivars) == kIOReturnSuccess;
    #endif
    if (!opened) {
        return false;
    }
    #if SWIFTERKIT_ENABLE_MEMORY
    if (StartMemory(provider) != kIOReturnSuccess) {
        #if SWIFTERKIT_ENABLE_USB
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
        #if SWIFTERKIT_ENABLE_USB
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
}

OSData* SwifterKitRuntimeService::newReportDescriptor() {
    if (kSwifterKitHIDReportDescriptorLength == 0) {
        return nullptr;
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
        result = handleReport(
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
    uint32_t,
    OSAction*) {
    if (!AcceptsHostReportType(reportType)) {
        return kIOReturnUnsupported;
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
            0x0300,
            payload->getBytesNoCopy(),
            static_cast<uint32_t>(payload->getLength()));
    }
    payload->release();
    return result;
}
#endif
