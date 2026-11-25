#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_USB

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <USBDriverKit/IOUSBHostDevice.h>
    #include <USBDriverKit/IOUSBHostInterface.h>
    #include <USBDriverKit/IOUSBHostPipe.h>
    #include <USBDriverKit/USBDriverKitDefs.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeUSBSupport.h"

namespace {
    constexpr uint32_t kTransferCountSize = sizeof(uint32_t);
    constexpr bool kSerialOwnsInterface = SWIFTERKIT_USB_SERIAL != 0;

    struct TransferBuffer {
        IOBufferMemoryDescriptor* descriptor = nullptr;
        IOMemoryMap* map = nullptr;

        ~TransferBuffer() {
            OSSafeReleaseNULL(map);
            OSSafeReleaseNULL(descriptor);
        }

        template<typename Provider>
        kern_return_t
            prepare(Provider* provider, bool input, uint32_t length, const uint8_t* bytes) {
            if (length == 0) {
                return kIOReturnSuccess;
            }
            return SwifterKitCreateUSBBuffer(provider, input, length, bytes, &descriptor, &map);
        }

        const void* bytes() const {
            return SwifterKitUSBMappedBytes(map);
        }
    };

    kern_return_t MakeTransferResponse(
        const TransferBuffer& buffer,
        bool input,
        uint32_t transferred,
        uint32_t requested,
        OSData** response) {
        if (response == nullptr || transferred > requested
            || (input && transferred != 0 && buffer.bytes() == nullptr)) {
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
        return (encodedByte & 0x80U) != 0;
    }

    bool ValidOutputPayload(bool input, uint32_t expectedLength, uint32_t payloadLength) {
        return input ? payloadLength == 0 : payloadLength == expectedLength;
    }
    bool HasInterfaceNumber(IOUSBHostInterface* interface, uint8_t interfaceNumber) {
        const IOUSBConfigurationDescriptor* configuration =
            interface->CopyConfigurationDescriptor();
        if (configuration == nullptr) {
            return false;
        }
        const IOUSBInterfaceDescriptor* descriptor =
            interface->GetInterfaceDescriptor(configuration);
        const bool matches =
            descriptor != nullptr && descriptor->bInterfaceNumber == interfaceNumber;
        IOUSBHostFreeDescriptor(configuration);
        return matches;
    }

    kern_return_t CopyInterface(
        IOUSBHostDevice* device,
        uint8_t interfaceNumber,
        IOUSBHostInterface** found) {
        uintptr_t iterator = 0;
        kern_return_t result = device->CreateInterfaceIterator(&iterator);
        if (result != kIOReturnSuccess) {
            return result;
        }
        while (*found == nullptr) {
            IOUSBHostInterface* interface = nullptr;
            result = device->CopyInterface(iterator, &interface);
            if (result != kIOReturnSuccess || interface == nullptr) {
                break;
            }
            if (HasInterfaceNumber(interface, interfaceNumber)) {
                *found = interface;
            } else {
                interface->release();
            }
        }
        (void)device->DestroyInterfaceIterator(iterator);
        if (*found != nullptr) {
            return kIOReturnSuccess;
        }
        return result == kIOReturnSuccess ? kIOReturnNotFound : result;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartUSB(IOService* provider) {
    if (provider == nullptr || ivars == nullptr || ivars->usbDevice != nullptr
        || ivars->usbInterface != nullptr) {
        return kIOReturnBadArgument;
    }

    if constexpr (kSwifterKitUSBDeviceProvider) {
        ivars->usbDevice = OSDynamicCast(IOUSBHostDevice, provider);
        if (ivars->usbDevice == nullptr) {
            return kIOReturnBadArgument;
        }
        ivars->usbDevice->retain();
        const kern_return_t result = ivars->usbDevice->Open(this, 0, 0);
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(ivars->usbDevice);
        }
        return result;
    } else {
        ivars->usbInterface = OSDynamicCast(IOUSBHostInterface, provider);
        if (ivars->usbInterface == nullptr) {
            return kIOReturnBadArgument;
        }
        ivars->usbInterface->retain();
        // IOUserUSBSerial opened the interface for this service in ConnectQueues and closes it in
        // DisconnectQueues, so the runtime only borrows it.
        if constexpr (kSerialOwnsInterface) {
            return kIOReturnSuccess;
        }
        const kern_return_t result = ivars->usbInterface->Open(this, 0, nullptr);
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(ivars->usbInterface);
        }
        return result;
    }
}

void SwifterKitRuntimeService::StopUSB() {
    if (ivars == nullptr || ivars->usbLock == nullptr) {
        return;
    }

    // Abort asynchronously: Stop runs on the default queue that delivers the completions, so a
    // synchronous abort could wait on itself. Each aborted completion releases its own slot.
    IOUSBHostPipe* pipes[kSwifterKitUSBMaximumPendingTransfers] = {};
    IOLockLock(ivars->usbLock);
    for (uint32_t slot = 0; slot < kSwifterKitUSBMaximumPendingTransfers; ++slot) {
        const SwifterKitUSBPendingTransfer& transfer = ivars->usbTransfers[slot];
        if (transfer.active && !transfer.completed && transfer.pipe != nullptr) {
            pipes[slot] = transfer.pipe;
            pipes[slot]->retain();
        }
    }
    IOLockUnlock(ivars->usbLock);
    for (IOUSBHostPipe*& pipe : pipes) {
        if (pipe != nullptr) {
            (void)pipe->Abort(kIOUSBAbortAsynchronous, kIOReturnAborted, nullptr);
            OSSafeReleaseNULL(pipe);
        }
    }
    AbortUSBAsyncRequests();

    if (ivars->usbInterface != nullptr) {
        if constexpr (!kSerialOwnsInterface) {
            (void)ivars->usbInterface->Close(this, 0);
        }
        OSSafeReleaseNULL(ivars->usbInterface);
    }
    if (ivars->usbDevice != nullptr) {
        (void)ivars->usbDevice->Close(this, 0);
        OSSafeReleaseNULL(ivars->usbDevice);
    }
}

kern_return_t SwifterKitRuntimeService::USBControlTransfer(
    const SwifterKitUSBControlTransferHeader* header,
    const uint8_t* bytes,
    uint32_t payloadLength,
    OSData** response) {
    // Retry completions that the required queue rejected earlier.
    DeliverUSBCompletions();
    if (header == nullptr || ivars == nullptr || header->reserved != 0
        || header->length > kSwifterKitUSBMaximumResponsePayload - kTransferCountSize) {
        return kIOReturnBadArgument;
    }
    if (ivars->usbInterface == nullptr && ivars->usbDevice == nullptr) {
        return kIOReturnNotReady;
    }

    const bool input = IsInput(header->requestType);
    if (!ValidOutputPayload(input, header->length, payloadLength)) {
        return kIOReturnBadArgument;
    }

    TransferBuffer buffer;
    kern_return_t result = ivars->usbInterface != nullptr
                               ? buffer.prepare(ivars->usbInterface, input, header->length, bytes)
                               : buffer.prepare(ivars->usbDevice, input, header->length, bytes);
    if (result != kIOReturnSuccess) {
        return result;
    }

    uint16_t transferred = 0;
    if (ivars->usbInterface != nullptr) {
        result = ivars->usbInterface->DeviceRequest(
            header->requestType,
            header->request,
            header->value,
            header->index,
            header->length,
            buffer.descriptor,
            &transferred,
            header->timeout);
    } else {
        result = ivars->usbDevice->DeviceRequest(
            this,
            header->requestType,
            header->request,
            header->value,
            header->index,
            header->length,
            buffer.descriptor,
            &transferred,
            header->timeout);
    }
    if (result != kIOReturnSuccess) {
        return result;
    }
    return MakeTransferResponse(buffer, input, transferred, header->length, response);
}

kern_return_t SwifterKitRuntimeService::USBPipeTransfer(
    const SwifterKitUSBPipeTransferHeader* header,
    const uint8_t* bytes,
    uint32_t payloadLength,
    OSData** response) {
    // Retry completions that the required queue rejected earlier.
    DeliverUSBCompletions();
    if (header == nullptr || ivars == nullptr || header->reserved8 != 0 || header->reserved16 != 0
        || header->reserved32 != 0 || header->length == 0
        || header->length > kSwifterKitUSBMaximumResponsePayload - kTransferCountSize) {
        return kIOReturnBadArgument;
    }
    if (ivars->usbInterface == nullptr) {
        return ivars->usbDevice != nullptr ? kIOReturnUnsupported : kIOReturnNotReady;
    }

    const bool input = IsInput(header->endpoint);
    if (!ValidOutputPayload(input, header->length, payloadLength)) {
        return kIOReturnBadArgument;
    }

    IOUSBHostPipe* pipe = nullptr;
    kern_return_t result = ivars->usbInterface->CopyPipe(header->endpoint, &pipe);
    if (result != kIOReturnSuccess || pipe == nullptr) {
        return result == kIOReturnSuccess ? kIOReturnNotFound : result;
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
    return MakeTransferResponse(buffer, input, transferred, header->length, response);
}

kern_return_t SwifterKitRuntimeService::USBClearStall(uint8_t endpoint, bool withRequest) {
    // Retry completions that the required queue rejected earlier.
    DeliverUSBCompletions();
    if (ivars == nullptr || ivars->usbInterface == nullptr) {
        return ivars != nullptr && ivars->usbDevice != nullptr ? kIOReturnUnsupported
                                                               : kIOReturnNotReady;
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
    // Retry completions that the required queue rejected earlier.
    DeliverUSBCompletions();
    if (ivars == nullptr || ivars->usbInterface == nullptr) {
        return ivars != nullptr && ivars->usbDevice != nullptr ? kIOReturnUnsupported
                                                               : kIOReturnNotReady;
    }
    return ivars->usbInterface->SelectAlternateSetting(alternateSetting);
}

kern_return_t SwifterKitRuntimeService::USBSelectInterfaceAlternateSetting(
    uint8_t interfaceNumber,
    uint8_t alternateSetting) {
    // Retry completions that the required queue rejected earlier.
    DeliverUSBCompletions();
    if (ivars == nullptr || (ivars->usbInterface == nullptr && ivars->usbDevice == nullptr)) {
        return kIOReturnNotReady;
    }
    if (ivars->usbInterface != nullptr
        && HasInterfaceNumber(ivars->usbInterface, interfaceNumber)) {
        return ivars->usbInterface->SelectAlternateSetting(alternateSetting);
    }

    IOUSBHostDevice* device = ivars->usbDevice;
    kern_return_t result = kIOReturnSuccess;
    if (device != nullptr) {
        device->retain();
    } else {
        result = ivars->usbInterface->CopyDevice(&device);
    }
    IOUSBHostInterface* interface = nullptr;
    if (result == kIOReturnSuccess && device != nullptr) {
        result = CopyInterface(device, interfaceNumber, &interface);
    }
    OSSafeReleaseNULL(device);
    if (result != kIOReturnSuccess || interface == nullptr) {
        OSSafeReleaseNULL(interface);
        return result == kIOReturnSuccess ? kIOReturnNotFound : result;
    }

    // Selecting a setting needs an open interface; one another driver holds fails here.
    result = interface->Open(this, 0, nullptr);
    if (result == kIOReturnSuccess) {
        result = interface->SelectAlternateSetting(alternateSetting);
        (void)interface->Close(this, 0);
    }
    interface->release();
    return result;
}

#endif
