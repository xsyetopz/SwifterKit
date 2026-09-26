import Foundation
import Testing

@testable import SwifterKit

/// Checks the native HID runtime's trust-boundary and completion rules in the generated sources.
@Suite
struct HIDRuntimeContractTests {
  @Test
  func nativeLimitsMatchSwiftLimits() throws {
    try withGeneratedExtension { output in
      let limits = try source("SwifterKitRuntimeHIDProtocol.h", in: output)
      #expect(
        limits.contains("kSwifterKitHIDMaximumElementPage = \(HIDLimits.maximumElementPage);")
      )
      #expect(limits.contains("kSwifterKitHIDMaximumCookies = \(HIDLimits.maximumCommitCookies);"))
      #expect(
        limits.contains(
          "kSwifterKitHIDMaximumCollectionElements = \(HIDLimits.maximumCollectionElements);"
        )
      )
      #expect(limits.contains("kSwifterKitHIDMaximumTouches = \(HIDLimits.maximumTouches);"))
      #expect(
        limits.contains("sizeof(SwifterKitHIDElementDescriptor) == \(HIDElement.encodedSize)")
      )
      let sizes = [
        (
          "SwifterKitHIDKeyboardEvent",
          DriverCommand.dispatchHIDKeyboardEvent(usagePage: 1, usage: 1, value: 1).payload.count
        ),
        (
          "SwifterKitHIDPointerEvent",
          try DriverCommand.dispatchHIDScrollEvent(dx: 0, dy: 0).payload.count
        ),
        (
          "SwifterKitHIDStylusEvent",
          try DriverCommand.dispatchHIDStylusEvent(HIDStylus(identifier: 1, x: 0, y: 0, state: []))
            .payload.count
        ),
        (
          "SwifterKitHIDGameControllerEvent",
          try DriverCommand.dispatchHIDGameControllerEvent(HIDGameControllerState()).payload.count
        ),
        (
          "SwifterKitHIDExtendedGameControllerEvent",
          try DriverCommand.dispatchHIDExtendedGameControllerEvent(
            HIDGameControllerState(),
            buttons: HIDGameControllerOptionalButtons()
          ).payload.count
        ),
        (
          "SwifterKitHIDReportRequest",
          try DriverCommand.hidInterfaceReport(type: .input, length: 1).payload.count
        ),
      ]
      for (name, size) in sizes {
        #expect(limits.contains("static_assert(sizeof(\(name)) == \(size));"), "\(name)")
      }
    }
  }

  @Test
  func everyHIDOpcodeReachesTheRuntime() throws {
    try withGeneratedExtension { output in
      let client = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let routed = try section(
        of: client,
        from: "case SwifterKitRuntimeOpcode::HIDCompleteGetReport:",
        to: "return DispatchHIDCommand(context);"
      )
      let names = RuntimeOpcode.allCases.filter { $0.rawValue >= 0x0310 && $0.rawValue < 0x0400 }
      #expect(names.count == 28)
      for opcode in names {
        let native = "HID" + "\(opcode)".dropFirst(3)
        #expect(routed.contains("case SwifterKitRuntimeOpcode::\(native):"), "\(opcode)")
      }
    }
  }

  @Test
  func inputReportsNeedAService() throws {
    try withGeneratedExtension { output in
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let submit = try section(
        of: dispatch,
        from: "kern_return_t DispatchHIDInputReport(",
        to: "kern_return_t HandleCommand("
      )
      // A client whose service is gone passes nullptr, so the check precedes the call.
      let check = try #require(submit.range(of: "context.service == nullptr")?.lowerBound)
      let call = try #require(submit.range(of: "->SubmitHIDInputReport(")?.lowerBound)
      #expect(check < call)
    }
  }

  @Test
  func getReportOwnsCompletionExactlyOnce() throws {
    try withGeneratedExtension { output in
      let requests = try source("SwifterKitRuntimeHIDRequests.cpp", in: output)
      let getReport = try section(of: requests, from: "::getReport(", to: "::AbortHIDRequests(")
      // The request is recorded before it is announced, and a failed announcement takes it back
      // without completing it, so the caller keeps ownership of an error return.
      let record = try #require(getReport.range(of: "slot = {")?.lowerBound)
      let enqueue = try #require(getReport.range(of: "EnqueueRequiredEvent(")?.lowerBound)
      #expect(record < enqueue)
      #expect(getReport.contains("ivars->eventClient != nullptr"))
      #expect(!getReport.contains("CompleteReport("))

      let abort = try section(of: requests, from: "::AbortHIDRequests(", to: "::StopHID(")
      #expect(abort.contains("CompleteReport(taken[index].action, kIOReturnAborted, 0);"))
      let complete = try section(of: requests, from: "::CompleteHIDGetReport(", to: "::HIDCommand(")
      #expect(complete.contains("completion.length > slot.capacity"))
      #expect(complete.contains("completion.reserved != 0"))
      let take = try #require(complete.range(of: "TakeRequests(")?.lowerBound)
      let finish = try #require(complete.range(of: "CompleteReport(")?.lowerBound)
      #expect(take < finish)

      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      #expect(events.contains("AbortHIDRequests();"))
      let service = try source("SwifterKitRuntimeService.cpp", in: output)
      #expect(service.contains("StopHID();"))
    }
  }

  @Test
  func setReportCompletesAcceptedReportsExactlyOnce() throws {
    try withGeneratedExtension { output in
      let hid = try source("SwifterKitRuntimeHID.cpp", in: output)
      let body = try section(of: hid, from: "::setReport(", to: "::handleReport(")
      // Unaccepted report types go to the superclass, which owns their completion.
      #expect(body.contains("return super::setReport("))
      // An accepted report completes once, with success, only after it is queued to Swift.
      let enqueue = try #require(body.range(of: "EnqueueEvent(")?.lowerBound)
      let complete = try #require(
        body.range(of: "CompleteReport(action, kIOReturnSuccess, header.reportLength);")?.lowerBound
      )
      #expect(enqueue < complete)
      #expect(body.contains("if (result == kIOReturnSuccess && action != nullptr) {"))
      #expect(body.components(separatedBy: "CompleteReport(").count == 2)
    }
  }

  @Test
  func elementsAndDispatchRunUnderTheHIDLock() throws {
    try withGeneratedExtension { output in
      let elements = try source("SwifterKitRuntimeHIDElements.cpp", in: output)
      let command = try section(of: elements, from: "::HIDElementCommand(", to: "#endif")
      let lock = try #require(
        command.range(of: "IORecursiveLockLock(ivars->hidLock);\n    const OSArray* elements")?
          .lowerBound
      )
      let access = try #require(command.range(of: "getElements()")?.lowerBound)
      #expect(lock < access)
      #expect(elements.contains("request.maximumCount > kSwifterKitHIDMaximumElementPage"))
      #expect(elements.contains("header.count > kSwifterKitHIDMaximumCookies"))

      let dispatch = try source("SwifterKitRuntimeHIDDispatch.cpp", in: output)
      let body = try section(
        of: dispatch,
        from: "::HIDDispatchCommand(",
        to: "::DispatchHIDDigitizerCollection("
      )
      let locked = try #require(body.range(of: "IORecursiveLockLock(ivars->hidLock);")?.lowerBound)
      let keyboard = try #require(body.range(of: "dispatchKeyboardEvent(")?.lowerBound)
      #expect(locked < keyboard)
      #expect(body.contains("header.count > kSwifterKitHIDMaximumTouches"))
      #expect(dispatch.contains("__builtin_available(driverkit 23.0, *)"))

      let events = try source("SwifterKitRuntimeHIDEvents.cpp", in: output)
      #expect(
        events.contains(
          "processReport(timestamp, report, reportLength, type, reportID, SUPERDISPATCH)"
        )
      )
      #expect(
        events.contains("super::handleReport(timestamp, report, reportLength, type, reportID);")
      )
    }
  }

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("HIDContract", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: HIDEventServiceGeneratorTests.eventConfiguration(
        .eventDriver(categories: .all)
      ),
      options: HIDEventServiceGeneratorTests.options,
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
