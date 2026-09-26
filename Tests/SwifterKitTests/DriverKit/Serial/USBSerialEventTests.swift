import Foundation
import Testing

@testable import SwifterKit

@Suite
struct USBSerialEventTests {
  @Test
  func decodesPacketEvents() throws {
    #expect(
      try DriverEvent(type: 0x0610, payload: packet(kind: 1, bytes: [1, 2, 3])).usbSerial()
        == .receivedPacket([1, 2, 3])
    )
    #expect(
      try DriverEvent(type: 0x0610, payload: packet(kind: 2, bytes: [0xA1, 0x20])).usbSerial()
        == .interruptPacket([0xA1, 0x20])
    )
    #expect(
      try DriverEvent(type: 0x0600, payload: [UInt8](repeating: 0, count: 16)).usbSerial() == nil
    )
    #expect(USBSerialEvent.maximumPacketLength == 65_500)
  }

  @Test
  func rejectsMalformedPacketEvents() {
    #expect(throws: SerialRuntimeError.invalidEventKind(3)) {
      try DriverEvent(type: 0x0610, payload: packet(kind: 3, bytes: [1])).usbSerial()
    }
    #expect(throws: SerialRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0610, payload: packet(kind: 1, bytes: [])).usbSerial()
    }
    var mismatched = packet(kind: 1, bytes: [1, 2])
    mismatched[4] = 3
    #expect(throws: SerialRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0610, payload: mismatched).usbSerial()
    }
  }

  private func packet(kind: UInt32, bytes: [UInt8]) -> [UInt8] {
    var data = Data()
    data.appendRuntimeInteger(kind)
    data.appendRuntimeInteger(UInt32(bytes.count))
    return [UInt8](data) + bytes
  }
}
