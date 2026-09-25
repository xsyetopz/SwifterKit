#ifndef SwifterKitRuntimeUSBSupport_h
#define SwifterKitRuntimeUSBSupport_h

#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_USB

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <string.h>

// Allocates a controller-optimized buffer from an IOUSBHostInterface or IOUSBHostDevice, maps
// it, and zeroes or fills it. The caller releases both objects on success or failure.
template<typename Provider>
kern_return_t SwifterKitCreateUSBBuffer(
    Provider* provider,
    bool input,
    uint32_t length,
    const uint8_t* bytes,
    IOBufferMemoryDescriptor** descriptor,
    IOMemoryMap** map) {
    if (provider == nullptr || length == 0 || descriptor == nullptr || map == nullptr
        || (!input && bytes == nullptr)) {
        return kIOReturnBadArgument;
    }
    kern_return_t result = provider->CreateIOBuffer(
        input ? kIOMemoryDirectionIn : kIOMemoryDirectionOut,
        length,
        descriptor);
    if (result != kIOReturnSuccess || *descriptor == nullptr) {
        return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
    }
    (void)(*descriptor)->SetLength(length);
    result = (*descriptor)->CreateMapping(0, 0, 0, length, 0, map);
    if (result != kIOReturnSuccess || *map == nullptr || (*map)->GetAddress() == 0
        || (*map)->GetLength() < length) {
        return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
    }
    auto* address = reinterpret_cast<uint8_t*>(static_cast<uintptr_t>((*map)->GetAddress()));
    if (input) {
        memset(address, 0, length);
    } else {
        memcpy(address, bytes, length);
    }
    return kIOReturnSuccess;
}

inline const uint8_t* SwifterKitUSBMappedBytes(IOMemoryMap* map) {
    if (map == nullptr || map->GetAddress() == 0) {
        return nullptr;
    }
    return reinterpret_cast<const uint8_t*>(static_cast<uintptr_t>(map->GetAddress()));
}

// Creates a response holding `length` bytes, or fails without a partial response.
inline kern_return_t
    SwifterKitUSBDataResponse(const void* bytes, uint32_t length, OSData** response) {
    if (response == nullptr || (length != 0 && bytes == nullptr)) {
        return kIOReturnBadArgument;
    }
    *response = OSData::withBytes(bytes, length);
    return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
}

inline kern_return_t SwifterKitUSBValueResponse(uint32_t value, OSData** response) {
    return SwifterKitUSBDataResponse(&value, sizeof(value), response);
}

#endif

#endif
