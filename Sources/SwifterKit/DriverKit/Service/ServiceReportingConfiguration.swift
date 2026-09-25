import Foundation

/// IOReporting channels the generated service publishes for the system's IOReport clients.
///
/// The extension creates the reporters when the service starts and publishes their legend with
/// `IOService::SetLegend`, so the channels exist whether or not a host is connected. The Swift
/// driver updates values through calls such as
/// ``DriverContext/setReportValue(_:reporter:channel:)``, naming a reporter by its index in
/// ``reporters``.
public struct ReportingConfiguration: Sendable, Hashable {
  /// The reporters, in the order Swift addresses them.
  public let reporters: [ReporterConfiguration]
  /// Whether the legend is public, `IOReportLegendPublic`, so unprivileged clients can read it.
  public let isLegendPublic: Bool

  /// Creates a reporting configuration.
  public init(reporters: [ReporterConfiguration], isLegendPublic: Bool = true) {
    self.reporters = reporters
    self.isLegendPublic = isLegendPublic
  }
}

/// One `IOReporter` and its legend entry.
public struct ReporterConfiguration: Sendable, Hashable {
  /// The reporter class and its class-specific layout.
  public enum Kind: Sendable, Hashable {
    /// `IOSimpleReporter`: one signed integer per channel.
    case simple
    /// `IOStateReporter`: each channel is in one of `states` at a time, named by state ID.
    case state(states: [UInt64])
    /// `IOHistogramReporter`: one channel whose values are tallied into `segments`' buckets.
    case histogram(segments: [HistogramSegment])
  }

  /// The reporter class.
  public let kind: Kind
  /// The legend group, `IOReportGroupName`.
  public let group: String
  /// The legend subgroup, `IOReportSubGroupName`, if any.
  public let subgroup: String?
  /// The reporter's channels; a histogram has exactly one.
  public let channels: [ReportChannel]
  /// The categories clients filter by.
  public let categories: ReportCategories
  /// The unit of the reported values.
  public let unit: ReportUnit

  /// Creates a reporter configuration.
  public init(
    kind: Kind,
    group: String,
    subgroup: String? = nil,
    channels: [ReportChannel],
    categories: ReportCategories,
    unit: ReportUnit = .none
  ) {
    self.kind = kind
    self.group = group
    self.subgroup = subgroup
    self.channels = channels
    self.categories = categories
    self.unit = unit
  }
}

/// A reporter channel: a nonzero identifier unique within the service, and a name.
public struct ReportChannel: Sendable, Hashable {
  /// The channel identifier; `IOREPORT_MAKEID` packs up to eight ASCII bytes into one.
  public let id: UInt64
  /// The channel name clients display.
  public let name: String

  /// Creates a channel.
  public init(id: UInt64, name: String) {
    self.id = id
    self.name = name
  }
}

/// A histogram segment, `IOHistogramSegmentConfig`.
///
/// Bucket `n` of a linear segment ends at `baseBucketWidth * (n + 1)`; bucket `n` of an
/// exponential segment ends at `baseBucketWidth` raised to `n + 1`.
public struct HistogramSegment: Sendable, Hashable {
  /// How bucket bounds grow.
  public enum Scale: UInt32, Sendable, Hashable {
    /// `kIOHistogramScaleLinear`.
    case linear = 0
    /// `kIOHistogramScaleExponential`.
    case exponential = 1
  }

  /// The first bucket's width, or the exponential base.
  public let baseBucketWidth: UInt32
  /// How bucket bounds grow.
  public let scale: Scale
  /// The number of buckets.
  public let bucketCount: UInt32

  /// Creates a segment.
  public init(baseBucketWidth: UInt32, scale: Scale = .linear, bucketCount: UInt32) {
    self.baseBucketWidth = baseBucketWidth
    self.scale = scale
    self.bucketCount = bucketCount
  }
}

/// IOReporting categories, the `kIOReportCategory*` bits.
public struct ReportCategories: OptionSet, Sendable, Hashable {
  public let rawValue: UInt16

  /// Creates categories from `IOReportCategories` bits.
  public init(rawValue: UInt16) { self.rawValue = rawValue }

  /// Power and energy, `kIOReportCategoryPower`.
  public static let power = Self(rawValue: 1 << 1)
  /// I/O at any level, `kIOReportCategoryTraffic`.
  public static let traffic = Self(rawValue: 1 << 2)
  /// Performance, `kIOReportCategoryPerformance`.
  public static let performance = Self(rawValue: 1 << 3)
  /// A peripheral rather than built-in hardware, `kIOReportCategoryPeripheral`.
  public static let peripheral = Self(rawValue: 1 << 4)
  /// Worth logging in the field, `kIOReportCategoryField`.
  public static let field = Self(rawValue: 1 << 8)
  /// Debugging, `kIOReportCategoryDebug`.
  public static let debug = Self(rawValue: 1 << 15)

  /// Every category the runtime accepts.
  public static let all: Self = [.power, .traffic, .performance, .peripheral, .field, .debug]
}

/// An IOReporting unit, an `IOReportUnit` value from `IOReportTypes.h`.
public struct ReportUnit: RawRepresentable, Sendable, Hashable {
  /// No unit, `kIOReportUnitNone`.
  public static let none = Self(rawValue: 0)
  /// Seconds, `kIOReportUnit_s`.
  public static let seconds = Self(rawValue: 0x0100_0000_0000_0000)
  /// Milliseconds, `kIOReportUnit_ms`.
  public static let milliseconds = Self(rawValue: 0x0100_007C_0000_0000)
  /// Microseconds, `kIOReportUnit_us`.
  public static let microseconds = Self(rawValue: 0x0100_0079_0000_0000)
  /// Nanoseconds, `kIOReportUnit_ns`.
  public static let nanoseconds = Self(rawValue: 0x0100_0076_0000_0000)
  /// Mach absolute-time ticks, `kIOReportUnitHWTicks`, the unit state residency uses.
  public static let hardwareTicks = Self(rawValue: 0x0101_0000_0000_0000)
  /// Bits, `kIOReportUnitBits`.
  public static let bits = Self(rawValue: 0x0900_0000_0000_0000)
  /// Bytes, `kIOReportUnitBytes`.
  public static let bytes = Self(rawValue: 0x0900_8200_0000_0000)
  /// Kibibytes, `kIOReportUnit_KiB`.
  public static let kibibytes = Self(rawValue: 0x0900_8C00_0000_0000)
  /// Mebibytes, `kIOReportUnit_MiB`.
  public static let mebibytes = Self(rawValue: 0x0900_9600_0000_0000)
  /// Events, `kIOReportUnitEvents`.
  public static let events = Self(rawValue: 0x6400_0000_0000_0000)
  /// Packets, `kIOReportUnitPackets`.
  public static let packets = Self(rawValue: 0x6500_0000_0000_0000)
  /// Joules, `kIOReportUnit_J`.
  public static let joules = Self(rawValue: 0x0300_0000_0000_0000)
  /// Millijoules, `kIOReportUnit_mJ`.
  public static let millijoules = Self(rawValue: 0x0300_007C_0000_0000)
  /// Microjoules, `kIOReportUnit_uJ`.
  public static let microjoules = Self(rawValue: 0x0300_0079_0000_0000)

  /// The `IOReportUnit` value.
  public let rawValue: UInt64
  /// Creates a unit from an `IOReportUnit` value.
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// Limits the generator and extension enforce on reporting.
public enum ReportingLimits {
  /// The most reporters in one configuration.
  public static let maximumReporters = 16
  /// The most channels in one reporter.
  public static let maximumChannels = 32
  /// The most states in one state reporter.
  public static let maximumStates = 16
  /// The most segments in one histogram.
  public static let maximumSegments = 8
  /// The most buckets in one histogram, across its segments.
  public static let maximumBuckets = 128
  /// The longest group, subgroup, or channel name in UTF-8 bytes.
  public static let maximumNameLength = 63
}

extension ReportingConfiguration {
  /// Returns whether every reporter fits the runtime's limits and channel IDs are unique.
  var isValid: Bool {
    let ids = reporters.flatMap { $0.channels.map(\.id) }
    return (1...ReportingLimits.maximumReporters).contains(reporters.count)
      && Set(ids).count == ids.count && reporters.allSatisfy(\.isValid)
  }
}

extension ReporterConfiguration {
  var isValid: Bool {
    guard Self.isName(group), subgroup.map(Self.isName) ?? true, !categories.isEmpty,
      categories.subtracting(.all).isEmpty,
      (1...ReportingLimits.maximumChannels).contains(channels.count),
      channels.allSatisfy({ $0.id != 0 && Self.isName($0.name) })
    else { return false }
    switch kind {
    case .simple: return true
    case .state(let states):
      return (1...ReportingLimits.maximumStates).contains(states.count)
        && Set(states).count == states.count
    case .histogram(let segments):
      let buckets = segments.reduce(0) { $0 + Int($1.bucketCount) }
      return channels.count == 1 && (1...ReportingLimits.maximumSegments).contains(segments.count)
        && buckets <= ReportingLimits.maximumBuckets
        && segments.allSatisfy {
          $0.bucketCount > 0 && $0.baseBucketWidth >= ($0.scale == .exponential ? 2 : 1)
        }
    }
  }

  static func isName(_ name: String) -> Bool {
    let bytes = Array(name.utf8)
    return (1...ReportingLimits.maximumNameLength).contains(bytes.count) && !bytes.contains(0)
  }
}
