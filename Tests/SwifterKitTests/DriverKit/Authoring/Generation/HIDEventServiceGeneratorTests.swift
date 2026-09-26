import Foundation
import Testing

@testable import SwifterKit

@Suite
struct HIDEventServiceGeneratorTests {
  static func eventConfiguration(
    _ serviceClass: HIDEventServiceClass,
    providerClass: String = HIDEventServiceConfiguration.providerClass,
    capabilities: RuntimeCapabilities = .hid,
    service: HIDEventServiceConfiguration? = nil
  ) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.hid-events",
      providerClass: providerClass,
      capabilities: capabilities,
      hidEventService: service
        ?? HIDEventServiceConfiguration(
          serviceClass: serviceClass,
          usagePairs: [HIDUsagePair(usagePage: 1, usage: 6), HIDUsagePair(usagePage: 0x0C)],
          vendorID: 0x1234,
          productID: 0x5678,
          delivery: [.reports, .elementValues]
        )
    )
  }

  static let options = DriverExtensionGenerationOptions(deploymentTarget: "21.0")

  @Test(arguments: [
    HIDEventServiceClass.eventService, .eventDriver(categories: [.keyboard, .led]),
  ])
  func generatesAndBuildsEventService(_ serviceClass: HIDEventServiceClass) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("HIDEvents", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: Self.eventConfiguration(serviceClass),
      options: Self.options,
      at: output
    )

    let personality = try loadDriverPersonality(in: output)
    #expect(personality["IOClass"] as? String == "AppleUserHIDEventService")
    #expect(personality["IOProviderClass"] as? String == "IOHIDInterface")
    #expect(personality["CFBundleIdentifierKernel"] as? String == "com.apple.iokit.IOHIDFamily")
    #expect(personality["VendorID"] as? UInt32 == 0x1234)
    #expect(personality["ProductID"] as? UInt32 == 0x5678)
    let pairs = try #require(personality["DeviceUsagePairs"] as? [[String: UInt32]])
    #expect(pairs == [["DeviceUsagePage": 1, "DeviceUsage": 6], ["DeviceUsagePage": 0x0C]])
    #expect(personality["PrimaryUsagePage"] == nil)

    let isDriver = serviceClass != .eventService
    let service = try source("SwifterKitRuntimeService.iig", in: output)
    let superclass = isDriver ? "IOUserHIDEventDriver" : "IOUserHIDEventService"
    #expect(service.contains("class SwifterKitRuntimeService : public \(superclass)"))
    #expect(service.contains("#include <HIDDriverKit/\(superclass).iig>"))
    #expect(service.contains("virtual kern_return_t processReport("))
    #expect(service.contains("virtual kern_return_t SetLEDState("))
    #expect(service.contains("virtual bool parseKeyboardElement(") == isDriver)
    #expect(service.contains("virtual void handleGameControllerReport(") == isDriver)
    #expect(!service.contains("newReportDescriptor"))

    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("#define SWIFTERKIT_HID_EVENT_SERVICE 1"))
    #expect(header.contains("#define SWIFTERKIT_HID_EVENT_DRIVER \(isDriver ? 1 : 0)"))
    #expect(header.contains("#define SWIFTERKIT_HID_DEVICE 0"))
    #expect(header.contains("kSwifterKitHIDEventDelivery = 3;"))
    #expect(header.contains("kSwifterKitHIDEventDriverCategories =\n    \(isDriver ? 9 : 0);"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func rejectsInvalidEventServices() {
    let valid = HIDEventServiceConfiguration(usagePairs: [HIDUsagePair(usagePage: 1)])
    let cases: [(DriverConfiguration, DriverExtensionGenerationOptions)] = [
      (Self.eventConfiguration(.eventService, service: valid), DriverExtensionGenerationOptions()),
      (
        Self.eventConfiguration(.eventService, providerClass: "IOService", service: valid),
        Self.options
      ),
      (
        Self.eventConfiguration(.eventService, capabilities: [.hid, .usb], service: valid),
        Self.options
      ),
      (
        Self.eventConfiguration(.eventService, service: HIDEventServiceConfiguration()),
        Self.options
      ),
      (
        Self.eventConfiguration(
          .eventService,
          service: HIDEventServiceConfiguration(usagePairs: [], productID: 1)
        ), Self.options
      ),
      (
        Self.eventConfiguration(
          .eventService,
          service: HIDEventServiceConfiguration(usagePairs: [
            HIDUsagePair(usagePage: 1), HIDUsagePair(usagePage: 1),
          ])
        ), Self.options
      ),
      (
        Self.eventConfiguration(
          .eventService,
          service: HIDEventServiceConfiguration(
            serviceClass: .eventDriver(categories: HIDEventDriverCategories(rawValue: 1 << 8)),
            usagePairs: [HIDUsagePair(usagePage: 1)]
          )
        ), Self.options
      ),
    ]
    for (configuration, options) in cases {
      #expect(throws: DriverExtensionGenerationError.invalidHIDConfiguration) {
        try DriverExtensionGenerator.generate(
          configuration: configuration,
          options: options,
          at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
      }
    }
  }

  @Test
  func rejectsMultipleHIDRolesAndReservedKeys() {
    let twoRoles = DriverConfiguration(
      bundleIdentifier: "com.example.hid-events",
      providerClass: HIDEventServiceConfiguration.providerClass,
      capabilities: .hid,
      hidEventService: HIDEventServiceConfiguration(usagePairs: [HIDUsagePair(usagePage: 1)]),
      usbHIDDevice: USBHIDDeviceConfiguration()
    )
    #expect(throws: DriverExtensionGenerationError.invalidHIDConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: twoRoles,
        options: Self.options,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
    let withoutCapability = DriverConfiguration(
      bundleIdentifier: "com.example.hid-events",
      providerClass: HIDEventServiceConfiguration.providerClass,
      capabilities: [],
      hidEventService: HIDEventServiceConfiguration(usagePairs: [HIDUsagePair(usagePage: 1)])
    )
    #expect(throws: DriverExtensionGenerationError.capabilityConfigurationMismatch(.hid)) {
      try DriverExtensionGenerator.generate(
        configuration: withoutCapability,
        options: Self.options,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
    let reserved = DriverConfiguration(
      bundleIdentifier: "com.example.hid-events",
      providerClass: HIDEventServiceConfiguration.providerClass,
      matchingProperties: ["DeviceUsagePairs": .array([])],
      capabilities: .hid,
      hidEventService: HIDEventServiceConfiguration(usagePairs: [HIDUsagePair(usagePage: 1)])
    )
    #expect(throws: DriverExtensionGenerationError.reservedMatchingProperty("DeviceUsagePairs")) {
      try DriverExtensionGenerator.generate(
        configuration: reserved,
        options: Self.options,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }
}
