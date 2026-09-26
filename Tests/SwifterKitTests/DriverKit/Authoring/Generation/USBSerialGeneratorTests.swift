import Foundation
import Testing

@testable import SwifterKit

@Suite
struct USBSerialGeneratorTests {
  static func configuration(
    capabilities: RuntimeCapabilities = [.serial, .usb],
    providerClass: String = USBDeviceConfiguration.interfaceProviderClass,
    usbDevice: USBDeviceConfiguration? = USBDeviceConfiguration(
      vendorID: 0x1A86,
      productIDs: [0x7523]
    ),
    serialPort: SerialPortConfiguration? = nil,
    usbSerialPort: USBSerialPortConfiguration? = USBSerialPortConfiguration(
      baseName: "usbserial",
      suffix: "Example",
      initialModemStatus: SerialModemStatus(dataSetReady: true),
      deliversReceivedPackets: true
    )
  ) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.usb-serial-port",
      providerClass: providerClass,
      capabilities: capabilities,
      usbDevice: usbDevice,
      serialPort: serialPort,
      usbSerialPort: usbSerialPort
    )
  }

  @Test
  func generatesAndBuildsUSBSerialPort() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBSerialPort", isDirectory: true)

    try DriverExtensionGenerator.generate(configuration: Self.configuration(), at: output)

    let personality = try loadDriverPersonality(in: output)
    #expect(personality["IOProviderClass"] as? String == "IOUSBHostInterface")
    #expect(personality["IOTTYBaseName"] as? String == "usbserial")
    #expect(personality["IOTTYSuffix"] as? String == "Example")
    let entitlements = try loadEntitlements(in: output)
    #expect(entitlements["com.apple.developer.driverkit.family.serial"] as? Bool == true)
    #expect(entitlements["com.apple.developer.driverkit.transport.usb"] != nil)

    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("#define SWIFTERKIT_ENABLE_SERIAL 1"))
    #expect(header.contains("#define SWIFTERKIT_ENABLE_USB 1"))
    #expect(header.contains("#define SWIFTERKIT_USB_SERIAL 1"))
    #expect(header.contains("kSwifterKitUSBSerialOverridesName = true;"))
    #expect(header.contains("kSwifterKitUSBSerialDeliversReceivedPackets =\n    true;"))
    #expect(header.contains("kSwifterKitUSBSerialDeliversInterruptPackets =\n    true;"))
    #expect(header.contains("kSwifterKitSerialInitialDSR =\n    true"))

    let service = try source("SwifterKitRuntimeService.iig", in: output)
    #expect(service.contains("#include <USBSerialDriverKit/IOUserUSBSerial.iig>"))
    #expect(service.contains("public IOUserUSBSerial"))
    #expect(service.contains("handleRxPacket(uint8_t*& packet, uint32_t& size) LOCALONLY override"))
    #expect(service.contains("handleInterruptPacket("))
    #expect(service.contains("HwProgramUART("))
    #expect(service.contains("USBControlTransfer("))
    // IOUserUSBSerial declares these final and runs the data path itself.
    #expect(!service.contains("RxFreeSpaceAvailable"))
    #expect(!service.contains("TxDataAvailable"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func defaultTerminalNameComesFromUSBSerialDriverKit() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBSerialDefaults", isDirectory: true)

    try DriverExtensionGenerator.generate(
      configuration: Self.configuration(usbSerialPort: USBSerialPortConfiguration()),
      at: output
    )

    let personality = try loadDriverPersonality(in: output)
    #expect(personality["IOTTYBaseName"] == nil)
    #expect(personality["IOTTYSuffix"] == nil)
    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("kSwifterKitUSBSerialOverridesName = false;"))
    #expect(header.contains("kSwifterKitUSBSerialDeliversReceivedPackets =\n    false;"))
  }

  @Test(arguments: [
    configuration(capabilities: .serial, usbDevice: nil),
    configuration(providerClass: USBDeviceConfiguration.deviceProviderClass),
    configuration(serialPort: SerialPortConfiguration(baseName: "usbserial", suffix: "A")),
    configuration(usbSerialPort: USBSerialPortConfiguration(baseName: "usbserial")),
    configuration(usbSerialPort: USBSerialPortConfiguration(suffix: "A")),
    configuration(usbSerialPort: USBSerialPortConfiguration(baseName: "", suffix: "A")),
    configuration(usbSerialPort: USBSerialPortConfiguration(baseName: "a\0b", suffix: "A")),
  ])
  func rejectsInvalidUSBSerialMetadata(_ configuration: DriverConfiguration) {
    #expect(throws: DriverExtensionGenerationError.invalidSerialConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test
  func rejectsUSBSerialMetadataWithoutTheSerialCapability() {
    #expect(throws: DriverExtensionGenerationError.capabilityConfigurationMismatch(.serial)) {
      try DriverExtensionGenerator.generate(
        configuration: Self.configuration(capabilities: .usb),
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }
}
