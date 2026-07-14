import Foundation
import SwifterKit
import Testing

@Suite struct DriverExtensionGeneratorValidationTests {
  @Test func refusesExistingDestination() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: output) }

    #expect(throws: DriverExtensionGenerationError.self) {
      try DriverExtensionGenerator.generate(configuration: validConfiguration, at: output)
    }
  }

  @Test func rejectsReservedPersonalityKey() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUserResources",
      matchingProperties: ["IOUserClass": .string("Override")],
      capabilities: []
    )

    #expect(throws: DriverExtensionGenerationError.reservedMatchingProperty("IOUserClass")) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test func rejectsInvalidBundleIdentifier() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "invalid",
      providerClass: "IOUserResources",
      capabilities: []
    )

    #expect(throws: DriverExtensionGenerationError.invalidBundleIdentifier("invalid")) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test func rejectsCapabilitiesWithoutNativeImplementation() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUSBHostInterface",
      capabilities: RuntimeCapabilities(rawValue: 1 << 63)
    )

    #expect(
      throws: DriverExtensionGenerationError.unsupportedCapabilities(
        RuntimeCapabilities(rawValue: 1 << 63)
      )
    ) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test func rejectsUSBWithoutMatchingMetadata() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUSBHostInterface",
      capabilities: .usb
    )

    #expect(throws: DriverExtensionGenerationError.invalidUSBConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test func rejectsHIDWithoutDeviceMetadata() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUserResources",
      capabilities: .hid
    )

    #expect(throws: DriverExtensionGenerationError.invalidHIDConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test(arguments: ["", ".19", "18.9", "19.", "19..0", "nineteen"])
  func rejectsInvalidOrPreDriverKitDeploymentTargets(target: String) {
    #expect(throws: DriverExtensionGenerationError.invalidDeploymentTarget) {
      try DriverExtensionGenerator.generate(
        configuration: validConfiguration,
        options: DriverExtensionGenerationOptions(deploymentTarget: target),
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private var validConfiguration: DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUserResources",
      capabilities: []
    )
  }
}
