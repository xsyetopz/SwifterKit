import Foundation

/// A memory-mapped device register inside one PCI base-address register.
public struct FastPathRegister: Sendable, Hashable {
  /// The width of one register access.
  public enum Width: UInt8, Sendable, Hashable, CaseIterable {
    /// An 8-bit access.
    case bits8 = 1
    /// A 16-bit access.
    case bits16 = 2
    /// A 32-bit access.
    case bits32 = 4
    /// A 64-bit access.
    case bits64 = 8

    /// The access size in bytes.
    public var byteCount: Int { Int(rawValue) }

    /// The largest value the register holds.
    var mask: UInt64 { self == .bits64 ? .max : (1 << (UInt64(rawValue) * 8)) - 1 }
  }

  /// The base-address register index, 0 through 5.
  public let bar: UInt8
  /// The byte offset inside the BAR, a multiple of the width.
  public let offset: UInt64
  /// The access width.
  public let width: Width

  /// Creates a register reference.
  public init(bar: UInt8, offset: UInt64, width: Width) {
    self.bar = bar
    self.offset = offset
    self.width = width
  }
}

/// One of the eight 64-bit scratch values a program works in, zeroed at program entry.
///
/// A command program receives its arguments in `v0` onward.
public enum FastPathSlot: UInt8, Sendable, Hashable, CaseIterable {
  /// Slot 0, the first argument.
  case v0
  /// Slot 1, the second argument.
  case v1
  /// Slot 2, the third argument.
  case v2
  /// Slot 3, the fourth argument.
  case v3
  /// Slot 4.
  case v4
  /// Slot 5.
  case v5
  /// Slot 6.
  case v6
  /// Slot 7.
  case v7
}

/// A value an operation writes or computes with.
public enum FastPathOperand: Sendable, Hashable {
  /// A constant.
  case constant(UInt64)
  /// The current value of a slot.
  case value(FastPathSlot)
  /// Half of the device address of entry 0 of the ring with this identifier.
  case ringDeviceAddress(UInt32, FastPathRingAddressHalf)
  /// The current producer or consumer index of the ring with this identifier.
  case ringIndex(UInt32, FastPathRingIndex)
}

/// A wrapping 64-bit operation that `compute` applies to a slot.
public enum FastPathComputeOperation: Sendable, Hashable, CaseIterable {
  /// Bitwise AND.
  case and
  /// Bitwise OR.
  case or
  /// Bitwise exclusive OR.
  case xor
  /// Logical shift left; a constant distance must be below 64, a slot distance uses its low six
  /// bits.
  case shiftLeft
  /// Logical shift right; a constant distance must be below 64, a slot distance uses its low six
  /// bits.
  case shiftRight
  /// Wrapping addition.
  case add
  /// Wrapping subtraction.
  case subtract
}

/// A test of one slot's bits that decides whether `skip` skips.
public struct FastPathCondition: Sendable, Hashable {
  /// What the masked bits must be for the condition to hold.
  public enum Test: Sendable, Hashable {
    /// Every masked bit is clear.
    case zero
    /// At least one masked bit is set.
    case nonzero
  }

  /// The slot tested.
  public let slot: FastPathSlot
  /// The bits tested.
  public let mask: UInt64
  /// What the masked bits must be.
  public let test: Test

  /// Creates a condition on `slot & mask`.
  public init(_ slot: FastPathSlot, mask: UInt64 = .max, is test: Test) {
    self.slot = slot
    self.mask = mask
    self.test = test
  }
}

/// One step of a fast-path program. The set is closed and every operation terminates: there are
/// no loops, only bounded polls and forward skips.
public enum FastPathOp: Sendable, Hashable {
  /// Reads a register into a slot, zero-extended.
  case read(FastPathRegister, into: FastPathSlot)
  /// Writes an operand to a register; a constant must fit the register width.
  case write(FastPathRegister, FastPathOperand)
  /// Reads a register, clears the `clear` bits, sets the `set` bits, and writes it back. Both
  /// masks must fit the register width.
  case modify(FastPathRegister, clear: UInt64, set: UInt64)
  /// Replaces a slot with the result of applying an operation to it and an operand.
  case compute(FastPathSlot, FastPathComputeOperation, FastPathOperand)
  /// Reads a register until `value & mask == equals`, at most `maxIterations` times with
  /// `intervalMicroseconds` between reads; when it never matches, the program ends with
  /// `kIOReturnTimeout`.
  case poll(
    FastPathRegister,
    mask: UInt64,
    equals: UInt64,
    maxIterations: UInt32,
    intervalMicroseconds: UInt32
  )
  /// Waits for a number of microseconds.
  case delay(microseconds: UInt32)
  /// Skips the next `count` operations when the condition holds. Skips only move forward, so
  /// every program terminates.
  case skip(count: UInt32, if: FastPathCondition)
  /// Delivers the values of up to eight slots to Swift as one event.
  case emit([FastPathSlot])
  /// Ends the program with a nonzero `IOReturn`.
  case fail(status: Int32)
  /// Reads `width` bytes at `fieldOffset` of the ring entry whose index is in `entry`, masked by
  /// the entry count, into a slot, zero-extended. The field is aligned to its width and lies
  /// inside the entry.
  case ringLoad(
    UInt32,
    entry: FastPathSlot,
    fieldOffset: UInt32,
    width: FastPathRegister.Width,
    into: FastPathSlot
  )
  /// Writes an operand to `width` bytes at `fieldOffset` of the ring entry whose index is in
  /// `entry`, masked by the entry count; a constant must fit the width.
  case ringStore(
    UInt32,
    entry: FastPathSlot,
    fieldOffset: UInt32,
    width: FastPathRegister.Width,
    FastPathOperand
  )
  /// Adds an operand to a ring index, wrapping by the entry count.
  case ringAdvance(UInt32, FastPathRingIndex, by: FastPathOperand)
  /// Appends the slots' values, 8 little-endian bytes each in order, as one entry of the
  /// ``FastPathDataQueueDirection/toHost`` data queue with this identifier. An entry that finds
  /// the queue full is dropped and counted; the program continues either way.
  case enqueue(UInt32, slots: [FastPathSlot])
}

/// What runs a fast-path program.
public enum FastPathTrigger: Sendable, Hashable {
  /// Whether the normal ``InterruptEvent`` still reaches Swift after an interrupt program runs.
  public enum Delivery: Sendable, Hashable, CaseIterable {
    /// The event is always delivered.
    case always
    /// The program handles the interrupt; the event is not delivered.
    case never
    /// The event is delivered when the program ran an `emit`.
    case whenProgramEmits
  }

  /// After the provider starts.
  case start
  /// Before the service tears down.
  case stop
  /// When the configured interrupt source with this provider index fires, before its event.
  case interrupt(sourceIndex: UInt32, delivery: Delivery)
  /// When Swift runs the program.
  case command
  /// Once for each entry of the ``FastPathDataQueueDirection/toExtension`` data queue with this
  /// identifier, on the extension's runtime queue, with the entry's first
  /// ``FastPathProgram/argumentCount`` little-endian 64-bit words in `v0` onward; words the entry
  /// does not hold are zero. A queue has at most one such program.
  case dataAvailable(UInt32)
}

/// A bounded sequence of fast-path operations and the trigger that runs it.
public struct FastPathProgram: Sendable, Hashable {
  /// What runs the program.
  public let trigger: FastPathTrigger
  /// The arguments a command program receives in `v0` onward, at most four.
  public let argumentCount: Int
  /// The operations, run in order.
  public let operations: [FastPathOp]

  /// Creates a program.
  public init(trigger: FastPathTrigger, argumentCount: Int = 0, operations: [FastPathOp]) {
    self.trigger = trigger
    self.argumentCount = argumentCount
    self.operations = operations
  }
}
