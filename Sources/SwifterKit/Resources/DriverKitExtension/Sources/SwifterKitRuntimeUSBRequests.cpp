#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_USB

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSAction.h>
    #include <DriverKit/OSData.h>
    #include <USBDriverKit/IOUSBHostDevice.h>
    #include <USBDriverKit/IOUSBHostInterface.h>
    #include <USBDriverKit/IOUSBHostPipe.h>
    #include <USBDriverKit/USBDriverKitDefs.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeUSBProtocol.h"
    #include "SwifterKitRuntimeUSBSupport.h"

// Asynchronous control requests and endpoint-policy changes.
//
// usbAsyncDeviceRequest follows the AsyncIO contract in SwifterKitRuntimeUSBPipes.cpp:
// - The request takes a pending-transfer slot and returns a nonzero identifier.
// - Its completion is a required usbDeviceRequest event correlated by that identifier.
// - The event can reach Swift before the submission's response.
// A slot keeps its buffer and action until the event is queued, so a full required queue delays
// delivery rather than losing it. Stop aborts outstanding requests through AbortDeviceRequests.
// Each still completes, with kIOReturnAborted.
//
// usbPipeAdjust changes the bandwidth policy of a periodic endpoint. The endpoint address and
// transfer type must match the pipe's original descriptor.

namespace {

    struct PreparedRequest {
        IOBufferMemoryDescriptor* buffer = nullptr;
        IOMemoryMap* map = nullptr;
        OSAction* action = nullptr;

        ~PreparedRequest() {
            OSSafeReleaseNULL(map);
            OSSafeReleaseNULL(buffer);
            OSSafeReleaseNULL(action);
        }
    };

    bool IsZero(const uint8_t* bytes, uint32_t length) {
        for (uint32_t index = 0; index < length; ++index) {
            if (bytes[index] != 0) {
                return false;
            }
        }
        return true;
    }

    bool SupportedRelease(uint16_t release) {
        for (const uint16_t supported : kSwifterKitUSBSupportedReleases) {
            if (supported == release) {
                return true;
            }
        }
        return false;
    }

    kern_return_t
        AdjustPipe(IOUSBHostInterface* interface, const uint8_t* payload, uint32_t length) {
        SwifterKitUSBAdjustPipeRequest request = {};
        if (length != sizeof(request)) {
            return kIOReturnBadArgument;
        }
        memcpy(&request, payload, sizeof(request));
        const SwifterKitUSBPipeDescriptors& value = request.descriptors;
        const uint8_t* companion = value.superSpeedCompanion;
        const uint8_t* plus = value.superSpeedPlusIsochronousCompanion;
        if (request.reserved[0] != 0 || request.reserved[1] != 0 || request.reserved[2] != 0
            || request.reserved8 != 0 || !SupportedRelease(value.bcdUSB) || value.endpoint[0] != 7
            || value.endpoint[1] != 0x05 || value.endpoint[2] != request.endpoint
            || !(IsZero(companion, 6) || (companion[0] == 6 && companion[1] == 0x30))
            || !(
                IsZero(plus, 8)
                || (plus[0] == 8 && plus[1] == 0x31 && plus[2] == 0 && plus[3] == 0))) {
            return kIOReturnBadArgument;
        }

        IOUSBHostPipe* pipe = nullptr;
        kern_return_t result = interface->CopyPipe(request.endpoint, &pipe);
        if (result != kIOReturnSuccess || pipe == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNotFound : result;
        }
        IOUSBStandardEndpointDescriptors original = {};
        result = pipe->GetDescriptors(&original, kIOUSBGetEndpointDescriptorOriginal);
        const uint8_t type = original.descriptor.bmAttributes & 0x03U;
        if (result == kIOReturnSuccess
            && (original.descriptor.bEndpointAddress != request.endpoint
                || (type != kIOUSBEndpointTypeIsochronous && type != kIOUSBEndpointTypeInterrupt)
                || (value.endpoint[3] & 0x03U) != type)) {
            result = kIOReturnBadArgument;
        }
        if (result == kIOReturnSuccess) {
            IOUSBStandardEndpointDescriptors adjusted = {};
            adjusted.bcdUSB = value.bcdUSB;
            memcpy(&adjusted.descriptor, value.endpoint, sizeof(value.endpoint));
            memcpy(&adjusted.ssCompanionDescriptor, companion, sizeof(value.superSpeedCompanion));
            memcpy(
                &adjusted.sspCompanionDescriptor,
                plus,
                sizeof(value.superSpeedPlusIsochronousCompanion));
            result = pipe->AdjustPipe(&adjusted);
        }
        pipe->release();
        return result;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::USBAsyncCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->usbLock == nullptr || response == nullptr
        || (payloadLength != 0 && payload == nullptr)) {
        return kIOReturnBadArgument;
    }
    IOUSBHostDevice* const device = ivars->usbDevice;
    IOUSBHostInterface* const interface = ivars->usbInterface;
    const auto code = static_cast<SwifterKitRuntimeOpcode>(opcode);
    switch (code) {
        case SwifterKitRuntimeOpcode::USBAsyncDeviceRequest:
            break;
        case SwifterKitRuntimeOpcode::USBPipeAdjust:
            if (interface == nullptr) {
                return device != nullptr ? kIOReturnUnsupported : kIOReturnNotReady;
            }
            return AdjustPipe(interface, payload, payloadLength);
        case SwifterKitRuntimeOpcode::USBPipeCreateBundleRing:
        case SwifterKitRuntimeOpcode::USBPipeEnqueueBundled:
        case SwifterKitRuntimeOpcode::USBPipeReleaseBundleRing:
            return USBBundleCommand(opcode, payload, payloadLength, response);
        default:
            return kIOReturnUnsupported;
    }

    SwifterKitUSBControlTransferHeader header = {};
    if (payloadLength < sizeof(header)) {
        return kIOReturnBadArgument;
    }
    memcpy(&header, payload, sizeof(header));
    const bool input = (header.requestType & 0x80U) != 0;
    const uint32_t bytesLength = payloadLength - sizeof(header);
    if (header.reserved != 0
        || (input ? bytesLength != 0 || header.length > kSwifterKitUSBMaximumAsyncRequestInputLength
                  : bytesLength != header.length)) {
        return kIOReturnBadArgument;
    }

    PreparedRequest prepared;
    kern_return_t result = kIOReturnSuccess;
    if (header.length != 0) {
        result = interface != nullptr ? SwifterKitCreateUSBBuffer(
                                            interface,
                                            input,
                                            header.length,
                                            payload + sizeof(header),
                                            &prepared.buffer,
                                            &prepared.map)
                                      : SwifterKitCreateUSBBuffer(
                                            device,
                                            input,
                                            header.length,
                                            payload + sizeof(header),
                                            &prepared.buffer,
                                            &prepared.map);
    }
    if (result == kIOReturnSuccess) {
        result = CreateActionUSBDeviceRequestComplete(
            sizeof(SwifterKitUSBTransferReference),
            &prepared.action);
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
    OSAction* action = prepared.action;
    IOBufferMemoryDescriptor* buffer = prepared.buffer;
    action->retain();
    if (buffer != nullptr) {
        buffer->retain();
    }
    uint32_t requestID = 0;
    IOLockLock(ivars->usbLock);
    const int32_t slot = SwifterKitReserveUSBTransfer(ivars, &requestID);
    if (slot >= 0) {
        SwifterKitUSBPendingTransfer& transfer = ivars->usbTransfers[slot];
        transfer.endpoint = header.requestType;
        transfer.deviceRequest = true;
        transfer.length = header.length;
        transfer.buffer = prepared.buffer;
        transfer.map = prepared.map;
        transfer.action = prepared.action;
        prepared.buffer = nullptr;
        prepared.map = nullptr;
        prepared.action = nullptr;
        *reference = {.slot = static_cast<uint32_t>(slot), .requestID = requestID};
    }
    IOLockUnlock(ivars->usbLock);
    if (slot < 0) {
        action->release();
        OSSafeReleaseNULL(buffer);
        return kIOReturnNoResources;
    }

    if (interface != nullptr) {
        result = interface->AsyncDeviceRequest(
            header.requestType,
            header.request,
            header.value,
            header.index,
            header.length,
            buffer,
            action,
            header.timeout);
    } else {
        result = device->AsyncDeviceRequest(
            this,
            header.requestType,
            header.request,
            header.value,
            header.index,
            header.length,
            buffer,
            action,
            header.timeout);
    }
    action->release();
    OSSafeReleaseNULL(buffer);
    if (result != kIOReturnSuccess) {
        // No completion follows a failed submission, so the slot is released here.
        IOLockLock(ivars->usbLock);
        SwifterKitReleaseUSBTransfer(ivars->usbTransfers[slot]);
        IOLockUnlock(ivars->usbLock);
        return result;
    }
    return SwifterKitUSBValueResponse(requestID, response);
}

void SwifterKitRuntimeService::USBDeviceRequestComplete_Impl(
    OSAction* action,
    IOReturn status,
    uint32_t bytesTransferred) {
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
    if (transfer.active && !transfer.completed && transfer.deviceRequest
        && transfer.action == action && transfer.requestID == reference->requestID) {
        transfer.completed = true;
        transfer.sequence = ivars->nextUSBCompletionSequence++;
        transfer.status = status;
        transfer.bytesTransferred =
            bytesTransferred > transfer.length ? transfer.length : bytesTransferred;
    }
    IOLockUnlock(ivars->usbLock);
    DeliverUSBCompletions();
}

void SwifterKitRuntimeService::AbortUSBAsyncRequests() {
    if (ivars == nullptr || ivars->usbLock == nullptr) {
        return;
    }
    bool requests = false;
    IOUSBHostPipe* pipes[kSwifterKitUSBMaximumBundleRings] = {};
    IOLockLock(ivars->usbLock);
    for (const SwifterKitUSBPendingTransfer& transfer : ivars->usbTransfers) {
        requests = requests || (transfer.active && !transfer.completed && transfer.deviceRequest);
    }
    for (uint32_t index = 0; index < kSwifterKitUSBMaximumBundleRings; ++index) {
        const SwifterKitUSBBundleRing& ring = ivars->usbBundleRings[index];
        if (!ring.ready) {
            continue;
        }
        for (uint32_t entry = 0; entry < ring.entryCount; ++entry) {
            if (ring.entries[entry].state == SwifterKitUSBBundleEntryState::InFlight) {
                pipes[index] = ring.pipe;
                pipes[index]->retain();
                break;
            }
        }
    }
    IOLockUnlock(ivars->usbLock);
    // Asynchronous only: Stop runs on the queue that delivers the completions.
    for (IOUSBHostPipe*& pipe : pipes) {
        if (pipe != nullptr) {
            (void)pipe->Abort(kIOUSBAbortAsynchronous, kIOReturnAborted, nullptr);
            OSSafeReleaseNULL(pipe);
        }
    }
    if (requests && ivars->usbInterface != nullptr) {
        (void)ivars->usbInterface->AbortDeviceRequests(kIOUSBAbortAsynchronous, kIOReturnAborted);
    } else if (requests && ivars->usbDevice != nullptr) {
        (void)
            ivars->usbDevice->AbortDeviceRequests(this, kIOUSBAbortAsynchronous, kIOReturnAborted);
    }
}

#endif
