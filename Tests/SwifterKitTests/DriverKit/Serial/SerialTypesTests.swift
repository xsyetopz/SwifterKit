import Foundation
import Testing

@testable import SwifterKit

@Suite struct SerialTypesTests {
  @Test func encodesReceiveAndTransmitCommands() throws {
    let receive = try DriverCommand.serialEnqueueReceive([1, 2, 3])
    let transmit = try DriverCommand.serialDequeueTransmit(maximumLength: 512)

    #expect(receive.opcode == 0x0600)
    #expect(receive.requiredCapabilities == .serial)
    #expect(receive.payload == Data([1, 2, 3]))
    #expect(transmit.opcode == 0x0601)
    #expect(transmit.maximumResponseSize == RuntimeMessage.headerSize + 512)
    #expect(try transmit.payload.readRuntimeInteger(at: 0) as UInt32 == 512)
  }

  @Test func rejectsInvalidTransferLengths() {
    #expect(throws: SerialRuntimeError.emptyReceiveData) {
      try DriverCommand.serialEnqueueReceive([])
    }
    #expect(throws: SerialRuntimeError.invalidTransferLength) {
      try DriverCommand.serialDequeueTransmit(maximumLength: 0)
    }
    #expect(throws: SerialRuntimeError.transferTooLarge) {
      try DriverCommand.serialDequeueTransmit(maximumLength: 65_513)
    }
  }

  @Test func encodesModemStatusAndReceiveErrors() {
    let modem = DriverCommand.serialSetModemStatus(
      SerialModemStatus(clearToSend: true, ringIndicator: true)
    )
    let errors = DriverCommand.serialReportReceiveErrors([.overrun, .parity])

    #expect(modem.opcode == 0x0602)
    #expect(modem.payload == Data([1, 0, 1, 0]))
    #expect(errors.opcode == 0x0603)
    #expect(errors.payload == Data([9, 0, 0, 0]))
  }

  @Test func decodesUARTAndFlowControlEvents() throws {
    var uart = Data(repeating: 0, count: 16)
    uart.replaceSubrange(0..<4, with: littleEndian(UInt32(7)))
    uart.replaceSubrange(4..<8, with: littleEndian(UInt32(115_200)))
    uart[8] = 8
    uart[9] = 2
    uart[10] = SerialParity.none.rawValue

    var flow = Data(repeating: 0, count: 16)
    flow.replaceSubrange(0..<4, with: littleEndian(UInt32(11)))
    flow.replaceSubrange(4..<8, with: littleEndian(UInt32(0x1234)))
    flow[8] = 0x11
    flow[9] = 0x13

    #expect(
      try DriverEvent(type: 0x0600, payload: Array(uart)).serial()
        == .programUART(
          SerialUARTConfiguration(baudRate: 115_200, dataBits: 8, halfStopBits: 2, parity: .none)
        )
    )
    #expect(
      try DriverEvent(type: 0x0600, payload: Array(flow)).serial()
        == .programFlowControl(SerialFlowControlConfiguration(flags: 0x1234, xon: 0x11, xoff: 0x13))
    )
  }

  @Test func decodesControlEventsAndRejectsMalformedPayloads() throws {
    #expect(try event(kind: 1, value: 0).serial() == .activate)
    #expect(try event(kind: 5, value: 3).serial() == .resetFIFO(transmit: true, receive: true))
    #expect(
      try event(kind: 9, value: 2).serial()
        == .programModemControl(dataTerminalReady: false, requestToSend: true)
    )
    #expect(try DriverEvent(type: 0x0100).serial() == nil)
    #expect(throws: SerialRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0600, payload: [1]).serial()
    }
    #expect(throws: SerialRuntimeError.invalidEventKind(99)) {
      try event(kind: 99, value: 0).serial()
    }
  }

  private func event(kind: UInt32, value: UInt32) -> DriverEvent {
    var payload = Data(repeating: 0, count: 16)
    payload.replaceSubrange(0..<4, with: littleEndian(kind))
    payload.replaceSubrange(4..<8, with: littleEndian(value))
    return DriverEvent(type: 0x0600, payload: Array(payload))
  }

  private func littleEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    var encoded = value.littleEndian
    return withUnsafeBytes(of: &encoded) { Array($0) }
  }
}
