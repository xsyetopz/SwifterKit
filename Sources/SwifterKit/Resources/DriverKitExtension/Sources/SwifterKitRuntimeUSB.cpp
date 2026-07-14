#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_USB

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <USBDriverKit/IOUSBHostPipe.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    constexpr uint32_t kTransferCountSize = sizeof(uint32_t);

    struct TransferBuffer {
        IOBufferMemoryDescriptor* descriptor = nullptr;
        IOMemoryMap* map = nullptr;

        ~TransferBuffer() {
            OSSafeReleaseNULL(map);
            OSSafeReleaseNULL(descriptor);
        }

        kern_return_t prepare(
            IOUSBHostInterface* interface,
            bool input,
            uint32_t length,
            const uint8_t* bytes) {
            if (length == 0) {
                return kIOReturnSuccess;
            }
            if (interface == nullptr || (!input && bytes == nullptr)) {
                return kIOReturnBadArgument;
            }

            kern_return_t result = interface->CreateIOBuffer(
                input ? kIOMemoryDirectionIn : kIOMemoryDirectionOut,
                length,
                &descriptor);
            if (result != kIOReturnSuccess || descriptor == nullptr) {
                return result;
            }
            (void)descriptor->SetLength(length);
            result = descriptor->CreateMapping(0, 0, 0, length, 0, &map);
            if (result != kIOReturnSuccess || map == nullptr || map->GetAddress() == 0) {
                return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
            }
            if (!input) {
                memcpy(
                    reinterpret_cast<void*>(static_cast<uintptr_t>(map->GetAddress())),
                    bytes,
                    length);
            }
            return kIOReturnSuccess;
        }

        const void* bytes() const {
            if (map == nullptr || map->GetAddress() == 0) {
                return nullptr;
            }
            return reinterpret_cast<const void*>(static_cast<uintptr_t>(map->GetAddress()));
        }
    };

    kern_return_t MakeTransferResponse(
        const TransferBuffer& buffer,
        bool input,
        uint32_t transferred,
        OSData** response) {
        if (response == nullptr || (input && transferred != 0 && buffer.bytes() == nullptr)) {
            return kIOReturnBadArgument;
        }

        *response = OSData::withCapacity(kTransferCountSize + (input ? transferred : 0));
        if (*response == nullptr || !(*response)->appendBytes(&transferred, sizeof(transferred))
            || (input && transferred != 0
                && !(*response)->appendBytes(buffer.bytes(), transferred))) {
            OSSafeReleaseNULL(*response);
            return kIOReturnNoMemory;
        }
        return kIOReturnSuccess;
    }

    bool IsInput(uint8_t encodedByte) {
        return (encodedByte & 0x80) != 0;
    }

    bool ValidOutputPayload(bool input, uint32_t expectedLength, uint32_t payloadLength) {
        return input ? payloadLength == 0 : payloadLength == expectedLength;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::USBControlTransfer(
    const SwifterKitUSBControlTransferHeader* header,
    const uint8_t* bytes,
    uint32_t payloadLength,
    OSData** response) {
    if (header == nullptr || ivars == nullptr || ivars->usbInterface == nullptr
        || header->reserved != 0 || header->length > 65508) {
        return kIOReturnBadArgument;
    }

    const bool input = IsInput(header->requestType);
    if (!ValidOutputPayload(input, header->length, payloadLength)) {
        return kIOReturnBadArgument;
    }

    TransferBuffer buffer;
    kern_return_t result = buffer.prepare(ivars->usbInterface, input, header->length, bytes);
    if (result != kIOReturnSuccess) {
        return result;
    }

    uint16_t transferred = 0;
    result = ivars->usbInterface->DeviceRequest(
        header->requestType,
        header->request,
        header->value,
        header->index,
        header->length,
        buffer.descriptor,
        &transferred,
        header->timeout);
    if (result != kIOReturnSuccess) {
        return result;
    }
    return MakeTransferResponse(buffer, input, transferred, response);
}

kern_return_t SwifterKitRuntimeService::USBPipeTransfer(
    const SwifterKitUSBPipeTransferHeader* header,
    const uint8_t* bytes,
    uint32_t payloadLength,
    OSData** response) {
    if (header == nullptr || ivars == nullptr || ivars->usbInterface == nullptr
        || header->reserved8 != 0 || header->reserved16 != 0 || header->reserved32 != 0
        || header->length == 0 || header->length > 65508) {
        return kIOReturnBadArgument;
    }

    const bool input = IsInput(header->endpoint);
    if (!ValidOutputPayload(input, header->length, payloadLength)) {
        return kIOReturnBadArgument;
    }

    IOUSBHostPipe* pipe = nullptr;
    kern_return_t result = ivars->usbInterface->CopyPipe(header->endpoint, &pipe);
    if (result != kIOReturnSuccess || pipe == nullptr) {
        return result;
    }

    TransferBuffer buffer;
    result = buffer.prepare(ivars->usbInterface, input, header->length, bytes);
    uint32_t transferred = 0;
    if (result == kIOReturnSuccess) {
        result = pipe->IO(buffer.descriptor, header->length, &transferred, header->timeout);
    }
    pipe->release();
    if (result != kIOReturnSuccess) {
        return result;
    }
    return MakeTransferResponse(buffer, input, transferred, response);
}

kern_return_t SwifterKitRuntimeService::USBClearStall(uint8_t endpoint, bool withRequest) {
    if (ivars == nullptr || ivars->usbInterface == nullptr) {
        return kIOReturnNotReady;
    }

    IOUSBHostPipe* pipe = nullptr;
    kern_return_t result = ivars->usbInterface->CopyPipe(endpoint, &pipe);
    if (result == kIOReturnSuccess && pipe != nullptr) {
        result = pipe->ClearStall(withRequest);
    }
    OSSafeReleaseNULL(pipe);
    return result;
}

kern_return_t SwifterKitRuntimeService::USBSelectAlternateSetting(uint8_t alternateSetting) {
    if (ivars == nullptr || ivars->usbInterface == nullptr) {
        return kIOReturnNotReady;
    }
    return ivars->usbInterface->SelectAlternateSetting(alternateSetting);
}

#endif
