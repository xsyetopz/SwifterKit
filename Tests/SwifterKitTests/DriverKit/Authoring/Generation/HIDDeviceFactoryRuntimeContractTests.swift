import Foundation
import Testing

@testable import SwifterKit

/// Checks the HID device factory's trust-boundary, lifetime, and completion rules in the
/// generated native sources.
@Suite
struct HIDDeviceFactoryRuntimeContractTests {
  private func withFactoryExtension(_ body: (URL) throws -> Void) throws {
    try withTemporaryExtension(
      named: "HIDFactory",
      configuration: HIDDeviceFactoryGeneratorTests.factoryConfiguration()
    ) { output, _ in try body(output) }
  }

  @Test
  func everyFactoryOpcodeRoutesWithTheCallingClient() throws {
    try withFactoryExtension { output in
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let routed = try section(
        of: dispatch,
        from: "case SwifterKitRuntimeOpcode::HIDFactoryCreateDevice:",
        to: "return DispatchHIDFactoryCommand(context);"
      )
      let names = RuntimeOpcode.allCases.filter { $0.rawValue >= 0x0340 && $0.rawValue < 0x0350 }
      #expect(names.count == 5)
      for opcode in names {
        let native = "HID" + "\(opcode)".dropFirst(3)
        #expect(routed.contains("case SwifterKitRuntimeOpcode::\(native):"), "\(opcode)")
      }
      let handler = try section(
        of: dispatch,
        from: "kern_return_t DispatchHIDFactoryCommand(",
        to: "return RespondToCommand("
      )
      try expectOrder(in: handler, "HIDFactoryCommand(", "context.client,")
    }
  }

  @Test
  func onlyTheEventClientCommandsTheFactory() throws {
    try withFactoryExtension { output in
      let factory = try source("SwifterKitRuntimeHIDFactory.cpp", in: output)
      let command = try section(
        of: factory,
        from: "kern_return_t SwifterKitRuntimeService::HIDFactoryCommand(",
        to: "device->release();"
      )
      try expectOrder(
        in: command,
        "IOLockLock(ivars->eventLock);",
        "IOLockUnlock(ivars->eventLock);",
        "if (eventClient == nullptr) {",
        "return kIOReturnNotReady;",
        "if (client != eventClient) {",
        "return kIOReturnNotPermitted;",
        "return CreateDevice(this, ivars, payload, payloadLength, response);",
        "ReadHandle(payload, payloadLength, &handle)"
      )
    }
  }

  @Test
  func rootTerminatesDevicesOutsideItsLock() throws {
    try withFactoryExtension { output in
      let factory = try source("SwifterKitRuntimeHIDFactory.cpp", in: output)
      #expect(
        factory.contains(
          "kSwifterKitMaximumQueuedRequiredEvents\n    > kSwifterKitHIDMaximumDevices "
            + "* (kSwifterKitHIDFactoryMaximumPendingReports + 1)"
        )
      )
      let abort = try section(
        of: factory,
        from: "void SwifterKitRuntimeService::AbortHIDRequests() {",
        to: "void SwifterKitRuntimeService::StopHID() {"
      )
      try expectOrder(
        in: abort,
        "IORecursiveLockLock(ivars->hidLock);",
        "ClearSlot(",
        "IORecursiveLockUnlock(ivars->hidLock);",
        "TerminateDevice(device);"
      )
      let stop = try section(
        of: factory,
        from: "void SwifterKitRuntimeService::StopHID() {",
        to: "kern_return_t SwifterKitRuntimeService::HIDFactoryAttachDevice("
      )
      try expectOrder(in: stop, "ivars->hidDevicesStopped = true;", "AbortHIDRequests();")
      let stopped = try section(
        of: factory,
        from: "void SwifterKitRuntimeService::HIDFactoryDeviceStopped(",
        to: "kern_return_t CreateDevice("
      )
      try expectOrder(
        in: stopped,
        "IORecursiveLockUnlock(ivars->hidLock);",
        "EnqueueRequiredEvent(kSwifterKitEventHIDFactoryDeviceTerminated"
      )
    }
  }

  @Test
  func deviceCompletesEachHostRequestOnce() throws {
    try withFactoryExtension { output in
      let device = try source("SwifterKitRuntimeHIDDevice.cpp", in: output)
      let getReport = try section(
        of: device,
        from: "kern_return_t SwifterKitRuntimeHIDDevice::getReport(",
        to: "kern_return_t SwifterKitRuntimeHIDDevice::CompleteGetReport("
      )
      #expect(!getReport.contains("CompleteReport("))
      try expectOrder(
        in: getReport,
        "IOLockLock(ivars->lock);",
        "slot = {",
        "IOLockUnlock(ivars->lock);",
        "ivars->root->EnqueueRequiredEvent(",
        "kSwifterKitEventHIDFactoryGetReportRequest",
        "SwifterKitHIDTakeRequests(ivars->requests, event.request.requestID, taken);"
      )
      let setReport = try section(
        of: device,
        from: "kern_return_t SwifterKitRuntimeHIDDevice::setReport(",
        to: "kern_return_t SwifterKitRuntimeHIDDevice::getReport("
      )
      try expectOrder(
        in: setReport,
        "ivars->root->EnqueueEvent(",
        "kSwifterKitEventHIDFactoryReport",
        "if (result == kIOReturnSuccess && action != nullptr) {",
        "CompleteReport(action, kIOReturnSuccess, header.reportLength);"
      )
      let abort = try section(
        of: device,
        from: "void SwifterKitRuntimeHIDDevice::AbortRequests() {",
        to: "\n}\n"
      )
      #expect(abort.contains("CompleteReport(taken[index].action, kIOReturnAborted, 0);"))
      let stop = try section(
        of: device,
        from: "auto SwifterKitRuntimeHIDDevice::Stop_Impl(",
        to: "return Stop(provider, SUPERDISPATCH);"
      )
      try expectOrder(
        in: stop,
        "ivars->stopped = true;",
        "AbortRequests();",
        "ivars->root->HIDFactoryDeviceStopped(ivars->handle);"
      )
    }
  }
}
