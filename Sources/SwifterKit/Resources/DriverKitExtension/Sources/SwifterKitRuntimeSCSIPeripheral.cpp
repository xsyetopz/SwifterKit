#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_SCSI_PERIPHERAL

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <string.h>

    #include "SwifterKitRuntimeProtocol.h"

namespace {
    constexpr uint32_t kMaximumPeripheralDataLength = 61'440;

    #if SWIFTERKIT_SCSI_PERIPHERAL_TYPE == 0
    using PeripheralOutParameters = SCSIType00OutParameters;
    using PeripheralInParameters = SCSIType00InParameters;
    #elif SWIFTERKIT_SCSI_PERIPHERAL_TYPE == 5
    using PeripheralOutParameters = SCSIType05OutParameters;
    using PeripheralInParameters = SCSIType05InParameters;
    #elif SWIFTERKIT_SCSI_PERIPHERAL_TYPE == 7
    using PeripheralOutParameters = SCSIType07OutParameters;
    using PeripheralInParameters = SCSIType07InParameters;
    #else
        #error Unsupported SCSI peripheral type
    #endif

    class MappedBuffer {
    public:
        ~MappedBuffer() {
            OSSafeReleaseNULL(map_);
            OSSafeReleaseNULL(descriptor_);
        }

        kern_return_t
            Create(uint64_t direction, uint32_t length, const uint8_t* initialBytes = nullptr) {
            if (length == 0) {
                return kIOReturnSuccess;
            }
            kern_return_t result =
                IOBufferMemoryDescriptor::Create(direction, length, 0, &descriptor_);
            if (result != kIOReturnSuccess || descriptor_ == nullptr) {
                return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
            }
            result = descriptor_->SetLength(length);
            if (result == kIOReturnSuccess) {
                result = descriptor_->CreateMapping(0, 0, 0, length, 0, &map_);
            }
            if (result != kIOReturnSuccess || map_ == nullptr || map_->GetAddress() == 0) {
                return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
            }
            if (initialBytes != nullptr) {
                memcpy(Bytes(), initialBytes, length);
            } else {
                memset(Bytes(), 0, length);
            }
            return kIOReturnSuccess;
        }

        uint64_t Address() const {
            return map_ == nullptr ? 0 : map_->GetAddress();
        }

        uint8_t* Bytes() const {
            return reinterpret_cast<uint8_t*>(static_cast<uintptr_t>(Address()));
        }

        MappedBuffer(const MappedBuffer&) = delete;
        MappedBuffer& operator=(const MappedBuffer&) = delete;
        MappedBuffer() = default;

    private:
        IOBufferMemoryDescriptor* descriptor_ = nullptr;
        IOMemoryMap* map_ = nullptr;
    };

    bool ReservedBytesAreZero(const uint8_t* bytes, uint32_t count) {
        for (uint32_t index = 0; index < count; ++index) {
            if (bytes[index] != 0) {
                return false;
            }
        }
        return true;
    }

    kern_return_t DataResponse(const void* bytes, uint32_t length, OSData** response) {
        if (response == nullptr || (length != 0 && bytes == nullptr)) {
            return kIOReturnBadArgument;
        }
        *response = OSData::withBytes(bytes, length);
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }
}  // namespace

    #if SWIFTERKIT_SCSI_PERIPHERAL_TYPE == 5
kern_return_t SwifterKitRuntimeService::UserInitializeDeviceSupport_Impl(bool* result) {
    #else
kern_return_t SwifterKitRuntimeService::UserDetermineDeviceCharacteristics_Impl(bool* result) {
    #endif
    if (result == nullptr) {
        return kIOReturnBadArgument;
    }
    *result = kSwifterKitSCSIPeripheralInitializationSucceeds;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::SCSIPeripheralCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (response == nullptr) {
        return kIOReturnBadArgument;
    }
    *response = nullptr;

    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::SCSIPeripheralSuspendServices:
            return payloadLength == 0 ? UserSuspendServices() : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::SCSIPeripheralResumeServices:
            return payloadLength == 0 ? UserResumeServices() : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::SCSIPeripheralReset: {
            if (payloadLength != 0) {
                return kIOReturnBadArgument;
            }
            SCSIServiceResponse serviceResponse = kSCSIServiceResponse_Request_In_Process;
            const kern_return_t result = UserResetDevice(&serviceResponse);
            if (result != kIOReturnSuccess) {
                return result;
            }
            const uint32_t rawResponse = static_cast<uint32_t>(serviceResponse);
            return DataResponse(&rawResponse, sizeof(rawResponse), response);
        }
        case SwifterKitRuntimeOpcode::SCSIPeripheralReportMediumBlockSize: {
            if (payloadLength != 0) {
                return kIOReturnBadArgument;
            }
            uint64_t blockSize = 0;
            const kern_return_t result = UserReportMediumBlockSize(&blockSize);
            return result == kIOReturnSuccess
                       ? DataResponse(&blockSize, sizeof(blockSize), response)
                       : result;
        }
        case SwifterKitRuntimeOpcode::SCSIPeripheralSendCDB:
            break;
        default:
            return kIOReturnUnsupported;
    }

    if (payload == nullptr || payloadLength < sizeof(SwifterKitSCSIPeripheralCommandHeader)) {
        return kIOReturnBadArgument;
    }
    const auto* header = reinterpret_cast<const SwifterKitSCSIPeripheralCommandHeader*>(payload);
    const uint8_t* outboundBytes = payload + sizeof(*header);
    const uint32_t outboundLength = payloadLength - sizeof(*header);
    if (header->requestedDataLength > kMaximumPeripheralDataLength
        || header->transferDirection > kSCSIDataTransfer_FromTargetToInitiator
        || !ReservedBytesAreZero(header->reserved, sizeof(header->reserved))) {
        return kIOReturnBadArgument;
    }

    uint64_t bufferDirection = 0;
    const uint8_t* initialBytes = nullptr;
    switch (header->transferDirection) {
        case kSCSIDataTransfer_NoDataTransfer:
            if (header->requestedDataLength != 0 || outboundLength != 0) {
                return kIOReturnBadArgument;
            }
            break;
        case kSCSIDataTransfer_FromInitiatorToTarget:
            if (header->requestedDataLength == 0 || outboundLength != header->requestedDataLength) {
                return kIOReturnBadArgument;
            }
            bufferDirection = kIOMemoryDirectionOut;
            initialBytes = outboundBytes;
            break;
        case kSCSIDataTransfer_FromTargetToInitiator:
            if (header->requestedDataLength == 0 || outboundLength != 0) {
                return kIOReturnBadArgument;
            }
            bufferDirection = kIOMemoryDirectionIn;
            break;
        default:
            return kIOReturnBadArgument;
    }

    MappedBuffer dataBuffer;
    kern_return_t result =
        dataBuffer.Create(bufferDirection, header->requestedDataLength, initialBytes);
    if (result != kIOReturnSuccess) {
        return result;
    }
    MappedBuffer senseBuffer;
    result = senseBuffer.Create(kIOMemoryDirectionIn, header->requestedSenseLength);
    if (result != kIOReturnSuccess) {
        return result;
    }

    PeripheralOutParameters command = {};
    command.fLogicalUnitNumber = header->logicalUnitNumber;
    command.fTimeoutDuration = header->timeoutMilliseconds;
    memcpy(
        command.fCommandDescriptorBlock,
        header->commandDescriptorBlock,
        sizeof(command.fCommandDescriptorBlock));
    command.fRequestedByteCountOfTransfer = header->requestedDataLength;
    command.fBufferDirection = static_cast<uint8_t>(bufferDirection);
    command.fDataTransferDirection = header->transferDirection;
    command.fSenseLengthRequested = header->requestedSenseLength;
    command.fDataBufferAddr = dataBuffer.Address();
    command.fSenseBufferAddr = senseBuffer.Address();

    PeripheralInParameters input = {};
    result = UserSendCDB(command, &input);
    if (result != kIOReturnSuccess
        || input.fRealizedByteCountOfTransfer > header->requestedDataLength) {
        return result == kIOReturnSuccess ? kIOReturnBadArgument : result;
    }

    const uint32_t dataLength = header->transferDirection == kSCSIDataTransfer_FromTargetToInitiator
                                    ? static_cast<uint32_t>(input.fRealizedByteCountOfTransfer)
                                    : 0;
    const uint8_t senseLength = input.fSenseDataValid ? header->requestedSenseLength : 0;
    const SwifterKitSCSIPeripheralResponseHeader responseHeader = {
        .taskStatus = static_cast<uint32_t>(input.fCompletionStatus),
        .serviceResponse = static_cast<uint32_t>(input.fServiceResponse),
        .realizedDataLength = input.fRealizedByteCountOfTransfer,
        .senseDataValid = input.fSenseDataValid ? uint8_t {1} : uint8_t {0},
        .senseLength = senseLength,
        .reserved = 0,
        .dataLength = dataLength,
    };
    OSData* output = OSData::withCapacity(sizeof(responseHeader) + dataLength + senseLength);
    if (output == nullptr || !output->appendBytes(&responseHeader, sizeof(responseHeader))
        || (dataLength != 0 && !output->appendBytes(dataBuffer.Bytes(), dataLength))
        || (senseLength != 0 && !output->appendBytes(senseBuffer.Bytes(), senseLength))) {
        OSSafeReleaseNULL(output);
        return kIOReturnNoMemory;
    }
    *response = output;
    return kIOReturnSuccess;
}

#endif
