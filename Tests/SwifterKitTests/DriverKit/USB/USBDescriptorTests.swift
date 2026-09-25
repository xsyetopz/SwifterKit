import Foundation
import Testing

@testable import SwifterKit

@Suite
struct USBDescriptorTests {
  /// A configuration with one vendor interface, a class-specific descriptor, and two endpoints.
  static let configuration: [UInt8] = [
    9, 0x02, 39, 0, 1, 1, 4, 0x80, 50, 9, 0x04, 0, 0, 2, 0xFF, 1, 2, 5, 5, 0x24, 0, 0, 0, 7, 0x05,
    0x81, 0x02, 0x00, 0x02, 0, 7, 0x05, 0x02, 0x03, 0x40, 0x00, 4, 2, 0x30,
  ]

  @Test
  func parsesConfigurationInterfacesAndEndpoints() throws {
    let descriptor = try USBConfigurationDescriptor(descriptor: Self.configuration)

    #expect(descriptor.configurationValue == 1)
    #expect(descriptor.interfaceCount == 1)
    #expect(descriptor.stringIndex == 4)
    #expect(descriptor.maxPower == 50)
    #expect(descriptor.bytes == Self.configuration)
    let interface = try #require(descriptor.interfaces.first)
    #expect(interface.interfaceClass == 0xFF)
    #expect(interface.interfaceProtocol == 2)
    #expect(interface.stringIndex == 5)
    #expect(interface.endpoints.count == 2)
    #expect(interface.endpoints[0].direction == .in)
    #expect(interface.endpoints[0].transferType == .bulk)
    #expect(interface.endpoints[0].maxPacketSize == 512)
    #expect(interface.endpoints[1].number == 2)
    #expect(interface.endpoints[1].transferType == .interrupt)
    #expect(interface.endpoints[1].interval == 4)
  }

  @Test
  func rejectsMalformedConfigurations() {
    var zeroLength = Self.configuration
    zeroLength[18] = 0
    var pastEnd = Self.configuration
    pastEnd[37] = 3
    var wrongTotal = Self.configuration
    wrongTotal[2] = 40
    var shortInterface = Self.configuration
    shortInterface[9] = 2
    shortInterface[2] = 32
    shortInterface.removeSubrange(11..<18)

    for bytes in [zeroLength, pastEnd, wrongTotal, shortInterface, [9, 0x02, 9], []] {
      #expect(throws: USBDescriptorError.malformed) {
        try USBConfigurationDescriptor(descriptor: bytes)
      }
    }
  }

  @Test
  func parsesDeviceDescriptor() throws {
    let bytes: [UInt8] = [
      18, 0x01, 0x00, 0x02, 0xEF, 2, 1, 64, 0x34, 0x12, 0x78, 0x56, 0x00, 0x01, 1, 2, 3, 1,
    ]
    let descriptor = try USBDeviceDescriptor(descriptor: bytes)

    #expect(descriptor.usbRelease == 0x0200)
    #expect(descriptor.deviceClass == 0xEF)
    #expect(descriptor.maxPacketSize0 == 64)
    #expect(descriptor.vendorID == 0x1234)
    #expect(descriptor.productID == 0x5678)
    #expect(descriptor.deviceRelease == 0x0100)
    #expect(descriptor.serialNumberStringIndex == 3)
    #expect(descriptor.configurationCount == 1)
    #expect(throws: USBDescriptorError.malformed) {
      try USBDeviceDescriptor(descriptor: Array(bytes.dropLast()))
    }
  }

  @Test
  func decodesStringDescriptors() throws {
    let text = try USBStringDescriptor(descriptor: [8, 0x03, 0x53, 0, 0x4B, 0, 0x21, 0])
    #expect(text.string == "SK!")

    let languages = try USBStringDescriptor(descriptor: [4, 0x03, 0x09, 0x04])
    #expect(languages.codeUnits == [0x0409])

    let odd = try USBStringDescriptor(descriptor: [5, 0x03, 0x41, 0, 0x42])
    #expect(odd.string == "A")

    for bytes: [UInt8] in [[1], [4, 0x03, 0x41], [4, 0x02, 0x41, 0]] {
      #expect(throws: USBDescriptorError.malformed) { try USBStringDescriptor(descriptor: bytes) }
    }
  }

  @Test
  func parsesCapabilityDescriptors() throws {
    let bytes: [UInt8] = [
      5, 0x0F, 22, 0, 2, 7, 0x10, 0x02, 0x02, 0, 0, 0, 10, 0x10, 0x03, 0, 0x0E, 0, 1, 10, 0xFF,
      0x07,
    ]
    let descriptor = try USBCapabilityDescriptors(descriptor: bytes)

    #expect(descriptor.capabilities.map(\.type) == [0x02, 0x03])
    #expect(descriptor.capabilities[1].bytes.count == 10)
    #expect(throws: USBDescriptorError.malformed) {
      try USBCapabilityDescriptors(descriptor: [5, 0x0F, 7, 0, 1, 2, 0x04])
    }
  }

  @Test
  func refusesDescriptorsLargerThanOneMessage() throws {
    var tooLarge = Data()
    tooLarge.appendRuntimeInteger(UInt32(65_535))
    #expect(throws: USBDescriptorError.tooLarge(length: 65_535)) {
      try USBDescriptorError.descriptorBytes(from: tooLarge)
    }

    var absent = Data()
    absent.appendRuntimeInteger(UInt32(0))
    #expect(try USBDescriptorError.descriptorBytes(from: absent) == nil)

    var fitting = Data()
    fitting.appendRuntimeInteger(UInt32(2))
    fitting.append(contentsOf: [2, 0x03])
    #expect(try USBDescriptorError.descriptorBytes(from: fitting) == [2, 0x03])

    var truncated = Data()
    truncated.appendRuntimeInteger(UInt32(3))
    truncated.append(contentsOf: [3, 0x03])
    var smallWithoutBytes = Data()
    smallWithoutBytes.appendRuntimeInteger(UInt32(18))
    for payload in [truncated, smallWithoutBytes] {
      #expect(throws: USBRuntimeError.invalidResponse) {
        try USBDescriptorError.descriptorBytes(from: payload)
      }
    }
  }

  @Test
  func decodesPipeDescriptors() throws {
    var payload = Data([0x10, 0x03])
    payload.append(contentsOf: [7, 0x05, 0x81, 0x02, 0x00, 0x04, 0])
    payload.append(contentsOf: [6, 0x30, 15, 0, 0, 0])
    payload.append(contentsOf: [8, 0x31, 0, 0, 0x00, 0x10, 0x00, 0x00])
    let descriptors = try USBPipeDescriptors(runtimePayload: payload)

    #expect(descriptors.usbRelease == 0x0310)
    #expect(descriptors.endpoint.maxPacketSize == 1_024)
    #expect(descriptors.superSpeedCompanion?.maxBurst == 15)
    #expect(descriptors.superSpeedPlusIsochronousBytesPerInterval == 0x1000)

    var usb2 = Data([0x00, 0x02, 7, 0x05, 0x02, 0x02, 0x00, 0x02, 0])
    usb2.append(contentsOf: [UInt8](repeating: 0, count: 14))
    let legacy = try USBPipeDescriptors(runtimePayload: usb2)
    #expect(legacy.superSpeedCompanion == nil)
    #expect(legacy.superSpeedPlusIsochronousBytesPerInterval == nil)
    #expect(throws: USBRuntimeError.invalidResponse) {
      try USBPipeDescriptors(runtimePayload: usb2.dropLast())
    }
  }

  @Test
  func decodesPortStatusBits() {
    let status = USBPortStatus(rawValue: 0x3 << 8 | 1 << 12 | 1 << 14 | 2)

    #expect(status.portType == 2)
    #expect(status.connectedSpeed == .high)
    #expect(status.isEnabled)
    #expect(status.isOvercurrent)
    #expect(!status.isSuspended)
    #expect(!status.isResetting)
  }
}
