#ifndef SwifterKitRuntimeUserClientHelpers_h
#define SwifterKitRuntimeUserClientHelpers_h

namespace {
    constexpr uint64_t kTransactSelector = 0;

    kern_return_t BuildResponse(
        IOUserClientMethodArguments* arguments,
        SwifterKitRuntimeMessageKind kind,
        uint64_t requestID,
        const void* payload,
        uint32_t payloadLength) {
        const uint32_t responseLength = sizeof(SwifterKitRuntimeHeader) + payloadLength;
        if (responseLength > kSwifterKitRuntimeMaximumMessageSize
            || arguments->structureOutputMaximumSize < responseLength
            || arguments->structureOutputDescriptor != nullptr) {
            return kIOReturnNoSpace;
        }

        const SwifterKitRuntimeHeader header = {
            .magic = kSwifterKitRuntimeMagic,
            .version = kSwifterKitRuntimeVersion,
            .kind = static_cast<uint16_t>(kind),
            .requestID = requestID,
            .payloadLength = payloadLength,
            .flags = 0,
        };
        OSData* output = OSData::withCapacity(responseLength);
        if (output == nullptr) {
            return kIOReturnNoMemory;
        }
        if (!output->appendBytes(&header, sizeof(header))
            || (payloadLength != 0 && !output->appendBytes(payload, payloadLength))) {
            output->release();
            return kIOReturnNoMemory;
        }

        arguments->structureOutput = output;
        return kIOReturnSuccess;
    }

    kern_return_t HandleHandshake(
        IOUserClientMethodArguments* arguments,
        const SwifterKitRuntimeHeader* request) {
        if (request->payloadLength != 0) {
            return kIOReturnBadArgument;
        }
        return BuildResponse(
            arguments,
            SwifterKitRuntimeMessageKind::Response,
            request->requestID,
            &kSwifterKitRuntimeCapabilities,
            sizeof(kSwifterKitRuntimeCapabilities));
    }

    kern_return_t HandlePollEvent(
        SwifterKitRuntimeService* service,
        IOUserClientMethodArguments* arguments,
        uint64_t requestID,
        uint32_t payloadLength) {
        if (payloadLength != 0 || service == nullptr) {
            return kIOReturnBadArgument;
        }

        OSData* event = nullptr;
        kern_return_t result = service->CopyNextEvent(&event);
        if (result != kIOReturnSuccess) {
            return result;
        }
        if (event == nullptr) {
            return BuildResponse(
                arguments,
                SwifterKitRuntimeMessageKind::Response,
                requestID,
                nullptr,
                0);
        }

        result = BuildResponse(
            arguments,
            SwifterKitRuntimeMessageKind::Event,
            requestID,
            event->getBytesNoCopy(),
            static_cast<uint32_t>(event->getLength()));
        event->release();
        return result;
    }

#if SWIFTERKIT_ENABLE_USB || SWIFTERKIT_ENABLE_PCI || SWIFTERKIT_ENABLE_INTERRUPTS     \
    || SWIFTERKIT_ENABLE_MEMORY || SWIFTERKIT_ENABLE_SERIAL || SWIFTERKIT_ENABLE_AUDIO \
    || SWIFTERKIT_ENABLE_SCSI_PERIPHERAL || SWIFTERKIT_ENABLE_VIDEO
    kern_return_t RespondWithData(
        kern_return_t result,
        OSData* data,
        IOUserClientMethodArguments* arguments,
        uint64_t requestID) {
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(data);
            return result;
        }
        if (data == nullptr || data->getLength() > UINT32_MAX) {
            OSSafeReleaseNULL(data);
            return kIOReturnBadArgument;
        }
        result = BuildResponse(
            arguments,
            SwifterKitRuntimeMessageKind::Response,
            requestID,
            data->getBytesNoCopy(),
            static_cast<uint32_t>(data->getLength()));
        data->release();
        return result;
    }

#endif

#if SWIFTERKIT_ENABLE_AUDIO || SWIFTERKIT_ENABLE_VIDEO
    kern_return_t HandleMediaCommand(
        SwifterKitRuntimeService* service,
        IOUserClientMethodArguments* arguments,
        uint64_t requestID,
        uint32_t opcode,
        const uint8_t* payload,
        uint32_t payloadLength) {
        if (service == nullptr) {
            return kIOReturnNotReady;
        }
        OSData* response = nullptr;
    #if SWIFTERKIT_ENABLE_AUDIO
        const kern_return_t result =
            service->AudioCommand(opcode, payload, payloadLength, &response);
    #else
        const kern_return_t result =
            service->VideoCommand(opcode, payload, payloadLength, &response);
    #endif
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(response);
            return result;
        }
        if (response != nullptr) {
            return RespondWithData(result, response, arguments, requestID);
        }
        return BuildResponse(
            arguments,
            SwifterKitRuntimeMessageKind::Response,
            requestID,
            nullptr,
            0);
    }
#endif

#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER || SWIFTERKIT_ENABLE_SCSI_PERIPHERAL
    kern_return_t HandleSCSICommand(
        SwifterKitRuntimeService* service,
        IOUserClientMethodArguments* arguments,
        uint64_t requestID,
        uint32_t opcode,
        const uint8_t* payload,
        uint32_t payloadLength) {
        if (service == nullptr) {
            return kIOReturnNotReady;
        }
    #if SWIFTERKIT_ENABLE_SCSI_PERIPHERAL
        OSData* response = nullptr;
        const kern_return_t result =
            service->SCSIPeripheralCommand(opcode, payload, payloadLength, &response);
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(response);
            return result;
        }
        if (response != nullptr) {
            return RespondWithData(result, response, arguments, requestID);
        }
    #else
        const kern_return_t result = service->SCSICommand(opcode, payload, payloadLength);
        if (result != kIOReturnSuccess) {
            return result;
        }
    #endif
        return BuildResponse(
            arguments,
            SwifterKitRuntimeMessageKind::Response,
            requestID,
            nullptr,
            0);
    }
#endif

#if SWIFTERKIT_ENABLE_INTERRUPTS
    kern_return_t HandleInterruptCommand(
        SwifterKitRuntimeService* service,
        IOUserClientMethodArguments* arguments,
        uint64_t requestID,
        uint32_t opcode,
        const uint8_t* payload,
        uint32_t payloadLength) {
        if (service == nullptr || payloadLength != sizeof(SwifterKitInterruptCommandHeader)) {
            return kIOReturnBadArgument;
        }

        OSData* response = nullptr;
        const auto* header = reinterpret_cast<const SwifterKitInterruptCommandHeader*>(payload);
        const kern_return_t result = service->InterruptCommand(opcode, header, &response);
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(response);
            return result;
        }
        if (response == nullptr) {
            return BuildResponse(
                arguments,
                SwifterKitRuntimeMessageKind::Response,
                requestID,
                nullptr,
                0);
        }
        return RespondWithData(result, response, arguments, requestID);
    }
#endif

#if SWIFTERKIT_ENABLE_USB
    kern_return_t HandleUSBControlTransfer(
        SwifterKitRuntimeService* service,
        IOUserClientMethodArguments* arguments,
        uint64_t requestID,
        const uint8_t* payload,
        uint32_t payloadLength) {
        if (service == nullptr || payloadLength < sizeof(SwifterKitUSBControlTransferHeader)) {
            return kIOReturnBadArgument;
        }
        const auto* header = reinterpret_cast<const SwifterKitUSBControlTransferHeader*>(payload);
        OSData* response = nullptr;
        const uint8_t* bytes = payload + sizeof(*header);
        const uint32_t bytesLength = payloadLength - sizeof(*header);
        return RespondWithData(
            service->USBControlTransfer(header, bytes, bytesLength, &response),
            response,
            arguments,
            requestID);
    }

    kern_return_t HandleUSBPipeTransfer(
        SwifterKitRuntimeService* service,
        IOUserClientMethodArguments* arguments,
        uint64_t requestID,
        const uint8_t* payload,
        uint32_t payloadLength) {
        if (service == nullptr || payloadLength < sizeof(SwifterKitUSBPipeTransferHeader)) {
            return kIOReturnBadArgument;
        }
        const auto* header = reinterpret_cast<const SwifterKitUSBPipeTransferHeader*>(payload);
        OSData* response = nullptr;
        const uint8_t* bytes = payload + sizeof(*header);
        const uint32_t bytesLength = payloadLength - sizeof(*header);
        return RespondWithData(
            service->USBPipeTransfer(header, bytes, bytesLength, &response),
            response,
            arguments,
            requestID);
    }
#endif

}  // namespace

#endif
