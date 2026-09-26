import Foundation
import Testing

@testable import SwifterKit

@Suite
struct SCSIPeripheralGeneratorTests {
  @Test(arguments: SCSIPeripheralDeviceType.allCases)
  func generatesPeripheralRuntime(type: SCSIPeripheralDeviceType) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("PeripheralDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.scsi-peripheral",
      providerClass: "IOService",
      capabilities: .scsi,
      scsiPeripheral: SCSIPeripheralConfiguration(
        deviceType: type,
        transferConstraints: SCSIPeripheralTransferConstraints(
          maximumBlockCountRead: 128,
          maximumByteCountWrite: 65_536,
          minimumSegmentAlignmentByteCount: 4,
          maximumSegmentAddressableBitCount: 64
        )
      )
    )

    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
      at: output
    )

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    #expect(entitlements["com.apple.developer.driverkit"] as? Bool == true)
    #expect(entitlements["com.apple.developer.driverkit.family.scsicontroller"] == nil)

    let personality = try loadDriverPersonality(in: output)
    #expect(personality["IOMaximumBlockCountRead"] as? UInt64 == 128)
    #expect(personality["IOMaximumByteCountWrite"] as? UInt64 == 65_536)
    #expect(personality["IOMinimumSegmentAlignmentByteCount"] as? UInt64 == 4)
    #expect(personality["IOMaximumSegmentAddressableBitCount"] as? UInt64 == 64)
    #expect(personality["IOMaximumBlockCountWrite"] == nil)

    let header = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(header.contains("SWIFTERKIT_ENABLE_SCSI_CONTROLLER 0"))
    #expect(header.contains("SWIFTERKIT_ENABLE_SCSI_PERIPHERAL 1"))
    #expect(header.contains("SWIFTERKIT_SCSI_PERIPHERAL_TYPE \(type.rawValue)"))

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public \(superclass(for: type))"))
    #expect(service.contains("SCSIPeripheralCommand"))
    let callback =
      type == .multimediaCommands
      ? "UserInitializeDeviceSupport" : "UserDetermineDeviceCharacteristics"
    #expect(service.contains(callback))

    let project = try String(
      contentsOf: output.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    #expect(project.contains("SCSIPeripheralsDriverKit.framework"))
    #expect(project.contains("SwifterKitRuntimeSCSIPeripheral.cpp in Sources"))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func rejectsAmbiguousAndDetachedConfiguration() {
    let root = FileManager.default.temporaryDirectory
    let controller = SCSIControllerConfiguration(
      initiatorIdentifier: 7,
      highestTargetIdentifier: 15
    )
    let peripheral = SCSIPeripheralConfiguration(deviceType: .blockCommands)
    let ambiguous = DriverConfiguration(
      bundleIdentifier: "com.example.scsi",
      providerClass: "IOService",
      capabilities: .scsi,
      scsiController: controller,
      scsiPeripheral: peripheral
    )
    #expect(throws: DriverExtensionGenerationError.invalidSCSIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: ambiguous,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let detached = DriverConfiguration(
      bundleIdentifier: "com.example.scsi",
      providerClass: "IOService",
      capabilities: [],
      scsiPeripheral: peripheral
    )
    #expect(throws: DriverExtensionGenerationError.capabilityConfigurationMismatch(.scsi)) {
      try DriverExtensionGenerator.generate(
        configuration: detached,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test
  func rejectsDeploymentTargetBeforeSCSIPeripheralsDriverKit() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.scsi-peripheral",
      providerClass: "IOService",
      capabilities: .scsi,
      scsiPeripheral: SCSIPeripheralConfiguration(deviceType: .blockCommands)
    )

    #expect(throws: DriverExtensionGenerationError.invalidSCSIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        options: DriverExtensionGenerationOptions(deploymentTarget: "21.9"),
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private func superclass(for type: SCSIPeripheralDeviceType) -> String {
    switch type {
    case .blockCommands: "IOUserSCSIPeripheralDeviceType00"
    case .multimediaCommands: "IOUserSCSIPeripheralDeviceType05"
    case .opticalMemory: "IOUserSCSIPeripheralDeviceType07"
    }
  }

}
