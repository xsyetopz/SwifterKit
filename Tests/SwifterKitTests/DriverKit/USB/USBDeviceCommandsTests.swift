import Foundation
import Testing

@testable import SwifterKit

@Suite
struct USBDeviceCommandsTests {
  @Test
  func encodesDeviceCommands() {
    let configuration = DriverCommand.usbSetConfiguration(2, matchInterfaces: false)
    #expect(configuration.opcode == 0x0210)
    #expect(configuration.requiredCapabilities == .usb)
    #expect(configuration.payload == Data([2, 0, 0, 0]))
    #expect(configuration.maximumResponseSize == RuntimeMessage.headerSize)
    #expect(DriverCommand.usbSetConfiguration(1).payload == Data([1, 1, 0, 0]))

    let empty: [(DriverCommand, UInt32, Int)] = [
      (.usbResetDevice(), 0x0211, 0), (.usbDeviceSpeed(), 0x0212, 4),
      (.usbDeviceAddress(), 0x0213, 4), (.usbPortStatus(), 0x0214, 4),
      (.usbFrameNumber(), 0x0215, 16), (.usbCurrentMicroframe(), 0x0216, 16),
      (.usbReferenceMicroframe(), 0x0217, 16), (.usbDeviceDescriptor(), 0x0218, 22),
      (.usbInterfaces(), 0x021D, 4 + 256 * 9), (.usbInterfaceDescriptor(), 0x021E, 9),
      (.usbIdlePolicy(), 0x0220, 4), (.usbAbortDeviceRequests(), 0x0221, 0),
    ]
    for (command, opcode, response) in empty {
      #expect(command.opcode == opcode)
      #expect(command.payload.isEmpty)
      #expect(command.requiredCapabilities == .usb)
      #expect(command.maximumResponseSize == RuntimeMessage.headerSize + response)
    }
  }

  @Test
  func encodesDescriptorSelectors() {
    #expect(DriverCommand.usbConfigurationDescriptor().payload == Data([0, 0, 0, 0]))
    #expect(DriverCommand.usbConfigurationDescriptor(.index(3)).payload == Data([1, 3, 0, 0]))
    #expect(DriverCommand.usbConfigurationDescriptor(.value(7)).payload == Data([2, 7, 0, 0]))
    #expect(DriverCommand.usbConfigurationDescriptor().opcode == 0x0219)
    #expect(
      DriverCommand.usbConfigurationDescriptor().maximumResponseSize == RuntimeMessage.maximumSize
    )
    #expect(DriverCommand.usbCapabilityDescriptors().opcode == 0x021B)
    #expect(
      DriverCommand.usbCapabilityDescriptors().maximumResponseSize == RuntimeMessage.maximumSize
    )

    let string = DriverCommand.usbStringDescriptor(index: 2, languageID: 0x0409)
    #expect(string.opcode == 0x021A)
    #expect(string.payload == Data([2, 1, 0x09, 0x04]))
    #expect(string.maximumResponseSize == RuntimeMessage.headerSize + 4 + 255)
    #expect(DriverCommand.usbStringDescriptor(index: 1).payload == Data([1, 0, 0, 0]))
  }

  @Test
  func boundsGenericDescriptorLength() throws {
    let command = try DriverCommand.usbDescriptor(
      type: 0x21,
      index: 1,
      languageID: 0x0409,
      requestType: .class,
      recipient: .interface,
      length: 9
    )
    #expect(command.opcode == 0x021C)
    #expect(command.payload == Data([0x21, 1, 0x09, 0x04, 1, 1, 9, 0]))
    #expect(command.maximumResponseSize == RuntimeMessage.headerSize + 4 + 9)

    let largest = DriverCommand.usbMaximumDescriptorLength
    #expect(largest == 65_508)
    #expect(
      try DriverCommand.usbDescriptor(type: 2, length: largest).maximumResponseSize
        == RuntimeMessage.maximumSize
    )
    for length in [0, -1, largest + 1] {
      #expect(throws: USBDescriptorError.invalidLength) {
        try DriverCommand.usbDescriptor(type: 2, length: length)
      }
    }
  }

  @Test
  func encodesIdlePolicy() {
    let command = DriverCommand.usbSetIdlePolicy(timeout: 0x0102_0304)
    #expect(command.opcode == 0x021F)
    #expect(command.payload == Data([4, 3, 2, 1]))
  }

  @Test
  func decodesFrameTimes() throws {
    var payload = Data()
    payload.appendRuntimeInteger(UInt64(42))
    payload.appendRuntimeInteger(UInt64(99))
    #expect(try USBFrameTime(runtimePayload: payload) == USBFrameTime(frame: 42, time: 99))
    #expect(throws: USBRuntimeError.invalidResponse) {
      try USBFrameTime(runtimePayload: payload.dropLast())
    }
  }

  @Test
  func deviceCommandsRequireUSBCapability() async {
    let context = DriverContext(capabilities: .pci)
    await #expect(throws: DriverContextError.unsupportedCapability(.usb)) {
      try await context.usbDeviceDescriptor()
    }
    await #expect(throws: DriverContextError.unsupportedCapability(.usb)) {
      try await context.usbInterfaces()
    }
  }
}
