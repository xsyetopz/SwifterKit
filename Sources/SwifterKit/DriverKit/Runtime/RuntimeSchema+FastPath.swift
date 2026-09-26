// Fast-path wire constants: limits, opcodes, operand and trigger codes, and table-row layouts.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeFastPathSchema.h`. The generator
// emits the fast-path tables in `SwifterKitRuntimeConfiguration.h` with these row layouts, and
// the native interpreter reads the same constants, so neither side spells a value twice.

/// Bounds the generator enforces on fast-path programs and the extension re-checks at start.
enum RuntimeFastPathLimits {
  /// The most programs in one configuration.
  static let maximumPrograms = 32
  /// The most operations in one program.
  static let maximumOperations = 64
  /// The scratch value slots, `v0` through `v7`, each 64 bits and zeroed at program entry.
  static let slotCount = 8
  /// The most arguments a command program receives, in `v0` onward.
  static let maximumArguments = 4
  /// The most register reads one `poll` makes.
  static let maximumPollIterations = 10_000
  /// The longest wait between two `poll` reads, in microseconds.
  static let maximumPollIntervalMicroseconds = 1_000
  /// The longest single `delay`, in microseconds.
  static let maximumDelayMicroseconds = 1_000
  /// The most time one program may spend in `delay` and worst-case `poll` waits together.
  static let maximumDelayBudgetMicroseconds = 10_000
  /// The PCI base-address registers a register may name, 0 through 5.
  static let barCount = 6
  /// The shift distance a `shiftLeft` or `shiftRight` constant stays below.
  static let shiftLimit = 64
  /// The most rings in one configuration.
  static let maximumRings = 8
  /// The entry sizes of a ring in bytes; a size must also be a power of two.
  static let ringEntrySizes = 8...4096
  /// The entry counts of a ring; a count must also be a power of two.
  static let ringEntryCounts = 2...65_536
  /// The most bytes every ring occupies together, headers included.
  static let maximumRingBytes = 4 * 1024 * 1024
  /// The bytes of a ring's header, before entry 0.
  static let ringHeaderSize = 64
  /// The header offset of the producer index, a `uint32_t`.
  static let ringProducerOffset = 0
  /// The header offset of the consumer index, a `uint32_t`.
  static let ringConsumerOffset = 4
  /// The header offset of the entry size, a `uint32_t`.
  static let ringEntrySizeOffset = 8
  /// The header offset of the entry count, a `uint32_t`.
  static let ringEntryCountOffset = 12
  /// The most host-shared data queues in one configuration.
  static let maximumDataQueues = 8
  /// The entry bytes of a data queue's host ring; a capacity must also be a power of two.
  static let dataQueueCapacities = 4096...1_048_576
  /// The payload bytes one data queue entry holds at most; a size must also be a multiple of 8.
  static let dataQueueEntrySizes = 8...64
  /// The most bytes every data queue host ring occupies together, headers included.
  static let maximumDataQueueBytes = 4 * 1024 * 1024
  /// The bytes of a data queue host ring's header, before record 0.
  static let dataQueueHeaderSize = 64
  /// The header offset of the producer's free-running record count, a `uint32_t`.
  static let dataQueueProducerOffset = 0
  /// The header offset of the consumer's free-running record count, a `uint32_t`.
  static let dataQueueConsumerOffset = 4
  /// The header offset of the record count, a power-of-two `uint32_t`.
  static let dataQueueEntryCountOffset = 8
  /// The header offset of the record stride in bytes, a power-of-two `uint32_t`.
  static let dataQueueStrideOffset = 12
  /// The header offset of the maximum entry payload size, a `uint32_t`.
  static let dataQueueMaximumEntrySizeOffset = 16
  /// The header offset of the ``RuntimeFastPathDataQueueDirection``, a `uint32_t`.
  static let dataQueueDirectionOffset = 20
  /// The header offset of the count of entries the extension dropped, a `uint64_t`.
  static let dataQueueDropsOffset = 24
  /// The bytes before a record's payload: its payload byte count, a `uint32_t`, then zero.
  static let dataQueueRecordHeaderSize = 8
}

/// What one `SwifterKitFastPathOperation` row does.
///
/// Row fields per opcode, with a register packed into `a` as `bar | widthBytes << 8` and an
/// operand as its ``RuntimeFastPathOperandKind`` in `c` and its value in `immediate1`:
/// - `read`: `a` register, `b` destination slot, `immediate0` offset.
/// - `write`: `a` register, `c` operand kind, `immediate0` offset, `immediate1` operand.
/// - `modify`: `a` register, `immediate0` offset, `immediate1` clear mask, `immediate2` set bits.
/// - `compute`: `a` slot, `b` ``RuntimeFastPathComputeOperation``, `c` operand kind,
///   `immediate1` operand.
/// - `poll`: `a` register, `b` maximum iterations, `c` interval in microseconds, `immediate0`
///   offset, `immediate1` mask, `immediate2` expected value.
/// - `delay`: `b` microseconds.
/// - `skip`: `a` slot, `b` operations skipped, `c` ``RuntimeFastPathConditionTest``,
///   `immediate1` mask.
/// - `emit`: `b` slot count, `immediate1` slot indices, one per byte from the lowest.
/// - `fail`: `b` the `IOReturn` bit pattern.
/// - `ringLoad`: `a` ring index into the ring table `| widthBytes << 8`, `b` entry slot, `c`
///   destination slot, `immediate0` field offset.
/// - `ringStore`: `a` ring index `| widthBytes << 8`, `b` entry slot, `c` operand kind,
///   `immediate0` field offset, `immediate1` operand.
/// - `ringAdvance`: `a` ring index, `b` ``RuntimeFastPathRingIndex``, `c` operand kind,
///   `immediate1` operand.
/// - `enqueue`: `a` data queue index into the data queue table, `b` slot count, `immediate1`
///   slot indices, one per byte from the lowest.
///
/// Unused fields are zero.
enum RuntimeFastPathOpcode: UInt32, CaseIterable {
  case read = 1
  case write = 2
  case modify = 3
  case compute = 4
  case poll = 5
  case delay = 6
  case skip = 7
  case emit = 8
  case fail = 9
  case ringLoad = 10
  case ringStore = 11
  case ringAdvance = 12
  case enqueue = 13
}

/// Which way a host-shared data queue moves entries.
enum RuntimeFastPathDataQueueDirection: UInt32, CaseIterable {
  /// Fast-path `enqueue` operations produce; the host consumes.
  case toHost = 0
  /// The host produces; the extension consumes.
  case toExtension = 1
}

/// How a `write` or `compute` row interprets its operand value.
enum RuntimeFastPathOperandKind: UInt32, CaseIterable {
  /// `immediate1` is the value.
  case constant = 0
  /// `immediate1` is a slot index whose value is used.
  case value = 1
  /// `immediate1` is a ring index `| RuntimeFastPathRingAddressHalf << 8`; the value is that
  /// half of the device address of the ring's entry 0.
  case ringDeviceAddress = 2
  /// `immediate1` is a ring index `| RuntimeFastPathRingIndex << 8`; the value is that index.
  case ringIndex = 3
}

/// The half of a ring device address a `ringDeviceAddress` operand takes.
enum RuntimeFastPathRingAddressHalf: UInt32, CaseIterable {
  case low = 0
  case high = 1
}

/// The ring index a `ringIndex` operand or a `ringAdvance` row names.
enum RuntimeFastPathRingIndex: UInt32, CaseIterable {
  case producer = 0
  case consumer = 1
}

/// The wrapping arithmetic or bitwise operation a `compute` row applies.
enum RuntimeFastPathComputeOperation: UInt32, CaseIterable {
  case and = 1
  case or = 2
  case xor = 3
  case shiftLeft = 4
  case shiftRight = 5
  case add = 6
  case subtract = 7
}

/// When a `skip` row skips: its slot masked by `immediate1` is zero, or is not.
enum RuntimeFastPathConditionTest: UInt32, CaseIterable {
  case zero = 0
  case nonzero = 1
}

/// What runs a program, the `kind` of its `SwifterKitFastPathTrigger` row.
enum RuntimeFastPathTriggerKind: UInt32, CaseIterable {
  /// After the provider starts.
  case start = 1
  /// Before the service tears down.
  case stop = 2
  /// In `InterruptOccurred` for the interrupt source in `source`, before the interrupt event.
  case interrupt = 3
  /// When Swift runs the program by index.
  case command = 4
}

/// Whether an interrupt trigger still delivers the normal interrupt event after its program;
/// non-interrupt triggers use zero.
enum RuntimeFastPathInterruptDelivery: UInt32, CaseIterable {
  case always = 1
  case never = 2
  case whenProgramEmits = 3
}

/// The `IOReturn` values the interpreter and the extension answer with, beside a `fail` row's
/// own status. The extension asserts each against its `IOReturn.h` name.
enum RuntimeFastPathStatus: UInt32, CaseIterable {
  /// The program ran to its end: `kIOReturnSuccess`.
  case success = 0
  /// The fast path is refused: a declared BAR is missing or smaller than declared, the tables
  /// fail re-validation, or a start program failed: `kIOReturnNoResources`.
  case refused = 0xE000_02BE
  /// A row, the program index, or the argument count failed re-validation and nothing ran:
  /// `kIOReturnBadArgument`.
  case rejected = 0xE000_02C2
  /// A `poll` never matched: `kIOReturnTimeout`.
  case timeout = 0xE000_02D6
  /// The fast path has not started or has stopped: `kIOReturnNotReady`.
  case notReady = 0xE000_02D8
}

/// A native table-row or payload layout: its C++ name and fields, all naturally aligned without
/// padding. A field name ending in `[n]` is an array of `n` elements.
struct RuntimeFastPathRow {
  let name: String
  let fields: [(type: String, name: String)]

  /// The row size in bytes, which the rendered header asserts.
  var size: Int {
    fields.reduce(0) { total, field in
      let count = field.name.last == "]" ? Int(field.name.split(separator: "[")[1].dropLast()) : 1
      return total + (field.type == "uint64_t" ? 8 : 4) * (count ?? 1)
    }
  }

  /// One program: its run of `SwifterKitFastPathOperation` rows and its argument count.
  static let program = Self(
    name: "SwifterKitFastPathProgram",
    fields: [
      ("uint32_t", "operationStart"), ("uint32_t", "operationCount"), ("uint32_t", "argumentCount"),
      ("uint32_t", "delayBudgetMicroseconds"),
    ]
  )
  /// One operation; ``RuntimeFastPathOpcode`` documents the fields each opcode reads.
  static let operation = Self(
    name: "SwifterKitFastPathOperation",
    fields: [
      ("uint32_t", "opcode"), ("uint32_t", "a"), ("uint32_t", "b"), ("uint32_t", "c"),
      ("uint64_t", "immediate0"), ("uint64_t", "immediate1"), ("uint64_t", "immediate2"),
    ]
  )
  /// One trigger: what runs `program`, the interrupt source index, and the event delivery.
  static let trigger = Self(
    name: "SwifterKitFastPathTrigger",
    fields: [
      ("uint32_t", "kind"), ("uint32_t", "source"), ("uint32_t", "delivery"),
      ("uint32_t", "program"),
    ]
  )
  /// The minimum size in bytes a program relies on for one BAR.
  static let bar = Self(
    name: "SwifterKitFastPathBAR",
    fields: [("uint32_t", "bar"), ("uint32_t", "reserved"), ("uint64_t", "minimumSize")]
  )

  /// One ring: its identifier, entry geometry, and `kIOMemoryDirection` value.
  static let ring = Self(
    name: "SwifterKitFastPathRing",
    fields: [
      ("uint32_t", "id"), ("uint32_t", "entrySize"), ("uint32_t", "entryCount"),
      ("uint32_t", "direction"),
    ]
  )

  /// One host-shared data queue: its identifier, host ring entry bytes, maximum entry payload
  /// bytes, and ``RuntimeFastPathDataQueueDirection``.
  static let dataQueue = Self(
    name: "SwifterKitFastPathDataQueue",
    fields: [
      ("uint32_t", "id"), ("uint32_t", "capacityBytes"), ("uint32_t", "maximumEntrySize"),
      ("uint32_t", "direction"),
    ]
  )

  /// A `fastPathDataQueue` event, queued once per batch the extension publishes into a host
  /// ring: the queue identifier, the entries published, and the queue's total dropped entries.
  static let dataQueueEvent = Self(
    name: "SwifterKitFastPathDataQueueEvent",
    fields: [("uint32_t", "id"), ("uint32_t", "published"), ("uint64_t", "droppedEntries")]
  )

  /// A `fastPathRun` command payload: the program index and its arguments, unused ones zero.
  static let runRequest = Self(
    name: "SwifterKitFastPathRunRequest",
    fields: [("uint32_t", "program"), ("uint32_t", "argumentCount"), ("uint64_t", "arguments[4]")]
  )
  /// A `fastPathRun` reply: the program's ``RuntimeFastPathStatus`` or `fail` status and its
  /// slots when it ended.
  static let runResult = Self(
    name: "SwifterKitFastPathRunResult",
    fields: [("uint32_t", "status"), ("uint32_t", "reserved"), ("uint64_t", "values[8]")]
  )
  /// A `fastPath` event: the emitting program, the slot count, and the values, unused ones zero.
  static let event = Self(
    name: "SwifterKitFastPathEvent",
    fields: [("uint32_t", "program"), ("uint32_t", "count"), ("uint64_t", "values[8]")]
  )
  /// A `fastPathStatus` reply: whether the fast path runs, and the `emit` events dropped because
  /// the lossy event queue was full.
  static let statusReply = Self(
    name: "SwifterKitFastPathStatusReply",
    fields: [("uint32_t", "status"), ("uint32_t", "reserved"), ("uint64_t", "droppedEvents")]
  )

  /// Every row layout, in header order.
  static let all = [
    program, operation, trigger, bar, ring, dataQueue, runRequest, runResult, event, dataQueueEvent,
    statusReply,
  ]
}
