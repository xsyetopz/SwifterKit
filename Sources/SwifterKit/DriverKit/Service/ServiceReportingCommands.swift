import Foundation

/// A state reporter's statistics for one state, from `IOStateReporter`.
public struct ReportStateStatistics: Sendable, Hashable {
  /// How many times the channel entered the state, `getStateInTransitions`.
  public let transitions: UInt64
  /// The time spent in the state in the reporter's unit, `getStateResidencyTime`.
  public let residency: UInt64
  /// When the channel last entered the state, `getStateLastTransitionTime`.
  public let lastTransition: UInt64
}

extension DriverCommand {
  /// Creates a value change through `IOSimpleReporter::setValue`.
  public static func setReportValue(_ value: Int64, reporter: Int, channel: UInt64) throws -> Self {
    try reporterUpdate(.setValue, reporter: reporter, channel: channel, values: [value])
  }

  /// Creates a value change through `IOSimpleReporter::incrementValue`.
  public static func incrementReportValue(
    by increment: Int64,
    reporter: Int,
    channel: UInt64
  ) throws -> Self {
    try reporterUpdate(.incrementValue, reporter: reporter, channel: channel, values: [increment])
  }

  /// Creates a state change through `IOStateReporter::setChannelState`.
  public static func setReportState(_ state: UInt64, reporter: Int, channel: UInt64) throws -> Self
  {
    try reporterUpdate(
      .setState,
      reporter: reporter,
      channel: channel,
      values: [Int64(bitPattern: state)]
    )
  }

  /// Creates a state adjustment through `IOStateReporter::overrideChannelState`, or with
  /// `accumulate` through `incrementChannelState`.
  ///
  /// `residency` and `lastTransition` are in the reporter's unit. The values may not exceed
  /// `Int64.max`.
  public static func adjustReportState(
    _ state: UInt64,
    reporter: Int,
    channel: UInt64,
    residency: UInt64,
    transitions: UInt64,
    lastTransition: UInt64 = 0,
    accumulate: Bool = false
  ) throws -> Self {
    let values = [residency, transitions, lastTransition]
    guard values.allSatisfy({ $0 <= UInt64(Int64.max) }) else {
      throw ServiceRuntimeError.invalidValue
    }
    return try reporterUpdate(
      accumulate ? .incrementState : .overrideState,
      reporter: reporter,
      channel: channel,
      values: [Int64(bitPattern: state)] + values.map { Int64($0) }
    )
  }

  /// Creates a histogram sample through `IOHistogramReporter::tallyValue`.
  public static func tallyReportValue(_ value: Int64, reporter: Int, channel: UInt64) throws -> Self
  { try reporterUpdate(.tallyValue, reporter: reporter, channel: channel, values: [value]) }

  /// Creates a bucket replacement through `IOHistogramReporter::overrideBucketValues`.
  public static func overrideHistogramBucket(
    _ bucket: Int,
    reporter: Int,
    channel: UInt64,
    hits: UInt64,
    minimum: Int64,
    maximum: Int64,
    sum: Int64
  ) throws -> Self {
    guard bucket >= 0, bucket < ReportingLimits.maximumBuckets, hits <= UInt64(Int64.max),
      minimum <= maximum
    else { throw ServiceRuntimeError.invalidValue }
    return try reporterUpdate(
      .overrideBucket,
      reporter: reporter,
      channel: channel,
      values: [Int64(bucket), Int64(hits), minimum, maximum, sum]
    )
  }

  /// Creates a read of a simple reporter's value through `IOSimpleReporter::getValue`.
  public static func reportValue(reporter: Int, channel: UInt64) throws -> Self {
    try reporterRead(reporter: reporter, channel: channel, state: 0)
  }

  /// Creates a read of one state's statistics from an `IOStateReporter`.
  public static func reportStateStatistics(
    _ state: UInt64,
    reporter: Int,
    channel: UInt64
  ) throws -> Self { try reporterRead(reporter: reporter, channel: channel, state: state) }

  typealias ReporterOperation = RuntimeReporterOperation

  private static func reporterUpdate(
    _ operation: ReporterOperation,
    reporter: Int,
    channel: UInt64,
    values: [Int64]
  ) throws -> Self {
    var payload = Data(capacity: 56)
    payload.appendRuntimeInteger(try reporterIndex(reporter, channel: channel))
    payload.appendRuntimeInteger(operation.rawValue)
    payload.appendRuntimeInteger(channel)
    for index in 0..<5 { payload.appendRuntimeInteger(index < values.count ? values[index] : 0) }
    return service(.reporterUpdate, payload: payload)
  }

  private static func reporterRead(reporter: Int, channel: UInt64, state: UInt64) throws -> Self {
    var payload = Data(capacity: 24)
    payload.appendRuntimeInteger(try reporterIndex(reporter, channel: channel))
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(channel)
    payload.appendRuntimeInteger(state)
    return service(.reporterRead, payload: payload, responseSize: 24)
  }

  private static func reporterIndex(_ reporter: Int, channel: UInt64) throws -> UInt32 {
    guard (0..<ReportingLimits.maximumReporters).contains(reporter), channel != 0 else {
      throw ServiceRuntimeError.invalidValue
    }
    return UInt32(reporter)
  }
}

extension DriverContext {
  /// Sets a simple reporter channel's value. `reporter` indexes
  /// ``ReportingConfiguration/reporters``.
  public func setReportValue(_ value: Int64, reporter: Int, channel: UInt64) async throws {
    _ = try await execute(try .setReportValue(value, reporter: reporter, channel: channel))
  }

  /// Adds `increment` to a simple reporter channel's value.
  public func incrementReportValue(by increment: Int64, reporter: Int, channel: UInt64) async throws
  {
    _ = try await execute(
      try .incrementReportValue(by: increment, reporter: reporter, channel: channel)
    )
  }

  /// Moves a state reporter channel to `state`, one of the reporter's configured state IDs.
  /// DriverKit accounts residency in mach absolute time.
  public func setReportState(_ state: UInt64, reporter: Int, channel: UInt64) async throws {
    _ = try await execute(try .setReportState(state, reporter: reporter, channel: channel))
  }

  /// Replaces, or with `accumulate` adds to, a state's residency, transition count, and last
  /// transition time, for reporters that keep their own time base.
  ///
  /// With `accumulate` the extension calls `IOStateReporter::incrementChannelState`.
  public func adjustReportState(
    _ state: UInt64,
    reporter: Int,
    channel: UInt64,
    residency: UInt64,
    transitions: UInt64,
    lastTransition: UInt64 = 0,
    accumulate: Bool = false
  ) async throws {
    _ = try await execute(
      try .adjustReportState(
        state,
        reporter: reporter,
        channel: channel,
        residency: residency,
        transitions: transitions,
        lastTransition: lastTransition,
        accumulate: accumulate
      )
    )
  }

  /// Tallies `value` into its histogram bucket.
  public func tallyReportValue(_ value: Int64, reporter: Int, channel: UInt64) async throws {
    _ = try await execute(try .tallyReportValue(value, reporter: reporter, channel: channel))
  }

  /// Replaces one histogram bucket's hit count, minimum, maximum, and sum.
  public func overrideHistogramBucket(
    _ bucket: Int,
    reporter: Int,
    channel: UInt64,
    hits: UInt64,
    minimum: Int64,
    maximum: Int64,
    sum: Int64
  ) async throws {
    _ = try await execute(
      try .overrideHistogramBucket(
        bucket,
        reporter: reporter,
        channel: channel,
        hits: hits,
        minimum: minimum,
        maximum: maximum,
        sum: sum
      )
    )
  }

  /// Returns a simple reporter channel's value.
  public func reportValue(reporter: Int, channel: UInt64) async throws -> Int64 {
    let reply = try await execute(try .reportValue(reporter: reporter, channel: channel))
    guard reply.count == 24 else { throw ServiceRuntimeError.invalidPayload }
    return try reply.readRuntimeInteger(at: 0)
  }

  /// Returns a state reporter channel's statistics for `state`.
  /// The extension reads it with `IOStateReporter::getStateInTransitions`,
  /// `IOStateReporter::getStateResidencyTime`, `IOStateReporter::getStateLastTransitionTime`.
  public func reportStateStatistics(
    _ state: UInt64,
    reporter: Int,
    channel: UInt64
  ) async throws -> ReportStateStatistics {
    let reply = try await execute(
      try .reportStateStatistics(state, reporter: reporter, channel: channel)
    )
    guard reply.count == 24 else { throw ServiceRuntimeError.invalidPayload }
    return ReportStateStatistics(
      transitions: try reply.readRuntimeInteger(at: 0),
      residency: try reply.readRuntimeInteger(at: 8),
      lastTransition: try reply.readRuntimeInteger(at: 16)
    )
  }
}
