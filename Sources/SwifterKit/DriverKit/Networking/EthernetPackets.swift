import Foundation

/// A NetworkingDriverKit packet service class (`IOUserNetworkServiceClass`).
public struct EthernetServiceClass: RawRepresentable, Sendable, Hashable {
  /// The unmodified service class value.
  public let rawValue: UInt32
  /// Preserves a service class value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// Background system-initiated traffic.
  public static let backgroundSystem = Self(rawValue: 0x0008_0090)
  /// Background traffic.
  public static let background = Self(rawValue: 0x0010_0080)
  /// Best-effort traffic.
  public static let bestEffort = Self(rawValue: 0x0000_0000)
  /// Responsive data.
  public static let responsiveData = Self(rawValue: 0x0018_0010)
  /// Operations, administration, and management traffic.
  public static let operationsAndManagement = Self(rawValue: 0x0020_0020)
  /// Multimedia audio and video streaming.
  public static let audioVideo = Self(rawValue: 0x0028_0120)
  /// Responsive multimedia audio and video.
  public static let responsiveAudioVideo = Self(rawValue: 0x0030_0110)
  /// Interactive video.
  public static let interactiveVideo = Self(rawValue: 0x0038_0100)
  /// Interactive voice.
  public static let interactiveVoice = Self(rawValue: 0x0040_0180)
  /// Network control traffic.
  public static let networkControl = Self(rawValue: 0x0048_0190)
  /// Every service class the SDK declares.
  public static let all: [Self] = [
    .backgroundSystem, .background, .bestEffort, .responsiveData, .operationsAndManagement,
    .audioVideo, .responsiveAudioVideo, .interactiveVideo, .interactiveVoice, .networkControl,
  ]
}

/// Transmit checksum offload requests (`IOUserNetworkPacketTxChecksumFlags`).
public struct EthernetTransmitChecksumFlags: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// Compute a partial checksum from ``EthernetTransmitMetadata/checksumStart``.
  public static let partial = Self(rawValue: 0x0001)
  /// Invert a computed checksum of zero.
  public static let zeroInvert = Self(rawValue: 0x0002)
  /// Compute the IPv4 header checksum.
  public static let ipHeader = Self(rawValue: 0x0004)
  /// Compute the TCP checksum over IPv4.
  public static let tcpIPv4 = Self(rawValue: 0x0008)
  /// Compute the UDP checksum over IPv4.
  public static let udpIPv4 = Self(rawValue: 0x0010)
  /// Compute the TCP checksum over IPv6.
  public static let tcpIPv6 = Self(rawValue: 0x0020)
  /// Compute the UDP checksum over IPv6.
  public static let udpIPv6 = Self(rawValue: 0x0040)
}

/// Receive checksum results (`IOUserNetworkPacketRxChecksumFlags`).
public struct EthernetReceiveChecksumFlags: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// The hardware checked the IP header checksum.
  public static let ipChecked = Self(rawValue: 0x0100)
  /// The IP header checksum is valid.
  public static let ipValid = Self(rawValue: 0x0200)
  /// ``EthernetReceiveMetadata/checksumValue`` holds the data checksum.
  public static let dataValid = Self(rawValue: 0x0400)
  /// The data checksum includes the pseudo-header.
  public static let pseudoHeader = Self(rawValue: 0x0800)
  /// Every flag the SDK declares.
  public static let all: Self = [.ipChecked, .ipValid, .dataValid, .pseudoHeader]
}

/// TCP segmentation offload requests (`IOUserNetworkPacketTSOFlags`).
public struct EthernetTSOFlags: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// Segment an IPv4 TCP packet.
  public static let ipv4 = Self(rawValue: 0x0010_0000)
  /// Segment an IPv6 TCP packet.
  public static let ipv6 = Self(rawValue: 0x0020_0000)
}

/// Large receive offload results (`IOUserNetworkPacketLROFlags`).
public struct EthernetLROFlags: OptionSet, Sendable, Hashable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }
  /// The packet coalesces IPv4 segments.
  public static let ipv4 = Self(rawValue: 0x01)
  /// The packet coalesces IPv6 segments.
  public static let ipv6 = Self(rawValue: 0x02)
  /// Every flag the SDK declares.
  public static let all: Self = [.ipv4, .ipv6]
}

/// Everything the networking stack recorded on an outgoing `IOUserNetworkPacket`.
public struct EthernetTransmitMetadata: Sendable, Hashable {
  /// Offset of the frame in the packet buffer (`getDataOff`).
  public var dataOffset: UInt32 = 0
  /// Link-layer header length (`getLinkHeaderLength`).
  public var linkHeaderLength: UInt8 = 0
  /// Service class (`getServiceClass`).
  public var serviceClass = EthernetServiceClass.bestEffort
  /// Trace identifier (`getTraceID`).
  public var traceID: UInt32 = 0
  /// Link-level multicast destination (`isLinkMulticast`).
  public var isLinkMulticast = false
  /// Link-level broadcast destination (`isLinkBroadcast`).
  public var isLinkBroadcast = false
  /// The stack asks for a transmit timestamp (`isTimestampRequested`).
  public var isTimestampRequested = false
  /// Background transport traffic (`isTransportTrafficBackground`).
  public var isBackgroundTraffic = false
  /// Real-time transport traffic (`isTransportTrafficRealtime`).
  public var isRealtimeTraffic = false
  /// Timestamp already on the packet (`getTimestamp`).
  public var timestamp: UInt64?
  /// Time after which the packet should be dropped (`getExpiryTime`).
  public var expiryTime: UInt64?
  /// Hardware VLAN tag (`getVlanTag`, DriverKit 24 and later, built with the 25.5 SDK or newer).
  public var vlanTag: UInt16?
  /// Checksum offload requests (`getTxChecksumInfo`).
  public var checksumFlags: EthernetTransmitChecksumFlags = []
  /// Where a partial checksum starts (`getTxChecksumInfo`).
  public var checksumStart: UInt16 = 0
  /// Where a partial checksum is stored (`getTxChecksumInfo`).
  public var checksumStuffOffset: UInt16 = 0
  /// Every checksum and segmentation offload bit (`getTxCsumFlags`).
  public var offloadFlags: UInt32 = 0
  /// Segmentation requests (`getTSOInfo`).
  public var tsoFlags: EthernetTSOFlags = []
  /// Segment size for segmentation (`getTSOInfo`).
  public var tsoSegmentSize: UInt16 = 0
  /// Maximum segment size (`getMSS`).
  public var maximumSegmentSize: UInt16 = 0
  /// Offset of the buffer in its pool memory segment (`getMemorySegmentOffset`).
  public var memorySegmentOffset: UInt64 = 0
  /// Device-visible address of the frame (`getDataIOVirtualAddress`).
  public var dataIOVirtualAddress: UInt64 = 0

  /// Creates empty metadata.
  public init() {}

  static let runtimeSize = RuntimeNetworkLimits.transmitMetadataSize

  init(runtimeData data: Data) throws {
    guard data.count == Self.runtimeSize else { throw EthernetRuntimeError.invalidPayload }
    let flags: UInt32 = try data.readRuntimeInteger(at: 4)
    let reserved: UInt8 = try data.readRuntimeInteger(at: 39)
    guard flags & ~RuntimeNetworkPacketFlag.transmit == 0, reserved == 0 else {
      throw EthernetRuntimeError.invalidPayload
    }
    dataOffset = try data.readRuntimeInteger(at: 0)
    serviceClass = EthernetServiceClass(rawValue: try data.readRuntimeInteger(at: 8))
    traceID = try data.readRuntimeInteger(at: 12)
    checksumFlags = EthernetTransmitChecksumFlags(rawValue: try data.readRuntimeInteger(at: 16))
    checksumStart = try data.readRuntimeInteger(at: 20)
    checksumStuffOffset = try data.readRuntimeInteger(at: 22)
    offloadFlags = try data.readRuntimeInteger(at: 24)
    tsoFlags = EthernetTSOFlags(rawValue: try data.readRuntimeInteger(at: 28))
    tsoSegmentSize = try data.readRuntimeInteger(at: 32)
    maximumSegmentSize = try data.readRuntimeInteger(at: 34)
    let tag: UInt16 = try data.readRuntimeInteger(at: 36)
    linkHeaderLength = try data.readRuntimeInteger(at: 38)
    let time: UInt64 = try data.readRuntimeInteger(at: 40)
    let expiry: UInt64 = try data.readRuntimeInteger(at: 48)
    memorySegmentOffset = try data.readRuntimeInteger(at: 56)
    dataIOVirtualAddress = try data.readRuntimeInteger(at: 64)
    isLinkMulticast = flags & RuntimeNetworkPacketFlag.linkMulticast.rawValue != 0
    isLinkBroadcast = flags & RuntimeNetworkPacketFlag.linkBroadcast.rawValue != 0
    isTimestampRequested = flags & RuntimeNetworkPacketFlag.timestampRequested.rawValue != 0
    isBackgroundTraffic = flags & RuntimeNetworkPacketFlag.trafficBackground.rawValue != 0
    isRealtimeTraffic = flags & RuntimeNetworkPacketFlag.trafficRealtime.rawValue != 0
    timestamp = flags & RuntimeNetworkPacketFlag.hasTimestamp.rawValue != 0 ? time : nil
    expiryTime = flags & RuntimeNetworkPacketFlag.hasExpiryTime.rawValue != 0 ? expiry : nil
    vlanTag = flags & RuntimeNetworkPacketFlag.hasVLANTag.rawValue != 0 ? tag : nil
  }
}

/// Per-frame state a driver sets on a received `IOUserNetworkPacket`.
public struct EthernetReceiveMetadata: Sendable, Hashable {
  /// Offset of the frame in the packet buffer, or nil for the pool's offset (`setDataOffAndLen`).
  public var dataOffset: UInt32?
  /// Link-layer header length (`setLinkHeaderLength`).
  public var linkHeaderLength: UInt8
  /// Link-level multicast destination (`setIsLinkMulticast`).
  public var isLinkMulticast: Bool
  /// Checksum results (`setRxChecksumInfo`).
  public var checksumFlags: EthernetReceiveChecksumFlags
  /// Data checksum when ``checksumFlags`` contains ``EthernetReceiveChecksumFlags/dataValid``.
  public var checksumValue: UInt16
  /// Coalesced segments (`setLROInfo`); empty when the frame is not coalesced.
  public var lroFlags: EthernetLROFlags
  /// Number of coalesced segments; nonzero exactly when ``lroFlags`` is not empty.
  public var lroSegmentCount: UInt8
  /// Receive timestamp (`setTimestamp`), or nil to clear it (`clearTimestamp`).
  public var timestamp: UInt64?
  /// Hardware VLAN tag (`setVlanTag`, DriverKit 24 and later, built with the 25.5 SDK or newer).
  public var vlanTag: UInt16?
  /// Marks the frame as the one that woke the system (`setWakeFlag`).
  public var isWakePacket: Bool
  /// Trace event posted for the packet (`traceEvent`).
  public var traceEvent: UInt32?

  /// Creates receive metadata.
  public init(
    dataOffset: UInt32? = nil,
    linkHeaderLength: UInt8 = 14,
    isLinkMulticast: Bool = false,
    checksumFlags: EthernetReceiveChecksumFlags = [],
    checksumValue: UInt16 = 0,
    lroFlags: EthernetLROFlags = [],
    lroSegmentCount: UInt8 = 0,
    timestamp: UInt64? = nil,
    vlanTag: UInt16? = nil,
    isWakePacket: Bool = false,
    traceEvent: UInt32? = nil
  ) {
    self.dataOffset = dataOffset
    self.linkHeaderLength = linkHeaderLength
    self.isLinkMulticast = isLinkMulticast
    self.checksumFlags = checksumFlags
    self.checksumValue = checksumValue
    self.lroFlags = lroFlags
    self.lroSegmentCount = lroSegmentCount
    self.timestamp = timestamp
    self.vlanTag = vlanTag
    self.isWakePacket = isWakePacket
    self.traceEvent = traceEvent
  }

  var isValid: Bool {
    EthernetReceiveChecksumFlags.all.isSuperset(of: checksumFlags)
      && EthernetLROFlags.all.isSuperset(of: lroFlags) && lroFlags.isEmpty == (lroSegmentCount == 0)
  }

  func runtimeHeader(length: Int) -> Data {
    var flags: UInt32 = isLinkMulticast ? RuntimeNetworkPacketFlag.linkMulticast.rawValue : 0
    if timestamp != nil { flags |= RuntimeNetworkPacketFlag.hasTimestamp.rawValue }
    if vlanTag != nil { flags |= RuntimeNetworkPacketFlag.hasVLANTag.rawValue }
    if dataOffset != nil { flags |= RuntimeNetworkPacketFlag.hasDataOffset.rawValue }
    if !lroFlags.isEmpty { flags |= RuntimeNetworkPacketFlag.hasLRO.rawValue }
    if traceEvent != nil { flags |= RuntimeNetworkPacketFlag.hasTraceEvent.rawValue }
    if isWakePacket { flags |= RuntimeNetworkPacketFlag.wake.rawValue }
    var data = Data(capacity: 40)
    data.appendRuntimeInteger(UInt32(length))
    data.appendRuntimeInteger(dataOffset ?? 0)
    data.appendRuntimeInteger(flags)
    data.appendRuntimeInteger(checksumFlags.rawValue)
    data.appendRuntimeInteger(checksumValue)
    data.appendRuntimeInteger(vlanTag ?? 0)
    data.append(contentsOf: [linkHeaderLength, lroFlags.rawValue, lroSegmentCount, 0])
    data.appendRuntimeInteger(traceEvent ?? 0)
    data.appendRuntimeInteger(UInt32(0))
    data.appendRuntimeInteger(timestamp ?? 0)
    return data
  }
}

/// A received frame and the metadata to set on its packet.
public struct EthernetReceivedFrame: Sendable, Hashable {
  /// Complete Ethernet frame.
  public let frame: Data
  /// Packet state to set with the frame.
  public let metadata: EthernetReceiveMetadata

  /// Creates a received frame.
  public init(frame: Data, metadata: EthernetReceiveMetadata = EthernetReceiveMetadata()) {
    self.frame = frame
    self.metadata = metadata
  }
}

/// The outcome of one transmit, recorded on its packet before it returns to the stack.
public struct EthernetTransmitCompletion: Sendable, Hashable {
  /// Identifier from ``EthernetTransmitRequest/requestID``.
  public let requestID: UInt32
  /// `IOReturn` status (`setCompletionStatus`); zero for success.
  public let status: Int32
  /// Transmit timestamp (`setTimestamp`), typically when the stack requested one.
  public let timestamp: UInt64?
  /// Trace event posted for the packet (`traceEvent`).
  public let traceEvent: UInt32?

  /// Creates a transmit completion.
  public init(
    requestID: UInt32,
    status: Int32 = 0,
    timestamp: UInt64? = nil,
    traceEvent: UInt32? = nil
  ) {
    self.requestID = requestID
    self.status = status
    self.timestamp = timestamp
    self.traceEvent = traceEvent
  }
}

/// One of the four packet queues the extension registers with the interface.
public enum EthernetPacketQueue: UInt32, Sendable, Hashable, CaseIterable {
  /// Frames the stack submits for transmission.
  case transmitSubmission = 0
  /// Transmitted frames returning to the stack.
  case transmitCompletion = 1
  /// Empty buffers the stack supplies for reception.
  case receiveSubmission = 2
  /// Received frames delivered to the stack.
  case receiveCompletion = 3
}

/// A packet buffer pool the extension creates, which ``DriverContext/mapPacketPool(_:)`` maps
/// read-only into the host.
///
/// Without a separate receive pool (a nil ``EthernetDeviceConfiguration/receivePacketCount``)
/// both values map the one shared pool.
public enum EthernetPacketPool: UInt32, Sendable, Hashable, CaseIterable {
  /// The pool that backs transmitted frames.
  case transmit = 0
  /// The pool that backs received frames.
  case receive = 1
}

/// A private `SIOCSDRVSPEC` or `SIOCGDRVSPEC` request that `processInterfaceCommand` received.
///
/// The request's data pointer belongs to the caller's address space, so only the interface
/// name, driver command, and data length reach Swift. Answer it exactly once with
/// ``DriverContext/completeEthernetInterfaceCommand(requestID:status:)`` within two seconds.
public struct EthernetInterfaceCommand: Sendable, Hashable {
  /// Identifier to answer.
  public let requestID: UInt32
  /// Interface name, such as `en5`.
  public let interfaceName: String
  /// Driver-private command number (`ifd_cmd`).
  public let command: UInt64
  /// Length of the caller's data buffer (`ifd_len`).
  public let length: UInt64

  init(requestID: UInt32, data: Data) throws {
    guard requestID != 0, data.count == 32 else { throw EthernetRuntimeError.invalidPayload }
    self.requestID = requestID
    let name = data.prefix(16).prefix { $0 != 0 }
    guard let text = String(bytes: name, encoding: .utf8) else {
      throw EthernetRuntimeError.invalidPayload
    }
    interfaceName = text
    command = try data.readRuntimeInteger(at: 16)
    length = try data.readRuntimeInteger(at: 24)
  }
}
