import Foundation
import Testing

@testable import SwifterKit

@Suite
struct FastPathValidationTests {
  private static let status = FastPathRegister(bar: 0, offset: 0x10, width: .bits32)

  private func validate(
    _ programs: [FastPathProgram],
    barSizes: [UInt8: UInt64] = [0: 0x100],
    interruptSources: [UInt32] = [3],
    hasPCIDevice: Bool = true
  ) throws(FastPathError) {
    try FastPathConfiguration(programs: programs, barSizes: barSizes).validate(
      interruptSources: interruptSources,
      hasPCIDevice: hasPCIDevice
    )
  }

  private func validate(
    _ operations: [FastPathOp],
    barSizes: [UInt8: UInt64] = [0: 0x100]
  ) throws(FastPathError) {
    try validate([FastPathProgram(trigger: .start, operations: operations)], barSizes: barSizes)
  }

  private func accepts(_ operations: [FastPathOp], barSizes: [UInt8: UInt64] = [0: 0x100]) {
    #expect(throws: Never.self) { try validate(operations, barSizes: barSizes) }
  }

  private func refuses(
    _ operations: [FastPathOp],
    barSizes: [UInt8: UInt64] = [0: 0x100],
    with error: FastPathError,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(throws: error, sourceLocation: sourceLocation) {
      try validate(operations, barSizes: barSizes)
    }
  }

  private func program(_ count: Int) -> FastPathProgram {
    FastPathProgram(
      trigger: .command,
      operations: Array(repeating: .compute(.v0, .add, .constant(1)), count: count)
    )
  }

  @Test
  func limitsProgramCount() {
    #expect(throws: FastPathError.noPrograms) { try validate([FastPathProgram]()) }
    #expect(throws: Never.self) { try validate(Array(repeating: program(1), count: 32)) }
    #expect(throws: FastPathError.tooManyPrograms(count: 33)) {
      try validate(Array(repeating: program(1), count: 33))
    }
  }

  @Test
  func limitsOperationCount() {
    #expect(throws: FastPathError.emptyProgram(program: 0)) { try validate([program(0)]) }
    #expect(throws: Never.self) { try validate([program(64)]) }
    #expect(throws: FastPathError.tooManyOperations(program: 1, count: 65)) {
      try validate([program(1), program(65)])
    }
  }

  @Test
  func limitsArgumentsToCommandPrograms() {
    let command = { (count: Int) in
      FastPathProgram(
        trigger: .command,
        argumentCount: count,
        operations: [.delay(microseconds: 1)]
      )
    }
    #expect(throws: Never.self) { try validate([command(4)]) }
    #expect(throws: FastPathError.invalidArgumentCount(program: 0, count: 5)) {
      try validate([command(5)])
    }
    #expect(throws: FastPathError.invalidArgumentCount(program: 0, count: -1)) {
      try validate([command(-1)])
    }
    #expect(throws: FastPathError.argumentsWithoutCommandTrigger(program: 0)) {
      try validate([
        FastPathProgram(trigger: .stop, argumentCount: 1, operations: [.delay(microseconds: 1)])
      ])
    }
  }

  @Test
  func interruptTriggersNameOneConfiguredSourceEach() {
    let handler = { (source: UInt32) in
      FastPathProgram(
        trigger: .interrupt(sourceIndex: source, delivery: .never),
        operations: [.read(Self.status, into: .v0)]
      )
    }
    #expect(throws: Never.self) { try validate([handler(3)]) }
    #expect(throws: FastPathError.unknownInterruptSource(program: 0, sourceIndex: 4)) {
      try validate([handler(4)])
    }
    #expect(throws: FastPathError.unknownInterruptSource(program: 0, sourceIndex: 3)) {
      try validate([handler(3)], interruptSources: [])
    }
    #expect(throws: FastPathError.duplicateInterruptTrigger(program: 1, sourceIndex: 3)) {
      try validate([handler(3), handler(3)])
    }
  }

  @Test
  func registersRequireDeclaredBARsAndAPCIDevice() {
    let read: [FastPathOp] = [.read(Self.status, into: .v0)]
    let program = [FastPathProgram(trigger: .start, operations: read)]
    #expect(throws: FastPathError.registersWithoutPCIDevice) {
      try validate(program, hasPCIDevice: false)
    }
    #expect(throws: FastPathError.registersWithoutPCIDevice) {
      try validate([self.program(1)], barSizes: [0: 4], hasPCIDevice: false)
    }
    #expect(throws: Never.self) {
      try validate([self.program(1)], barSizes: [:], hasPCIDevice: false)
    }
    accepts(read, barSizes: [0: 0x14, 5: 1])
    refuses(read, barSizes: [0: 0x100, 6: 1], with: .invalidBARSize(bar: 6))
    refuses(read, barSizes: [0: 0x100, 2: 0], with: .invalidBARSize(bar: 2))
    refuses(read, barSizes: [1: 0x100], with: .undeclaredBAR(program: 0, operation: 0))
    let bar5 = FastPathRegister(bar: 5, offset: 0, width: .bits8)
    let bar6 = FastPathRegister(bar: 6, offset: 0, width: .bits8)
    accepts([.read(bar5, into: .v0)], barSizes: [5: 1])
    refuses([.read(bar6, into: .v0)], with: .invalidBAR(program: 0, operation: 0))
  }

  @Test
  func registersAreAlignedAndInsideTheirBAR() {
    for width in FastPathRegister.Width.allCases {
      let bytes = UInt64(width.byteCount)
      let last = FastPathRegister(bar: 0, offset: 0x100 - bytes, width: width)
      let past = FastPathRegister(bar: 0, offset: 0x100, width: width)
      accepts([.read(last, into: .v1)])
      refuses([.read(past, into: .v1)], with: .registerOutOfBounds(program: 0, operation: 0))
      if bytes > 1 {
        let misaligned = FastPathRegister(bar: 0, offset: bytes / 2, width: width)
        refuses([.read(misaligned, into: .v1)], with: .misalignedRegister(program: 0, operation: 0))
      }
    }
    let wide = FastPathRegister(bar: 0, offset: 0, width: .bits64)
    refuses(
      [.read(wide, into: .v0)],
      barSizes: [0: 4],
      with: .registerOutOfBounds(program: 0, operation: 0)
    )
    let highest = FastPathRegister(bar: 0, offset: UInt64.max - 7, width: .bits64)
    refuses([.read(highest, into: .v0)], with: .registerOutOfBounds(program: 0, operation: 0))
    refuses(
      [.read(highest, into: .v0)],
      barSizes: [0: .max],
      with: .registerOutOfBounds(program: 0, operation: 0)
    )
    let lastOfLargest = FastPathRegister(bar: 0, offset: UInt64.max - 15, width: .bits64)
    accepts([.read(lastOfLargest, into: .v0)], barSizes: [0: .max])
  }

  @Test
  func valuesFitTheRegisterWidth() {
    let byte = FastPathRegister(bar: 0, offset: 0, width: .bits8)
    let quad = FastPathRegister(bar: 0, offset: 8, width: .bits64)
    let error = FastPathError.valueExceedsWidth(program: 0, operation: 0)
    accepts([
      .write(byte, .constant(0xFF)), .write(quad, .constant(.max)), .write(byte, .value(.v7)),
    ])
    refuses([.write(byte, .constant(0x100))], with: error)
    accepts([.modify(byte, clear: 0xFF, set: 0xFF)])
    refuses([.modify(byte, clear: 0x100, set: 0)], with: error)
    refuses([.modify(byte, clear: 0, set: 0x100)], with: error)
    let poll = { (mask: UInt64, equals: UInt64) -> FastPathOp in
      .poll(byte, mask: mask, equals: equals, maxIterations: 1, intervalMicroseconds: 0)
    }
    accepts([poll(0xFF, 0x80)])
    refuses([poll(0x100, 0)], with: error)
    refuses([poll(0x0F, 0x10)], with: .pollValueOutsideMask(program: 0, operation: 0))
  }

  @Test
  func pollsAndDelaysStayWithinTheirLimits() {
    let poll = { (iterations: UInt32, interval: UInt32) -> FastPathOp in
      .poll(
        Self.status,
        mask: 1,
        equals: 1,
        maxIterations: iterations,
        intervalMicroseconds: interval
      )
    }
    accepts([poll(10_000, 1)])
    accepts([poll(10, 1_000)])
    refuses([poll(0, 1)], with: .invalidPollIterations(program: 0, operation: 0))
    refuses([poll(10_001, 0)], with: .invalidPollIterations(program: 0, operation: 0))
    refuses([poll(UInt32.max, UInt32.max)], with: .invalidPollIterations(program: 0, operation: 0))
    refuses([poll(1, 1_001)], with: .pollIntervalTooLong(program: 0, operation: 0))
    accepts([.delay(microseconds: 1), .delay(microseconds: 1_000)])
    refuses([.delay(microseconds: 0)], with: .invalidDelay(program: 0, operation: 0))
    refuses([.delay(microseconds: 1_001)], with: .invalidDelay(program: 0, operation: 0))
    refuses([.delay(microseconds: .max)], with: .invalidDelay(program: 0, operation: 0))
  }

  @Test
  func limitsEachProgramsDelayBudget() {
    let full: [FastPathOp] =
      Array(repeating: .delay(microseconds: 1_000), count: 9) + [
        .poll(Self.status, mask: 1, equals: 0, maxIterations: 10, intervalMicroseconds: 100)
      ]
    accepts(full)
    refuses(
      full + [.delay(microseconds: 1)],
      with: .delayBudgetExceeded(program: 0, microseconds: 10_001)
    )
    let polls: [FastPathOp] = Array(
      repeating: .poll(
        Self.status,
        mask: 1,
        equals: 0,
        maxIterations: 10_000,
        intervalMicroseconds: 1
      ),
      count: 2
    )
    refuses(polls, with: .delayBudgetExceeded(program: 0, microseconds: 20_000))
  }

  @Test
  func skipsMoveForwardInsideTheProgram() {
    let condition = FastPathCondition(.v0, mask: 1, is: .nonzero)
    let tail: [FastPathOp] = [.delay(microseconds: 1), .fail(status: -1)]
    accepts([.skip(count: 2, if: condition)] + tail)
    refuses([.skip(count: 3, if: condition)] + tail, with: .invalidSkip(program: 0, operation: 0))
    refuses([.skip(count: 0, if: condition)] + tail, with: .invalidSkip(program: 0, operation: 0))
    refuses(tail + [.skip(count: 1, if: condition)], with: .invalidSkip(program: 0, operation: 2))
    refuses([.skip(count: .max, if: condition)], with: .invalidSkip(program: 0, operation: 0))
  }

  @Test
  func computesWithShiftsBelowSixtyFour() {
    for shift in [FastPathComputeOperation.shiftLeft, .shiftRight] {
      accepts([.compute(.v2, shift, .constant(63)), .compute(.v2, shift, .value(.v3))])
      refuses(
        [.compute(.v2, shift, .constant(64))],
        with: .shiftOutOfRange(program: 0, operation: 0)
      )
      refuses(
        [.compute(.v2, shift, .constant(.max))],
        with: .shiftOutOfRange(program: 0, operation: 0)
      )
    }
    accepts(
      [FastPathComputeOperation.and, .or, .xor, .add, .subtract].map {
        .compute(.v4, $0, .constant(.max))
      }
    )
  }

  @Test
  func emitsOneToEightSlotsAndFailsWithAnError() {
    accepts([.emit([.v0]), .emit(FastPathSlot.allCases)])
    refuses([.emit([])], with: .invalidEmit(program: 0, operation: 0))
    refuses([.emit(FastPathSlot.allCases + [.v0])], with: .invalidEmit(program: 0, operation: 0))
    accepts([.fail(status: 1)])
    accepts([.fail(status: Int32(bitPattern: 0xE000_02D6))])
    refuses([.fail(status: 0)], with: .invalidFailStatus(program: 0, operation: 0))
  }

  @Test
  func generatorRefusesInvalidFastPathsWithTheTypedError() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.fast-path",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: [],
      fastPath: FastPathConfiguration(programs: [
        FastPathProgram(trigger: .start, operations: [.read(Self.status, into: .v0)])
      ])
    )
    #expect(
      throws: DriverExtensionGenerationError.invalidFastPathConfiguration(
        .registersWithoutPCIDevice
      )
    ) {
      try withTemporaryExtension(named: "FastPathDriver", configuration: configuration) { _, _ in }
    }
  }
}
