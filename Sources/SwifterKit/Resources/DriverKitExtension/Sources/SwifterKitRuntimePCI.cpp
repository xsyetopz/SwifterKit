#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_PCI

    #include <DriverKit/OSData.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    kern_return_t MakeUInt64Response(uint64_t value, OSData** response) {
        if (response == nullptr) {
            return kIOReturnBadArgument;
        }
        *response = OSData::withBytes(&value, sizeof(value));
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }

    bool IsValidAccess(const SwifterKitPCIAccessHeader* header) {
        if (header == nullptr || header->reserved != 0 || header->space > 1) {
            return false;
        }
        if (header->width != 1 && header->width != 2 && header->width != 4 && header->width != 8) {
            return false;
        }
        if (header->offset % header->width != 0) {
            return false;
        }
        if (header->space == 0) {
            return header->width != 8 && header->options == 0
                   && header->offset <= 4096 - header->width;
        }
        return true;
    }

    uint64_t ReadConfiguration(IOPCIDevice* device, const SwifterKitPCIAccessHeader* header) {
        switch (header->width) {
            case 1: {
                uint8_t value = 0;
                device->ConfigurationRead8(header->offset, &value);
                return value;
            }
            case 2: {
                uint16_t value = 0;
                device->ConfigurationRead16(header->offset, &value);
                return value;
            }
            case 4: {
                uint32_t value = 0;
                device->ConfigurationRead32(header->offset, &value);
                return value;
            }
        }
        return 0;
    }

    void WriteConfiguration(IOPCIDevice* device, const SwifterKitPCIAccessHeader* header) {
        switch (header->width) {
            case 1:
                device->ConfigurationWrite8(header->offset, static_cast<uint8_t>(header->value));
                break;
            case 2:
                device->ConfigurationWrite16(header->offset, static_cast<uint16_t>(header->value));
                break;
            case 4:
                device->ConfigurationWrite32(header->offset, static_cast<uint32_t>(header->value));
                break;
        }
    }

    uint64_t ReadMemory(IOPCIDevice* device, const SwifterKitPCIAccessHeader* header) {
        switch (header->width) {
            case 1: {
                uint8_t value = 0;
                device->MemoryRead8(header->memoryIndex, header->offset, &value, header->options);
                return value;
            }
            case 2: {
                uint16_t value = 0;
                device->MemoryRead16(header->memoryIndex, header->offset, &value, header->options);
                return value;
            }
            case 4: {
                uint32_t value = 0;
                device->MemoryRead32(header->memoryIndex, header->offset, &value, header->options);
                return value;
            }
            case 8: {
                uint64_t value = 0;
                device->MemoryRead64(header->memoryIndex, header->offset, &value, header->options);
                return value;
            }
        }
        return 0;
    }

    void WriteMemory(IOPCIDevice* device, const SwifterKitPCIAccessHeader* header) {
        switch (header->width) {
            case 1:
                device->MemoryWrite8(
                    header->memoryIndex,
                    header->offset,
                    static_cast<uint8_t>(header->value),
                    header->options);
                break;
            case 2:
                device->MemoryWrite16(
                    header->memoryIndex,
                    header->offset,
                    static_cast<uint16_t>(header->value),
                    header->options);
                break;
            case 4:
                device->MemoryWrite32(
                    header->memoryIndex,
                    header->offset,
                    static_cast<uint32_t>(header->value),
                    header->options);
                break;
            case 8:
                device->MemoryWrite64(
                    header->memoryIndex,
                    header->offset,
                    header->value,
                    header->options);
                break;
        }
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::PCIAccess(
    const SwifterKitPCIAccessHeader* header,
    bool write,
    OSData** response) {
    if (!IsValidAccess(header) || ivars == nullptr || ivars->pciDevice == nullptr
        || response == nullptr) {
        return kIOReturnBadArgument;
    }
    *response = nullptr;

    if (write && header->width != 8 && header->value >= (UINT64_C(1) << (header->width * 8))) {
        return kIOReturnBadArgument;
    }
    if (write) {
        if (header->space == 0) {
            WriteConfiguration(ivars->pciDevice, header);
        } else {
            WriteMemory(ivars->pciDevice, header);
        }
        return kIOReturnSuccess;
    }

    const uint64_t value = header->space == 0 ? ReadConfiguration(ivars->pciDevice, header)
                                              : ReadMemory(ivars->pciDevice, header);
    return MakeUInt64Response(value, response);
}

kern_return_t SwifterKitRuntimeService::PCIGetBARInfo(uint8_t barIndex, OSData** response) {
    if (barIndex > 6 || ivars == nullptr || ivars->pciDevice == nullptr || response == nullptr) {
        return kIOReturnBadArgument;
    }

    uint8_t memoryIndex = 0;
    uint8_t type = 0;
    uint64_t size = 0;
    kern_return_t result = ivars->pciDevice->GetBARInfo(barIndex, &memoryIndex, &size, &type);
    if (result != kIOReturnSuccess) {
        return result;
    }

    const uint16_t reserved = 0;
    *response = OSData::withCapacity(12);
    if (*response == nullptr || !(*response)->appendBytes(&memoryIndex, sizeof(memoryIndex))
        || !(*response)->appendBytes(&type, sizeof(type))
        || !(*response)->appendBytes(&reserved, sizeof(reserved))
        || !(*response)->appendBytes(&size, sizeof(size))) {
        OSSafeReleaseNULL(*response);
        return kIOReturnNoMemory;
    }
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::PCIGetLocation(OSData** response) {
    if (ivars == nullptr || ivars->pciDevice == nullptr || response == nullptr) {
        return kIOReturnBadArgument;
    }

    uint8_t value[4] = {};
    kern_return_t result = ivars->pciDevice->GetBusDeviceFunction(&value[0], &value[1], &value[2]);
    if (result != kIOReturnSuccess) {
        return result;
    }
    *response = OSData::withBytes(value, sizeof(value));
    return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::PCIFindCapability(
    const SwifterKitPCICapabilityHeader* header,
    OSData** response) {
    if (header == nullptr || header->reserved != 0 || ivars == nullptr
        || ivars->pciDevice == nullptr || response == nullptr) {
        return kIOReturnBadArgument;
    }

    uint64_t offset = 0;
    kern_return_t result =
        ivars->pciDevice->FindPCICapability(header->identifier, header->searchOffset, &offset);
    if (result != kIOReturnSuccess) {
        return result;
    }
    return MakeUInt64Response(offset, response);
}

kern_return_t SwifterKitRuntimeService::PCICommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (response == nullptr || (payloadLength != 0 && payload == nullptr)) {
        return kIOReturnBadArgument;
    }
    *response = nullptr;

    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::PCIRead:
        case SwifterKitRuntimeOpcode::PCIWrite:
            if (payloadLength != sizeof(SwifterKitPCIAccessHeader)) {
                return kIOReturnBadArgument;
            }
            return PCIAccess(
                reinterpret_cast<const SwifterKitPCIAccessHeader*>(payload),
                opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::PCIWrite),
                response);
        case SwifterKitRuntimeOpcode::PCIGetBARInfo:
            if (payloadLength != 4 || payload[1] != 0 || payload[2] != 0 || payload[3] != 0) {
                return kIOReturnBadArgument;
            }
            return PCIGetBARInfo(payload[0], response);
        case SwifterKitRuntimeOpcode::PCIGetLocation:
            if (payloadLength != 0) {
                return kIOReturnBadArgument;
            }
            return PCIGetLocation(response);
        case SwifterKitRuntimeOpcode::PCIFindCapability:
            if (payloadLength != sizeof(SwifterKitPCICapabilityHeader)) {
                return kIOReturnBadArgument;
            }
            return PCIFindCapability(
                reinterpret_cast<const SwifterKitPCICapabilityHeader*>(payload),
                response);
        default:
            return kIOReturnUnsupported;
    }
}

#endif
