import Foundation
import Testing

@testable import SwifterKit

@Suite
struct SCSIGeneratorTests {
  @Test
  func generatesPCIControllerRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("SCSIDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.scsi-driver",
      providerClass: "IOPCIDevice",
      capabilities: [.scsi, .pci],
      pciDevice: PCIDeviceConfiguration(vendorID: 0x1234, deviceIDs: [0x5678]),
      scsiController: controller
    )

    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "20.4"),
      at: output
    )

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    #expect(entitlements["com.apple.developer.driverkit.family.scsicontroller"] as? Bool == true)

    let header = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(header.contains("SWIFTERKIT_ENABLE_SCSI_CONTROLLER 1"))
    #expect(header.contains("kSwifterKitSCSIMaximumTaskCount =\n    32"))
    #expect(header.contains("kSwifterKitSCSISupportedFeatures =\n    3"))

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public IOUserSCSIParallelInterfaceController"))
    #expect(service.contains("UserProcessParallelTask"))
    #expect(service.contains("SCSICommand"))
    #expect(service.contains("PCICommand"))

    let project = try String(
      contentsOf: output.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    #expect(project.contains("SCSIControllerDriverKit.framework"))
    #expect(project.contains("SwifterKitRuntimeSCSI.cpp in Sources"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func rejectsMissingInvalidAndConflictingPolicy() {
    let root = FileManager.default.temporaryDirectory
    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.scsi",
      providerClass: "IOUserResources",
      capabilities: .scsi
    )
    #expect(throws: DriverExtensionGenerationError.invalidSCSIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let invalid = DriverConfiguration(
      bundleIdentifier: "com.example.scsi",
      providerClass: "IOUserResources",
      capabilities: .scsi,
      scsiController: SCSIControllerConfiguration(
        initiatorIdentifier: 7,
        highestTargetIdentifier: 15,
        maximumTaskCount: 0
      )
    )
    #expect(throws: DriverExtensionGenerationError.invalidSCSIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: invalid,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let conflicting = DriverConfiguration(
      bundleIdentifier: "com.example.scsi",
      providerClass: "IOUserResources",
      capabilities: [.scsi, .audio],
      scsiController: controller
    )
    #expect(throws: DriverExtensionGenerationError.invalidAudioConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: conflicting,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test
  func rejectsDeploymentTargetBeforeSCSIControllerDriverKit() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.scsi",
      providerClass: "IOPCIDevice",
      capabilities: [.scsi, .pci],
      pciDevice: PCIDeviceConfiguration(vendorID: 0x1234, deviceIDs: [0x5678]),
      scsiController: controller
    )

    #expect(throws: DriverExtensionGenerationError.invalidSCSIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        options: DriverExtensionGenerationOptions(deploymentTarget: "20.3"),
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private var controller: SCSIControllerConfiguration {
    SCSIControllerConfiguration(
      initiatorIdentifier: 7,
      highestTargetIdentifier: 15,
      highestLogicalUnitNumber: 255,
      maximumTaskCount: 32,
      maximumTransferSize: 1_048_576,
      minimumSegmentAlignment: 4_096,
      addressBitCount: 64,
      dmaSegmentType: .host64,
      supportedFeatures: [.wideDataTransfer, .synchronousDataTransfer],
      taskManagementResponse: .functionComplete
    )
  }
}
