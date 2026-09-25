import Foundation
import Testing

@testable import SwifterKit

/// Checks the native USB runtime's trust-boundary rules in the generated sources.
@Suite
struct DriverExtensionUSBContractTests {
  @Test
  func nativeLimitsMatchSwiftLimits() throws {
    try withGeneratedExtension { output in
      let limits = try source("SwifterKitRuntimeUSBProtocol.h", in: output)
      let read = DriverCommand.usbMaximumAsyncReadLength
      let write = DriverCommand.usbMaximumAsyncWriteLength
      let descriptor = DriverCommand.usbMaximumDescriptorLength
      #expect(limits.contains("static_assert(kSwifterKitUSBMaximumAsyncInputLength == \(read));"))
      #expect(limits.contains("static_assert(kSwifterKitUSBMaximumAsyncOutputLength == \(write));"))
      #expect(
        limits.contains("static_assert(kSwifterKitUSBMaximumDescriptorLength == \(descriptor));")
      )
      #expect(limits.contains("kSwifterKitUSBMaximumPendingTransfers = 32;"))
      #expect(
        limits.contains(
          "kSwifterKitUSBMaximumIsochronousFrames = \(DriverCommand.usbMaximumIsochronousFrames);"
        )
      )

      let state = try source("SwifterKitRuntimeServiceState.h", in: output)
      #expect(state.contains("> sizeof(SwifterKitRuntimeService_IVars::usbTransfers)"))
    }
  }

  @Test
  func submissionsValidateLengthsBeforeUse() throws {
    try withGeneratedExtension { output in
      let pipes = try source("SwifterKitRuntimeUSBPipes.cpp", in: output)
      let submit = try section(
        of: pipes,
        from: "::USBPipeCommand(",
        to: "::USBPipeIOComplete_Impl("
      )
      let check = try #require(submit.range(of: "kSwifterKitUSBMaximumAsyncInputLength"))
      let outputCheck = try #require(submit.range(of: "kSwifterKitUSBMaximumAsyncOutputLength"))
      let buffer = try #require(submit.range(of: "SwifterKitCreateUSBBuffer("))
      #expect(check.upperBound < buffer.lowerBound)
      #expect(outputCheck.upperBound < buffer.lowerBound)
      #expect(submit.contains("header->frameCount > kSwifterKitUSBMaximumIsochronousFrames"))
      #expect(submit.contains("eventLength > kSwifterKitUSBMaximumEventPayload"))
      #expect(submit.contains("bytesLength != (input ? 0 : total)"))
      #expect(submit.contains("return kIOReturnNoResources;"))

      let complete = try section(
        of: pipes,
        from: "::USBPipeIOComplete_Impl(",
        to: "::USBPipeIsochIOComplete_Impl("
      )
      #expect(complete.contains("actualByteCount > transfer.length ? transfer.length"))
      #expect(complete.contains("transfer.requestID == reference->requestID"))

      let queue = try section(
        of: pipes,
        from: "kern_return_t QueueCompletion(",
        to: "CreateFrameList("
      )
      #expect(queue.contains("if (frame.completeCount > frame.requestCount) {"))
      #expect(queue.contains("frame.completeCount = frame.requestCount;"))
      #expect(queue.contains("EnqueueRequiredEvent(kSwifterKitEventUSBPipeIO"))
      #expect(queue.contains("EnqueueRequiredEvent(kSwifterKitEventUSBPipeIsochIO"))
      #expect(!pipes.contains("EnqueueEvent("))

      let deliver = try section(
        of: pipes,
        from: "::DeliverUSBCompletions(",
        to: "::ReleaseUSBTransfers("
      )
      #expect(deliver.contains("transfer.sequence < oldest->sequence"))
      #expect(deliver.contains("!= kIOReturnSuccess) {\n            break;"))
    }
  }

  @Test
  func abortsNeverWaitOnTheCompletionQueue() throws {
    try withGeneratedExtension { output in
      for name in [
        "SwifterKitRuntimeUSB.cpp", "SwifterKitRuntimeUSBDevice.cpp",
        "SwifterKitRuntimeUSBPipes.cpp",
      ] {
        let text = try source(name, in: output)
        #expect(!text.contains("kIOUSBAbortSynchronous"), "\(name) aborts synchronously")
      }
      let stop = try section(
        of: try source("SwifterKitRuntimeUSB.cpp", in: output),
        from: "::StopUSB(",
        to: "::USBControlTransfer("
      )
      #expect(stop.contains("Abort(kIOUSBAbortAsynchronous, kIOReturnAborted, nullptr)"))
    }
  }

  @Test
  func descriptorsLargerThanOneResponseAreRefused() throws {
    try withGeneratedExtension { output in
      let device = try source("SwifterKitRuntimeUSBDevice.cpp", in: output)
      let response = try section(
        of: device,
        from: "kern_return_t DescriptorResponse(",
        to: "RespondWithDescriptor("
      )
      #expect(
        response.contains("const bool fits = length <= kSwifterKitUSBMaximumDescriptorLength;")
      )
      #expect(
        response.contains("(fits && length != 0 && !(*response)->appendBytes(bytes, length))")
      )
      #expect(device.contains("request->length > kSwifterKitUSBMaximumDescriptorLength"))
      #expect(device.contains("IOUSBHostFreeDescriptor(descriptor);"))
      #expect(device.contains("count < kSwifterKitUSBMaximumInterfaces"))
    }
  }

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBContractDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.contract-usb",
        providerClass: USBDeviceConfiguration.interfaceProviderClass,
        capabilities: .usb,
        usbDevice: USBDeviceConfiguration(vendorID: 0x1234, interfaceClass: 0xFF)
      ),
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
