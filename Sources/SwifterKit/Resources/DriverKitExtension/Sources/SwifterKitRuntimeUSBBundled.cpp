#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_USB

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSAction.h>
    #include <DriverKit/OSData.h>
    #include <USBDriverKit/IOUSBHostInterface.h>
    #include <USBDriverKit/IOUSBHostPipe.h>
    #include <USBDriverKit/USBDriverKitDefs.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeUSBProtocol.h"
    #include "SwifterKitRuntimeUSBSupport.h"

// Bundled bulk I/O contract:
// - usbPipeCreateBundleRing creates one runtime-owned descriptor ring on a bulk pipe: up to
//   kSwifterKitUSBMaximumBundleRingEntries buffers of one length, set with SetMemoryDescriptor
//   from index 0. At most kSwifterKitUSBMaximumBundleRings rings exist at once, one per endpoint.
// - usbPipeEnqueueBundled submits 1...kIOUSBHostPipeBundlingMax consecutive entries, wrapping at
//   the end of the ring. Every entry must be idle; the response is the number of transfers the
//   pipe accepted, and entries it did not accept become idle again.
// - Each entry completes with its own required usbPipeBundledIO event carrying its ring index,
//   status, byte count, and, for IN, its bytes. The kernel's completion bundle boundaries are not
//   preserved. An entry stays unavailable until its event is queued; a full required queue delays
//   delivery, which is retried with the other USB completions.
// - usbPipeReleaseBundleRing releases an idle ring's buffers. USBDriverKit owns the ring itself
//   until the pipe is destroyed, so a pipe accepts CreateMemoryDescriptorRing only as USBDriverKit
//   allows. Stop aborts in-flight entries; they still complete.

namespace {
    struct BundleReference {
        uint32_t ring;
        uint32_t generation;
    };

    void ReleaseRing(SwifterKitUSBBundleRing& ring) {
        for (SwifterKitUSBBundleEntry& entry : ring.entries) {
            OSSafeReleaseNULL(entry.map);
            OSSafeReleaseNULL(entry.buffer);
        }
        OSSafeReleaseNULL(ring.pipe);
        OSSafeReleaseNULL(ring.action);
        ring = SwifterKitUSBBundleRing {};
    }

    // Returns the ready ring for endpoint. The caller holds usbLock.
    SwifterKitUSBBundleRing* FindRing(SwifterKitRuntimeService_IVars* state, uint8_t endpoint) {
        for (SwifterKitUSBBundleRing& ring : state->usbBundleRings) {
            if (ring.ready && ring.endpoint == endpoint) {
                return &ring;
            }
        }
        return nullptr;
    }

    kern_return_t BuildRing(
        SwifterKitRuntimeService* service,
        IOUSBHostInterface* interface,
        const SwifterKitUSBBundleRingRequest& request,
        SwifterKitUSBBundleRing* ring) {
        kern_return_t result = interface->CopyPipe(request.endpoint, &ring->pipe);
        if (result != kIOReturnSuccess || ring->pipe == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNotFound : result;
        }
        IOUSBStandardEndpointDescriptors descriptors = {};
        result = ring->pipe->GetDescriptors(&descriptors, kIOUSBGetEndpointDescriptorOriginal);
        if (result != kIOReturnSuccess) {
            return result;
        }
        // AsyncIOBundled is for bulk pipes only.
        if ((descriptors.descriptor.bmAttributes & 0x03) != kIOUSBEndpointTypeBulk) {
            return kIOReturnBadArgument;
        }
        result =
            service->CreateActionUSBPipeBundledIOComplete(sizeof(BundleReference), &ring->action);
        if (result != kIOReturnSuccess || ring->action == nullptr
            || ring->action->GetReference() == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        result = ring->pipe->CreateMemoryDescriptorRing(request.entryCount);
        const bool input = (request.endpoint & 0x80) != 0;
        for (uint32_t index = 0; result == kIOReturnSuccess && index < request.entryCount;
             ++index) {
            SwifterKitUSBBundleEntry& entry = ring->entries[index];
            result = interface->CreateIOBuffer(
                input ? kIOMemoryDirectionIn : kIOMemoryDirectionOut,
                request.bufferLength,
                &entry.buffer);
            if (result == kIOReturnSuccess && entry.buffer == nullptr) {
                result = kIOReturnNoMemory;
            }
            if (result == kIOReturnSuccess) {
                (void)entry.buffer->SetLength(request.bufferLength);
                result = entry.buffer->CreateMapping(0, 0, 0, request.bufferLength, 0, &entry.map);
            }
            if (result == kIOReturnSuccess
                && (entry.map == nullptr || entry.map->GetAddress() == 0
                    || entry.map->GetLength() < request.bufferLength)) {
                result = kIOReturnNoMemory;
            }
            if (result == kIOReturnSuccess) {
                result = ring->pipe->SetMemoryDescriptor(entry.buffer, index);
            }
        }
        return result;
    }

    kern_return_t CreateRing(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        const uint8_t* payload,
        uint32_t length) {
        SwifterKitUSBBundleRingRequest request = {};
        if (length != sizeof(request)) {
            return kIOReturnBadArgument;
        }
        memcpy(&request, payload, sizeof(request));
        if (request.reserved8 != 0 || request.reserved16 != 0 || request.reserved32 != 0
            || request.entryCount == 0
            || request.entryCount > kSwifterKitUSBMaximumBundleRingEntries
            || request.bufferLength == 0
            || request.bufferLength > kSwifterKitUSBMaximumBundleBufferLength
            || uint64_t {request.entryCount} * request.bufferLength
                   > kSwifterKitUSBMaximumBundleRingBytes) {
            return kIOReturnBadArgument;
        }

        // Reserve the endpoint first so concurrent requests cannot build two rings for it.
        int32_t slot = -1;
        IOLockLock(state->usbLock);
        bool duplicate = false;
        for (uint32_t index = 0; index < kSwifterKitUSBMaximumBundleRings; ++index) {
            SwifterKitUSBBundleRing& ring = state->usbBundleRings[index];
            duplicate = duplicate || (ring.reserved && ring.endpoint == request.endpoint);
            if (!ring.reserved && slot < 0) {
                slot = static_cast<int32_t>(index);
            }
        }
        if (!duplicate && slot >= 0) {
            state->usbBundleRings[slot].reserved = true;
            state->usbBundleRings[slot].endpoint = request.endpoint;
        }
        IOLockUnlock(state->usbLock);
        if (duplicate) {
            return kIOReturnExclusiveAccess;
        }
        if (slot < 0) {
            return kIOReturnNoResources;
        }

        SwifterKitUSBBundleRing ring;
        ring.endpoint = request.endpoint;
        kern_return_t result = BuildRing(service, state->usbInterface, request, &ring);
        IOLockLock(state->usbLock);
        if (result == kIOReturnSuccess) {
            ring.reserved = true;
            ring.ready = true;
            ring.generation = state->nextUSBBundleGeneration++;
            ring.entryCount = request.entryCount;
            ring.bufferLength = request.bufferLength;
            *static_cast<BundleReference*>(ring.action->GetReference()) = {
                .ring = static_cast<uint32_t>(slot),
                .generation = ring.generation,
            };
            state->usbBundleRings[slot] = ring;
            ring = SwifterKitUSBBundleRing {};
        } else {
            state->usbBundleRings[slot] = SwifterKitUSBBundleRing {};
        }
        IOLockUnlock(state->usbLock);
        ReleaseRing(ring);
        return result;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::USBBundleCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->usbLock == nullptr || response == nullptr
        || (payloadLength != 0 && payload == nullptr)) {
        return kIOReturnBadArgument;
    }
    if (ivars->usbInterface == nullptr) {
        return ivars->usbDevice != nullptr ? kIOReturnUnsupported : kIOReturnNotReady;
    }
    const auto code = static_cast<SwifterKitRuntimeOpcode>(opcode);
    if (code == SwifterKitRuntimeOpcode::USBPipeCreateBundleRing) {
        return CreateRing(this, ivars, payload, payloadLength);
    }
    if (code == SwifterKitRuntimeOpcode::USBPipeReleaseBundleRing) {
        SwifterKitUSBPipeRequest request = {};
        if (payloadLength != sizeof(request)) {
            return kIOReturnBadArgument;
        }
        memcpy(&request, payload, sizeof(request));
        if (request.option != 0 || request.reserved != 0 || request.value != 0) {
            return kIOReturnBadArgument;
        }
        SwifterKitUSBBundleRing taken;
        kern_return_t result = kIOReturnNotFound;
        IOLockLock(ivars->usbLock);
        if (SwifterKitUSBBundleRing* ring = FindRing(ivars, request.endpoint)) {
            result = kIOReturnSuccess;
            for (uint32_t index = 0; index < ring->entryCount; ++index) {
                if (ring->entries[index].state != SwifterKitUSBBundleEntryState::Idle) {
                    result = kIOReturnBusy;
                }
            }
            if (result == kIOReturnSuccess) {
                taken = *ring;
                *ring = SwifterKitUSBBundleRing {};
            }
        }
        IOLockUnlock(ivars->usbLock);
        ReleaseRing(taken);
        return result;
    }
    if (code != SwifterKitRuntimeOpcode::USBPipeEnqueueBundled) {
        return kIOReturnUnsupported;
    }

    SwifterKitUSBBundledIOHeader header = {};
    if (payloadLength < sizeof(header)) {
        return kIOReturnBadArgument;
    }
    memcpy(&header, payload, sizeof(header));
    const uint32_t count = header.transferCount;
    if (header.reserved16 != 0 || header.reserved32 != 0 || count == 0
        || count > kSwifterKitUSBMaximumBundledTransfers
        || payloadLength - sizeof(header) < count * sizeof(uint32_t)) {
        return kIOReturnBadArgument;
    }
    const bool input = (header.endpoint & 0x80) != 0;
    uint32_t lengths[kIOUSBHostPipeBundlingMax] = {};
    memcpy(lengths, payload + sizeof(header), count * sizeof(uint32_t));
    const uint8_t* bytes = payload + sizeof(header) + count * sizeof(uint32_t);
    const uint32_t bytesLength = payloadLength - sizeof(header) - count * sizeof(uint32_t);
    uint64_t total = 0;
    for (uint32_t index = 0; index < count; ++index) {
        total += lengths[index];
    }
    if (bytesLength != (input ? 0 : total)) {
        return kIOReturnBadArgument;
    }

    IOUSBHostPipe* pipe = nullptr;
    OSAction* action = nullptr;
    SwifterKitUSBBundleRing* ring = nullptr;
    uint32_t generation = 0;
    kern_return_t result = kIOReturnSuccess;
    IOLockLock(ivars->usbLock);
    ring = FindRing(ivars, header.endpoint);
    if (ring == nullptr) {
        result = kIOReturnNotFound;
    } else if (header.firstIndex >= ring->entryCount || count > ring->entryCount) {
        result = kIOReturnBadArgument;
    }
    for (uint32_t index = 0; result == kIOReturnSuccess && index < count; ++index) {
        const SwifterKitUSBBundleEntry& entry =
            ring->entries[(header.firstIndex + index) % ring->entryCount];
        if (lengths[index] == 0 || lengths[index] > ring->bufferLength) {
            result = kIOReturnBadArgument;
        } else if (entry.state != SwifterKitUSBBundleEntryState::Idle) {
            result = kIOReturnBusy;
        }
    }
    if (result == kIOReturnSuccess) {
        for (uint32_t index = 0; index < count; ++index) {
            SwifterKitUSBBundleEntry& entry =
                ring->entries[(header.firstIndex + index) % ring->entryCount];
            entry.state = SwifterKitUSBBundleEntryState::InFlight;
            if (!input) {
                memcpy(
                    reinterpret_cast<void*>(static_cast<uintptr_t>(entry.map->GetAddress())),
                    bytes,
                    lengths[index]);
                bytes += lengths[index];
            }
        }
        pipe = ring->pipe;
        action = ring->action;
        generation = ring->generation;
        pipe->retain();
        action->retain();
    }
    IOLockUnlock(ivars->usbLock);
    if (result != kIOReturnSuccess) {
        return result;
    }

    uint32_t accepted = 0;
    result = pipe->AsyncIOBundled(
        header.firstIndex,
        count,
        &accepted,
        lengths,
        static_cast<int>(count),
        action,
        header.timeout);
    if (result != kIOReturnSuccess || accepted > count) {
        accepted = result == kIOReturnSuccess ? count : 0;
    }
    // Entries the pipe did not accept never complete, so they become idle here.
    IOLockLock(ivars->usbLock);
    if (ring->ready && ring->generation == generation) {
        for (uint32_t index = accepted; index < count; ++index) {
            SwifterKitUSBBundleEntry& entry =
                ring->entries[(header.firstIndex + index) % ring->entryCount];
            if (entry.state == SwifterKitUSBBundleEntryState::InFlight) {
                entry.state = SwifterKitUSBBundleEntryState::Idle;
            }
        }
    }
    IOLockUnlock(ivars->usbLock);
    pipe->release();
    action->release();
    if (result != kIOReturnSuccess) {
        return result;
    }
    return SwifterKitUSBValueResponse(accepted, response);
}

void SwifterKitRuntimeService::USBPipeBundledIOComplete_Impl(
    OSAction* action,
    uint32_t ioCompletionIndex,
    uint32_t ioCompletionCount,
    const uint32_t* actualByteCountArray,
    int actualByteCountArrayCount,
    const kern_return_t* statusArray,
    int statusArrayCount) {
    if (action == nullptr || ivars == nullptr || ivars->usbLock == nullptr
        || actualByteCountArray == nullptr || statusArray == nullptr || ioCompletionCount == 0
        || ioCompletionCount > kIOUSBHostPipeBundlingMax || actualByteCountArrayCount < 0
        || statusArrayCount < 0
        || static_cast<uint32_t>(actualByteCountArrayCount) < ioCompletionCount
        || static_cast<uint32_t>(statusArrayCount) < ioCompletionCount) {
        return;
    }
    const auto* reference = static_cast<const BundleReference*>(action->GetReference());
    if (reference == nullptr || reference->ring >= kSwifterKitUSBMaximumBundleRings) {
        return;
    }
    IOLockLock(ivars->usbLock);
    SwifterKitUSBBundleRing& ring = ivars->usbBundleRings[reference->ring];
    if (ring.ready && ring.action == action && ring.generation == reference->generation
        && ioCompletionIndex < ring.entryCount && ioCompletionCount <= ring.entryCount) {
        for (uint32_t index = 0; index < ioCompletionCount; ++index) {
            SwifterKitUSBBundleEntry& entry =
                ring.entries[(ioCompletionIndex + index) % ring.entryCount];
            if (entry.state != SwifterKitUSBBundleEntryState::InFlight) {
                continue;
            }
            entry.state = SwifterKitUSBBundleEntryState::Completed;
            entry.sequence = ivars->nextUSBCompletionSequence++;
            entry.status = statusArray[index];
            entry.bytesTransferred = actualByteCountArray[index] > ring.bufferLength
                                         ? ring.bufferLength
                                         : actualByteCountArray[index];
        }
    }
    IOLockUnlock(ivars->usbLock);
    DeliverUSBBundledCompletions();
}

void SwifterKitRuntimeService::DeliverUSBBundledCompletions() {
    if (ivars == nullptr || ivars->usbLock == nullptr) {
        return;
    }
    IOLockLock(ivars->usbLock);
    while (true) {
        SwifterKitUSBBundleRing* oldestRing = nullptr;
        uint32_t oldestIndex = 0;
        for (SwifterKitUSBBundleRing& ring : ivars->usbBundleRings) {
            for (uint32_t index = 0; ring.ready && index < ring.entryCount; ++index) {
                const SwifterKitUSBBundleEntry& entry = ring.entries[index];
                if (entry.state == SwifterKitUSBBundleEntryState::Completed
                    && (oldestRing == nullptr
                        || entry.sequence < oldestRing->entries[oldestIndex].sequence)) {
                    oldestRing = &ring;
                    oldestIndex = index;
                }
            }
        }
        if (oldestRing == nullptr) {
            break;
        }
        SwifterKitUSBBundleEntry& entry = oldestRing->entries[oldestIndex];
        const bool input = (oldestRing->endpoint & 0x80) != 0;
        const SwifterKitUSBBundledIOEvent header = {
            .endpoint = oldestRing->endpoint,
            .reserved8 = 0,
            .reserved16 = 0,
            .index = oldestIndex,
            .status = entry.status,
            .bytesTransferred = entry.bytesTransferred,
        };
        if (SwifterKitQueueUSBEvent(
                this,
                kSwifterKitEventUSBPipeBundledIO,
                &header,
                sizeof(header),
                SwifterKitUSBMappedBytes(entry.map),
                input ? entry.bytesTransferred : 0)
            != kIOReturnSuccess) {
            break;
        }
        entry.state = SwifterKitUSBBundleEntryState::Idle;
    }
    IOLockUnlock(ivars->usbLock);
}

void SwifterKitRuntimeService::ReleaseUSBBundleRings() {
    if (ivars == nullptr || ivars->usbLock == nullptr) {
        return;
    }
    SwifterKitUSBBundleRing taken[kSwifterKitUSBMaximumBundleRings];
    IOLockLock(ivars->usbLock);
    for (uint32_t index = 0; index < kSwifterKitUSBMaximumBundleRings; ++index) {
        taken[index] = ivars->usbBundleRings[index];
        ivars->usbBundleRings[index] = SwifterKitUSBBundleRing {};
    }
    IOLockUnlock(ivars->usbLock);
    for (SwifterKitUSBBundleRing& ring : taken) {
        ReleaseRing(ring);
    }
}

#endif
