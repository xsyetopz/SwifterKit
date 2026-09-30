#ifndef SwifterKitRuntimeHIDShared_h
#define SwifterKitRuntimeHIDShared_h

#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_HID_DEVICE || SWIFTERKIT_HID_DEVICE_FACTORY
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSCollections.h>
    #include <HIDDriverKit/IOHIDDeviceKeys.h>
    #include <HIDDriverKit/IOHIDDeviceTypes.h>
    #include <string.h>

    #include "SwifterKitRuntimeHIDProtocol.h"
    #include "SwifterKitRuntimeMappedMemory.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

// Helpers shared by the generated IOUserHIDDevice root (SwifterKitRuntimeHID.cpp) and the
// devices a HID device factory creates (SwifterKitRuntimeHIDDevice.cpp).

// Swift answers a get-report with a command header and a completion header before the bytes.
static constexpr uint32_t kSwifterKitHIDMaximumAnsweredReport =
    kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize
    - sizeof(SwifterKitRuntimeCommandHeader) - sizeof(SwifterKitHIDReportCompletion);

// A string that need not end in a terminator.
struct SwifterKitHIDText {
    const char* bytes;
    size_t length;
};

// A validated hidFactoryCreateDevice payload. The pointers point into the payload.
struct SwifterKitHIDFactoryConfiguration {
    SwifterKitHIDFactoryDevice device;
    SwifterKitHIDText transport;
    SwifterKitHIDText manufacturer;
    SwifterKitHIDText product;
    SwifterKitHIDText serialNumber;
    const uint8_t* descriptor;
};

inline void SwifterKitHIDSetNumber(OSDictionary* dictionary, const char* key, uint32_t value) {
    OSNumber* number = OSNumber::withNumber(value, 32);
    if (number != nullptr) {
        OSDictionarySetValue(dictionary, key, number);
        number->release();
    }
}

inline void
    SwifterKitHIDSetString(OSDictionary* dictionary, const char* key, SwifterKitHIDText text) {
    OSString* string = OSString::withCString(text.bytes, text.length);
    if (string != nullptr) {
        OSDictionarySetValue(dictionary, key, string);
        string->release();
    }
}

inline SwifterKitHIDText SwifterKitHIDCString(const char* string) {
    return {string, strlen(string)};
}

// The IOUserHIDDevice description of a device with the numbers in device and the given strings.
inline OSDictionary* SwifterKitHIDNewDescription(
    const SwifterKitHIDFactoryDevice& device,
    SwifterKitHIDText transport,
    SwifterKitHIDText manufacturer,
    SwifterKitHIDText product,
    SwifterKitHIDText serialNumber) {
    OSDictionary* description = OSDictionary::withCapacity(14);
    if (description == nullptr) {
        return nullptr;
    }
    OSDictionarySetValue(description, "RegisterService", kOSBooleanTrue);
    OSDictionarySetValue(description, "HIDDefaultBehavior", kOSBooleanTrue);
    SwifterKitHIDSetString(description, kIOHIDTransportKey, transport);
    SwifterKitHIDSetNumber(description, kIOHIDVendorIDKey, device.vendorID);
    SwifterKitHIDSetNumber(description, kIOHIDProductIDKey, device.productID);
    SwifterKitHIDSetNumber(description, kIOHIDVersionNumberKey, device.versionNumber);
    SwifterKitHIDSetNumber(description, kIOHIDCountryCodeKey, device.countryCode);
    SwifterKitHIDSetNumber(description, kIOHIDLocationIDKey, device.locationID);
    SwifterKitHIDSetString(description, kIOHIDManufacturerKey, manufacturer);
    SwifterKitHIDSetString(description, kIOHIDProductKey, product);
    SwifterKitHIDSetString(description, kIOHIDSerialNumberKey, serialNumber);
    SwifterKitHIDSetNumber(description, kIOHIDPrimaryUsagePageKey, device.primaryUsagePage);
    SwifterKitHIDSetNumber(description, kIOHIDPrimaryUsageKey, device.primaryUsage);

    OSArray* pairs = OSArray::withCapacity(1);
    OSDictionary* pair = OSDictionary::withCapacity(2);
    if (pairs != nullptr && pair != nullptr) {
        SwifterKitHIDSetNumber(pair, kIOHIDDeviceUsagePageKey, device.primaryUsagePage);
        SwifterKitHIDSetNumber(pair, kIOHIDDeviceUsageKey, device.primaryUsage);
        if (pairs->setObject(pair)) {
            OSDictionarySetValue(description, kIOHIDDeviceUsagePairsKey, pairs);
        }
    }
    OSSafeReleaseNULL(pair);
    OSSafeReleaseNULL(pairs);
    return description;
}

// Whether Swift observes host set-reports of reportType. mask holds kSwifterKitHIDHostReport bits.
inline bool SwifterKitHIDAcceptsHostReportType(uint32_t mask, IOHIDReportType reportType) {
    switch (reportType) {
        case kIOHIDReportTypeOutput:
            return (mask & kSwifterKitHIDHostReportOutput) != 0;
        case kIOHIDReportTypeFeature:
            return (mask & kSwifterKitHIDHostReportFeature) != 0;
        default:
            return false;
    }
}

// Whether Swift answers host get-reports of reportType. mask holds kSwifterKitHIDGetReport bits.
inline bool SwifterKitHIDAnswersReportType(uint32_t mask, IOHIDReportType reportType) {
    switch (reportType) {
        case kIOHIDReportTypeInput:
            return (mask & kSwifterKitHIDGetReportInput) != 0;
        case kIOHIDReportTypeOutput:
            return (mask & kSwifterKitHIDGetReportOutput) != 0;
        case kIOHIDReportTypeFeature:
            return (mask & kSwifterKitHIDGetReportFeature) != 0;
        default:
            return false;
    }
}

inline kern_return_t SwifterKitHIDCopyDescriptorBytes(
    IOMemoryDescriptor* descriptor,
    uint32_t length,
    OSData* destination) {
    IOMemoryMap* map = nullptr;
    kern_return_t result = descriptor->CreateMapping(kIOMemoryMapReadOnly, 0, 0, length, 0, &map);
    if (result != kIOReturnSuccess || map == nullptr) {
        return result;
    }
    const uint64_t address = map->GetAddress();
    if (address == 0
        || !destination->appendBytes(SwifterKitMappedPointer<const void>(address), length)) {
        result = kIOReturnNoMemory;
    }
    map->release();
    return result;
}

inline kern_return_t SwifterKitHIDCopyIntoDescriptor(
    IOMemoryDescriptor* report,
    const uint8_t* bytes,
    uint32_t length) {
    IOMemoryMap* map = nullptr;
    kern_return_t result = report->CreateMapping(0, 0, 0, length, 0, &map);
    if (result == kIOReturnSuccess && (map == nullptr || map->GetAddress() == 0)) {
        result = kIOReturnNoMemory;
    }
    if (result == kIOReturnSuccess) {
        memcpy(SwifterKitMappedPointer<void>(map->GetAddress()), bytes, length);
    }
    OSSafeReleaseNULL(map);
    return result;
}

// A new input-report buffer holding a copy of bytes.
inline kern_return_t SwifterKitHIDCreateReportBuffer(
    const uint8_t* bytes,
    uint32_t length,
    IOBufferMemoryDescriptor** buffer) {
    kern_return_t result =
        IOBufferMemoryDescriptor::Create(kIOMemoryDirectionIn, length, 0, buffer);
    if (result != kIOReturnSuccess || *buffer == nullptr) {
        return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
    }
    (void)(*buffer)->SetLength(length);
    result = SwifterKitHIDCopyIntoDescriptor(*buffer, bytes, length);
    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(*buffer);
    }
    return result;
}

// Takes the pending request with requestID out of table, or every request when requestID is
// zero, taking at most TakenCount. The caller holds the lock that guards table.
template<size_t Count, size_t TakenCount>
uint32_t SwifterKitHIDTakeRequests(
    SwifterKitHIDPendingReport (&table)[Count],
    uint32_t requestID,
    SwifterKitHIDPendingReport (&taken)[TakenCount]) {
    uint32_t count = 0;
    for (auto& slot : table) {
        if (count == TakenCount) {
            break;
        }
        if (slot.requestID != 0 && (requestID == 0 || slot.requestID == requestID)) {
            taken[count++] = slot;
            slot = {};
        }
    }
    return count;
}

    #if SWIFTERKIT_HID_DEVICE_FACTORY
// Pending get-reports per created device. Every device's table fits the required-event queue
// together with one terminated event per device. See SwifterKitRuntimeServiceState.h.
static constexpr uint32_t kSwifterKitHIDFactoryMaximumPendingReports = 8;
// Factory events and commands carry a SwifterKitHIDFactoryHandle before the static payload.
static constexpr uint32_t kSwifterKitHIDFactoryMaximumAnsweredReport =
    kSwifterKitHIDMaximumAnsweredReport - sizeof(SwifterKitHIDFactoryHandle);
static constexpr uint32_t kSwifterKitHIDFactoryMaximumHostReport =
    kSwifterKitMaximumEventPayloadLength - sizeof(SwifterKitHIDFactoryHandle)
    - sizeof(SwifterKitHIDReportHeader);

inline bool SwifterKitHIDTextIsValid(SwifterKitHIDText text) {
    return text.length != 0 && memchr(text.bytes, 0, text.length) == nullptr;
}

// Validates a hidFactoryCreateDevice payload the way HIDDeviceConfiguration.hasValidFields does.
inline bool SwifterKitHIDParseFactoryDevice(
    const uint8_t* payload,
    uint32_t length,
    SwifterKitHIDFactoryConfiguration* configuration) {
    if (payload == nullptr || configuration == nullptr
        || length < sizeof(SwifterKitHIDFactoryDevice)) {
        return false;
    }
    SwifterKitHIDFactoryDevice device = {};
    memcpy(&device, payload, sizeof(device));
    const uint64_t total = uint64_t {sizeof(device)} + device.transportLength
                           + device.manufacturerLength + device.productLength
                           + device.serialNumberLength + device.descriptorLength;
    if (device.reserved[0] != 0 || device.reserved[1] != 0 || total != length
        || device.descriptorLength == 0
        || (device.acceptedHostReportTypes & ~kSwifterKitHIDHostReportTypesAll) != 0
        || (device.answeredReportTypes
            & ~(kSwifterKitHIDGetReportInput | kSwifterKitHIDGetReportOutput
                | kSwifterKitHIDGetReportFeature))
               != 0) {
        return false;
    }
    const auto* cursor = reinterpret_cast<const char*>(payload + sizeof(device));
    const SwifterKitHIDText texts[4] = {
        {cursor, device.transportLength},
        {cursor + device.transportLength, device.manufacturerLength},
        {cursor + device.transportLength + device.manufacturerLength, device.productLength},
        {cursor + device.transportLength + device.manufacturerLength + device.productLength,
         device.serialNumberLength},
    };
    for (const SwifterKitHIDText& text : texts) {
        if (!SwifterKitHIDTextIsValid(text)) {
            return false;
        }
    }
    *configuration = {
        .device = device,
        .transport = texts[0],
        .manufacturer = texts[1],
        .product = texts[2],
        .serialNumber = texts[3],
        .descriptor = reinterpret_cast<const uint8_t*>(texts[3].bytes + texts[3].length),
    };
    return true;
}
    #endif
#endif
#endif
