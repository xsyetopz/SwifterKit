import Foundation
import Testing

@testable import SwifterKit

@Suite struct DriverExtensionGeneratorTests {
  @Test func generatesConfiguredNativeRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("GeneratedDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.swift-driver",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .hid,
      hidDevice: hidConfiguration
    )

    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(
        shortVersion: "2.3.4",
        buildVersion: "9",
        deploymentTarget: "21.0"
      ),
      at: output
    )

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    #expect(info["CFBundleShortVersionString"] as? String == "2.3.4")
    #expect(info["CFBundleVersion"] as? String == "9")

    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["IOProviderClass"] as? String == "IOUserResources")
    #expect(personality["IOClass"] as? String == "AppleUserHIDDevice")
    #expect(personality["IOUserClass"] as? String == DriverConfiguration.runtimeServiceClass)
    #expect(personality["PrimaryUsagePage"] as? Int == 0xFF00)
    #expect(personality["PrimaryUsage"] as? Int == 1)

    let header = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeProtocol.h"),
      encoding: .utf8
    )
    #expect(header.contains("kSwifterKitRuntimeCapabilities = 8;"))

    let runtimeConfiguration = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(runtimeConfiguration.contains("SWIFTERKIT_ENABLE_HID 1"))
    #expect(runtimeConfiguration.contains("kSwifterKitHIDVendorID = 4660"))

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    #expect(entitlements["com.apple.developer.driverkit.family.hid.device"] as? Bool == true)

    let project = try String(
      contentsOf: output.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    #expect(project.contains("com.example.swift-driver"))
    #expect(project.contains("DRIVERKIT_DEPLOYMENT_TARGET = 21.0;"))
    #expect(!project.contains("9PQP6CDMQT"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func generatesUSBInterfaceRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.usb-driver",
      providerClass: "IOUSBHostInterface",
      capabilities: .usb,
      usbDevice: USBDeviceConfiguration(
        vendorID: 0x1234,
        productIDs: [0x1000, 0x1001],
        interfaceClass: 0xFF
      )
    )

    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["IOProviderClass"] as? String == "IOUSBHostInterface")
    #expect(personality["idVendor"] as? UInt32 == 0x1234)
    #expect(personality["idProductArray"] as? [UInt32] == [0x1000, 0x1001])

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    let usbEntitlement = try #require(
      entitlements["com.apple.developer.driverkit.transport.usb"] as? [[String: Any]]
    )
    #expect(usbEntitlement.first?["idVendor"] as? UInt32 == 0x1234)

    let configurationHeader = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(configurationHeader.contains("SWIFTERKIT_ENABLE_USB 1"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func generatesCombinedHIDAndUSBRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("CombinedDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.hid-usb-driver",
      providerClass: "IOUSBHostInterface",
      capabilities: [.hid, .usb],
      hidDevice: hidConfiguration,
      usbDevice: USBDeviceConfiguration(vendorID: 0x1234, productIDs: [0x5678])
    )

    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public IOUserHIDDevice"))
    #expect(service.contains("USBControlTransfer"))
    #expect(service.contains("SubmitHIDInputReport"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func generatesPCIMemoryRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("PCIDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.pci-driver",
      providerClass: "IOPCIDevice",
      capabilities: [.pci, .memory],
      pciDevice: PCIDeviceConfiguration(vendorID: 0x1011, deviceIDs: [0x0026]),
      memoryPool: MemoryPoolConfiguration()
    )

    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["IOProviderClass"] as? String == "IOPCIDevice")
    #expect(personality["IOPCIPrimaryMatch"] as? String == "0x00261011")

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    let pciEntitlement = try #require(
      entitlements["com.apple.developer.driverkit.transport.pci"] as? [[String: Any]]
    )
    #expect(pciEntitlement.first?["IOPCIPrimaryMatch"] as? String == "0x00261011")

    let configurationHeader = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(configurationHeader.contains("SWIFTERKIT_ENABLE_PCI 1"))
    #expect(configurationHeader.contains("SWIFTERKIT_ENABLE_MEMORY 1"))

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("MemoryCommand"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func rejectsPCIWithoutMatchingMetadata() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOPCIDevice",
      capabilities: .pci
    )

    #expect(throws: DriverExtensionGenerationError.invalidPCIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test func generatesCombinedHIDAndPCIRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("HIDPCIDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.hid-pci-driver",
      providerClass: "IOPCIDevice",
      capabilities: [.hid, .pci],
      hidDevice: hidConfiguration,
      pciDevice: PCIDeviceConfiguration(vendorID: 0x1011, deviceIDs: [0x0026])
    )

    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public IOUserHIDDevice"))
    #expect(service.contains("PCICommand"))
    #expect(service.contains("SubmitHIDInputReport"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func generatesInterruptRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("InterruptDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.interrupt-driver",
      providerClass: "IOPCIDevice",
      capabilities: [.pci, .interrupts],
      pciDevice: PCIDeviceConfiguration(vendorID: 0x1011, deviceIDs: [0x0026]),
      interruptSources: [
        InterruptSourceConfiguration(index: 0),
        InterruptSourceConfiguration(index: 2, clock: .continuous),
      ]
    )

    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let runtimeConfiguration = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(runtimeConfiguration.contains("SWIFTERKIT_ENABLE_INTERRUPTS 1"))
    #expect(runtimeConfiguration.contains("kSwifterKitInterruptIndices[] = {0, 65538, 0}"))
    #expect(runtimeConfiguration.contains("kSwifterKitInterruptSourceCount =\n    2;"))

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("IOInterruptDispatchSource.iig"))
    #expect(service.contains("InterruptOccurred"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func rejectsInvalidInterruptConfiguration() {
    let duplicate = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOPCIDevice",
      capabilities: .interrupts,
      interruptSources: [
        InterruptSourceConfiguration(index: 1), InterruptSourceConfiguration(index: 1),
      ]
    )
    #expect(throws: DriverExtensionGenerationError.invalidInterruptConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: duplicate,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }

    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOPCIDevice",
      capabilities: .interrupts
    )
    #expect(throws: DriverExtensionGenerationError.invalidInterruptConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }

    let metadataOnly = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOPCIDevice",
      capabilities: [],
      interruptSources: [InterruptSourceConfiguration(index: 0)]
    )
    #expect(throws: DriverExtensionGenerationError.capabilityConfigurationMismatch(.interrupts)) {
      try DriverExtensionGenerator.generate(
        configuration: metadataOnly,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }

    let outOfRange = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOPCIDevice",
      capabilities: .interrupts,
      interruptSources: [InterruptSourceConfiguration(index: 65_536)]
    )
    #expect(throws: DriverExtensionGenerationError.invalidInterruptConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: outOfRange,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test func generatesMemoryRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("MemoryDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.memory-driver",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .memory,
      memoryPool: MemoryPoolConfiguration(
        maximumBuffers: 8,
        maximumBufferSize: 1 << 20,
        maximumTotalSize: 4 << 20
      )
    )

    try DriverExtensionGenerator.generate(configuration: configuration, at: output)

    let runtimeConfiguration = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(runtimeConfiguration.contains("SWIFTERKIT_ENABLE_MEMORY 1"))
    #expect(runtimeConfiguration.contains("kSwifterKitMaximumMemoryBuffers = 8"))
    #expect(runtimeConfiguration.contains("kSwifterKitMaximumMemoryBufferSize =\n    1048576"))

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("StartMemory"))
    #expect(service.contains("MemoryCommand"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func rejectsInvalidMemoryConfiguration() {
    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUserResources",
      capabilities: .memory
    )
    #expect(throws: DriverExtensionGenerationError.invalidMemoryConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }

    let invalid = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUserResources",
      capabilities: .memory,
      memoryPool: MemoryPoolConfiguration(
        maximumBuffers: 65,
        maximumBufferSize: 4_096,
        maximumTotalSize: 4_096
      )
    )
    #expect(throws: DriverExtensionGenerationError.invalidMemoryConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: invalid,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }

    let metadataOnly = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUserResources",
      capabilities: [],
      memoryPool: MemoryPoolConfiguration()
    )
    #expect(throws: DriverExtensionGenerationError.capabilityConfigurationMismatch(.memory)) {
      try DriverExtensionGenerator.generate(
        configuration: metadataOnly,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private func buildGeneratedExtension(at directory: URL, derivedData: URL) throws -> (
    status: Int32, output: String
  ) {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
      "xcodebuild", "-quiet", "-project", "SwifterKitRuntime.xcodeproj", "-scheme",
      "SwifterKitRuntime", "-configuration", "Debug", "-sdk", "driverkit", "-derivedDataPath",
      derivedData.path, "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "DEVELOPMENT_TEAM=",
      "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "GCC_TREAT_WARNINGS_AS_ERRORS=YES", "build",
    ]
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    return (
      process.terminationStatus,
      String(bytes: data, encoding: .utf8) ?? "xcodebuild emitted non-UTF-8 output"
    )
  }

  private var hidConfiguration: HIDDeviceConfiguration {
    HIDDeviceConfiguration(
      reportDescriptor: [
        0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95,
        0x01, 0x09, 0x02, 0x81, 0x02, 0xC0,
      ],
      vendorID: 0x1234,
      productID: 0x5678,
      manufacturer: "Example",
      product: "Swift HID",
      serialNumber: "swift-1",
      primaryUsagePage: 0xFF00,
      primaryUsage: 1
    )
  }
}
