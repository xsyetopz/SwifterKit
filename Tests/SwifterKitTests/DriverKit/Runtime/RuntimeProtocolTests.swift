import Foundation
import Testing

@testable import SwifterKit

@Suite
struct RuntimeProtocolTests {
  @Test
  func roundTripsCompleteMessage() throws {
    let message = RuntimeMessage(
      kind: .command,
      requestID: 42,
      flags: .expectsResponse,
      payload: Data([1, 2, 3])
    )

    let decoded = try RuntimeMessage(decoding: message.encoded())

    #expect(decoded == message)
    #expect(try message.encoded().count == RuntimeMessage.headerSize + 3)
  }

  @Test
  func rejectsTruncatedHeader() {
    #expect(throws: RuntimeProtocolError.truncatedHeader) {
      try RuntimeMessage(decoding: Data(repeating: 0, count: RuntimeMessage.headerSize - 1))
    }
  }

  @Test
  func rejectsInvalidMagic() throws {
    var encoded = try RuntimeMessage(kind: .handshake, requestID: 0).encoded()
    encoded[0] = 0

    #expect(throws: RuntimeProtocolError.invalidMagic) { try RuntimeMessage(decoding: encoded) }
  }

  @Test(arguments: [UInt16(1), RuntimeSchema.maximumVersion + 1])
  func rejectsUnsupportedVersion(version: UInt16) throws {
    let encoded = try RuntimeMessage(
      version: RuntimeProtocolVersion(rawValue: version),
      kind: .handshake,
      requestID: 0
    ).encoded()

    #expect(throws: RuntimeProtocolError.unsupportedVersion(version)) {
      try RuntimeMessage(decoding: encoded)
    }
  }

  @Test
  func decodesEverySupportedVersion() throws {
    for rawValue in RuntimeSchema.minimumVersion...RuntimeSchema.maximumVersion {
      let version = RuntimeProtocolVersion(rawValue: rawValue)
      let message = RuntimeMessage(version: version, kind: .response, requestID: 3)

      #expect(try RuntimeMessage(decoding: message.encoded()).version == version)
    }
    #expect(RuntimeProtocolVersion.current == .version2)
  }

  @Test
  func encodesHeaderFieldsAtFixedOffsets() throws {
    let encoded = try RuntimeMessage(
      kind: .command,
      requestID: 0x0102_0304_0506_0708,
      flags: .expectsResponse,
      payload: Data([0xAA])
    ).encoded()

    #expect(
      Array(encoded) == [
        0x54, 0x4B, 0x57, 0x53, 0x02, 0x00, 0x02, 0x00, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02,
        0x01, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xAA,
      ]
    )
  }

  @Test
  func rejectsMessagesLargerThanMaximumSize() throws {
    let largest = RuntimeMessage.maximumSize - RuntimeMessage.headerSize
    let fitting = RuntimeMessage(kind: .command, requestID: 1, payload: Data(count: largest))
    let oversize = RuntimeMessage(kind: .command, requestID: 1, payload: Data(count: largest + 1))

    #expect(RuntimeMessage.maximumSize == 65_536)
    #expect(try fitting.encoded().count == RuntimeMessage.maximumSize)
    #expect(throws: RuntimeProtocolError.payloadTooLarge) { try oversize.encoded() }
  }

  @Test
  func encodesHandshakeOfferAndAcceptanceLayouts() throws {
    let offer = RuntimeHandshakeOffer(versions: .version2...RuntimeProtocolVersion(rawValue: 5))
    let acceptance = RuntimeHandshakeAcceptance(version: .version2, capabilities: [.usb, .video])

    #expect(Array(offer.encoded()) == [0x02, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00])
    #expect(
      Array(acceptance.encoded()) == [
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00,
      ]
    )
    #expect(try RuntimeHandshakeOffer(decoding: offer.encoded()) == offer)
    #expect(try RuntimeHandshakeAcceptance(decoding: acceptance.encoded()) == acceptance)
    #expect(throws: DriverRuntimeError.invalidHandshake) {
      try RuntimeHandshakeAcceptance(decoding: Data(count: 8))
    }
  }

  @Test
  func rejectsUnknownMessageKind() throws {
    var encoded = try RuntimeMessage(kind: .handshake, requestID: 0).encoded()
    encoded[6] = 0xFF
    encoded[7] = 0xFF

    #expect(throws: RuntimeProtocolError.unknownMessageKind) {
      try RuntimeMessage(decoding: encoded)
    }
  }

  @Test
  func rejectsMismatchedPayloadLength() throws {
    var encoded = try RuntimeMessage(kind: .command, requestID: 1, payload: Data([1])).encoded()
    encoded[16] = 2

    #expect(throws: RuntimeProtocolError.invalidPayloadLength) {
      try RuntimeMessage(decoding: encoded)
    }
  }
}
