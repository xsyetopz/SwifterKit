#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_PCI

    #include <DriverKit/OSBoolean.h>
    #include <DriverKit/OSCollections.h>
    #include <DriverKit/OSData.h>
    #include <PCIDriverKit/IOPCIFamilyDefinitions.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    constexpr uint32_t kAccessOptionMask = kIOPCIAccessLatencyTolerantHint;

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
        return (header->options & ~kAccessOptionMask) == 0;
    }

    // Loads BAR0...BAR5 once. A 64-bit BAR's upper half and unimplemented BARs fail GetBARInfo
    // and are skipped; the expansion ROM reports no size, so it is never an accepted aperture.
    void LoadApertures(SwifterKitRuntimeService_IVars* state) {
        if (state->pciAperturesLoaded) {
            return;
        }
        state->pciApertureCount = 0;
        for (uint8_t barIndex = kPCIMemoryRangeBAR0; barIndex <= kPCIMemoryRangeBAR5; ++barIndex) {
            uint8_t memoryIndex = 0;
            uint64_t size = 0;
            uint8_t type = 0;
            if (state->pciDevice->GetBARInfo(barIndex, &memoryIndex, &size, &type)
                    == kIOReturnSuccess
                && size != 0) {
                state->pciApertureIndices[state->pciApertureCount] = memoryIndex;
                state->pciApertureSizes[state->pciApertureCount] = size;
                ++state->pciApertureCount;
            }
        }
        state->pciAperturesLoaded = true;
    }

    bool ApertureContains(
        SwifterKitRuntimeService_IVars* state,
        uint8_t memoryIndex,
        uint64_t offset,
        uint8_t width) {
        LoadApertures(state);
        for (uint8_t slot = 0; slot < state->pciApertureCount; ++slot) {
            if (state->pciApertureIndices[slot] == memoryIndex) {
                const uint64_t size = state->pciApertureSizes[slot];
                return size >= width && offset <= size - width;
            }
        }
        return false;
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
            default:
                break;
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
            default:
                break;
        }
    }

    uint64_t ReadMemory(IOPCIDevice* device, const SwifterKitPCIAccessHeader* header) {
        switch (header->width) {
            case 1: {
                uint8_t value = 0;
                if (header->options == 0) {
                    device->MemoryRead8(header->memoryIndex, header->offset, &value);
                } else {
                    device
                        ->MemoryRead8(header->memoryIndex, header->offset, &value, header->options);
                }
                return value;
            }
            case 2: {
                uint16_t value = 0;
                if (header->options == 0) {
                    device->MemoryRead16(header->memoryIndex, header->offset, &value);
                } else {
                    device->MemoryRead16(
                        header->memoryIndex,
                        header->offset,
                        &value,
                        header->options);
                }
                return value;
            }
            case 4: {
                uint32_t value = 0;
                if (header->options == 0) {
                    device->MemoryRead32(header->memoryIndex, header->offset, &value);
                } else {
                    device->MemoryRead32(
                        header->memoryIndex,
                        header->offset,
                        &value,
                        header->options);
                }
                return value;
            }
            case 8: {
                uint64_t value = 0;
                if (header->options == 0) {
                    device->MemoryRead64(header->memoryIndex, header->offset, &value);
                } else {
                    device->MemoryRead64(
                        header->memoryIndex,
                        header->offset,
                        &value,
                        header->options);
                }
                return value;
            }
            default:
                break;
        }
        return 0;
    }

    // The options-free overloads are the documented equivalent of passing no options.
    void WriteMemory(IOPCIDevice* device, const SwifterKitPCIAccessHeader* header) {
        const bool plain = header->options == 0;
        switch (header->width) {
            case 1:
                if (plain) {
                    device->MemoryWrite8(
                        header->memoryIndex,
                        header->offset,
                        static_cast<uint8_t>(header->value));
                } else {
                    device->MemoryWrite8(
                        header->memoryIndex,
                        header->offset,
                        static_cast<uint8_t>(header->value),
                        header->options);
                }
                break;
            case 2:
                if (plain) {
                    device->MemoryWrite16(
                        header->memoryIndex,
                        header->offset,
                        static_cast<uint16_t>(header->value));
                } else {
                    device->MemoryWrite16(
                        header->memoryIndex,
                        header->offset,
                        static_cast<uint16_t>(header->value),
                        header->options);
                }
                break;
            case 4:
                if (plain) {
                    device->MemoryWrite32(
                        header->memoryIndex,
                        header->offset,
                        static_cast<uint32_t>(header->value));
                } else {
                    device->MemoryWrite32(
                        header->memoryIndex,
                        header->offset,
                        static_cast<uint32_t>(header->value),
                        header->options);
                }
                break;
            case 8:
                if (plain) {
                    device->MemoryWrite64(header->memoryIndex, header->offset, header->value);
                } else {
                    device->MemoryWrite64(
                        header->memoryIndex,
                        header->offset,
                        header->value,
                        header->options);
                }
                break;
            default:
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

    if (write && header->width != 8 && header->value >= (UINT64_C(1) << (header->width * 8U))) {
        return kIOReturnBadArgument;
    }
    if (header->space == 1
        && !ApertureContains(ivars, header->memoryIndex, header->offset, header->width)) {
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
    const kern_return_t result = ivars->pciDevice->GetBARInfo(barIndex, &memoryIndex, &size, &type);
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
    const kern_return_t result =
        ivars->pciDevice->GetBusDeviceFunction(&value[0], &value[1], &value[2]);
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
    const kern_return_t result =
        ivars->pciDevice->FindPCICapability(header->identifier, header->searchOffset, &offset);
    if (result != kIOReturnSuccess) {
        return result;
    }
    return MakeUInt64Response(offset, response);
}

// The Swift host sends these SDK values as raw integers; see PCIControlTypes.swift.
static_assert(kIOPCIAccessLatencyTolerantHint == 0x1);
static_assert(kIOPCIDeviceResetTypeHotReset == 0x01 && kIOPCIDeviceResetTypeWarmReset == 0x02);
static_assert(kIOPCIDeviceResetTypeWarmResetDisable == 0x04);
static_assert(kIOPCIDeviceResetTypeWarmResetEnable == 0x08);
static_assert(kIOPCIDeviceResetTypeFunctionReset == 0x10);
static_assert(kIOPCIDeviceResetOptionTerminate == 0x1);
static_assert(kPCIConfigShadowPermanent == 0x80000000U);
static_assert(kPCILinkSpeed_2_5_GTs == 1 && kPCILinkSpeed_32_GTs == 5);
static_assert(kIOPCILinkControlASPMBitsL0s == 0x1 && kIOPCILinkControlASPMBitsL1 == 0x2);
static_assert(kPCIPMCD3Support == 0x0001 && kPCIPMCD1Support == 0x0200);
static_assert(kPCIPMCD2Support == 0x0400 && kPCIPMCPMESupportFromD0 == 0x0800);
static_assert(kPCIPMCPMESupportFromD3Cold == 0x8000);
static_assert(kPCIPMCSPowerStateD3 == 3);

namespace {
    // Combines SDK bit constants, which are signed enumerators, as unsigned bits.
    template<typename... Bits>
    constexpr uint64_t BitMask(Bits... bits) {
        return (static_cast<uint64_t>(bits) | ...);
    }

    constexpr uint32_t kResetOptionMask = kIOPCIDeviceResetOptionTerminate;
    constexpr uint32_t kSaveStateOptionMask = kPCIConfigShadowPermanent;
    constexpr uint64_t kPowerManagementSupportMask = BitMask(
        kPCIPMCPMESupportFromD3Cold,
        kPCIPMCPMESupportFromD3Hot,
        kPCIPMCPMESupportFromD2,
        kPCIPMCPMESupportFromD1,
        kPCIPMCPMESupportFromD0,
        kPCIPMCD2Support,
        kPCIPMCD1Support,
        kPCIPMCD3Support);
    constexpr uint32_t kASPMMask = kIOPCILinkControlASPMBitsL0sL1;

    bool IsResetType(uint32_t type) {
        switch (type) {
            case kIOPCIDeviceResetTypeHotReset:
            case kIOPCIDeviceResetTypeWarmReset:
            case kIOPCIDeviceResetTypeWarmResetDisable:
            case kIOPCIDeviceResetTypeWarmResetEnable:
            case kIOPCIDeviceResetTypeFunctionReset:
                return true;
            default:
                return false;
        }
    }

    bool IsPowerManagementState(uint64_t state) {
        return state == kPCIPMCSPowerStateD0 || state == kPCIPMCSPowerStateD1
               || state == kPCIPMCSPowerStateD2 || state == kPCIPMCSPowerStateD3
               || state == static_cast<uint32_t>(kPCIPMCSDefaultEnableBits);
    }

    bool IsLinkSpeed(uint32_t speed) {
        return speed >= kPCILinkSpeed_2_5_GTs && speed <= kPCILinkSpeed_32_GTs;
    }

    template<typename Value>
    bool ReadScalar(const uint8_t* payload, uint32_t payloadLength, Value* value) {
        if (payloadLength != sizeof(Value)) {
            return false;
        }
        __builtin_memcpy(value, payload, sizeof(Value));
        return true;
    }

    kern_return_t MakeUInt32Response(uint32_t value, OSData** response) {
        *response = OSData::withBytes(&value, sizeof(value));
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }

    // Encodes an optional Boolean property: 0 leaves it unchanged, 1 is false, 2 is true.
    bool SetBooleanProperty(OSDictionary* properties, const char* key, uint8_t value) {
        if (value == 0) {
            return true;
        }
        return properties->setObject(key, value == 2 ? kOSBooleanTrue : kOSBooleanFalse);
    }

    kern_return_t SetDeviceProperties(
        IOPCIDevice* device,
        const SwifterKitPCIPropertiesHeader* header) {
        if (header->reserved != 0 || header->configSpaceVolatile > 2 || header->sleepLinkDisable > 2
            || header->sleepReset > 2
            || (header->configSpaceVolatile == 0 && header->sleepLinkDisable == 0
                && header->sleepReset == 0)) {
            return kIOReturnBadArgument;
        }
        OSDictionary* properties = OSDictionary::withCapacity(3);
        if (properties == nullptr) {
            return kIOReturnNoMemory;
        }
        kern_return_t result = kIOReturnNoMemory;
        if (SetBooleanProperty(
                properties,
                kIOPMPCIConfigSpaceVolatileKey,
                header->configSpaceVolatile)
            && SetBooleanProperty(properties, kIOPMPCISleepLinkDisableKey, header->sleepLinkDisable)
            && SetBooleanProperty(properties, kIOPMPCISleepResetKey, header->sleepReset)) {
            result = device->SetProperties(properties);
        }
        OSSafeReleaseNULL(properties);
        return result;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::PCIControl(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->pciDevice == nullptr || response == nullptr
        || (payloadLength != 0 && payload == nullptr)) {
        return kIOReturnBadArgument;
    }
    *response = nullptr;
    IOPCIDevice* device = ivars->pciDevice;

    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::PCIReset: {
            SwifterKitPCIResetHeader header = {};
            if (!ReadScalar(payload, payloadLength, &header) || !IsResetType(header.type)
                || (header.options & ~kResetOptionMask) != 0) {
                return kIOReturnBadArgument;
            }
            // Reset can change BAR assignments; reload them before the next aperture access.
            ivars->pciAperturesLoaded = false;
    #if SWIFTERKIT_ENABLE_FAST_PATH
            InvalidateFastPathBARs();
    #endif
            // With kIOPCIDeviceResetOptionTerminate, Reset starts the asynchronous termination
            // "but not block on its completion" (IOPCIFamilyDefinitions.h), so it returns and the
            // caller answers Swift with its result. Termination can stop this service
            // concurrently and release ivars->pciDevice, so hold the device across the call.
            device->retain();
            const kern_return_t result = device->Reset(header.type, header.options);
            device->release();
            return result;
        }
        case SwifterKitRuntimeOpcode::PCISaveDeviceState: {
            uint32_t options = 0;
            if (!ReadScalar(payload, payloadLength, &options)
                || (options & ~kSaveStateOptionMask) != 0) {
                return kIOReturnBadArgument;
            }
            return device->SaveDeviceState(options);
        }
        case SwifterKitRuntimeOpcode::PCIRestoreDeviceState:
            if (payloadLength != 0) {
                return kIOReturnBadArgument;
            }
            return device->RestoreDeviceState(0);
        case SwifterKitRuntimeOpcode::PCIHasPowerManagement: {
            uint64_t support = 0;
            if (!ReadScalar(payload, payloadLength, &support)
                || (support & ~kPowerManagementSupportMask) != 0) {
                return kIOReturnBadArgument;
            }
            const bool supported = device->HasPCIPowerManagement(support) == kIOReturnSuccess;
            return MakeUInt32Response(supported ? 1 : 0, response);
        }
        case SwifterKitRuntimeOpcode::PCIEnablePowerManagement: {
            uint64_t state = 0;
            if (!ReadScalar(payload, payloadLength, &state) || !IsPowerManagementState(state)) {
                return kIOReturnBadArgument;
            }
            return device->EnablePCIPowerManagement(state);
        }
        case SwifterKitRuntimeOpcode::PCIGetLinkSpeed: {
            if (payloadLength != 0) {
                return kIOReturnBadArgument;
            }
            IOPCILinkSpeed speed = kPCILinkSpeed_2_5_GTs;
            const kern_return_t result = device->GetLinkSpeed(&speed);
            if (result != kIOReturnSuccess) {
                return result;
            }
            if (!IsLinkSpeed(static_cast<uint32_t>(speed))) {
                return kIOReturnUnsupported;
            }
            return MakeUInt32Response(static_cast<uint32_t>(speed), response);
        }
        case SwifterKitRuntimeOpcode::PCISetLinkSpeed: {
            SwifterKitPCILinkSpeedHeader header = {};
            if (!ReadScalar(payload, payloadLength, &header) || !IsLinkSpeed(header.speed)
                || header.retrain > 1 || header.reserved[0] != 0 || header.reserved[1] != 0
                || header.reserved[2] != 0) {
                return kIOReturnBadArgument;
            }
            return device->SetLinkSpeed(
                static_cast<IOPCILinkSpeed>(header.speed),
                header.retrain != 0);
        }
        case SwifterKitRuntimeOpcode::PCISetASPMState: {
            uint32_t state = 0;
            if (!ReadScalar(payload, payloadLength, &state) || (state & ~kASPMMask) != 0) {
                return kIOReturnBadArgument;
            }
            return device->SetASPMState(state);
        }
        case SwifterKitRuntimeOpcode::PCISetProperties: {
            SwifterKitPCIPropertiesHeader header = {};
            if (!ReadScalar(payload, payloadLength, &header)) {
                return kIOReturnBadArgument;
            }
            return SetDeviceProperties(device, &header);
        }
        default:
            return kIOReturnUnsupported;
    }
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
            return PCIControl(opcode, payload, payloadLength, response);
    }
}

#endif
