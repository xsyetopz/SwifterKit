import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverExtensionRuntimeContractTests {
  private static let bundleIdentifier = "com.example.contract-block"

  @Test
  func nonAudioRuntimeRequiresClientEntitlement() throws {
    try withGeneratedExtension { output in
      let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
      let encoded = DriverExtensionGenerator.cString(Self.bundleIdentifier)
      #expect(header.contains("SWIFTERKIT_ENABLE_AUDIO 0"))
      #expect(header.contains("kSwifterKitBundleIdentifier[] =\n    \(encoded);"))
      #expect(!header.contains("kSwifterKitBundleIdentifier[] = \"\""))

      let userClient = try source("SwifterKitRuntimeUserClient.cpp", in: output)
      let start = try #require(
        userClient.range(of: "SwifterKitRuntimeUserClient::Start_Impl(")?.upperBound
      )
      let copy = try #require(
        userClient.range(of: "CopyClientEntitlements(", range: start..<userClient.endIndex)?
          .lowerBound
      )
      let key = try #require(
        userClient.range(
          of: "\"com.apple.developer.driverkit.userclient-access\"",
          range: copy..<userClient.endIndex
        )?.lowerBound
      )
      let match = try #require(
        userClient.range(
          of: "isEqualTo(kSwifterKitBundleIdentifier)",
          range: key..<userClient.endIndex
        )?.lowerBound
      )
      let rejection = try #require(
        userClient.range(of: "return kIOReturnNotPermitted;", range: match..<userClient.endIndex)?
          .lowerBound
      )
      let binding = try #require(
        userClient.range(of: "ivars->service =", range: start..<userClient.endIndex)?.lowerBound
      )
      #expect(!userClient[start..<copy].contains("#if"))
      #expect(userClient[start..<copy].contains("Start(provider, SUPERDISPATCH)"))
      #expect(userClient[match..<rejection].contains("Stop(provider, SUPERDISPATCH)"))
      #expect(rejection < binding)
      #expect(userClient.contains("identifier->getLength() != 0"))

      let entitlements = try loadPropertyList(
        at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
      )
      #expect(entitlements["com.apple.developer.driverkit.allow-any-userclient-access"] == nil)
    }
  }

  @Test
  func eventProducersCheckTheEventQueueBound() throws {
    try withGeneratedExtension { output in
      let checks = [
        (
          "SwifterKitRuntimeHID.cpp",
          "length64 > kSwifterKitMaximumEventPayloadLength - sizeof(SwifterKitHIDReportHeader)"
        ),
        (
          "SwifterKitRuntimeMIDI.cpp",
          "(kSwifterKitMaximumEventPayloadLength - sizeof(SwifterKitMIDIEventHeader))"
        ),
        (
          "SwifterKitRuntimeBlockStorage.cpp",
          "payloadLength > kSwifterKitMaximumEventPayloadLength"
        ),
      ]
      for (name, check) in checks {
        let text = try source(name, in: output)
        #expect(text.contains(check), "\(name)")
        #expect(!text.contains("kSwifterKitRuntimeMaximumMessageSize"), "\(name)")
      }
    }
  }

  @Test
  func requiredEventsHaveReservedCapacityAndPollFirst() throws {
    try withGeneratedExtension { output in
      let state = try source("SwifterKitRuntimeServiceState.h", in: output)
      #expect(state.contains("kSwifterKitMaximumQueuedLossyEvents = 64;"))
      #expect(state.contains("kSwifterKitMaximumQueuedRequiredEvents = 512;"))
      #expect(state.contains("OSArray* requiredEvents = nullptr;"))
      #expect(state.contains("uint64_t lossyEventDrops = 0;"))

      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let copy = try #require(events.range(of: "::CopyNextEvent(")?.upperBound)
      let required = try #require(
        events.range(of: "TakeFirst(ivars->requiredEvents)", range: copy..<events.endIndex)?
          .lowerBound
      )
      let lossy = try #require(
        events.range(of: "TakeFirst(ivars->events)", range: copy..<events.endIndex)?.lowerBound
      )
      #expect(required < lossy)
      let protocolHeader = try source("SwifterKitRuntimeProtocol.h", in: output)
      #expect(
        protocolHeader.contains(
          "kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize - sizeof(uint32_t);"
        )
      )
      #expect(events.contains("payloadLength > kSwifterKitMaximumEventPayloadLength"))

      let lossyEnqueue = try section(
        of: events,
        from: "::EnqueueEvent(",
        to: "::EnqueueRequiredEvent("
      )
      #expect(lossyEnqueue.contains("ivars->events,"))
      #expect(lossyEnqueue.contains("kSwifterKitMaximumQueuedLossyEvents"))
      #expect(lossyEnqueue.contains("ivars->lossyEventDrops += 1;"))
      let requiredEnqueue = try #require(
        events.range(of: "::EnqueueRequiredEvent(").map { events[$0.lowerBound...] }
      )
      #expect(requiredEnqueue.contains("ivars->requiredEvents,"))
      #expect(requiredEnqueue.contains("kSwifterKitMaximumQueuedRequiredEvents"))
      #expect(!requiredEnqueue.contains("ivars->events"))

      let lifecycle = try source("SwifterKitRuntimeLifecycle.cpp", in: output)
      #expect(lifecycle.contains("OSArray::withCapacity(kSwifterKitMaximumQueuedRequiredEvents)"))
    }
  }

  @Test
  func blockStorageAnswersRequestsItCannotQueue() throws {
    try withGeneratedExtension { output in
      let block = try source("SwifterKitRuntimeBlockStorage.cpp", in: output)
      let queue = try section(
        of: block,
        from: "kern_return_t QueueRequest(",
        to: "CopyDeviceString("
      )
      let enqueue = try #require(queue.range(of: "EnqueueRequiredEvent(")?.upperBound)
      let tail = queue[enqueue...]
      #expect(tail.contains("if (RemovePendingRequest(state, requestID))"))
      #expect(tail.contains("(void)RejectRequest(service, requestID, isIO, result);"))
      #expect(!tail.contains("return result;"))
      let reject = try section(
        of: block,
        from: "kern_return_t RejectRequest(",
        to: "kern_return_t QueueRequest("
      )
      #expect(reject.contains("service->CompleteIO(requestID, 0, status);"))
      #expect(reject.contains("service->Complete(requestID, status);"))
      #expect(reject.contains("return kIOReturnSuccess;"))
    }
  }

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("ContractDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: DriverConfiguration(
        bundleIdentifier: Self.bundleIdentifier,
        providerClass: "IOPCIDevice",
        capabilities: [.blockStorage, .pci],
        pciDevice: PCIDeviceConfiguration(vendorID: 0x1234, deviceIDs: [0x5678]),
        blockStorageDevice: BlockStorageDeviceConfiguration(
          blockCount: 1_048_576,
          blockSize: 4_096,
          maximumIOSize: 1_048_576,
          vendor: "Example",
          product: "Contract Storage",
          revision: "1.0"
        )
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
      at: output
    )
    try body(output)
  }

  private func source(_ name: String, in output: URL) throws -> String {
    try String(
      contentsOf: output.appendingPathComponent("Sources").appendingPathComponent(name),
      encoding: .utf8
    )
  }

  private func section(of text: String, from start: String, to end: String) throws -> Substring {
    let lower = try #require(text.range(of: start)?.lowerBound)
    let upper = try #require(text.range(of: end, range: lower..<text.endIndex)?.lowerBound)
    return text[lower..<upper]
  }
}
