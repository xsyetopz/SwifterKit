#ifndef SwifterKitRuntimeMappedMemory_h
#define SwifterKitRuntimeMappedMemory_h

#include <DriverKit/IOMemoryDescriptor.h>
#include <stdint.h>

// Returns the allocation direction for a buffer the extension fills through its own mapping.
//
// DriverKit describes kIOMemoryDirectionOut memory as readable only (IOMemoryDescriptor.h), so an
// output buffer the runtime writes is allocated InOut. Callers keep the requested direction for
// their own checks.
inline uint64_t SwifterKitWritableDirection(uint64_t direction) {
    return direction == kIOMemoryDirectionOut ? kIOMemoryDirectionInOut : direction;
}

// Returns a pointer to mapped memory at `address`.
//
// DriverKit reports a mapping only as an integer (IOMemoryMap::GetAddress, IOAddressSegment), so
// every access to mapped bytes has to convert that integer to a pointer. Keeping the one conversion
// here leaves performance-no-int-to-ptr active for the rest of the runtime.
template<typename Byte = uint8_t>
inline Byte* SwifterKitMappedPointer(uint64_t address) {
    // NOLINTNEXTLINE(performance-no-int-to-ptr): DriverKit has no pointer-typed mapping accessor.
    return reinterpret_cast<Byte*>(static_cast<uintptr_t>(address));
}

#endif
