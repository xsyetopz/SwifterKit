import Foundation
import Testing

@testable import SwifterKit

/// Checks the native asynchronous-control, bundled-I/O, endpoint-policy, and USB serial rules in
/// the generated sources.
@Suite
struct USBAsyncRuntimeContractTests {
  @Test
  func nativeLimitsMatchSwiftLimits() throws {
    try withGeneratedExtension { output in
      let limits = try source("SwifterKitRuntimeUSBProtocol.h", in: output)
      let read = DriverCommand.usbMaximumAsyncControlReadLength
      let buffer = DriverCommand.usbMaximumBundleBufferLength
      #expect(
        limits.contains("static_assert(kSwifterKitUSBMaximumAsyncRequestInputLength == \(read));")
      )
      #expect(
        limits.contains("static_assert(kSwifterKitUSBMaximumBundleBufferLength == \(buffer));")
      )
      let schema = try source(RuntimeSchemaHeader.fileName, in: output)
      #expect(
        schema.contains(
          "kSwifterKitUSBMaximumBundleRingEntries = \(DriverCommand.usbMaximumBundleRingEntries);"
        )
      )
      #expect(
        schema.contains(
          "kSwifterKitUSBMaximumBundleRingBytes = \(DriverCommand.usbMaximumBundleRingBytes);"
        )
      )
      #expect(
        schema.contains(
          "kSwifterKitUSBMaximumBundledTransfers = \(DriverCommand.usbMaximumBundledTransfers);"
        )
      )
      #expect(limits.contains("static_assert(sizeof(SwifterKitUSBAdjustPipeRequest) == 28);"))
      let state = try source("SwifterKitRuntimeServiceState.h", in: output)
      #expect(
        state.contains(
          "+ kSwifterKitUSBMaximumBundleRings * kSwifterKitUSBMaximumBundleRingEntries"
        )
      )
    }
  }

  @Test
  func everyNewOpcodeReachesTheRuntime() throws {
    try withGeneratedExtension { output in
      let client = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      for opcode in RuntimeOpcode.allCases where (0x0240..<0x0300).contains(opcode.rawValue) {
        let native = "USB" + "\(opcode)".dropFirst(3)
        #expect(client.contains("case SwifterKitRuntimeOpcode::\(native):"), "\(opcode)")
      }
      let device = try source("SwifterKitRuntimeUSBDevice.cpp", in: output)
      let async = try #require(device.range(of: "return USBAsyncCommand(")?.lowerBound)
      let pipe = try #require(device.range(of: "return USBPipeCommand(")?.lowerBound)
      // Device providers accept asynchronous control requests, so they route before pipe opcodes.
      #expect(async < pipe)
    }
  }

  @Test
  func asynchronousControlRequestsOwnOneSlotUntilDelivered() throws {
    try withGeneratedExtension { output in
      let requests = try source("SwifterKitRuntimeUSBRequests.cpp", in: output)
      let submit = try section(
        of: requests,
        from: "::USBAsyncCommand(",
        to: "::USBDeviceRequestComplete_Impl("
      )
      let check = try #require(submit.range(of: "kSwifterKitUSBMaximumAsyncRequestInputLength"))
      let buffer = try #require(submit.range(of: "SwifterKitCreateUSBBuffer("))
      #expect(check.upperBound < buffer.lowerBound)
      #expect(submit.contains("return kIOReturnNoResources;"))
      #expect(submit.contains("SwifterKitReleaseUSBTransfer(ivars->usbTransfers[slot]);"))
      let complete = try section(
        of: requests,
        from: "::USBDeviceRequestComplete_Impl(",
        to: "::AbortUSBAsyncRequests("
      )
      #expect(complete.contains("transfer.requestID == reference->requestID"))
      #expect(complete.contains("bytesTransferred > transfer.length ? transfer.length"))
      let abort = try section(of: requests, from: "::AbortUSBAsyncRequests(", to: "#endif")
      #expect(abort.contains("AbortDeviceRequests(kIOUSBAbortAsynchronous, kIOReturnAborted)"))
      #expect(!abort.contains("kIOUSBAbortSynchronous"))
      let pipes = try source("SwifterKitRuntimeUSBPipes.cpp", in: output)
      #expect(pipes.contains("kSwifterKitEventUSBDeviceRequest,"))
      let adjust = try section(
        of: requests,
        from: "AdjustPipe(IOUSBHostInterface* interface",
        to: "}  // namespace"
      )
      #expect(adjust.contains("kIOUSBGetEndpointDescriptorOriginal"))
      #expect(
        adjust.contains(
          "type != kIOUSBEndpointTypeIsochronous && type != kIOUSBEndpointTypeInterrupt"
        )
      )
    }
  }

  @Test
  func bundledEntriesAreBoundedAndRolledBack() throws {
    try withGeneratedExtension { output in
      let bundled = try source("SwifterKitRuntimeUSBBundled.cpp", in: output)
      #expect(bundled.contains("!= kIOUSBEndpointTypeBulk"))
      #expect(bundled.contains("return kIOReturnExclusiveAccess;"))
      let enqueue = try section(
        of: bundled,
        from: "::USBBundleCommand(",
        to: "::USBPipeBundledIOComplete_Impl("
      )
      let mark = try #require(
        enqueue.range(of: "SwifterKitUSBBundleEntryState::InFlight;")?.lowerBound
      )
      let submit = try #require(enqueue.range(of: "AsyncIOBundled(")?.lowerBound)
      #expect(mark < submit)
      #expect(enqueue.contains("for (uint32_t index = accepted; index < count; ++index)"))
      #expect(enqueue.contains("count > kSwifterKitUSBMaximumBundledTransfers"))
      let complete = try section(
        of: bundled,
        from: "::USBPipeBundledIOComplete_Impl(",
        to: "::DeliverUSBBundledCompletions("
      )
      #expect(complete.contains("ioCompletionCount > kIOUSBHostPipeBundlingMax"))
      #expect(complete.contains("ioCompletionIndex < ring.entryCount"))
      #expect(complete.contains("ring.generation == reference->generation"))
      let deliver = try section(
        of: bundled,
        from: "::DeliverUSBBundledCompletions(",
        to: "::ReleaseUSBBundleRings("
      )
      let queue = try #require(deliver.range(of: "SwifterKitQueueUSBEvent(")?.lowerBound)
      let idle = try #require(deliver.range(of: "SwifterKitUSBBundleEntryState::Idle;")?.lowerBound)
      #expect(queue < idle)
      #expect(bundled.contains("result = kIOReturnBusy;"))
    }
  }

  @Test
  func usbSerialLeavesTheDataPathToItsSuperclass() throws {
    try withGeneratedExtension { output in
      let serial = try source("SwifterKitRuntimeSerial.cpp", in: output)
      let activate = try section(
        of: serial,
        from: "#if SWIFTERKIT_USB_SERIAL\n// IOUserUSBSerial copies",
        to: "#else"
      )
      #expect(activate.contains("HwActivate(SUPERDISPATCH)"))
      #expect(activate.contains("HwDeactivate(SUPERDISPATCH)"))
      #expect(!activate.contains("RxFreeSpaceAvailable_Impl"))
      let command = try section(
        of: serial,
        from: "::SerialCommand(",
        to: "IOLockLock(ivars->serialLock);"
      )
      #expect(command.contains("return kIOReturnUnsupported;"))
      let stop = try section(of: serial, from: "::StopSerial(", to: "::SerialCommand(")
      let abort = try #require(stop.range(of: "StopUSB();")?.lowerBound)
      let disconnect = try #require(stop.range(of: "DisconnectQueues()")?.lowerBound)
      #expect(abort < disconnect)
      let start = try section(of: serial, from: "::StartSerial(", to: "::StopSerial(")
      #expect(start.contains("PublishTerminalName(this)"))
      // A start that fails after ConnectQueues disconnects the queues before the service stops.
      let modem = try #require(start.range(of: "result = SetModemStatus(")?.lowerBound)
      let cleanup = try #require(
        start.range(
          of: "if (result != kIOReturnSuccess) {\n        StopSerial();\n    }\n    return result;"
        )?.lowerBound
      )
      #expect(modem < cleanup)

      let usb = try source("SwifterKitRuntimeUSB.cpp", in: output)
      let startUSB = try section(of: usb, from: "::StartUSB(", to: "::StopUSB(")
      let borrow = try #require(
        startUSB.range(of: "if constexpr (kSerialOwnsInterface)")?.lowerBound
      )
      let open = try #require(startUSB.range(of: "ivars->usbInterface->Open(")?.lowerBound)
      #expect(borrow < open)
      let stopUSB = try section(of: usb, from: "::StopUSB(", to: "::USBControlTransfer(")
      #expect(stopUSB.contains("if constexpr (!kSerialOwnsInterface)"))

      let hooks = try source("SwifterKitRuntimeUSBSerial.cpp", in: output)
      #expect(hooks.contains("super::handleRxPacket(packet, size);"))
      #expect(hooks.contains("super::handleInterruptPacket(packet, size);"))
      #expect(
        hooks.contains(
          "static_assert(kMaximumPacketChunk == \(USBSerialEvent.maximumPacketLength));"
        )
      )
      #expect(hooks.contains("service->EnqueueEvent(\n"))
    }
  }

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    try withTemporaryExtension(
      named: "USBAsyncContract",
      configuration: USBSerialGeneratorTests.configuration(),
    ) { output, _ in try body(output) }
  }
}
