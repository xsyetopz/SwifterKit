import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverExtensionSerialGeneratorTests {
  @Test
  func generatesSerialRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("SerialDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.serial-driver",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .serial,
      serialPort: SerialPortConfiguration(
        baseName: "usbserial",
        suffix: "Example",
        initialModemStatus: SerialModemStatus(clearToSend: true, dataCarrierDetect: true)
      )
    )

    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let personality = try loadDriverPersonality(in: output)
    #expect(personality["IOTTYBaseName"] as? String == "usbserial")
    #expect(personality["IOTTYSuffix"] as? String == "Example")

    let entitlements = try loadEntitlements(in: output)
    #expect(entitlements["com.apple.developer.driverkit.family.serial"] as? Bool == true)

    let configurationHeader = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(configurationHeader.contains("SWIFTERKIT_ENABLE_SERIAL 1"))
    #expect(configurationHeader.contains("kSwifterKitSerialInitialCTS =\n    true"))
    #expect(configurationHeader.contains("kSwifterKitSerialInitialDCD =\n    true"))

    let service = try source("SwifterKitRuntimeService.iig", in: output)
    #expect(service.contains("public IOUserSerial"))
    #expect(service.contains("SerialCommand"))
    #expect(service.contains("HwProgramUART"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func generatesUSBBackedSerialRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBSerialDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.usb-serial-driver",
      providerClass: "IOUSBHostInterface",
      capabilities: [.serial, .usb],
      usbDevice: USBDeviceConfiguration(vendorID: 0x1234, productIDs: [0x5678]),
      serialPort: SerialPortConfiguration(baseName: "usbserial", suffix: "5678")
    )

    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let service = try source("SwifterKitRuntimeService.iig", in: output)
    #expect(service.contains("public IOUserSerial"))
    #expect(service.contains("SerialCommand"))
    #expect(service.contains("USBControlTransfer"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func rejectsMissingInvalidAndConflictingSerialMetadata() {
    let root = FileManager.default.temporaryDirectory
    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.serial",
      providerClass: "IOUserResources",
      capabilities: .serial
    )
    #expect(throws: DriverExtensionGenerationError.invalidSerialConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let invalid = DriverConfiguration(
      bundleIdentifier: "com.example.serial",
      providerClass: "IOUserResources",
      capabilities: .serial,
      serialPort: SerialPortConfiguration(baseName: "", suffix: "Port")
    )
    #expect(throws: DriverExtensionGenerationError.invalidSerialConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: invalid,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let conflicting = DriverConfiguration(
      bundleIdentifier: "com.example.serial",
      providerClass: "IOUserResources",
      capabilities: [.hid, .serial],
      hidDevice: hidConfiguration,
      serialPort: SerialPortConfiguration(baseName: "usbserial", suffix: "Port")
    )
    #expect(throws: DriverExtensionGenerationError.invalidSerialConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: conflicting,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private var hidConfiguration: HIDDeviceConfiguration {
    HIDDeviceConfiguration(
      reportDescriptor: [0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0xC0],
      vendorID: 1,
      productID: 1,
      manufacturer: "Example",
      product: "Serial conflict",
      serialNumber: "1",
      primaryUsagePage: 0xFF00,
      primaryUsage: 1
    )
  }
}
