#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER

    #include <DriverKit/IODispatchQueue.h>
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
    // The property count, key, and value limits come from RuntimeSchema+Storage.swift.
    // The longest wait between attempts to queue a target-creation result.
    constexpr uint32_t kMaximumRetryDelayMilliseconds = 64;

    // Whether a host is registered to take events, so a full required queue will drain.
    bool HasEventClient(SwifterKitRuntimeService_IVars* state) {
        IOLockLock(state->eventLock);
        const bool attached = state->eventClient != nullptr;
        IOLockUnlock(state->eventLock);
        return attached;
    }

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
        if (header->reserved != 0 || header->count > kSwifterKitSCSIMaximumPropertyCount
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
            if (entry.keyLength == 0 || entry.keyLength > kSwifterKitSCSIPropertyKeyMaximumLength
                || entry.valueLength > kSwifterKitSCSIPropertyValueMaximumLength
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
            // UserCreateTargetForID starts the target, and the kernel then waits for INQUIRY
            // through UserProcessParallelTask. Swift polls that task and completes it through
            // this user client, whose queue would stay blocked in the create until INQUIRY
            // timed out. The create runs on scsiTargetQueue; the command returns once it is
            // queued, after the properties are validated, so this request is answered then.
            // The create's own result follows as a required SCSITargetCreated event. With no
            // host registered it waits for the next host. While a host is registered and the
            // required queue is full, the block retries with a growing IOSleep backoff on
            // scsiTargetQueue, which runs nothing else that the wait could hold up. If that host
            // detaches meanwhile, DetachEventClient empties the queues and the retry stops; the
            // next host finds the created target through scsiTargetPresent.
            result = ParseProperties(payload, payloadLength, true, &target, &properties, nullptr);
            if (result == kIOReturnSuccess && ivars->scsiTargetQueue == nullptr) {
                result = kIOReturnNotReady;
            }
            if (result == kIOReturnSuccess) {
                OSDictionary* targetProperties = properties;
                properties = nullptr;
                retain();
                ivars->scsiTargetQueue->DispatchAsync(^{
                  const kern_return_t created = UserCreateTargetForID(target, targetProperties);
                  targetProperties->release();
                  const SwifterKitSCSITargetCreatedEvent event = {
                      .targetIdentifier = target,
                      .status = created,
                      .reserved = 0,
                  };
                  kern_return_t queued = EnqueueRequiredEvent(
                      kSwifterKitEventSCSITargetCreated,
                      &event,
                      sizeof(event));
                  for (uint32_t delay = 1; queued == kIOReturnNoSpace && HasEventClient(ivars);
                       delay = delay < kMaximumRetryDelayMilliseconds ? delay * 2 : delay) {
                      IOSleep(delay);
                      queued = EnqueueRequiredEvent(
                          kSwifterKitEventSCSITargetCreated,
                          &event,
                          sizeof(event));
                  }
                  release();
                });
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
