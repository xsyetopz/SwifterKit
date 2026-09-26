#ifndef SwifterKitRuntimeMIDIProperties_h
#define SwifterKitRuntimeMIDIProperties_h

#include <DriverKit/IOReturn.h>
#include <stdint.h>

class OSData;
class OSObject;

// MIDIPropertyValue wire format, all integers little-endian:
//   u32 type, u32 bodyLength, body
//   type 0 string: UTF-8 bytes without NUL
//   type 1 number: u32 bits (8, 16, 32, 64), u32 reserved, u64 value (low `bits` bits)
//   type 2 dictionary: u32 count, u32 reserved, count × (u32 keyLength, u32 reserved, key, value)
//   type 3 data: raw bytes
//   type 4 array: u32 count, u32 reserved, count × value
// Containers nest at most four deep and hold at most 256 entries.

// Decodes exactly one value filling `length` bytes into a new OSObject the caller releases.
kern_return_t SwifterKitDecodeMIDIValue(const uint8_t* bytes, uint32_t length, OSObject** value);

// Appends the encoding of `value` to `data`, failing with kIOReturnNoSpace when the encoding
// would not fit in one runtime response and kIOReturnUnsupported for other OSObject types.
kern_return_t SwifterKitEncodeMIDIValue(OSObject* value, OSData* data);

#endif
