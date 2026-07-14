import Foundation

/// Clock used for timestamps delivered by a hardware interrupt source.
public enum InterruptClock: Sendable, Hashable {
  /// Uses  values.
  case absolute
  /// Uses  values that include system sleep.
  case continuous
}

/// Static configuration for one provider interrupt source.
public struct InterruptSourceConfiguration: Sendable, Hashable {
  /// The provider's interrupt index.
  public let index: UInt32
  /// The clock used for interrupt timestamps.
  public let clock: InterruptClock

  /// Creates interrupt-source metadata for a generated extension.
  public init(index: UInt32, clock: InterruptClock = .absolute) {
    self.index = index
    self.clock = clock
  }

  var nativeIndex: UInt32 { index | (clock == .continuous ? 0x0001_0000 : 0) }
}

/// The most recently observed count and timestamp for an interrupt source.
public struct InterruptSnapshot: Sendable, Hashable {
  /// The cumulative interrupt count.
  public let count: UInt64
  /// The time of the most recent interrupt in the configured clock.
  public let time: UInt64

  /// Creates an interrupt snapshot.
  public init(count: UInt64, time: UInt64) {
    self.count = count
    self.time = time
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 16 else { throw InterruptRuntimeError.invalidPayload }
    self.init(
      count: try runtimePayload.readRuntimeInteger(at: 0),
      time: try runtimePayload.readRuntimeInteger(at: 8)
    )
  }
}

/// One hardware interrupt delivered by the internal DriverKit runtime.
public struct InterruptEvent: Sendable, Hashable {
  /// The configured provider interrupt index.
  public let sourceIndex: UInt32
  /// The number of interrupts represented by this delivery.
  public let count: UInt64
  /// The interrupt timestamp in the configured clock.
  public let time: UInt64

  /// Creates a hardware-interrupt event.
  public init(sourceIndex: UInt32, count: UInt64, time: UInt64) {
    self.sourceIndex = sourceIndex
    self.count = count
    self.time = time
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 24, try runtimePayload.readRuntimeInteger(at: 4) as UInt32 == 0
    else { throw InterruptRuntimeError.invalidPayload }
    self.init(
      sourceIndex: try runtimePayload.readRuntimeInteger(at: 0),
      count: try runtimePayload.readRuntimeInteger(at: 8),
      time: try runtimePayload.readRuntimeInteger(at: 16)
    )
  }
}

/// An interrupt configuration or response that cannot be represented safely.
public enum InterruptRuntimeError: Error, Sendable, Equatable {
  /// DriverKit interrupt indices occupy the low 16 bits.
  case invalidSourceIndex
  /// A generated extension cannot configure the same source more than once.
  case duplicateSourceIndex
  /// The native runtime returned a malformed interrupt payload.
  case invalidPayload
}
