import Foundation
import Testing

@testable import SwifterKit

@Suite
struct HIDUSBDeviceGeneratorTests {
  private static let usbMatch = USBDeviceConfiguration(
    vendorID: 0x1234,
    productIDs: [0x5678],
    interfaceClass: 3
  )

  static func usbHIDConfiguration(
    _ device: USBHIDDeviceConfiguration,
    capabilities: RuntimeCapabilities = [.hid, .usb],
    providerClass: String = USBDeviceConfiguration.interfaceProviderClass
  ) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.usb-hid",
      providerClass: providerClass,
      capabilities: capabilities,
      usbHIDDevice: device,
      usbDevice: capabilities.contains(.usb) ? usbMatch : nil
    )
  }

  @Test
  func generatesAndBuildsUSBHIDDevice() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBHID", isDirectory: true)
    let device = USBHIDDeviceConfiguration(
      reportDescriptor: [0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0xC0],
      deviceProperties: [
        "Product": .string("Example keyboard"), "CountryCode": .unsignedInteger(33),
      ],
      acceptedHostReportTypes: .feature,
      answeredReportTypes: [.feature],
      deliversInputReports: true
    )
    try DriverExtensionGenerator.generate(
      configuration: Self.usbHIDConfiguration(device),
      at: output
    )

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["IOClass"] as? String == "AppleUserHIDDevice")
    #expect(personality["IOProviderClass"] as? String == "IOUSBHostInterface")
    #expect(personality["CFBundleIdentifierKernel"] as? String == "com.apple.iokit.IOHIDFamily")
    #expect(personality["bInterfaceClass"] as? UInt32 == 3)
    #expect(personality["PrimaryUsagePage"] == nil)

    let service = try source("SwifterKitRuntimeService.iig", in: output)
    #expect(service.contains("class SwifterKitRuntimeService : public IOUserUSBHostHIDDevice"))
    #expect(service.contains("#include <HIDDriverKit/IOUserUSBHostHIDDevice.iig>"))
    #expect(service.contains("virtual kern_return_t handleReport("))
    #expect(service.contains("virtual kern_return_t getReport("))
    #expect(service.contains("virtual void setProperty(OSObject* key, OSObject* value)"))

    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("#define SWIFTERKIT_HID_USB_DEVICE 1"))
    #expect(header.contains("#define SWIFTERKIT_HID_DEVICE 1"))
    #expect(header.contains("kSwifterKitHIDReportDescriptorLength = 7;"))
    #expect(header.contains("kSwifterKitHIDAnsweredReportTypes = 4;"))
    #expect(header.contains("kSwifterKitHIDDeliversDeviceInputReports =\n    true;"))
    let encoded = try #require(device.encodedDeviceProperties)
    #expect(header.contains("kSwifterKitHIDDevicePropertiesLength = \(encoded.count);"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func virtualHIDOverUSBKeepsIOUserHIDDevice() throws {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.virtual-usb-hid",
      providerClass: USBDeviceConfiguration.interfaceProviderClass,
      capabilities: [.hid, .usb],
      hidDevice: HIDDeviceConfiguration(
        reportDescriptor: [0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0xC0],
        vendorID: 1,
        productID: 2,
        manufacturer: "Example",
        product: "Virtual",
        serialNumber: "1",
        primaryUsagePage: 0xFF00,
        primaryUsage: 1,
        answeredReportTypes: .feature
      ),
      usbDevice: Self.usbMatch
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("VirtualUSBHID", isDirectory: true)
    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let service = try source("SwifterKitRuntimeService.iig", in: output)
    #expect(service.contains("class SwifterKitRuntimeService : public IOUserHIDDevice"))
    #expect(service.contains("kern_return_t StartUSB(IOService* provider) LOCALONLY;"))
    #expect(!service.contains("virtual kern_return_t handleReport("))
    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["IOClass"] as? String == "AppleUserHIDDevice")
    #expect(personality["CFBundleIdentifierKernel"] as? String == "com.apple.kpi.iokit")
    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("#define SWIFTERKIT_HID_USB_DEVICE 0"))
    #expect(header.contains("kSwifterKitHIDAnsweredReportTypes = 4;"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func rejectsInvalidUSBHIDDevices() {
    let invalid: [DriverConfiguration] = [
      Self.usbHIDConfiguration(USBHIDDeviceConfiguration(reportDescriptor: [])),
      Self.usbHIDConfiguration(USBHIDDeviceConfiguration(deviceProperties: ["": .boolean(true)])),
      Self.usbHIDConfiguration(
        USBHIDDeviceConfiguration(answeredReportTypes: HIDGetReportTypes(rawValue: 1 << 5))
      ), Self.usbHIDConfiguration(USBHIDDeviceConfiguration(), capabilities: .hid),
      Self.usbHIDConfiguration(
        USBHIDDeviceConfiguration(),
        providerClass: USBDeviceConfiguration.deviceProviderClass
      ),
    ]
    for configuration in invalid {
      #expect(throws: DriverExtensionGenerationError.self) {
        try DriverExtensionGenerator.generate(
          configuration: configuration,
          at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
      }
    }
    #expect(throws: DriverExtensionGenerationError.invalidHIDConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: Self.usbHIDConfiguration(USBHIDDeviceConfiguration(reportDescriptor: [])),
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private func source(_ name: String, in output: URL) throws -> String {
    try String(
      contentsOf: output.appendingPathComponent("Sources").appendingPathComponent(name),
      encoding: .utf8
    )
  }
}
