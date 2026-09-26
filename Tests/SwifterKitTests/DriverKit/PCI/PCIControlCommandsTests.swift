import Foundation
import Testing

@testable import SwifterKit

@Suite
struct PCIControlCommandsTests {
  @Test
  func typedValuesMatchDriverKitConstants() {
    // The native runtime static_asserts the same SDK values in SwifterKitRuntimePCI.cpp.
    #expect(PCIAccessOptions.latencyTolerant.rawValue == 0x1)
    #expect(PCIResetType.allCases.map(\.rawValue) == [0x01, 0x02, 0x04, 0x08, 0x10])
    #expect(PCIResetOptions.terminate.rawValue == 0x1)
    #expect(PCISaveStateOptions.permanent.rawValue == 0x8000_0000)
    #expect(PCILinkSpeed.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
    #expect(PCIASPMState.all.rawValue == 0x3)
    #expect(PCIPowerManagementSupport.all.rawValue == 0xFE01)
    #expect(PCIPowerManagementState.allCases.map(\.rawValue) == [0, 1, 2, 3, 0xFFFF_FFFF])
    #expect(PCIInterruptType.allCases.map(\.rawValue) == [0x1, 0x1_0000, 0x2_0000])
  }

  @Test
  func encodesResetAndStateCommands() throws {
    let reset = try DriverCommand.pciReset(type: .functionLevel, options: .terminate)
    #expect(reset.opcode == 0x0410)
    #expect(reset.requiredCapabilities == .pci)
    #expect(reset.payload.count == 8)
    #expect(try reset.payload.readRuntimeInteger(at: 0) as UInt32 == 0x10)
    #expect(try reset.payload.readRuntimeInteger(at: 4) as UInt32 == 1)
    #expect(reset.maximumResponseSize == RuntimeMessage.headerSize)

    let save = try DriverCommand.pciSaveDeviceState(options: .permanent)
    #expect(save.opcode == 0x0411)
    #expect(save.payload == Data([0, 0, 0, 0x80]))

    #expect(DriverCommand.pciRestoreDeviceState.opcode == 0x0412)
    #expect(DriverCommand.pciRestoreDeviceState.payload.isEmpty)
  }

  @Test
  func encodesPowerAndLinkCommands() throws {
    let query = try DriverCommand.pciHasPowerManagement(support: [.d3, .pmeFromD3Cold])
    #expect(query.opcode == 0x0413)
    #expect(try query.payload.readRuntimeInteger(at: 0) as UInt64 == 0x8001)
    #expect(query.maximumResponseSize == RuntimeMessage.headerSize + 4)

    let enable = DriverCommand.pciEnablePowerManagement(state: .automatic)
    #expect(enable.opcode == 0x0414)
    #expect(try enable.payload.readRuntimeInteger(at: 0) as UInt64 == 0xFFFF_FFFF)

    #expect(DriverCommand.pciLinkSpeed.opcode == 0x0415)
    #expect(DriverCommand.pciLinkSpeed.payload.isEmpty)
    #expect(DriverCommand.pciLinkSpeed.maximumResponseSize == RuntimeMessage.headerSize + 4)

    let speed = DriverCommand.pciSetLinkSpeed(.gen3, retrain: true)
    #expect(speed.opcode == 0x0416)
    #expect(speed.payload == Data([3, 0, 0, 0, 1, 0, 0, 0]))

    let aspm = try DriverCommand.pciSetASPMState([.l0s, .l1])
    #expect(aspm.opcode == 0x0417)
    #expect(aspm.payload == Data([3, 0, 0, 0]))
    #expect(try DriverCommand.pciSetASPMState([]).payload == Data([0, 0, 0, 0]))
  }

  @Test
  func encodesPropertyUpdate() throws {
    let command = try DriverCommand.pciSetProperties(
      PCIDeviceProperties(configSpaceVolatile: false, sleepReset: true)
    )
    #expect(command.opcode == 0x0418)
    #expect(command.payload == Data([1, 0, 2, 0]))
    #expect(throws: PCIRuntimeError.emptyPropertyUpdate) {
      try DriverCommand.pciSetProperties(PCIDeviceProperties())
    }
  }

  @Test
  func decodesPowerManagementAndLinkSpeedResponses() throws {
    #expect(try PCIPowerManagementSupport.isSupported(runtimePayload: Data([1, 0, 0, 0])))
    #expect(!(try PCIPowerManagementSupport.isSupported(runtimePayload: Data([0, 0, 0, 0]))))
    #expect(throws: PCIRuntimeError.invalidResponse) {
      try PCIPowerManagementSupport.isSupported(runtimePayload: Data([2, 0, 0, 0]))
    }
    #expect(throws: PCIRuntimeError.invalidResponse) {
      try PCIPowerManagementSupport.isSupported(runtimePayload: Data([1, 0, 0]))
    }

    #expect(try PCILinkSpeed(runtimePayload: Data([4, 0, 0, 0])) == .gen4)
    for invalid in [Data([0, 0, 0, 0]), Data([6, 0, 0, 0]), Data([3, 0, 0, 0, 0])] {
      #expect(throws: PCIRuntimeError.invalidResponse) { try PCILinkSpeed(runtimePayload: invalid) }
    }
  }

  @Test
  func nativeUserClientDispatchesEveryPCIOpcode() throws {
    let userClient = checkedInNativeSources.appendingPathComponent(
      "SwifterKitRuntimeCommandDispatch.cpp"
    )
    let source = try String(contentsOf: userClient, encoding: .utf8)
    // Native opcode names are the schema's, e.g. `PCIReset` for `RuntimeOpcode.pciReset`.
    let names = RuntimeOpcode.allCases.filter { $0.rawValue >> 8 == 0x04 }.map {
      RuntimeSchemaHeader.nativeName($0)
    }
    #expect(!names.isEmpty)
    for name in names {
      #expect(source.contains("case SwifterKitRuntimeOpcode::\(name):"), "\(name)")
    }
  }

  @Test
  func rejectsUndefinedOptionBits() {
    #expect(throws: PCIRuntimeError.invalidOptions) {
      try DriverCommand.pciReset(type: .hot, options: PCIResetOptions(rawValue: 2))
    }
    #expect(throws: PCIRuntimeError.invalidOptions) {
      try DriverCommand.pciSaveDeviceState(options: PCISaveStateOptions(rawValue: 1))
    }
    #expect(throws: PCIRuntimeError.invalidOptions) {
      try DriverCommand.pciHasPowerManagement(support: PCIPowerManagementSupport(rawValue: 0x2))
    }
    #expect(throws: PCIRuntimeError.invalidOptions) {
      try DriverCommand.pciSetASPMState(PCIASPMState(rawValue: 4))
    }
  }

  @Test
  func validatesInterruptVectorCounts() {
    #expect(
      PCIInterruptConfiguration(type: .msiX, requiredVectorCount: 4).requestedVectorCount == 4
    )
    #expect(PCIInterruptConfiguration(type: .msi, requestedVectorCount: 32).hasValidVectorCounts)
    #expect(!PCIInterruptConfiguration(type: .msi, requestedVectorCount: 33).hasValidVectorCounts)
    #expect(
      PCIInterruptConfiguration(type: .msiX, requestedVectorCount: 2_048).hasValidVectorCounts
    )
    #expect(!PCIInterruptConfiguration(type: .legacy, requestedVectorCount: 2).hasValidVectorCounts)
    #expect(!PCIInterruptConfiguration(type: .msi, requiredVectorCount: 0).hasValidVectorCounts)
    #expect(
      !PCIInterruptConfiguration(type: .msi, requiredVectorCount: 4, requestedVectorCount: 2)
        .hasValidVectorCounts
    )
    let allocation = PCIInterruptConfiguration(type: .msi, requiredVectorCount: 2)
    #expect(allocation.canDeliver(sourceIndex: 1))
    #expect(!allocation.canDeliver(sourceIndex: 2))
  }
}
