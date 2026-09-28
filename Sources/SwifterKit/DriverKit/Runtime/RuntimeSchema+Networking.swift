// Networking wire constants: event kinds, packet flags and masks, batch and poller bounds.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeSchema.h`, which
// `SwifterKitRuntimeProtocol.h` and the `SwifterKitRuntimeNetwork*.cpp` sources read, so neither
// side spells a value twice.

/// Bounds and layout sizes the Ethernet commands and events share with the extension.
enum RuntimeNetworkLimits {
  /// The most frames one receive or completion batch carries.
  static let maximumBatch = 32
  /// The largest poll interval Swift may request, in nanoseconds: one second.
  static let maximumPollInterval: UInt64 = 1_000_000_000
  /// The bytes of `SwifterKitNetworkEventHeader`, which begins every network event.
  static let eventHeaderSize = 16
  /// The bytes of `SwifterKitNetworkTransmitMetadata`, which precedes each transmitted frame.
  static let transmitMetadataSize = 72
  /// The largest packet buffer: a full frame plus its metadata must fit in one transmit event.
  static let maximumPacketBufferSize =
    RuntimeSchema.maximumMessageSize - RuntimeSchema.headerSize - 4 - eventHeaderSize
    - transmitMetadataSize
  /// The packet queues the extension registers, ``EthernetPacketQueue``.
  static let queueCount = EthernetPacketQueue.allCases.count
}

/// What a network event reports, the `kind` of its `SwifterKitNetworkEventHeader`.
enum RuntimeNetworkEventKind: UInt32, CaseIterable {
  case interfaceEnabled = 1
  case transmit = 2
  case promiscuousMode = 3
  case multicastAddresses = 4
  case allMulticastMode = 5
  case wakeOnMagicPacket = 6
  case maximumTransferUnit = 7
  case hardwareAssists = 8
  case selectedMedia = 9
  case powerState = 10
  case hardwareAddress = 11
  case hardwareAssistsChanged = 12
  case polling = 13
  case packetTap = 14
  case nicProxyConfiguration = 15
  case interfaceCommand = 16
}

/// Packet flag bits. Transmit metadata reports the transmit bits. A received packet sets the
/// receive bits, and a transmit completion the completion bits.
enum RuntimeNetworkPacketFlag: UInt32, CaseIterable {
  case linkMulticast = 0x0001
  case linkBroadcast = 0x0002
  case timestampRequested = 0x0004
  case trafficBackground = 0x0008
  case trafficRealtime = 0x0010
  case hasTimestamp = 0x0020
  case hasExpiryTime = 0x0040
  case hasVLANTag = 0x0080
  case hasDataOffset = 0x0100
  case hasLRO = 0x0200
  case hasTraceEvent = 0x0400
  case wake = 0x0800

  /// The bits transmit metadata may carry.
  static let transmit = bits([
    .linkMulticast, .linkBroadcast, .timestampRequested, .trafficBackground, .trafficRealtime,
    .hasTimestamp, .hasExpiryTime, .hasVLANTag,
  ])
  /// The bits a received packet may carry.
  static let receive = bits([
    .linkMulticast, .hasTimestamp, .hasVLANTag, .hasDataOffset, .hasLRO, .hasTraceEvent, .wake,
  ])
  /// The bits a transmit completion may carry.
  static let completion = bits([.hasTimestamp, .hasTraceEvent])
  /// Every receive checksum bit, ``EthernetReceiveChecksumFlags/all``.
  static let receiveChecksum = EthernetReceiveChecksumFlags.all.rawValue
  /// Every large receive offload bit, ``EthernetLROFlags/all``.
  static let largeReceiveOffload = UInt32(EthernetLROFlags.all.rawValue)

  private static func bits(_ flags: [Self]) -> UInt32 { flags.reduce(0) { $0 | $1.rawValue } }
}

/// Berkeley packet filter tap directions. The public type carries the wire values.
typealias RuntimeNetworkTapMode = EthernetPacketTapMode
