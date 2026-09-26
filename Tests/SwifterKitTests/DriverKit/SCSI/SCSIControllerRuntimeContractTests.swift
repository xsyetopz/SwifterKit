import Foundation
import Testing

@testable import SwifterKit

@Suite
struct SCSIControllerRuntimeContractTests {
  @Test
  func routesEveryControllerOpcodeThroughTheSCSIFamily() throws {
    try withGeneratedExtension { output in
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let group = try section(
        of: dispatch,
        from: "case SwifterKitRuntimeOpcode::SCSIPeripheralSendCDB:",
        to: "return DispatchSCSICommand(context);"
      )
      let opcodes = RuntimeOpcode.allCases.filter { (0x0B20...0x0B29).contains($0.rawValue) }
      #expect(opcodes.count == 10)
      for opcode in opcodes {
        let name = String(describing: opcode).dropFirst("scsi".count)
        #expect(group.contains("case SwifterKitRuntimeOpcode::SCSI\(name):"))
      }
      let scsi = try source("SwifterKitRuntimeSCSI.cpp", in: output)
      let command = try section(of: scsi, from: "::SCSICommand(", to: "::StopSCSI(")
      #expect(
        command.contains("return SCSIControlCommand(opcode, payload, payloadLength, response);")
      )
    }
  }

  @Test
  func callsEveryControllerMethodFromItsCommand() throws {
    try withGeneratedExtension { output in
      let control = try source("SwifterKitRuntimeSCSIControl.cpp", in: output)
      for call in [
        "UserTargetPresentForID(target, &present)",
        "UserCreateTargetForID(target, targetProperties)", "UserDestroyTargetForID(target)",
        "UserSetHBAProperties(properties)", "UserSetTargetProperties(target, properties)",
        "UserRemoveHBAProperties(keys)", "UserRemoveTargetProperties(target, keys)",
        "UserCallMediaParametersHaveChanged()",
        "UserGetDataBuffer(request->fTargetID, request->fControllerTaskIdentifier, buffer)",
      ] { #expect(control.contains(call)) }
      // Controller-wide properties reject a target identifier.
      #expect(control.contains("target == 0 ? UserSetHBAProperties(properties)"))
      #expect(control.contains("target == 0 ? UserRemoveHBAProperties(keys)"))
      // Task data is copied under the lock that completions take before releasing the buffer.
      let data = try section(of: control, from: "::SCSITaskData(", to: "#endif")
      let lock = try #require(data.range(of: "IOLockLock(ivars->scsiLock);")?.lowerBound)
      let copy = try #require(data.range(of: "memcpy(bytes + header.offset")?.lowerBound)
      let unlock = try #require(data.range(of: "IOLockUnlock(ivars->scsiLock);")?.lowerBound)
      #expect(lock < copy && copy < unlock)
      #expect(data.contains("header.length > available - header.offset"))
    }
  }

  @Test
  func nativePropertyLimitsAndManagementKindsComeFromTheSchema() throws {
    try withGeneratedExtension { output in
      let header = try source(RuntimeSchemaHeader.fileName, in: output)
      let limits = SCSIControllerLimits.self
      #expect(
        header.contains("kSwifterKitSCSIMaximumPropertyCount = \(limits.maximumPropertyCount);")
      )
      #expect(
        header.contains(
          "kSwifterKitSCSIPropertyKeyMaximumLength = \(limits.maximumPropertyKeyLength);"
        )
      )
      #expect(
        header.contains(
          "kSwifterKitSCSIPropertyValueMaximumLength = \(limits.maximumPropertyValueLength);"
        )
      )
      #expect(header.contains("enum class SwifterKitSCSIManagementKind : uint32_t {"))
      let scsi = try source("SwifterKitRuntimeSCSI.cpp", in: output)
      #expect(scsi.contains("using ManagementKind = SwifterKitSCSIManagementKind;"))
      #expect(scsi.contains("ForwardManagement(this, ManagementKind::TargetReset,"))
    }
  }

  @Test
  func nativeTaskAndPeripheralBoundsComeFromTheSchema() throws {
    try withGeneratedExtension { output in
      let header = try source(RuntimeSchemaHeader.fileName, in: output)
      let scsi = RuntimeSCSILimits.self
      #expect(header.contains("kSwifterKitSCSIMaximumFeatureRequests = 5;"))
      #expect(header.contains("kSwifterKitSCSICommandDescriptorBlockMaximumSize = 16;"))
      #expect(
        header.contains(
          "kSwifterKitSCSIPeripheralMaximumDataLength = \(SCSIPeripheralCommand.maximumDataLength);"
        )
      )
      #expect(scsi.maximumFeatureRequests == 5 && scsi.commandDescriptorBlockMaximumSize == 16)
      let protocolHeader = try source("SwifterKitRuntimeProtocol.h", in: output)
      #expect(protocolHeader.contains("featureRequests[kSwifterKitSCSIMaximumFeatureRequests];"))
      let task = try source("SwifterKitRuntimeSCSI.cpp", in: output)
      #expect(
        task.contains(
          "static_assert(kSwifterKitSCSIMaximumFeatureRequests == "
            + "kSCSIParallelFeature_TotalFeatureCount);"
        )
      )
      #expect(
        task.contains("request.fCommandSize > kSwifterKitSCSICommandDescriptorBlockMaximumSize")
      )
      let peripheral = try source("SwifterKitRuntimeSCSIPeripheral.cpp", in: output)
      #expect(
        peripheral.contains("requestedDataLength > kSwifterKitSCSIPeripheralMaximumDataLength")
      )
    }
  }

  @Test
  func releasesTaskBuffersOnEveryExitAndAnswersBundledTasks() throws {
    try withGeneratedExtension { output in
      let scsi = try source("SwifterKitRuntimeSCSI.cpp", in: output)
      let task = try section(of: scsi, from: "::UserProcessParallelTask_Impl(", to: "::UserGetDMA")
      let fetch = try #require(task.range(of: "SCSIFetchTaskBuffer(&request")?.upperBound)
      let failed = task[fetch...]
      #expect(
        failed.prefix(160).contains("CompleteWithDeliveryFailure(this, completion, request);")
      )
      let full = try section(of: String(task), from: "if (pending == nullptr) {", to: "return")
      #expect(full.contains("OSSafeReleaseNULL(dataBuffer);"))
      let enqueue = try #require(task.range(of: "EnqueueRequiredEvent(")?.upperBound)
      #expect(task[enqueue...].contains("ReleaseTaskBuffer(task);"))
      let complete = try section(of: scsi, from: "::SCSICommand(", to: "::StopSCSI(")
      #expect(complete.contains("ReleaseTaskBuffer(task);"))
      let stop = try section(of: scsi, from: "::StopSCSI(", to: "#endif")
      #expect(stop.contains("ReleaseTaskBuffer(task);"))

      let bundled = try section(
        of: scsi,
        from: "::UserProcessBundledParallelTasks_Impl(",
        to: "::SCSICommand("
      )
      #expect(bundled.contains("requestSlotCount > kMaxBundledParallelTasks"))
      #expect(
        bundled.contains(
          "BundledParallelTaskCompletion(completion, requestSlotIndices, requestSlotCount);"
        )
      )

      let initialize = try section(
        of: scsi,
        from: "::UserInitializeController_Impl(",
        to: "::UserStartController_Impl("
      )
      #expect(initialize.contains("UserReportHBAConstraints(constraints)"))
      let constraints = try section(
        of: scsi,
        from: "OSDictionary* CreateConstraints()",
        to: "}  //"
      )
      for key in [
        "kIOMaximumSegmentCountReadKey", "kIOMaximumSegmentCountWriteKey",
        "kIOMaximumSegmentByteCountReadKey", "kIOMaximumSegmentByteCountWriteKey",
        "kIOMinimumSegmentAlignmentByteCountKey", "kIOMaximumSegmentAddressableBitCountKey",
        "kIOMinimumHBADataAlignmentMaskKey", "kIOHierarchicalLogicalUnitSupportKey",
      ] { #expect(constraints.contains(key)) }
    }
  }

  @Test
  func createsTargetsAwayFromTheUserClientQueue() throws {
    try withGeneratedExtension { output in
      let control = try source("SwifterKitRuntimeSCSIControl.cpp", in: output)
      let create = try section(
        of: control,
        from: "case SwifterKitRuntimeOpcode::SCSICreateTarget:",
        to: "case SwifterKitRuntimeOpcode::SCSIDestroyTarget:"
      )
      let queued = try #require(create.range(of: "scsiTargetQueue->DispatchAsync(^{")?.lowerBound)
      let call = try #require(
        create.range(of: "UserCreateTargetForID(target, targetProperties)")?.lowerBound
      )
      #expect(queued < call)
      #expect(create.contains("targetProperties->release();"))
      #expect(create.contains("retain();") && create.contains("release();"))

      let lifecycle = try source("SwifterKitRuntimeLifecycle.cpp", in: output)
      #expect(lifecycle.contains("IODispatchQueue::Create(\"SwifterKit SCSI Targets\""))
      let service = try source("SwifterKitRuntimeService.cpp", in: output)
      #expect(service.contains("OSSafeReleaseNULL(ivars->scsiTargetQueue);"))
    }
  }

  @Test
  func reportsTheCreateResultAsARequiredEvent() throws {
    try withGeneratedExtension { output in
      let control = try source("SwifterKitRuntimeSCSIControl.cpp", in: output)
      let create = try section(
        of: control,
        from: "case SwifterKitRuntimeOpcode::SCSICreateTarget:",
        to: "case SwifterKitRuntimeOpcode::SCSIDestroyTarget:"
      )
      #expect(!create.contains("(void)UserCreateTargetForID"))
      let call = try #require(
        create.range(of: "UserCreateTargetForID(target, targetProperties)")?.upperBound
      )
      let enqueued = try #require(create.range(of: "EnqueueRequiredEvent(")?.upperBound)
      let type = try #require(create.range(of: "kSwifterKitEventSCSITargetCreated")?.lowerBound)
      #expect(call < enqueued && enqueued <= type)
      let separator = create[enqueued..<type]
      #expect(separator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      #expect(create.contains(".targetIdentifier = target"))
      #expect(create.contains(".status = "))

      let protocolHeader = try source("SwifterKitRuntimeProtocol.h", in: output)
      #expect(
        protocolHeader.contains("struct __attribute__((packed)) SwifterKitSCSITargetCreatedEvent {")
      )
      #expect(
        protocolHeader.contains("static_assert(sizeof(SwifterKitSCSITargetCreatedEvent) == 16);")
      )
    }
  }

  @Test
  func retriesTheCreateResultWhileAHostIsRegistered() throws {
    try withGeneratedExtension { output in
      let control = try source("SwifterKitRuntimeSCSIControl.cpp", in: output)
      let create = try section(
        of: control,
        from: "case SwifterKitRuntimeOpcode::SCSICreateTarget:",
        to: "case SwifterKitRuntimeOpcode::SCSIDestroyTarget:"
      )
      #expect(!create.contains("(void)EnqueueRequiredEvent"))
      let first = try #require(create.range(of: "queued = EnqueueRequiredEvent(")?.upperBound)
      let retry = try #require(
        create.range(of: "queued == kIOReturnNoSpace && HasEventClient(ivars)")?.lowerBound
      )
      let sleep = try #require(create.range(of: "IOSleep(delay);")?.lowerBound)
      let again = try #require(
        create.range(of: "queued = EnqueueRequiredEvent(", range: sleep..<create.endIndex)
      )
      let release = try #require(
        create.range(of: "release();\n", range: again.upperBound..<create.endIndex)
      )
      #expect(first < retry && retry < sleep && again.upperBound < release.lowerBound)
      #expect(create.contains("scsiTargetPresent"))

      let helper = try section(of: control, from: "bool HasEventClient(", to: "return attached;")
      #expect(helper.contains("IOLockLock(state->eventLock);"))
      #expect(helper.contains("state->eventClient != nullptr"))
    }
  }

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    try withTemporaryExtension(
      named: "SCSIControlDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.scsi-control",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: .scsi,
        scsiController: SCSIControllerConfiguration(
          initiatorIdentifier: 7,
          highestTargetIdentifier: 15,
          providesTaskDataBuffers: true
        )
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "24.0")
    ) { output, _ in try body(output) }
  }
}
