import Foundation

/// A timer the extension runs with `IOTimerDispatchSource`, returned by
/// ``DriverContext/startTimer(afterNanoseconds:repeatingEveryNanoseconds:leewayNanoseconds:)``.
public struct ServiceTimer: Sendable, Hashable {
  /// The identifier that ``ServiceTimerFiring/timer`` repeats.
  public let id: UInt32

  /// Wraps an identifier the extension returned.
  public init(id: UInt32) { self.id = id }
}

/// One firing of a ``ServiceTimer``, delivered as a lossy event.
///
/// Events can be dropped while the host stalls, so compare ``fireCount`` with the last count seen
/// to learn how many firings were missed.
public struct ServiceTimerFiring: Sendable, Hashable {
  /// The timer that fired.
  public let timer: ServiceTimer
  /// How many times the timer has fired, counted from 1.
  public let fireCount: UInt64
  /// `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` in the extension when the timer fired.
  public let timestamp: UInt64

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 24, try runtimePayload.readRuntimeInteger(at: 4) as UInt32 == 0
    else { throw ServiceRuntimeError.invalidPayload }
    let id: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    timer = ServiceTimer(id: id)
    fireCount = try runtimePayload.readRuntimeInteger(at: 8)
    timestamp = try runtimePayload.readRuntimeInteger(at: 16)
    guard id != 0, fireCount != 0 else { throw ServiceRuntimeError.invalidPayload }
  }
}

/// Limits the extension enforces on timers.
public enum ServiceTimerLimits {
  /// The most timers that run at once.
  public static let maximumTimers = RuntimeDispatchLimits.maximumTimers
  /// The shortest repeating interval, one millisecond.
  public static let minimumIntervalNanoseconds = RuntimeDispatchLimits
    .timerMinimumIntervalNanoseconds
  /// The longest delay, interval, or leeway, one day.
  public static let maximumNanoseconds = RuntimeDispatchLimits.timerMaximumNanoseconds
}

extension DriverCommand {
  /// Creates a timer through `IOTimerDispatchSource::Create` and `WakeAtTime`.
  ///
  /// `delay` and `leeway` may be zero. `interval`, when present, lies within
  /// ``ServiceTimerLimits/minimumIntervalNanoseconds`` and
  /// ``ServiceTimerLimits/maximumNanoseconds``.
  public static func startTimer(
    afterNanoseconds delay: UInt64,
    repeatingEveryNanoseconds interval: UInt64? = nil,
    leewayNanoseconds leeway: UInt64 = 0
  ) throws -> Self {
    let limit = ServiceTimerLimits.maximumNanoseconds
    guard delay <= limit, leeway <= limit else { throw ServiceRuntimeError.invalidValue }
    if let interval {
      guard interval >= ServiceTimerLimits.minimumIntervalNanoseconds, interval <= limit else {
        throw ServiceRuntimeError.invalidValue
      }
    }
    var payload = Data(capacity: 24)
    payload.appendRuntimeInteger(delay)
    payload.appendRuntimeInteger(interval ?? 0)
    payload.appendRuntimeInteger(leeway)
    return service(.timerStart, payload: payload, responseSize: 8)
  }

  /// Creates a timer cancellation through `IOTimerDispatchSource::Cancel`.
  public static func cancelTimer(_ timer: ServiceTimer) throws -> Self {
    service(.timerCancel, payload: try identifierPayload(timer.id))
  }

  static func identifierPayload(_ id: UInt32) throws -> Data {
    guard id != 0 else { throw ServiceRuntimeError.invalidValue }
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(id)
    payload.appendRuntimeInteger(UInt32(0))
    return payload
  }
}

extension DriverContext {
  /// Starts a timer in the extension that fires after `delay` nanoseconds and, with `interval`,
  /// again every `interval` nanoseconds until ``cancelTimer(_:)``.
  ///
  /// Each firing arrives as an event that ``DriverEvent/timerFiring()`` decodes. A one-shot timer
  /// ends when it fires. At most ``ServiceTimerLimits/maximumTimers`` timers run at once. More
  /// fail with `kIOReturnNoResources`. Timers end when the host disconnects.
  public func startTimer(
    afterNanoseconds delay: UInt64,
    repeatingEveryNanoseconds interval: UInt64? = nil,
    leewayNanoseconds leeway: UInt64 = 0
  ) async throws -> ServiceTimer {
    let command = try DriverCommand.startTimer(
      afterNanoseconds: delay,
      repeatingEveryNanoseconds: interval,
      leewayNanoseconds: leeway
    )
    return ServiceTimer(id: try Self.identifier(from: try await execute(command)))
  }

  /// Cancels a timer. Fails with `kIOReturnNotFound` once a one-shot timer has fired.
  public func cancelTimer(_ timer: ServiceTimer) async throws {
    _ = try await execute(try .cancelTimer(timer))
  }

  static func identifier(from reply: Data) throws -> UInt32 {
    guard reply.count == 8, try reply.readRuntimeInteger(at: 4) as UInt32 == 0 else {
      throw ServiceRuntimeError.invalidPayload
    }
    let id: UInt32 = try reply.readRuntimeInteger(at: 0)
    guard id != 0 else { throw ServiceRuntimeError.invalidPayload }
    return id
  }
}

extension DriverEvent {
  /// Decodes a ``ServiceTimer`` firing.
  public func timerFiring() throws -> ServiceTimerFiring? {
    guard type == RuntimeEventType.timer.rawValue else { return nil }
    return try ServiceTimerFiring(runtimePayload: Data(payload))
  }
}
