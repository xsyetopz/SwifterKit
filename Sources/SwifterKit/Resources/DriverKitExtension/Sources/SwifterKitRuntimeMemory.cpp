#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_MEMORY

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IODMACommand.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/IOReturn.h>
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
        for (uint32_t index = 0; index < kMaximumMemoryEntries; ++index) {
            if (state->memoryEntries[index].handle == handle) {
                return &state->memoryEntries[index];
            }
        }
        return nullptr;
    }

    void ReleaseMemoryEntry(SwifterKitRuntimeService_IVars* state, SwifterKitMemoryEntry* entry) {
        if (state == nullptr || entry == nullptr) {
            return;
        }
        const bool wasAllocated = entry->handle != 0;
        if (entry->dmaCommand != nullptr) {
            (void)entry->dmaCommand->CompleteDMA(0);
            OSSafeReleaseNULL(entry->dmaCommand);
        }
        OSSafeReleaseNULL(entry->map);
        OSSafeReleaseNULL(entry->descriptor);
        if (wasAllocated) {
            state->allocatedMemory -= entry->capacity;
        }
        *entry = {};
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
}  // namespace

kern_return_t SwifterKitRuntimeService::StartMemory(IOService* provider) {
    if (provider == nullptr || ivars == nullptr || ivars->memoryLock == nullptr) {
        return kIOReturnBadArgument;
    }
    MemoryLockGuard guard(ivars->memoryLock);
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
    MemoryLockGuard guard(ivars->memoryLock);
    for (uint32_t index = 0; index < kMaximumMemoryEntries; ++index) {
        ReleaseMemoryEntry(ivars, &ivars->memoryEntries[index]);
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
    MemoryLockGuard guard(ivars->memoryLock);
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
                || header->length > header->capacity
                || (header->direction != kIOMemoryDirectionIn
                    && header->direction != kIOMemoryDirectionOut
                    && header->direction != kIOMemoryDirectionOutIn)
                || header->alignment > UINT32_MAX
                || (header->alignment != 0 && !IsPowerOfTwo(header->alignment))
                || header->capacity > kSwifterKitMaximumMemoryTotalSize - ivars->allocatedMemory) {
                return kIOReturnBadArgument;
            }

            SwifterKitMemoryEntry* entry = nullptr;
            for (uint32_t index = 0; index < kSwifterKitMaximumMemoryBuffers; ++index) {
                if (ivars->memoryEntries[index].handle == 0) {
                    entry = &ivars->memoryEntries[index];
                    break;
                }
            }
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

            entry->handle = ivars->nextMemoryHandle++;
            if (entry->handle == 0) {
                entry->handle = ivars->nextMemoryHandle++;
            }
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
            SwifterKitMemoryEntry* entry = FindMemory(ivars, header->handle);
            if (entry == nullptr) {
                return kIOReturnNotFound;
            }
            if (!RangeIsValid(header->offset, header->length, entry->length)
                || entry->map == nullptr || entry->map->GetAddress() == 0) {
                return kIOReturnBadArgument;
            }

            auto* address = reinterpret_cast<uint8_t*>(
                static_cast<uintptr_t>(entry->map->GetAddress() + header->offset));
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
                entry->descriptor,
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
        default:
            return kIOReturnUnsupported;
    }
}

#endif
