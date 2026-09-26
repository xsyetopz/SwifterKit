#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER

    #include <DriverKit/IOKitKeys.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSBoolean.h>
    #include <DriverKit/OSDictionary.h>
    #include <DriverKit/OSNumber.h>
    #include <string.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
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
        return service->EnqueueRequiredEvent(kSwifterKitEventSCSIManagement, &event, sizeof(event));
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
        *response = result == kIOReturnSuccess
                        ? kSwifterKitSCSITaskManagementResponse
                        : kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE;
        return result;
    }

    void CompleteWithDeliveryFailure(
        SwifterKitRuntimeService* service,
        OSAction* completion,
        const SCSIUserParallelTask& request) {
        SCSIUserParallelResponse response = {};
        response.version = kScsiUserParallelTaskResponseCurrentVersion1;
        response.fTargetID = request.fTargetID;
        response.fControllerTaskIdentifier = request.fControllerTaskIdentifier;
        response.fCompletionStatus = kSCSITaskStatus_No_Status;
        response.fServiceResponse = kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE;
        service->ParallelTaskCompletion(completion, response);
    }

    void ReleaseTaskBuffer(SwifterKitSCSIPendingTask& task) {
        OSSafeReleaseNULL(task.dataMap);
        OSSafeReleaseNULL(task.dataBuffer);
    }

    // IOUserSCSIParallelInterfaceController.iig: every key except the hierarchical-LUN flag is
    // required, and a missing one panics, so the dictionary is reported whole or not at all.
    OSDictionary* CreateConstraints() {
        struct Constraint {
            const char* key;
            uint64_t value;
        };
        const Constraint constraints[] = {
            {kIOMaximumSegmentCountReadKey, kSwifterKitSCSIMaximumSegmentCountRead},
            {kIOMaximumSegmentCountWriteKey, kSwifterKitSCSIMaximumSegmentCountWrite},
            {kIOMaximumSegmentByteCountReadKey, kSwifterKitSCSIMaximumSegmentByteCountRead},
            {kIOMaximumSegmentByteCountWriteKey, kSwifterKitSCSIMaximumSegmentByteCountWrite},
            {kIOMinimumSegmentAlignmentByteCountKey,
             kSwifterKitSCSIMinimumSegmentAlignmentByteCount},
            {kIOMaximumSegmentAddressableBitCountKey,
             kSwifterKitSCSIMaximumSegmentAddressableBitCount},
            {kIOMinimumHBADataAlignmentMaskKey, kSwifterKitSCSIMinimumHBADataAlignmentMask},
        };
        OSDictionary* dictionary = OSDictionary::withCapacity(8);
        bool complete = dictionary != nullptr;
        for (const auto& constraint : constraints) {
            OSNumber* number = complete ? OSNumber::withNumber(constraint.value, 64) : nullptr;
            complete = number != nullptr && dictionary->setObject(constraint.key, number);
            OSSafeReleaseNULL(number);
        }
        if (complete && kSwifterKitSCSISupportsHierarchicalLogicalUnits) {
            complete = dictionary->setObject(kIOHierarchicalLogicalUnitSupportKey, kOSBooleanTrue);
        }
        if (!complete) {
            OSSafeReleaseNULL(dictionary);
        }
        return dictionary;
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
    // The header requires the report before UserInitializeController returns.
    if (!kSwifterKitSCSIReportsConstraints) {
        return kIOReturnSuccess;
    }
    OSDictionary* constraints = CreateConstraints();
    if (constraints == nullptr) {
        return kIOReturnNoMemory;
    }
    const kern_return_t result = UserReportHBAConstraints(constraints);
    constraints->release();
    return result;
}

kern_return_t SwifterKitRuntimeService::UserStartController_Impl() {
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::UserProcessParallelTask_Impl(
    SCSIUserParallelTask request,
    uint32_t* response,
    OSAction* completion) {
    if (ivars == nullptr || ivars->scsiLock == nullptr || response == nullptr
        || completion == nullptr) {
        return kIOReturnBadArgument;
    }
    // The header defines no meaning for an error return, so every task that can be answered is
    // answered through its completion, exactly once: a task this runtime cannot take completes
    // with a delivery failure and reports Request_In_Process, as an enqueue failure does.
    *response = kSCSIServiceResponse_Request_In_Process;
    if (request.version != kScsiUserParallelTaskCurrentVersion1
        || request.fSCSIParallelFeatureRequestCount > kSCSIParallelFeature_TotalFeatureCount
        || request.fCommandSize == 0 || request.fCommandSize > kSCSICDBSize_Maximum) {
        CompleteWithDeliveryFailure(this, completion, request);
        return kIOReturnSuccess;
    }
    // The header allows UserGetDataBuffer only inside UserProcessParallelTask, so the buffer is
    // fetched here; a task whose buffer is unavailable is answered instead of forwarded.
    IOBufferMemoryDescriptor* dataBuffer = nullptr;
    IOMemoryMap* dataMap = nullptr;
    if (kSwifterKitSCSIProvidesTaskDataBuffers && request.fRequestedTransferCount != 0
        && SCSIFetchTaskBuffer(&request, &dataBuffer, &dataMap) != kIOReturnSuccess) {
        CompleteWithDeliveryFailure(this, completion, request);
        return kIOReturnSuccess;
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
        // Every task slot is taken; the completion was not retained or stored.
        IOLockUnlock(ivars->scsiLock);
        OSSafeReleaseNULL(dataMap);
        OSSafeReleaseNULL(dataBuffer);
        CompleteWithDeliveryFailure(this, completion, request);
        return kIOReturnSuccess;
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
    pending->dataBuffer = dataBuffer;
    pending->dataMap = dataMap;
    IOLockUnlock(ivars->scsiLock);

    const kern_return_t result =
        EnqueueRequiredEvent(kSwifterKitEventSCSIParallelTask, &event, sizeof(event));
    if (result != kIOReturnSuccess) {
        bool removed = false;
        SwifterKitSCSIPendingTask task = {};
        IOLockLock(ivars->scsiLock);
        for (auto& candidate : ivars->scsiTasks) {
            if (candidate.completion == completion && candidate.requestID == event.requestID) {
                task = candidate;
                candidate = {};
                removed = true;
                break;
            }
        }
        IOLockUnlock(ivars->scsiLock);
        ReleaseTaskBuffer(task);
        // The task was accepted, so answer it through its completion with a
        // delivery failure, as StopSCSI does. When StopSCSI already took the
        // entry, it has completed the task.
        if (removed) {
            CompleteWithDeliveryFailure(this, completion, request);
            completion->release();
        }
    }
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
    // UserMapBundledParallelTaskCommandAndResponseBuffers declines the shared buffers, so the
    // header says the framework never calls this. If it does, the slots go straight back so no
    // bundled request is left unanswered.
    if (completion == nullptr || requestSlotIndices == nullptr
        || requestSlotCount > kMaxBundledParallelTasks) {
        return;
    }
    BundledParallelTaskCompletion(completion, requestSlotIndices, requestSlotCount);
}

kern_return_t SwifterKitRuntimeService::SCSICommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (opcode != static_cast<uint32_t>(SwifterKitRuntimeOpcode::SCSICompleteParallelTask)) {
        return SCSIControlCommand(opcode, payload, payloadLength, response);
    }
    if (payload == nullptr || payloadLength < sizeof(SwifterKitSCSICompletionHeader)
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

    ReleaseTaskBuffer(task);
    SCSIUserParallelResponse completed = {};
    completed.version = kScsiUserParallelTaskResponseCurrentVersion1;
    completed.fTargetID = task.targetIdentifier;
    completed.fSCSIParallelFeatureRequestResultCount = header->featureResultCount;
    completed.fControllerTaskIdentifier = task.controllerTaskIdentifier;
    completed.fCompletionStatus = static_cast<SCSITaskStatus>(header->taskStatus);
    completed.fServiceResponse = static_cast<SCSIServiceResponse>(header->serviceResponse);
    completed.fBytesTransferred = header->bytesTransferred;
    completed.fSenseLength = static_cast<uint8_t>(header->senseLength);
    for (uint32_t index = 0; index < header->featureResultCount; ++index) {
        completed.fSCSIParallelFeatureResult[index] = header->featureResults[index];
    }
    memcpy(completed.fSenseBuffer, payload + sizeof(*header), header->senseLength);
    ParallelTaskCompletion(task.completion, completed);
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
        ReleaseTaskBuffer(task);
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
