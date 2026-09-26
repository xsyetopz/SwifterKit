import Foundation

/// Register sequences the generated extension runs natively, without a round trip to Swift.
///
/// A fast path is data: the generator validates the programs and emits them as constant tables
/// that the extension's fixed interpreter reads. No Swift code is translated. Every limit in
/// ``FastPathLimits`` is enforced when the extension is generated, and an invalid configuration
/// is refused with a ``FastPathError`` rather than truncated.
public struct FastPathConfiguration: Sendable, Hashable {
  /// The programs, addressed by their index.
  public let programs: [FastPathProgram]
  /// The minimum size in bytes of each BAR the programs access, keyed by BAR index.
  ///
  /// Every register must lie inside its declared BAR; the extension refuses to start the fast
  /// path when the device's BAR is smaller.
  public let barSizes: [UInt8: UInt64]

  /// Creates a fast-path configuration.
  public init(programs: [FastPathProgram], barSizes: [UInt8: UInt64] = [:]) {
    self.programs = programs
    self.barSizes = barSizes
  }
}

/// Limits the generator enforces on a ``FastPathConfiguration`` and the extension re-checks.
public enum FastPathLimits {
  /// The most programs in one configuration.
  public static let maximumPrograms = RuntimeFastPathLimits.maximumPrograms
  /// The most operations in one program.
  public static let maximumOperations = RuntimeFastPathLimits.maximumOperations
  /// The most arguments a command program receives.
  public static let maximumArguments = RuntimeFastPathLimits.maximumArguments
  /// The most register reads one `poll` makes.
  public static let maximumPollIterations = RuntimeFastPathLimits.maximumPollIterations
  /// The longest wait between two `poll` reads, in microseconds.
  public static let maximumPollIntervalMicroseconds = RuntimeFastPathLimits
    .maximumPollIntervalMicroseconds
  /// The longest single `delay`, in microseconds.
  public static let maximumDelayMicroseconds = RuntimeFastPathLimits.maximumDelayMicroseconds
  /// The most time one program may wait in `delay` operations and worst-case `poll` intervals
  /// together, in microseconds.
  public static let maximumDelayBudgetMicroseconds = RuntimeFastPathLimits
    .maximumDelayBudgetMicroseconds
  /// The highest BAR index a register may name.
  public static let maximumBAR = UInt8(RuntimeFastPathLimits.barCount - 1)
  /// The most slots one `emit` delivers.
  public static let maximumEmittedSlots = RuntimeFastPathLimits.slotCount
}

/// Why a ``FastPathConfiguration`` was refused. `program` and `operation` are array indices.
public enum FastPathError: Error, Sendable, Hashable {
  /// The configuration has no programs.
  case noPrograms
  /// The configuration has more than ``FastPathLimits/maximumPrograms`` programs.
  case tooManyPrograms(count: Int)
  /// A program has no operations.
  case emptyProgram(program: Int)
  /// A program has more than ``FastPathLimits/maximumOperations`` operations.
  case tooManyOperations(program: Int, count: Int)
  /// A program's argument count is negative or above ``FastPathLimits/maximumArguments``.
  case invalidArgumentCount(program: Int, count: Int)
  /// A program that is not run by ``FastPathTrigger/command`` declares arguments.
  case argumentsWithoutCommandTrigger(program: Int)
  /// An interrupt trigger names a provider index no ``InterruptSourceConfiguration`` declares.
  case unknownInterruptSource(program: Int, sourceIndex: UInt32)
  /// A second program is triggered by the same interrupt source.
  case duplicateInterruptTrigger(program: Int, sourceIndex: UInt32)
  /// A declared BAR index is above ``FastPathLimits/maximumBAR`` or its size is zero.
  case invalidBARSize(bar: UInt8)
  /// Registers or BAR sizes are declared without ``DriverConfiguration/pciDevice``.
  case registersWithoutPCIDevice
  /// A register names a BAR above ``FastPathLimits/maximumBAR``.
  case invalidBAR(program: Int, operation: Int)
  /// A register names a BAR that ``FastPathConfiguration/barSizes`` does not declare.
  case undeclaredBAR(program: Int, operation: Int)
  /// A register offset is not a multiple of its width.
  case misalignedRegister(program: Int, operation: Int)
  /// A register extends past its BAR's declared size.
  case registerOutOfBounds(program: Int, operation: Int)
  /// A constant written, a `modify` mask, or a `poll` mask or value does not fit the register.
  case valueExceedsWidth(program: Int, operation: Int)
  /// A `poll` expects bits outside its mask, so it could never match.
  case pollValueOutsideMask(program: Int, operation: Int)
  /// A `poll` makes zero reads or more than ``FastPathLimits/maximumPollIterations``.
  case invalidPollIterations(program: Int, operation: Int)
  /// A `poll` interval exceeds ``FastPathLimits/maximumPollIntervalMicroseconds``.
  case pollIntervalTooLong(program: Int, operation: Int)
  /// A `delay` is zero or exceeds ``FastPathLimits/maximumDelayMicroseconds``.
  case invalidDelay(program: Int, operation: Int)
  /// A program's delays and worst-case poll waits exceed
  /// ``FastPathLimits/maximumDelayBudgetMicroseconds``.
  case delayBudgetExceeded(program: Int, microseconds: UInt64)
  /// A `skip` skips no operations or past the end of its program.
  case invalidSkip(program: Int, operation: Int)
  /// A constant shift distance is 64 or more.
  case shiftOutOfRange(program: Int, operation: Int)
  /// An `emit` names no slots or more than ``FastPathLimits/maximumEmittedSlots``.
  case invalidEmit(program: Int, operation: Int)
  /// A `fail` status is zero, `kIOReturnSuccess`.
  case invalidFailStatus(program: Int, operation: Int)
}
