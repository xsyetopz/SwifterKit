import Foundation
import Testing

@testable import SwifterKit

/// The generated extension's client-memory wiring: the user client forwards each mapping once,
/// the service validates the type and identifier, subranges and chains retain their sources,
/// and memory- and networking-enabled extensions build.
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
      "return ivars->service->CopyClientMemory(type, options, memory);"
    )
    #expect(copy.components(separatedBy: "return ").count == 3)
  }

  @Test
  func serviceRefusesUnknownTypesMapsRingsAndReservesQueues() throws {
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
      "kern_return_t result = kIOReturnBadArgument;",
      "SwifterKitClientMemoryKind::MemoryBuffer",
      "if (identifier != 0) {",
      "result = CopyMemoryForClient(identifier, memory);",
      "SwifterKitClientMemoryKind::PacketPool",
      "readOnly = true;",
      "result = CopyPacketPoolMemory(identifier, memory);",
      "SwifterKitClientMemoryKind::Ring",
      "result = CopyFastPathRingMemory(identifier, memory);",
      "SwifterKitClientMemoryKind::DataQueue",
      "result = kIOReturnUnsupported;",
      "if (result == kIOReturnSuccess && options != nullptr && readOnly) {",
      "*options |= kIOUserClientMemoryReadOnly;",
      "return result;"
    )
    #expect(!copy.contains("default:"))
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
      #expect(service.contains("kern_return_t CopyMemoryForClient(uint64_t handle,"))
      let memory = try source("SwifterKitRuntimeMemory.cpp", in: output)
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
