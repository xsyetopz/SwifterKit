#include <DriverKit/IOLib.h>
#include <DriverKit/IOService.h>
#include <DriverKit/OSCollections.h>
#include <string.h>

#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceProperties.h"
#include "SwifterKitRuntimeServiceProtocol.h"
#include "SwifterKitRuntimeServiceState.h"

// IOService operations for Swift. Every payload is validated here again after Swift validates it:
// exact lengths, zero reserved bytes, registry names of 1...127 NUL-free bytes, and documented
// flag values. Responses larger than one runtime message fail with kIOReturnNoSpace.

namespace {
    constexpr uint32_t kMaximumResponseLength =
        kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize;
    // Absent from the DriverKit 24.4 headers; the values match the 25.5 and later SDKs.
    constexpr uint32_t kPMAssertionCPU = 0x1;
    constexpr uint32_t kPMAssertionForceFullWakeup = 0x800;

    kern_return_t EncodeResponse(const OSObject* value, OSData** response) {
        OSData* data = OSData::withCapacity(256);
        if (data == nullptr) {
            return kIOReturnNoMemory;
        }
        const kern_return_t result = SwifterKitEncodeProperty(value, data, kMaximumResponseLength);
        if (result != kIOReturnSuccess) {
            data->release();
            return result;
        }
        *response = data;
        return kIOReturnSuccess;
    }

    kern_return_t BytesResponse(const void* bytes, uint32_t length, OSData** response) {
        *response = OSData::withBytes(bytes, length);
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }

    // Decode one property value of the class the operation requires.
    kern_return_t DecodeContainer(const uint8_t* bytes, uint32_t length, OSDictionary** container) {
        OSObject* value = nullptr;
        kern_return_t result = SwifterKitDecodeProperty(bytes, length, &value);
        if (result == kIOReturnSuccess) {
            *container = OSDynamicCast(OSDictionary, value);
            if (*container == nullptr) {
                value->release();
                result = kIOReturnBadArgument;
            }
        }
        return result;
    }

    kern_return_t DecodeContainer(const uint8_t* bytes, uint32_t length, OSArray** container) {
        OSObject* value = nullptr;
        kern_return_t result = SwifterKitDecodeProperty(bytes, length, &value);
        if (result == kIOReturnSuccess) {
            *container = OSDynamicCast(OSArray, value);
            if (*container == nullptr) {
                value->release();
                result = kIOReturnBadArgument;
            }
        }
        return result;
    }

    OSString* CopyRegistryString(const uint8_t* bytes, uint32_t length) {
        return SwifterKitIsPropertyName(bytes, length)
                   ? OSString::withCString(reinterpret_cast<const char*>(bytes), length)
                   : nullptr;
    }

    // Reads SwifterKitServiceNamedValueHeader, the name, and a dictionary that is required,
    // optional, or absent.
    enum class NamedValue {
        Absent,
        Optional,
        Required
    };

    kern_return_t DecodeNamedValue(
        const uint8_t* payload,
        uint32_t length,
        NamedValue expectation,
        OSString** name,
        OSDictionary** value) {
        if (length < sizeof(SwifterKitServiceNamedValueHeader)) {
            return kIOReturnBadArgument;
        }
        const auto* header = reinterpret_cast<const SwifterKitServiceNamedValueHeader*>(payload);
        const uint32_t available = length - sizeof(SwifterKitServiceNamedValueHeader);
        if (header->reserved != 0 || header->nameLength > available) {
            return kIOReturnBadArgument;
        }
        const uint8_t* bytes = payload + sizeof(SwifterKitServiceNamedValueHeader);
        const uint32_t valueLength = available - header->nameLength;
        if ((valueLength == 0 && expectation == NamedValue::Required)
            || (valueLength != 0 && expectation == NamedValue::Absent)) {
            return kIOReturnBadArgument;
        }
        *name = CopyRegistryString(bytes, header->nameLength);
        if (*name == nullptr) {
            return kIOReturnBadArgument;
        }
        if (valueLength == 0) {
            return kIOReturnSuccess;
        }
        const kern_return_t result =
            DecodeContainer(bytes + header->nameLength, valueLength, value);
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(*name);
        }
        return result;
    }

    // Copies a search name or plane into a NUL-terminated IOPropertyName-sized buffer.
    bool CopyRegistryName(const uint8_t* bytes, uint32_t length, char (&name)[128]) {
        if (!SwifterKitIsPropertyName(bytes, length)) {
            return false;
        }
        memcpy(name, bytes, length);
        name[length] = '\0';
        return true;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::ServiceCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::ServiceSetProperties: {
            OSDictionary* properties = nullptr;
            kern_return_t result = DecodeContainer(payload, payloadLength, &properties);
            if (result == kIOReturnSuccess) {
                result =
                    properties->getCount() == 0 ? kIOReturnBadArgument : SetProperties(properties);
                properties->release();
            }
            return result;
        }
        case SwifterKitRuntimeOpcode::ServiceCopyProperties: {
            OSDictionary* properties = nullptr;
            kern_return_t result =
                payloadLength == 0 ? CopyProperties(&properties) : kIOReturnBadArgument;
            if (result == kIOReturnSuccess) {
                result = properties == nullptr ? kIOReturnNotFound
                                               : EncodeResponse(properties, response);
            }
            OSSafeReleaseNULL(properties);
            return result;
        }
        case SwifterKitRuntimeOpcode::ServiceRemoveProperty: {
            OSString* name = CopyRegistryString(payload, payloadLength);
            if (name == nullptr) {
                return kIOReturnBadArgument;
            }
            const kern_return_t result = RemoveProperty(name);
            name->release();
            return result;
        }
        case SwifterKitRuntimeOpcode::ServiceSearchProperty: {
            if (payloadLength < sizeof(SwifterKitServiceSearchHeader)) {
                return kIOReturnBadArgument;
            }
            const auto* header = reinterpret_cast<const SwifterKitServiceSearchHeader*>(payload);
            const uint8_t* nameBytes = payload + sizeof(SwifterKitServiceSearchHeader);
            char name[128] = {};
            char plane[128] = "IOService";
            if ((header->options & ~static_cast<uint32_t>(kIOServiceSearchPropertyParents)) != 0
                || payloadLength
                       != sizeof(SwifterKitServiceSearchHeader) + header->nameLength
                              + header->planeLength
                || !CopyRegistryName(nameBytes, header->nameLength, name)
                || (header->planeLength != 0
                    && !CopyRegistryName(
                        nameBytes + header->nameLength,
                        header->planeLength,
                        plane))) {
                return kIOReturnBadArgument;
            }
            OSContainer* property = nullptr;
            const kern_return_t result = SearchProperty(name, plane, header->options, &property);
            // A missing property answers with an empty payload rather than an error.
            if (result == kIOReturnNotFound
                || (result == kIOReturnSuccess && property == nullptr)) {
                OSSafeReleaseNULL(property);
                return kIOReturnSuccess;
            }
            const kern_return_t encoded =
                result == kIOReturnSuccess ? EncodeResponse(property, response) : result;
            OSSafeReleaseNULL(property);
            return encoded;
        }
        case SwifterKitRuntimeOpcode::ServiceCopyProviderProperties: {
            OSArray* keys = nullptr;
            if (payloadLength != 0) {
                const kern_return_t decoded = DecodeContainer(payload, payloadLength, &keys);
                if (decoded != kIOReturnSuccess) {
                    return decoded;
                }
                __block bool valid = keys->getCount() != 0;
                keys->iterateObjects(^bool(OSObject* key) {
                  const auto* string = OSDynamicCast(OSString, key);
                  valid = valid && string != nullptr && string->getLength() != 0;
                  return !valid;
                });
                if (!valid) {
                    keys->release();
                    return kIOReturnBadArgument;
                }
            }
            OSArray* properties = nullptr;
            kern_return_t result = CopyProviderProperties(keys, &properties);
            if (result == kIOReturnSuccess) {
                result = properties == nullptr ? kIOReturnNotFound
                                               : EncodeResponse(properties, response);
            }
            OSSafeReleaseNULL(properties);
            OSSafeReleaseNULL(keys);
            return result;
        }
        case SwifterKitRuntimeOpcode::ServiceCopyName: {
            if (payloadLength != 0) {
                return kIOReturnBadArgument;
            }
            OSString* name = nullptr;
            kern_return_t result = CopyName(&name);
            if (result == kIOReturnSuccess) {
                result = name == nullptr ? kIOReturnNotFound
                                         : BytesResponse(
                                               name->getCStringNoCopy(),
                                               static_cast<uint32_t>(name->getLength()),
                                               response);
            }
            OSSafeReleaseNULL(name);
            return result;
        }
        case SwifterKitRuntimeOpcode::ServiceGetRegistryEntryID: {
            uint64_t registryEntryID = 0;
            const kern_return_t result =
                payloadLength == 0 ? GetRegistryEntryID(&registryEntryID) : kIOReturnBadArgument;
            return result == kIOReturnSuccess
                       ? BytesResponse(&registryEntryID, sizeof(registryEntryID), response)
                       : result;
        }
        default:
            return ServiceSystemCommand(opcode, payload, payloadLength, response);
    }
}

kern_return_t SwifterKitRuntimeService::ServiceSystemCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::ServiceCopySystemStateItem:
        case SwifterKitRuntimeOpcode::ServiceCreateSystemStateItem:
        case SwifterKitRuntimeOpcode::ServiceSetSystemStateItem: {
            const auto kind = static_cast<SwifterKitRuntimeOpcode>(opcode);
            const NamedValue expectation =
                kind == SwifterKitRuntimeOpcode::ServiceCopySystemStateItem  ? NamedValue::Absent
                : kind == SwifterKitRuntimeOpcode::ServiceSetSystemStateItem ? NamedValue::Required
                                                                             : NamedValue::Optional;
            OSString* name = nullptr;
            OSDictionary* value = nullptr;
            kern_return_t result =
                DecodeNamedValue(payload, payloadLength, expectation, &name, &value);
            IOService* system = nullptr;
            if (result == kIOReturnSuccess) {
                result = CopySystemStateNotificationService(&system);
            }
            if (result == kIOReturnSuccess && system == nullptr) {
                result = kIOReturnNotFound;
            }
            if (result == kIOReturnSuccess) {
                if (kind == SwifterKitRuntimeOpcode::ServiceCreateSystemStateItem) {
                    result = system->StateNotificationItemCreate(name, value);
                } else if (kind == SwifterKitRuntimeOpcode::ServiceSetSystemStateItem) {
                    result = system->StateNotificationItemSet(name, value);
                } else {
                    OSDictionary* item = nullptr;
                    result = system->StateNotificationItemCopy(name, &item);
                    if (result == kIOReturnSuccess && item != nullptr) {
                        result = EncodeResponse(item, response);
                    }
                    OSSafeReleaseNULL(item);
                }
            }
            OSSafeReleaseNULL(system);
            OSSafeReleaseNULL(value);
            OSSafeReleaseNULL(name);
            return result;
        }
        case SwifterKitRuntimeOpcode::ServiceSendCoreAnalyticsEvent: {
            OSString* name = nullptr;
            OSDictionary* value = nullptr;
            kern_return_t result =
                DecodeNamedValue(payload, payloadLength, NamedValue::Required, &name, &value);
            if (result == kIOReturnSuccess) {
                result = CoreAnalyticsSendEvent(0, name, value);
            }
            OSSafeReleaseNULL(value);
            OSSafeReleaseNULL(name);
            return result;
        }
        case SwifterKitRuntimeOpcode::ServiceAdjustBusy: {
            int32_t delta = 0;
            if (payloadLength != sizeof(delta)) {
                return kIOReturnBadArgument;
            }
            memcpy(&delta, payload, sizeof(delta));
            return delta == 0 ? kIOReturnBadArgument : AdjustBusy(delta);
        }
        case SwifterKitRuntimeOpcode::ServiceGetBusyState: {
            uint32_t busyState = 0;
            const kern_return_t result =
                payloadLength == 0 ? GetBusyState(&busyState) : kIOReturnBadArgument;
            return result == kIOReturnSuccess
                       ? BytesResponse(&busyState, sizeof(busyState), response)
                       : result;
        }
        case SwifterKitRuntimeOpcode::ServiceRequireMaxBusStall: {
            uint64_t stall = 0;
            if (payloadLength != sizeof(stall)) {
                return kIOReturnBadArgument;
            }
            memcpy(&stall, payload, sizeof(stall));
            switch (stall) {
                case kIOMaxBusStallNone:
                case kIOMaxBusStall5usec:
                case kIOMaxBusStall10usec:
                case kIOMaxBusStall20usec:
                case kIOMaxBusStall25usec:
                case kIOMaxBusStall30usec:
                case kIOMaxBusStall40usec:
                    return RequireMaxBusStall(stall);
                default:
                    return kIOReturnBadArgument;
            }
        }
        case SwifterKitRuntimeOpcode::ServiceTerminate:
            return payloadLength == 0 ? Terminate(0) : kIOReturnBadArgument;
        default:
            return ServicePowerCommand(opcode, payload, payloadLength, response);
    }
}

kern_return_t SwifterKitRuntimeService::ServicePowerCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::ServiceChangePowerState: {
            uint32_t flags = 0;
            if (payloadLength != sizeof(flags)) {
                return kIOReturnBadArgument;
            }
            memcpy(&flags, payload, sizeof(flags));
            return flags == kIOServicePowerCapabilityOff || flags == kIOServicePowerCapabilityOn
                           || flags == kIOServicePowerCapabilityLow
                       ? ChangePowerState(flags)
                       : kIOReturnBadArgument;
        }
        case SwifterKitRuntimeOpcode::ServiceSetPowerOverride:
            if (payloadLength != 4 || payload[0] > 1 || payload[1] != 0 || payload[2] != 0
                || payload[3] != 0) {
                return kIOReturnBadArgument;
            }
            return SetPowerOverride(payload[0] != 0);
        case SwifterKitRuntimeOpcode::ServiceCreatePMAssertion: {
            if (payloadLength != sizeof(SwifterKitServicePMAssertionHeader)) {
                return kIOReturnBadArgument;
            }
            const auto* header =
                reinterpret_cast<const SwifterKitServicePMAssertionHeader*>(payload);
            const uint32_t bits = header->assertionBits;
            if (bits == 0 || (bits & ~(kPMAssertionCPU | kPMAssertionForceFullWakeup)) != 0
                || header->synced > 1 || header->reserved[0] != 0 || header->reserved[1] != 0
                || header->reserved[2] != 0 || (header->synced != 0 && bits != kPMAssertionCPU)) {
                return kIOReturnBadArgument;
            }
#if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5
            uint64_t assertionID = 0;
            const kern_return_t result = CreatePMAssertion(bits, &assertionID, header->synced != 0);
            return result == kIOReturnSuccess
                       ? BytesResponse(&assertionID, sizeof(assertionID), response)
                       : result;
#else
            (void)response;
            return kIOReturnUnsupported;
#endif
        }
        case SwifterKitRuntimeOpcode::ServiceReleasePMAssertion: {
            uint64_t assertionID = 0;
            if (payloadLength != sizeof(assertionID)) {
                return kIOReturnBadArgument;
            }
            memcpy(&assertionID, payload, sizeof(assertionID));
            if (assertionID == 0) {
                return kIOReturnBadArgument;
            }
#if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5
            return ReleasePMAssertion(assertionID);
#else
            return kIOReturnUnsupported;
#endif
        }
        case SwifterKitRuntimeOpcode::ServiceCompletePowerState: {
            if (payloadLength != sizeof(SwifterKitServicePowerStateCompletion)) {
                return kIOReturnBadArgument;
            }
            const auto* completion =
                reinterpret_cast<const SwifterKitServicePowerStateCompletion*>(payload);
            if (completion->requestID == 0 || completion->reserved != 0) {
                return kIOReturnBadArgument;
            }
            return AnswerPowerState(completion->requestID);
        }
        default:
            return kIOReturnUnsupported;
    }
}
