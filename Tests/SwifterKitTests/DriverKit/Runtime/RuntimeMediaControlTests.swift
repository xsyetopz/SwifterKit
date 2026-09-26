import Foundation
import Testing

@testable import SwifterKit

@Suite
struct RuntimeMediaControlTests {
  private struct Invalid: Error, Equatable {}

  @Test
  func controlPayloadRoundTripsKindAndWords() throws {
    let payload = try Data.runtimeControlPayload(
      identifier: 9,
      kind: 4,
      values: [10, 20],
      maximumItems: 2,
      invalidValue: Invalid()
    )
    #expect(payload.count == 24)
    #expect(try payload.readRuntimeInteger(at: 0) as UInt32 == 9)
    let decoded = try payload.readRuntimeControlWords(maximumItems: 2, invalidPayload: Invalid())
    #expect(decoded.kind == 4)
    #expect(decoded.values == [10, 20])
  }

  @Test
  func controlPayloadRejectsEmptyOversizedAndMalformedValues() {
    #expect(throws: Invalid()) {
      try Data.runtimeControlPayload(
        identifier: 1,
        kind: 1,
        values: [],
        maximumItems: 2,
        invalidValue: Invalid()
      )
    }
    #expect(throws: Invalid()) {
      try Data.runtimeControlPayload(
        identifier: 1,
        kind: 1,
        values: [1, 2, 3],
        maximumItems: 2,
        invalidValue: Invalid()
      )
    }
    var reserved = Data()
    for word in [UInt32(1), 1, 1, 7, 0] { reserved.appendRuntimeInteger(word) }
    #expect(throws: Invalid()) {
      try reserved.readRuntimeControlWords(maximumItems: 2, invalidPayload: Invalid())
    }
    #expect(throws: Invalid()) {
      try reserved.prefix(15).readRuntimeControlWords(maximumItems: 2, invalidPayload: Invalid())
    }
  }

  @Test
  func customPropertyCommandCarriesFamilyCapabilityAndLimits() throws {
    let command = try DriverCommand.runtimeCustomPropertyCommand(
      opcode: .videoSetCustomProperty,
      requiredCapabilities: .video,
      identifier: 3,
      qualifier: "Mode",
      value: "On",
      nameMaximumLength: 4,
      valueMaximumLength: 2,
      invalidValue: Invalid()
    )
    #expect(command.requiredCapabilities == .video)
    #expect(command.payload.suffix(6) == Data("ModeOn".utf8))
    #expect(command.maximumResponseSize == RuntimeMessage.headerSize + 2)
    #expect(throws: Invalid()) {
      try DriverCommand.runtimeCustomPropertyCommand(
        opcode: .videoGetCustomProperty,
        requiredCapabilities: .video,
        identifier: 3,
        qualifier: "Modes",
        value: nil,
        nameMaximumLength: 4,
        valueMaximumLength: 2,
        invalidValue: Invalid()
      )
    }
  }
}
