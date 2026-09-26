#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER

    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSArray.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSDictionary.h>
    #include <DriverKit/OSString.h>
    #include <string.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

// Swift-initiated IOUserSCSIParallelInterfaceController calls: target presence, creation, and
// destruction, HBA and target properties, media-parameter changes, and access to the data
// buffers fetched for pending tasks. Each command answers its runtime request exactly once.
namespace {
    constexpr uint32_t kMaximumPropertyCount = 32;
    constexpr uint16_t kMaximumKeyLength = 127;
    constexpr uint16_t kMaximumValueLength = 1'024;

    // Parses the entries after a SwifterKitSCSIPropertyHeader. With `keys`, the entries are key
    // names only; otherwise they are key and OSString value pairs for `dictionary`. Keys may not
    // repeat, and no key or value may contain a NUL byte.
    kern_return_t ParseProperties(
        const uint8_t* payload,
        uint32_t payloadLength,
        bool allowsEmpty,
        uint64_t* target,
        OSDictionary** dictionary,
        OSArray** keys) {
        if (payload == nullptr || payloadLength < sizeof(SwifterKitSCSIPropertyHeader)) {
            return kIOReturnBadArgument;
        }
        const auto* header = reinterpret_cast<const SwifterKitSCSIPropertyHeader*>(payload);
        if (header->reserved != 0 || header->count > kMaximumPropertyCount
            || (header->count == 0 && !allowsEmpty)) {
            return kIOReturnBadArgument;
        }
        OSDictionary* values =
            keys == nullptr ? OSDictionary::withCapacity(header->count + 1) : nullptr;
        OSArray* names = keys != nullptr ? OSArray::withCapacity(header->count + 1) : nullptr;
        kern_return_t result =
            values == nullptr && names == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        uint32_t offset = sizeof(*header);
        for (uint32_t index = 0; result == kIOReturnSuccess && index < header->count; ++index) {
            SwifterKitSCSIPropertyEntry entry = {};
            if (payloadLength - offset < sizeof(entry)) {
                result = kIOReturnBadArgument;
                break;
            }
            memcpy(&entry, payload + offset, sizeof(entry));
            offset += sizeof(entry);
            const char* key = reinterpret_cast<const char*>(payload + offset);
            const char* value = key + entry.keyLength;
            if (entry.keyLength == 0 || entry.keyLength > kMaximumKeyLength
                || entry.valueLength > kMaximumValueLength
                || (names != nullptr && entry.valueLength != 0)
                || payloadLength - offset < uint32_t {entry.keyLength} + entry.valueLength
                || memchr(key, 0, entry.keyLength) != nullptr
                || memchr(value, 0, entry.valueLength) != nullptr) {
                result = kIOReturnBadArgument;
                break;
            }
            offset += entry.keyLength + entry.valueLength;
            OSString* name = OSString::withCString(key, entry.keyLength);
            OSString* string =
                values != nullptr ? OSString::withCString(value, entry.valueLength) : nullptr;
            if (name == nullptr || (values != nullptr && string == nullptr)) {
                result = kIOReturnNoMemory;
            } else if (values != nullptr) {
                result = values->getObject(name) != nullptr ? kIOReturnBadArgument
                         : values->setObject(name, string)  ? kIOReturnSuccess
                                                            : kIOReturnNoMemory;
            } else {
                for (uint32_t other = 0; result == kIOReturnSuccess && other < names->getCount();
                     ++other) {
                    if (name->isEqualTo(OSDynamicCast(OSString, names->getObject(other)))) {
                        result = kIOReturnBadArgument;
                    }
                }
                if (result == kIOReturnSuccess && !names->setObject(name)) {
                    result = kIOReturnNoMemory;
                }
            }
            OSSafeReleaseNULL(string);
            OSSafeReleaseNULL(name);
        }
        if (result == kIOReturnSuccess && offset != payloadLength) {
            result = kIOReturnBadArgument;
        }
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(values);
            OSSafeReleaseNULL(names);
            return result;
        }
        *target = header->targetIdentifier;
        if (keys != nullptr) {
            *keys = names;
        } else {
            *dictionary = values;
        }
        return kIOReturnSuccess;
    }

    bool ReadTarget(const uint8_t* payload, uint32_t payloadLength, uint64_t* target) {
        if (payload == nullptr || payloadLength != sizeof(*target)) {
            return false;
        }
        memcpy(target, payload, sizeof(*target));
        return true;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::SCSIFetchTaskBuffer(
    const SCSIUserParallelTask* request,
    IOBufferMemoryDescriptor** buffer,
    IOMemoryMap** map) {
    if (request == nullptr || buffer == nullptr || map == nullptr) {
        return kIOReturnBadArgument;
    }
    uint64_t length = 0;
    kern_return_t result =
        UserGetDataBuffer(request->fTargetID, request->fControllerTaskIdentifier, buffer);
    if (result == kIOReturnSuccess && *buffer == nullptr) {
        result = kIOReturnNotFound;
    }
    if (result == kIOReturnSuccess) {
        result = (*buffer)->GetLength(&length);
    }
    if (result == kIOReturnSuccess) {
        result =
            length == 0 ? kIOReturnNotFound : (*buffer)->CreateMapping(0, 0, 0, length, 0, map);
    }
    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(*map);
        OSSafeReleaseNULL(*buffer);
    }
    return result;
}

kern_return_t SwifterKitRuntimeService::SCSIControlCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (response == nullptr || ivars == nullptr || ivars->scsiLock == nullptr) {
        return kIOReturnBadArgument;
    }
    uint64_t target = 0;
    OSDictionary* properties = nullptr;
    OSArray* keys = nullptr;
    kern_return_t result = kIOReturnBadArgument;
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::SCSITargetPresent: {
            bool present = false;
            if (!ReadTarget(payload, payloadLength, &target)) {
                return kIOReturnBadArgument;
            }
            result = UserTargetPresentForID(target, &present);
            if (result != kIOReturnSuccess) {
                return result;
            }
            const uint32_t value = present ? 1 : 0;
            *response = OSData::withBytes(&value, sizeof(value));
            return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
        case SwifterKitRuntimeOpcode::SCSICreateTarget:
            result = ParseProperties(payload, payloadLength, true, &target, &properties, nullptr);
            if (result == kIOReturnSuccess) {
                result = UserCreateTargetForID(target, properties);
            }
            break;
        case SwifterKitRuntimeOpcode::SCSIDestroyTarget:
            return ReadTarget(payload, payloadLength, &target) ? UserDestroyTargetForID(target)
                                                               : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::SCSISetControllerProperties:
        case SwifterKitRuntimeOpcode::SCSISetTargetProperties:
            result = ParseProperties(payload, payloadLength, false, &target, &properties, nullptr);
            if (result != kIOReturnSuccess) {
                break;
            }
            if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::SCSISetTargetProperties)) {
                result = UserSetTargetProperties(target, properties);
            } else {
                result = target == 0 ? UserSetHBAProperties(properties) : kIOReturnBadArgument;
            }
            break;
        case SwifterKitRuntimeOpcode::SCSIRemoveControllerProperties:
        case SwifterKitRuntimeOpcode::SCSIRemoveTargetProperties:
            result = ParseProperties(payload, payloadLength, false, &target, nullptr, &keys);
            if (result != kIOReturnSuccess) {
                break;
            }
            if (opcode
                == static_cast<uint32_t>(SwifterKitRuntimeOpcode::SCSIRemoveTargetProperties)) {
                result = UserRemoveTargetProperties(target, keys);
            } else {
                result = target == 0 ? UserRemoveHBAProperties(keys) : kIOReturnBadArgument;
            }
            break;
        case SwifterKitRuntimeOpcode::SCSIMediaParametersChanged:
            return payloadLength == 0 ? UserCallMediaParametersHaveChanged() : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::SCSIReadTaskData:
        case SwifterKitRuntimeOpcode::SCSIWriteTaskData:
            return SCSITaskData(opcode, payload, payloadLength, response);
        default:
            return kIOReturnBadArgument;
    }
    OSSafeReleaseNULL(properties);
    OSSafeReleaseNULL(keys);
    return result;
}

kern_return_t SwifterKitRuntimeService::SCSITaskData(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (!kSwifterKitSCSIProvidesTaskDataBuffers) {
        return kIOReturnUnsupported;
    }
    SwifterKitSCSITaskDataHeader header = {};
    if (payload == nullptr || payloadLength < sizeof(header)) {
        return kIOReturnBadArgument;
    }
    memcpy(&header, payload, sizeof(header));
    const bool writes = opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::SCSIWriteTaskData);
    const uint32_t maximum = kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize;
    if (header.requestID == 0 || header.length == 0 || header.length > maximum
        || payloadLength != sizeof(header) + (writes ? header.length : 0)) {
        return kIOReturnBadArgument;
    }
    // The copy runs under scsiLock so a completion cannot release the buffer during it.
    kern_return_t result = kIOReturnNotFound;
    IOLockLock(ivars->scsiLock);
    for (const auto& task : ivars->scsiTasks) {
        if (task.completion == nullptr || task.requestID != header.requestID) {
            continue;
        }
        const uint64_t mapped = task.dataMap == nullptr ? 0 : task.dataMap->GetLength();
        const uint64_t available =
            mapped < task.requestedTransferCount ? mapped : task.requestedTransferCount;
        auto* bytes = task.dataMap == nullptr
                          ? nullptr
                          : reinterpret_cast<uint8_t*>(task.dataMap->GetAddress());
        if (bytes == nullptr) {
            result = kIOReturnNotReady;
        } else if (header.offset > available || header.length > available - header.offset) {
            result = kIOReturnBadArgument;
        } else if (writes) {
            memcpy(bytes + header.offset, payload + sizeof(header), header.length);
            result = kIOReturnSuccess;
        } else {
            *response = OSData::withBytes(bytes + header.offset, header.length);
            result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
        break;
    }
    IOLockUnlock(ivars->scsiLock);
    return result;
}

#endif
