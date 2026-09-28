// Service-family wire constants: timers, watches, IOReporting, and registry properties.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeSchema.h` with the native names that
// `SwifterKitRuntimeDispatchProtocol.h`, `SwifterKitRuntimeReportingProtocol.h`, and
// `SwifterKitRuntimeServiceProtocol.h` used before, so neither side spells a value twice.

/// Limits the extension enforces on timers and watches.
enum RuntimeDispatchLimits {
  /// The most timers that run at once.
  static let maximumTimers = 16
  /// The shortest repeating timer interval, one millisecond.
  static let timerMinimumIntervalNanoseconds: UInt64 = 1_000_000
  /// The longest timer delay, interval, or leeway, one day.
  static let timerMaximumNanoseconds: UInt64 = 86_400_000_000_000
  /// The most service-matching and system-state watches that run at once, together.
  static let maximumServiceWatches = 8
  /// The most items one system-state watch names.
  static let maximumWatchedStateItems = 8
}

/// Whether a watched service matched or terminated. The public type carries the wire values,
/// which match `kIOServiceNotificationTypeTerminated` and `kIOServiceNotificationTypeMatched`.
typealias RuntimeServiceWatchKind = ServiceMatchNotification.Kind

/// Limits the generator and extension enforce on IOReporting tables.
enum RuntimeReportingLimits {
  static let maximumReporters = 16
  static let maximumReportChannels = 32
  static let maximumReportStates = 16
  static let maximumHistogramSegments = 8
  static let maximumHistogramBuckets = 128
}

/// The reporter class a generated reporter table entry creates.
enum RuntimeReporterKind: UInt32, CaseIterable {
  case simple = 1
  case state = 2
  case histogram = 3
}

/// The update a `reporterUpdate` command applies. See `SwifterKitReporterUpdate`.
enum RuntimeReporterOperation: UInt32, CaseIterable {
  case setValue = 1
  case incrementValue = 2
  case setState = 3
  case overrideState = 4
  case incrementState = 5
  case tallyValue = 6
  case overrideBucket = 7
}

/// The tag that begins each value in the registry-property encoding.
enum RuntimePropertyTag: UInt8, CaseIterable {
  case boolean = 1
  case number = 2
  case string = 3
  case data = 4
  case array = 5
  case dictionary = 6
}

/// Bounds of the registry-property encoding.
enum RuntimePropertyLimits {
  /// The deepest nesting either side accepts. A top-level value is at depth 1.
  static let maximumDepth = 8
  /// The longest registry name: `IOPropertyName` and `IORegistryPlaneName` hold 128 bytes
  /// including the terminating NUL.
  static let nameMaximumLength = 127
}
