import Foundation

/// A six-octet Ethernet hardware address.
public struct EthernetAddress: Sendable, Hashable {
  /// Address octets in network order.
  public let bytes: [UInt8]

  /// Creates a valid Ethernet address from six octets.
  public init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8, _ e: UInt8, _ f: UInt8) {
    self.bytes = [a, b, c, d, e, f]
  }
}

/// A NetworkingDriverKit Ethernet media word.
public struct EthernetMedia: RawRepresentable, Sendable, Hashable {
  /// The unmodified NetworkingDriverKit media word.
  public let rawValue: UInt32
  /// Preserves a NetworkingDriverKit media word.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Automatic Ethernet media selection.
  public static let automatic = Self(rawValue: 0x20)
  /// No active Ethernet media.
  public static let none = Self(rawValue: 0x22)
  /// 10BASE-T Ethernet.
  public static let base10T = Self(rawValue: 0x23)
  /// 100BASE-TX Ethernet.
  public static let base100TX = Self(rawValue: 0x26)
  /// 1000BASE-T Ethernet.
  public static let base1000T = Self(rawValue: 0x30)
  /// 2.5GBASE-T Ethernet.
  public static let base2500T = Self(rawValue: 0x36)
  /// 5GBASE-T Ethernet.
  public static let base5000T = Self(rawValue: 0x37)
  /// 10GBASE-T Ethernet.
  public static let base10GT = Self(rawValue: 0x35)

  /// Full-duplex media option bit.
  public static let fullDuplex: UInt32 = 0x0010_0000
  /// Half-duplex media option bit.
  public static let halfDuplex: UInt32 = 0x0020_0000
  /// Link-level flow-control media option bit.
  public static let flowControl: UInt32 = 0x0040_0000
}

/// Static Ethernet interface and packet-pool configuration.
public struct EthernetDeviceConfiguration: Sendable, Hashable {
  /// Initial unicast hardware address.
  public let hardwareAddress: EthernetAddress
  /// Largest frame payload accepted by the interface.
  public let maximumTransferUnit: UInt32
  /// Bytes allocated for each native packet buffer.
  public let packetBufferSize: UInt32
  /// Number of packets and backing buffers in the native pool.
  public let packetCount: UInt32
  /// Capacity of each native submission and completion queue.
  public let queueCapacity: UInt32
  /// Hardware-assist flags advertised to NetworkingDriverKit.
  public let hardwareAssists: UInt32
  /// Media words offered to the networking stack.
  public let media: [EthernetMedia]
  /// Media selected when the interface is first created.
  public let initialMedia: EthernetMedia
  /// Whether the hardware supports wake-on-magic-packet.
  public let supportsWakeOnMagicPacket: Bool
  /// Smallest MTU the stack may select through `setMaxTransferUnit`.
  public let minimumTransferUnit: UInt32
  /// Feature flags added to the family's `getFeatureFlags` result.
  public let featureFlags: EthernetFeatureFlags
  /// Segmentation limits; required when ``hardwareAssists`` includes TSO.
  public let tsoOptions: EthernetTSOOptions?
  /// Whether the interface supports software VLAN tagging.
  public let supportsSoftwareVLAN: Bool
  /// Bytes the stack reserves before each transmitted frame.
  public let transmitHeadroom: UInt16
  /// Bytes the stack reserves after each transmitted frame.
  public let transmitTailroom: UInt16
  /// Data offset the hardware expects in every transmitted packet.
  public let transmitDataOffset: UInt16
  /// Interface subfamily reported to the stack.
  public let interfaceSubFamily: EthernetInterfaceSubFamily
  /// BSD name prefix of one to seven lowercase letters, or nil for `en`.
  public let bsdNamePrefix: String?
  /// Fixed BSD unit number, or nil to let the stack assign one.
  public let bsdUnitNumber: Int32?
  /// Whether the interface attaches an Ethernet packet filter tap (`DLT_EN10MB`).
  public let packetTap: Bool
  /// Buffer and DMA options for the native packet pools.
  public let poolOptions: EthernetPacketPoolOptions
  /// Packets in a separate receive pool, or nil to share the transmit pool.
  public let receivePacketCount: UInt32?
  /// Hybrid-polling parameters, or nil for interrupt-driven operation only.
  public let packetPolling: EthernetPacketPolling?
  /// Service class of the transmit submission queue, or nil for none; applied on DriverKit 24
  /// and later through `IOUserNetworkTxSubmissionQueue::Create(pool, owner, serviceClass, ...)`.
  public let transmitServiceClass: EthernetServiceClass?

  /// The ``hardwareAssists`` bits as a typed set.
  public var assists: EthernetHardwareAssists { EthernetHardwareAssists(rawValue: hardwareAssists) }

  /// Creates static Ethernet interface and packet-pool metadata.
  public init(
    hardwareAddress: EthernetAddress,
    maximumTransferUnit: UInt32 = 1_500,
    packetBufferSize: UInt32 = 16_384,
    packetCount: UInt32 = 64,
    queueCapacity: UInt32 = 32,
    hardwareAssists: UInt32 = 0,
    media: [EthernetMedia] = [.automatic, .base1000T],
    initialMedia: EthernetMedia = .automatic,
    supportsWakeOnMagicPacket: Bool = false,
    minimumTransferUnit: UInt32 = 68,
    featureFlags: EthernetFeatureFlags = [],
    tsoOptions: EthernetTSOOptions? = nil,
    supportsSoftwareVLAN: Bool = false,
    transmitHeadroom: UInt16 = 0,
    transmitTailroom: UInt16 = 0,
    transmitDataOffset: UInt16 = 0,
    interfaceSubFamily: EthernetInterfaceSubFamily = .any,
    bsdNamePrefix: String? = nil,
    bsdUnitNumber: Int32? = nil,
    packetTap: Bool = false,
    poolOptions: EthernetPacketPoolOptions = EthernetPacketPoolOptions(),
    receivePacketCount: UInt32? = nil,
    packetPolling: EthernetPacketPolling? = nil,
    transmitServiceClass: EthernetServiceClass? = nil
  ) {
    self.hardwareAddress = hardwareAddress
    self.maximumTransferUnit = maximumTransferUnit
    self.packetBufferSize = packetBufferSize
    self.packetCount = packetCount
    self.queueCapacity = queueCapacity
    self.hardwareAssists = hardwareAssists
    self.media = media
    self.initialMedia = initialMedia
    self.supportsWakeOnMagicPacket = supportsWakeOnMagicPacket
    self.minimumTransferUnit = minimumTransferUnit
    self.featureFlags = featureFlags
    self.tsoOptions = tsoOptions
    self.supportsSoftwareVLAN = supportsSoftwareVLAN
    self.transmitHeadroom = transmitHeadroom
    self.transmitTailroom = transmitTailroom
    self.transmitDataOffset = transmitDataOffset
    self.interfaceSubFamily = interfaceSubFamily
    self.bsdNamePrefix = bsdNamePrefix
    self.bsdUnitNumber = bsdUnitNumber
    self.packetTap = packetTap
    self.poolOptions = poolOptions
    self.receivePacketCount = receivePacketCount
    self.packetPolling = packetPolling
    self.transmitServiceClass = transmitServiceClass
  }
}

/// An outgoing frame that remains pending until Swift completes it.
public struct EthernetTransmitRequest: Sendable, Hashable {
  /// Opaque identifier used exactly once for completion.
  public let requestID: UInt32
  /// Complete Ethernet frame supplied by the networking stack.
  public let frame: Data
  /// Offload, timestamp, VLAN, and trace state the stack recorded on the packet.
  public let metadata: EthernetTransmitMetadata

  /// Creates an outgoing frame request.
  public init(
    requestID: UInt32,
    frame: Data,
    metadata: EthernetTransmitMetadata = EthernetTransmitMetadata()
  ) {
    self.requestID = requestID
    self.frame = frame
    self.metadata = metadata
  }
}

/// A hardware-programming or transmit request from NetworkingDriverKit.
public enum EthernetEvent: Sendable, Hashable {
  /// Reports whether the network interface is enabled.
  case interfaceEnabled(Bool)
  /// Carries an outgoing frame and its request identifier for Swift completion.
  case transmit(EthernetTransmitRequest)
  /// Reports whether promiscuous mode is enabled.
  case promiscuousMode(Bool)
  /// Supplies the multicast destination addresses that the interface accepts.
  case multicastAddresses([EthernetAddress])
  /// Reports whether the interface accepts all multicast traffic.
  case allMulticastMode(Bool)
  /// Reports whether wake on magic packet is enabled.
  case wakeOnMagicPacket(Bool)
  /// Supplies the maximum frame size in bytes for the interface.
  case maximumTransferUnit(UInt32)
  /// Supplies the hardware assist bit mask requested by the network stack.
  case hardwareAssists(UInt32)
  /// Supplies the media word selected for the interface.
  case selectedMedia(EthernetMedia)
  /// Reports the power state value from NetworkingDriverKit.
  case powerState(UInt32)
  /// Supplies the six-byte Ethernet address of the interface.
  case hardwareAddress(EthernetAddress)
  /// The stack changed the assists in `mask` to the values in `assists`.
  case hardwareAssistsChanged(assists: EthernetHardwareAssists, mask: EthernetHardwareAssists)
  /// The poller started (true) or stopped (false) polling.
  case polling(Bool)
  /// The packet filter tap directions changed.
  case packetTap(EthernetPacketTapMode)
  /// The family handed over NIC proxy offload data.
  case nicProxyConfiguration(EthernetNICProxyConfiguration)
  /// A private interface command waits for an answer through
  /// ``DriverContext/completeEthernetInterfaceCommand(requestID:status:)``.
  case interfaceCommand(EthernetInterfaceCommand)

  init(runtimePayload: Data) throws {
    let headerSize = RuntimeNetworkLimits.eventHeaderSize
    guard runtimePayload.count >= headerSize else { throw EthernetRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let requestID: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let value: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    let length: UInt32 = try runtimePayload.readRuntimeInteger(at: 12)
    guard Int(length) == runtimePayload.count - headerSize else {
      throw EthernetRuntimeError.invalidPayload
    }
    let data = runtimePayload.subdata(in: headerSize..<runtimePayload.count)
    guard let eventKind = RuntimeNetworkEventKind(rawValue: kind) else {
      throw EthernetRuntimeError.invalidEventKind(kind)
    }
    switch eventKind {
    case .interfaceEnabled:
      self = .interfaceEnabled(try Self.boolean(value, requestID: requestID, data: data))
    case .transmit:
      let size = EthernetTransmitMetadata.runtimeSize
      guard requestID != 0, value != 0, Int(value) == data.count - size else {
        throw EthernetRuntimeError.invalidPayload
      }
      let metadata = try EthernetTransmitMetadata(runtimeData: Data(data.prefix(size)))
      self = .transmit(
        EthernetTransmitRequest(
          requestID: requestID,
          frame: Data(data.dropFirst(size)),
          metadata: metadata
        )
      )
    case .promiscuousMode:
      self = .promiscuousMode(try Self.boolean(value, requestID: requestID, data: data))
    case .multicastAddresses:
      guard requestID == 0, value == UInt32(data.count / 6), data.count.isMultiple(of: 6) else {
        throw EthernetRuntimeError.invalidPayload
      }
      self = .multicastAddresses(
        stride(from: 0, to: data.count, by: 6).map { offset in
          EthernetAddress(
            data[offset],
            data[offset + 1],
            data[offset + 2],
            data[offset + 3],
            data[offset + 4],
            data[offset + 5]
          )
        }
      )
    case .allMulticastMode:
      self = .allMulticastMode(try Self.boolean(value, requestID: requestID, data: data))
    case .wakeOnMagicPacket:
      self = .wakeOnMagicPacket(try Self.boolean(value, requestID: requestID, data: data))
    case .maximumTransferUnit:
      try Self.requireScalar(requestID, data)
      self = .maximumTransferUnit(value)
    case .hardwareAssists:
      try Self.requireScalar(requestID, data)
      self = .hardwareAssists(value)
    case .selectedMedia:
      try Self.requireScalar(requestID, data)
      self = .selectedMedia(EthernetMedia(rawValue: value))
    case .powerState:
      try Self.requireScalar(requestID, data)
      self = .powerState(value)
    case .hardwareAddress:
      guard requestID == 0, value == 1, data.count == 6 else {
        throw EthernetRuntimeError.invalidPayload
      }
      self = .hardwareAddress(EthernetAddress(data[0], data[1], data[2], data[3], data[4], data[5]))
    case .hardwareAssistsChanged:
      guard requestID == 0, data.count == 4 else { throw EthernetRuntimeError.invalidPayload }
      let mask: UInt32 = try data.readRuntimeInteger(at: 0)
      guard value & ~mask == 0 else { throw EthernetRuntimeError.invalidPayload }
      self = .hardwareAssistsChanged(
        assists: EthernetHardwareAssists(rawValue: value),
        mask: EthernetHardwareAssists(rawValue: mask)
      )
    case .polling: self = .polling(try Self.boolean(value, requestID: requestID, data: data))
    case .packetTap:
      try Self.requireScalar(requestID, data)
      guard value & ~RuntimeNetworkTapMode([.input, .output]).rawValue == 0 else {
        throw EthernetRuntimeError.invalidPayload
      }
      self = .packetTap(EthernetPacketTapMode(rawValue: value))
    case .nicProxyConfiguration:
      guard requestID == 0, value == UInt32(data.count) else {
        throw EthernetRuntimeError.invalidPayload
      }
      self = .nicProxyConfiguration(try EthernetNICProxyConfiguration(data: data))
    case .interfaceCommand:
      guard value == 0 else { throw EthernetRuntimeError.invalidPayload }
      self = .interfaceCommand(try EthernetInterfaceCommand(requestID: requestID, data: data))
    }
  }

  private static func boolean(_ value: UInt32, requestID: UInt32, data: Data) throws -> Bool {
    try requireScalar(requestID, data)
    guard value <= 1 else { throw EthernetRuntimeError.invalidPayload }
    return value == 1
  }

  private static func requireScalar(_ requestID: UInt32, _ data: Data) throws {
    guard requestID == 0, data.isEmpty else { throw EthernetRuntimeError.invalidPayload }
  }
}

/// A malformed or unsupported Ethernet runtime value.
public enum EthernetRuntimeError: Error, Sendable, Equatable {
  /// The command contains an empty Ethernet frame.
  case emptyFrame
  /// The frame or runtime payload exceeds its size limit.
  case frameTooLarge
  /// The runtime payload has an invalid size, value, or field combination.
  case invalidPayload
  /// The event kind has no matching `RuntimeNetworkEventKind` value.
  case invalidEventKind(UInt32)
  /// The link status contains unsupported status bits.
  case invalidLinkStatus
  /// The link quality value is outside the NetworkingDriverKit range.
  case invalidLinkQuality
  /// An effective bandwidth exceeds its maximum bandwidth.
  case invalidBandwidths
  /// The packet polling rate or interval is outside its valid range.
  case invalidPollingParameters
  /// A packet batch has an invalid count or completion identifier.
  case invalidBatch
  /// Packet metadata contains values that the runtime cannot encode.
  case invalidPacketMetadata
}
