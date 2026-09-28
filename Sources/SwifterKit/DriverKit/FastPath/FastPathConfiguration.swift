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
  /// Every register must lie inside its declared BAR. The extension refuses to start the fast
  /// path when the device's BAR is smaller.
  public let barSizes: [UInt8: UInt64]
  /// The descriptor rings the extension allocates for DMA when the fast path starts.
  public let rings: [FastPathRing]
  /// The host-shared data queues the extension allocates when the fast path starts.
  public let dataQueues: [FastPathDataQueue]

  /// Creates a fast-path configuration.
  public init(
    programs: [FastPathProgram],
    barSizes: [UInt8: UInt64] = [:],
    rings: [FastPathRing] = [],
    dataQueues: [FastPathDataQueue] = []
  ) {
    self.programs = programs
    self.barSizes = barSizes
    self.rings = rings
    self.dataQueues = dataQueues
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
  /// The most rings in one configuration.
  public static let maximumRings = RuntimeFastPathLimits.maximumRings
  /// The allowed entry sizes of a ring, in bytes. Each is a power of two.
  public static let ringEntrySizes = RuntimeFastPathLimits.ringEntrySizes
  /// The allowed entry counts of a ring. Each is a power of two.
  public static let ringEntryCounts = RuntimeFastPathLimits.ringEntryCounts
  /// The most bytes every ring of a configuration occupies together, headers included.
  public static let maximumRingBytes = RuntimeFastPathLimits.maximumRingBytes
  /// The most data queues in one configuration.
  public static let maximumDataQueues = RuntimeFastPathLimits.maximumDataQueues
  /// The allowed host ring capacities of a data queue, in bytes. Each is a power of two.
  public static let dataQueueCapacities = RuntimeFastPathLimits.dataQueueCapacities
  /// The allowed maximum entry sizes of a data queue, in bytes. Each is a multiple of 8.
  public static let dataQueueEntrySizes = RuntimeFastPathLimits.dataQueueEntrySizes
  /// The most bytes every data queue host ring occupies together, headers included.
  public static let maximumDataQueueBytes = RuntimeFastPathLimits.maximumDataQueueBytes
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
  /// A program that is not run by ``FastPathTrigger/command`` or
  /// ``FastPathTrigger/dataAvailable(_:)`` declares arguments.
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
  /// The configuration has more than ``FastPathLimits/maximumRings`` rings.
  case tooManyRings(count: Int)
  /// A ring's identifier is above `0xFF_FFFF`, or its entry size or count is not a power of two
  /// in ``FastPathLimits/ringEntrySizes`` or ``FastPathLimits/ringEntryCounts``.
  case invalidRing(ring: UInt32)
  /// Two rings share an identifier.
  case duplicateRing(ring: UInt32)
  /// The rings together occupy more than ``FastPathLimits/maximumRingBytes``.
  case ringBytesExceeded(bytes: UInt64)
  /// Rings are declared without ``DriverConfiguration/pciDevice``, the device that DMAs them.
  case ringsWithoutPCIDevice
  /// An operation or operand names a ring the configuration does not declare.
  case unknownRing(program: Int, operation: Int)
  /// A ring field is not aligned to its width or extends past the entry.
  case ringFieldOutOfBounds(program: Int, operation: Int)
  /// The configuration has more than ``FastPathLimits/maximumDataQueues`` data queues.
  case tooManyDataQueues(count: Int)
  /// A data queue fails one of these checks:
  /// - Its identifier is above `0xFF_FFFF`.
  /// - Its capacity is not a power of two in ``FastPathLimits/dataQueueCapacities``.
  /// - Its maximum entry size is not a multiple of 8 in ``FastPathLimits/dataQueueEntrySizes``.
  /// - Its capacity holds fewer than two records.
  case invalidDataQueue(queue: UInt32)
  /// Two data queues share an identifier.
  case duplicateDataQueue(queue: UInt32)
  /// The data queues together occupy more than ``FastPathLimits/maximumDataQueueBytes``.
  case dataQueueBytesExceeded(bytes: UInt64)
  /// An `enqueue` names a data queue the configuration does not declare, or one the host
  /// produces.
  case unknownDataQueue(program: Int, operation: Int)
  /// A ``FastPathTrigger/dataAvailable(_:)`` trigger names a data queue the configuration does
  /// not declare, or one the extension produces.
  case unknownDataAvailableQueue(program: Int, queue: UInt32)
  /// A second program is triggered by the same data queue.
  case duplicateDataAvailableTrigger(program: Int, queue: UInt32)
  /// An `enqueue` names no slots, more than ``FastPathLimits/maximumEmittedSlots``, or more bytes
  /// than the queue's maximum entry size.
  case invalidEnqueue(program: Int, operation: Int)
}
