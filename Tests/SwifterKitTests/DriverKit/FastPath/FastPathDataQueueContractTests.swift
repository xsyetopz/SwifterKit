import Foundation
import Testing

@testable import SwifterKit

/// The extension's data queue wiring:
/// - Staging sizing and self-check.
/// - Lossy coalesced enqueues, signalled once per run.
/// - A complete drain, under the fast-path lock.
/// - Teardown order.
@Suite
struct FastPathDataQueueContractTests {
  private static func checkedIn(_ name: String) throws -> String {
    try String(contentsOf: checkedInNativeSources.appendingPathComponent(name), encoding: .utf8)
  }

  private static let queues = "SwifterKitRuntimeFastPathDataQueues.cpp"

  @Test
  func stagingIsSizedAndCheckedBeforeItsHandlerIsEnabled() throws {
    let source = try Self.checkedIn(Self.queues)
    let staging = try section(of: source, from: "kern_return_t PrepareStaging(", to: "\n    }\n")
    try expectOrder(
      in: staging,
      "(entries + 1)",
      "IODataQueueDispatchSource::GetDataQueueEntryHeaderSize() + row.maximumEntrySize",
      "IODataQueueDispatchSource::Create(",
      "state->fastPathDataQueueDispatch",
      "CanEnqueueData(row.maximumEntrySize, static_cast<uint32_t>(entries))",
      "return kIOReturnNoResources;",
      "SetDataAvailableHandler(state->fastPathDataAvailableAction)",
      "!IsToHost(row)",
      "SetDataServicedHandler(state->fastPathDataServicedAction)",
      "SwifterKitEnableSource(queue->staging)"
    )
    let start = try section(
      of: source,
      from: "SwifterKitRuntimeService::StartFastPathDataQueues()",
      to: "\n}\n"
    )
    try expectOrder(
      in: start,
      "CopyDispatchQueue(kIOServiceDefaultQueueName",
      "CreateActionFastPathDataAvailable(0,",
      "CreateActionFastPathDataServiced(0,",
      "PrepareHostRing(row, queue)",
      "PrepareStaging(row, ivars, queue)",
      "ReleaseDataQueues(ivars);",
      "return kIOReturnNoResources;"
    )
  }

  @Test
  func enqueueIsLossyAndSignalledOncePerRun() throws {
    let source = try Self.checkedIn(Self.queues)
    let enqueue = try section(
      of: source,
      from: "SwifterKitRuntimeService::EnqueueFastPathData(",
      to: "\n}\n"
    )
    try expectOrder(
      in: enqueue,
      "CanEnqueueData(size) != kIOReturnSuccess",
      "CountDrop(queue);",
      "return;",
      "EnqueueWithCoalesce(size, &sendDataAvailable,",
      "CountDrop(queue);",
      "queue->notify = queue->notify || sendDataAvailable;"
    )
    #expect(!enqueue.contains("SendDataAvailable()"))
    let signal = try section(
      of: source,
      from: "SwifterKitRuntimeService::SignalFastPathDataQueues()",
      to: "\n}\n"
    )
    try expectOrder(in: signal, "queue.notify", "SendDataAvailable();", "queue.notify = false;")
    let runtime = try Self.checkedIn("SwifterKitRuntimeFastPath.cpp")
    let run = try section(
      of: runtime,
      from: "kern_return_t ExecuteHoldingLock(",
      to: "kern_return_t RunPrograms("
    )
    try expectOrder(
      in: run,
      "SwifterKitFastPathExecute(",
      "service->SignalFastPathDataQueues();",
      "IOLockLock(state->fastPathLock);",
      "ExecuteHoldingLock(",
      "IOLockUnlock(state->fastPathLock);"
    )
    #expect(run.components(separatedBy: "SignalFastPathDataQueues").count == 2)
  }

  @Test
  func drainEmptiesEveryStagingQueueUnderTheLock() throws {
    let source = try Self.checkedIn(Self.queues)
    let handler = try section(
      of: source,
      from: "SwifterKitRuntimeService::FastPathDataAvailable_Impl(",
      to: "\n}\n"
    )
    try expectOrder(
      in: handler,
      "IOLockLock(ivars->fastPathLock);",
      "ivars->fastPathRunning",
      "Drain(row, queue)",
      "if (published != 0)",
      "EnqueueEvent(kSwifterKitEventFastPathDataQueue",
      "IOLockUnlock(ivars->fastPathLock);"
    )
    let drain = try section(of: source, from: "uint32_t Drain(", to: "\n    }\n")
    try expectOrder(
      in: drain,
      "while (queue->staging->IsDataAvailable())",
      "queue->staging->Dequeue(^(const void* data, size_t size)",
      "Publish(",
      "CountDrop(",
      "if (result != kIOReturnSuccess)"
    )
    let publish = try section(of: source, from: "bool Publish(", to: "\n    }\n")
    try expectOrder(
      in: publish,
      "__ATOMIC_RELAXED",
      "kSwifterKitFastPathDataQueueConsumerOffset),\n            __ATOMIC_ACQUIRE",
      "producer - consumer >= count || size == 0 || size > row.maximumEntrySize",
      "return false;",
      "producer & (count - 1)",
      "__builtin_memcpy(",
      "producer + 1,\n            __ATOMIC_RELEASE"
    )
  }

  @Test
  func dataQueuesStartAfterRingsAndStopBeforeThem() throws {
    let runtime = try Self.checkedIn("SwifterKitRuntimeFastPath.cpp")
    let start = try section(
      of: runtime,
      from: "void SwifterKitRuntimeService::StartFastPath()",
      to: "\n}\n"
    )
    try expectOrder(
      in: start,
      "PrepareFastPath(ivars);",
      "prepared = StartFastPathDataQueues();",
      "ReleaseRings(ivars);",
      "ivars->fastPathRunning = prepared == kIOReturnSuccess;",
      "RunPrograms(this, ivars, SwifterKitFastPathTriggerKind::Start)"
    )
    let stop = try section(
      of: runtime,
      from: "void SwifterKitRuntimeService::StopFastPath()",
      to: "\n}\n"
    )
    try expectOrder(
      in: stop,
      "RunPrograms(this, ivars, SwifterKitFastPathTriggerKind::Stop)",
      "ivars->fastPathRunning = false;",
      "StopFastPathDataQueues();",
      "ReleaseRings(ivars);"
    )
    let source = try Self.checkedIn(Self.queues)
    let release = try section(of: source, from: "void ReleaseDataQueues(", to: "\n    }\n")
    try expectOrder(
      in: release,
      "queue.staging->Cancel(nullptr);",
      "OSSafeReleaseNULL(queue.staging);",
      "OSSafeReleaseNULL(queue.buffer);",
      "fastPathDataAvailableAction->Cancel(nullptr);",
      "fastPathDataServicedAction->Cancel(nullptr);",
      "OSSafeReleaseNULL(state->fastPathDataServicedAction);"
    )
  }

  @Test
  func hostMappingAnswersOnceUnderTheLock() throws {
    let source = try Self.checkedIn(Self.queues)
    let copy = try section(
      of: source,
      from: "SwifterKitRuntimeService::CopyFastPathDataQueueMemory(",
      to: "\n}\n"
    )
    try expectOrder(
      in: copy,
      "IOLockLock(ivars->fastPathLock);",
      "result = kIOReturnBadArgument;",
      "result = kIOReturnNotReady;",
      "buffer->retain();",
      "IOLockUnlock(ivars->fastPathLock);",
      "return result;"
    )
    #expect(copy.components(separatedBy: "return ").count == 3)
  }
}
