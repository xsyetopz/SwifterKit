extension DriverExtensionGenerator {
  /// Native fast-path tables in the row layouts of `RuntimeFastPathRow`.
  ///
  /// Each program indexes a run of the shared operation table; each has one trigger row. Arrays
  /// hold at least one element so the tables stay valid C++ when they are empty.
  static func fastPathDeclarations(_ fastPath: FastPathConfiguration?) -> String {
    let programs = fastPath?.programs ?? []
    var operations: [String] = []
    var programRows: [String] = []
    var triggers: [String] = []
    for (index, program) in programs.enumerated() {
      programRows.append(
        row([
          "\(operations.count)", "\(program.operations.count)", "\(program.argumentCount)",
          "\(program.delayBudgetMicroseconds)",
        ])
      )
      operations += program.operations.map(fastPathRow)
      triggers.append(fastPathRow(program.trigger, program: index))
    }
    let bars = (fastPath?.barSizes ?? [:]).sorted { $0.key < $1.key }.map {
      row(["\($0.key)", "0", "\($0.value)ULL"])
    }
    func table(_ type: String, _ name: String, _ rows: [String]) -> String {
      let body = rows.isEmpty ? "{}" : "{\n" + rows.joined(separator: ",\n") + "\n}"
      return """
        static constexpr \(type) \(name)[\(max(rows.count, 1))] = \(body);
        static constexpr uint32_t \(name.dropLast())Count = \(rows.count);
        """
    }
    return [
      table("SwifterKitFastPathProgram", "kSwifterKitFastPathPrograms", programRows),
      table("SwifterKitFastPathOperation", "kSwifterKitFastPathOperations", operations),
      table("SwifterKitFastPathTrigger", "kSwifterKitFastPathTriggers", triggers),
      table("SwifterKitFastPathBAR", "kSwifterKitFastPathBARSizes", bars),
    ].joined(separator: "\n")
  }

  private static func row(_ fields: [String]) -> String {
    "    {" + fields.joined(separator: ", ") + "}"
  }

  private static func fastPathRow(_ trigger: FastPathTrigger, program: Int) -> String {
    let kind: RuntimeFastPathTriggerKind
    var source: UInt32 = 0
    var delivery: UInt32 = 0
    switch trigger {
    case .start: kind = .start
    case .stop: kind = .stop
    case .command: kind = .command
    case .interrupt(let sourceIndex, let value):
      kind = .interrupt
      source = sourceIndex
      let native: RuntimeFastPathInterruptDelivery =
        switch value {
        case .always: .always
        case .never: .never
        case .whenProgramEmits: .whenProgramEmits
        }
      delivery = native.rawValue
    }
    return row(["\(kind.rawValue)", "\(source)", "\(delivery)", "\(program)"])
  }

  /// One `SwifterKitFastPathOperation` row, in the field use `RuntimeFastPathOpcode` documents.
  private static func fastPathRow(_ operation: FastPathOp) -> String {
    var fields: (a: UInt32, b: UInt32, c: UInt32) = (0, 0, 0)
    var immediates: [UInt64] = [0, 0, 0]
    let opcode: RuntimeFastPathOpcode
    if let register = operation.register {
      fields.a = UInt32(register.bar) | UInt32(register.width.rawValue) << 8
      immediates[0] = register.offset
    }
    switch operation {
    case .read(_, let slot):
      opcode = .read
      fields.b = UInt32(slot.rawValue)
    case .write(_, let operand):
      opcode = .write
      (fields.c, immediates[1]) = encoded(operand)
    case .modify(_, let clear, let set):
      opcode = .modify
      immediates[1] = clear
      immediates[2] = set
    case .compute(let slot, let computation, let operand):
      opcode = .compute
      fields.a = UInt32(slot.rawValue)
      fields.b = encoded(computation).rawValue
      (fields.c, immediates[1]) = encoded(operand)
    case .poll(_, let mask, let equals, let iterations, let interval):
      opcode = .poll
      fields.b = iterations
      fields.c = interval
      immediates[1] = mask
      immediates[2] = equals
    case .delay(let microseconds):
      opcode = .delay
      fields.b = microseconds
    case .skip(let count, let condition):
      opcode = .skip
      fields.a = UInt32(condition.slot.rawValue)
      fields.b = count
      fields.c =
        (condition.test == .zero
        ? RuntimeFastPathConditionTest.zero : RuntimeFastPathConditionTest.nonzero).rawValue
      immediates[1] = condition.mask
    case .emit(let slots):
      opcode = .emit
      fields.b = UInt32(slots.count)
      immediates[1] = slots.enumerated().reduce(0) {
        $0 | UInt64($1.element.rawValue) << (8 * UInt64($1.offset))
      }
    case .fail(let status):
      opcode = .fail
      fields.b = UInt32(bitPattern: status)
    }
    // An IOReturn reads best, and stays unsigned, in hex.
    let b = opcode == .fail ? RuntimeSchemaHeader.hex(fields.b, digits: 8) : "\(fields.b)"
    return row(
      ["\(opcode.rawValue)", "\(fields.a)", b, "\(fields.c)"] + immediates.map { "\($0)ULL" }
    )
  }

  private static func encoded(_ operand: FastPathOperand) -> (UInt32, UInt64) {
    switch operand {
    case .constant(let value): (RuntimeFastPathOperandKind.constant.rawValue, value)
    case .value(let slot): (RuntimeFastPathOperandKind.value.rawValue, UInt64(slot.rawValue))
    }
  }

  private static func encoded(
    _ computation: FastPathComputeOperation
  ) -> RuntimeFastPathComputeOperation {
    switch computation {
    case .and: .and
    case .or: .or
    case .xor: .xor
    case .shiftLeft: .shiftLeft
    case .shiftRight: .shiftRight
    case .add: .add
    case .subtract: .subtract
    }
  }
}
