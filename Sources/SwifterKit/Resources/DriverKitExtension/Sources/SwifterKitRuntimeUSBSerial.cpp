#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_USB_SERIAL

    #include <DriverKit/IOLib.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

// IOUserUSBSerial packet hooks. The superclass calls handleRxPacket for each completed bulk IN
// transfer, before copying the packet into the receive queue. It calls handleInterruptPacket
// for each completed interrupt IN transfer, before resubmitting it. The runtime passes every
// packet through unchanged and, when configured, copies it to Swift as lossy usbSerialPacket
// events. A packet larger than one event is split into consecutive events in order.

namespace {
    // SwifterKitUSBSerialPacketKind comes from RuntimeSchema+Storage.swift.
    using USBSerialPacketKind = SwifterKitUSBSerialPacketKind;

    struct __attribute__((packed)) USBSerialPacketHeader {
        uint32_t kind;
        uint32_t length;
    };
    static_assert(sizeof(USBSerialPacketHeader) == 8);

    constexpr uint32_t kMaximumPacketChunk = kSwifterKitRuntimeMaximumMessageSize
                                             - kSwifterKitRuntimeHeaderSize - sizeof(uint32_t)
                                             - sizeof(USBSerialPacketHeader);
    static_assert(kMaximumPacketChunk == 65500);

    void DeliverPacket(
        SwifterKitRuntimeService* service,
        USBSerialPacketKind kind,
        const uint8_t* packet,
        uint32_t size) {
        if (packet == nullptr || size == 0) {
            return;
        }
        const uint32_t capacity = sizeof(USBSerialPacketHeader)
                                  + (size < kMaximumPacketChunk ? size : kMaximumPacketChunk);
        auto* event = static_cast<uint8_t*>(IOMalloc(capacity));
        if (event == nullptr) {
            return;
        }
        for (uint32_t offset = 0; offset < size;) {
            const uint32_t remaining = size - offset;
            const uint32_t length =
                remaining < kMaximumPacketChunk ? remaining : kMaximumPacketChunk;
            const USBSerialPacketHeader header = {
                .kind = static_cast<uint32_t>(kind),
                .length = length,
            };
            memcpy(event, &header, sizeof(header));
            memcpy(event + sizeof(header), packet + offset, length);
            if (service->EnqueueEvent(
                    kSwifterKitEventUSBSerialPacket,
                    event,
                    static_cast<uint32_t>(sizeof(header) + length))
                != kIOReturnSuccess) {
                break;
            }
            offset += length;
        }
        IOFree(event, capacity);
    }
}  // namespace

void SwifterKitRuntimeService::handleRxPacket(uint8_t*& packet, uint32_t& size) {
    super::handleRxPacket(packet, size);
    if constexpr (kSwifterKitUSBSerialDeliversReceivedPackets) {
        DeliverPacket(this, USBSerialPacketKind::Received, packet, size);
    }
}

void SwifterKitRuntimeService::handleInterruptPacket(const uint8_t* packet, uint32_t size) {
    super::handleInterruptPacket(packet, size);
    if constexpr (kSwifterKitUSBSerialDeliversInterruptPackets) {
        DeliverPacket(this, USBSerialPacketKind::Interrupt, packet, size);
    }
}

#endif
