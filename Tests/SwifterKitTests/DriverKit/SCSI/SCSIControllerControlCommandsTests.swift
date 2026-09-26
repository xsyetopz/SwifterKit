import Foundation
import Testing

@testable import SwifterKit

@Suite
struct SCSIControllerControlCommandsTests {
  @Test
  func encodesTargetCommands() throws {
    let present = DriverCommand.scsiTargetPresent(0x0102)
    #expect(present.opcode == 0x0B20)
    #expect(present.requiredCapabilities == .scsi)
    #expect(Array(present.payload) == [2, 1, 0, 0, 0, 0, 0, 0])
    #expect(present.maximumResponseSize == RuntimeMessage.headerSize + 4)

    let destroy = DriverCommand.scsiDestroyTarget(3)
    #expect(destroy.opcode == 0x0B22)
    #expect(Array(destroy.payload) == [3, 0, 0, 0, 0, 0, 0, 0])

    let create = try DriverCommand.scsiCreateTarget(4)
    #expect(create.opcode == 0x0B21)
    #expect(Array(create.payload) == bytes([4, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]))

    let changed = DriverCommand.scsiMediaParametersChanged
    #expect(changed.opcode == 0x0B27)
    #expect(changed.payload.isEmpty)
  }

  @Test
  func encodesPropertiesSortedByKey() throws {
    let command = try DriverCommand.scsiSetTargetProperties(
      [.sasAddress: "5000", .fibreChannelALPA: "E8"],
      for: 9
    )
    #expect(command.opcode == 0x0B25)
    let alpa = bytes([5, 0, 2, 0], Array("AL_PA".utf8), Array("E8".utf8))
    let header = bytes([9, 0, 0, 0, 0, 0, 0, 0], [2, 0, 0, 0], [0, 0, 0, 0])
    let sas = bytes([11, 0, 4, 0], Array("SAS Address".utf8), Array("5000".utf8))
    #expect(Array(command.payload) == bytes(header, alpa, sas))

    let controller = try DriverCommand.scsiSetControllerProperties([.vendorName: "Acme"])
    #expect(controller.opcode == 0x0B23)
    #expect(try controller.payload.readRuntimeInteger(at: 0) as UInt64 == 0)
  }

  @Test
  func encodesRemovals() throws {
    let command = try DriverCommand.scsiRemoveControllerProperties([.portSpeed])
    #expect(command.opcode == 0x0B24)
    let expected = bytes(
      [0, 0, 0, 0, 0, 0, 0, 0],
      [1, 0, 0, 0],
      [0, 0, 0, 0],
      [10, 0, 0, 0],
      Array("Port Speed".utf8)
    )
    #expect(Array(command.payload) == expected)

    let target = try DriverCommand.scsiRemoveTargetProperties([.sasAddress], for: 2)
    #expect(target.opcode == 0x0B26)
    #expect(try target.payload.readRuntimeInteger(at: 0) as UInt64 == 2)
  }

  @Test
  func rejectsInvalidPropertyUpdates() {
    #expect(throws: SCSIControllerRuntimeError.invalidPropertyUpdate) {
      try DriverCommand.scsiSetControllerProperties([:])
    }
    #expect(throws: SCSIControllerRuntimeError.invalidPropertyUpdate) {
      try DriverCommand.scsiRemoveControllerProperties([])
    }
    #expect(throws: SCSIControllerRuntimeError.invalidPropertyUpdate) {
      try DriverCommand.scsiRemoveTargetProperties([.sasAddress, .sasAddress], for: 1)
    }
    #expect(throws: SCSIControllerRuntimeError.invalidPropertyUpdate) {
      try DriverCommand.scsiSetControllerProperties([SCSIProtocolPropertyKey(rawValue: ""): "x"])
    }
    #expect(throws: SCSIControllerRuntimeError.invalidPropertyUpdate) {
      try DriverCommand.scsiSetControllerProperties([.vendorName: "a\u{0}b"])
    }
    let longKey = SCSIProtocolPropertyKey(rawValue: String(repeating: "k", count: 128))
    #expect(throws: SCSIControllerRuntimeError.invalidPropertyUpdate) {
      try DriverCommand.scsiSetControllerProperties([longKey: "v"])
    }
    #expect(throws: SCSIControllerRuntimeError.invalidPropertyUpdate) {
      try DriverCommand.scsiSetControllerProperties([
        .vendorName: String(repeating: "v", count: 1_025)
      ])
    }
    let many = Dictionary(
      uniqueKeysWithValues: (0...32).map { (SCSIProtocolPropertyKey(rawValue: "k\($0)"), "v") }
    )
    #expect(throws: SCSIControllerRuntimeError.invalidPropertyUpdate) {
      try DriverCommand.scsiSetTargetProperties(many, for: 1)
    }
    let largest = Dictionary(
      uniqueKeysWithValues: (0..<32).map {
        (
          SCSIProtocolPropertyKey(
            rawValue: String(format: "%03d", $0) + String(repeating: "k", count: 124)
          ), String(repeating: "v", count: 1_024)
        )
      }
    )
    let command = try? DriverCommand.scsiCreateTarget(1, properties: largest)
    let size = command.map { $0.payload.count + RuntimeSchema.commandHeaderSize }
    #expect(size.map { $0 <= RuntimeMessage.maximumSize - RuntimeMessage.headerSize } == true)
  }

  @Test
  func encodesTaskDataAccess() throws {
    let read = try DriverCommand.scsiReadTaskData(requestID: 7, offset: 512, count: 64)
    #expect(read.opcode == 0x0B28)
    #expect(Array(read.payload) == bytes([7, 0, 0, 0], [64, 0, 0, 0], [0, 2, 0, 0, 0, 0, 0, 0]))
    #expect(read.maximumResponseSize == RuntimeMessage.headerSize + 64)

    let write = try DriverCommand.scsiWriteTaskData(requestID: 7, offset: 0, bytes: [0xAA, 0xBB])
    #expect(write.opcode == 0x0B29)
    #expect(
      Array(write.payload)
        == bytes([7, 0, 0, 0], [2, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0], [0xAA, 0xBB])
    )

    let largest = SCSIControllerLimits.maximumTaskDataWriteLength
    let full = try DriverCommand.scsiWriteTaskData(
      requestID: 1,
      offset: 0,
      bytes: Array(repeating: 0, count: largest)
    )
    #expect(
      full.payload.count + RuntimeSchema.commandHeaderSize + RuntimeMessage.headerSize
        == RuntimeMessage.maximumSize
    )
    let fullRead = try DriverCommand.scsiReadTaskData(
      requestID: 1,
      offset: 0,
      count: SCSIControllerLimits.maximumTaskDataReadLength
    )
    #expect(fullRead.maximumResponseSize == RuntimeMessage.maximumSize)
  }

  @Test
  func rejectsInvalidTaskDataRanges() {
    #expect(throws: SCSIControllerRuntimeError.invalidDataRange) {
      try DriverCommand.scsiReadTaskData(requestID: 0, offset: 0, count: 1)
    }
    #expect(throws: SCSIControllerRuntimeError.invalidDataRange) {
      try DriverCommand.scsiReadTaskData(requestID: 1, offset: 0, count: 0)
    }
    #expect(throws: SCSIControllerRuntimeError.invalidDataRange) {
      try DriverCommand.scsiReadTaskData(
        requestID: 1,
        offset: 0,
        count: SCSIControllerLimits.maximumTaskDataReadLength + 1
      )
    }
    #expect(throws: SCSIControllerRuntimeError.invalidDataRange) {
      try DriverCommand.scsiWriteTaskData(requestID: 1, offset: 0, bytes: [])
    }
    #expect(throws: SCSIControllerRuntimeError.invalidDataRange) {
      try DriverCommand.scsiWriteTaskData(
        requestID: 1,
        offset: 0,
        bytes: Array(repeating: 0, count: SCSIControllerLimits.maximumTaskDataWriteLength + 1)
      )
    }
  }

  @Test
  func validatesConstraints() {
    let valid = SCSIControllerConstraints(
      maximumSegmentCountRead: 1,
      maximumSegmentCountWrite: 1,
      maximumSegmentByteCountRead: 4_096,
      maximumSegmentByteCountWrite: 4_096
    )
    #expect(valid.isValid)
    let badAlignment = SCSIControllerConstraints(
      maximumSegmentCountRead: 1,
      maximumSegmentCountWrite: 1,
      maximumSegmentByteCountRead: 4_096,
      maximumSegmentByteCountWrite: 4_096,
      minimumSegmentAlignmentByteCount: 3
    )
    #expect(!badAlignment.isValid)
    let noSegments = SCSIControllerConstraints(
      maximumSegmentCountRead: 0,
      maximumSegmentCountWrite: 1,
      maximumSegmentByteCountRead: 4_096,
      maximumSegmentByteCountWrite: 4_096
    )
    #expect(!noSegments.isValid)
    let wideAddress = SCSIControllerConstraints(
      maximumSegmentCountRead: 1,
      maximumSegmentCountWrite: 1,
      maximumSegmentByteCountRead: 4_096,
      maximumSegmentByteCountWrite: 4_096,
      maximumSegmentAddressableBitCount: 65
    )
    #expect(!wideAddress.isValid)
    let fullMask = SCSIControllerConstraints(
      maximumSegmentCountRead: 1,
      maximumSegmentCountWrite: 1,
      maximumSegmentByteCountRead: 4_096,
      maximumSegmentByteCountWrite: 4_096,
      minimumHBADataAlignmentMask: .max
    )
    #expect(fullMask.isValid)
  }

  private func bytes(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }
}
