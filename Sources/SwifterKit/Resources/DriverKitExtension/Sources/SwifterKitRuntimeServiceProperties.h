#ifndef SwifterKitRuntimeServiceProperties_h
#define SwifterKitRuntimeServiceProperties_h

#include <DriverKit/OSData.h>
#include <DriverKit/OSObject.h>
#include <DriverKit/OSString.h>

// Decodes exactly one tagged property value (see SwifterKitRuntimeServiceProtocol.h) into a
// retained OSBoolean, OSNumber, OSString, OSData, OSArray, or OSDictionary. Malformed input,
// trailing bytes, duplicate or invalid keys, and excess nesting return kIOReturnBadArgument.
kern_return_t SwifterKitDecodeProperty(const uint8_t* bytes, uint32_t length, OSObject** value);

// Appends the tagged encoding of value to data. The result never grows past maximumLength
// bytes. A larger value returns kIOReturnNoSpace. Other object classes return
// kIOReturnUnsupported.
kern_return_t SwifterKitEncodeProperty(const OSObject* value, OSData* data, uint32_t maximumLength);

// Creates an OSString from length bytes that need no NUL terminator. The two-argument
// OSString::withCString documents a NUL-terminated source, so the bytes are copied and
// terminated first.
OSString* SwifterKitCreateString(const uint8_t* bytes, uint32_t length);

// Returns whether bytes form a registry name: 1...127 bytes without NUL.
bool SwifterKitIsPropertyName(const uint8_t* bytes, uint32_t length);

#endif
