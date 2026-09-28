import Foundation
import Testing

@testable import SwifterKit

/// The generated extension's fast-path wiring: lifecycle order, interrupt ordering and delivery,
/// the exactly-once command answer, locking, and the PCI-only build.
@Suite
struct FastPathRuntimeContractTests {
  private static let register = FastPathRegister(bar: 0, offset: 0x10, width: .bits32)

  @Test
  func pciOnlyFastPathGeneratesAndBuilds() throws {
    let fastPath = FastPathConfiguration(
      programs: [
        FastPathProgram(trigger: .start, operations: [.write(Self.register, .constant(1))]),
        FastPathProgram(
          trigger: .command,
          argumentCount: 1,
          operations: [.write(Self.register, .value(.v0)), .read(Self.register, into: .v1)]
        ), FastPathProgram(trigger: .stop, operations: [.modify(Self.register, clear: 1, set: 0)]),
      ],
      barSizes: [0: 0x100]
    )
    try withTemporaryExtension(
      named: "FastPathPCIDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.fast-path-pci",
        providerClass: "IOPCIDevice",
        capabilities: [.pci],
        pciDevice: PCIDeviceConfiguration(vendorID: 0x1011, deviceIDs: [0x0026]),
        fastPath: fastPath
      )
    ) { output, root in
      let configuration = try source("SwifterKitRuntimeConfiguration.h", in: output)
      #expect(configuration.contains("#define SWIFTERKIT_ENABLE_FAST_PATH 1"))
      #expect(configuration.contains("#define SWIFTERKIT_ENABLE_INTERRUPTS 0"))
      let service = try source("SwifterKitRuntimeService.iig", in: output)
      #expect(service.contains("kern_return_t FastPathCommand("))
      #expect(service.contains("bool RunFastPathInterrupt(uint32_t sourceIndex) LOCALONLY;"))
      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }

  @Test
  func interruptProgramRunsBeforeTheEventAndDecidesDelivery() throws {
    try withMaximalExtension { output in
      let interrupts = try source("SwifterKitRuntimeInterrupts.cpp", in: output)
      let handler = try section(
        of: interrupts,
        from: "void SwifterKitRuntimeService::InterruptOccurred_Impl(",
        to: "kern_return_t SwifterKitRuntimeService::InterruptCommand("
      )
      try expectOrder(
        in: handler,
        "if (!RunFastPathInterrupt(event.index)) {",
        "return;",
        "(void)EnqueueEvent(kSwifterKitEventInterrupt, &event, sizeof(event));"
      )
      let runtime = try source("SwifterKitRuntimeFastPath.cpp", in: output)
      let run = try section(
        of: runtime,
        from: "bool SwifterKitRuntimeService::RunFastPathInterrupt(",
        to: "kern_return_t SwifterKitRuntimeService::FastPathCommand("
      )
      try expectOrder(
        in: run,
        "SwifterKitFastPathInterruptProgram(kTables, sourceIndex)",
        "return true;",
        "RunProgram(this, ivars, program, nullptr, 0, &outcome) == kIOReturnSuccess",
        "&& outcome.executed;",
        "return SwifterKitFastPathDeliversInterrupt(",
        "kTables.triggers[program].delivery,"
      )
    }
  }

  @Test
  func commandIsAnsweredExactlyOnceWithStatusAndSlots() throws {
    try withMaximalExtension { output in
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let route = try section(
        of: dispatch,
        from: "kern_return_t DispatchFastPathCommand(",
        to: "kern_return_t DispatchUSBControlTransfer("
      )
      #expect(route.components(separatedBy: "->FastPathCommand(").count == 2)
      #expect(route.components(separatedBy: "return RespondToCommand(").count == 2)
      #expect(dispatch.contains("case SwifterKitRuntimeOpcode::FastPathRun:"))
      #expect(dispatch.contains("case SwifterKitRuntimeOpcode::FastPathStatus:"))

      let runtime = try source("SwifterKitRuntimeFastPath.cpp", in: output)
      let command = try section(
        of: runtime,
        from: "kern_return_t RunCommand(",
        to: "}  // namespace"
      )
      // Every refusal returns before the program runs. A program that ran answers one reply
      // carrying its own status, even a timeout or fail status.
      try expectOrder(
        in: command,
        "if (payloadLength != sizeof(request)) {",
        "request.arguments[index] != 0",
        "SwifterKitFastPathIsCommand(kTables, request.program, request.argumentCount)",
        "const kern_return_t result = RunProgram(",
        "if (!outcome.executed) {",
        ".status = outcome.status",
        "reply.values[slot] = outcome.slots[slot];",
        "*response = OSData::withBytes(&reply, sizeof(reply));"
      )
      #expect(command.components(separatedBy: "RunProgram(").count == 2)
      #expect(command.components(separatedBy: "*response = ").count == 2)
    }
  }

  @Test
  func runsAreSerializedAndLifecycleOrdered() throws {
    try withMaximalExtension { output in
      let runtime = try source("SwifterKitRuntimeFastPath.cpp", in: output)
      let run = try section(
        of: runtime,
        from: "kern_return_t ExecuteHoldingLock(",
        to: "kern_return_t RunPrograms("
      )
      // The lock-held body runs the program. RunProgram wraps it in the lock.
      try expectOrder(
        in: run,
        "state->fastPathRunning",
        "*outcome = SwifterKitFastPathExecute(",
        "kern_return_t RunProgram(",
        "IOLockLock(state->fastPathLock);",
        "ExecuteHoldingLock(service, state, program, arguments, argumentCount, outcome);",
        "IOLockUnlock(state->fastPathLock);"
      )
      #expect(run.components(separatedBy: "IOLockLock(").count == 2)
      #expect(
        runtime.contains(
          "SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Timeout)\n"
            + "    == static_cast<uint32_t>(kIOReturnTimeout));"
        )
      )
      let emit = try section(of: runtime, from: "void Emit(", to: "kern_return_t PrepareBARs(")
      try expectOrder(
        in: emit,
        "service->EnqueueEvent(kSwifterKitEventFastPath, &event, sizeof(event))",
        "state->fastPathEventDrops += 1;"
      )
      let prepare = try section(
        of: runtime,
        from: "kern_return_t PrepareBARs(",
        to: "kern_return_t PrepareFastPath("
      )
      try expectOrder(
        in: prepare,
        "->GetBARInfo(",
        "|| size < bars.sizes[bar]) {",
        "return kIOReturnNoResources;"
      )

      let service = try source("SwifterKitRuntimeService.cpp", in: output)
      let start = try section(
        of: service,
        from: "Start_Impl(IOService* provider)",
        to: "Stop_Impl("
      )
      try expectOrder(
        in: start,
        "result = OpenPCIProvider(this, provider, ivars);",
        "StartFastPath();",
        "result = StartInterrupts(provider);"
      )
      let stop = try section(
        of: service,
        from: "Stop_Impl(IOService* provider)",
        to: "return Stop(provider, SUPERDISPATCH);"
      )
      try expectOrder(
        in: stop,
        "StopFastPath();",
        "DetachEventClient(nullptr);",
        "StopInterrupts();",
        "ClosePCIProvider(this, ivars);"
      )
      let pci = try source("SwifterKitRuntimePCI.cpp", in: output)
      try expectOrder(
        in: pci[...],
        "ivars->pciAperturesLoaded = false;",
        "InvalidateFastPathBARs();",
        "device->Reset("
      )
    }
  }

  @Test
  func extensionWithoutAFastPathDeclaresNone() throws {
    try withTemporaryExtension(
      named: "PlainDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.plain",
        providerClass: "IOPCIDevice",
        capabilities: [.pci],
        pciDevice: PCIDeviceConfiguration(vendorID: 0x1011, deviceIDs: [0x0026])
      )
    ) { output, _ in
      #expect(!(try source("SwifterKitRuntimeService.iig", in: output)).contains("FastPath"))
      let configuration = try source("SwifterKitRuntimeConfiguration.h", in: output)
      #expect(configuration.contains("#define SWIFTERKIT_ENABLE_FAST_PATH 0"))
    }
  }

  private func withMaximalExtension(_ body: (URL) throws -> Void) throws {
    try withTemporaryExtension(
      named: "FastPathDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.fast-path",
        providerClass: "IOPCIDevice",
        capabilities: [.pci, .interrupts],
        pciDevice: PCIDeviceConfiguration(vendorID: 0x1011, deviceIDs: [0x0026]),
        interruptSources: (0..<32).map { InterruptSourceConfiguration(index: $0) },
        fastPath: FastPathGenerationTests.maximal
      )
    ) { output, _ in try body(output) }
  }
}
