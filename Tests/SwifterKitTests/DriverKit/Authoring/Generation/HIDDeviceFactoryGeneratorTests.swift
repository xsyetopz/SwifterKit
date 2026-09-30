import Foundation
import Testing

@testable import SwifterKit

@Suite
struct HIDDeviceFactoryGeneratorTests {
  static func factoryConfiguration(
    maximumDevices: Int = 8,
    capabilities: RuntimeCapabilities = .hid,
    matchingProperties: [String: DriverProperty] = ["IOResourceMatch": .string("IOKit")],
    hidDevice: HIDDeviceConfiguration? = nil
  ) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.hid-factory",
      providerClass: "IOUserResources",
      matchingProperties: matchingProperties,
      capabilities: capabilities,
      hidDevice: hidDevice,
      hidDeviceFactory: HIDDeviceFactoryConfiguration(maximumDevices: maximumDevices)
    )
  }

  @Test
  func generatesFactoryRoot() throws {
    try withTemporaryExtension(named: "HIDFactory", configuration: Self.factoryConfiguration()) {
      output,
      root in
      let personality = try loadDriverPersonality(in: output)
      #expect(personality["IOClass"] as? String == "IOUserService")
      #expect(personality["IOProviderClass"] as? String == "IOUserResources")
      #expect(personality["CFBundleIdentifierKernel"] as? String == "com.apple.kpi.iokit")
      #expect(personality["PrimaryUsagePage"] == nil)
      let child = try #require(personality["HIDDeviceProperties"] as? [String: String])
      #expect(
        child == ["IOClass": "AppleUserHIDDevice", "IOUserClass": "SwifterKitRuntimeHIDDevice"]
      )

      let entitlements = try loadEntitlements(in: output)
      #expect(entitlements["com.apple.developer.driverkit.family.hid.device"] as? Bool == true)
      #expect(entitlements["com.apple.developer.hid.virtual.device"] == nil)

      let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
      #expect(header.contains("#define SWIFTERKIT_ENABLE_HID 1"))
      #expect(header.contains("#define SWIFTERKIT_HID_DEVICE_FACTORY 1"))
      #expect(header.contains("#define SWIFTERKIT_HID_DEVICE 0"))
      #expect(header.contains("#define SWIFTERKIT_HID_EVENT_SERVICE 0"))
      #expect(header.contains("kSwifterKitHIDMaximumDevices =\n    8;"))

      let service = try source("SwifterKitRuntimeService.iig", in: output)
      #expect(service.contains("class SwifterKitRuntimeService : public IOService"))
      #expect(!service.contains("#include <HIDDriverKit/"))
      #expect(service.contains("kern_return_t HIDFactoryCommand("))
      #expect(service.contains("kern_return_t HIDFactoryAttachDevice("))
      #expect(service.contains("void HIDFactoryDeviceStopped(uint32_t handle) LOCALONLY;"))
      #expect(service.contains("virtual kern_return_t Start(IOService* provider) override;"))
      #expect(!service.contains("newReportDescriptor"))
      #expect(!service.contains("SubmitHIDInputReport"))

      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }

  @Test
  func staticModesDisableTheFactory() {
    let header = DriverExtensionGenerator.runtimeConfigurationHeader(
      Self.factoryConfiguration(maximumDevices: 1)
    )
    #expect(header.contains("kSwifterKitHIDMaximumDevices =\n    1;"))

    let staticHeader = DriverExtensionGenerator.runtimeConfigurationHeader(
      DriverConfiguration(
        bundleIdentifier: "com.example.hid",
        providerClass: "IOUserResources",
        capabilities: .hid,
        hidDevice: Self.device
      )
    )
    #expect(staticHeader.contains("#define SWIFTERKIT_HID_DEVICE_FACTORY 0"))
    #expect(staticHeader.contains("#define SWIFTERKIT_HID_DEVICE 1"))
    #expect(staticHeader.contains("kSwifterKitHIDMaximumDevices =\n    0;"))
  }

  @Test
  func checkedInHeaderDisablesTheFactory() throws {
    let header = try String(
      contentsOf: checkedInNativeSources.appendingPathComponent("SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(header.contains("#define SWIFTERKIT_HID_DEVICE_FACTORY 0"))
    #expect(header.contains("kSwifterKitHIDMaximumDevices = 0;"))
  }

  @Test(arguments: [
    factoryConfiguration(maximumDevices: 0),
    factoryConfiguration(maximumDevices: RuntimeHIDLimits.maximumFactoryDevices + 1),
    factoryConfiguration(hidDevice: device), factoryConfiguration(capabilities: [.hid, .usb]),
    factoryConfiguration(capabilities: [.hid, .audio]),
    factoryConfiguration(capabilities: [.hid, .serial]),
  ])
  func rejectsInvalidFactories(_ configuration: DriverConfiguration) {
    #expect(throws: DriverExtensionGenerationError.invalidHIDConfiguration) {
      try generate(configuration)
    }
  }

  @Test
  func acceptsTheDeviceLimitBounds() throws {
    for count in [1, RuntimeHIDLimits.maximumFactoryDevices] {
      #expect(HIDDeviceFactoryConfiguration.deviceLimit.contains(count))
      try withTemporaryExtension(
        named: "Bounds",
        configuration: Self.factoryConfiguration(maximumDevices: count)
      ) { _, _ in }
    }
  }

  @Test
  func requiresTheHIDCapability() {
    #expect(throws: DriverExtensionGenerationError.capabilityConfigurationMismatch(.hid)) {
      try generate(Self.factoryConfiguration(capabilities: []))
    }
  }

  @Test
  func reservesTheChildPropertiesKey() {
    let configuration = Self.factoryConfiguration(matchingProperties: [
      "IOResourceMatch": .string("IOKit"), "HIDDeviceProperties": .string("x"),
    ])
    #expect(throws: DriverExtensionGenerationError.reservedMatchingProperty("HIDDeviceProperties"))
    { try generate(configuration) }
  }

  private func generate(_ configuration: DriverConfiguration) throws {
    try withTemporaryExtension(named: "Invalid", configuration: configuration) { _, _ in }
  }

  static let device = HIDDeviceConfiguration(
    reportDescriptor: [0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0xC0],
    vendorID: 1,
    productID: 2,
    manufacturer: "M",
    product: "P",
    serialNumber: "S",
    primaryUsagePage: 1,
    primaryUsage: 5
  )
}
