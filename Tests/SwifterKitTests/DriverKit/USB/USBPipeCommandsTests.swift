import Foundation
import Testing

@testable import SwifterKit

@Suite
struct USBPipeCommandsTests {
  @Test
  func encodesAsynchronousTransfers() throws {
    let read = try DriverCommand.usbEnqueueRead(endpoint: 0x81, length: 512, timeout: 100)
    #expect(read.opcode == 0x0230)
    #expect(read.requiredCapabilities == .usb)
    #expect(read.payload.count == 16)
    #expect(read.payload[0] == 0x81)
    #expect(try read.payload.readRuntimeInteger(at: 4) as UInt32 == 512)
    #expect(try read.payload.readRuntimeInteger(at: 8) as UInt32 == 100)
    #expect(read.maximumResponseSize == RuntimeMessage.headerSize + 4)

    let write = try DriverCommand.usbEnqueueWrite(endpoint: 0x02, data: [1, 2, 3])
    #expect(write.payload.count == 19)
    #expect(try write.payload.readRuntimeInteger(at: 4) as UInt32 == 3)
    #expect(Array(write.payload.suffix(3)) == [1, 2, 3])
  }

  @Test
  func boundsAsynchronousTransfersToOneMessage() throws {
    #expect(DriverCommand.usbMaximumAsyncReadLength == 65_484)
    #expect(DriverCommand.usbMaximumAsyncWriteLength == 65_480)

    _ = try DriverCommand.usbEnqueueRead(endpoint: 0x81, length: 65_484)
    let write = try DriverCommand.usbEnqueueWrite(
      endpoint: 0x02,
      data: [UInt8](repeating: 0, count: 65_480)
    )
    let message = RuntimeMessage(kind: .command, requestID: 1, payload: try write.encodedPayload())
    #expect(try message.encoded().count == RuntimeMessage.maximumSize)

    #expect(throws: USBRuntimeError.transferTooLarge) {
      try DriverCommand.usbEnqueueRead(endpoint: 0x81, length: 65_485)
    }
    #expect(throws: USBRuntimeError.transferTooLarge) {
      try DriverCommand.usbEnqueueWrite(endpoint: 0x02, data: [UInt8](repeating: 0, count: 65_481))
    }
    #expect(throws: USBRuntimeError.emptyTransfer) {
      try DriverCommand.usbEnqueueRead(endpoint: 0x81, length: 0)
    }
    #expect(throws: USBRuntimeError.emptyTransfer) {
      try DriverCommand.usbEnqueueWrite(endpoint: 0x02, data: [])
    }
    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbEnqueueRead(endpoint: 0x01, length: 8)
    }
    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbEnqueueWrite(endpoint: 0x82, data: [1])
    }
  }

  @Test
  func encodesIsochronousTransfers() throws {
    let read = try DriverCommand.usbEnqueueIsochronousRead(
      endpoint: 0x83,
      frameLengths: [192, 0, 196],
      firstFrame: 0x1_0000_0001
    )
    #expect(read.opcode == 0x0237)
    #expect(read.payload.count == 16 + 12)
    #expect(try read.payload.readRuntimeInteger(at: 2) as UInt16 == 3)
    #expect(try read.payload.readRuntimeInteger(at: 8) as UInt64 == 0x1_0000_0001)
    #expect(try read.payload.readRuntimeInteger(at: 24) as UInt32 == 196)

    let write = try DriverCommand.usbEnqueueIsochronousWrite(
      endpoint: 0x03,
      frames: [[1, 2], [3]]
    )
    #expect(write.payload.count == 16 + 8 + 3)
    #expect(try write.payload.readRuntimeInteger(at: 16) as UInt32 == 2)
    #expect(Array(write.payload.suffix(3)) == [1, 2, 3])
  }

  @Test
  func boundsIsochronousTransfers() throws {
    let frames = DriverCommand.usbMaximumIsochronousFrames
    _ = try DriverCommand.usbEnqueueIsochronousRead(
      endpoint: 0x81,
      frameLengths: [UInt32](repeating: 1, count: frames)
    )
    #expect(throws: USBRuntimeError.transferTooLarge) {
      try DriverCommand.usbEnqueueIsochronousRead(
        endpoint: 0x81,
        frameLengths: [UInt32](repeating: 1, count: frames + 1)
      )
    }
    // The completion event holds a 16-byte header, 24 bytes per frame, and the data.
    let largestRead = 65_508 - 16 - 24
    _ = try DriverCommand.usbEnqueueIsochronousRead(
      endpoint: 0x81,
      frameLengths: [UInt32(largestRead)]
    )
    #expect(throws: USBRuntimeError.transferTooLarge) {
      try DriverCommand.usbEnqueueIsochronousRead(
        endpoint: 0x81,
        frameLengths: [UInt32(largestRead + 1)]
      )
    }
    let largestWrite = 65_496 - 16 - 4
    _ = try DriverCommand.usbEnqueueIsochronousWrite(
      endpoint: 0x01,
      frames: [[UInt8](repeating: 0, count: largestWrite)]
    )
    #expect(throws: USBRuntimeError.transferTooLarge) {
      try DriverCommand.usbEnqueueIsochronousWrite(
        endpoint: 0x01,
        frames: [[UInt8](repeating: 0, count: largestWrite + 1)]
      )
    }
    #expect(throws: USBRuntimeError.emptyTransfer) {
      try DriverCommand.usbEnqueueIsochronousRead(endpoint: 0x81, frameLengths: [])
    }
    #expect(throws: USBRuntimeError.emptyTransfer) {
      try DriverCommand.usbEnqueueIsochronousRead(endpoint: 0x81, frameLengths: [0, 0])
    }
    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbEnqueueIsochronousWrite(endpoint: 0x81, frames: [[1]])
    }
  }

  @Test
  func encodesPipeRequests() {
    let requests: [(DriverCommand, UInt32, [UInt8], Int)] = [
      (.usbAbortPipe(endpoint: 0x81), 0x0231, [0x81, 0, 0, 0, 0, 0, 0, 0], 0),
      (
        .usbSetPipeIdlePolicy(endpoint: 0x02, timeout: 0x0304), 0x0232,
        [0x02, 0, 0, 0, 0x04, 0x03, 0, 0], 0
      ), (.usbPipeIdlePolicy(endpoint: 0x02), 0x0233, [0x02, 0, 0, 0, 0, 0, 0, 0], 4),
      (
        .usbPipeDescriptors(endpoint: 0x81, policy: .currentPolicy), 0x0234,
        [0x81, 1, 0, 0, 0, 0, 0, 0], 23
      ), (.usbPipeSpeed(endpoint: 0x81), 0x0235, [0x81, 0, 0, 0, 0, 0, 0, 0], 4),
      (.usbPipeDeviceAddress(endpoint: 0x81), 0x0236, [0x81, 0, 0, 0, 0, 0, 0, 0], 4),
    ]
    for (command, opcode, payload, response) in requests {
      #expect(command.opcode == opcode)
      #expect(command.payload == Data(payload))
      #expect(command.maximumResponseSize == RuntimeMessage.headerSize + response)
    }
  }

  @Test
  func decodesPipeCompletions() throws {
    let read = DriverEvent(
      type: 0x0200,
      payload: pipeEvent(endpoint: 0x81, count: 3, data: [7, 8, 9])
    )
    guard case .pipeIO(let completion) = try read.usb() else {
      Issue.record("Expected a pipe completion")
      return
    }
    #expect(completion.requestID == 5)
    #expect(completion.status == 0)
    #expect(completion.succeeded)
    #expect(completion.bytesTransferred == 3)
    #expect(completion.timestamp == 1_234)
    #expect(completion.data == [7, 8, 9])

    let write = DriverEvent(type: 0x0200, payload: pipeEvent(endpoint: 0x02, count: 64, data: []))
    guard case .pipeIO(let output) = try write.usb() else {
      Issue.record("Expected a pipe completion")
      return
    }
    #expect(output.data.isEmpty)
    #expect(output.bytesTransferred == 64)

    let mismatched = DriverEvent(
      type: 0x0200,
      payload: pipeEvent(endpoint: 0x81, count: 4, data: [1])
    )
    #expect(throws: USBRuntimeError.invalidResponse) { try mismatched.usb() }
    #expect(try DriverEvent(type: 0x0300, payload: [1]).usb() == nil)
  }

  @Test
  func decodesIsochronousCompletions() throws {
    var payload: [UInt8] = []
    payload += le(UInt32(9)) + le(Int32(0)) + [0x83, 0] + le(UInt16(2)) + le(UInt32(6))
    payload += le(Int32(0)) + le(UInt32(4)) + le(UInt32(2)) + le(UInt32(0)) + le(UInt64(10))
    payload += le(Int32(-536_870_211)) + le(UInt32(2)) + le(UInt32(1)) + le(UInt32(0))
    payload += le(UInt64(11))
    payload += [1, 2, 0, 0, 5, 0]
    guard
      case .isochronousIO(let completion) = try DriverEvent(type: 0x0201, payload: payload).usb()
    else {
      Issue.record("Expected an isochronous completion")
      return
    }
    #expect(completion.requestID == 9)
    #expect(completion.frames.count == 2)
    #expect(completion.frames[1].status == -536_870_211)
    #expect(Array(completion.bytes(inFrame: 0)) == [1, 2])
    #expect(Array(completion.bytes(inFrame: 1)) == [5])
    #expect(completion.bytes(inFrame: 2).isEmpty)

    var overlong = payload
    overlong[24] = 5  // completeCount greater than requestCount
    #expect(throws: USBRuntimeError.invalidResponse) {
      try DriverEvent(type: 0x0201, payload: overlong).usb()
    }
    #expect(throws: USBRuntimeError.invalidResponse) {
      try DriverEvent(type: 0x0201, payload: Array(payload.dropLast())).usb()
    }
  }

  private func pipeEvent(endpoint: UInt8, count: UInt32, data: [UInt8]) -> [UInt8] {
    le(UInt32(5)) + le(Int32(0)) + le(count) + [endpoint, 0, 0, 0] + le(UInt64(1_234)) + data
  }
}
