import Foundation
import Testing

@testable import SwifterKit

@Suite
struct NetworkingGeneratorTests {
  @Test
  func generatesNetworkingRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("EthernetDriver")
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.ethernet",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .networking,
      ethernetDevice: deviceConfiguration
    )

    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
      at: output
    )

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["CFBundleIdentifierKernel"] as? String == "com.apple.iokit.IOSkywalkFamily")
    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    #expect(entitlements["com.apple.developer.driverkit.family.networking"] as? Bool == true)

    let config = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(config.contains("SWIFTERKIT_ENABLE_NETWORKING 1"))
    #expect(config.contains("kSwifterKitEthernetAddress[] = {2, 3, 4, 5, 6, 7}"))
    #expect(config.contains("kSwifterKitEthernetMTU = 1500"))
    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public IOUserNetworkEthernet"))
    #expect(service.contains("NetworkTxPacketAvailable"))
    #expect(service.contains("setInterfaceEnable"))

    // The family's power change is acknowledged through super whether or not Swift is notified,
    // and never through SUPERDISPATCH here, which SwifterKitRuntimeServicePower already owns.
    let setup = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeNetworkSetup.cpp"),
      encoding: .utf8
    )
    let power = try #require(
      setup.range(of: "SwifterKitRuntimeService::setPowerState(")?.upperBound
    )
    let powerEnd = try #require(setup.range(of: "\n}", range: power..<setup.endIndex)?.lowerBound)
    let powerBody = setup[power..<powerEnd]
    #expect(
      powerBody.contains(
        "(void)NetworkControlEvent(kSwifterKitNetworkEventPowerState, "
          + "static_cast<uint32_t>(state));"
      )
    )
    #expect(powerBody.contains("return super::setPowerState(state, device);"))
    #expect(!powerBody.contains("SUPERDISPATCH"))
    #expect(!powerBody.contains("?"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func generatesUSBBackedNetworkingRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBEthernetDriver")
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.usb-ethernet",
      providerClass: "IOUSBHostInterface",
      capabilities: [.networking, .usb],
      usbDevice: USBDeviceConfiguration(
        vendorID: 0x1234,
        productIDs: [0x5678],
        interfaceClass: 0xFF
      ),
      ethernetDevice: deviceConfiguration
    )
    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
      at: output
    )
    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func rejectsMissingInvalidOldAndConflictingConfiguration() {
    let root = FileManager.default.temporaryDirectory
    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.net",
      providerClass: "IOUserResources",
      capabilities: .networking
    )
    #expect(throws: DriverExtensionGenerationError.invalidEthernetConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
    let multicast = EthernetDeviceConfiguration(hardwareAddress: EthernetAddress(1, 2, 3, 4, 5, 6))
    let invalid = DriverConfiguration(
      bundleIdentifier: "com.example.net",
      providerClass: "IOUserResources",
      capabilities: .networking,
      ethernetDevice: multicast
    )
    #expect(throws: DriverExtensionGenerationError.invalidEthernetConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: invalid,
        options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
    let valid = DriverConfiguration(
      bundleIdentifier: "com.example.net",
      providerClass: "IOUserResources",
      capabilities: .networking,
      ethernetDevice: deviceConfiguration
    )
    #expect(throws: DriverExtensionGenerationError.invalidEthernetConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: valid,
        options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
    let conflict = DriverConfiguration(
      bundleIdentifier: "com.example.net",
      providerClass: "IOUserResources",
      capabilities: [.networking, .midi],
      midiDevice: MIDIDeviceConfiguration(
        driverName: "M",
        deviceIdentifier: "D",
        modelIdentifier: "X",
        manufacturerIdentifier: "Y",
        entityName: "E",
        protocol: .midi1,
        sourceCount: 1,
        destinationCount: 0
      ),
      ethernetDevice: deviceConfiguration
    )
    #expect(throws: DriverExtensionGenerationError.invalidEthernetConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: conflict,
        options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private var deviceConfiguration: EthernetDeviceConfiguration {
    EthernetDeviceConfiguration(hardwareAddress: EthernetAddress(2, 3, 4, 5, 6, 7))
  }
}
