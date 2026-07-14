import Foundation
import Testing

@testable import SwifterKit

@Suite struct PCITypesTests {
  @Test func createsPrimaryDeviceMatching() {
    let configuration = PCIDeviceConfiguration(vendorID: 0x1011, deviceIDs: [0x0026, 0x0078])

    #expect(
      configuration.matchingProperties["IOPCIPrimaryMatch"] == .string("0x00261011 0x00781011")
    )
  }

  @Test func encodesConfigurationRead() throws {
    let command = try DriverCommand.pciRead(space: .configuration, offset: 4, width: .doubleWord)

    #expect(command.opcode == 0x0400)
    #expect(command.requiredCapabilities == .pci)
    #expect(command.payload.count == 24)
    #expect(try command.payload.readRuntimeInteger(at: 0) as UInt64 == 4)
    #expect(command.payload[21] == PCIAccessWidth.doubleWord.rawValue)
    #expect(command.payload[22] == 0)
  }

  @Test func encodesMemoryWrite() throws {
    let command = try DriverCommand.pciWrite(
      space: .memory(index: 3),
      offset: 8,
      value: 0x1122,
      width: .quadWord,
      options: 7
    )

    #expect(command.opcode == 0x0401)
    #expect(try command.payload.readRuntimeInteger(at: 8) as UInt64 == 0x1122)
    #expect(try command.payload.readRuntimeInteger(at: 16) as UInt32 == 7)
    #expect(command.payload[20] == 3)
    #expect(command.payload[22] == 1)
  }

  @Test func rejectsInvalidWidthAndAlignment() {
    #expect(throws: PCIRuntimeError.invalidConfigurationWidth) {
      try DriverCommand.pciRead(space: .configuration, offset: 0, width: .quadWord)
    }
    #expect(throws: PCIRuntimeError.misalignedOffset) {
      try DriverCommand.pciRead(space: .memory(index: 0), offset: 3, width: .doubleWord)
    }
    #expect(throws: PCIRuntimeError.configurationOffsetOutOfRange) {
      try DriverCommand.pciRead(space: .configuration, offset: 4_096, width: .byte)
    }
    #expect(throws: PCIRuntimeError.valueOutOfRange) {
      try DriverCommand.pciWrite(space: .configuration, offset: 0, value: 256, width: .byte)
    }
    #expect(throws: PCIRuntimeError.invalidBARIndex) {
      try DriverCommand.pciBaseAddressInfo(index: 7)
    }
  }

  @Test func decodesBARAndLocationResponses() throws {
    var bar = Data([2, 4, 0, 0])
    bar.appendRuntimeInteger(UInt64(4_096))

    #expect(
      try PCIBaseAddressInfo(runtimePayload: bar)
        == PCIBaseAddressInfo(memoryIndex: 2, type: 4, size: 4_096)
    )
    #expect(
      try PCILocation(runtimePayload: Data([1, 2, 3, 0]))
        == PCILocation(bus: 1, device: 2, function: 3)
    )
  }
}
