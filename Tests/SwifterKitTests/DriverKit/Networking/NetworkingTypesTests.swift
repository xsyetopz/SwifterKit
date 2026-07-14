import Foundation
import Testing

@testable import SwifterKit

@Suite struct NetworkingTypesTests {
  @Test func encodesReceiveCompletionAndLinkCommands() throws {
    let receive = try DriverCommand.ethernetReceive(frame: Data([1, 2, 3]), linkHeaderLength: 14)
    #expect(receive.opcode == 0x0900)
    #expect(receive.requiredCapabilities == .networking)
    #expect(receive.payload == Data([3, 0, 0, 0, 14, 0, 0, 0, 1, 2, 3]))

    let completion = DriverCommand.completeEthernetTransmit(requestID: 7, status: -1)
    #expect(completion.opcode == 0x0901)
    #expect(completion.payload == Data([7, 0, 0, 0, 255, 255, 255, 255]))

    let link = DriverCommand.reportEthernetLink(active: true, media: .base1000T)
    #expect(link.opcode == 0x0902)
    #expect(link.payload == Data([3, 0, 0, 0, 48, 0, 0, 0]))
  }

  @Test func decodesTransmitAndControlEvents() throws {
    let transmit = DriverEvent(
      type: 0x0900,
      payload: [2, 0, 0, 0, 9, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 1, 2, 3]
    )
    #expect(
      try transmit.ethernet()
        == .transmit(EthernetTransmitRequest(requestID: 9, frame: Data([1, 2, 3])))
    )

    let enable = DriverEvent(
      type: 0x0900,
      payload: [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
    )
    #expect(try enable.ethernet() == .interfaceEnabled(true))

    let address = DriverEvent(
      type: 0x0900,
      payload: [11, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 0, 0, 2, 3, 4, 5, 6, 7]
    )
    #expect(try address.ethernet() == .hardwareAddress(EthernetAddress(2, 3, 4, 5, 6, 7)))

    let multicast = DriverEvent(
      type: 0x0900,
      payload: [4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 0, 0, 1, 2, 3, 4, 5, 6]
    )
    #expect(try multicast.ethernet() == .multicastAddresses([EthernetAddress(1, 2, 3, 4, 5, 6)]))
  }

  @Test func rejectsInvalidCommandsAndEvents() throws {
    #expect(throws: EthernetRuntimeError.emptyFrame) {
      try DriverCommand.ethernetReceive(frame: Data())
    }
    #expect(throws: EthernetRuntimeError.frameTooLarge) {
      try DriverCommand.ethernetReceive(frame: Data(repeating: 0, count: 65_481))
    }
    let malformed = DriverEvent(
      type: 0x0900,
      payload: [2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1]
    )
    #expect(throws: EthernetRuntimeError.invalidPayload) { try malformed.ethernet() }
    #expect(try DriverEvent(type: 1, payload: []).ethernet() == nil)
  }

  @Test func configurationPreservesRawMediaAndAddress() {
    let config = EthernetDeviceConfiguration(
      hardwareAddress: EthernetAddress(2, 3, 4, 5, 6, 7),
      media: [.automatic, .base10GT],
      initialMedia: .base10GT
    )
    #expect(config.hardwareAddress.bytes == [2, 3, 4, 5, 6, 7])
    #expect(config.initialMedia.rawValue == 0x35)
    #expect(EthernetMedia.fullDuplex == 0x0010_0000)
  }
}
