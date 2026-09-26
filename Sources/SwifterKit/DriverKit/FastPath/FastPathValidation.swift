import Foundation

extension FastPathConfiguration {
  /// Checks every program against ``FastPathLimits`` and the driver's interrupt sources and PCI
  /// device.
  ///
  /// The generator calls this before emitting the tables; nothing is truncated or clamped.
  public func validate(for configuration: DriverConfiguration) throws(FastPathError) {
    try validate(
      interruptSources: configuration.interruptSources.map(\.index),
      hasPCIDevice: configuration.pciDevice != nil
    )
  }

  func validate(interruptSources: [UInt32], hasPCIDevice: Bool) throws(FastPathError) {
    guard !programs.isEmpty else { throw .noPrograms }
    guard programs.count <= FastPathLimits.maximumPrograms else {
      throw .tooManyPrograms(count: programs.count)
    }
    for (bar, size) in barSizes.sorted(by: { $0.key < $1.key })
    where bar > FastPathLimits.maximumBAR || size == 0 { throw .invalidBARSize(bar: bar) }
    let usesRegisters = programs.contains { $0.operations.contains { $0.register != nil } }
    if (usesRegisters || !barSizes.isEmpty) && !hasPCIDevice { throw .registersWithoutPCIDevice }
    var interruptTriggers: Set<UInt32> = []
    for (index, program) in programs.enumerated() {
      try program.validate(index: index, barSizes: barSizes)
      if case .interrupt(let source, _) = program.trigger {
        guard interruptSources.contains(source) else {
          throw .unknownInterruptSource(program: index, sourceIndex: source)
        }
        guard interruptTriggers.insert(source).inserted else {
          throw .duplicateInterruptTrigger(program: index, sourceIndex: source)
        }
      }
    }
  }
}

extension FastPathProgram {
  /// The most time the program waits in `delay` operations and `poll` intervals, in
  /// microseconds. Call after each operation is within its own limits.
  var delayBudgetMicroseconds: UInt64 {
    operations.reduce(0) { total, operation in
      switch operation {
      case .delay(let microseconds): total + UInt64(microseconds)
      case .poll(_, _, _, let iterations, let interval):
        total + UInt64(iterations) * UInt64(interval)
      default: total
      }
    }
  }

  func validate(index: Int, barSizes: [UInt8: UInt64]) throws(FastPathError) {
    guard !operations.isEmpty else { throw .emptyProgram(program: index) }
    guard operations.count <= FastPathLimits.maximumOperations else {
      throw .tooManyOperations(program: index, count: operations.count)
    }
    guard (0...FastPathLimits.maximumArguments).contains(argumentCount) else {
      throw .invalidArgumentCount(program: index, count: argumentCount)
    }
    if argumentCount > 0, trigger != .command {
      throw .argumentsWithoutCommandTrigger(program: index)
    }
    for (position, operation) in operations.enumerated() {
      try operation.validate(
        program: index,
        operation: position,
        remaining: operations.count - position - 1,
        barSizes: barSizes
      )
    }
    let budget = delayBudgetMicroseconds
    guard budget <= FastPathLimits.maximumDelayBudgetMicroseconds else {
      throw .delayBudgetExceeded(program: index, microseconds: budget)
    }
  }
}

extension FastPathOp {
  /// The register the operation accesses, if any.
  var register: FastPathRegister? {
    switch self {
    case .read(let register, _), .write(let register, _), .modify(let register, _, _),
      .poll(let register, _, _, _, _):
      register
    case .compute, .delay, .skip, .emit, .fail: nil
    }
  }

  func validate(
    program: Int,
    operation: Int,
    remaining: Int,
    barSizes: [UInt8: UInt64]
  ) throws(FastPathError) {
    if let register {
      try register.validate(program: program, operation: operation, barSizes: barSizes)
    }
    let width = register?.width.mask ?? .max
    var fits = true
    switch self {
    case .read: break
    case .write(_, let operand): if case .constant(let value) = operand { fits = value <= width }
    case .modify(_, let clear, let set): fits = clear <= width && set <= width
    case .compute(_, let computation, let operand):
      if case .constant(let distance) = operand, [.shiftLeft, .shiftRight].contains(computation),
        distance >= RuntimeFastPathLimits.shiftLimit
      {
        throw .shiftOutOfRange(program: program, operation: operation)
      }
    case .poll(_, let mask, let equals, let iterations, let interval):
      guard mask <= width, equals <= width else {
        throw .valueExceedsWidth(program: program, operation: operation)
      }
      guard equals & ~mask == 0 else {
        throw .pollValueOutsideMask(program: program, operation: operation)
      }
      guard (1...FastPathLimits.maximumPollIterations).contains(Int(iterations)) else {
        throw .invalidPollIterations(program: program, operation: operation)
      }
      guard interval <= FastPathLimits.maximumPollIntervalMicroseconds else {
        throw .pollIntervalTooLong(program: program, operation: operation)
      }
    case .delay(let microseconds):
      guard (1...FastPathLimits.maximumDelayMicroseconds).contains(Int(microseconds)) else {
        throw .invalidDelay(program: program, operation: operation)
      }
    case .skip(let count, _):
      guard count > 0, Int(count) <= remaining else {
        throw .invalidSkip(program: program, operation: operation)
      }
    case .emit(let slots):
      guard (1...FastPathLimits.maximumEmittedSlots).contains(slots.count) else {
        throw .invalidEmit(program: program, operation: operation)
      }
    case .fail(let status):
      guard status != 0 else { throw .invalidFailStatus(program: program, operation: operation) }
    }
    guard fits else { throw .valueExceedsWidth(program: program, operation: operation) }
  }
}

extension FastPathRegister {
  func validate(program: Int, operation: Int, barSizes: [UInt8: UInt64]) throws(FastPathError) {
    guard bar <= FastPathLimits.maximumBAR else {
      throw .invalidBAR(program: program, operation: operation)
    }
    guard let size = barSizes[bar] else {
      throw .undeclaredBAR(program: program, operation: operation)
    }
    let bytes = UInt64(width.byteCount)
    guard offset.isMultiple(of: bytes) else {
      throw .misalignedRegister(program: program, operation: operation)
    }
    guard size >= bytes, offset <= size - bytes else {
      throw .registerOutOfBounds(program: program, operation: operation)
    }
  }
}
