import Foundation
import Testing

@testable import SwifterKit

@Suite struct DriverCommandTests {
  @Test func encodesOpcodeCapabilitiesAndPayload() throws {
    let command = DriverCommand(
      opcode: 42,
      requiredCapabilities: [.usb, .memory],
      payload: Data([1, 2])
    )

    let encoded = try command.encodedPayload()
    let opcode: UInt32 = try encoded.readRuntimeInteger(at: 0)
    let reserved: UInt32 = try encoded.readRuntimeInteger(at: 4)
    let capabilities: UInt64 = try encoded.readRuntimeInteger(at: 8)

    #expect(opcode == 42)
    #expect(reserved == 0)
    #expect(capabilities == RuntimeCapabilities([.usb, .memory]).rawValue)
    #expect(encoded.dropFirst(16) == Data([1, 2]))
  }

  @Test func integerReaderRejectsTruncatedValue() {
    #expect(throws: RuntimeProtocolError.truncatedPayload) {
      let _: UInt64 = try Data([1]).readRuntimeInteger(at: 0)
    }
  }
}
