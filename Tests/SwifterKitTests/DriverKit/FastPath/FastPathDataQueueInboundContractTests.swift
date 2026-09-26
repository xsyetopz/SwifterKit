import Foundation
import Testing

@testable import SwifterKit

/// The extension's to-extension data queue wiring: bounds checks before any host-written byte is
/// read, a doorbell answered once, DataServiced only after a coalesced dequeue, and resumption
/// under the fast-path lock.
@Suite
struct FastPathDataQueueInboundContractTests {
  private static func checkedIn(_ name: String) throws -> String {
    try String(contentsOf: checkedInNativeSources.appendingPathComponent(name), encoding: .utf8)
  }

  private static let queues = "SwifterKitRuntimeFastPathDataQueues.cpp"
  private static let transfer = "SwifterKitRuntimeFastPathDataQueueTransfer.h"

  @Test
  func boundsChecksPrecedeEveryHostRecordRead() throws {
    let source = try Self.checkedIn(Self.transfer)
    let take = try section(of: source, from: "SwifterKitFastPathTakeHostRecords(", to: "\n}\n")
    try expectOrder(
      in: take,
      "SwifterKitFastPathDataQueueEntryCount(row)",
      "SwifterKitFastPathDataQueueStride(row)",
      "__ATOMIC_ACQUIRE",
      "producer - consumer > count",
      "transfer.corrupt = true;",
      "consumer & (count - 1)",
      "size == 0 || size > row.maximumEntrySize || reserved != 0",
      "transfer.corrupt = true;",
      "staging.Enqueue(",
      "consumer += 1;",
      "SwifterKitMappedPointer<uint32_t>(consumerField),\n"
        + "            consumer,\n            __ATOMIC_RELEASE);"
    )
    // The header's geometry is host-writable, so it never addresses a record.
    #expect(!source.contains("kSwifterKitFastPathDataQueueEntryCountOffset"))
    #expect(!source.contains("kSwifterKitFastPathDataQueueStrideOffset"))
    #expect(take.components(separatedBy: "SwifterKitMappedPointer<uint32_t>(record)").count == 2)
  }

  @Test
  func sendDataServicedFollowsOnlyACoalescedDequeue() throws {
    let source = try Self.checkedIn(Self.transfer)
    let consume = try section(of: source, from: "bool SwifterKitFastPathConsumeEntry(", to: "\n}\n")
    try expectOrder(
      in: consume,
      "staging.Peek(words)",
      "run(",
      "bool sendDataServiced = false;",
      "staging.DequeueWithCoalesce(&sendDataServiced)",
      "if (sendDataServiced)",
      "staging.SendDataServiced();"
    )
    let native = try Self.checkedIn(Self.queues)
    let staging = try section(of: native, from: "struct Staging {", to: "\n    };\n")
    try expectOrder(
      in: staging,
      "source->Enqueue(size,",
      "kIOReturnOverrun ? SwifterKitFastPathStagingResult::Full",
      "source->Peek(",
      "SwifterKitFastPathEntryWords(data, size, words);",
      "source->DequeueWithCoalesce(",
      "source->SendDataServiced();"
    )
    #expect(native.components(separatedBy: "SendDataServiced();").count == 2)
  }

  @Test
  func doorbellIsAnsweredOnceUnderTheLock() throws {
    let native = try Self.checkedIn(Self.queues)
    let notify = try section(
      of: native,
      from: "SwifterKitRuntimeService::NotifyFastPathDataQueue(",
      to: "\n}\n"
    )
    try expectOrder(
      in: notify,
      "payloadLength != sizeof(request)",
      "request.reserved != 0",
      "IOLockLock(ivars->fastPathLock);",
      "QueueIndex(request.id)",
      "IsToHost(QueueRow(index))",
      "result = kIOReturnBadArgument;",
      "result = kIOReturnNotReady;",
      "Take(QueueRow(index), queue)",
      "SwifterKitFastPathStatus::Corrupt",
      "IOLockUnlock(ivars->fastPathLock);",
      "*response = OSData::withBytes(&reply, sizeof(reply));"
    )
    #expect(notify.components(separatedBy: "*response = ").count == 2)
    let take = try section(of: native, from: "SwifterKitFastPathTransfer Take(", to: "\n    }\n")
    try expectOrder(
      in: take,
      "SwifterKitFastPathTakeHostRecords(row, queue->address, staging)",
      "queue->blocked = transfer.blocked;",
      "queue->refusals += 1;"
    )
    let runtime = try Self.checkedIn("SwifterKitRuntimeFastPath.cpp")
    #expect(
      runtime.contains(
        "case SwifterKitRuntimeOpcode::FastPathDataQueueNotify:\n"
          + "            return NotifyFastPathDataQueue(payload, payloadLength, response);"
      )
    )
    let dispatch = try Self.checkedIn("SwifterKitRuntimeCommandDispatch.cpp")
    try expectOrder(
      in: dispatch[...],
      "case SwifterKitRuntimeOpcode::FastPathDataQueueNotify:",
      "return DispatchFastPathCommand(context);"
    )
  }

  @Test
  func consumerHoldsTheLockForOneEntryAndResumesBlockedQueues() throws {
    let native = try Self.checkedIn(Self.queues)
    let consume = try section(of: native, from: "void Consume(", to: "\n    }\n}")
    try expectOrder(
      in: consume,
      "while (consumed)",
      "IOLockLock(state->fastPathLock);",
      "state->fastPathRunning && queue->staging != nullptr",
      "SwifterKitFastPathConsumeEntry(staging,",
      "service->RunFastPathDataAvailable(index, words)",
      "CountDrop(queue);",
      "IOLockUnlock(state->fastPathLock);"
    )
    let available = try section(
      of: native,
      from: "SwifterKitRuntimeService::FastPathDataAvailable_Impl(",
      to: "\n}\n"
    )
    try expectOrder(
      in: available,
      "IOLockUnlock(ivars->fastPathLock);",
      "Consume(this, ivars, index);"
    )
    let serviced = try section(
      of: native,
      from: "SwifterKitRuntimeService::FastPathDataServiced_Impl(",
      to: "\n}\n"
    )
    try expectOrder(
      in: serviced,
      "IOLockLock(ivars->fastPathLock);",
      "ivars->fastPathRunning",
      "!queue->blocked",
      "Take(row, queue)",
      "transfer.moved != 0",
      "EnqueueEvent(kSwifterKitEventFastPathDataQueue",
      "IOLockUnlock(ivars->fastPathLock);"
    )
    let runtime = try Self.checkedIn("SwifterKitRuntimeFastPath.cpp")
    let run = try section(
      of: runtime,
      from: "bool SwifterKitRuntimeService::RunFastPathDataAvailable(",
      to: "\n}\n"
    )
    try expectOrder(
      in: run,
      "SwifterKitFastPathTriggerKind::DataAvailable",
      "ExecuteHoldingLock(",
      "kTables.programs[program].argumentCount"
    )
    #expect(!run.contains("IOLockLock"))
  }
}
