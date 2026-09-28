import Foundation
import Testing

@testable import SwifterKit

/// Wrapped host memory belongs to the user client that wrapped it:
/// - Every command and host mapping from another client is refused with kIOReturnNotPermitted.
/// - A subrange or chain of it inherits the owner.
/// - The owner's Stop releases its entries, compositions first.
@Suite
struct ClientMemoryOwnershipContractTests {
  private static func checkedIn(_ name: String) throws -> String {
    try String(contentsOf: checkedInNativeSources.appendingPathComponent(name), encoding: .utf8)
  }

  @Test
  func notOwnerIsKIOReturnNotPermitted() throws {
    #expect(RuntimeMemoryStatus.notOwner.rawValue == 0xE000_02E2)
    let memory = try Self.checkedIn("SwifterKitRuntimeMemory.cpp")
    #expect(
      memory.contains(
        "static_cast<uint32_t>(SwifterKitMemoryStatus::NotOwner)\n    == "
          + "static_cast<uint32_t>(kIOReturnNotPermitted)"
      )
    )
    let state = try Self.checkedIn("SwifterKitRuntimeServiceState.h")
    #expect(state.contains("    const IOService* owner = nullptr;\n"))
  }

  @Test
  func everyCommandAndMappingChecksTheCallingClient() throws {
    let memory = try Self.checkedIn("SwifterKitRuntimeMemory.cpp")
    let command = try section(
      of: memory,
      from: "kern_return_t SwifterKitRuntimeService::MemoryCommand(",
      to: "\n}\n"
    )
    #expect(command.contains("const IOService* client,"))
    // Each handle lookup is followed by the owner check before the entry is used.
    #expect(
      command.components(separatedBy: "FindMemory(ivars,").count
        == command.components(separatedBy: "IsForeign(entry, client)").count
    )
    for (start, end) in [
      ("kern_return_t CreateMemorySubrange(", "kern_return_t CreateMemoryChain("),
      ("kern_return_t CreateMemoryChain(", "}  // namespace"),
    ] {
      let body = try section(of: memory, from: start, to: end)
      try expectOrder(
        in: body,
        "return kIOReturnNotFound;",
        "if (IsForeign(source, client)) {",
        "return kIOReturnNotPermitted;",
        "return FinishComposedEntry("
      )
    }
    // A composition of owned memory takes its owner.
    let finish = try section(
      of: memory,
      from: "kern_return_t FinishComposedEntry(",
      to: "kern_return_t CreateMemorySubrange("
    )
    try expectOrder(in: finish, "entry->owner = owner;", "AssignMemoryHandle(state, entry);")
    let wrap = try section(
      of: memory,
      from: "kern_return_t SwifterKitRuntimeService::WrapClientMemory(",
      to: "kern_return_t SwifterKitRuntimeService::CopyMemoryForClient("
    )
    try expectOrder(in: wrap, "client->CreateMemoryDescriptorFromClient(", "client,\n")
    let copy = try section(
      of: memory,
      from: "kern_return_t SwifterKitRuntimeService::CopyMemoryForClient(",
      to: "\n}\n"
    )
    try expectOrder(
      in: copy,
      "if (entry == nullptr) {",
      "if (IsForeign(entry, client)) {",
      "return kIOReturnNotPermitted;",
      "descriptor->retain();"
    )
    let clients = try Self.checkedIn("SwifterKitRuntimeClients.cpp")
    #expect(clients.contains("return CopyMemoryForClient(client, identifier, memory);"))
    let userClient = try Self.checkedIn("SwifterKitRuntimeUserClient.cpp")
    #expect(
      userClient.contains("return ivars->service->CopyClientMemory(this, type, options, memory);")
    )
  }

  @Test
  func stoppingTheOwnerReleasesItsEntriesCompositionsFirst() throws {
    let memory = try Self.checkedIn("SwifterKitRuntimeMemory.cpp")
    let release = try section(
      of: memory,
      from: "void SwifterKitRuntimeService::ReleaseClientMemory(",
      to: "\n}\n"
    )
    try expectOrder(
      in: release,
      "const MemoryLockGuard guard(ivars->memoryLock);",
      "ReleaseLeavesFirst(ivars, [client](const SwifterKitMemoryEntry& entry) {",
      "return entry.owner == client;"
    )
    let leaves = try section(of: memory, from: "void ReleaseLeavesFirst(", to: "\n    }\n\n")
    try expectOrder(
      in: leaves,
      "for (bool released = true; released;) {",
      "entry.handle != 0 && entry.dependents == 0 && matches(entry)",
      "ReleaseMemoryEntry(state, &entry);"
    )
    // ReleaseMemoryEntry completes a prepared DMA before it drops the descriptor.
    let entry = try section(
      of: memory,
      from: "void ReleaseMemoryEntry(",
      to: "SwifterKitMemoryEntry* FreeMemoryEntry("
    )
    try expectOrder(
      in: entry,
      "entry->dmaCommand->CompleteDMA(0);",
      "OSSafeReleaseNULL(entry->composed);"
    )
    // Stop releases the client's memory before it lets go of the service, on the queue its
    // ExternalMethod runs on. No wrap from this client can then follow the release.
    let client = try Self.checkedIn("SwifterKitRuntimeUserClient.cpp")
    let stop = try section(
      of: client,
      from: "auto SwifterKitRuntimeUserClient::Stop_Impl(",
      to: "auto SwifterKitRuntimeUserClient::ExternalMethod("
    )
    try expectOrder(
      in: stop,
      "ivars->service->ReleaseClientMemory(this);",
      "ivars->service->DetachEventClient(this);",
      "OSSafeReleaseNULL(ivars->service);"
    )
    let clients = try Self.checkedIn("SwifterKitRuntimeClients.cpp")
    let crashed = try section(
      of: clients,
      from: "auto SwifterKitRuntimeService::ClientCrashed_Impl(",
      to: "\n}\n"
    )
    try expectOrder(in: crashed, "ReleaseClientMemory(client);", "DetachEventClient(client);")
  }
}
