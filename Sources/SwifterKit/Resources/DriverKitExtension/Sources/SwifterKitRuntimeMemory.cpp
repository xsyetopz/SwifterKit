#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeMappedMemory.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_MEMORY

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IODMACommand.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/IOReturn.h>
    #include <DriverKit/IOUserClient.h>
    #include <DriverKit/OSArray.h>
    #include <DriverKit/OSData.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    constexpr uint32_t kMaximumMemoryEntries = 64;

    class MemoryLockGuard {
    public:
        explicit MemoryLockGuard(IOLock* lock) : lock_(lock) {
            if (lock_ != nullptr) {
                IOLockLock(lock_);
            }
        }

        ~MemoryLockGuard() {
            if (lock_ != nullptr) {
                IOLockUnlock(lock_);
            }
        }

        MemoryLockGuard(const MemoryLockGuard&) = delete;
        MemoryLockGuard& operator=(const MemoryLockGuard&) = delete;

    private:
        IOLock* lock_;
    };

    SwifterKitMemoryEntry* FindMemory(SwifterKitRuntimeService_IVars* state, uint64_t handle) {
        if (state == nullptr || handle == 0) {
            return nullptr;
        }
        for (auto& entry : state->memoryEntries) {
            if (entry.handle == handle) {
                return &entry;
            }
        }
        return nullptr;
    }

    // The descriptor an entry describes: its own buffer, or its subrange or chain.
    IOMemoryDescriptor* EntryMemory(const SwifterKitMemoryEntry* entry) {
        if (entry->descriptor != nullptr) {
            return entry->descriptor;
        }
        return entry->composed;
    }

    void ReleaseMemoryEntry(SwifterKitRuntimeService_IVars* state, SwifterKitMemoryEntry* entry) {
        if (state == nullptr || entry == nullptr) {
            return;
        }
        // Only allocated buffers count against the pool's total size.
        const bool wasAllocated = entry->handle != 0 && entry->descriptor != nullptr;
        if (entry->dmaCommand != nullptr) {
            (void)entry->dmaCommand->CompleteDMA(0);
            OSSafeReleaseNULL(entry->dmaCommand);
        }
        OSSafeReleaseNULL(entry->map);
        OSSafeReleaseNULL(entry->descriptor);
        OSSafeReleaseNULL(entry->composed);
        OSSafeReleaseNULL(entry->sources);
        if (wasAllocated) {
            state->allocatedMemory -= entry->capacity;
        }
        *entry = {};
    }

    SwifterKitMemoryEntry* FreeMemoryEntry(SwifterKitRuntimeService_IVars* state) {
        // The configured buffer limit can be below the entry array's extent.
        // NOLINTNEXTLINE(modernize-loop-convert)
        for (uint32_t index = 0; index < kSwifterKitMaximumMemoryBuffers; ++index) {
            if (state->memoryEntries[index].handle == 0) {
                return &state->memoryEntries[index];
            }
        }
        return nullptr;
    }

    // Handles stay within the client-memory identifier field: they count up to
    // kSwifterKitMemoryMaximumHandle, wrap to 1, and skip handles still in use.
    void AssignMemoryHandle(SwifterKitRuntimeService_IVars* state, SwifterKitMemoryEntry* entry) {
        uint64_t handle = state->nextMemoryHandle;
        while (handle == 0 || handle > kSwifterKitMemoryMaximumHandle
               || FindMemory(state, handle) != nullptr) {
            handle = handle == 0 || handle >= kSwifterKitMemoryMaximumHandle ? 1 : handle + 1;
        }
        entry->handle = handle;
        state->nextMemoryHandle = handle + 1;
    }

    bool IsDirection(uint32_t direction) {
        return direction == kIOMemoryDirectionIn || direction == kIOMemoryDirectionOut
               || direction == kIOMemoryDirectionOutIn;
    }

    // A composed descriptor may narrow, never widen, the device access of its sources.
    bool DirectionIsWithin(uint32_t direction, const SwifterKitMemoryEntry* source) {
        return (direction & ~source->direction) == 0;
    }

    bool IsPowerOfTwo(uint64_t value) {
        return value != 0 && (value & (value - 1)) == 0;
    }

    bool RangeIsValid(uint64_t offset, uint64_t length, uint64_t limit) {
        return length != 0 && offset <= limit && length <= limit - offset;
    }

    kern_return_t AppendResponse(OSData** response, const void* bytes, uint32_t length) {
        if (response == nullptr || (length != 0 && bytes == nullptr)) {
            return kIOReturnBadArgument;
        }
        *response = OSData::withBytes(bytes, length);
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }

    // Finishes a subrange or chain whose creation returned `result` into `entry->composed`:
    // retains the sources, maps the result into the extension when DriverKit can, and answers
    // with the new handle. Any failure leaves the entry free.
    kern_return_t FinishComposedEntry(
        SwifterKitRuntimeService_IVars* state,
        SwifterKitMemoryEntry* entry,
        kern_return_t result,
        IOMemoryDescriptor* const* sources,
        uint32_t sourceCount,
        uint64_t length,
        uint32_t direction,
        OSData** response) {
        if (result == kIOReturnSuccess && entry->composed == nullptr) {
            result = kIOReturnNoMemory;
        }
        // Wrapped host memory has no source entries to retain.
        if (result == kIOReturnSuccess && sourceCount != 0) {
            entry->sources = OSArray::withCapacity(sourceCount);
            result = entry->sources == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
        for (uint32_t index = 0; result == kIOReturnSuccess && index < sourceCount; ++index) {
            if (!entry->sources->setObject(sources[index])) {
                result = kIOReturnNoMemory;
            }
        }
        if (result != kIOReturnSuccess) {
            ReleaseMemoryEntry(state, entry);
            return result;
        }
        // Read and write need an extension mapping; DMA and host mapping do not, so an entry
        // DriverKit cannot map here stays usable for them.
        if (entry->composed->CreateMapping(0, 0, 0, length, 0, &entry->map) != kIOReturnSuccess
            || entry->map == nullptr || entry->map->GetAddress() == 0) {
            OSSafeReleaseNULL(entry->map);
        }
        AssignMemoryHandle(state, entry);
        entry->capacity = length;
        entry->length = length;
        entry->direction = direction;
        result = AppendResponse(response, &entry->handle, sizeof(entry->handle));
        if (result != kIOReturnSuccess) {
            ReleaseMemoryEntry(state, entry);
        }
        return result;
    }

    // Opcode MemorySubrange: a new entry for part of an existing entry's valid bytes.
    kern_return_t CreateMemorySubrange(
        SwifterKitRuntimeService_IVars* state,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        if (payloadLength != sizeof(SwifterKitMemorySubrangeHeader)) {
            return kIOReturnBadArgument;
        }
        const auto* header = reinterpret_cast<const SwifterKitMemorySubrangeHeader*>(payload);
        if (header->reserved != 0 || !IsDirection(header->direction)) {
            return kIOReturnBadArgument;
        }
        const SwifterKitMemoryEntry* source = FindMemory(state, header->handle);
        if (source == nullptr) {
            return kIOReturnNotFound;
        }
        if (!RangeIsValid(header->offset, header->length, source->length)
            || !DirectionIsWithin(header->direction, source)) {
            return kIOReturnBadArgument;
        }
        SwifterKitMemoryEntry* entry = FreeMemoryEntry(state);
        if (entry == nullptr) {
            return kIOReturnNoResources;
        }
        IOMemoryDescriptor* const sources[] = {EntryMemory(source)};
        kern_return_t result = kIOReturnUnsupported;
        if (__builtin_available(driverkit 20.0, *)) {
            result = IOMemoryDescriptor::CreateSubMemoryDescriptor(
                header->direction,
                header->offset,
                header->length,
                sources[0],
                &entry->composed);
        }
        return FinishComposedEntry(
            state,
            entry,
            result,
            sources,
            1,
            header->length,
            header->direction,
            response);
    }

    // Opcode MemoryChain: a new entry that concatenates the valid bytes of 1...32 entries.
    kern_return_t CreateMemoryChain(
        SwifterKitRuntimeService_IVars* state,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        // CreateWithMemoryDescriptors takes a fixed array of this many descriptors.
        static_assert(kSwifterKitMemoryMaximumChainLength == 32);
        if (payloadLength < sizeof(SwifterKitMemoryChainHeader)) {
            return kIOReturnBadArgument;
        }
        const auto* header = reinterpret_cast<const SwifterKitMemoryChainHeader*>(payload);
        const uint32_t count = header->count;
        if (count == 0 || count > kSwifterKitMemoryMaximumChainLength
            || !IsDirection(header->direction)
            || payloadLength != sizeof(*header) + count * sizeof(uint64_t)) {
            return kIOReturnBadArgument;
        }
        IOMemoryDescriptor* sources[kSwifterKitMemoryMaximumChainLength] = {};
        uint64_t length = 0;
        for (uint32_t index = 0; index < count; ++index) {
            uint64_t handle = 0;
            memcpy(&handle, payload + sizeof(*header) + index * sizeof(handle), sizeof(handle));
            const SwifterKitMemoryEntry* source = FindMemory(state, handle);
            if (source == nullptr) {
                return kIOReturnNotFound;
            }
            if (!DirectionIsWithin(header->direction, source) || source->length == 0
                || source->length > UINT64_MAX - length) {
                return kIOReturnBadArgument;
            }
            length += source->length;
            sources[index] = EntryMemory(source);
        }
        SwifterKitMemoryEntry* entry = FreeMemoryEntry(state);
        if (entry == nullptr) {
            return kIOReturnNoResources;
        }
        kern_return_t result = kIOReturnUnsupported;
        if (__builtin_available(driverkit 20.0, *)) {
            result = IOMemoryDescriptor::CreateWithMemoryDescriptors(
                header->direction,
                count,
                sources,
                &entry->composed);
        }
        return FinishComposedEntry(
            state,
            entry,
            result,
            sources,
            count,
            length,
            header->direction,
            response);
    }
}  // namespace

// Opcode MemoryWrapClient: a new entry for 1...32 segments of the calling host's own memory,
// described with CreateMemoryDescriptorFromClient while `client`'s ExternalMethod runs. The entry
// takes a buffer slot but none of the byte budget, which counts only buffers the extension
// allocates; its length is fixed. The descriptor references the host's pages, so the host must
// keep them allocated until it releases the entry and everything composed from it.
kern_return_t SwifterKitRuntimeService::WrapClientMemory(
    IOUserClient* client,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    // CreateMemoryDescriptorFromClient takes a fixed array of this many segments.
    static_assert(kSwifterKitMemoryMaximumClientSegments == 32);
    static_assert(sizeof(IOAddressSegment) == kSwifterKitMemoryClientSegmentSize);
    if (ivars == nullptr || ivars->memoryLock == nullptr || client == nullptr || payload == nullptr
        || response == nullptr) {
        return kIOReturnNotReady;
    }
    *response = nullptr;
    if (payloadLength < sizeof(SwifterKitMemoryClientHeader)) {
        return kIOReturnBadArgument;
    }
    SwifterKitMemoryClientHeader header = {};
    memcpy(&header, payload, sizeof(header));
    if (header.count == 0 || header.count > kSwifterKitMemoryMaximumClientSegments
        || !IsDirection(header.direction)
        || payloadLength != sizeof(header) + header.count * sizeof(IOAddressSegment)) {
        return kIOReturnBadArgument;
    }
    IOAddressSegment segments[kSwifterKitMemoryMaximumClientSegments] = {};
    memcpy(segments, payload + sizeof(header), header.count * sizeof(IOAddressSegment));
    uint64_t length = 0;
    for (uint32_t index = 0; index < header.count; ++index) {
        const IOAddressSegment& segment = segments[index];
        if (segment.length == 0 || segment.address > UINT64_MAX - segment.length
            || segment.length > UINT64_MAX - length) {
            return kIOReturnBadArgument;
        }
        length += segment.length;
    }
    const MemoryLockGuard guard(ivars->memoryLock);
    if (ivars->memoryProvider == nullptr) {
        return kIOReturnNotReady;
    }
    SwifterKitMemoryEntry* entry = FreeMemoryEntry(ivars);
    if (entry == nullptr) {
        return kIOReturnNoResources;
    }
    kern_return_t result = kIOReturnUnsupported;
    if (__builtin_available(driverkit 20.0, *)) {
        result = client->CreateMemoryDescriptorFromClient(
            header.direction,
            header.count,
            segments,
            &entry->composed);
    }
    return FinishComposedEntry(
        ivars,
        entry,
        result,
        nullptr,
        0,
        length,
        header.direction,
        response);
}

kern_return_t SwifterKitRuntimeService::CopyMemoryForClient(
    uint64_t handle,
    IOMemoryDescriptor** memory) {
    if (memory == nullptr || ivars == nullptr || ivars->memoryLock == nullptr) {
        return kIOReturnNotReady;
    }
    const MemoryLockGuard guard(ivars->memoryLock);
    if (ivars->memoryProvider == nullptr) {
        return kIOReturnNotReady;
    }
    const SwifterKitMemoryEntry* entry = FindMemory(ivars, handle);
    if (entry == nullptr) {
        return kIOReturnBadArgument;
    }
    // DriverKit consumes this reference; the entry keeps its own.
    IOMemoryDescriptor* descriptor = EntryMemory(entry);
    descriptor->retain();
    *memory = descriptor;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::StartMemory(IOService* provider) {
    if (provider == nullptr || ivars == nullptr || ivars->memoryLock == nullptr) {
        return kIOReturnBadArgument;
    }
    const MemoryLockGuard guard(ivars->memoryLock);
    if (ivars->memoryProvider != nullptr || kSwifterKitMaximumMemoryBuffers == 0
        || kSwifterKitMaximumMemoryBuffers > kMaximumMemoryEntries
        || kSwifterKitMaximumMemoryBufferSize == 0
        || kSwifterKitMaximumMemoryTotalSize < kSwifterKitMaximumMemoryBufferSize) {
        return kIOReturnBadArgument;
    }
    provider->retain();
    ivars->memoryProvider = provider;
    ivars->nextMemoryHandle = 1;
    return kIOReturnSuccess;
}

void SwifterKitRuntimeService::StopMemory() {
    if (ivars == nullptr || ivars->memoryLock == nullptr) {
        return;
    }
    const MemoryLockGuard guard(ivars->memoryLock);
    for (auto& entry : ivars->memoryEntries) {
        ReleaseMemoryEntry(ivars, &entry);
    }
    OSSafeReleaseNULL(ivars->memoryProvider);
    ivars->allocatedMemory = 0;
}

kern_return_t SwifterKitRuntimeService::MemoryCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->memoryLock == nullptr || payload == nullptr
        || response == nullptr) {
        return kIOReturnNotReady;
    }
    const MemoryLockGuard guard(ivars->memoryLock);
    if (ivars->memoryProvider == nullptr) {
        return kIOReturnNotReady;
    }
    *response = nullptr;

    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::MemoryAllocate: {
            if (payloadLength != sizeof(SwifterKitMemoryAllocateHeader)) {
                return kIOReturnBadArgument;
            }
            const auto* header = reinterpret_cast<const SwifterKitMemoryAllocateHeader*>(payload);
            if (header->reserved != 0 || header->capacity == 0
                || header->capacity > kSwifterKitMaximumMemoryBufferSize
                || header->length > header->capacity || !IsDirection(header->direction)
                || header->alignment > UINT32_MAX
                || (header->alignment != 0 && !IsPowerOfTwo(header->alignment))
                || header->capacity > kSwifterKitMaximumMemoryTotalSize - ivars->allocatedMemory) {
                return kIOReturnBadArgument;
            }

            SwifterKitMemoryEntry* entry = FreeMemoryEntry(ivars);
            if (entry == nullptr) {
                return kIOReturnNoResources;
            }

            kern_return_t result = IOBufferMemoryDescriptor::Create(
                header->direction,
                header->capacity,
                header->alignment,
                &entry->descriptor);
            if (result != kIOReturnSuccess || entry->descriptor == nullptr) {
                ReleaseMemoryEntry(ivars, entry);
                return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
            }
            entry->capacity = header->capacity;
            result = entry->descriptor->SetLength(header->capacity);
            if (result == kIOReturnSuccess) {
                result =
                    entry->descriptor->CreateMapping(0, 0, 0, header->capacity, 0, &entry->map);
            }
            if (result == kIOReturnSuccess && entry->map != nullptr
                && entry->map->GetAddress() != 0) {
                result = entry->descriptor->SetLength(header->length);
            } else if (result == kIOReturnSuccess) {
                result = kIOReturnNoMemory;
            }
            if (result != kIOReturnSuccess) {
                ReleaseMemoryEntry(ivars, entry);
                return result;
            }

            AssignMemoryHandle(ivars, entry);
            entry->length = header->length;
            entry->direction = header->direction;
            entry->alignment = static_cast<uint32_t>(header->alignment);
            ivars->allocatedMemory += header->capacity;
            return AppendResponse(response, &entry->handle, sizeof(entry->handle));
        }
        case SwifterKitRuntimeOpcode::MemoryRelease:
        case SwifterKitRuntimeOpcode::MemoryGetInfo:
        case SwifterKitRuntimeOpcode::MemoryCompleteDMA: {
            if (payloadLength != sizeof(uint64_t)) {
                return kIOReturnBadArgument;
            }
            uint64_t handle = 0;
            memcpy(&handle, payload, sizeof(handle));
            SwifterKitMemoryEntry* entry = FindMemory(ivars, handle);
            if (entry == nullptr) {
                return kIOReturnNotFound;
            }
            if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::MemoryRelease)) {
                ReleaseMemoryEntry(ivars, entry);
                return kIOReturnSuccess;
            }
            if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::MemoryCompleteDMA)) {
                if (entry->dmaCommand == nullptr) {
                    return kIOReturnNotReady;
                }
                const kern_return_t result = entry->dmaCommand->CompleteDMA(0);
                if (result == kIOReturnSuccess) {
                    OSSafeReleaseNULL(entry->dmaCommand);
                }
                return result;
            }
            const SwifterKitMemoryInfo info = {
                .handle = entry->handle,
                .capacity = entry->capacity,
                .length = entry->length,
                .direction = entry->direction,
                .alignment = entry->alignment,
            };
            return AppendResponse(response, &info, sizeof(info));
        }
        case SwifterKitRuntimeOpcode::MemorySetLength: {
            if (payloadLength != sizeof(SwifterKitMemorySetLengthHeader)) {
                return kIOReturnBadArgument;
            }
            const auto* header = reinterpret_cast<const SwifterKitMemorySetLengthHeader*>(payload);
            SwifterKitMemoryEntry* entry = FindMemory(ivars, header->handle);
            if (entry == nullptr) {
                return kIOReturnNotFound;
            }
            if (entry->descriptor == nullptr) {
                return kIOReturnUnsupported;
            }
            if (header->length > entry->capacity || entry->dmaCommand != nullptr) {
                return kIOReturnBadArgument;
            }
            const kern_return_t result = entry->descriptor->SetLength(header->length);
            if (result == kIOReturnSuccess) {
                entry->length = header->length;
            }
            return result;
        }
        case SwifterKitRuntimeOpcode::MemoryRead:
        case SwifterKitRuntimeOpcode::MemoryWrite: {
            if (payloadLength < sizeof(SwifterKitMemoryAccessHeader)) {
                return kIOReturnBadArgument;
            }
            const auto* header = reinterpret_cast<const SwifterKitMemoryAccessHeader*>(payload);
            const uint32_t bytesLength = payloadLength - sizeof(*header);
            const bool write =
                opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::MemoryWrite);
            if (header->reserved != 0 || !RangeIsValid(header->offset, header->length, UINT64_MAX)
                || (write && bytesLength != header->length) || (!write && bytesLength != 0)) {
                return kIOReturnBadArgument;
            }
            const SwifterKitMemoryEntry* entry = FindMemory(ivars, header->handle);
            if (entry == nullptr) {
                return kIOReturnNotFound;
            }
            if (!RangeIsValid(header->offset, header->length, entry->length)) {
                return kIOReturnBadArgument;
            }
            // A composed entry the extension could not map is reachable by DMA and the host only.
            if (entry->map == nullptr || entry->map->GetAddress() == 0) {
                return kIOReturnUnsupported;
            }

            auto* address = SwifterKitMappedPointer(entry->map->GetAddress() + header->offset);
            if (write) {
                memcpy(address, payload + sizeof(*header), header->length);
                return kIOReturnSuccess;
            }
            return AppendResponse(response, address, header->length);
        }
        case SwifterKitRuntimeOpcode::MemoryPrepareDMA: {
            if (payloadLength != sizeof(SwifterKitMemoryDMAHeader)) {
                return kIOReturnBadArgument;
            }
            const auto* header = reinterpret_cast<const SwifterKitMemoryDMAHeader*>(payload);
            SwifterKitMemoryEntry* entry = FindMemory(ivars, header->handle);
            if (entry == nullptr) {
                return kIOReturnNotFound;
            }
            const uint64_t length = header->length == 0 && header->offset <= entry->length
                                        ? entry->length - header->offset
                                        : header->length;
            if (header->reserved != 0 || header->maximumAddressBits == 0
                || header->maximumAddressBits > 64
                || !RangeIsValid(header->offset, length, entry->length)
                || entry->dmaCommand != nullptr) {
                return kIOReturnBadArgument;
            }

            IODMACommandSpecification specification = {};
            specification.maxAddressBits = header->maximumAddressBits;
            kern_return_t result =
                IODMACommand::Create(ivars->memoryProvider, 0, &specification, &entry->dmaCommand);
            if (result != kIOReturnSuccess || entry->dmaCommand == nullptr) {
                OSSafeReleaseNULL(entry->dmaCommand);
                return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
            }

            uint64_t flags = 0;
            uint32_t segmentCount = 32;
            IOAddressSegment segments[32] = {};
            result = entry->dmaCommand->PrepareForDMA(
                0,
                EntryMemory(entry),
                header->offset,
                length,
                &flags,
                &segmentCount,
                segments);
            if (result != kIOReturnSuccess || segmentCount > 32) {
                (void)entry->dmaCommand->CompleteDMA(0);
                OSSafeReleaseNULL(entry->dmaCommand);
                return result == kIOReturnSuccess ? kIOReturnError : result;
            }

            const SwifterKitMemoryDMAResponseHeader responseHeader = {
                .flags = flags,
                .segmentCount = segmentCount,
                .reserved = 0,
            };
            *response = OSData::withCapacity(
                sizeof(responseHeader) + segmentCount * sizeof(IOAddressSegment));
            if (*response == nullptr
                || !(*response)->appendBytes(&responseHeader, sizeof(responseHeader))
                || (segmentCount != 0
                    && !(*response)->appendBytes(
                        segments,
                        segmentCount * sizeof(IOAddressSegment)))) {
                OSSafeReleaseNULL(*response);
                (void)entry->dmaCommand->CompleteDMA(0);
                OSSafeReleaseNULL(entry->dmaCommand);
                return kIOReturnNoMemory;
            }
            return kIOReturnSuccess;
        }
        case SwifterKitRuntimeOpcode::MemorySubrange:
            return CreateMemorySubrange(ivars, payload, payloadLength, response);
        case SwifterKitRuntimeOpcode::MemoryChain:
            return CreateMemoryChain(ivars, payload, payloadLength, response);
        default:
            return kIOReturnUnsupported;
    }
}

#endif
