#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_BLOCK_STORAGE

    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    constexpr uint32_t kBlockStorageEventType = 0x0700;

    enum class BlockStorageRequestKind : uint32_t {
        Eject = 1,
        Synchronize = 2,
        Unmap = 3,
        Read = 4,
        Write = 5,
    };

    struct __attribute__((packed)) SynchronizeRequest {
        SwifterKitBlockStorageRequestHeader header;
        uint64_t startBlock;
        uint64_t blockCount;
    };

    struct __attribute__((packed)) UnmapRequestHeader {
        SwifterKitBlockStorageRequestHeader header;
        uint32_t rangeCount;
        uint32_t reserved;
    };

    static_assert(sizeof(SynchronizeRequest) == 24);
    static_assert(sizeof(UnmapRequestHeader) == 16);

    kern_return_t AddPendingRequest(
        SwifterKitRuntimeService_IVars* state,
        uint32_t requestID,
        bool isIO,
        uint64_t maximumByteCount) {
        if (state == nullptr || state->blockStorageLock == nullptr) {
            return kIOReturnNotReady;
        }
        IOLockLock(state->blockStorageLock);
        SwifterKitBlockStoragePendingRequest* freeEntry = nullptr;
        uint32_t count = 0;
        for (auto& entry : state->blockStorageRequests) {
            if (entry.active) {
                ++count;
                if (entry.requestID == requestID) {
                    IOLockUnlock(state->blockStorageLock);
                    return kIOReturnExclusiveAccess;
                }
            } else if (freeEntry == nullptr) {
                freeEntry = &entry;
            }
        }
        if (freeEntry == nullptr || count >= kSwifterKitBlockMaximumOutstandingIOCount) {
            IOLockUnlock(state->blockStorageLock);
            return kIOReturnNoResources;
        }
        *freeEntry = {
            .requestID = requestID,
            .maximumByteCount = maximumByteCount,
            .isIO = isIO,
            .active = true,
        };
        IOLockUnlock(state->blockStorageLock);
        return kIOReturnSuccess;
    }

    void RemovePendingRequest(SwifterKitRuntimeService_IVars* state, uint32_t requestID) {
        IOLockLock(state->blockStorageLock);
        for (auto& entry : state->blockStorageRequests) {
            if (entry.active && entry.requestID == requestID) {
                entry = {};
                break;
            }
        }
        IOLockUnlock(state->blockStorageLock);
    }

    kern_return_t QueueRequest(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        uint32_t requestID,
        bool isIO,
        uint64_t maximumByteCount,
        const void* event,
        uint32_t eventLength) {
        kern_return_t result = AddPendingRequest(state, requestID, isIO, maximumByteCount);
        if (result != kIOReturnSuccess) {
            return result;
        }
        result = service->EnqueueRequiredEvent(kBlockStorageEventType, event, eventLength);
        if (result != kIOReturnSuccess) {
            RemovePendingRequest(state, requestID);
        }
        return result;
    }

    kern_return_t
        CopyDeviceString(DeviceString* destination, const char* source, size_t sourceLength) {
        if (destination == nullptr || source == nullptr || sourceLength >= kMaxDeviceStringLength) {
            return kIOReturnBadArgument;
        }
        memset(destination->data, 0, sizeof(destination->data));
        memcpy(destination->data, source, sourceLength);
        return kIOReturnSuccess;
    }
}  // namespace

void SwifterKitRuntimeService::StopBlockStorage() {
    if (ivars == nullptr || ivars->blockStorageLock == nullptr) {
        return;
    }
    for (auto& entry : ivars->blockStorageRequests) {
        IOLockLock(ivars->blockStorageLock);
        const auto pending = entry;
        entry = {};
        IOLockUnlock(ivars->blockStorageLock);
        if (!pending.active) {
            continue;
        }
        if (pending.isIO) {
            CompleteIO(pending.requestID, 0, kIOReturnAborted);
        } else {
            Complete(pending.requestID, kIOReturnAborted);
        }
    }
}

kern_return_t SwifterKitRuntimeService::BlockStorageCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength) {
    if (ivars == nullptr || ivars->blockStorageLock == nullptr || payload == nullptr) {
        return kIOReturnNotReady;
    }

    uint32_t requestID = 0;
    int32_t status = 0;
    uint64_t bytesTransferred = 0;
    bool completingIO = false;
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::BlockStorageComplete: {
            if (payloadLength != sizeof(SwifterKitBlockStorageCompletion)) {
                return kIOReturnBadArgument;
            }
            const auto* completion =
                reinterpret_cast<const SwifterKitBlockStorageCompletion*>(payload);
            requestID = completion->requestID;
            status = completion->status;
            break;
        }
        case SwifterKitRuntimeOpcode::BlockStorageCompleteIO: {
            if (payloadLength != sizeof(SwifterKitBlockStorageIOCompletion)) {
                return kIOReturnBadArgument;
            }
            const auto* completion =
                reinterpret_cast<const SwifterKitBlockStorageIOCompletion*>(payload);
            requestID = completion->requestID;
            status = completion->status;
            bytesTransferred = completion->bytesTransferred;
            completingIO = true;
            break;
        }
        default:
            return kIOReturnUnsupported;
    }

    IOLockLock(ivars->blockStorageLock);
    SwifterKitBlockStoragePendingRequest* match = nullptr;
    for (auto& entry : ivars->blockStorageRequests) {
        if (entry.active && entry.requestID == requestID) {
            match = &entry;
            break;
        }
    }
    if (match == nullptr || match->isIO != completingIO
        || (completingIO && bytesTransferred > match->maximumByteCount)) {
        IOLockUnlock(ivars->blockStorageLock);
        return kIOReturnNotFound;
    }
    *match = {};
    IOLockUnlock(ivars->blockStorageLock);

    if (completingIO) {
        CompleteIO(requestID, bytesTransferred, status);
    } else {
        Complete(requestID, status);
    }
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::DoAsyncEjectMedia_Impl(uint32_t requestID) {
    if (!kSwifterKitBlockIsEjectable) {
        return kIOReturnUnsupported;
    }
    const SwifterKitBlockStorageRequestHeader request = {
        .kind = static_cast<uint32_t>(BlockStorageRequestKind::Eject),
        .requestID = requestID,
    };
    return QueueRequest(this, ivars, requestID, false, 0, &request, sizeof(request));
}

kern_return_t SwifterKitRuntimeService::DoAsyncSynchronize_Impl(
    uint32_t requestID,
    uint64_t lba,
    uint64_t blockCount) {
    if (blockCount == 0 || lba >= kSwifterKitBlockCount
        || blockCount > kSwifterKitBlockCount - lba) {
        return kIOReturnBadArgument;
    }
    const SynchronizeRequest request = {
        .header =
            {
                .kind = static_cast<uint32_t>(BlockStorageRequestKind::Synchronize),
                .requestID = requestID,
            },
        .startBlock = lba,
        .blockCount = blockCount,
    };
    return QueueRequest(this, ivars, requestID, false, 0, &request, sizeof(request));
}

kern_return_t SwifterKitRuntimeService::DoAsyncUnmapPriv(
    uint32_t requestID,
    BlockRange* ranges,
    uint32_t rangeCount) {
    if (!kSwifterKitBlockSupportsUnmap || rangeCount == 0
        || rangeCount > kSwifterKitBlockMaximumUnmapRegionCount || ranges == nullptr) {
        return kIOReturnBadArgument;
    }
    for (uint32_t index = 0; index < rangeCount; ++index) {
        if (ranges[index].numOfBlocks == 0 || ranges[index].startBlock >= kSwifterKitBlockCount
            || ranges[index].numOfBlocks > kSwifterKitBlockCount - ranges[index].startBlock) {
            return kIOReturnBadArgument;
        }
    }
    const uint64_t payloadLength =
        sizeof(UnmapRequestHeader) + static_cast<uint64_t>(rangeCount) * sizeof(BlockRange);
    if (payloadLength > kSwifterKitRuntimeMaximumMessageSize - sizeof(uint32_t)) {
        return kIOReturnNoSpace;
    }
    const UnmapRequestHeader header = {
        .header =
            {
                .kind = static_cast<uint32_t>(BlockStorageRequestKind::Unmap),
                .requestID = requestID,
            },
        .rangeCount = rangeCount,
        .reserved = 0,
    };
    OSData* data = OSData::withCapacity(static_cast<uint32_t>(payloadLength));
    if (data == nullptr || !data->appendBytes(&header, sizeof(header))
        || !data->appendBytes(ranges, rangeCount * sizeof(BlockRange))) {
        OSSafeReleaseNULL(data);
        return kIOReturnNoMemory;
    }
    const kern_return_t result = QueueRequest(
        this,
        ivars,
        requestID,
        false,
        0,
        data->getBytesNoCopy(),
        static_cast<uint32_t>(data->getLength()));
    data->release();
    return result;
}

kern_return_t SwifterKitRuntimeService::DoAsyncReadWrite_Impl(
    bool isRead,
    uint32_t requestID,
    uint64_t dmaAddress,
    uint64_t byteCount,
    uint64_t lba,
    uint64_t blockCount,
    IOUserStorageOptions options) {
    if (byteCount == 0 || byteCount > kSwifterKitBlockMaximumIOSize || blockCount == 0
        || lba >= kSwifterKitBlockCount || blockCount > kSwifterKitBlockCount - lba
        || blockCount > UINT64_MAX / kSwifterKitBlockSize
        || byteCount != blockCount * kSwifterKitBlockSize
        || (options & ~kIOUserStorageOptionForceUnitAccess) != 0
        || ((options & kIOUserStorageOptionForceUnitAccess) != 0 && !kSwifterKitBlockSupportsFUA)) {
        return kIOReturnBadArgument;
    }
    const SwifterKitBlockStorageIORequest request = {
        .kind = static_cast<uint32_t>(
            isRead ? BlockStorageRequestKind::Read : BlockStorageRequestKind::Write),
        .requestID = requestID,
        .dmaAddress = dmaAddress,
        .byteCount = byteCount,
        .startBlock = lba,
        .blockCount = blockCount,
        .options = options,
        .reserved = 0,
    };
    return QueueRequest(this, ivars, requestID, true, byteCount, &request, sizeof(request));
}

kern_return_t SwifterKitRuntimeService::GetDeviceParams_Impl(DeviceParams* parameters) {
    if (parameters == nullptr) {
        return kIOReturnBadArgument;
    }
    *parameters = {
        .numOfBlocks = kSwifterKitBlockCount,
        .blockSize = kSwifterKitBlockSize,
        .maxIOSize = kSwifterKitBlockMaximumIOSize,
        .numOfOutstandingIOs = kSwifterKitBlockMaximumOutstandingIOCount,
        .maxNumOfUnmapRegions = kSwifterKitBlockMaximumUnmapRegionCount,
        .minSegmentAlignment = kSwifterKitBlockMinimumSegmentAlignment,
        .numOfAddressBits = kSwifterKitBlockAddressBitCount,
        .isUnmapSupported = kSwifterKitBlockSupportsUnmap,
        .isFUASupported = kSwifterKitBlockSupportsFUA,
    };
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::GetVendorString_Impl(DeviceString* value) {
    return CopyDeviceString(value, kSwifterKitBlockVendor, sizeof(kSwifterKitBlockVendor) - 1);
}

kern_return_t SwifterKitRuntimeService::GetProductString_Impl(DeviceString* value) {
    return CopyDeviceString(value, kSwifterKitBlockProduct, sizeof(kSwifterKitBlockProduct) - 1);
}

kern_return_t SwifterKitRuntimeService::GetRevisionString_Impl(DeviceString* value) {
    return CopyDeviceString(value, kSwifterKitBlockRevision, sizeof(kSwifterKitBlockRevision) - 1);
}

kern_return_t SwifterKitRuntimeService::GetAdditionalInfoString_Impl(DeviceString* value) {
    return CopyDeviceString(
        value,
        kSwifterKitBlockAdditionalInfo,
        sizeof(kSwifterKitBlockAdditionalInfo) - 1);
}

kern_return_t SwifterKitRuntimeService::ReportEjectability_Impl(bool* value) {
    if (value == nullptr) {
        return kIOReturnBadArgument;
    }
    *value = kSwifterKitBlockIsEjectable;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::ReportRemovability_Impl(bool* value) {
    if (value == nullptr) {
        return kIOReturnBadArgument;
    }
    *value = kSwifterKitBlockIsRemovable;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::ReportWriteProtection_Impl(bool* value) {
    if (value == nullptr) {
        return kIOReturnBadArgument;
    }
    *value = kSwifterKitBlockIsWriteProtected;
    return kIOReturnSuccess;
}

#endif
