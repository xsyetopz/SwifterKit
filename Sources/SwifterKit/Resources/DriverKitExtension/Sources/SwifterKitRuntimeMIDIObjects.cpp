#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_MIDI
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSArray.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSDictionary.h>
    #include <DriverKit/OSString.h>
    #include <MIDIDriverKit/MIDIDriverKit.h>

    #include "SwifterKitRuntimeMIDIProperties.h"
    #include "SwifterKitRuntimeSchema.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    using Opcode = SwifterKitRuntimeOpcode;

    // The target kinds, key kinds, driver class marker, listed-object limit, and name limit
    // come from RuntimeSchema+MIDI.swift.

    struct __attribute__((packed)) MIDIObjectInfoHeader {
        uint32_t objectID;
        uint32_t ownerObjectID;
        uint32_t classID;
        uint32_t baseClassID;
        uint32_t nameLength;
        uint32_t reserved;
    };
    static_assert(sizeof(MIDIObjectInfoHeader) == 24);

    uint32_t ReadU32(const uint8_t* payload, uint32_t offset) {
        uint32_t value = 0;
        memcpy(&value, payload + offset, sizeof(value));
        return value;
    }

    bool Is(uint32_t opcode, Opcode expected) {
        return opcode == static_cast<uint32_t>(expected);
    }

    // Returns a retained object for a device, entity, endpoint, or object-ID target.
    IOUserMIDIObject* CopyObject(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        uint32_t kind,
        uint32_t index) {
        if (kind == kSwifterKitMIDITargetObject) {
            if (index == 0) {
                return nullptr;
            }
            OSSharedPtr<IOUserMIDIObject> holder = service->GetMIDIObjectForObjectID(index);
            if (holder) {
                holder->retain();
            }
            return holder.get();
        }
        IOUserMIDIObject* object = nullptr;
        IOLockLock(state->midiLock);
        if (kind == kSwifterKitMIDITargetDevice && index == 0) {
            object = state->midiDevice;
        } else if (kind == kSwifterKitMIDITargetEntity && index == 0) {
            object = state->midiEntity;
        } else if (kind == kSwifterKitMIDITargetSource && index < kSwifterKitMIDISourceCount) {
            object = state->midiSources[index];
        } else if (
            kind == kSwifterKitMIDITargetDestination && index < kSwifterKitMIDIDestinationCount) {
            object = state->midiDestinations[index];
        }
        if (object != nullptr) {
            object->retain();
        }
        IOLockUnlock(state->midiLock);
        return object;
    }

    // Reads a NUL-free string of 1...maximumLength bytes.
    OSString* CopyString(const uint8_t* bytes, uint32_t length, uint32_t maximumLength) {
        if (length == 0 || length > maximumLength || memchr(bytes, 0, length) != nullptr) {
            return nullptr;
        }
        return OSString::withCString(reinterpret_cast<const char*>(bytes), length);
    }

    // A property key read after the target: u32 kind (0 selector, 1 string), u32 selector or
    // string length, then the string bytes.
    struct PropertyKey {
        uint32_t selector = 0;
        OSString* name = nullptr;
        uint32_t end = 0;
    };

    kern_return_t ReadKey(const uint8_t* payload, uint32_t length, PropertyKey* key) {
        if (length < 16) {
            return kIOReturnBadArgument;
        }
        const uint32_t kind = ReadU32(payload, 8);
        const uint32_t value = ReadU32(payload, 12);
        if (kind == kSwifterKitMIDIKeySelector) {
            key->selector = value;
            key->end = 16;
            return value == 0 ? kIOReturnBadArgument : kIOReturnSuccess;
        }
        if (kind != kSwifterKitMIDIKeyString || value > length - 16) {
            return kIOReturnBadArgument;
        }
        key->name = CopyString(payload + 16, value, kSwifterKitMIDIPropertyKeyMaximumLength);
        key->end = 16 + value;
        return key->name == nullptr ? kIOReturnBadArgument : kIOReturnSuccess;
    }

    kern_return_t EncodeResponse(OSObject* value, OSData** response) {
        OSData* data = OSData::withCapacity(64);
        if (data == nullptr) {
            return kIOReturnNoMemory;
        }
        const kern_return_t result = SwifterKitEncodeMIDIValue(value, data);
        if (result != kIOReturnSuccess) {
            data->release();
            return result;
        }
        *response = data;
        return kIOReturnSuccess;
    }

    kern_return_t
        ObjectInfo(SwifterKitRuntimeService* service, IOUserMIDIObject* object, OSData** response) {
        MIDIObjectInfoHeader header = {};
        OSSharedPtr<OSString> name;
        if (object == nullptr) {
            header.objectID = kIOUserMIDIObjectIDDriver;
            header.classID = kSwifterKitMIDIDriverClass;
            header.baseClassID = kSwifterKitMIDIDriverClass;
            name = service->GetName();
        } else {
            header.objectID = object->GetObjectID();
            header.ownerObjectID = object->GetOwnerObjectID();
            header.classID = static_cast<uint32_t>(object->GetClassID());
            header.baseClassID = static_cast<uint32_t>(object->GetBaseClassID());
            name = object->GetName();
        }
        header.nameLength = name ? static_cast<uint32_t>(name->getLength()) : 0;
        if (header.nameLength > kSwifterKitMIDINameMaximumLength) {
            return kIOReturnNoSpace;
        }
        OSData* data = OSData::withCapacity(sizeof(header) + header.nameLength);
        if (data == nullptr || !data->appendBytes(&header, sizeof(header))
            || (header.nameLength != 0
                && !data->appendBytes(name->getCStringNoCopy(), header.nameLength))) {
            OSSafeReleaseNULL(data);
            return kIOReturnNoMemory;
        }
        *response = data;
        return kIOReturnSuccess;
    }

    // Answers `u32 value, u32 count, count × u32 object ID` from up to two object arrays.
    kern_return_t ObjectIDList(uint32_t value, OSArray* first, OSArray* second, OSData** response) {
        const uint32_t firstCount = first == nullptr ? 0 : first->getCount();
        const uint32_t count = firstCount + (second == nullptr ? 0 : second->getCount());
        if (count > kSwifterKitMIDIMaximumListedObjects) {
            return kIOReturnNoSpace;
        }
        OSData* data = OSData::withCapacity(8 + count * 4);
        const uint32_t header[2] = {value, count};
        if (data == nullptr || !data->appendBytes(header, sizeof(header))) {
            OSSafeReleaseNULL(data);
            return kIOReturnNoMemory;
        }
        __block kern_return_t result = kIOReturnSuccess;
        OSArray* arrays[2] = {first, second};
        for (OSArray* array : arrays) {
            if (array == nullptr || result != kIOReturnSuccess) {
                continue;
            }
            array->iterateObjects(^bool(OSObject* member) {
              auto* object = OSDynamicCast(IOUserMIDIObject, member);
              const uint32_t objectID = object == nullptr ? 0 : object->GetObjectID();
              if (objectID == 0) {
                  result = kIOReturnInternalError;
              } else if (!data->appendBytes(&objectID, sizeof(objectID))) {
                  result = kIOReturnNoMemory;
              }
              return result != kIOReturnSuccess;
            });
        }
        if (result != kIOReturnSuccess) {
            data->release();
            return result;
        }
        *response = data;
        return kIOReturnSuccess;
    }

    kern_return_t SetMembership(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        const uint8_t* payload) {
        const uint32_t kind = ReadU32(payload, 0);
        const uint32_t index = ReadU32(payload, 4);
        const uint32_t attached = ReadU32(payload, 8);
        if (attached > 1 || ReadU32(payload, 12) != 0
            || (kind != kSwifterKitMIDITargetEntity && kind != kSwifterKitMIDITargetSource
                && kind != kSwifterKitMIDITargetDestination)) {
            return kIOReturnBadArgument;
        }
        IOUserMIDIObject* member = CopyObject(service, state, kind, index);
        const uint32_t ownerKind = kind == kSwifterKitMIDITargetEntity
                                       ? kSwifterKitMIDITargetDevice
                                       : kSwifterKitMIDITargetEntity;
        IOUserMIDIObject* owner = CopyObject(service, state, ownerKind, 0);
        kern_return_t result = kIOReturnNotReady;
        if (member != nullptr && owner != nullptr) {
            if (auto* entity = OSDynamicCast(IOUserMIDIEntity, member)) {
                auto* device = OSDynamicCast(IOUserMIDIDevice, owner);
                result = attached != 0 ? device->AddEntity(entity) : device->RemoveEntity(entity);
            } else if (auto* source = OSDynamicCast(IOUserMIDISource, member)) {
                auto* entityOwner = OSDynamicCast(IOUserMIDIEntity, owner);
                result = attached != 0 ? entityOwner->AddSource(source)
                                       : entityOwner->RemoveSource(source);
            } else if (auto* destination = OSDynamicCast(IOUserMIDIDestination, member)) {
                auto* entityOwner = OSDynamicCast(IOUserMIDIEntity, owner);
                result = attached != 0 ? entityOwner->AddDestination(destination)
                                       : entityOwner->RemoveDestination(destination);
            } else {
                result = kIOReturnInternalError;
            }
        }
        OSSafeReleaseNULL(member);
        OSSafeReleaseNULL(owner);
        return result;
    }

    // Serves the property opcodes on an object the caller holds.
    kern_return_t PropertyCommand(
        uint32_t opcode,
        IOUserMIDIObject* object,
        const uint8_t* payload,
        uint32_t length,
        OSData** response) {
        if (Is(opcode, Opcode::MIDIGetProperties)) {
            if (length != 8) {
                return kIOReturnBadArgument;
            }
            OSSharedPtr<OSDictionary> properties = object->GetProperties();
            OSDictionary* empty = properties ? nullptr : OSDictionary::withCapacity(1);
            OSObject* value = properties ? static_cast<OSObject*>(properties.get()) : empty;
            const kern_return_t result =
                value == nullptr ? kIOReturnNoMemory : EncodeResponse(value, response);
            OSSafeReleaseNULL(empty);
            return result;
        }
        if (Is(opcode, Opcode::MIDISetProperties)) {
            OSObject* value = nullptr;
            kern_return_t result = SwifterKitDecodeMIDIValue(payload + 8, length - 8, &value);
            auto* dictionary = OSDynamicCast(OSDictionary, value);
            if (result == kIOReturnSuccess) {
                result = dictionary == nullptr ? kIOReturnBadArgument
                                               : object->SetProperties(dictionary);
            }
            OSSafeReleaseNULL(value);
            return result;
        }

        PropertyKey key;
        kern_return_t result = ReadKey(payload, length, &key);
        const auto selector = static_cast<IOUserMIDIProperty>(key.selector);
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(key.name);
            return result;
        }
        if (Is(opcode, Opcode::MIDIGetPropertyType)) {
            IOUserMIDIPropertyType type = IOUserMIDIPropertyType::String;
            result = key.name != nullptr || key.end != length
                         ? kIOReturnBadArgument
                         : object->GetPropertyType(selector, &type);
            const uint32_t value = static_cast<uint32_t>(type);
            if (result == kIOReturnSuccess) {
                *response = OSData::withBytes(&value, sizeof(value));
                result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
            }
        } else if (Is(opcode, Opcode::MIDICopyProperty)) {
            OSObject* value = nullptr;
            if (key.end != length) {
                result = kIOReturnBadArgument;
            } else {
                result = key.name != nullptr ? object->CopyProperty(key.name, &value)
                                             : object->CopyProperty(selector, &value);
            }
            if (result == kIOReturnSuccess) {
                result = value == nullptr ? kIOReturnNotFound : EncodeResponse(value, response);
            }
            OSSafeReleaseNULL(value);
        } else if (Is(opcode, Opcode::MIDISetProperty)) {
            OSObject* value = nullptr;
            result = SwifterKitDecodeMIDIValue(payload + key.end, length - key.end, &value);
            if (result == kIOReturnSuccess) {
                result = key.name != nullptr ? object->SetProperty(key.name, value)
                                             : object->SetProperty(selector, value);
            }
            OSSafeReleaseNULL(value);
        } else {
            result = kIOReturnBadArgument;
        }
        OSSafeReleaseNULL(key.name);
        return result;
    }
}  // namespace

// Serves opcodes 0x0810-0x0819 for MIDIObjectTarget, MIDIPropertyValue, and MIDIMember.
kern_return_t SwifterKitRuntimeService::MIDIObjectCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->midiLock == nullptr || response == nullptr
        || opcode < static_cast<uint32_t>(Opcode::MIDIGetObjectInfo)
        || opcode > static_cast<uint32_t>(Opcode::MIDISetMemberAttachment)
        || (payload == nullptr && payloadLength != 0)) {
        return kIOReturnBadArgument;
    }

    if (Is(opcode, Opcode::MIDIGetDeviceState) || Is(opcode, Opcode::MIDIGetEntityMembers)) {
        if (payloadLength != 0) {
            return kIOReturnBadArgument;
        }
        const bool device = Is(opcode, Opcode::MIDIGetDeviceState);
        IOUserMIDIObject* object = CopyObject(
            this,
            ivars,
            device ? kSwifterKitMIDITargetDevice : kSwifterKitMIDITargetEntity,
            0);
        if (object == nullptr) {
            return kIOReturnNotReady;
        }
        kern_return_t result = kIOReturnInternalError;
        if (auto* midiDevice = OSDynamicCast(IOUserMIDIDevice, object)) {
            OSSharedPtr<OSArray> entities = midiDevice->GetEntities();
            const uint32_t running = midiDevice->GetDeviceIsRunning() ? 1 : 0;
            result = ObjectIDList(running, entities.get(), nullptr, response);
        } else if (auto* entity = OSDynamicCast(IOUserMIDIEntity, object)) {
            OSSharedPtr<OSArray> sources = entity->GetSources();
            OSSharedPtr<OSArray> destinations = entity->GetDestinations();
            const uint32_t sourceCount = sources ? sources->getCount() : 0;
            result = ObjectIDList(sourceCount, sources.get(), destinations.get(), response);
        }
        object->release();
        return result;
    }

    if (payloadLength < 8) {
        return kIOReturnBadArgument;
    }
    if (Is(opcode, Opcode::MIDISetMemberAttachment)) {
        return payloadLength == 16 ? SetMembership(this, ivars, payload) : kIOReturnBadArgument;
    }
    const uint32_t kind = ReadU32(payload, 0);
    const uint32_t index = ReadU32(payload, 4);
    const bool driver = kind == kSwifterKitMIDITargetDriver;
    if (driver && index != 0) {
        return kIOReturnBadArgument;
    }
    IOUserMIDIObject* object = driver ? nullptr : CopyObject(this, ivars, kind, index);
    if (!driver && object == nullptr) {
        return kIOReturnNotFound;
    }

    kern_return_t result = kIOReturnBadArgument;
    if (Is(opcode, Opcode::MIDIGetObjectInfo)) {
        result = payloadLength == 8 ? ObjectInfo(this, object, response) : kIOReturnBadArgument;
    } else if (Is(opcode, Opcode::MIDISetObjectName)) {
        const uint32_t nameLength = payloadLength >= 16 ? ReadU32(payload, 8) : 0;
        OSString* name =
            payloadLength >= 16 && ReadU32(payload, 12) == 0 && nameLength == payloadLength - 16
                ? CopyString(payload + 16, nameLength, kSwifterKitMIDINameMaximumLength)
                : nullptr;
        if (name != nullptr) {
            result = driver ? SetName(name) : object->SetName(name);
            name->release();
        }
    } else if (!driver) {
        result = PropertyCommand(opcode, object, payload, payloadLength, response);
    }
    OSSafeReleaseNULL(object);
    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(*response);
    }
    return result;
}

#endif
