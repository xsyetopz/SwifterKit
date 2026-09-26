#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_USB

    #include <Availability.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <USBDriverKit/IOUSBHostDevice.h>
    #include <USBDriverKit/IOUSBHostInterface.h>
    #include <USBDriverKit/USBDriverKitDefs.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeUSBProtocol.h"
    #include "SwifterKitRuntimeUSBSupport.h"

namespace {
    constexpr uint32_t kLengthSize = sizeof(uint32_t);
    constexpr uint32_t kInterfaceSize = sizeof(IOUSBInterfaceDescriptor);

    // A descriptor response is the descriptor's full length, then its bytes when they fit in
    // one response. A length of zero reports that USBDriverKit returned no descriptor.
    kern_return_t DescriptorResponse(const void* bytes, uint32_t length, OSData** response) {
        if (response == nullptr || (length != 0 && bytes == nullptr)) {
            return kIOReturnBadArgument;
        }
        const bool fits = length <= kSwifterKitUSBMaximumDescriptorLength;
        *response = OSData::withCapacity(kLengthSize + (fits ? length : 0));
        if (*response == nullptr || !(*response)->appendBytes(&length, sizeof(length))
            || (fits && length != 0 && !(*response)->appendBytes(bytes, length))) {
            OSSafeReleaseNULL(*response);
            return kIOReturnNoMemory;
        }
        return kIOReturnSuccess;
    }

    template<typename Descriptor>
    kern_return_t
        RespondWithDescriptor(const Descriptor* descriptor, uint32_t length, OSData** response) {
        if (descriptor == nullptr) {
            return DescriptorResponse(nullptr, 0, response);
        }
        const kern_return_t result = DescriptorResponse(descriptor, length, response);
        IOUSBHostFreeDescriptor(descriptor);
        return result;
    }

    uint32_t TotalLength(const IOUSBConfigurationDescriptor* descriptor) {
        return descriptor == nullptr ? 0 : descriptor->wTotalLength;
    }

    uint32_t TotalLength(const IOUSBBOSDescriptor* descriptor) {
        return descriptor == nullptr ? 0 : descriptor->wTotalLength;
    }

    kern_return_t
        FrameResponse(kern_return_t result, uint64_t frame, uint64_t time, OSData** response) {
        if (result != kIOReturnSuccess) {
            return result;
        }
        const SwifterKitUSBFrameTime value = {.frame = frame, .time = time};
        return SwifterKitUSBDataResponse(&value, sizeof(value), response);
    }

    // CurrentMicroframe and ReferenceMicroframe first appear in the DriverKit 25 SDKs. Testing
    // for them keeps older SDKs compiling; there the runtime reports them unsupported.
    template<typename Provider>
    concept HasMicroframes = requires(Provider* value, uint64_t* number) {
        value->CurrentMicroframe(number, number);
        value->ReferenceMicroframe(number, number);
    };

    #if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5
    static_assert(HasMicroframes<IOUSBHostDevice> && HasMicroframes<IOUSBHostInterface>);
    #endif

    template<typename Provider>
    kern_return_t
        CopyMicroframe(Provider* provider, bool reference, uint64_t* frame, uint64_t* time) {
        if constexpr (HasMicroframes<Provider>) {
            return reference ? provider->ReferenceMicroframe(frame, time)
                             : provider->CurrentMicroframe(frame, time);
        } else {
            (void)provider;
            (void)reference;
            (void)frame;
            (void)time;
            return kIOReturnUnsupported;
        }
    }

    bool IsEmpty(uint32_t payloadLength) {
        return payloadLength == 0;
    }

    kern_return_t AppendInterface(IOUSBHostInterface* interface, OSData* response) {
        const IOUSBConfigurationDescriptor* configuration =
            interface->CopyConfigurationDescriptor();
        if (configuration == nullptr) {
            return kIOReturnNotFound;
        }
        const IOUSBInterfaceDescriptor* descriptor =
            interface->GetInterfaceDescriptor(configuration);
        const bool appended =
            descriptor != nullptr
            && response->appendBytes(descriptor, sizeof(IOUSBInterfaceDescriptor));
        IOUSBHostFreeDescriptor(configuration);
        if (descriptor == nullptr) {
            return kIOReturnNotFound;
        }
        return appended ? kIOReturnSuccess : kIOReturnNoMemory;
    }

    kern_return_t CopyInterfaces(IOUSBHostDevice* device, OSData** response) {
        uintptr_t iterator = 0;
        kern_return_t result = device->CreateInterfaceIterator(&iterator);
        if (result != kIOReturnSuccess) {
            return result;
        }
        OSData* list = OSData::withCapacity(kSwifterKitUSBMaximumInterfaces * kInterfaceSize);
        uint32_t count = 0;
        result = list == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        while (result == kIOReturnSuccess) {
            IOUSBHostInterface* interface = nullptr;
            result = device->CopyInterface(iterator, &interface);
            if (result != kIOReturnSuccess || interface == nullptr) {
                break;
            }
            result = count < kSwifterKitUSBMaximumInterfaces ? AppendInterface(interface, list)
                                                             : kIOReturnOverrun;
            interface->release();
            count += result == kIOReturnSuccess ? 1 : 0;
        }
        (void)device->DestroyInterfaceIterator(iterator);
        if (result == kIOReturnSuccess) {
            *response = OSData::withCapacity(kLengthSize + count * kInterfaceSize);
            if (*response == nullptr || !(*response)->appendBytes(&count, sizeof(count))
                || (count != 0 && !(*response)->appendBytes(list))) {
                OSSafeReleaseNULL(*response);
                result = kIOReturnNoMemory;
            }
        }
        OSSafeReleaseNULL(list);
        return result;
    }

    kern_return_t CopyDescriptor(
        IOUSBHostDevice* device,
        const SwifterKitUSBDescriptorRequest* request,
        OSData** response) {
        if (request->length == 0 || request->length > kSwifterKitUSBMaximumDescriptorLength
            || request->requestType > kIOUSBDeviceRequestTypeValueVendor
            || request->recipient > kIOUSBDeviceRequestRecipientValueOther) {
            return kIOReturnBadArgument;
        }
        auto* buffer = static_cast<uint8_t*>(IOMallocZero(request->length));
        if (buffer == nullptr) {
            return kIOReturnNoMemory;
        }
        uint16_t length = request->length;
        kern_return_t result = device->CopyDescriptor(
            request->type,
            &length,
            request->index,
            request->languageID,
            request->requestType,
            request->recipient,
            buffer);
        if (result == kIOReturnSuccess) {
            result = length <= request->length ? DescriptorResponse(buffer, length, response)
                                               : kIOReturnOverrun;
        }
        IOFree(buffer, request->length);
        return result;
    }

    kern_return_t CopyConfiguration(
        IOUSBHostDevice* parent,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        const auto* request = reinterpret_cast<const SwifterKitUSBConfigurationRequest*>(payload);
        if (payloadLength != sizeof(*request) || request->reserved != 0) {
            return kIOReturnBadArgument;
        }
        const IOUSBConfigurationDescriptor* configuration = nullptr;
        if (request->selector == kSwifterKitUSBConfigurationIndex) {
            configuration = parent->CopyConfigurationDescriptor(request->value);
        } else if (request->selector == kSwifterKitUSBConfigurationValue) {
            configuration = parent->CopyConfigurationDescriptorWithValue(request->value);
        } else {
            return kIOReturnBadArgument;
        }
        return RespondWithDescriptor(configuration, TotalLength(configuration), response);
    }

    // Read-only device queries, which also work from an interface through its parent device.
    kern_return_t ParentDeviceQuery(
        IOUSBHostDevice* parent,
        uint32_t opcode,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        kern_return_t result = kIOReturnBadArgument;
        uint8_t byte = 0;
        switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
            case SwifterKitRuntimeOpcode::USBGetDeviceSpeed:
                if (IsEmpty(payloadLength)) {
                    result = parent->GetSpeed(&byte);
                    result = result == kIOReturnSuccess ? SwifterKitUSBValueResponse(byte, response)
                                                        : result;
                }
                break;
            case SwifterKitRuntimeOpcode::USBGetDeviceAddress:
                if (IsEmpty(payloadLength)) {
                    result = parent->GetAddress(&byte);
                    result = result == kIOReturnSuccess ? SwifterKitUSBValueResponse(byte, response)
                                                        : result;
                }
                break;
            case SwifterKitRuntimeOpcode::USBCopyDeviceDescriptor:
                if (IsEmpty(payloadLength)) {
                    result = RespondWithDescriptor(
                        parent->CopyDeviceDescriptor(),
                        sizeof(IOUSBDeviceDescriptor),
                        response);
                }
                break;
            case SwifterKitRuntimeOpcode::USBCopyCapabilityDescriptors:
                if (IsEmpty(payloadLength)) {
                    const IOUSBBOSDescriptor* capabilities = parent->CopyCapabilityDescriptors();
                    result =
                        RespondWithDescriptor(capabilities, TotalLength(capabilities), response);
                }
                break;
            case SwifterKitRuntimeOpcode::USBCopyDescriptor:
                if (payloadLength == sizeof(SwifterKitUSBDescriptorRequest)) {
                    result = CopyDescriptor(
                        parent,
                        reinterpret_cast<const SwifterKitUSBDescriptorRequest*>(payload),
                        response);
                }
                break;
            case SwifterKitRuntimeOpcode::USBCopyConfigurationDescriptor:
                result = CopyConfiguration(parent, payload, payloadLength, response);
                break;
            default:
                result = kIOReturnUnsupported;
                break;
        }
        return result;
    }

    kern_return_t CopyCurrentConfiguration(
        SwifterKitRuntimeService* service,
        IOUSBHostDevice* device,
        IOUSBHostInterface* interface,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        const auto* request = reinterpret_cast<const SwifterKitUSBConfigurationRequest*>(payload);
        if (payloadLength != sizeof(*request) || request->reserved != 0 || request->value != 0) {
            return kIOReturnBadArgument;
        }
        const IOUSBConfigurationDescriptor* configuration =
            interface != nullptr ? interface->CopyConfigurationDescriptor()
                                 : device->CopyConfigurationDescriptor(service);
        return RespondWithDescriptor(configuration, TotalLength(configuration), response);
    }

    kern_return_t CopyString(
        IOUSBHostDevice* device,
        IOUSBHostInterface* interface,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        const auto* request = reinterpret_cast<const SwifterKitUSBStringRequest*>(payload);
        if (payloadLength != sizeof(*request) || request->hasLanguageID > 1
            || (request->hasLanguageID == 0 && request->languageID != 0)) {
            return kIOReturnBadArgument;
        }
        const IOUSBStringDescriptor* string = nullptr;
        if (interface != nullptr) {
            string = request->hasLanguageID != 0
                         ? interface->CopyStringDescriptor(request->index, request->languageID)
                         : interface->CopyStringDescriptor(request->index);
        } else {
            string = request->hasLanguageID != 0
                         ? device->CopyStringDescriptor(request->index, request->languageID)
                         : device->CopyStringDescriptor(request->index);
        }
        return RespondWithDescriptor(string, string == nullptr ? 0 : string->bLength, response);
    }

    kern_return_t CopyInterfaceDescriptor(IOUSBHostInterface* interface, OSData** response) {
        OSData* data = OSData::withCapacity(sizeof(IOUSBInterfaceDescriptor));
        const kern_return_t result =
            data == nullptr ? kIOReturnNoMemory : AppendInterface(interface, data);
        if (result == kIOReturnSuccess) {
            *response = data;
        } else {
            OSSafeReleaseNULL(data);
        }
        return result;
    }

    // Operations that need the matched interface, or that use it when it is the provider.
    kern_return_t InterfaceCommand(
        IOUSBHostDevice* device,
        IOUSBHostInterface* interface,
        uint32_t opcode,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        kern_return_t result = kIOReturnBadArgument;
        uint64_t frame = 0;
        uint64_t time = 0;
        uint32_t value = 0;
        switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
            case SwifterKitRuntimeOpcode::USBGetPortStatus:
                if (IsEmpty(payloadLength)) {
                    result = interface != nullptr ? interface->GetPortStatus(&value)
                                                  : device->GetPortStatus(&value);
                    result = result == kIOReturnSuccess
                                 ? SwifterKitUSBValueResponse(value, response)
                                 : result;
                }
                break;
            case SwifterKitRuntimeOpcode::USBGetFrameNumber:
                if (IsEmpty(payloadLength)) {
                    result = interface != nullptr ? interface->GetFrameNumber(&frame, &time)
                                                  : device->GetFrameNumber(&frame, &time);
                    result = FrameResponse(result, frame, time, response);
                }
                break;
            case SwifterKitRuntimeOpcode::USBGetCurrentMicroframe:
            case SwifterKitRuntimeOpcode::USBGetReferenceMicroframe:
                if (IsEmpty(payloadLength)) {
                    const bool reference = opcode
                                           == static_cast<uint32_t>(
                                               SwifterKitRuntimeOpcode::USBGetReferenceMicroframe);
                    result = interface != nullptr
                                 ? CopyMicroframe(interface, reference, &frame, &time)
                                 : CopyMicroframe(device, reference, &frame, &time);
                    result = FrameResponse(result, frame, time, response);
                }
                break;
            case SwifterKitRuntimeOpcode::USBCopyStringDescriptor:
                result = CopyString(device, interface, payload, payloadLength, response);
                break;
            case SwifterKitRuntimeOpcode::USBCopyInterfaceDescriptor:
                if (interface == nullptr) {
                    result = kIOReturnUnsupported;
                } else if (IsEmpty(payloadLength)) {
                    result = CopyInterfaceDescriptor(interface, response);
                }
                break;
            case SwifterKitRuntimeOpcode::USBSetIdlePolicy:
                if (interface == nullptr) {
                    result = kIOReturnUnsupported;
                } else if (payloadLength == sizeof(value)) {
                    memcpy(&value, payload, sizeof(value));
                    result = interface->SetIdlePolicy(value);
                }
                break;
            case SwifterKitRuntimeOpcode::USBGetIdlePolicy:
                if (interface == nullptr) {
                    result = kIOReturnUnsupported;
                } else if (IsEmpty(payloadLength)) {
                    result = interface->GetIdlePolicy(&value);
                    result = result == kIOReturnSuccess
                                 ? SwifterKitUSBValueResponse(value, response)
                                 : result;
                }
                break;
            default:
                result = kIOReturnUnsupported;
                break;
        }
        return result;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::USBCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || response == nullptr || (payloadLength != 0 && payload == nullptr)) {
        return kIOReturnBadArgument;
    }
    IOUSBHostDevice* const device = ivars->usbDevice;
    IOUSBHostInterface* const interface = ivars->usbInterface;
    if (device == nullptr && interface == nullptr) {
        return kIOReturnNotReady;
    }
    DeliverUSBCompletions();
    if (opcode >= static_cast<uint32_t>(SwifterKitRuntimeOpcode::USBAsyncDeviceRequest)) {
        return USBAsyncCommand(opcode, payload, payloadLength, response);
    }
    if (opcode >= static_cast<uint32_t>(SwifterKitRuntimeOpcode::USBPipeAsyncIO)) {
        return USBPipeCommand(opcode, payload, payloadLength, response);
    }

    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::USBDeviceSetConfiguration: {
            const auto* request = reinterpret_cast<const SwifterKitUSBSetConfiguration*>(payload);
            if (device == nullptr) {
                return kIOReturnUnsupported;
            }
            if (payloadLength != sizeof(*request) || request->matchInterfaces > 1
                || request->reserved != 0) {
                return kIOReturnBadArgument;
            }
            return device->SetConfiguration(
                request->configurationValue,
                request->matchInterfaces != 0);
        }
        case SwifterKitRuntimeOpcode::USBDeviceReset:
            if (device == nullptr) {
                return kIOReturnUnsupported;
            }
            return IsEmpty(payloadLength) ? device->Reset() : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::USBCopyInterfaces:
            if (device == nullptr) {
                return kIOReturnUnsupported;
            }
            return IsEmpty(payloadLength) ? CopyInterfaces(device, response) : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::USBAbortDeviceRequests:
            // Asynchronous only: a synchronous abort could wait on the queue delivering it.
            if (!IsEmpty(payloadLength)) {
                return kIOReturnBadArgument;
            }
            return interface != nullptr
                       ? interface->AbortDeviceRequests(kIOUSBAbortAsynchronous, kIOReturnAborted)
                       : device->AbortDeviceRequests(
                             this,
                             kIOUSBAbortAsynchronous,
                             kIOReturnAborted);
        case SwifterKitRuntimeOpcode::USBGetPortStatus:
        case SwifterKitRuntimeOpcode::USBGetFrameNumber:
        case SwifterKitRuntimeOpcode::USBGetCurrentMicroframe:
        case SwifterKitRuntimeOpcode::USBGetReferenceMicroframe:
        case SwifterKitRuntimeOpcode::USBCopyStringDescriptor:
        case SwifterKitRuntimeOpcode::USBCopyInterfaceDescriptor:
        case SwifterKitRuntimeOpcode::USBSetIdlePolicy:
        case SwifterKitRuntimeOpcode::USBGetIdlePolicy:
            return InterfaceCommand(device, interface, opcode, payload, payloadLength, response);
        default:
            break;
    }

    if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::USBCopyConfigurationDescriptor)
        && payloadLength == sizeof(SwifterKitUSBConfigurationRequest)
        && payload[0] == kSwifterKitUSBConfigurationCurrent) {
        return CopyCurrentConfiguration(this, device, interface, payload, payloadLength, response);
    }

    IOUSBHostDevice* parent = device;
    if (parent != nullptr) {
        parent->retain();
    } else {
        const kern_return_t result = interface->CopyDevice(&parent);
        if (result != kIOReturnSuccess || parent == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNotFound : result;
        }
    }
    const kern_return_t result =
        ParentDeviceQuery(parent, opcode, payload, payloadLength, response);
    parent->release();
    return result;
}

#endif
