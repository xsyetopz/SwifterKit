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

    let entitlements = try loadEntitlements(in: output)
    #expect(entitlements["com.apple.developer.driverkit.family.scsicontroller"] as? Bool == true)

    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("SWIFTERKIT_ENABLE_SCSI_CONTROLLER 1"))
    #expect(header.contains("kSwifterKitSCSIMaximumTaskCount =\n    32"))
    #expect(header.contains("kSwifterKitSCSISupportedFeatures =\n    3"))
    #expect(header.contains("kSwifterKitSCSIProvidesTaskDataBuffers =\n    true"))
    #expect(header.contains("kSwifterKitSCSIReportsConstraints = true"))
    #expect(header.contains("kSwifterKitSCSIMaximumSegmentCountWrite =\n    128"))
    #expect(header.contains("kSwifterKitSCSIMinimumHBADataAlignmentMask =\n    3"))
    #expect(header.contains("kSwifterKitSCSISupportsHierarchicalLogicalUnits =\n    true"))

    let service = try source("SwifterKitRuntimeService.iig", in: output)
    #expect(service.contains("public IOUserSCSIParallelInterfaceController"))
    #expect(service.contains("UserProcessParallelTask"))
    #expect(service.contains("SCSICommand"))
    #expect(service.contains("PCICommand"))
    #expect(service.contains("SCSIControlCommand"))
    #expect(service.contains("SCSIFetchTaskBuffer"))

    let scsi = try source("SwifterKitRuntimeSCSI.cpp", in: output)
    let enqueueFailure = try #require(
      scsi.range(of: "EnqueueRequiredEvent(kSwifterKitEventSCSIParallelTask")?.upperBound
    )
    let taskFailure = scsi[enqueueFailure...]
    #expect(taskFailure.contains("CompleteWithDeliveryFailure(this, completion, request);"))
    #expect(scsi.contains(": kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE;"))
    // A task the runtime cannot take is completed, not returned as an error.
    let task = try #require(scsi.range(of: "::UserProcessParallelTask_Impl(")?.lowerBound)
    let taskBody = scsi[task...]
    #expect(!taskBody.contains("return kIOReturnNoSpace;"))
    let full = try #require(taskBody.range(of: "if (pending == nullptr) {")?.upperBound)
    let fullBody = try #require(
      taskBody.range(of: "return kIOReturnSuccess;", range: full..<taskBody.endIndex)
    )
    #expect(
      taskBody[full..<fullBody.lowerBound].contains(
        "CompleteWithDeliveryFailure(this, completion, request);"
      )
    )
    let inProcess = try #require(
      taskBody.range(of: "*response = kSCSIServiceResponse_Request_In_Process;")?.lowerBound
    )
    let version = try #require(
      taskBody.range(of: "request.version != kScsiUserParallelTaskCurrentVersion1")?.lowerBound
    )
    #expect(inProcess < version)

    let project = try String(
      contentsOf: output.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    #expect(project.contains("SCSIControllerDriverKit.framework"))
    #expect(project.contains("SwifterKitRuntimeSCSI.cpp in Sources"))
    #expect(project.contains("SwifterKitRuntimeSCSIControl.cpp in Sources"))

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

    let badConstraints = DriverConfiguration(
      bundleIdentifier: "com.example.scsi",
      providerClass: "IOUserResources",
      capabilities: .scsi,
      scsiController: SCSIControllerConfiguration(
        initiatorIdentifier: 7,
        highestTargetIdentifier: 15,
        constraints: SCSIControllerConstraints(
          maximumSegmentCountRead: 1,
          maximumSegmentCountWrite: 1,
          maximumSegmentByteCountRead: 4_096,
          maximumSegmentByteCountWrite: 4_096,
          minimumHBADataAlignmentMask: 6
        )
      )
    )
    #expect(throws: DriverExtensionGenerationError.invalidSCSIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: badConstraints,
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
      taskManagementResponse: .functionComplete,
      constraints: SCSIControllerConstraints(
        maximumSegmentCountRead: 256,
        maximumSegmentCountWrite: 128,
        maximumSegmentByteCountRead: 65_536,
        maximumSegmentByteCountWrite: 65_536,
        supportsHierarchicalLogicalUnits: true
      ),
      providesTaskDataBuffers: true
    )
  }
}
