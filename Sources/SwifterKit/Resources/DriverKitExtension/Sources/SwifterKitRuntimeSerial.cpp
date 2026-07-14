#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_SERIAL

    #include <DriverKit/IOLib.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    constexpr uint32_t kSerialEventType = 0x0600;

    enum class SerialEventKind : uint32_t {
        Activate = 1,
        Deactivate = 2,
        ReceiveSpaceAvailable = 3,
        TransmitDataAvailable = 4,
        ResetFIFO = 5,
        SendBreak = 6,
        ProgramUART = 7,
        ProgramBaudRate = 8,
        ProgramModemControl = 9,
        ProgramLatencyTimer = 10,
        ProgramFlowControl = 11,
    };

    kern_return_t MapDescriptor(IOMemoryDescriptor* descriptor, IOMemoryMap** map) {
        if (descriptor == nullptr || map == nullptr) {
            return kIOReturnBadArgument;
        }
        return descriptor->CreateMapping(0, 0, 0, 0, 0, map);
    }

    bool ValidRing(uint32_t offset, uint8_t logSize, uint64_t mappingLength) {
        if (logSize == 0 || logSize >= 31) {
            return false;
        }
        return static_cast<uint64_t>(offset) + (uint64_t {1} << logSize) <= mappingLength;
    }

    void CopyIntoRing(
        uint8_t* ring,
        uint32_t ringSize,
        uint32_t producer,
        const uint8_t* source,
        uint32_t length) {
        const uint32_t firstLength = (length < ringSize - producer ? length : ringSize - producer);
        memcpy(ring + producer, source, firstLength);
        if (firstLength != length) {
            memcpy(ring, source + firstLength, length - firstLength);
        }
    }

    bool AppendFromRing(
        OSData* output,
        const uint8_t* ring,
        uint32_t ringSize,
        uint32_t consumer,
        uint32_t length) {
        const uint32_t firstLength = (length < ringSize - consumer ? length : ringSize - consumer);
        if (firstLength != 0 && !output->appendBytes(ring + consumer, firstLength)) {
            return false;
        }
        return firstLength == length || output->appendBytes(ring, length - firstLength);
    }

    kern_return_t QueueSerialEvent(
        SwifterKitRuntimeService* service,
        SerialEventKind kind,
        uint32_t value = 0,
        uint8_t byte0 = 0,
        uint8_t byte1 = 0,
        uint8_t byte2 = 0) {
        const SwifterKitSerialEvent event = {
            .kind = static_cast<uint32_t>(kind),
            .value = value,
            .byte0 = byte0,
            .byte1 = byte1,
            .byte2 = byte2,
            .byte3 = 0,
            .reserved = 0,
        };
        return service->EnqueueEvent(kSerialEventType, &event, sizeof(event));
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartSerial() {
    if (ivars == nullptr || ivars->serialLock == nullptr || ivars->serialConnected) {
        return kIOReturnNotReady;
    }

    kern_return_t result = ConnectQueues(
        &ivars->serialArenaDescriptor,
        &ivars->serialReceiveDescriptor,
        &ivars->serialTransmitDescriptor,
        nullptr,
        nullptr,
        0,
        0,
        0,
        0);
    if (result != kIOReturnSuccess) {
        return result;
    }
    ivars->serialConnected = true;

    result = MapDescriptor(ivars->serialArenaDescriptor, &ivars->serialArenaMap);
    if (result == kIOReturnSuccess) {
        result = MapDescriptor(ivars->serialReceiveDescriptor, &ivars->serialReceiveMap);
    }
    if (result == kIOReturnSuccess) {
        result = MapDescriptor(ivars->serialTransmitDescriptor, &ivars->serialTransmitMap);
    }
    if (result != kIOReturnSuccess) {
        StopSerial();
        return result;
    }

    if (ivars->serialArenaMap->GetLength() < sizeof(driverkit::serial::SerialPortInterface)) {
        StopSerial();
        return kIOReturnBadArgument;
    }
    ivars->serialInterface = reinterpret_cast<driverkit::serial::SerialPortInterface*>(
        ivars->serialArenaMap->GetAddress());
    if (ivars->serialInterface == nullptr
        || !ValidRing(
            ivars->serialInterface->rxqoffset,
            ivars->serialInterface->rxqlogsz,
            ivars->serialReceiveMap->GetLength())
        || !ValidRing(
            ivars->serialInterface->txqoffset,
            ivars->serialInterface->txqlogsz,
            ivars->serialTransmitMap->GetLength())) {
        StopSerial();
        return kIOReturnBadArgument;
    }

    ivars->serialCTS = kSwifterKitSerialInitialCTS;
    ivars->serialDSR = kSwifterKitSerialInitialDSR;
    ivars->serialRI = kSwifterKitSerialInitialRI;
    ivars->serialDCD = kSwifterKitSerialInitialDCD;
    return SetModemStatus(ivars->serialCTS, ivars->serialDSR, ivars->serialRI, ivars->serialDCD);
}

void SwifterKitRuntimeService::StopSerial() {
    if (ivars == nullptr) {
        return;
    }
    ivars->serialInterface = nullptr;
    OSSafeReleaseNULL(ivars->serialTransmitMap);
    OSSafeReleaseNULL(ivars->serialReceiveMap);
    OSSafeReleaseNULL(ivars->serialArenaMap);
    if (ivars->serialConnected) {
        (void)DisconnectQueues();
        ivars->serialConnected = false;
    }
    OSSafeReleaseNULL(ivars->serialTransmitDescriptor);
    OSSafeReleaseNULL(ivars->serialReceiveDescriptor);
    OSSafeReleaseNULL(ivars->serialArenaDescriptor);
}

kern_return_t SwifterKitRuntimeService::SerialCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->serialInterface == nullptr || response == nullptr
        || (payload == nullptr && payloadLength != 0)) {
        return kIOReturnNotReady;
    }
    *response = nullptr;

    IOLockLock(ivars->serialLock);
    auto* serial = ivars->serialInterface;
    kern_return_t result = kIOReturnSuccess;
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::SerialEnqueueReceive: {
            if (payloadLength == 0) {
                result = kIOReturnBadArgument;
                break;
            }
            const uint32_t size = uint32_t {1} << serial->rxqlogsz;
            const uint32_t mask = size - 1;
            const uint32_t producer = serial->rxPI & mask;
            const uint32_t consumer = serial->rxCI & mask;
            const uint32_t available = (consumer - producer - 1) & mask;
            if (payloadLength > available) {
                result = kIOReturnNoSpace;
                break;
            }
            auto* ring = reinterpret_cast<uint8_t*>(ivars->serialReceiveMap->GetAddress())
                         + serial->rxqoffset;
            CopyIntoRing(ring, size, producer, payload, payloadLength);
            __atomic_store_n(&serial->rxPI, (producer + payloadLength) & mask, __ATOMIC_RELEASE);
            break;
        }
        case SwifterKitRuntimeOpcode::SerialDequeueTransmit: {
            if (payloadLength != sizeof(uint32_t)) {
                result = kIOReturnBadArgument;
                break;
            }
            uint32_t maximumLength = 0;
            memcpy(&maximumLength, payload, sizeof(maximumLength));
            if (maximumLength == 0) {
                result = kIOReturnBadArgument;
                break;
            }
            const uint32_t size = uint32_t {1} << serial->txqlogsz;
            const uint32_t mask = size - 1;
            const uint32_t producer = serial->txPI & mask;
            const uint32_t consumer = serial->txCI & mask;
            const uint32_t length =
                (maximumLength < ((producer - consumer) & mask) ? maximumLength
                                                                : ((producer - consumer) & mask));
            OSData* data = OSData::withCapacity(length);
            if (data == nullptr) {
                result = kIOReturnNoMemory;
                break;
            }
            const auto* ring =
                reinterpret_cast<const uint8_t*>(ivars->serialTransmitMap->GetAddress())
                + serial->txqoffset;
            if (!AppendFromRing(data, ring, size, consumer, length)) {
                data->release();
                result = kIOReturnNoMemory;
                break;
            }
            __atomic_store_n(&serial->txCI, (consumer + length) & mask, __ATOMIC_RELEASE);
            *response = data;
            break;
        }
        case SwifterKitRuntimeOpcode::SerialSetModemStatus:
            if (payloadLength != 4 || payload[0] > 1 || payload[1] > 1 || payload[2] > 1
                || payload[3] > 1) {
                result = kIOReturnBadArgument;
                break;
            }
            ivars->serialCTS = payload[0] != 0;
            ivars->serialDSR = payload[1] != 0;
            ivars->serialRI = payload[2] != 0;
            ivars->serialDCD = payload[3] != 0;
            break;
        case SwifterKitRuntimeOpcode::SerialReportReceiveErrors:
            if (payloadLength != 4 || (payload[0] & ~uint8_t {0x0F}) != 0 || payload[1] != 0
                || payload[2] != 0 || payload[3] != 0) {
                result = kIOReturnBadArgument;
            }
            break;
        default:
            result = kIOReturnUnsupported;
            break;
    }
    IOLockUnlock(ivars->serialLock);

    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(*response);
        return result;
    }
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::SerialEnqueueReceive:
            RxDataAvailable();
            break;
        case SwifterKitRuntimeOpcode::SerialDequeueTransmit:
            TxFreeSpaceAvailable();
            break;
        case SwifterKitRuntimeOpcode::SerialSetModemStatus:
            result = SetModemStatus(
                ivars->serialCTS,
                ivars->serialDSR,
                ivars->serialRI,
                ivars->serialDCD);
            break;
        case SwifterKitRuntimeOpcode::SerialReportReceiveErrors:
            result = RxError(
                (payload[0] & 1) != 0,
                (payload[0] & 2) != 0,
                (payload[0] & 4) != 0,
                (payload[0] & 8) != 0);
            break;
        default:
            break;
    }
    return result;
}

void SwifterKitRuntimeService::RxFreeSpaceAvailable_Impl() {
    (void)QueueSerialEvent(this, SerialEventKind::ReceiveSpaceAvailable);
}

void SwifterKitRuntimeService::TxDataAvailable_Impl() {
    (void)QueueSerialEvent(this, SerialEventKind::TransmitDataAvailable);
}

kern_return_t SwifterKitRuntimeService::HwActivate_Impl() {
    return QueueSerialEvent(this, SerialEventKind::Activate);
}

kern_return_t SwifterKitRuntimeService::HwDeactivate_Impl() {
    return QueueSerialEvent(this, SerialEventKind::Deactivate);
}

kern_return_t SwifterKitRuntimeService::HwResetFIFO_Impl(bool tx, bool rx) {
    return QueueSerialEvent(
        this,
        SerialEventKind::ResetFIFO,
        (tx ? uint32_t {1} : 0) | (rx ? uint32_t {2} : 0));
}

kern_return_t SwifterKitRuntimeService::HwSendBreak_Impl(bool sendBreak) {
    return QueueSerialEvent(this, SerialEventKind::SendBreak, sendBreak ? 1 : 0);
}

kern_return_t SwifterKitRuntimeService::HwProgramUART_Impl(
    uint32_t baudRate,
    uint8_t dataBits,
    uint8_t halfStopBits,
    uint8_t parity) {
    return QueueSerialEvent(
        this,
        SerialEventKind::ProgramUART,
        baudRate,
        dataBits,
        halfStopBits,
        parity);
}

kern_return_t SwifterKitRuntimeService::HwProgramBaudRate_Impl(uint32_t baudRate) {
    return QueueSerialEvent(this, SerialEventKind::ProgramBaudRate, baudRate);
}

kern_return_t SwifterKitRuntimeService::HwProgramMCR_Impl(bool dtr, bool rts) {
    return QueueSerialEvent(
        this,
        SerialEventKind::ProgramModemControl,
        (dtr ? uint32_t {1} : 0) | (rts ? uint32_t {2} : 0));
}

kern_return_t
    SwifterKitRuntimeService::HwGetModemStatus_Impl(bool* cts, bool* dsr, bool* ri, bool* dcd) {
    if (ivars == nullptr || cts == nullptr || dsr == nullptr || ri == nullptr || dcd == nullptr) {
        return kIOReturnBadArgument;
    }
    IOLockLock(ivars->serialLock);
    *cts = ivars->serialCTS;
    *dsr = ivars->serialDSR;
    *ri = ivars->serialRI;
    *dcd = ivars->serialDCD;
    IOLockUnlock(ivars->serialLock);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeService::HwProgramLatencyTimer_Impl(uint32_t latency) {
    return QueueSerialEvent(this, SerialEventKind::ProgramLatencyTimer, latency);
}

kern_return_t
    SwifterKitRuntimeService::HwProgramFlowControl_Impl(uint32_t flags, uint8_t xon, uint8_t xoff) {
    return QueueSerialEvent(this, SerialEventKind::ProgramFlowControl, flags, xon, xoff);
}

#endif
