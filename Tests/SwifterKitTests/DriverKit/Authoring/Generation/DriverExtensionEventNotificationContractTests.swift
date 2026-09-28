import Foundation
import Testing

@testable import SwifterKit

/// Source-level checks of the extension's event-notification contract. The generated-extension
/// build tests compile this code per family. No test here runs it.
@Suite
struct DriverExtensionEventNotificationContractTests {
  @Test
  func pollArmsAndEnqueueNotifiesOnceOutsideTheLock() throws {
    try withGeneratedExtension { output in
      let state = try source("SwifterKitRuntimeServiceState.h", in: output)
      #expect(state.contains("SwifterKitRuntimeUserClient* eventClient = nullptr;"))
      #expect(state.contains("bool eventNotificationArmed = false;"))

      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let take = try section(
        of: events,
        from: "TakeNotificationTarget(",
        to: "void SendNotification("
      )
      let check = try #require(take.range(of: "!state->eventNotificationArmed")?.lowerBound)
      let disarm = try #require(
        take.range(of: "state->eventNotificationArmed = false;")?.lowerBound
      )
      #expect(check < disarm)

      let enqueue = try section(
        of: events,
        from: "kern_return_t EnqueueInto(",
        to: "OSData* TakeFirst("
      )
      try expectOrder(
        in: enqueue,
        "IOLockLock(state->eventLock);",
        "queue->setObject(event)",
        "added ? TakeNotificationTarget(state) : nullptr",
        "IOLockUnlock(state->eventLock);",
        "SendNotification(target);"
      )

      let poll = try section(of: events, from: "::CopyNextEvent(", to: "::EnqueueEvent(")
      try expectOrder(
        in: poll,
        "IOLockLock(ivars->eventLock);",
        "TakeFirst(ivars->events)",
        "if (*event == nullptr) {\n        ivars->eventNotificationArmed = true;",
        "IOLockUnlock(ivars->eventLock);"
      )

      let attach = try section(of: events, from: "::AttachEventClient(", to: "::DetachEventClient(")
      try expectOrder(
        in: attach,
        "IOLockLock(ivars->eventLock);",
        "ivars->eventNotificationArmed = true;",
        "pending ? TakeNotificationTarget(ivars) : nullptr",
        "IOLockUnlock(ivars->eventLock);",
        "SendNotification(target);"
      )

      let userClient = try source("SwifterKitRuntimeUserClient.cpp", in: output)
      let notify = try section(of: userClient, from: "::NotifyEventsPending()", to: "::Start_Impl(")
      try expectOrder(
        in: notify,
        "IOLockLock(ivars->actionLock);",
        "IOLockUnlock(ivars->actionLock);",
        "AsyncCompletion(action, kIOReturnSuccess, noArguments, 0);"
      )
      #expect(events.contains("A poll that finds both\n//   queues empty arms it."))
    }
  }

  @Test
  func registrationUsesTheSchemaSelectorAndRetainsTheCompletion() throws {
    try withGeneratedExtension { output in
      let schema = try source("SwifterKitRuntimeSchema.h", in: output)
      #expect(schema.contains("kSwifterKitSelectorTransact = 0;"))
      #expect(schema.contains("kSwifterKitSelectorEventNotification = 1;"))

      let userClient = try source("SwifterKitRuntimeUserClient.cpp", in: output)
      let method = try section(
        of: userClient,
        from: "::ExternalMethod(",
        to: "const size_t inputLength"
      )
      try expectOrder(
        in: method,
        "selector == kSwifterKitSelectorEventNotification",
        "RegisterEventNotification(this, ivars, arguments)",
        "selector != kSwifterKitSelectorTransact"
      )
      let register = try section(
        of: userClient,
        from: "kern_return_t RegisterEventNotification(",
        to: "}  // namespace"
      )
      try expectOrder(
        in: register,
        "arguments->completion == nullptr",
        "ReplaceEventAction(state, arguments->completion);",
        "AttachEventClient(client);",
        "ReplaceEventAction(state, nullptr);"
      )
      let helpers = try source("SwifterKitRuntimeUserClientHelpers.h", in: output)
      #expect(!helpers.contains("kTransactSelector"))
    }
  }

  @Test
  func hostDepartureEmptiesQueuesThenAnswersTrackedRequests() throws {
    try withGeneratedExtension { output in
      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let detach = try #require(
        events.range(of: "::DetachEventClient(").map { events[$0.lowerBound...] }
      )
      try expectOrder(
        in: detach,
        "IOLockLock(ivars->eventLock);",
        "client != nullptr && client != detached",
        "ivars->requiredEvents->flushCollection();",
        "ivars->events->flushCollection();",
        "IOLockUnlock(ivars->eventLock);",
        "detached->release();",
        "#if SWIFTERKIT_ENABLE_BLOCK_STORAGE\n    StopBlockStorage();",
        "#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER\n    StopSCSI();",
        "#if SWIFTERKIT_ENABLE_NETWORKING\n    AbortNetworkTransmits();"
      )
      let userClient = try source("SwifterKitRuntimeUserClient.cpp", in: output)
      let stop = try section(of: userClient, from: "::Stop_Impl(", to: "::ExternalMethod(")
      try expectOrder(
        in: stop,
        "ivars->service->DetachEventClient(this);",
        "ReplaceEventAction(ivars, nullptr);",
        "OSSafeReleaseNULL(ivars->service);",
        "Stop(provider, SUPERDISPATCH)"
      )

      let service = try source("SwifterKitRuntimeService.cpp", in: output)
      let serviceStop = try section(
        of: service,
        from: "::Stop_Impl(",
        to: "#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER"
      )
      #expect(serviceStop.contains("DetachEventClient(nullptr);"))
      #expect(service.contains("OSSafeReleaseNULL(ivars->eventClient);"))

      let clients = try source("SwifterKitRuntimeClients.cpp", in: output)
      let crashed = try #require(
        clients.range(of: "::ClientCrashed_Impl(").map { clients[$0.lowerBound...] }
      )
      try expectOrder(
        in: crashed,
        "DetachEventClient(client);",
        "ClientCrashed(client, options, SUPERDISPATCH)"
      )

      let block = try source("SwifterKitRuntimeBlockStorage.cpp", in: output)
      let stopBlock = try section(
        of: block,
        from: "::StopBlockStorage()",
        to: "::BlockStorageCommand("
      )
      #expect(stopBlock.contains("CompleteIO(pending.requestID, 0, kIOReturnAborted);"))
      #expect(stopBlock.contains("Complete(pending.requestID, kIOReturnAborted);"))

      let network = try source("SwifterKitRuntimeNetworkSetup.cpp", in: output)
      let abort = try section(of: network, from: "::AbortNetworkTransmits()", to: "::StopNetwork()")
      try expectOrder(
        in: abort,
        "IOLockLock(ivars->networkLock);",
        "ReturnPendingTransmits(ivars);",
        "IOLockUnlock(ivars->networkLock);"
      )
      #expect(!abort.contains("setEnable(false)"))
    }
  }

  @Test
  func replacingTheClientAnswersRequestsThePreviousClientTook() throws {
    try withGeneratedExtension { output in
      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let attach = try section(of: events, from: "::AttachEventClient(", to: "::DetachEventClient(")
      try expectOrder(
        in: attach,
        "IOLockLock(ivars->eventLock);",
        "while (ivars->eventClient != nullptr && ivars->eventClient != userClient) {",
        "IOLockUnlock(ivars->eventLock);",
        "DetachEventClient(replaced);",
        "IOLockLock(ivars->eventLock);",
        "const SwifterKitRuntimeUserClient* previous = ivars->eventClient;",
        "ivars->eventClient = userClient;",
        "IOLockUnlock(ivars->eventLock);",
        "OSSafeReleaseNULL(previous);",
        "SendNotification(target);"
      )
      #expect(!attach.contains("StopBlockStorage"))
      #expect(!attach.contains("flushCollection"))
      #expect(events.contains("A registration from a different user client first detaches"))
    }
  }

  @Test
  func pollThatTakesARequiredEventRetriesUSBCompletionsOutsideTheLock() throws {
    try withGeneratedExtension { output in
      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let poll = try section(of: events, from: "::CopyNextEvent(", to: "::EnqueueEvent(")
      try expectOrder(
        in: poll,
        "IOLockLock(ivars->eventLock);",
        "*event = TakeFirst(ivars->requiredEvents);",
        "const bool tookRequired = *event != nullptr;",
        "IOLockUnlock(ivars->eventLock);",
        "#if SWIFTERKIT_ENABLE_USB",
        "if (tookRequired) {\n        DeliverUSBCompletions();",
        "#endif",
        "return kIOReturnSuccess;"
      )
      #expect(poll.components(separatedBy: "DeliverUSBCompletions();").count == 2)
    }
  }

  @Test
  func serviceInterfacesDeclareTheNotificationMethods() throws {
    let declarations = [
      "virtual kern_return_t ClientCrashed(IOService* client, uint64_t options) override;",
      "kern_return_t AttachEventClient(IOService* client) LOCALONLY;",
      "void DetachEventClient(IOService* client) LOCALONLY;",
    ]
    let checkedIn = try String(
      contentsOf: checkedInNativeSources.appendingPathComponent("SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    let userClient = try String(
      contentsOf: checkedInNativeSources.appendingPathComponent("SwifterKitRuntimeUserClient.iig"),
      encoding: .utf8
    )
    #expect(userClient.contains("void NotifyEventsPending() LOCALONLY;"))

    let networking = DriverExtensionGenerator.serviceInterface(
      DriverConfiguration(
        bundleIdentifier: "com.example.contract-network",
        providerClass: "IOUserResources",
        capabilities: .networking,
        ethernetDevice: EthernetDeviceConfiguration(
          hardwareAddress: EthernetAddress(2, 3, 4, 5, 6, 7)
        )
      )
    )
    let scsi = DriverExtensionGenerator.serviceInterface(
      DriverConfiguration(
        bundleIdentifier: "com.example.contract-scsi",
        providerClass: "IOPCIDevice",
        capabilities: [.scsi, .pci],
        pciDevice: PCIDeviceConfiguration(vendorID: 0x1234, deviceIDs: [0x5678]),
        scsiController: SCSIControllerConfiguration(
          initiatorIdentifier: 7,
          highestTargetIdentifier: 15
        )
      )
    )
    for declaration in declarations {
      #expect(checkedIn.contains(declaration))
      #expect(networking.contains(declaration))
      #expect(scsi.contains(declaration))
    }
    #expect(networking.contains("void AbortNetworkTransmits() LOCALONLY;"))
    #expect(scsi.contains("void StopSCSI() LOCALONLY;"))
  }

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    try withTemporaryExtension(
      named: "NotificationDriver",
      configuration: DriverExtensionRuntimeContractTests.configuration(
        bundleIdentifier: "com.example.contract-notification"
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0")
    ) { output, _ in try body(output) }
  }
}
