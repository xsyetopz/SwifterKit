import Foundation
import Testing

@testable import SwifterKit

/// The generated extension's client-memory wiring: the user client forwards each mapping once,
/// the service validates the type and identifier, subranges and chains retain their sources and
/// keep them from being released, and memory- and networking-enabled extensions build.
@Suite
struct ClientMemoryRuntimeContractTests {
  private static func checkedIn(_ name: String) throws -> String {
    try String(contentsOf: checkedInNativeSources.appendingPathComponent(name), encoding: .utf8)
  }

  @Test
  func userClientForwardsEachMappingOnceAfterStartAdmittedTheHost() throws {
    let header = try Self.checkedIn("SwifterKitRuntimeUserClient.iig")
    #expect(header.contains("virtual kern_return_t CopyClientMemoryForType("))
    let client = try Self.checkedIn("SwifterKitRuntimeUserClient.cpp")
    let start = try section(
      of: client,
      from: "auto SwifterKitRuntimeUserClient::Start_Impl(",
      to: "auto SwifterKitRuntimeUserClient::Stop_Impl("
    )
    // The service is attached only after the entitlement check admits the host.
    try expectOrder(
      in: start,
      "CopyClientEntitlements(&entitlements)",
      "return kIOReturnNotPermitted;",
      "ivars->service = OSDynamicCast(SwifterKitRuntimeService, provider);"
    )
    let copy = try section(
      of: client,
      from: "auto SwifterKitRuntimeUserClient::CopyClientMemoryForType_Impl(",
      to: "\n}\n"
    )
    try expectOrder(
      in: copy,
      "if (ivars == nullptr || ivars->service == nullptr) {",
      "return kIOReturnNotReady;",
      "return ivars->service->CopyClientMemory(this, type, options, memory);"
    )
    #expect(copy.components(separatedBy: "return ").count == 3)
  }

  @Test
  func serviceRefusesUnknownTypesAndMapsRingsAndDataQueues() throws {
    let clients = try Self.checkedIn("SwifterKitRuntimeClients.cpp")
    let copy = try section(
      of: clients,
      from: "auto SwifterKitRuntimeService::CopyClientMemory(",
      to: "\n}\n"
    )
    try expectOrder(
      in: copy,
      "*memory = nullptr;",
      "if (type > UINT32_MAX) {",
      "return kIOReturnBadArgument;",
      ">> kSwifterKitClientMemoryKindShift;",
      "& kSwifterKitClientMemoryIdentifierMask;",
      "const kern_return_t result = [&]() -> kern_return_t {",
      "SwifterKitClientMemoryKind::MemoryBuffer",
      "if (identifier != 0) {",
      "return CopyMemoryForClient(client, identifier, memory);",
      "SwifterKitClientMemoryKind::PacketPool",
      "return CopyPacketPoolMemory(identifier, memory);",
      "SwifterKitClientMemoryKind::Ring",
      "return CopyFastPathRingMemory(identifier, memory);",
      "SwifterKitClientMemoryKind::DataQueue",
      "return CopyFastPathDataQueueMemory(identifier, memory);",
      "return kIOReturnBadArgument;\n    }();",
      "const bool readOnly =",
      "kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::PacketPool);",
      "if (result == kIOReturnSuccess && options != nullptr && readOnly) {",
      "*options |= kIOUserClientMemoryReadOnly;",
      "return result;"
    )
    #expect(!copy.contains("default:"))
  }

  @Test
  func releaseRefusesUsedSourcesAndStopReleasesCompositionsFirst() throws {
    let memory = try Self.checkedIn("SwifterKitRuntimeMemory.cpp")
    #expect(
      memory.contains(
        "static_cast<uint32_t>(SwifterKitMemoryStatus::InUse) == "
          + "static_cast<uint32_t>(kIOReturnBusy)"
      )
    )
    // A composition counts once per source it retains, and releasing it undoes exactly that.
    let finish = try section(
      of: memory,
      from: "kern_return_t FinishComposedEntry(",
      to: "kern_return_t CreateMemorySubrange("
    )
    try expectOrder(
      in: finish,
      "if (!entry->sources->setObject(sources[index])) {",
      "} else if (SwifterKitMemoryEntry* source =",
      "FindMemoryByDescriptor(state, sources[index]);",
      "++source->dependents;",
      "AssignMemoryHandle(state, entry);"
    )
    let release = try section(
      of: memory,
      from: "void ReleaseMemoryEntry(",
      to: "SwifterKitMemoryEntry* FreeMemoryEntry("
    )
    try expectOrder(
      in: release,
      "entry->sources->getCount()",
      "FindMemoryByDescriptor(state, entry->sources->getObject(index));",
      "if (source != nullptr && source->dependents != 0) {",
      "--source->dependents;",
      "OSSafeReleaseNULL(entry->sources);"
    )
    let command = try section(
      of: memory,
      from: "case SwifterKitRuntimeOpcode::MemoryRelease:",
      to: "case SwifterKitRuntimeOpcode::MemorySetLength:"
    )
    try expectOrder(
      in: command,
      "return kIOReturnNotFound;",
      "if (entry->dependents != 0) {",
      "return kIOReturnBusy;",
      "ReleaseMemoryEntry(ivars, entry);"
    )
    // Teardown releases leaves pass by pass, then sweeps every slot regardless of dependents.
    let stop = try section(
      of: memory,
      from: "void SwifterKitRuntimeService::StopMemory() {",
      to: "\n}\n"
    )
    try expectOrder(
      in: stop,
      "const MemoryLockGuard guard(ivars->memoryLock);",
      "ReleaseLeavesFirst(ivars, [](const SwifterKitMemoryEntry&) { return true; });",
      "OSSafeReleaseNULL(ivars->memoryProvider);"
    )
    let leaves = try section(of: memory, from: "void ReleaseLeavesFirst(", to: "\n    }\n\n")
    try expectOrder(
      in: leaves,
      "for (bool released = true; released;) {",
      "if (entry.handle != 0 && entry.dependents == 0 && matches(entry)) {",
      "ReleaseMemoryEntry(state, &entry);",
      "released = true;",
      "for (auto& entry : state->memoryEntries) {",
      "if (matches(entry)) {",
      "ReleaseMemoryEntry(state, &entry);"
    )
    // Detaching events takes no memory lock under eventLock; the user client's Stop releases
    // the host's wrapped memory first, as ClientMemoryOwnershipContractTests checks.
    let events = try Self.checkedIn("SwifterKitRuntimeEvents.cpp")
    let detach = try section(
      of: events,
      from: "void SwifterKitRuntimeService::DetachEventClient(",
      to: "auto SwifterKitRuntimeService::CopyNextEvent("
    )
    #expect(!detach.contains("StopMemory") && !detach.contains("ReleaseMemory"))
    let state = try Self.checkedIn("SwifterKitRuntimeServiceState.h")
    #expect(state.contains("    uint32_t dependents = 0;\n"))
  }

  @Test
  func memoryExtensionMapsRetainsAndComposesDescriptors() throws {
    try withTemporaryExtension(
      named: "ClientMemoryDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.client-memory",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: .memory,
        memoryPool: MemoryPoolConfiguration(maximumBuffers: 8)
      )
    ) { output, root in
      let service = try source("SwifterKitRuntimeService.iig", in: output)
      #expect(service.contains("kern_return_t CopyClientMemory("))
      #expect(service.contains("kern_return_t CopyMemoryForClient(\n        IOService* client,"))
      #expect(service.contains("kern_return_t WrapClientMemory(\n        IOUserClient* client,"))
      let memory = try source("SwifterKitRuntimeMemory.cpp", in: output)
      // The wrap checks every segment before it takes the lock, describes the calling client's
      // memory, and stores it without a byte-budget charge or retained sources.
      let wrap = try section(
        of: memory,
        from: "kern_return_t SwifterKitRuntimeService::WrapClientMemory(",
        to: "kern_return_t SwifterKitRuntimeService::CopyMemoryForClient("
      )
      try expectOrder(
        in: wrap,
        "header.count > kSwifterKitMemoryMaximumClientSegments",
        "payloadLength != sizeof(header) + header.count * sizeof(IOAddressSegment)",
        "segment.length == 0 || segment.address > UINT64_MAX - segment.length",
        "const MemoryLockGuard guard(ivars->memoryLock);",
        "FreeMemoryEntry(ivars);",
        "client->CreateMemoryDescriptorFromClient(",
        "&entry->composed);",
        "return FinishComposedEntry("
      )
      #expect(!wrap.contains("allocatedMemory"))
      let messages = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      #expect(messages.contains("context.service->WrapClientMemory(\n"))
      #expect(
        messages.contains("return HandleCommand(client, service, arguments, request, payload);")
      )
      let client = try source("SwifterKitRuntimeUserClient.cpp", in: output)
      #expect(client.contains("return SwifterKitHandleMessage(\n        this,"))
      let copy = try section(
        of: memory,
        from: "kern_return_t SwifterKitRuntimeService::CopyMemoryForClient(",
        to: "kern_return_t SwifterKitRuntimeService::StartMemory("
      )
      try expectOrder(
        in: copy,
        "const MemoryLockGuard guard(ivars->memoryLock);",
        "if (entry == nullptr) {",
        "return kIOReturnBadArgument;",
        "descriptor->retain();",
        "*memory = descriptor;"
      )
      let release = try section(
        of: memory,
        from: "void ReleaseMemoryEntry(",
        to: "SwifterKitMemoryEntry* FreeMemoryEntry("
      )
      try expectOrder(
        in: release,
        "entry->handle != 0 && entry->descriptor != nullptr;",
        "OSSafeReleaseNULL(entry->composed);",
        "OSSafeReleaseNULL(entry->sources);"
      )
      let finish = try section(
        of: memory,
        from: "kern_return_t FinishComposedEntry(",
        to: "kern_return_t CreateMemorySubrange("
      )
      try expectOrder(
        in: finish,
        "entry->sources = OSArray::withCapacity(sourceCount);",
        "entry->sources->setObject(sources[index])",
        "ReleaseMemoryEntry(state, entry);",
        "AssignMemoryHandle(state, entry);",
        "result = AppendResponse(response, &entry->handle, sizeof(entry->handle));",
        "ReleaseMemoryEntry(state, entry);",
        "return result;"
      )
      for (start, end, call) in [
        (
          "kern_return_t CreateMemorySubrange(", "kern_return_t CreateMemoryChain(",
          "IOMemoryDescriptor::CreateSubMemoryDescriptor("
        ),
        (
          "kern_return_t CreateMemoryChain(", "}  // namespace",
          "IOMemoryDescriptor::CreateWithMemoryDescriptors("
        ),
      ] {
        let body = try section(of: memory, from: start, to: end)
        try expectOrder(
          in: body,
          "return kIOReturnBadArgument;",
          "return kIOReturnNotFound;",
          "DirectionIsWithin(header->direction, source)",
          "SwifterKitMemoryEntry* entry = FreeMemoryEntry(state);",
          "return kIOReturnNoResources;",
          "if (__builtin_available(driverkit 20.0, *)) {",
          call,
          "return FinishComposedEntry("
        )
      }
      let chain = try section(
        of: memory,
        from: "kern_return_t CreateMemoryChain(",
        to: "}  // namespace"
      )
      #expect(chain.contains("count == 0 || count > kSwifterKitMemoryMaximumChainLength"))
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      try expectOrder(
        in: dispatch[...],
        "case SwifterKitRuntimeOpcode::MemorySubrange:",
        "case SwifterKitRuntimeOpcode::MemoryChain:",
        "return DispatchMemoryCommand(context);"
      )
      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }

  @Test
  func networkingExtensionCopiesPoolMemoryOutsideTheLock() throws {
    try withTemporaryExtension(
      named: "PacketPoolDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.packet-pool",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: .networking,
        ethernetDevice: EthernetDeviceConfiguration(
          hardwareAddress: EthernetAddress(2, 3, 4, 5, 6, 7),
          receivePacketCount: 64
        )
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "22.0")
    ) { output, root in
      let service = try source("SwifterKitRuntimeService.iig", in: output)
      #expect(service.contains("kern_return_t CopyPacketPoolMemory(uint32_t pool,"))
      let setup = try source("SwifterKitRuntimeNetworkSetup.cpp", in: output)
      let copy = try section(
        of: setup,
        from: "kern_return_t SwifterKitRuntimeService::CopyPacketPoolMemory(",
        to: "\n}\n"
      )
      try expectOrder(
        in: copy,
        "return kIOReturnBadArgument;",
        "IOLockLock(ivars->networkLock);",
        "SwifterKitPacketPool::Transmit) ? ivars->networkPool",
        ": ivars->networkRxPool;",
        "if (ivars->networkStopping || source == nullptr) {",
        "IOLockUnlock(ivars->networkLock);",
        "return kIOReturnNotReady;",
        "source->retain();",
        "IOLockUnlock(ivars->networkLock);",
        "source->CopyMemoryDescriptor(memory);",
        "source->release();",
        "return result;"
      )
      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }
}
