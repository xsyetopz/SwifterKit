import Foundation

extension DriverExtensionGenerator {
  static func scsiConfigurationDeclarations(_ configuration: DriverConfiguration) -> String {
    let scsi = configuration.scsiController
    let peripheral = configuration.scsiPeripheral
    return """
      static constexpr uint64_t kSwifterKitSCSIInitiatorIdentifier =
          \(scsi?.initiatorIdentifier ?? 0);
      static constexpr uint64_t kSwifterKitSCSIHighestTargetIdentifier =
          \(scsi?.highestTargetIdentifier ?? 0);
      static constexpr uint64_t kSwifterKitSCSIHighestLogicalUnitNumber =
          \(scsi?.highestLogicalUnitNumber ?? 0);
      static constexpr uint32_t kSwifterKitSCSIMaximumTaskCount =
          \(scsi?.maximumTaskCount ?? 0);
      static constexpr uint64_t kSwifterKitSCSIMaximumTransferSize =
          \(scsi?.maximumTransferSize ?? 0);
      static constexpr uint32_t kSwifterKitSCSIMinimumSegmentAlignment =
          \(scsi?.minimumSegmentAlignment ?? 0);
      static constexpr uint8_t kSwifterKitSCSIAddressBitCount =
          \(scsi?.addressBitCount ?? 0);
      static constexpr uint16_t kSwifterKitSCSIDMASegmentType =
          \(scsi?.dmaSegmentType.rawValue ?? 0);
      static constexpr uint32_t kSwifterKitSCSISupportedFeatures =
          \(scsi?.supportedFeatures.rawValue ?? 0);
      static constexpr bool kSwifterKitSCSIPerformsAutoSense =
          \(scsi?.performsAutoSense == true ? "true" : "false");
      static constexpr bool kSwifterKitSCSISupportsMultipathing =
          \(scsi?.supportsMultipathing == true ? "true" : "false");
      static constexpr uint32_t kSwifterKitSCSITaskManagementResponse =
          \(scsi?.taskManagementResponse.rawValue ?? 5);
      static constexpr bool kSwifterKitSCSIPeripheralInitializationSucceeds =
          \(peripheral?.initializationSucceeds == true ? "true" : "false");
      """
  }

  static func scsiServiceMethods(enabled: Bool) -> String {
    guard enabled else { return "" }
    return """
          void StopSCSI() LOCALONLY;
          kern_return_t SCSICommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength) LOCALONLY;

      protected:
          virtual kern_return_t UserReportHBAHighestLogicalUnitNumber(
              uint64_t* value) override;
          virtual kern_return_t UserDoesHBASupportSCSIParallelFeature(
              uint32_t feature,
              bool* result) override;
          virtual kern_return_t UserInitializeTargetForID(
              SCSITargetIdentifier targetID) override;
          virtual kern_return_t UserDoesHBAPerformAutoSense(bool* result) override;
          virtual kern_return_t UserDoesHBASupportMultiPathing(bool* result) override;
          virtual kern_return_t UserAbortTaskRequest(
              uint64_t target,
              uint64_t logicalUnit,
              uint64_t taskTag,
              uint32_t* response) override;
          virtual kern_return_t UserAbortTaskSetRequest(
              uint64_t target,
              uint64_t logicalUnit,
              uint32_t* response) override;
          virtual kern_return_t UserClearACARequest(
              uint64_t target,
              uint64_t logicalUnit,
              uint32_t* response) override;
          virtual kern_return_t UserClearTaskSetRequest(
              uint64_t target,
              uint64_t logicalUnit,
              uint32_t* response) override;
          virtual kern_return_t UserLogicalUnitResetRequest(
              uint64_t target,
              uint64_t logicalUnit,
              uint32_t* response) override;
          virtual kern_return_t UserTargetResetRequest(
              uint64_t target,
              uint32_t* response) override;
          virtual kern_return_t UserReportInitiatorIdentifier(uint64_t* identifier) override;
          virtual kern_return_t UserReportHighestSupportedDeviceID(
              uint64_t* identifier) override;
          virtual kern_return_t UserReportMaximumTaskCount(uint32_t* count) override;
          virtual kern_return_t UserDoesHBAPerformDeviceManagement(bool* result) override;
          virtual kern_return_t UserInitializeController() override;
          virtual kern_return_t UserStartController() override;
          virtual kern_return_t UserProcessParallelTask(
              SCSIUserParallelTask request,
              uint32_t* response,
              OSAction* completion
                  TYPE(IOUserSCSIParallelInterfaceController::ParallelTaskCompletion)) override;
          virtual kern_return_t UserGetDMASpecification(
              uint64_t* maximumTransferSize,
              uint32_t* alignment,
              uint8_t* addressBitCount,
              DMAOutputSegmentType* segmentType) override;
          virtual kern_return_t UserMapHBAData(uint32_t* uniqueTaskID) override;
          virtual kern_return_t UserMapBundledParallelTaskCommandAndResponseBuffers(
              IOBufferMemoryDescriptor* commandBuffer,
              IOBufferMemoryDescriptor* responseBuffer) override;
          virtual void UserProcessBundledParallelTasks(
              const uint16_t requestSlotIndices[kMaxBundledParallelTasks],
              uint16_t requestSlotCount,
              OSAction* completion
                  TYPE(IOUserSCSIParallelInterfaceController::BundledParallelTaskCompletion))
              override;
      """
  }
  static func scsiPeripheralSuperclass(_ configuration: SCSIPeripheralConfiguration?) -> String? {
    guard let type = configuration?.deviceType else { return nil }
    switch type {
    case .blockCommands: return "IOUserSCSIPeripheralDeviceType00"
    case .multimediaCommands: return "IOUserSCSIPeripheralDeviceType05"
    case .opticalMemory: return "IOUserSCSIPeripheralDeviceType07"
    }
  }

  static func scsiPeripheralSuperclassInclude(_ configuration: SCSIPeripheralConfiguration?)
    -> String?
  {
    guard let type = configuration?.deviceType else { return nil }
    let suffix = String(format: "%02d", type.rawValue)
    return "#include <SCSIPeripheralsDriverKit/IOUserSCSIPeripheralDeviceType\(suffix).iig>"
  }

  static func scsiPeripheralServiceMethods(_ configuration: SCSIPeripheralConfiguration?) -> String
  {
    guard let type = configuration?.deviceType else { return "" }
    let initialization =
      type == .multimediaCommands
      ? "UserInitializeDeviceSupport" : "UserDetermineDeviceCharacteristics"
    return """
          kern_return_t SCSIPeripheralCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;

      protected:
          virtual kern_return_t \(initialization)(bool* result) override;
      """
  }

}
