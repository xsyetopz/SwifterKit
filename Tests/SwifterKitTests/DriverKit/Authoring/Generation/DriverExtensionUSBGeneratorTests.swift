import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverExtensionUSBGeneratorTests {
  private static let deviceConfiguration = DriverConfiguration(
    bundleIdentifier: "com.example.usb-device-driver",
    providerClass: USBDeviceConfiguration.deviceProviderClass,
    capabilities: .usb,
    usbDevice: USBDeviceConfiguration(
      vendorID: 0x1234,
      productIDs: [0x5678],
      deviceRelease: 0x0100,
      deviceClass: 0xFF
    )
  )

  @Test
  func generatesUSBDeviceRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBDeviceDriver", isDirectory: true)

    try DriverExtensionGenerator.generate(configuration: Self.deviceConfiguration, at: output)

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["IOProviderClass"] as? String == "IOUSBHostDevice")
    #expect(personality["idVendor"] as? UInt32 == 0x1234)
    #expect(personality["idProduct"] as? UInt32 == 0x5678)
    #expect(personality["bcdDevice"] as? UInt32 == 0x0100)
    #expect(personality["bDeviceClass"] as? UInt32 == 0xFF)
    for key in ["bConfigurationValue", "bInterfaceNumber", "bInterfaceClass"] {
      #expect(personality[key] == nil)
    }

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    let usbEntitlement = try #require(
      entitlements["com.apple.developer.driverkit.transport.usb"] as? [[String: Any]]
    )
    #expect(usbEntitlement.first?["idProduct"] as? UInt32 == 0x5678)

    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("SWIFTERKIT_ENABLE_USB 1"))
    #expect(header.contains("kSwifterKitUSBDeviceProvider =\n    true;"))

    let service = try source("SwifterKitRuntimeService.iig", in: output)
    #expect(service.contains("#include <USBDriverKit/IOUSBHostPipe.iig>"))
    #expect(service.contains("TYPE(IOUSBHostPipe::CompleteAsyncIO)"))
    #expect(service.contains("TYPE(IOUSBHostPipe::CompleteAsyncIsochIO)"))
    #expect(service.contains("kern_return_t USBCommand("))

    let project = try String(
      contentsOf: output.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    #expect(project.contains("SwifterKitRuntimeUSBDevice.cpp in Sources"))
    #expect(project.contains("SwifterKitRuntimeUSBPipes.cpp in Sources"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func interfaceProviderKeepsInterfaceRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBInterfaceDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.usb-interface-driver",
        providerClass: USBDeviceConfiguration.interfaceProviderClass,
        capabilities: .usb,
        usbDevice: USBDeviceConfiguration(vendorID: 0x1234, interfaceClass: 0xFF)
      ),
      at: output
    )

    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("kSwifterKitUSBDeviceProvider =\n    false;"))
  }

  @Test
  func rejectsDeviceProviderWithInterfaceMatching() {
    let interfaceKeys: [USBDeviceConfiguration] = [
      USBDeviceConfiguration(vendorID: 0x1234, configurationValue: 1),
      USBDeviceConfiguration(vendorID: 0x1234, interfaceNumber: 0),
      USBDeviceConfiguration(vendorID: 0x1234, interfaceClass: 0xFF),
      USBDeviceConfiguration(vendorID: 0x1234, interfaceSubclass: 1),
      USBDeviceConfiguration(vendorID: 0x1234, interfaceProtocol: 1),
    ]
    for usb in interfaceKeys {
      #expect(throws: DriverExtensionGenerationError.invalidUSBConfiguration) {
        try generate(providerClass: USBDeviceConfiguration.deviceProviderClass, usb: usb)
      }
    }
    #expect(throws: DriverExtensionGenerationError.invalidUSBConfiguration) {
      try generate(providerClass: "IOService", usb: USBDeviceConfiguration(vendorID: 0x1234))
    }
  }

  private func generate(providerClass: String, usb: USBDeviceConfiguration) throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: output) }
    try DriverExtensionGenerator.generate(
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.invalid-usb",
        providerClass: providerClass,
        capabilities: .usb,
        usbDevice: usb
      ),
      at: output
    )
  }

  private func source(_ name: String, in output: URL) throws -> String {
    try String(
      contentsOf: output.appendingPathComponent("Sources").appendingPathComponent(name),
      encoding: .utf8
    )
  }
}
