import Foundation
import Testing

@testable import SwifterKit

@Suite
struct BlockStorageGeneratorTests {
  @Test
  func generatesPCIBlockStorageRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("BlockDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.block-driver",
      providerClass: "IOPCIDevice",
      capabilities: [.blockStorage, .pci],
      pciDevice: PCIDeviceConfiguration(vendorID: 0x1234, deviceIDs: [0x5678]),
      blockStorageDevice: deviceConfiguration
    )

    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
      at: output
    )

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["CFBundleIdentifierKernel"] as? String == "com.apple.iokit.IOStorageFamily")

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    #expect(
      entitlements["com.apple.developer.driverkit.family.block-storage-device"] as? Bool == true
    )

    let header = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(header.contains("SWIFTERKIT_ENABLE_BLOCK_STORAGE 1"))
    #expect(header.contains("kSwifterKitBlockCount = 1048576"))

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public IOUserBlockStorageDevice"))
    #expect(service.contains("DoAsyncReadWrite"))
    #expect(service.contains("BlockStorageCommand"))
    #expect(service.contains("PCICommand"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func rejectsMissingInvalidAndConflictingConfiguration() {
    let root = FileManager.default.temporaryDirectory
    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.block",
      providerClass: "IOUserResources",
      capabilities: .blockStorage
    )
    #expect(throws: DriverExtensionGenerationError.invalidBlockStorageConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let invalid = DriverConfiguration(
      bundleIdentifier: "com.example.block",
      providerClass: "IOUserResources",
      capabilities: .blockStorage,
      blockStorageDevice: BlockStorageDeviceConfiguration(
        blockCount: 1,
        blockSize: 500,
        maximumIOSize: 500,
        vendor: "V",
        product: "P",
        revision: "1"
      )
    )
    #expect(throws: DriverExtensionGenerationError.invalidBlockStorageConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: invalid,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let conflicting = DriverConfiguration(
      bundleIdentifier: "com.example.block",
      providerClass: "IOUserResources",
      capabilities: [.serial, .blockStorage],
      serialPort: SerialPortConfiguration(baseName: "serial", suffix: "1"),
      blockStorageDevice: deviceConfiguration
    )
    #expect(throws: DriverExtensionGenerationError.invalidBlockStorageConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: conflicting,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test
  func rejectsDeploymentTargetBeforeBlockStorageDriverKit() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.block",
      providerClass: "IOPCIDevice",
      capabilities: [.blockStorage, .pci],
      pciDevice: PCIDeviceConfiguration(vendorID: 0x1234, deviceIDs: [0x5678]),
      blockStorageDevice: deviceConfiguration
    )

    #expect(throws: DriverExtensionGenerationError.invalidBlockStorageConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        options: DriverExtensionGenerationOptions(deploymentTarget: "20.9"),
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private var deviceConfiguration: BlockStorageDeviceConfiguration {
    BlockStorageDeviceConfiguration(
      blockCount: 1_048_576,
      blockSize: 4_096,
      maximumIOSize: 1_048_576,
      maximumOutstandingIOCount: 32,
      maximumUnmapRegionCount: 128,
      minimumSegmentAlignment: 4_096,
      supportsUnmap: true,
      supportsForceUnitAccess: true,
      vendor: "Example",
      product: "Swift Storage",
      revision: "1.0",
      additionalInfo: "PCI",
      isEjectable: false,
      isRemovable: false
    )
  }
}
