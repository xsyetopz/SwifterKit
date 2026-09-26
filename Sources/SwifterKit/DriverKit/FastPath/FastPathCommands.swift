import Foundation

/// How a command-triggered fast-path program ended.
public struct FastPathResult: Sendable, Hashable {
  /// The program's `IOReturn`: `kIOReturnSuccess` (zero) when it ran to its end,
  /// `kIOReturnTimeout` when a `poll` never matched, or the status of the `fail` it ran.
  public let status: Int32
  /// The eight slots, `v0` through `v7`, when the program ended.
  public let values: [UInt64]

  /// Creates a program result.
  public init(status: Int32, values: [UInt64]) {
    self.status = status
    self.values = values
  }

  /// Whether the program ran to its end.
  public var succeeded: Bool { status == 0 }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == RuntimeFastPathRow.runResult.size,
      try runtimePayload.readRuntimeInteger(at: 4) as UInt32 == 0
    else { throw FastPathRuntimeError.invalidPayload }
    self.init(
      status: Int32(bitPattern: try runtimePayload.readRuntimeInteger(at: 0)),
      values: try (0..<FastPathLimits.maximumEmittedSlots).map {
        try runtimePayload.readRuntimeInteger(at: 8 + 8 * $0)
      }
    )
  }
}

/// The values a fast-path program delivered with `emit`.
public struct FastPathEvent: Sendable, Hashable {
  /// The index of the program that emitted, in ``FastPathConfiguration/programs``.
  public let program: Int
  /// The emitted slots' values, in the order the `emit` named them.
  public let values: [UInt64]

  /// Creates a fast-path event.
  public init(program: Int, values: [UInt64]) {
    self.program = program
    self.values = values
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == RuntimeFastPathRow.event.size else {
      throw FastPathRuntimeError.invalidPayload
    }
    let program: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let count: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let values: [UInt64] = try (0..<FastPathLimits.maximumEmittedSlots).map {
      try runtimePayload.readRuntimeInteger(at: 8 + 8 * $0)
    }
    guard program < FastPathLimits.maximumPrograms,
      (1...FastPathLimits.maximumEmittedSlots).contains(Int(count)),
      values[Int(count)...].allSatisfy({ $0 == 0 })
    else { throw FastPathRuntimeError.invalidPayload }
    self.init(program: Int(program), values: Array(values.prefix(Int(count))))
  }
}

/// Whether the extension runs its fast path, and the events it could not queue.
public struct FastPathStatus: Sendable, Hashable {
  /// `kIOReturnSuccess` (zero) while programs run. Otherwise why they do not:
  /// `kIOReturnNoResources` when a declared BAR is missing or smaller than declared or the
  /// tables failed the extension's checks, a failed start program's status, or
  /// `kIOReturnNotReady` before start and after stop.
  public let status: Int32
  /// The `emit` events dropped because the extension's lossy event queue was full.
  public let droppedEvents: UInt64

  /// Creates a fast-path status.
  public init(status: Int32, droppedEvents: UInt64) {
    self.status = status
    self.droppedEvents = droppedEvents
  }

  /// Whether the extension runs fast-path programs.
  public var isRunning: Bool { status == 0 }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == RuntimeFastPathRow.statusReply.size,
      try runtimePayload.readRuntimeInteger(at: 4) as UInt32 == 0
    else { throw FastPathRuntimeError.invalidPayload }
    self.init(
      status: Int32(bitPattern: try runtimePayload.readRuntimeInteger(at: 0)),
      droppedEvents: try runtimePayload.readRuntimeInteger(at: 8)
    )
  }
}

/// A fast-path command Swift refused before sending, or a malformed reply.
public enum FastPathRuntimeError: Error, Sendable, Hashable {
  /// The program index is negative, above ``FastPathLimits/maximumPrograms``, or past the
  /// configuration's programs.
  case unknownProgram(Int)
  /// The program is not run by ``FastPathTrigger/command``.
  case notACommandProgram(Int)
  /// The argument count exceeds ``FastPathLimits/maximumArguments`` or differs from the
  /// program's ``FastPathProgram/argumentCount``.
  case invalidArgumentCount(program: Int, count: Int)
  /// The extension returned a malformed fast-path payload.
  case invalidPayload
  /// The ring identifier is above `0xFF_FFFF` or not declared by the context's configuration.
  case unknownRing(UInt32)
  /// The data queue identifier is above `0xFF_FFFF` or not declared by the context's
  /// configuration.
  case unknownDataQueue(UInt32)
}

extension DriverCommand {
  /// Creates a run of a command-triggered fast-path program with arguments in `v0` onward.
  ///
  /// The index and argument count are checked against ``FastPathLimits``, and against
  /// `configuration` when it is given; the extension checks them again against its tables.
  public static func runFastPathProgram(
    _ program: Int,
    arguments: [UInt64] = [],
    in configuration: FastPathConfiguration? = nil
  ) throws(FastPathRuntimeError) -> Self {
    guard (0..<FastPathLimits.maximumPrograms).contains(program) else {
      throw .unknownProgram(program)
    }
    guard arguments.count <= FastPathLimits.maximumArguments else {
      throw .invalidArgumentCount(program: program, count: arguments.count)
    }
    if let configuration {
      guard program < configuration.programs.count else { throw .unknownProgram(program) }
      let declared = configuration.programs[program]
      guard declared.trigger == .command else { throw .notACommandProgram(program) }
      guard arguments.count == declared.argumentCount else {
        throw .invalidArgumentCount(program: program, count: arguments.count)
      }
    }
    var payload = Data(capacity: RuntimeFastPathRow.runRequest.size)
    payload.appendRuntimeInteger(UInt32(program))
    payload.appendRuntimeInteger(UInt32(arguments.count))
    for index in 0..<FastPathLimits.maximumArguments {
      payload.appendRuntimeInteger(index < arguments.count ? arguments[index] : 0)
    }
    return Self(
      opcode: .fastPathRun,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + RuntimeFastPathRow.runResult.size
    )
  }

  /// Creates a query of whether the fast path runs and how many events it dropped.
  public static let fastPathStatus = Self(
    opcode: .fastPathStatus,
    maximumResponseSize: RuntimeMessage.headerSize + RuntimeFastPathRow.statusReply.size
  )
}

extension DriverContext {
  /// Runs a command-triggered fast-path program in the extension and returns its status and
  /// slots.
  ///
  /// The program runs under the extension's fast-path lock, so it never interleaves with an
  /// interrupt, start, or stop program. A program that times out or runs `fail` still returns a
  /// result with that status; the call throws when Swift or the extension refuses the request or
  /// the fast path does not run.
  public func runFastPathProgram(
    _ program: Int,
    arguments: [UInt64] = []
  ) async throws -> FastPathResult {
    let command = try DriverCommand.runFastPathProgram(program, arguments: arguments, in: fastPath)
    return try FastPathResult(runtimePayload: await execute(command))
  }

  /// Returns whether the extension runs its fast path and how many `emit` events it dropped.
  public func fastPathStatus() async throws -> FastPathStatus {
    try FastPathStatus(runtimePayload: await execute(.fastPathStatus))
  }
}

extension DriverEvent {
  /// Decodes the values a fast-path program delivered with `emit`.
  ///
  /// Returns nil when the event belongs to another family.
  public func fastPath() throws -> FastPathEvent? {
    guard type == RuntimeEventType.fastPath.rawValue else { return nil }
    return try FastPathEvent(runtimePayload: Data(payload))
  }
}
