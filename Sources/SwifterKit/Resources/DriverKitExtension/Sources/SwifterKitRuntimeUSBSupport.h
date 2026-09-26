#ifndef SwifterKitRuntimeUSBSupport_h
#define SwifterKitRuntimeUSBSupport_h

#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_USB

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <string.h>

    #include "SwifterKitRuntimeServiceState.h"

// The OSAction reference of an asynchronous transfer: its slot and the identifier it was issued.
struct SwifterKitUSBTransferReference {
    uint32_t slot;
    uint32_t requestID;
};

inline void SwifterKitReleaseUSBTransfer(SwifterKitUSBPendingTransfer& transfer) {
    OSSafeReleaseNULL(transfer.frameMap);
    OSSafeReleaseNULL(transfer.frames);
    OSSafeReleaseNULL(transfer.map);
    OSSafeReleaseNULL(transfer.buffer);
    OSSafeReleaseNULL(transfer.pipe);
    OSSafeReleaseNULL(transfer.action);
    transfer = SwifterKitUSBPendingTransfer {};
}

inline bool SwifterKitUSBRequestIDInUse(
    const SwifterKitRuntimeService_IVars* state,
    uint32_t requestID) {
    for (const SwifterKitUSBPendingTransfer& transfer : state->usbTransfers) {
        if (transfer.active && transfer.requestID == requestID) {
            return true;
        }
    }
    return false;
}

// Claims a free slot and a fresh identifier. Call with usbLock held.
inline int32_t SwifterKitReserveUSBTransfer(
    SwifterKitRuntimeService_IVars* state,
    uint32_t* requestID) {
    for (uint32_t slot = 0; slot < kSwifterKitUSBMaximumPendingTransfers; ++slot) {
        if (state->usbTransfers[slot].active) {
            continue;
        }
        do {
            *requestID = state->nextUSBRequestID++;
        } while (*requestID == 0 || SwifterKitUSBRequestIDInUse(state, *requestID));
        state->usbTransfers[slot] = SwifterKitUSBPendingTransfer {};
        state->usbTransfers[slot].active = true;
        state->usbTransfers[slot].requestID = *requestID;
        return static_cast<int32_t>(slot);
    }
    return -1;
}

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

// Queues a required event made of a fixed header and optional trailing bytes.
template<typename Service>
kern_return_t SwifterKitQueueUSBEvent(
    Service* service,
    uint32_t type,
    const void* header,
    uint32_t headerLength,
    const uint8_t* bytes,
    uint32_t length) {
    if (length != 0 && bytes == nullptr) {
        return kIOReturnNoMemory;
    }
    const uint32_t total = headerLength + length;
    auto* event = static_cast<uint8_t*>(IOMallocZero(total));
    if (event == nullptr) {
        return kIOReturnNoMemory;
    }
    memcpy(event, header, headerLength);
    if (length != 0) {
        memcpy(event + headerLength, bytes, length);
    }
    const kern_return_t result = service->EnqueueRequiredEvent(type, event, total);
    IOFree(event, total);
    return result;
}

#endif

#endif
