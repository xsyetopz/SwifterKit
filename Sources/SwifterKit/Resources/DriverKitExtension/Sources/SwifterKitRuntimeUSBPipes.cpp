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

// Asynchronous pipe transfer contract:
// - AsyncIO and IsochIO submissions take one of kSwifterKitUSBMaximumPendingTransfers slots and
//   return a nonzero request identifier. A full table fails the submission with
//   kIOReturnNoResources. Identifiers are unique among outstanding requests.
// - The completion event is a required event and can reach Swift before the submission's
//   response does, so Swift correlates completions by request identifier.
// - A slot owns its pipe, buffers, and action until its completion event is queued. When the
//   required queue rejects the event, the slot keeps the stored result and delivery is retried
//   on every later USB command and completion, oldest completion first.
// - Stop aborts outstanding requests asynchronously; each still completes with its status.

namespace {
    constexpr uint32_t kFrameSize = sizeof(SwifterKitUSBIsochFrame);
    constexpr uint32_t kIsochEventSize = sizeof(SwifterKitUSBIsochIOEvent);
    constexpr uint32_t kIOEventSize = sizeof(SwifterKitUSBPipeIOEvent);
    constexpr uint32_t kCountSize = sizeof(uint32_t);

    static_assert(sizeof(IOUSBEndpointDescriptor) == 7);
    static_assert(sizeof(IOUSBSuperSpeedEndpointCompanionDescriptor) == 6);
    static_assert(sizeof(IOUSBSuperSpeedPlusIsochronousEndpointCompanionDescriptor) == 8);
    static_assert(sizeof(IOUSBIsochronousFrame) == sizeof(SwifterKitUSBIsochFrame));

    // One pending transfer's resources before it owns a slot.
    struct PreparedTransfer {
        IOUSBHostPipe* pipe = nullptr;
        IOBufferMemoryDescriptor* buffer = nullptr;
        IOMemoryMap* map = nullptr;
        IOBufferMemoryDescriptor* frames = nullptr;
        IOMemoryMap* frameMap = nullptr;
        OSAction* action = nullptr;

        ~PreparedTransfer() {
            OSSafeReleaseNULL(frameMap);
            OSSafeReleaseNULL(frames);
            OSSafeReleaseNULL(map);
            OSSafeReleaseNULL(buffer);
            OSSafeReleaseNULL(pipe);
            OSSafeReleaseNULL(action);
        }

        void moveInto(SwifterKitUSBPendingTransfer& transfer) {
            transfer.pipe = pipe;
            transfer.buffer = buffer;
            transfer.map = map;
            transfer.frames = frames;
            transfer.frameMap = frameMap;
            transfer.action = action;
            pipe = nullptr;
            buffer = nullptr;
            map = nullptr;
            frames = nullptr;
            frameMap = nullptr;
            action = nullptr;
        }
    };

    // Builds and queues the completion event of a completed slot. Call with usbLock held.
    kern_return_t QueueCompletion(
        SwifterKitRuntimeService* service,
        const SwifterKitUSBPendingTransfer& transfer) {
        const bool input = (transfer.endpoint & 0x80) != 0;
        const uint8_t* data = SwifterKitUSBMappedBytes(transfer.map);
        uint32_t length = 0;
        if (transfer.deviceRequest) {
            const SwifterKitUSBDeviceRequestEvent header = {
                .requestID = transfer.requestID,
                .status = transfer.status,
                .bytesTransferred = transfer.bytesTransferred,
                .requestType = transfer.endpoint,
                .reserved = {0, 0, 0},
            };
            return SwifterKitQueueUSBEvent(
                service,
                kSwifterKitEventUSBDeviceRequest,
                &header,
                sizeof(header),
                data,
                input ? transfer.bytesTransferred : 0);
        }
        if (transfer.isochronous) {
            const uint8_t* frames = SwifterKitUSBMappedBytes(transfer.frameMap);
            if (frames == nullptr || (input && data == nullptr)) {
                return kIOReturnNoMemory;
            }
            const uint32_t framesLength = transfer.frameCount * kFrameSize;
            const uint32_t dataLength = input ? transfer.length : 0;
            length = kIsochEventSize + framesLength + dataLength;
            auto* event = static_cast<uint8_t*>(IOMallocZero(length));
            if (event == nullptr) {
                return kIOReturnNoMemory;
            }
            const SwifterKitUSBIsochIOEvent header = {
                .requestID = transfer.requestID,
                .status = transfer.status,
                .endpoint = transfer.endpoint,
                .reserved = 0,
                .frameCount = static_cast<uint16_t>(transfer.frameCount),
                .dataLength = dataLength,
            };
            memcpy(event, &header, sizeof(header));
            uint8_t* cursor = event + sizeof(header);
            for (uint32_t index = 0; index < transfer.frameCount; ++index) {
                SwifterKitUSBIsochFrame frame = {};
                memcpy(&frame, frames + index * sizeof(frame), sizeof(frame));
                if (frame.completeCount > frame.requestCount) {
                    frame.completeCount = frame.requestCount;
                }
                frame.reserved = 0;
                memcpy(cursor, &frame, sizeof(frame));
                cursor += sizeof(frame);
            }
            if (dataLength != 0) {
                memcpy(cursor, data, dataLength);
            }
            const kern_return_t result =
                service->EnqueueRequiredEvent(kSwifterKitEventUSBPipeIsochIO, event, length);
            IOFree(event, length);
            return result;
        }

        const uint32_t dataLength = input ? transfer.bytesTransferred : 0;
        if (dataLength != 0 && data == nullptr) {
            return kIOReturnNoMemory;
        }
        length = kIOEventSize + dataLength;
        auto* event = static_cast<uint8_t*>(IOMallocZero(length));
        if (event == nullptr) {
            return kIOReturnNoMemory;
        }
        const SwifterKitUSBPipeIOEvent header = {
            .requestID = transfer.requestID,
            .status = transfer.status,
            .bytesTransferred = transfer.bytesTransferred,
            .endpoint = transfer.endpoint,
            .reserved = {0, 0, 0},
            .timestamp = transfer.timestamp,
        };
        memcpy(event, &header, sizeof(header));
        if (dataLength != 0) {
            memcpy(event + sizeof(header), data, dataLength);
        }
        const kern_return_t result =
            service->EnqueueRequiredEvent(kSwifterKitEventUSBPipeIO, event, length);
        IOFree(event, length);
        return result;
    }

    kern_return_t CreateFrameList(
        IOUSBHostInterface* interface,
        const uint8_t* counts,
        uint32_t frameCount,
        PreparedTransfer* transfer) {
        const uint32_t length = frameCount * kFrameSize;
        kern_return_t result =
            interface->CreateIOBuffer(kIOMemoryDirectionInOut, length, &transfer->frames);
        if (result != kIOReturnSuccess || transfer->frames == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        (void)transfer->frames->SetLength(length);
        result = transfer->frames->CreateMapping(0, 0, 0, length, 0, &transfer->frameMap);
        if (result != kIOReturnSuccess || transfer->frameMap == nullptr
            || transfer->frameMap->GetAddress() == 0 || transfer->frameMap->GetLength() < length) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        auto* frames =
            reinterpret_cast<uint8_t*>(static_cast<uintptr_t>(transfer->frameMap->GetAddress()));
        for (uint32_t index = 0; index < frameCount; ++index) {
            SwifterKitUSBIsochFrame frame = {};
            memcpy(&frame.requestCount, counts + index * sizeof(uint32_t), sizeof(uint32_t));
            memcpy(frames + index * sizeof(frame), &frame, sizeof(frame));
        }
        return kIOReturnSuccess;
    }

    kern_return_t PipeDescriptors(IOUSBHostPipe* pipe, uint8_t option, OSData** response) {
        IOUSBStandardEndpointDescriptors descriptors = {};
        const kern_return_t result = pipe->GetDescriptors(
            &descriptors,
            option == kSwifterKitUSBPipeDescriptorsCurrentPolicy
                ? kIOUSBGetEndpointDescriptorCurrentPolicy
                : kIOUSBGetEndpointDescriptorOriginal);
        if (result != kIOReturnSuccess) {
            return result;
        }
        SwifterKitUSBPipeDescriptors value = {};
        value.bcdUSB = descriptors.bcdUSB;
        memcpy(value.endpoint, &descriptors.descriptor, sizeof(value.endpoint));
        memcpy(
            value.superSpeedCompanion,
            &descriptors.ssCompanionDescriptor,
            sizeof(value.superSpeedCompanion));
        memcpy(
            value.superSpeedPlusIsochronousCompanion,
            &descriptors.sspCompanionDescriptor,
            sizeof(value.superSpeedPlusIsochronousCompanion));
        return SwifterKitUSBDataResponse(&value, sizeof(value), response);
    }

    kern_return_t PipeRequest(
        IOUSBHostInterface* interface,
        uint32_t opcode,
        const SwifterKitUSBPipeRequest* request,
        OSData** response) {
        const auto code = static_cast<SwifterKitRuntimeOpcode>(opcode);
        const bool takesOption = code == SwifterKitRuntimeOpcode::USBPipeGetDescriptors;
        const bool takesValue = code == SwifterKitRuntimeOpcode::USBPipeSetIdlePolicy;
        if (request->reserved != 0 || (!takesOption && request->option != 0)
            || request->option > kSwifterKitUSBPipeDescriptorsCurrentPolicy
            || (!takesValue && request->value != 0)) {
            return kIOReturnBadArgument;
        }

        IOUSBHostPipe* pipe = nullptr;
        kern_return_t result = interface->CopyPipe(request->endpoint, &pipe);
        if (result != kIOReturnSuccess || pipe == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNotFound : result;
        }
        uint32_t value = 0;
        uint8_t byte = 0;
        switch (code) {
            case SwifterKitRuntimeOpcode::USBPipeAbort:
                // Asynchronous only: aborted requests report kIOReturnAborted in their events.
                result = pipe->Abort(kIOUSBAbortAsynchronous, kIOReturnAborted, nullptr);
                break;
            case SwifterKitRuntimeOpcode::USBPipeSetIdlePolicy:
                result = pipe->SetIdlePolicy(request->value);
                break;
            case SwifterKitRuntimeOpcode::USBPipeGetIdlePolicy:
                result = pipe->GetIdlePolicy(&value);
                result = result == kIOReturnSuccess ? SwifterKitUSBValueResponse(value, response)
                                                    : result;
                break;
            case SwifterKitRuntimeOpcode::USBPipeGetDescriptors:
                result = PipeDescriptors(pipe, request->option, response);
                break;
            case SwifterKitRuntimeOpcode::USBPipeGetSpeed:
                result = pipe->GetSpeed(&byte);
                result = result == kIOReturnSuccess ? SwifterKitUSBValueResponse(byte, response)
                                                    : result;
                break;
            case SwifterKitRuntimeOpcode::USBPipeGetDeviceAddress:
                result = pipe->GetDeviceAddress(&byte);
                result = result == kIOReturnSuccess ? SwifterKitUSBValueResponse(byte, response)
                                                    : result;
                break;
            default:
                result = kIOReturnUnsupported;
                break;
        }
        pipe->release();
        return result;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::USBPipeCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->usbLock == nullptr || response == nullptr) {
        return kIOReturnBadArgument;
    }
    IOUSBHostInterface* const interface = ivars->usbInterface;
    if (interface == nullptr) {
        return ivars->usbDevice != nullptr ? kIOReturnUnsupported : kIOReturnNotReady;
    }

    const auto code = static_cast<SwifterKitRuntimeOpcode>(opcode);
    if (code != SwifterKitRuntimeOpcode::USBPipeAsyncIO
        && code != SwifterKitRuntimeOpcode::USBPipeIsochIO) {
        if (payloadLength != sizeof(SwifterKitUSBPipeRequest)) {
            return kIOReturnBadArgument;
        }
        return PipeRequest(
            interface,
            opcode,
            reinterpret_cast<const SwifterKitUSBPipeRequest*>(payload),
            response);
    }

    PreparedTransfer prepared;
    uint8_t endpoint = 0;
    uint32_t length = 0;
    uint32_t frameCount = 0;
    uint32_t timeout = 0;
    uint64_t firstFrame = 0;
    kern_return_t result = kIOReturnBadArgument;
    if (code == SwifterKitRuntimeOpcode::USBPipeAsyncIO) {
        const auto* header = reinterpret_cast<const SwifterKitUSBAsyncIOHeader*>(payload);
        if (payloadLength < sizeof(*header) || header->reserved8 != 0 || header->reserved16 != 0
            || header->reserved32 != 0 || header->length == 0) {
            return kIOReturnBadArgument;
        }
        const bool input = (header->endpoint & 0x80) != 0;
        const uint32_t bytesLength = payloadLength - sizeof(*header);
        const bool valid =
            input ? bytesLength == 0 && header->length <= kSwifterKitUSBMaximumAsyncInputLength
                  : bytesLength == header->length
                        && header->length <= kSwifterKitUSBMaximumAsyncOutputLength;
        if (!valid) {
            return kIOReturnBadArgument;
        }
        endpoint = header->endpoint;
        length = header->length;
        timeout = header->timeout;
        result = SwifterKitCreateUSBBuffer(
            interface,
            input,
            length,
            payload + sizeof(*header),
            &prepared.buffer,
            &prepared.map);
        if (result == kIOReturnSuccess) {
            result = CreateActionUSBPipeIOComplete(
                sizeof(SwifterKitUSBTransferReference),
                &prepared.action);
        }
    } else {
        const auto* header = reinterpret_cast<const SwifterKitUSBIsochIOHeader*>(payload);
        if (payloadLength < sizeof(*header) || header->reserved8 != 0 || header->reserved32 != 0
            || header->frameCount == 0
            || header->frameCount > kSwifterKitUSBMaximumIsochronousFrames
            || payloadLength - sizeof(*header) < header->frameCount * sizeof(uint32_t)) {
            return kIOReturnBadArgument;
        }
        const bool input = (header->endpoint & 0x80) != 0;
        const uint8_t* counts = payload + sizeof(*header);
        uint64_t total = 0;
        for (uint32_t index = 0; index < header->frameCount; ++index) {
            uint32_t count = 0;
            memcpy(&count, counts + index * sizeof(count), sizeof(count));
            total += count;
        }
        const uint32_t countsLength = header->frameCount * kCountSize;
        const uint32_t bytesLength = payloadLength - sizeof(*header) - countsLength;
        const uint64_t eventLength =
            sizeof(SwifterKitUSBIsochIOEvent)
            + uint64_t {header->frameCount} * sizeof(SwifterKitUSBIsochFrame) + (input ? total : 0);
        if (total == 0 || eventLength > kSwifterKitUSBMaximumEventPayload
            || bytesLength != (input ? 0 : total)) {
            return kIOReturnBadArgument;
        }
        endpoint = header->endpoint;
        length = static_cast<uint32_t>(total);
        frameCount = header->frameCount;
        firstFrame = header->firstFrameNumber;
        result = SwifterKitCreateUSBBuffer(
            interface,
            input,
            length,
            counts + countsLength,
            &prepared.buffer,
            &prepared.map);
        if (result == kIOReturnSuccess) {
            result = CreateFrameList(interface, counts, frameCount, &prepared);
        }
        if (result == kIOReturnSuccess) {
            result = CreateActionUSBPipeIsochIOComplete(
                sizeof(SwifterKitUSBTransferReference),
                &prepared.action);
        }
    }
    if (result == kIOReturnSuccess && prepared.action == nullptr) {
        result = kIOReturnNoMemory;
    }
    if (result == kIOReturnSuccess) {
        result = interface->CopyPipe(endpoint, &prepared.pipe);
        result =
            result == kIOReturnSuccess && prepared.pipe == nullptr ? kIOReturnNotFound : result;
    }
    auto* reference =
        prepared.action == nullptr
            ? nullptr
            : static_cast<SwifterKitUSBTransferReference*>(prepared.action->GetReference());
    if (result == kIOReturnSuccess && reference == nullptr) {
        result = kIOReturnNoMemory;
    }
    if (result != kIOReturnSuccess) {
        return result;
    }

    // The submission keeps its own references: the completion can release the slot's references
    // before the submitting call returns.
    PreparedTransfer submission;
    submission.pipe = prepared.pipe;
    submission.buffer = prepared.buffer;
    submission.frames = prepared.frames;
    submission.action = prepared.action;
    submission.pipe->retain();
    submission.buffer->retain();
    if (submission.frames != nullptr) {
        submission.frames->retain();
    }
    submission.action->retain();
    uint32_t requestID = 0;
    IOLockLock(ivars->usbLock);
    const int32_t slot = SwifterKitReserveUSBTransfer(ivars, &requestID);
    if (slot >= 0) {
        SwifterKitUSBPendingTransfer& transfer = ivars->usbTransfers[slot];
        transfer.endpoint = endpoint;
        transfer.isochronous = code == SwifterKitRuntimeOpcode::USBPipeIsochIO;
        transfer.length = length;
        transfer.frameCount = frameCount;
        prepared.moveInto(transfer);
        *reference = {.slot = static_cast<uint32_t>(slot), .requestID = requestID};
    }
    IOLockUnlock(ivars->usbLock);
    if (slot < 0) {
        return kIOReturnNoResources;
    }

    result = submission.frames == nullptr
                 ? submission.pipe->AsyncIO(submission.buffer, length, submission.action, timeout)
                 : submission.pipe->IsochIO(
                       submission.buffer,
                       submission.frames,
                       firstFrame,
                       submission.action);
    if (result != kIOReturnSuccess) {
        // No completion follows a failed submission, so the slot is released here.
        IOLockLock(ivars->usbLock);
        SwifterKitReleaseUSBTransfer(ivars->usbTransfers[slot]);
        IOLockUnlock(ivars->usbLock);
        return result;
    }
    return SwifterKitUSBValueResponse(requestID, response);
}

void SwifterKitRuntimeService::USBPipeIOComplete_Impl(
    OSAction* action,
    IOReturn status,
    uint32_t actualByteCount,
    uint64_t completionTimestamp) {
    if (action == nullptr || ivars == nullptr || ivars->usbLock == nullptr) {
        return;
    }
    const auto* reference =
        static_cast<const SwifterKitUSBTransferReference*>(action->GetReference());
    if (reference == nullptr || reference->slot >= kSwifterKitUSBMaximumPendingTransfers) {
        return;
    }
    IOLockLock(ivars->usbLock);
    SwifterKitUSBPendingTransfer& transfer = ivars->usbTransfers[reference->slot];
    if (transfer.active && !transfer.completed && !transfer.isochronous && transfer.action == action
        && transfer.requestID == reference->requestID) {
        transfer.completed = true;
        transfer.sequence = ivars->nextUSBCompletionSequence++;
        transfer.status = status;
        transfer.bytesTransferred =
            actualByteCount > transfer.length ? transfer.length : actualByteCount;
        transfer.timestamp = completionTimestamp;
    }
    IOLockUnlock(ivars->usbLock);
    DeliverUSBCompletions();
}

void SwifterKitRuntimeService::USBPipeIsochIOComplete_Impl(OSAction* action, IOReturn status) {
    if (action == nullptr || ivars == nullptr || ivars->usbLock == nullptr) {
        return;
    }
    const auto* reference =
        static_cast<const SwifterKitUSBTransferReference*>(action->GetReference());
    if (reference == nullptr || reference->slot >= kSwifterKitUSBMaximumPendingTransfers) {
        return;
    }
    IOLockLock(ivars->usbLock);
    SwifterKitUSBPendingTransfer& transfer = ivars->usbTransfers[reference->slot];
    if (transfer.active && !transfer.completed && transfer.isochronous && transfer.action == action
        && transfer.requestID == reference->requestID) {
        transfer.completed = true;
        transfer.sequence = ivars->nextUSBCompletionSequence++;
        transfer.status = status;
    }
    IOLockUnlock(ivars->usbLock);
    DeliverUSBCompletions();
}

void SwifterKitRuntimeService::DeliverUSBCompletions() {
    if (ivars == nullptr || ivars->usbLock == nullptr) {
        return;
    }
    IOLockLock(ivars->usbLock);
    while (true) {
        SwifterKitUSBPendingTransfer* oldest = nullptr;
        for (SwifterKitUSBPendingTransfer& transfer : ivars->usbTransfers) {
            if (transfer.active && transfer.completed
                && (oldest == nullptr || transfer.sequence < oldest->sequence)) {
                oldest = &transfer;
            }
        }
        if (oldest == nullptr || QueueCompletion(this, *oldest) != kIOReturnSuccess) {
            break;
        }
        SwifterKitReleaseUSBTransfer(*oldest);
    }
    IOLockUnlock(ivars->usbLock);
    DeliverUSBBundledCompletions();
}

void SwifterKitRuntimeService::ReleaseUSBTransfers() {
    if (ivars == nullptr || ivars->usbLock == nullptr) {
        return;
    }
    IOLockLock(ivars->usbLock);
    for (SwifterKitUSBPendingTransfer& transfer : ivars->usbTransfers) {
        SwifterKitReleaseUSBTransfer(transfer);
    }
    IOLockUnlock(ivars->usbLock);
    ReleaseUSBBundleRings();
}

#endif
