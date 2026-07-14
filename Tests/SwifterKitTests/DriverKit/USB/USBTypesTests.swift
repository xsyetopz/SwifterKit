import Foundation
import Testing

@testable import SwifterKit

@Suite struct USBTypesTests {
  @Test func decodesTransferDirections() {
    #expect(USBTransferDirection(encodedByte: 0x02) == .out)
    #expect(USBTransferDirection(encodedByte: 0x82) == .in)
  }

  @Test func encodesControlTransfer() throws {
    let request = USBControlRequest(
      requestType: USBRequestType.out | USBRequestType.vendor | USBRequestType.interface,
      request: 7,
      value: 0x1234,
      index: 2,
      length: 3
    )
    let command = try DriverCommand.usbControlTransfer(request, data: [1, 2, 3], timeout: 99)

    #expect(command.opcode == 0x0200)
    #expect(command.requiredCapabilities == .usb)
    #expect(command.payload.count == 19)
    #expect(command.payload[0] == request.requestType)
    #expect(try command.payload.readRuntimeInteger(at: 2) as UInt16 == 0x1234)
    #expect(try command.payload.readRuntimeInteger(at: 8) as UInt32 == 99)
  }

  @Test func enforcesControlDirectionAndLength() {
    let input = USBControlRequest(
      requestType: USBRequestType.in,
      request: USBRequest.getDescriptor,
      length: 8
    )
    let output = USBControlRequest(requestType: USBRequestType.out, request: 1, length: 2)

    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbControlTransfer(input, data: [1])
    }
    #expect(throws: USBRuntimeError.invalidOutputLength) {
      try DriverCommand.usbControlTransfer(output, data: [1])
    }
  }

  @Test func validatesEndpointDirection() {
    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbPipeRead(endpoint: 0x02, length: 4)
    }
    #expect(throws: USBRuntimeError.directionMismatch) {
      try DriverCommand.usbPipeWrite(endpoint: 0x82, data: [1])
    }
    #expect(throws: USBRuntimeError.emptyTransfer) {
      try DriverCommand.usbPipeWrite(endpoint: 0x02, data: [])
    }
  }

  @Test func buildsCompleteUSBMatchingDictionary() {
    let configuration = USBDeviceConfiguration(
      vendorID: 0x1234,
      productIDs: [0x5678],
      productIDMask: 0xFFF0,
      deviceRelease: 0x0102,
      configurationValue: 1,
      deviceClass: 0xEF,
      deviceSubclass: 2,
      deviceProtocol: 1,
      interfaceNumber: 3,
      interfaceClass: 0xFF,
      interfaceSubclass: 4,
      interfaceProtocol: 5
    )

    #expect(configuration.matchingProperties["idVendor"] == .unsignedInteger(0x1234))
    #expect(configuration.matchingProperties["idProduct"] == .unsignedInteger(0x5678))
    #expect(configuration.matchingProperties["idProductMask"] == .unsignedInteger(0xFFF0))
    #expect(configuration.matchingProperties["bcdDevice"] == .unsignedInteger(0x0102))
    #expect(configuration.matchingProperties["bInterfaceNumber"] == .unsignedInteger(3))
    #expect(configuration.matchingProperties["bInterfaceProtocol"] == .unsignedInteger(5))
  }

  @Test func decodesTransferResults() throws {
    var payload = Data()
    payload.appendRuntimeInteger(UInt32(3))
    payload.append(contentsOf: [4, 5, 6])

    #expect(
      try USBTransferResult(runtimePayload: payload)
        == USBTransferResult(bytesTransferred: 3, data: [4, 5, 6])
    )
    #expect(throws: USBRuntimeError.invalidResponse) {
      try USBTransferResult(runtimePayload: Data([2, 0, 0, 0, 1]))
    }
  }
}
