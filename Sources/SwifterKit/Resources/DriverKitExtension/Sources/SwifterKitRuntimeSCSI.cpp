#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER

    #include <DriverKit/IOLib.h>
    #include <string.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    constexpr uint32_t kSCSIParallelTaskEvent = 0x0B00;
    constexpr uint32_t kSCSIManagementEvent = 0x0B01;
    constexpr uint32_t kSCSIInitializeTarget = 1;
    constexpr uint32_t kSCSIAbortTask = 2;
    constexpr uint32_t kSCSIAbortTaskSet = 3;
    constexpr uint32_t kSCSIClearACA = 4;
    constexpr uint32_t kSCSIClearTaskSet = 5;
    constexpr uint32_t kSCSILogicalUnitReset = 6;
    constexpr uint32_t kSCSITargetReset = 7;

    kern_return_t EnqueueManagement(
        SwifterKitRuntimeService* service,
        uint32_t kind,
        uint64_t target,
        uint64_t logicalUnit,
        uint64_t taskTag) {
        if (service == nullptr) {
            return kIOReturnNotReady;
        }
        const SwifterKitSCSIManagementEvent event = {
            .kind = kind,
            .reserved = 0,
            .targetIdentifier = target,
            .logicalUnit = logicalUnit,
            .taskTag = taskTag,
        };
        return service->EnqueueRequiredEvent(kSCSIManagementEvent, &event, sizeof(event));
    }

    kern_return_t ForwardManagement(
        SwifterKitRuntimeService* service,
        uint32_t kind,
        uint64_t target,
        uint64_t logicalUnit,
        uint64_t taskTag,
        uint32_t* response) {
        if (response == nullptr) {
            return kIOReturnBadArgument;
        }
        const kern_return_t result = EnqueueManagement(service, kind, target, logicalUnit, taskTag);
        if (result == kIOReturnSuccess) {
            *response = kSwifterKitSCSITaskManagementResponse;
        }
        return result;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::UserReportHBAHighestLogicalUnitNumber_Impl(
    uint64_t* value) {
    if (value == nullptr) {
        return kIOReturnBadArgument;
    }
    *value = kSwifterKitSCSIHighestLogicalUnitNumber;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserDoesHBASupportSCSIParallelFeature_Impl(
    uint32_t feature,
    bool* result) {
    if (result == nullptr || feature >= kSCSIParallelFeature_TotalFeatureCount) {
        return kIOReturnBadArgument;
    }
    *result = (kSwifterKitSCSISupportedFeatures & (1U << feature)) != 0;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserInitializeTargetForID_Impl(
    SCSITargetIdentifier targetID) {
    return EnqueueManagement(this, kSCSIInitializeTarget, targetID, 0, 0);
}

kern_return_t SwifterKitRuntimeService::UserDoesHBAPerformAutoSense_Impl(bool* result) {
    if (result == nullptr) {
        return kIOReturnBadArgument;
    }
    *result = kSwifterKitSCSIPerformsAutoSense;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserDoesHBASupportMultiPathing_Impl(bool* result) {
    if (result == nullptr) {
        return kIOReturnBadArgument;
    }
    *result = kSwifterKitSCSISupportsMultipathing;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserAbortTaskRequest_Impl(
    uint64_t target,
    uint64_t logicalUnit,
    uint64_t taskTag,
    uint32_t* response) {
    return ForwardManagement(this, kSCSIAbortTask, target, logicalUnit, taskTag, response);
}

kern_return_t SwifterKitRuntimeService::UserAbortTaskSetRequest_Impl(
    uint64_t target,
    uint64_t logicalUnit,
    uint32_t* response) {
    return ForwardManagement(this, kSCSIAbortTaskSet, target, logicalUnit, 0, response);
}

kern_return_t SwifterKitRuntimeService::UserClearACARequest_Impl(
    uint64_t target,
    uint64_t logicalUnit,
    uint32_t* response) {
    return ForwardManagement(this, kSCSIClearACA, target, logicalUnit, 0, response);
}

kern_return_t SwifterKitRuntimeService::UserClearTaskSetRequest_Impl(
    uint64_t target,
    uint64_t logicalUnit,
    uint32_t* response) {
    return ForwardManagement(this, kSCSIClearTaskSet, target, logicalUnit, 0, response);
}

kern_return_t SwifterKitRuntimeService::UserLogicalUnitResetRequest_Impl(
    uint64_t target,
    uint64_t logicalUnit,
    uint32_t* response) {
    return ForwardManagement(this, kSCSILogicalUnitReset, target, logicalUnit, 0, response);
}

kern_return_t SwifterKitRuntimeService::UserTargetResetRequest_Impl(
    uint64_t target,
    uint32_t* response) {
    return ForwardManagement(this, kSCSITargetReset, target, 0, 0, response);
}

kern_return_t SwifterKitRuntimeService::UserReportInitiatorIdentifier_Impl(uint64_t* identifier) {
    if (identifier == nullptr) {
        return kIOReturnBadArgument;
    }
    *identifier = kSwifterKitSCSIInitiatorIdentifier;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserReportHighestSupportedDeviceID_Impl(
    uint64_t* identifier) {
    if (identifier == nullptr) {
        return kIOReturnBadArgument;
    }
    *identifier = kSwifterKitSCSIHighestTargetIdentifier;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserReportMaximumTaskCount_Impl(uint32_t* count) {
    if (count == nullptr) {
        return kIOReturnBadArgument;
    }
    *count = kSwifterKitSCSIMaximumTaskCount;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserDoesHBAPerformDeviceManagement_Impl(bool* result) {
    if (result == nullptr) {
        return kIOReturnBadArgument;
    }
    *result = false;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserInitializeController_Impl() {
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserStartController_Impl() {
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserProcessParallelTask_Impl(
    SCSIUserParallelTask request,
    uint32_t* response,
    OSAction* completion) {
    if (ivars == nullptr || ivars->scsiLock == nullptr || response == nullptr
        || completion == nullptr || request.version != kScsiUserParallelTaskCurrentVersion1
        || request.fSCSIParallelFeatureRequestCount > kSCSIParallelFeature_TotalFeatureCount
        || request.fCommandSize == 0 || request.fCommandSize > kSCSICDBSize_Maximum) {
        return kIOReturnBadArgument;
    }

    SwifterKitSCSIParallelTaskEvent event = {};
    event.featureRequestCount = static_cast<uint32_t>(request.fSCSIParallelFeatureRequestCount);
    event.targetIdentifier = request.fTargetID;
    event.controllerTaskIdentifier = request.fControllerTaskIdentifier;
    event.requestedTransferCount = request.fRequestedTransferCount;
    event.bufferIOVMAddress = request.fBufferIOVMAddr;
    event.taskTagIdentifier = request.fTaskTagIdentifier;
    event.timeoutMilliseconds = request.fTimeoutInMilliSec;
    event.taskAttribute = static_cast<uint8_t>(request.fTaskAttribute);
    event.transferDirection = request.fTransferDirection;
    event.commandSize = request.fCommandSize;
    memcpy(event.logicalUnitBytes, request.fLogicalUnitBytes, sizeof(event.logicalUnitBytes));
    memcpy(
        event.commandDescriptorBlock,
        request.fCommandDescriptorBlock,
        sizeof(event.commandDescriptorBlock));
    for (uint32_t index = 0; index < event.featureRequestCount; ++index) {
        event.featureRequests[index] = request.fSCSIParallelFeatureRequest[index];
    }

    IOLockLock(ivars->scsiLock);
    SwifterKitSCSIPendingTask* pending = nullptr;
    for (auto& candidate : ivars->scsiTasks) {
        if (candidate.completion == nullptr) {
            pending = &candidate;
            break;
        }
    }
    if (pending == nullptr) {
        IOLockUnlock(ivars->scsiLock);
        return kIOReturnNoSpace;
    }
    event.requestID = ivars->nextSCSIRequestID++;
    if (ivars->nextSCSIRequestID == 0) {
        ivars->nextSCSIRequestID = 1;
    }
    completion->retain();
    pending->requestID = event.requestID;
    pending->targetIdentifier = request.fTargetID;
    pending->controllerTaskIdentifier = request.fControllerTaskIdentifier;
    pending->requestedTransferCount = request.fRequestedTransferCount;
    pending->featureRequestCount = event.featureRequestCount;
    pending->completion = completion;
    IOLockUnlock(ivars->scsiLock);

    const kern_return_t result =
        EnqueueRequiredEvent(kSCSIParallelTaskEvent, &event, sizeof(event));
    if (result != kIOReturnSuccess) {
        bool removed = false;
        IOLockLock(ivars->scsiLock);
        for (auto& candidate : ivars->scsiTasks) {
            if (candidate.completion == completion && candidate.requestID == event.requestID) {
                candidate = {};
                removed = true;
                break;
            }
        }
        IOLockUnlock(ivars->scsiLock);
        if (removed) {
            completion->release();
        }
        return result;
    }
    *response = kSCSIServiceResponse_Request_In_Process;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserGetDMASpecification_Impl(
    uint64_t* maximumTransferSize,
    uint32_t* alignment,
    uint8_t* addressBitCount,
    DMAOutputSegmentType* segmentType) {
    if (maximumTransferSize == nullptr || alignment == nullptr || addressBitCount == nullptr
        || segmentType == nullptr) {
        return kIOReturnBadArgument;
    }
    *maximumTransferSize = kSwifterKitSCSIMaximumTransferSize;
    *alignment = kSwifterKitSCSIMinimumSegmentAlignment;
    *addressBitCount = kSwifterKitSCSIAddressBitCount;
    *segmentType = static_cast<DMAOutputSegmentType>(kSwifterKitSCSIDMASegmentType);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserMapHBAData_Impl(uint32_t* uniqueTaskID) {
    if (uniqueTaskID == nullptr || ivars == nullptr || ivars->scsiLock == nullptr) {
        return kIOReturnBadArgument;
    }
    IOLockLock(ivars->scsiLock);
    *uniqueTaskID = ivars->nextSCSITaskMapID++;
    if (ivars->nextSCSITaskMapID == 0) {
        ivars->nextSCSITaskMapID = 1;
    }
    IOLockUnlock(ivars->scsiLock);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserMapBundledParallelTaskCommandAndResponseBuffers_Impl(
    IOBufferMemoryDescriptor* commandBuffer,
    IOBufferMemoryDescriptor* responseBuffer) {
    (void)commandBuffer;
    (void)responseBuffer;
    return kIOReturnError;
}

void SwifterKitRuntimeService::UserProcessBundledParallelTasks_Impl(
    const uint16_t requestSlotIndices[kMaxBundledParallelTasks],
    uint16_t requestSlotCount,
    OSAction* completion) {
    (void)requestSlotIndices;
    (void)requestSlotCount;
    (void)completion;
}

kern_return_t SwifterKitRuntimeService::SCSICommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength) {
    if (opcode != static_cast<uint32_t>(SwifterKitRuntimeOpcode::SCSICompleteParallelTask)
        || payload == nullptr || payloadLength < sizeof(SwifterKitSCSICompletionHeader)
        || ivars == nullptr || ivars->scsiLock == nullptr) {
        return kIOReturnBadArgument;
    }
    const auto* header = reinterpret_cast<const SwifterKitSCSICompletionHeader*>(payload);
    if (header->requestID == 0
        || header->featureResultCount > kSCSIParallelFeature_TotalFeatureCount
        || header->taskStatus > UINT8_MAX
        || header->serviceResponse > kSCSIServiceResponse_FUNCTION_REJECTED
        || header->senseLength > kMaxSenseBufferSize
        || payloadLength != sizeof(*header) + header->senseLength) {
        return kIOReturnBadArgument;
    }

    SwifterKitSCSIPendingTask task = {};
    IOLockLock(ivars->scsiLock);
    for (auto& candidate : ivars->scsiTasks) {
        if (candidate.completion != nullptr && candidate.requestID == header->requestID) {
            if (header->bytesTransferred > candidate.requestedTransferCount
                || header->featureResultCount != candidate.featureRequestCount) {
                IOLockUnlock(ivars->scsiLock);
                return kIOReturnBadArgument;
            }
            task = candidate;
            candidate = {};
            break;
        }
    }
    IOLockUnlock(ivars->scsiLock);
    if (task.completion == nullptr) {
        return kIOReturnNotFound;
    }

    SCSIUserParallelResponse response = {};
    response.version = kScsiUserParallelTaskResponseCurrentVersion1;
    response.fTargetID = task.targetIdentifier;
    response.fSCSIParallelFeatureRequestResultCount = header->featureResultCount;
    response.fControllerTaskIdentifier = task.controllerTaskIdentifier;
    response.fCompletionStatus = static_cast<SCSITaskStatus>(header->taskStatus);
    response.fServiceResponse = static_cast<SCSIServiceResponse>(header->serviceResponse);
    response.fBytesTransferred = header->bytesTransferred;
    response.fSenseLength = static_cast<uint8_t>(header->senseLength);
    for (uint32_t index = 0; index < header->featureResultCount; ++index) {
        response.fSCSIParallelFeatureResult[index] = header->featureResults[index];
    }
    memcpy(response.fSenseBuffer, payload + sizeof(*header), header->senseLength);
    ParallelTaskCompletion(task.completion, response);
    task.completion->release();
    return kIOReturnSuccess;
}

void SwifterKitRuntimeService::StopSCSI() {
    if (ivars == nullptr || ivars->scsiLock == nullptr) {
        return;
    }
    for (auto& candidate : ivars->scsiTasks) {
        IOLockLock(ivars->scsiLock);
        SwifterKitSCSIPendingTask task = candidate;
        candidate = {};
        IOLockUnlock(ivars->scsiLock);
        if (task.completion == nullptr) {
            continue;
        }
        SCSIUserParallelResponse response = {};
        response.version = kScsiUserParallelTaskResponseCurrentVersion1;
        response.fTargetID = task.targetIdentifier;
        response.fControllerTaskIdentifier = task.controllerTaskIdentifier;
        response.fCompletionStatus = kSCSITaskStatus_No_Status;
        response.fServiceResponse = kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE;
        ParallelTaskCompletion(task.completion, response);
        task.completion->release();
    }
}

#endif
