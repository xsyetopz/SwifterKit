import Foundation
import Testing

@testable import SwifterKit

@Suite struct InterruptTypesTests {
  @Test func configuresNativeTimebaseFlag() {
    #expect(InterruptSourceConfiguration(index: 3).nativeIndex == 3)
    #expect(InterruptSourceConfiguration(index: 7, clock: .continuous).nativeIndex == 0x0001_0007)
  }

  @Test func encodesEnableAndQueries() throws {
    let enable = try DriverCommand.setInterruptEnabled(index: 4, enabled: true)
    #expect(enable.opcode == 0x0100)
    #expect(enable.requiredCapabilities == .interrupts)
    #expect(enable.payload == Data([4, 0, 0, 0, 1, 0, 0, 0]))

    #expect(try DriverCommand.interruptType(index: 4).opcode == 0x0101)
    #expect(try DriverCommand.lastInterrupt(index: 4).maximumResponseSize == 40)
  }

  @Test func rejectsOutOfRangeSource() {
    #expect(throws: InterruptRuntimeError.invalidSourceIndex) {
      try DriverCommand.setInterruptEnabled(index: 65_536, enabled: true)
    }
  }

  @Test func decodesEventAndSnapshot() throws {
    var eventPayload = Data()
    eventPayload.appendRuntimeInteger(UInt32(2))
    eventPayload.appendRuntimeInteger(UInt32(0))
    eventPayload.appendRuntimeInteger(UInt64(9))
    eventPayload.appendRuntimeInteger(UInt64(42))

    let event = DriverEvent(type: 0x0100, payload: Array(eventPayload))
    #expect(try event.interrupt() == InterruptEvent(sourceIndex: 2, count: 9, time: 42))
    #expect(try DriverEvent(type: 0x0300).interrupt() == nil)

    var snapshot = Data()
    snapshot.appendRuntimeInteger(UInt64(11))
    snapshot.appendRuntimeInteger(UInt64(84))
    #expect(
      try InterruptSnapshot(runtimePayload: snapshot) == InterruptSnapshot(count: 11, time: 84)
    )
  }

  @Test func rejectsMalformedPayloads() {
    #expect(throws: InterruptRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0100, payload: [0]).interrupt()
    }
    #expect(throws: InterruptRuntimeError.invalidPayload) {
      try InterruptSnapshot(runtimePayload: Data(repeating: 0, count: 15))
    }
  }
}
