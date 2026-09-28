import Foundation
import Testing

@testable import SwifterKit

@Suite
struct ServiceDispatchContractTests {
  @Test
  func nativeLimitsMatchSwift() throws {
    try withGeneratedExtension { output in
      let layouts = try source("SwifterKitRuntimeDispatchProtocol.h", in: output)
      #expect(layouts.contains("#include \"SwifterKitRuntimeSchema.h\""))
      let header = try source(RuntimeSchemaHeader.fileName, in: output)
      #expect(header.contains("kSwifterKitMaximumTimers = \(ServiceTimerLimits.maximumTimers);"))
      let minimum = ServiceTimerLimits.minimumIntervalNanoseconds
      let maximum = ServiceTimerLimits.maximumNanoseconds
      #expect(header.contains("kSwifterKitTimerMinimumIntervalNanoseconds = \(minimum)ULL;"))
      #expect(header.contains("kSwifterKitTimerMaximumNanoseconds = \(maximum)ULL;"))
      #expect(
        header.contains("kSwifterKitMaximumServiceWatches = \(ServiceWatchLimits.maximumWatches);")
      )
      #expect(
        header.contains(
          "kSwifterKitMaximumWatchedStateItems = \(ServiceWatchLimits.maximumStateItems);"
        )
      )
      for kind in [ServiceMatchNotification.Kind.terminated, .matched] {
        let name = String(describing: kind)
        #expect(
          header.contains("\(name.prefix(1).uppercased() + name.dropFirst()) = \(kind.rawValue),")
        )
      }
      for size in [
        "SwifterKitTimerStart) == 24", "SwifterKitDispatchIdentifier) == 8",
        "SwifterKitTimerEvent) == 24", "SwifterKitServiceWatchEvent) == 32",
        "SwifterKitSystemStateEvent) == 16",
      ] { #expect(layouts.contains("static_assert(sizeof(\(size));")) }
    }
  }

  @Test
  func everyDispatchOpcodeRoutesWithoutACapability() throws {
    try withGeneratedExtension { output in
      let userClient = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let group = try section(
        of: userClient,
        from: "case SwifterKitRuntimeOpcode::ServiceSetProperties:",
        to: "return DispatchServiceCommand(context);"
      )
      let control = try source("SwifterKitRuntimeServiceControl.cpp", in: output)
      let opcodes = RuntimeOpcode.allCases.filter { $0.rawValue & 0xFF00 == 0x0E00 }
      #expect(opcodes.count == 7)
      for opcode in opcodes {
        let name = String(describing: opcode)
        let native =
          "case SwifterKitRuntimeOpcode::\(name.prefix(1).uppercased() + name.dropFirst()):"
        #expect(group.contains(native))
        #expect(control.contains(native))
      }
      #expect(!group.contains("#if"))
      #expect(control.contains("return TimerCommand(opcode, payload, payloadLength, response);"))
      #expect(control.contains("return WatchCommand(opcode, payload, payloadLength, response);"))
    }
  }

  @Test
  func serviceDeclaresDispatchHandlers() throws {
    try withGeneratedExtension { output in
      let service = try source("SwifterKitRuntimeService.iig", in: output)
      #expect(service.contains("#include <DriverKit/IOServiceNotificationDispatchSource.iig>"))
      #expect(service.contains("#include <DriverKit/IOServiceStateNotificationDispatchSource.iig>"))
      #expect(service.contains("TYPE(IOTimerDispatchSource::TimerOccurred);"))
      #expect(
        service.contains("TYPE(IOServiceNotificationDispatchSource::ServiceNotificationReady);")
      )
      #expect(
        service.contains("TYPE(IOServiceStateNotificationDispatchSource::StateNotificationReady);")
      )
      for method in ["TimerCommand(", "WatchCommand(", "StopTimers()", "StopWatches()"] {
        #expect(service.contains(method))
      }
    }
  }

  @Test
  func timersValidateAndIdentifyEveryFiring() throws {
    try withGeneratedExtension { output in
      let timers = try source("SwifterKitRuntimeTimers.cpp", in: output)
      #expect(timers.contains("request.delay <= kSwifterKitTimerMaximumNanoseconds"))
      #expect(timers.contains("request.leeway <= kSwifterKitTimerMaximumNanoseconds"))
      #expect(timers.contains("request.interval >= kSwifterKitTimerMinimumIntervalNanoseconds"))
      #expect(timers.contains("payloadLength != sizeof(request)"))
      #expect(timers.contains("result = kIOReturnNoResources;"))
      // The action carries the timer ID, and a firing for a freed slot is dropped.
      #expect(timers.contains("SwifterKitSetActionIdentifier(action, timerID);"))
      // The slot takes its own references before it becomes visible to cancel and stop.
      let timerRetain = try #require(timers.range(of: "source->retain();")?.lowerBound)
      let timerStore = try #require(timers.range(of: ".timerID = timerID,")?.lowerBound)
      #expect(timerRetain < timerStore)
      #expect(timers.contains("SwifterKitTimerSlot* slot = FindTimer(ivars, timerID);"))
      // Missed periods are skipped rather than delivered as a burst.
      #expect(timers.contains("((now - slot->deadline) / slot->interval + 1) * slot->interval"))
      #expect(timers.contains("EnqueueEvent(kSwifterKitEventTimer, &event, sizeof(event));"))
      #expect(timers.contains("WakeAtTime(kIOTimerClockUptimeRaw, deadline, request.leeway)"))

      let sources = try source("SwifterKitRuntimeDispatchSources.h", in: output)
      #expect(sources.contains("SwifterKitEnableSource(IODispatchSource* source)"))
      // TimerCommand hands its creation references to this helper on failure. Without
      // os_consumed, the static analyzer reports them as leaked.
      #expect(sources.contains("IODispatchSource* __attribute__((os_consumed)) source,"))
      #expect(sources.contains("OSAction* __attribute__((os_consumed)) action) {"))
      #expect(sources.contains("return words[1] == 0 ? words[0] : 0;"))
    }
  }

  @Test
  func watchesValidateAndReportWhatADextMayObserve() throws {
    try withGeneratedExtension { output in
      let watches = try source("SwifterKitRuntimeServiceWatches.cpp", in: output)
      let watchRetain = try #require(watches.range(of: "watch.source->retain();")?.lowerBound)
      let watchStore = try #require(watches.range(of: "slot = watch;")?.lowerBound)
      #expect(watchRetain < watchStore)
      #expect(watches.contains("(*matching)->getObject(kIOProviderClassKey)"))
      #expect(watches.contains("(*items)->getCount() <= kSwifterKitMaximumWatchedStateItems"))
      #expect(watches.contains("SwifterKitIsPropertyName("))
      #expect(watches.contains("IOServiceNotificationDispatchSource::Create(matching, 0, queue"))
      #expect(watches.contains("CopySystemStateNotificationService(&watch.stateService)"))
      #expect(watches.contains("source->DeliverNotifications(^("))
      #expect(watches.contains("service->GetRegistryEntryID(&registryEntryID)"))
      // The source re-arms before its items are read.
      let begin = try #require(watches.range(of: "source->StateNotificationBegin()")?.lowerBound)
      let copy = try #require(watches.range(of: "->StateNotificationItemCopy(name")?.lowerBound)
      #expect(begin < copy)
      #expect(
        watches.contains(
          "SwifterKitEncodeProperty(value, event, kSwifterKitMaximumEventPayloadLength)"
        )
      )
      // The shared protocol bound is the only copy, so the limits cannot drift.
      #expect(!watches.contains("kMaximumEventPayloadLength ="))
    }
  }

  @Test
  func hostDepartureAndStopCancelTimersAndWatches() throws {
    try withGeneratedExtension { output in
      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let detach = try section(
        of: events,
        from: "void SwifterKitRuntimeService::DetachEventClient",
        to: "auto SwifterKitRuntimeService::CopyNextEvent"
      )
      let unlock = try #require(
        detach.range(of: "IOLockUnlock(ivars->eventLock);\n    detached")?.lowerBound
      )
      let stop = try #require(detach.range(of: "StopTimers();")?.lowerBound)
      #expect(unlock < stop)
      #expect(detach.contains("StopWatches();"))

      let service = try source("SwifterKitRuntimeService.cpp", in: output)
      let stopImpl = try section(
        of: service,
        from: "auto SwifterKitRuntimeService::Stop_Impl",
        to: "return Stop(provider, SUPERDISPATCH);"
      )
      #expect(stopImpl.contains("StopTimers();") && stopImpl.contains("StopWatches();"))
      let lifecycle = try source("SwifterKitRuntimeLifecycle.cpp", in: output)
      #expect(lifecycle.contains("ivars->dispatchLock = IOLockAlloc();"))
    }
  }

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    try withTemporaryExtension(
      named: "DispatchDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.contract-dispatch",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: []
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0")
    ) { output, _ in try body(output) }
  }
}
