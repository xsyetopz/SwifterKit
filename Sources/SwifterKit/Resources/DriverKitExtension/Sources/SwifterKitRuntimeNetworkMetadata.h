#ifndef SwifterKitRuntimeNetworkMetadata_h
#define SwifterKitRuntimeNetworkMetadata_h

#include "SwifterKitRuntimeConfiguration.h"
#if SWIFTERKIT_ENABLE_NETWORKING
    #include <NetworkingDriverKit/NetworkingDriverKit.h>
    #include <string.h>

    #include "SwifterKitRuntimeProtocol.h"

    // The DriverKit 24.4 SDK does not declare the packet VLAN accessors; 25.5 and later do.
    #if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5
        #define SWIFTERKIT_NETWORK_HAS_VLAN 1
    #else
        #define SWIFTERKIT_NETWORK_HAS_VLAN 0
    #endif

// Packet metadata contract:
// - A transmit event carries SwifterKitNetworkTransmitMetadata, read from the packet, before the
//   frame. Members the running DriverKit lacks (getDataOff before 23, getVlanTag before 24, or
//   an SDK without the VLAN accessors) fall back to the older member or report nothing.
// - A received frame carries SwifterKitNetworkReceivePacket. Every field is validated here after
//   Swift validates it, and the packet's per-frame state (offset, length, link header, checksum,
//   multicast, timestamp) is always written, because the pool recycles packets.
// - A packet returns to the pool it came from, which getPacketBufferPool reports.

// Returns a packet to its own pool.
inline void SwifterKitReturnNetworkPacket(IOUserNetworkPacket* packet) {
    IOUserNetworkPacketBufferPool* pool =
        packet == nullptr ? nullptr : packet->getPacketBufferPool();
    if (pool != nullptr)
        (void)pool->deallocatePacket(packet);
}

inline void SwifterKitReadTransmitMetadata(
    IOUserNetworkPacket* packet,
    SwifterKitNetworkTransmitMetadata* metadata) {
    *metadata = {};
    if (__builtin_available(driverkit 23.0, *))
        metadata->dataOffset = static_cast<uint32_t>(packet->getDataOff());
    else
        metadata->dataOffset = packet->getDataOffset();
    uint32_t flags = 0;
    if (packet->isLinkMulticast())
        flags |= kSwifterKitNetworkPacketLinkMulticast;
    if (packet->isLinkBroadcast())
        flags |= kSwifterKitNetworkPacketLinkBroadcast;
    if (packet->isTimestampRequested())
        flags |= kSwifterKitNetworkPacketTimestampRequested;
    if (packet->isTransportTrafficBackground())
        flags |= kSwifterKitNetworkPacketTrafficBackground;
    if (packet->isTransportTrafficRealtime())
        flags |= kSwifterKitNetworkPacketTrafficRealtime;
    uint64_t time = 0;
    if (packet->getTimestamp(&time) == kIOReturnSuccess) {
        flags |= kSwifterKitNetworkPacketHasTimestamp;
        metadata->timestamp = time;
    }
    time = 0;
    if (packet->getExpiryTime(&time) == kIOReturnSuccess && time != 0) {
        flags |= kSwifterKitNetworkPacketHasExpiryTime;
        metadata->expiryTime = time;
    }
    #if SWIFTERKIT_NETWORK_HAS_VLAN
    if (__builtin_available(driverkit 24.0, *)) {
        uint16_t tag = 0;
        if (packet->getVlanTag(&tag)) {
            flags |= kSwifterKitNetworkPacketHasVLANTag;
            metadata->vlanTag = tag;
        }
    }
    #endif
    IOUserNetworkPacketTxChecksumFlags checksum = 0;
    uint16_t start = 0;
    uint16_t stuff = 0;
    if (packet->getTxChecksumInfo(&checksum, &start, &stuff) == kIOReturnSuccess) {
        metadata->checksumFlags = checksum;
        metadata->checksumStart = start;
        metadata->checksumStuff = stuff;
    }
    uint16_t segmentSize = 0;
    IOUserNetworkPacketTSOFlags tso = 0;
    if (packet->getTSOInfo(&segmentSize, &tso) == kIOReturnSuccess) {
        metadata->tsoFlags = tso;
        metadata->tsoSegmentSize = segmentSize;
    }
    metadata->flags = flags;
    metadata->serviceClass = packet->getServiceClass();
    metadata->traceID = packet->getTraceID();
    metadata->offloadFlags = packet->getTxCsumFlags();
    metadata->maximumSegmentSize = packet->getMSS();
    metadata->linkHeaderLength = packet->getLinkHeaderLength();
    metadata->memorySegmentOffset = packet->getMemorySegmentOffset();
    metadata->dataIOVirtualAddress = packet->getDataIOVirtualAddress();
}

// Returns whether Swift's receive entry is well formed for a buffer of bufferSize bytes.
inline bool SwifterKitIsValidReceivePacket(
    const SwifterKitNetworkReceivePacket& entry,
    uint32_t bufferSize) {
    const bool hasOffset = (entry.flags & kSwifterKitNetworkPacketHasDataOffset) != 0;
    const bool hasLRO = (entry.flags & kSwifterKitNetworkPacketHasLRO) != 0;
    return entry.length != 0 && entry.length <= bufferSize
           && (entry.flags & ~kSwifterKitNetworkReceiveFlags) == 0
           && (hasOffset ? entry.dataOffset <= bufferSize - entry.length : entry.dataOffset == 0)
           && (entry.checksumFlags & ~kSwifterKitNetworkRxChecksumFlags) == 0
           && (hasLRO ? (entry.lroFlags & ~kSwifterKitNetworkLROFlags) == 0 && entry.lroFlags != 0
                            && entry.lroSegmentCount != 0
                      : entry.lroFlags == 0 && entry.lroSegmentCount == 0)
           && ((entry.flags & kSwifterKitNetworkPacketHasVLANTag) != 0 || entry.vlanTag == 0)
           && ((entry.flags & kSwifterKitNetworkPacketHasTimestamp) != 0 || entry.timestamp == 0)
           && ((entry.flags & kSwifterKitNetworkPacketHasTraceEvent) != 0 || entry.traceEvent == 0)
           && entry.reserved0 == 0 && entry.reserved1 == 0;
}

// Copies a validated frame into an empty receive packet and writes its metadata.
inline IOReturn SwifterKitFillReceivePacket(
    IOUserNetworkPacket* packet,
    const SwifterKitNetworkReceivePacket& entry,
    const uint8_t* frame,
    uint32_t bufferSize) {
    const uint64_t address = packet->getDataVirtualAddress();
    if (address == 0)
        return kIOReturnNotReady;
    uint32_t offset = packet->getDataOffset();
    if ((entry.flags & kSwifterKitNetworkPacketHasDataOffset) != 0)
        offset = entry.dataOffset;
    if (offset > bufferSize - entry.length)
        return kIOReturnBadArgument;
    IOReturn result = kIOReturnSuccess;
    if (__builtin_available(driverkit 23.0, *))
        result = packet->setDataOffAndLen(offset, entry.length);
    else if (offset <= UINT16_MAX)
        result = packet->setDataOffsetAndLength(static_cast<uint16_t>(offset), entry.length);
    else
        result = kIOReturnUnsupported;
    if (result != kIOReturnSuccess)
        return result;
    memcpy(reinterpret_cast<void*>(address + offset), frame, entry.length);
    result = packet->setLinkHeaderLength(entry.linkHeaderLength);
    if (result == kIOReturnSuccess)
        result =
            packet->setIsLinkMulticast((entry.flags & kSwifterKitNetworkPacketLinkMulticast) != 0);
    if (result == kIOReturnSuccess)
        result = packet->setRxChecksumInfo(entry.checksumFlags, entry.checksumValue);
    if (result == kIOReturnSuccess && (entry.flags & kSwifterKitNetworkPacketHasLRO) != 0)
        result = packet->setLROInfo(entry.lroFlags, entry.lroSegmentCount);
    if (result == kIOReturnSuccess)
        result = (entry.flags & kSwifterKitNetworkPacketHasTimestamp) != 0
                     ? packet->setTimestamp(entry.timestamp)
                     : packet->clearTimestamp();
    if (result == kIOReturnSuccess && (entry.flags & kSwifterKitNetworkPacketHasVLANTag) != 0) {
    #if SWIFTERKIT_NETWORK_HAS_VLAN
        if (__builtin_available(driverkit 24.0, *))
            packet->setVlanTag(entry.vlanTag);
        else
            result = kIOReturnUnsupported;
    #else
        result = kIOReturnUnsupported;
    #endif
    }
    if (result == kIOReturnSuccess && (entry.flags & kSwifterKitNetworkPacketWake) != 0)
        packet->setWakeFlag();
    if (result == kIOReturnSuccess && (entry.flags & kSwifterKitNetworkPacketHasTraceEvent) != 0)
        packet->traceEvent(entry.traceEvent);
    return result;
}

// Records Swift's outcome on a transmitted packet before it returns through the completion queue.
inline void SwifterKitCompleteTransmitPacket(
    IOUserNetworkPacket* packet,
    int32_t status,
    uint32_t flags,
    uint64_t timestamp,
    uint32_t traceEvent) {
    packet->setCompletionStatus(status);
    if ((flags & kSwifterKitNetworkPacketHasTimestamp) != 0)
        (void)packet->setTimestamp(timestamp);
    if ((flags & kSwifterKitNetworkPacketHasTraceEvent) != 0)
        packet->traceEvent(traceEvent);
}
#endif

#endif
