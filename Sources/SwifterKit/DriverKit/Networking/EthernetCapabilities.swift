import Foundation

/// NetworkingDriverKit hardware assists (`kIOUserNetworkHWAssist*`) an Ethernet interface offers.
public struct EthernetHardwareAssists: OptionSet, Sendable, Hashable {
  /// The unmodified `kIOUserNetworkHWAssist*` bits.
  public let rawValue: UInt32
  /// Preserves `kIOUserNetworkHWAssist*` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// IPv4 header checksum on transmit.
  public static let transmitIPv4HeaderChecksum = Self(rawValue: 0x0000_0001)
  /// TCP checksum on transmit.
  public static let transmitTCPChecksum = Self(rawValue: 0x0000_0002)
  /// UDP checksum on transmit.
  public static let transmitUDPChecksum = Self(rawValue: 0x0000_0004)
  /// Software VLAN tagging with a VLAN-sized MTU.
  public static let softwareVLAN = Self(rawValue: 0x0002_0000)
  /// IPv4 TCP segmentation offload. Requires ``EthernetTSOOptions``.
  public static let tso4 = Self(rawValue: 0x0020_0000)
  /// IPv6 TCP segmentation offload. Requires ``EthernetTSOOptions``.
  public static let tso6 = Self(rawValue: 0x0040_0000)
  /// Hardware packet timestamps.
  public static let hardwareTimestamp = Self(rawValue: 0x0100_0000)
  /// Software packet timestamps.
  public static let softwareTimestamp = Self(rawValue: 0x0200_0000)
  /// Wake on magic packet.
  public static let wakeOnMagicPacket = Self(rawValue: 0x0400_0000)
  /// NIC proxy offload while the host sleeps.
  public static let nicProxy = Self(rawValue: 0x0800_0000)
  /// Large receive offload.
  public static let lro = Self(rawValue: 0x1000_0000)
  /// Receive checksum validation.
  public static let receiveChecksum = Self(rawValue: 0x2000_0000)
  /// Large receive offload that reports its segment count.
  public static let lroSegmentCount = Self(rawValue: 0x4000_0000)

  /// Every assist NetworkingDriverKit defines.
  public static let all: Self = [
    .transmitIPv4HeaderChecksum, .transmitTCPChecksum, .transmitUDPChecksum, .softwareVLAN, .tso4,
    .tso6, .hardwareTimestamp, .softwareTimestamp, .wakeOnMagicPacket, .nicProxy, .lro,
    .receiveChecksum, .lroSegmentCount,
  ]
}

/// NetworkingDriverKit interface feature flags (`kIOUserNetworkFeature*`).
public struct EthernetFeatureFlags: OptionSet, Sendable, Hashable {
  /// The unmodified `kIOUserNetworkFeature*` bits.
  public let rawValue: UInt32
  /// Preserves `kIOUserNetworkFeature*` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Software VLAN support.
  public static let softwareVLAN = Self(rawValue: 0x0002_0000)
  /// Hardware packet timestamps.
  public static let hardwareTimestamp = Self(rawValue: 0x0100_0000)
  /// Software packet timestamps.
  public static let softwareTimestamp = Self(rawValue: 0x0200_0000)
  /// Wake on magic packet.
  public static let wakeOnMagicPacket = Self(rawValue: 0x0400_0000)
  /// NIC proxy offload; the family then sends ``EthernetEvent/nicProxyConfiguration(_:)``.
  public static let nicProxy = Self(rawValue: 0x0800_0000)

  /// Every flag NetworkingDriverKit defines.
  public static let all: Self = [
    .softwareVLAN, .hardwareTimestamp, .softwareTimestamp, .wakeOnMagicPacket, .nicProxy,
  ]
}

/// TCP segmentation offload limits returned from `getTSOOptions`.
public struct EthernetTSOOptions: Sendable, Hashable {
  /// Largest IPv4 segment the hardware accepts, in bytes.
  public let maximumSegmentSizeIPv4: UInt32
  /// Largest IPv6 segment the hardware accepts, in bytes.
  public let maximumSegmentSizeIPv6: UInt32
  /// Creates TCP segmentation offload limits.
  public init(maximumSegmentSizeIPv4: UInt32, maximumSegmentSizeIPv6: UInt32) {
    self.maximumSegmentSizeIPv4 = maximumSegmentSizeIPv4
    self.maximumSegmentSizeIPv6 = maximumSegmentSizeIPv6
  }
}

/// The interface subfamily returned from `getInterfaceSubFamily`.
public struct EthernetInterfaceSubFamily: RawRepresentable, Sendable, Hashable {
  /// The unmodified `IFNET_SUBFAMILY_*` value.
  public let rawValue: UInt32
  /// Preserves an `IFNET_SUBFAMILY_*` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// The family default.
  public static let any = Self(rawValue: 0)
  /// An Ethernet adapter attached over USB.
  public static let usb = Self(rawValue: 1)
  /// An Ethernet adapter attached over Thunderbolt.
  public static let thunderbolt = Self(rawValue: 4)
}

/// `IOUserNetworkPacketBufferPool` creation flags (`PoolFlag*`).
public struct EthernetPacketPoolFlags: OptionSet, Sendable, Hashable {
  /// The unmodified `PoolFlag*` bits.
  public let rawValue: UInt32
  /// Preserves `PoolFlag*` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Backs every buffer with one memory segment.
  public static let singleMemorySegment = Self(rawValue: 0x0000_0002)
  /// Restricts device DMA to writes into the buffers.
  public static let ioDirectionIn = Self(rawValue: 0x0000_0200)
  /// Restricts device DMA to reads from the buffers.
  public static let ioDirectionOut = Self(rawValue: 0x0000_0400)
  /// Marks the pool as belonging to a virtual interface.
  public static let virtualDevice = Self(rawValue: 0x0000_1000)
  /// Maps the pool into device I/O space.
  public static let mapToDevice = Self(rawValue: 0x2000_0000)

  /// Every flag a SwifterKit pool may add; the runtime always maps pools into the extension.
  public static let all: Self = [
    .singleMemorySegment, .ioDirectionIn, .ioDirectionOut, .virtualDevice, .mapToDevice,
  ]
}

/// Sizing and DMA options for the native packet buffer pools.
public struct EthernetPacketPoolOptions: Sendable, Hashable {
  /// Backing buffers per pool, or nil for one buffer per packet.
  public let bufferCount: UInt32?
  /// Bytes in each backing memory segment, or 0 for the family default.
  public let memorySegmentSize: UInt32
  /// Extra pool flags; the runtime always adds `PoolFlagMapToDext`.
  public let flags: EthernetPacketPoolFlags
  /// Widest DMA address the device can generate, from 32 through 64 bits.
  public let maximumAddressBits: UInt8

  /// Creates packet pool options.
  public init(
    bufferCount: UInt32? = nil,
    memorySegmentSize: UInt32 = 0,
    flags: EthernetPacketPoolFlags = [],
    maximumAddressBits: UInt8 = 64
  ) {
    self.bufferCount = bufferCount
    self.memorySegmentSize = memorySegmentSize
    self.flags = flags
    self.maximumAddressBits = maximumAddressBits
  }
}

/// Hybrid-polling parameters for the runtime's `IOUserNetworkPacketPoller`.
///
/// While polling runs, the poller drains transmit work on each tick and the runtime delivers
/// ``EthernetEvent/polling(_:)`` so Swift can mask device interrupts and harvest received frames.
public struct EthernetPacketPolling: Sendable, Hashable {
  /// Interface data rate in bits per second.
  public let dataRate: UInt64
  /// Poll interval in nanoseconds, or 0 for the family default.
  public let pollInterval: UInt64
  /// Whether the poller starts enabled.
  public let enabled: Bool

  /// Largest accepted poll interval: one second.
  public static let maximumPollInterval = RuntimeNetworkLimits.maximumPollInterval

  /// Creates poller parameters.
  public init(dataRate: UInt64, pollInterval: UInt64 = 0, enabled: Bool = true) {
    self.dataRate = dataRate
    self.pollInterval = pollInterval
    self.enabled = enabled
  }

  var isValid: Bool { dataRate > 0 && pollInterval <= Self.maximumPollInterval }
}

/// A NetworkingDriverKit link status (`kIOUserNetworkLinkStatus*`).
public struct EthernetLinkStatus: RawRepresentable, Sendable, Hashable {
  /// The unmodified `kIOUserNetworkLinkStatus*` value.
  public let rawValue: UInt32
  /// Preserves a `kIOUserNetworkLinkStatus*` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// The link is down.
  public static let inactive = Self(rawValue: 0x0000_0001)
  /// The link is up.
  public static let active = Self(rawValue: 0x0000_0003)

  /// Reports that the link came back on the same network after a wake.
  public var wakingOnSameNetwork: Self { Self(rawValue: rawValue | 0x0000_0004) }
  /// Notifies the stack even when the status did not change.
  public var forcingNotification: Self { Self(rawValue: rawValue | 0x8000_0000) }

  var isValid: Bool {
    let base = rawValue & ~UInt32(0x8000_0004)
    return base == Self.inactive.rawValue || base == Self.active.rawValue
  }
}

/// A NetworkingDriverKit link quality (`kIOUserNetworkLinkQuality*`).
public struct EthernetLinkQuality: RawRepresentable, Sendable, Hashable {
  /// The unmodified quality: -2, -1, or 0 through 100.
  public let rawValue: Int32
  /// Preserves a `kIOUserNetworkLinkQuality*` value.
  public init(rawValue: Int32) { self.rawValue = rawValue }

  /// The link is off.
  public static let off = Self(rawValue: -2)
  /// The quality is unknown.
  public static let unknown = Self(rawValue: -1)
  /// The link is unusable.
  public static let bad = Self(rawValue: 10)
  /// The link is degraded.
  public static let poor = Self(rawValue: 50)
  /// The link is healthy.
  public static let good = Self(rawValue: 100)

  var isValid: Bool { (-2...100).contains(rawValue) }
}

/// Maximum and effective interface bandwidths, in bits per second.
public struct EthernetDataBandwidths: Sendable, Hashable {
  /// Largest receive rate the link supports.
  public let maximumInput: UInt64
  /// Largest transmit rate the link supports.
  public let maximumOutput: UInt64
  /// Receive rate the link currently achieves.
  public let effectiveInput: UInt64
  /// Transmit rate the link currently achieves.
  public let effectiveOutput: UInt64

  /// Creates bandwidths; an effective rate may not exceed its maximum.
  public init(
    maximumInput: UInt64,
    maximumOutput: UInt64,
    effectiveInput: UInt64,
    effectiveOutput: UInt64
  ) {
    self.maximumInput = maximumInput
    self.maximumOutput = maximumOutput
    self.effectiveInput = effectiveInput
    self.effectiveOutput = effectiveOutput
  }

  var isValid: Bool { effectiveInput <= maximumInput && effectiveOutput <= maximumOutput }
}

/// Hardware counters added to the interface statistics, then reset by the driver.
public struct EthernetHardwareCounts: Sendable, Hashable {
  public var packetsIn: UInt64 = 0
  public var bytesIn: UInt64 = 0
  public var multicastsIn: UInt64 = 0
  public var errorsIn: UInt64 = 0
  public var packetsOut: UInt64 = 0
  public var bytesOut: UInt64 = 0
  public var multicastsOut: UInt64 = 0
  public var errorsOut: UInt64 = 0
  public var collisions: UInt64 = 0
  public var dropped: UInt64 = 0
  public var noProtocol: UInt64 = 0

  /// Creates zeroed counters.
  public init() {}

  var fields: [UInt64] {
    [
      packetsIn, bytesIn, multicastsIn, errorsIn, packetsOut, bytesOut, multicastsOut, errorsOut,
      collisions, dropped, noProtocol,
    ]
  }
}

/// NIC proxy capacities reported through `reportNicProxyLimits`.
public struct EthernetNICProxyLimits: Sendable, Hashable {
  public var ipv4AddressCount: UInt8 = 0
  public var ipv6AddressCount: UInt8 = 0
  public var ipv4KeepAliveCount: UInt16 = 0
  public var ipv6KeepAliveCount: UInt16 = 0
  public var wakeUDPPortCount: UInt16 = 0
  public var wakeTCPPortCount: UInt16 = 0
  public var resourceRecordCount: UInt16 = 0
  public var maximumMDNSDomainLength: UInt8 = 0
  public var ethernetAddressCount: UInt8 = 0
  public var resourceRecordBufferSize: UInt16 = 0

  /// Creates zeroed limits.
  public init() {}
}

/// NIC proxy offload data the family hands the driver before the host sleeps.
public struct EthernetNICProxyConfiguration: Sendable, Hashable {
  /// The complete `nicproxy_info_t`, including its variable-length record buffer.
  public let data: Data
  /// The interface address the proxy answers for.
  public let hardwareAddress: EthernetAddress
  /// `NIC_PROXY_FLAGS_*` bits, such as wake on magic packet (0x40) and wake on link (0x80).
  public let flags: UInt8

  /// Smallest `nicproxy_info_t`: its fixed header.
  static let minimumLength = 80

  init(data: Data) throws {
    guard data.count >= Self.minimumLength, data.count.isMultiple(of: 4) else {
      throw EthernetRuntimeError.invalidPayload
    }
    let length: UInt32 = try data.readRuntimeInteger(at: 0)
    guard Int(length) == data.count else { throw EthernetRuntimeError.invalidPayload }
    let start = data.startIndex
    self.data = data
    self.hardwareAddress = EthernetAddress(
      data[start + 4],
      data[start + 5],
      data[start + 6],
      data[start + 7],
      data[start + 8],
      data[start + 9]
    )
    self.flags = data[start + 10]
  }
}

/// Berkeley packet filter tap directions the stack requested (`BPF_MODE_*`).
public struct EthernetPacketTapMode: OptionSet, Sendable, Hashable {
  /// The unmodified `BPF_MODE_*` bits.
  public let rawValue: UInt32
  /// Preserves `BPF_MODE_*` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Received frames are tapped.
  public static let input = Self(rawValue: 1)
  /// Transmitted frames are tapped.
  public static let output = Self(rawValue: 2)
}
