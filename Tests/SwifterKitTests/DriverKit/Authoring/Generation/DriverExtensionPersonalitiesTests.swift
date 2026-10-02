import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverExtensionPersonalitiesTests {
  static let bundleIdentifier = "com.example.multi-personality"

  static func factory(bundleIdentifier: String = bundleIdentifier) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: bundleIdentifier,
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .hid,
      hidDeviceFactory: HIDDeviceFactoryConfiguration(maximumDevices: 4)
    )
  }

  static let usbInterface = DriverConfiguration(
    bundleIdentifier: bundleIdentifier,
    providerClass: USBDeviceConfiguration.interfaceProviderClass,
    capabilities: .usb,
    usbDevice: USBDeviceConfiguration(vendorID: 0x045E, productIDs: [0x028E], interfaceNumber: 0)
  )

  static let eventService = DriverConfiguration(
    bundleIdentifier: bundleIdentifier,
    providerClass: HIDEventServiceConfiguration.providerClass,
    capabilities: .hid,
    hidEventService: HIDEventServiceConfiguration(
      usagePairs: [HIDUsagePair(usagePage: 1, usage: 5)],
      vendorID: 0x045E,
      productID: 0x028E
    )
  )

  static let serial = DriverConfiguration(
    bundleIdentifier: bundleIdentifier,
    providerClass: "IOUserResources",
    matchingProperties: ["IOResourceMatch": .string("IOKit")],
    capabilities: .serial,
    serialPort: SerialPortConfiguration(baseName: "usbserial", suffix: "Example")
  )

  static let pci = DriverConfiguration(
    bundleIdentifier: bundleIdentifier,
    providerClass: "IOPCIDevice",
    capabilities: [.pci, .interrupts],
    pciDevice: PCIDeviceConfiguration(
      vendorID: 0x1011,
      deviceIDs: [0x0026],
      interrupts: PCIInterruptConfiguration(type: .msi)
    ),
    interruptSources: [InterruptSourceConfiguration(index: 0)]
  )

  static let extensionConfiguration = DriverExtensionConfiguration(
    bundleIdentifier: bundleIdentifier,
    personalities: ["HIDFactory": factory(), "XboxUSB": usbInterface]
  )

  @Test
  func generatesOneRuntimePerPersonality() throws {
    try withTemporaryExtension(Self.extensionConfiguration) { output, root in
      let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
      let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
      #expect(Set(personalities.keys) == ["HIDFactory", "XboxUSB"])

      let factory = try #require(personalities["HIDFactory"] as? [String: Any])
      #expect(factory["IOProviderClass"] as? String == "IOUserResources")
      #expect(factory["IOUserClass"] as? String == "SwifterKitHIDFactoryRuntimeService")
      #expect(userClientClass(factory) == "SwifterKitHIDFactoryRuntimeUserClient")
      let device = try #require(factory["HIDDeviceProperties"] as? [String: Any])
      #expect(device["IOUserClass"] as? String == "SwifterKitHIDFactoryRuntimeHIDDevice")
      #expect(factory["SwifterKitPersonality"] == nil)
      #expect(factory["SwifterKitCapabilities"] == nil)

      let usb = try #require(personalities["XboxUSB"] as? [String: Any])
      #expect(usb["IOProviderClass"] as? String == "IOUSBHostInterface")
      #expect(usb["IOUserClass"] as? String == "SwifterKitXboxUSBRuntimeService")
      #expect(userClientClass(usb) == "SwifterKitXboxUSBRuntimeUserClient")
      #expect(usb["idVendor"] as? UInt32 == 0x045E)
      #expect(usb["HIDDeviceProperties"] == nil)

      let entitlements = try loadEntitlements(in: output)
      #expect(entitlements["com.apple.developer.driverkit"] as? Bool == true)
      #expect(entitlements["com.apple.developer.driverkit.family.hid.device"] as? Bool == true)
      let transport = try #require(
        entitlements["com.apple.developer.driverkit.transport.usb"] as? [[String: Any]]
      )
      #expect(transport.count == 1)
      #expect(transport.first?["idVendor"] as? UInt32 == 0x045E)

      try expectCapabilities(.hid, personality: "HIDFactory", in: output)
      try expectCapabilities(.usb, personality: "XboxUSB", in: output)
      let factoryHeader = try source("SwifterKitHIDFactoryRuntimeConfiguration.h", in: output)
      #expect(factoryHeader.contains("#define SWIFTERKIT_HID_DEVICE_FACTORY 1"))
      #expect(factoryHeader.contains("#define SWIFTERKIT_ENABLE_USB 0"))
      #expect(collapsed(factoryHeader).contains("kSwifterKitHIDMaximumDevices = 4;"))
      let usbHeader = try source("SwifterKitXboxUSBRuntimeConfiguration.h", in: output)
      #expect(usbHeader.contains("#define SWIFTERKIT_ENABLE_USB 1"))
      #expect(usbHeader.contains("#define SWIFTERKIT_ENABLE_HID 0"))
      try expectOnlyPersonalitySources(["HIDFactory", "XboxUSB"], in: output)

      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }

  @Test
  func buildsPersonalitiesWithDifferentSuperclasses() throws {
    let mixed = DriverExtensionConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      personalities: ["Factory": Self.factory(), "Events": Self.eventService, "Port": Self.serial]
    )
    try withTemporaryExtension(
      mixed,
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0")
    ) { output, root in
      let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
      let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
      let events = try #require(personalities["Events"] as? [String: Any])
      #expect(events["IOClass"] as? String == "AppleUserHIDEventService")
      #expect(events["IOUserClass"] as? String == "SwifterKitEventsRuntimeService")
      let port = try #require(personalities["Port"] as? [String: Any])
      #expect(port["IOTTYBaseName"] as? String == "usbserial")
      #expect(port["IOUserClass"] as? String == "SwifterKitPortRuntimeService")

      let factoryInterface = try source("SwifterKitFactoryRuntimeService.iig", in: output)
      #expect(factoryInterface.contains("class SwifterKitFactoryRuntimeService : public IOService"))
      let eventInterface = try source("SwifterKitEventsRuntimeService.iig", in: output)
      #expect(eventInterface.contains("public IOUserHIDEventService"))
      let portInterface = try source("SwifterKitPortRuntimeService.iig", in: output)
      #expect(portInterface.contains("public IOUserSerial"))
      try expectOnlyPersonalitySources(["Events", "Factory", "Port"], in: output)

      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }

  @Test
  func buildsPCIWithInterruptsBesideUSB() throws {
    let combined = DriverExtensionConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      personalities: ["Card": Self.pci, "XboxUSB": Self.usbInterface]
    )
    try withTemporaryExtension(combined) { output, root in
      try expectCapabilities([.pci, .interrupts], personality: "Card", in: output)
      try expectCapabilities(.usb, personality: "XboxUSB", in: output)
      let entitlements = try loadEntitlements(in: output)
      #expect(entitlements["com.apple.developer.driverkit.transport.pci"] != nil)
      #expect(entitlements["com.apple.developer.driverkit.transport.usb"] != nil)
      let project = try String(
        contentsOf: output.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
        encoding: .utf8
      )
      #expect(project.contains("PCIDriverKit.framework"))
      #expect(project.contains("USBDriverKit.framework"))
      #expect(!project.contains("HIDDriverKit.framework"))

      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }

  @Test
  func serviceClassNamesThePersonalityOnlyWhenRequested() throws {
    #expect(Self.factory().serviceClass == DriverConfiguration.runtimeServiceClass)
    #expect(Self.extensionConfiguration.personalities["XboxUSB"]?.personalityName == nil)

    let usb = try #require(Self.extensionConfiguration.personality("XboxUSB"))
    #expect(usb.personalityName == "XboxUSB")
    #expect(usb.serviceClass == "SwifterKitXboxUSBRuntimeService")
    #expect(
      usb.serviceMatch.registryProperties == [
        "CFBundleIdentifier": .string(Self.bundleIdentifier),
        "IOUserClass": .string("SwifterKitXboxUSBRuntimeService"),
      ]
    )
    #expect(usb != Self.usbInterface)
    #expect(Self.extensionConfiguration.personality("Missing") == nil)
  }

  @Test
  func generatingOnePersonalityUsesItsClasses() throws {
    let usb = try #require(Self.extensionConfiguration.personality("XboxUSB"))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("Single")
    try DriverExtensionGenerator.generate(configuration: usb, at: output)

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let entry = try #require(personalities["XboxUSB"] as? [String: Any])
    #expect(entry["IOUserClass"] as? String == usb.serviceClass)
    try expectOnlyPersonalitySources(["XboxUSB"], in: output)
  }

  @Test
  func rejectsAnEmptyPersonalitySet() {
    let empty = DriverExtensionConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      personalities: [:]
    )
    #expect(throws: DriverExtensionGenerationError.noPersonalities) {
      try withTemporaryExtension(empty) { _, _ in }
    }
  }

  @Test(arguments: ["", "1Pad", "Pad-1", "Pad_1", "Pad 1", "Päd"])
  func rejectsNamesThatAreNotIdentifiers(_ name: String) {
    let invalid = DriverExtensionConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      personalities: [name: Self.usbInterface]
    )
    #expect(throws: DriverExtensionGenerationError.invalidPersonalityName(name)) {
      try withTemporaryExtension(invalid) { _, _ in }
    }
  }

  @Test(arguments: [("Pad", "Pad2"), ("Pad", "pad"), ("pad", "PADUSB")])
  func rejectsNamesWhereOneStartsAnother(_ first: String, _ second: String) {
    let overlapping = DriverExtensionConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      personalities: [first: Self.usbInterface, second: Self.factory()]
    )
    #expect(throws: DriverExtensionGenerationError.invalidPersonalityName(min(first, second))) {
      try withTemporaryExtension(overlapping) { _, _ in }
    }
  }

  @Test
  func rejectsAPersonalityNamedDifferentlyFromItsConfiguration() throws {
    let usb = try #require(Self.extensionConfiguration.personality("XboxUSB"))
    let renamed = DriverExtensionConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      personalities: ["Gamepad": usb]
    )
    #expect(throws: DriverExtensionGenerationError.invalidPersonalityName("Gamepad")) {
      try withTemporaryExtension(renamed) { _, _ in }
    }
  }

  @Test
  func rejectsMismatchedBundleIdentifiers() {
    let mismatched = DriverExtensionConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      personalities: [
        "HIDFactory": Self.factory(bundleIdentifier: "com.example.other"),
        "XboxUSB": Self.usbInterface,
      ]
    )
    #expect(throws: DriverExtensionGenerationError.invalidBundleIdentifier("com.example.other")) {
      try withTemporaryExtension(mismatched) { _, _ in }
    }
  }

  @Test
  func reportsAPersonalitysOwnValidationError() throws {
    let invalid = DriverConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      providerClass: "IOUserResources",
      matchingProperties: ["IOUserClass": .string("Other")],
      capabilities: .usb,
      usbDevice: USBDeviceConfiguration(vendorID: 0x045E, interfaceNumber: 0)
    )
    let combined = DriverExtensionConfiguration(
      bundleIdentifier: Self.bundleIdentifier,
      personalities: ["HIDFactory": Self.factory(), "XboxUSB": invalid]
    )
    let expected = #expect(throws: DriverExtensionGenerationError.self) {
      try DriverExtensionGenerator.validate(
        configuration: invalid,
        options: DriverExtensionGenerationOptions()
      )
    }
    let error = try #require(expected)
    #expect(throws: error) { try withTemporaryExtension(combined) { _, _ in } }
  }

  private func userClientClass(_ personality: [String: Any]) -> String? {
    (personality["UserClientProperties"] as? [String: Any])?["IOUserClass"] as? String
  }

  private func expectCapabilities(
    _ capabilities: RuntimeCapabilities,
    personality: String,
    in output: URL,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let header = try source("SwifterKit\(personality)RuntimeProtocol.h", in: output)
    #expect(
      header.contains(
        "static constexpr uint64_t kSwifterKitRuntimeCapabilities = \(capabilities.rawValue);"
      ),
      sourceLocation: sourceLocation
    )
  }

  /// Expects every runtime source to belong to one of `personalities`, each with the same files,
  /// and no source to name a class or file of the unrenamed runtime.
  private func expectOnlyPersonalitySources(
    _ personalities: [String],
    in output: URL,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let sources = output.appendingPathComponent("Sources")
    let names = try FileManager.default.contentsOfDirectory(atPath: sources.path)
    var files: [String: Set<String>] = [:]
    for name in names {
      let owner = personalities.first { name.hasPrefix("SwifterKit\($0)Runtime") }
      #expect(owner != nil, "\(name)", sourceLocation: sourceLocation)
      if let owner {
        files[owner, default: []].insert(String(name.dropFirst("SwifterKit\(owner)".count)))
      }
      let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
      #expect(
        !DriverExtensionPersonalityRenaming.renamedSource(text, personality: "Unrenamed").contains(
          "SwifterKitUnrenamedRuntime"
        ),
        "\(name) names the unrenamed runtime",
        sourceLocation: sourceLocation
      )
    }
    #expect(Set(files.keys) == Set(personalities), sourceLocation: sourceLocation)
    #expect(Set(files.values).count == 1, sourceLocation: sourceLocation)
    #expect(
      files.values.first?.contains("RuntimeService.iig") == true,
      sourceLocation: sourceLocation
    )
  }

  private func collapsed(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// Generates `configuration` into a fresh temporary directory, then runs `body` with the
  /// extension directory and the temporary root, which is removed afterwards.
  private func withTemporaryExtension(
    _ configuration: DriverExtensionConfiguration,
    options: DriverExtensionGenerationOptions = DriverExtensionGenerationOptions(),
    _ body: (_ output: URL, _ root: URL) throws -> Void
  ) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("MultiPersonality", isDirectory: true)
    try DriverExtensionGenerator.generate(extension: configuration, options: options, at: output)
    try body(output, root)
  }
}
