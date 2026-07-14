import Foundation
import Testing

@testable import SwifterKit

@Suite struct SCSIPeripheralTypesTests {
  @Test func mapsTransferConstraintsToRegistryKeys() {
    let constraints = SCSIPeripheralTransferConstraints(
      maximumBlockCountRead: 32,
      maximumSegmentCountWrite: 8,
      maximumSwapWrite: 1
    )

    #expect(
      constraints.registryProperties == [
        "IOMaximumBlockCountRead": 32, "IOMaximumSegmentCountWrite": 8, "IOMaximumSwapWrite": 1,
      ]
    )
  }

  @Test func encodesReadAndWriteCommands() throws {
    let read = try SCSIPeripheralCommand(
      timeoutMilliseconds: 2_000,
      commandDescriptorBlock: [0x12],
      transferDirection: .targetToInitiator,
      requestedDataLength: 96,
      requestedSenseLength: 18
    )
    let write = try SCSIPeripheralCommand(
      logicalUnitNumber: 3,
      timeoutMilliseconds: 4_000,
      commandDescriptorBlock: [0x2A, 0, 0, 0, 0, 1],
      transferDirection: .initiatorToTarget,
      outboundData: [1, 2, 3],
      requestedDataLength: 3
    )
    let readCommand = DriverCommand.sendSCSIPeripheralCommand(read)
    let writeCommand = DriverCommand.sendSCSIPeripheralCommand(write)

    #expect(readCommand.opcode == 0x0B10)
    #expect(readCommand.requiredCapabilities == .scsi)
    #expect(try readCommand.payload.readRuntimeInteger(at: 8) as UInt32 == 2_000)
    #expect(try readCommand.payload.readRuntimeInteger(at: 12) as UInt32 == 96)
    #expect(readCommand.payload[16] == 0x12)
    #expect(readCommand.payload[32] == 2)
    #expect(readCommand.payload[33] == 18)
    #expect(writeCommand.payload.count == 43)
    #expect(Array(writeCommand.payload.suffix(3)) == [1, 2, 3])
  }

  @Test func decodesDataAndSenseResponse() throws {
    var payload = Data()
    payload.appendRuntimeInteger(UInt32(2))
    payload.appendRuntimeInteger(UInt32(2))
    payload.appendRuntimeInteger(UInt64(3))
    payload.append(contentsOf: [1, 2])
    payload.appendRuntimeInteger(UInt16(0))
    payload.appendRuntimeInteger(UInt32(3))
    payload.append(contentsOf: [9, 8, 7, 0x70, 5])

    let response = try SCSIPeripheralResponse(runtimePayload: payload)
    #expect(response.taskStatus == .checkCondition)
    #expect(response.serviceResponse == .taskComplete)
    #expect(response.realizedDataLength == 3)
    #expect(response.data == [9, 8, 7])
    #expect(response.senseData == [0x70, 5])
  }

  @Test func validatesDirectionLengthsAndResponses() {
    #expect(throws: SCSIPeripheralRuntimeError.invalidCommand) {
      try SCSIPeripheralCommand(
        timeoutMilliseconds: 1,
        commandDescriptorBlock: [],
        transferDirection: .targetToInitiator,
        requestedDataLength: 1
      )
    }
    #expect(throws: SCSIPeripheralRuntimeError.invalidCommand) {
      try SCSIPeripheralCommand(
        timeoutMilliseconds: 1,
        commandDescriptorBlock: [0x2A],
        transferDirection: .initiatorToTarget,
        outboundData: [1],
        requestedDataLength: 2
      )
    }
    #expect(throws: SCSIPeripheralRuntimeError.invalidPayload) {
      try SCSIPeripheralResponse(runtimePayload: Data(repeating: 0, count: 23))
    }
  }

  @Test func exposesServiceControlOpcodes() {
    #expect(DriverCommand.suspendSCSIPeripheralServices.opcode == 0x0B11)
    #expect(DriverCommand.resumeSCSIPeripheralServices.opcode == 0x0B12)
    #expect(DriverCommand.resetSCSIPeripheral.opcode == 0x0B13)
    #expect(DriverCommand.scsiPeripheralMediumBlockSize.opcode == 0x0B14)
  }
}
