#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_MIDI
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSArray.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSDictionary.h>
    #include <DriverKit/OSNumber.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeMIDIProperties.h"
    #include "SwifterKitRuntimeSchema.h"

namespace {
    // The value types and the depth, entry, and key limits come from RuntimeSchema+MIDI.swift.
    constexpr uint32_t kMaximumEncodedLength =
        kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize;

    uint32_t ReadU32(const uint8_t* bytes) {
        uint32_t value = 0;
        memcpy(&value, bytes, sizeof(value));
        return value;
    }

    uint64_t ReadU64(const uint8_t* bytes) {
        uint64_t value = 0;
        memcpy(&value, bytes, sizeof(value));
        return value;
    }

    bool IsValidWidth(uint64_t bits) {
        return bits == 8 || bits == 16 || bits == 32 || bits == 64;
    }

    uint64_t WidthMask(uint64_t bits) {
        return bits == 64 ? UINT64_MAX : (1ULL << bits) - 1;
    }

    // Copies a NUL-free byte run into an OSString.
    OSString* MakeString(const uint8_t* bytes, uint32_t length) {
        if (length != 0 && memchr(bytes, 0, length) != nullptr) {
            return nullptr;
        }
        return OSString::withCString(reinterpret_cast<const char*>(bytes), length);
    }

    kern_return_t Decode(
        const uint8_t* bytes,
        uint32_t length,
        uint32_t* offset,
        uint32_t depth,
        OSObject** value);

    kern_return_t DecodeContainer(
        uint32_t type,
        const uint8_t* body,
        uint32_t length,
        uint32_t depth,
        OSObject** value) {
        if (depth > kSwifterKitMIDIPropertyMaximumDepth || length < 8) {
            return kIOReturnBadArgument;
        }
        const uint32_t count = ReadU32(body);
        if (ReadU32(body + 4) != 0 || count > kSwifterKitMIDIPropertyMaximumEntries) {
            return kIOReturnBadArgument;
        }
        OSDictionary* dictionary = nullptr;
        OSArray* array = nullptr;
        if (type == kSwifterKitMIDIValueDictionary) {
            dictionary = OSDictionary::withCapacity(count == 0 ? 1 : count);
        } else {
            array = OSArray::withCapacity(count == 0 ? 1 : count);
        }
        if (dictionary == nullptr && array == nullptr) {
            return kIOReturnNoMemory;
        }
        kern_return_t result = kIOReturnSuccess;
        uint32_t cursor = 8;
        for (uint32_t index = 0; result == kIOReturnSuccess && index < count; ++index) {
            const OSString* key = nullptr;
            if (dictionary != nullptr) {
                if (length - cursor < 8) {
                    result = kIOReturnBadArgument;
                    break;
                }
                const uint32_t keyLength = ReadU32(body + cursor);
                if (ReadU32(body + cursor + 4) != 0 || keyLength == 0
                    || keyLength > kSwifterKitMIDIPropertyKeyMaximumLength
                    || keyLength > length - cursor - 8) {
                    result = kIOReturnBadArgument;
                    break;
                }
                key = MakeString(body + cursor + 8, keyLength);
                cursor += 8 + keyLength;
                if (key == nullptr || dictionary->getObject(key) != nullptr) {
                    OSSafeReleaseNULL(key);
                    result = kIOReturnBadArgument;
                    break;
                }
            }
            OSObject* member = nullptr;
            result = Decode(body, length, &cursor, depth + 1, &member);
            if (result == kIOReturnSuccess) {
                const bool stored =
                    key != nullptr ? dictionary->setObject(key, member) : array->setObject(member);
                result = stored ? kIOReturnSuccess : kIOReturnNoMemory;
            }
            OSSafeReleaseNULL(member);
            OSSafeReleaseNULL(key);
        }
        if (result == kIOReturnSuccess && cursor != length) {
            result = kIOReturnBadArgument;
        }
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(dictionary);
            OSSafeReleaseNULL(array);
            return result;
        }
        *value = dictionary != nullptr ? static_cast<OSObject*>(dictionary)
                                       : static_cast<OSObject*>(array);
        return kIOReturnSuccess;
    }

    kern_return_t Decode(
        const uint8_t* bytes,
        uint32_t length,
        uint32_t* offset,
        uint32_t depth,
        OSObject** value) {
        if (*offset > length || length - *offset < 8) {
            return kIOReturnBadArgument;
        }
        const uint32_t type = ReadU32(bytes + *offset);
        const uint32_t bodyLength = ReadU32(bytes + *offset + 4);
        const uint32_t start = *offset + 8;
        if (bodyLength > length - start) {
            return kIOReturnBadArgument;
        }
        const uint8_t* body = bytes + start;
        *offset = start + bodyLength;
        OSObject* object = nullptr;
        switch (type) {
            case kSwifterKitMIDIValueString:
                object = MakeString(body, bodyLength);
                if (object == nullptr) {
                    return kIOReturnBadArgument;
                }
                break;
            case kSwifterKitMIDIValueNumber: {
                if (bodyLength != 16) {
                    return kIOReturnBadArgument;
                }
                const uint32_t bits = ReadU32(body);
                const uint64_t raw = ReadU64(body + 8);
                if (!IsValidWidth(bits) || ReadU32(body + 4) != 0
                    || (raw & ~WidthMask(bits)) != 0) {
                    return kIOReturnBadArgument;
                }
                object = OSNumber::withNumber(raw, bits);
                break;
            }
            case kSwifterKitMIDIValueData:
                object =
                    bodyLength == 0 ? OSData::withCapacity(1) : OSData::withBytes(body, bodyLength);
                break;
            case kSwifterKitMIDIValueDictionary:
            case kSwifterKitMIDIValueArray:
                return DecodeContainer(type, body, bodyLength, depth, value);
            default:
                return kIOReturnBadArgument;
        }
        if (object == nullptr) {
            return kIOReturnNoMemory;
        }
        *value = object;
        return kIOReturnSuccess;
    }

    kern_return_t Append(OSData* data, const void* bytes, size_t length) {
        if (length > kMaximumEncodedLength - data->getLength()) {
            return kIOReturnNoSpace;
        }
        return length == 0 || data->appendBytes(bytes, length) ? kIOReturnSuccess
                                                               : kIOReturnNoMemory;
    }

    kern_return_t AppendHeader(OSData* data, uint32_t type, uint32_t length) {
        const uint32_t header[2] = {type, length};
        return Append(data, header, sizeof(header));
    }

    kern_return_t Encode(const OSObject* value, OSData* data, uint32_t depth);

    // Encodes container members into a scratch buffer so the header can carry the body length.
    kern_return_t EncodeContainer(const OSObject* value, OSData* data, uint32_t depth) {
        const auto* dictionary = OSDynamicCast(OSDictionary, value);
        const auto* array = OSDynamicCast(OSArray, value);
        const uint32_t count = dictionary != nullptr ? dictionary->getCount() : array->getCount();
        if (depth > kSwifterKitMIDIPropertyMaximumDepth
            || count > kSwifterKitMIDIPropertyMaximumEntries) {
            return kIOReturnNoSpace;
        }
        OSData* body = OSData::withCapacity(64);
        if (body == nullptr) {
            return kIOReturnNoMemory;
        }
        __block kern_return_t result = AppendHeader(body, count, 0);
        if (result == kIOReturnSuccess && dictionary != nullptr) {
            dictionary->iterateObjects(^bool(OSObject* key, OSObject* member) {
              const auto* name = OSDynamicCast(OSString, key);
              const size_t keyLength = name == nullptr ? 0 : name->getLength();
              if (keyLength == 0 || keyLength > kSwifterKitMIDIPropertyKeyMaximumLength) {
                  result = kIOReturnUnsupported;
                  return true;
              }
              result = AppendHeader(body, static_cast<uint32_t>(keyLength), 0);
              if (result == kIOReturnSuccess) {
                  result = Append(body, name->getCStringNoCopy(), keyLength);
              }
              if (result == kIOReturnSuccess) {
                  result = Encode(member, body, depth + 1);
              }
              return result != kIOReturnSuccess;
            });
        } else if (result == kIOReturnSuccess) {
            array->iterateObjects(^bool(OSObject* member) {
              result = Encode(member, body, depth + 1);
              return result != kIOReturnSuccess;
            });
        }
        const uint32_t type =
            dictionary != nullptr ? kSwifterKitMIDIValueDictionary : kSwifterKitMIDIValueArray;
        if (result == kIOReturnSuccess) {
            result = AppendHeader(data, type, static_cast<uint32_t>(body->getLength()));
        }
        if (result == kIOReturnSuccess) {
            result = Append(data, body->getBytesNoCopy(), body->getLength());
        }
        body->release();
        return result;
    }

    kern_return_t Encode(const OSObject* value, OSData* data, uint32_t depth) {
        if (const auto* string = OSDynamicCast(OSString, value)) {
            const size_t length = string->getLength();
            if (length > kMaximumEncodedLength) {
                return kIOReturnNoSpace;
            }
            const kern_return_t result =
                AppendHeader(data, kSwifterKitMIDIValueString, static_cast<uint32_t>(length));
            return result == kIOReturnSuccess ? Append(data, string->getCStringNoCopy(), length)
                                              : result;
        }
        if (const auto* number = OSDynamicCast(OSNumber, value)) {
            const uint64_t bits = number->numberOfBits();
            if (!IsValidWidth(bits)) {
                return kIOReturnUnsupported;
            }
            const uint32_t header[2] = {static_cast<uint32_t>(bits), 0};
            const uint64_t raw = number->unsigned64BitValue() & WidthMask(bits);
            kern_return_t result = AppendHeader(data, kSwifterKitMIDIValueNumber, 16);
            if (result == kIOReturnSuccess) {
                result = Append(data, header, sizeof(header));
            }
            return result == kIOReturnSuccess ? Append(data, &raw, sizeof(raw)) : result;
        }
        if (const auto* bytes = OSDynamicCast(OSData, value)) {
            const size_t length = bytes->getLength();
            if (length > kMaximumEncodedLength) {
                return kIOReturnNoSpace;
            }
            const kern_return_t result =
                AppendHeader(data, kSwifterKitMIDIValueData, static_cast<uint32_t>(length));
            return result == kIOReturnSuccess ? Append(data, bytes->getBytesNoCopy(), length)
                                              : result;
        }
        if (OSDynamicCast(OSDictionary, value) != nullptr
            || OSDynamicCast(OSArray, value) != nullptr) {
            return EncodeContainer(value, data, depth);
        }
        return kIOReturnUnsupported;
    }
}  // namespace

kern_return_t SwifterKitDecodeMIDIValue(const uint8_t* bytes, uint32_t length, OSObject** value) {
    if (bytes == nullptr || value == nullptr) {
        return kIOReturnBadArgument;
    }
    *value = nullptr;
    uint32_t offset = 0;
    OSObject* object = nullptr;
    const kern_return_t result = Decode(bytes, length, &offset, 1, &object);
    if (result != kIOReturnSuccess) {
        return result;
    }
    if (offset != length) {
        object->release();
        return kIOReturnBadArgument;
    }
    *value = object;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitEncodeMIDIValue(OSObject* value, OSData* data) {
    if (value == nullptr || data == nullptr) {
        return kIOReturnBadArgument;
    }
    return Encode(value, data, 1);
}

#endif
