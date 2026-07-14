import Foundation
import Testing

@testable import SwifterKit

@Suite struct RuntimeProtocolTests {
  @Test func roundTripsCompleteMessage() throws {
    let message = RuntimeMessage(
      kind: .command,
      requestID: 42,
      flags: [.expectsResponse, .finalFragment],
      payload: Data([1, 2, 3])
    )

    let decoded = try RuntimeMessage(decoding: message.encoded())

    #expect(decoded == message)
    #expect(try message.encoded().count == RuntimeMessage.headerSize + 3)
  }

  @Test func rejectsTruncatedHeader() {
    #expect(throws: RuntimeProtocolError.truncatedHeader) {
      try RuntimeMessage(decoding: Data(repeating: 0, count: RuntimeMessage.headerSize - 1))
    }
  }

  @Test func rejectsInvalidMagic() throws {
    var encoded = try RuntimeMessage(kind: .handshake, requestID: 0).encoded()
    encoded[0] = 0

    #expect(throws: RuntimeProtocolError.invalidMagic) { try RuntimeMessage(decoding: encoded) }
  }

  @Test func rejectsUnsupportedVersion() throws {
    var encoded = try RuntimeMessage(kind: .handshake, requestID: 0).encoded()
    encoded[4] = 2

    #expect(throws: RuntimeProtocolError.unsupportedVersion(2)) {
      try RuntimeMessage(decoding: encoded)
    }
  }

  @Test func rejectsUnknownMessageKind() throws {
    var encoded = try RuntimeMessage(kind: .handshake, requestID: 0).encoded()
    encoded[6] = 0xFF
    encoded[7] = 0xFF

    #expect(throws: RuntimeProtocolError.unknownMessageKind) {
      try RuntimeMessage(decoding: encoded)
    }
  }

  @Test func rejectsMismatchedPayloadLength() throws {
    var encoded = try RuntimeMessage(kind: .command, requestID: 1, payload: Data([1])).encoded()
    encoded[16] = 2

    #expect(throws: RuntimeProtocolError.invalidPayloadLength) {
      try RuntimeMessage(decoding: encoded)
    }
  }
}
