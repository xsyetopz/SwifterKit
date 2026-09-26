import Foundation
import Testing

@testable import SwifterKit

@Suite
struct USBAsyncCommandsTests {
  @Test
  func encodesAsynchronousControlRequests() throws {
    let read = try DriverCommand.usbEnqueueControlTransfer(
      USBControlRequest(requestType: 0xC0, request: 0x5F, value: 1, index: 2, length: 8),
      timeout: 100
    )
    #expect(read.opcode == RuntimeOpcode.usbAsyncDeviceRequest.rawValue)
    #expect(read.requiredCapabilities == .usb)
    #expect(read.maximumResponseSize == RuntimeMessage.headerSize + 4)
    #expect(
      read.payload == Data([0xC0, 0x5F] + le(UInt16(1)) + le(UInt16(2)) + le(UInt16(8)))
        + Data(le(UInt32(100)) + le(UInt32(0)))
    )
    let write = try DriverCommand.usbEnqueueControlTransfer(
      USBControlRequest(requestType: 0x40, request: 0xA1, value: 0, index: 0, length: 2),
      data: [9, 8]
    )
    #expect(write.payload.suffix(2) == Data([9, 8]))
    #expect(write.payload.count == 18)

    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbEnqueueControlTransfer(
        USBControlRequest(requestType: 0x80, request: 6, value: 0, index: 0, length: 1),
        data: [1]
      )
    }
    #expect(throws: USBRuntimeError.invalidOutputLength) {
      try DriverCommand.usbEnqueueControlTransfer(
        USBControlRequest(requestType: 0x40, request: 1, value: 0, index: 0, length: 2),
        data: [1]
      )
    }
    #expect(DriverCommand.usbMaximumAsyncControlReadLength == 65_492)
    #expect(DriverCommand.usbMaximumAsyncControlWriteLength == 65_480)
    #expect(throws: USBRuntimeError.transferTooLarge) {
      try DriverCommand.usbEnqueueControlTransfer(
        USBControlRequest(requestType: 0xC0, request: 1, value: 0, index: 0, length: 65_493)
      )
    }
  }

  @Test
  func encodesAndValidatesBundleRings() throws {
    let create = try DriverCommand.usbCreateBundleRing(
      endpoint: 0x81,
      entryCount: 8,
      bufferLength: 512
    )
    #expect(create.opcode == RuntimeOpcode.usbPipeCreateBundleRing.rawValue)
    #expect(
      create.payload == Data([0x81, 0, 0, 0] + le(UInt32(8)) + le(UInt32(512)) + le(UInt32(0)))
    )
    for (count, length) in [(0, 512), (65, 512), (1, 0), (1, 65_493), (64, 65_536)] {
      #expect(throws: USBRuntimeError.invalidBundleRing) {
        try DriverCommand.usbCreateBundleRing(
          endpoint: 0x81,
          entryCount: count,
          bufferLength: length
        )
      }
    }
    let release = DriverCommand.usbReleaseBundleRing(endpoint: 0x02)
    #expect(release.opcode == RuntimeOpcode.usbPipeReleaseBundleRing.rawValue)
    #expect(release.payload == Data([0x02, 0, 0, 0, 0, 0, 0, 0]))
  }

  @Test
  func encodesAndValidatesBundledTransfers() throws {
    let reads = try DriverCommand.usbEnqueueBundledReads(
      endpoint: 0x81,
      firstIndex: 6,
      lengths: [512, 64],
      timeout: 10
    )
    #expect(reads.opcode == RuntimeOpcode.usbPipeEnqueueBundled.rawValue)
    #expect(reads.maximumResponseSize == RuntimeMessage.headerSize + 4)
    #expect(
      reads.payload
        == Data(
          [0x81, 2, 0, 0] + le(UInt32(6)) + le(UInt32(10)) + le(UInt32(0)) + le(UInt32(512))
            + le(UInt32(64))
        )
    )
    let writes = try DriverCommand.usbEnqueueBundledWrites(
      endpoint: 0x02,
      firstIndex: 0,
      transfers: [[1, 2], [3]]
    )
    #expect(writes.payload.suffix(3) == Data([1, 2, 3]))
    #expect(writes.payload.count == 16 + 8 + 3)

    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbEnqueueBundledReads(endpoint: 0x02, firstIndex: 0, lengths: [1])
    }
    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbEnqueueBundledWrites(endpoint: 0x81, firstIndex: 0, transfers: [[1]])
    }
    #expect(throws: USBRuntimeError.invalidBundledTransfer) {
      try DriverCommand.usbEnqueueBundledReads(endpoint: 0x81, firstIndex: 0, lengths: [])
    }
    #expect(throws: USBRuntimeError.invalidBundledTransfer) {
      try DriverCommand.usbEnqueueBundledReads(
        endpoint: 0x81,
        firstIndex: 0,
        lengths: Array(repeating: 1, count: 17)
      )
    }
    #expect(throws: USBRuntimeError.invalidBundledTransfer) {
      try DriverCommand.usbEnqueueBundledReads(endpoint: 0x81, firstIndex: 64, lengths: [1])
    }
    #expect(throws: USBRuntimeError.emptyTransfer) {
      try DriverCommand.usbEnqueueBundledWrites(endpoint: 0x02, firstIndex: 0, transfers: [[]])
    }
    #expect(throws: USBRuntimeError.transferTooLarge) {
      try DriverCommand.usbEnqueueBundledWrites(
        endpoint: 0x02,
        firstIndex: 0,
        transfers: [[UInt8]](repeating: [UInt8](repeating: 0, count: 5_000), count: 16)
      )
    }
  }

  @Test
  func encodesAdjustedEndpointPolicy() throws {
    let descriptors = USBPipeDescriptors(
      usbRelease: 0x0300,
      endpoint: USBEndpointDescriptor(
        address: 0x83,
        attributes: 0x03,
        maxPacketSize: 64,
        interval: 4
      ),
      superSpeedCompanion: USBSuperSpeedEndpointCompanion(
        maxBurst: 0,
        attributes: 0,
        bytesPerInterval: 64
      )
    )
    #expect(try USBPipeDescriptors(runtimePayload: Data(descriptors.runtimePayload)) == descriptors)
    let command = try DriverCommand.usbAdjustPipe(endpoint: 0x83, descriptors: descriptors)
    #expect(command.opcode == RuntimeOpcode.usbPipeAdjust.rawValue)
    #expect(command.payload.count == 28)
    #expect(command.payload.prefix(4) == Data([0x83, 0, 0, 0]))
    #expect(command.payload.last == 0)

    let bulk = USBPipeDescriptors(
      usbRelease: 0x0200,
      endpoint: USBEndpointDescriptor(
        address: 0x81,
        attributes: 0x02,
        maxPacketSize: 512,
        interval: 0
      )
    )
    let unsupported = USBPipeDescriptors(usbRelease: 0x0100, endpoint: descriptors.endpoint)
    for (endpoint, value) in [(0x81, bulk), (0x84, descriptors), (0x83, unsupported)] {
      #expect(throws: USBRuntimeError.invalidEndpointPolicy) {
        try DriverCommand.usbAdjustPipe(endpoint: UInt8(endpoint), descriptors: value)
      }
    }
  }

  @Test
  func decodesDeviceRequestCompletions() throws {
    let read = DriverEvent(
      type: 0x0210,
      payload: le(UInt32(4)) + le(Int32(0)) + le(UInt32(2)) + [0xC0, 0, 0, 0] + [7, 8]
    )
    guard case .deviceRequest(let completion) = try read.usb() else {
      Issue.record("Expected a device-request completion")
      return
    }
    #expect(completion.requestID == 4)
    #expect(completion.requestType == 0xC0)
    #expect(completion.succeeded)
    #expect(completion.data == [7, 8])

    let write = DriverEvent(
      type: 0x0210,
      payload: le(UInt32(5)) + le(Int32(-536_870_165)) + le(UInt32(1)) + [0x40, 0, 0, 0]
    )
    guard case .deviceRequest(let output) = try write.usb() else {
      Issue.record("Expected a device-request completion")
      return
    }
    #expect(!output.succeeded)
    #expect(output.data.isEmpty)

    for payload in [
      le(UInt32(0)) + le(Int32(0)) + le(UInt32(0)) + [0x40, 0, 0, 0],
      le(UInt32(1)) + le(Int32(0)) + le(UInt32(2)) + [0xC0, 0, 0, 0] + [1],
      le(UInt32(1)) + le(Int32(0)) + le(UInt32(0)) + [0x40, 1, 0, 0], [1, 2, 3],
    ] {
      #expect(throws: USBRuntimeError.invalidResponse) {
        try DriverEvent(type: 0x0210, payload: payload).usb()
      }
    }
  }

  @Test
  func decodesBundledCompletions() throws {
    let read = DriverEvent(
      type: 0x0220,
      payload: [0x81, 0, 0, 0] + le(UInt32(3)) + le(Int32(0)) + le(UInt32(2)) + [5, 6]
    )
    guard case .bundledIO(let completion) = try read.usb() else {
      Issue.record("Expected a bundled completion")
      return
    }
    #expect(completion.endpoint == 0x81)
    #expect(completion.index == 3)
    #expect(completion.data == [5, 6])

    for payload in [
      [0x81, 0, 0, 0] + le(UInt32(64)) + le(Int32(0)) + le(UInt32(0)),
      [0x02, 0, 0, 0] + le(UInt32(1)) + le(Int32(0)) + le(UInt32(4)) + [1],
      [0x81, 1, 0, 0] + le(UInt32(1)) + le(Int32(0)) + le(UInt32(0)),
    ] {
      #expect(throws: USBRuntimeError.invalidResponse) {
        try DriverEvent(type: 0x0220, payload: payload).usb()
      }
    }
  }

  private func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    var data = Data()
    data.appendRuntimeInteger(value)
    return [UInt8](data)
  }
}
