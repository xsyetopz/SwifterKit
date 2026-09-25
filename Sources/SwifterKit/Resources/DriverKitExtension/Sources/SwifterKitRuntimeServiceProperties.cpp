#include "SwifterKitRuntimeServiceProperties.h"

#include <DriverKit/IOLib.h>
#include <DriverKit/OSCollections.h>
#include <string.h>

#include "SwifterKitRuntimeServiceProtocol.h"

namespace {
    // Reads the wire format front to back; every read checks the remaining length first.
    struct PropertyReader {
        const uint8_t* bytes;
        uint32_t length;
        uint32_t offset = 0;

        [[nodiscard]] uint32_t remaining() const {
            return length - offset;
        }

        bool readBytes(void* destination, uint32_t count) {
            if (count > remaining()) {
                return false;
            }
            memcpy(destination, bytes + offset, count);
            offset += count;
            return true;
        }

        bool skip(uint32_t count, const uint8_t** start) {
            if (count > remaining()) {
                return false;
            }
            *start = bytes + offset;
            offset += count;
            return true;
        }
    };

    bool HasNul(const uint8_t* bytes, uint32_t length) {
        return length != 0 && memchr(bytes, 0, length) != nullptr;
    }

    OSObject* DecodeValue(PropertyReader* reader, uint32_t depth);

    OSObject* DecodeNumber(PropertyReader* reader) {
        uint8_t bits = 0;
        uint64_t value = 0;
        if (!reader->readBytes(&bits, sizeof(bits)) || !reader->readBytes(&value, sizeof(value))
            || (bits != 8 && bits != 16 && bits != 32 && bits != 64)
            || (bits < 64 && (value >> bits) != 0)) {
            return nullptr;
        }
        return OSNumber::withNumber(value, bits);
    }

    OSObject* DecodeString(PropertyReader* reader) {
        uint32_t count = 0;
        const uint8_t* start = nullptr;
        if (!reader->readBytes(&count, sizeof(count)) || !reader->skip(count, &start)
            || HasNul(start, count)) {
            return nullptr;
        }
        return OSString::withCString(reinterpret_cast<const char*>(start), count);
    }

    OSObject* DecodeData(PropertyReader* reader) {
        uint32_t count = 0;
        const uint8_t* start = nullptr;
        if (!reader->readBytes(&count, sizeof(count)) || !reader->skip(count, &start)) {
            return nullptr;
        }
        return count == 0 ? OSData::withCapacity(1) : OSData::withBytes(start, count);
    }

    OSObject* DecodeArray(PropertyReader* reader, uint32_t depth) {
        uint32_t count = 0;
        // Every element takes at least two bytes, so the count never sizes past the payload.
        if (!reader->readBytes(&count, sizeof(count)) || count > reader->remaining() / 2) {
            return nullptr;
        }
        OSArray* array = OSArray::withCapacity(count);
        for (uint32_t index = 0; array != nullptr && index < count; ++index) {
            const OSObject* element = DecodeValue(reader, depth + 1);
            const bool added = element != nullptr && array->setObject(element);
            OSSafeReleaseNULL(element);
            if (!added) {
                OSSafeReleaseNULL(array);
            }
        }
        return array;
    }

    OSObject* DecodeDictionary(PropertyReader* reader, uint32_t depth) {
        uint32_t count = 0;
        // Every entry takes at least a key length, one key byte, and a two-byte value.
        if (!reader->readBytes(&count, sizeof(count)) || count > reader->remaining() / 7) {
            return nullptr;
        }
        OSDictionary* dictionary = OSDictionary::withCapacity(count);
        for (uint32_t index = 0; dictionary != nullptr && index < count; ++index) {
            uint32_t keyLength = 0;
            const uint8_t* key = nullptr;
            const OSString* name = nullptr;
            if (reader->readBytes(&keyLength, sizeof(keyLength)) && keyLength != 0
                && reader->skip(keyLength, &key) && !HasNul(key, keyLength)) {
                name = OSString::withCString(reinterpret_cast<const char*>(key), keyLength);
            }
            const OSObject* element = name == nullptr || dictionary->getObject(name) != nullptr
                                          ? nullptr
                                          : DecodeValue(reader, depth + 1);
            const bool added = element != nullptr && dictionary->setObject(name, element);
            OSSafeReleaseNULL(element);
            OSSafeReleaseNULL(name);
            if (!added) {
                OSSafeReleaseNULL(dictionary);
            }
        }
        return dictionary;
    }

    OSObject* DecodeValue(PropertyReader* reader, uint32_t depth) {
        uint8_t tag = 0;
        if (depth > kSwifterKitPropertyMaximumDepth || !reader->readBytes(&tag, sizeof(tag))) {
            return nullptr;
        }
        switch (static_cast<SwifterKitPropertyTag>(tag)) {
            case SwifterKitPropertyTag::Boolean: {
                uint8_t value = 0;
                if (!reader->readBytes(&value, sizeof(value)) || value > 1) {
                    return nullptr;
                }
                OSBoolean* boolean = value != 0 ? kOSBooleanTrue : kOSBooleanFalse;
                boolean->retain();
                return boolean;
            }
            case SwifterKitPropertyTag::Number:
                return DecodeNumber(reader);
            case SwifterKitPropertyTag::String:
                return DecodeString(reader);
            case SwifterKitPropertyTag::Data:
                return DecodeData(reader);
            case SwifterKitPropertyTag::Array:
                return DecodeArray(reader, depth);
            case SwifterKitPropertyTag::Dictionary:
                return DecodeDictionary(reader, depth);
        }
        return nullptr;
    }

    bool Append(OSData* data, uint32_t maximumLength, const void* bytes, uint32_t count) {
        return count <= maximumLength && data->getLength() <= maximumLength - count
               && (count == 0 || data->appendBytes(bytes, count));
    }

    bool AppendTag(OSData* data, uint32_t maximumLength, SwifterKitPropertyTag tag) {
        const auto value = static_cast<uint8_t>(tag);
        return Append(data, maximumLength, &value, sizeof(value));
    }

    bool AppendBytes(
        OSData* data,
        uint32_t maximumLength,
        SwifterKitPropertyTag tag,
        const void* bytes,
        size_t count) {
        if (count > UINT32_MAX) {
            return false;
        }
        const auto length = static_cast<uint32_t>(count);
        return AppendTag(data, maximumLength, tag)
               && Append(data, maximumLength, &length, sizeof(length))
               && Append(data, maximumLength, bytes, length);
    }

    kern_return_t
        EncodeValue(const OSObject* value, OSData* data, uint32_t maximumLength, uint32_t depth) {
        if (value == nullptr || depth > kSwifterKitPropertyMaximumDepth) {
            return kIOReturnUnsupported;
        }
        bool fits = true;
        if (value == kOSBooleanTrue || value == kOSBooleanFalse) {
            const uint8_t flag = value == kOSBooleanTrue ? 1 : 0;
            fits = AppendTag(data, maximumLength, SwifterKitPropertyTag::Boolean)
                   && Append(data, maximumLength, &flag, sizeof(flag));
        } else if (const auto* number = OSDynamicCast(OSNumber, value)) {
            const auto bits = static_cast<uint8_t>(number->numberOfBits());
            const uint64_t raw = number->unsigned64BitValue();
            fits = AppendTag(data, maximumLength, SwifterKitPropertyTag::Number)
                   && Append(data, maximumLength, &bits, sizeof(bits))
                   && Append(data, maximumLength, &raw, sizeof(raw));
        } else if (const auto* string = OSDynamicCast(OSString, value)) {
            fits = AppendBytes(
                data,
                maximumLength,
                SwifterKitPropertyTag::String,
                string->getCStringNoCopy(),
                string->getLength());
        } else if (const auto* bytes = OSDynamicCast(OSData, value)) {
            fits = AppendBytes(
                data,
                maximumLength,
                SwifterKitPropertyTag::Data,
                bytes->getBytesNoCopy(),
                bytes->getLength());
        } else if (const auto* array = OSDynamicCast(OSArray, value)) {
            const uint32_t count = array->getCount();
            fits = AppendTag(data, maximumLength, SwifterKitPropertyTag::Array)
                   && Append(data, maximumLength, &count, sizeof(count));
            for (uint32_t index = 0; fits && index < count; ++index) {
                const kern_return_t result =
                    EncodeValue(array->getObject(index), data, maximumLength, depth + 1);
                if (result != kIOReturnSuccess) {
                    return result;
                }
            }
        } else if (const auto* dictionary = OSDynamicCast(OSDictionary, value)) {
            const uint32_t count = dictionary->getCount();
            fits = AppendTag(data, maximumLength, SwifterKitPropertyTag::Dictionary)
                   && Append(data, maximumLength, &count, sizeof(count));
            __block kern_return_t result = fits ? kIOReturnSuccess : kIOReturnNoSpace;
            dictionary->iterateObjects(^bool(OSObject* key, OSObject* element) {
              if (result != kIOReturnSuccess) {
                  return true;
              }
              const auto* name = OSDynamicCast(OSString, key);
              const size_t nameLength = name == nullptr ? 0 : name->getLength();
              const auto keyLength = static_cast<uint32_t>(nameLength);
              if (nameLength == 0 || nameLength > maximumLength) {
                  result = nameLength == 0 ? kIOReturnUnsupported : kIOReturnNoSpace;
              } else if (
                  !Append(data, maximumLength, &keyLength, sizeof(keyLength))
                  || !Append(data, maximumLength, name->getCStringNoCopy(), keyLength)) {
                  result = kIOReturnNoSpace;
              } else {
                  result = EncodeValue(element, data, maximumLength, depth + 1);
              }
              return result != kIOReturnSuccess;
            });
            return result;
        } else {
            return kIOReturnUnsupported;
        }
        return fits ? kIOReturnSuccess : kIOReturnNoSpace;
    }
}  // namespace

kern_return_t SwifterKitDecodeProperty(const uint8_t* bytes, uint32_t length, OSObject** value) {
    if (bytes == nullptr || value == nullptr) {
        return kIOReturnBadArgument;
    }
    PropertyReader reader = {.bytes = bytes, .length = length};
    OSObject* decoded = DecodeValue(&reader, 1);
    if (decoded == nullptr || reader.remaining() != 0) {
        OSSafeReleaseNULL(decoded);
        return kIOReturnBadArgument;
    }
    *value = decoded;
    return kIOReturnSuccess;
}

kern_return_t
    SwifterKitEncodeProperty(const OSObject* value, OSData* data, uint32_t maximumLength) {
    if (data == nullptr) {
        return kIOReturnBadArgument;
    }
    return EncodeValue(value, data, maximumLength, 1);
}

bool SwifterKitIsPropertyName(const uint8_t* bytes, uint32_t length) {
    return bytes != nullptr && length != 0 && length <= kSwifterKitPropertyNameMaximumLength
           && !HasNul(bytes, length);
}
