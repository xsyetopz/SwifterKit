import Foundation
import Testing

@testable import SwifterKit

@Suite
struct SCSIControllerTypesTests {
  @Test
  func decodesParallelTask() throws {
    var payload = Data()
    payload.appendRuntimeInteger(UInt32(9))
    payload.appendRuntimeInteger(UInt32(2))
    payload.appendRuntimeInteger(UInt64(3))
    payload.appendRuntimeInteger(UInt64(44))
    payload.appendRuntimeInteger(UInt64(8_192))
    payload.appendRuntimeInteger(UInt64(0x1234))
    payload.appendRuntimeInteger(UInt64(77))
    payload.appendRuntimeInteger(UInt32(5_000))
    payload.append(contentsOf: [1, 2, 6, 0])
    payload.append(contentsOf: [0, 1, 2, 3, 4, 5, 6, 7])
    payload.append(contentsOf: [0x12, 0, 0, 0, 36, 0] + Array(repeating: 0, count: 10))
    payload.appendRuntimeInteger(SCSIParallelFeatureRequest.attemptNegotiation.rawValue)
    payload.appendRuntimeInteger(SCSIParallelFeatureRequest.clearNegotiation.rawValue)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(UInt32(0))

    let event = try DriverEvent(type: 0x0B00, payload: Array(payload)).scsiController()
    let task = try #require(parallelTask(from: event))
    #expect(task.requestID == 9)
    #expect(task.targetIdentifier == 3)
    #expect(task.controllerTaskIdentifier == 44)
    #expect(task.requestedTransferCount == 8_192)
    #expect(task.bufferIOVMAddress == 0x1234)
    #expect(task.taskTagIdentifier == 77)
    #expect(task.timeoutMilliseconds == 5_000)
    #expect(task.taskAttribute == .ordered)
    #expect(task.transferDirection == .targetToInitiator)
    #expect(task.logicalUnitBytes == [0, 1, 2, 3, 4, 5, 6, 7])
    #expect(task.commandDescriptorBlock == [0x12, 0, 0, 0, 36, 0])
    #expect(task.featureRequests == [.attemptNegotiation, .clearNegotiation])
  }

  @Test
  func encodesCompletion() throws {
    let completion = try SCSIParallelTaskCompletion(
      requestID: 11,
      taskStatus: .checkCondition,
      serviceResponse: .taskComplete,
      bytesTransferred: 512,
      featureResults: [.success, .cleared],
      senseData: [0x70, 0, 5]
    )
    let command = DriverCommand.completeSCSIParallelTask(completion)

    #expect(command.opcode == 0x0B00)
    #expect(command.requiredCapabilities == .scsi)
    #expect(try command.payload.readRuntimeInteger(at: 0) as UInt32 == 11)
    #expect(try command.payload.readRuntimeInteger(at: 4) as UInt32 == 2)
    #expect(try command.payload.readRuntimeInteger(at: 8) as UInt32 == 2)
    #expect(try command.payload.readRuntimeInteger(at: 16) as UInt64 == 512)
    #expect(try command.payload.readRuntimeInteger(at: 24) as UInt32 == 3)
    #expect(Array(command.payload.suffix(3)) == [0x70, 0, 5])
  }

  @Test
  func decodesManagementCallbacks() throws {
    #expect(try management(kind: 1, target: 4).scsiController() == .initializeTarget(4))
    #expect(
      try management(kind: 2, target: 4, logicalUnit: 7, taskTag: 8).scsiController()
        == .taskManagement(.abortTask(targetIdentifier: 4, logicalUnit: 7, taskTag: 8))
    )
    #expect(
      try management(kind: 7, target: 5).scsiController()
        == .taskManagement(.targetReset(targetIdentifier: 5))
    )
  }

  @Test
  func rejectsMalformedPayloadsAndOversizedCompletion() throws {
    #expect(try DriverEvent(type: 0x0100).scsiController() == nil)
    #expect(throws: SCSIControllerRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0B00, payload: [0]).scsiController()
    }
    #expect(throws: SCSIControllerRuntimeError.invalidCompletion) {
      try SCSIParallelTaskCompletion(requestID: 1, senseData: Array(repeating: 0, count: 257))
    }
  }

  @Test
  func decodesTargetCreationResults() throws {
    let created = try #require(targetCreation(from: targetCreated(target: 4).scsiController()))
    #expect(created.target == 4)
    #expect(created.status == 0)
    #expect(created.succeeded)

    // kIOReturnBadArgument, as a signed IOReturn.
    let failure = Int32(bitPattern: 0xE000_02C2)
    let failed = try #require(
      targetCreation(from: targetCreated(target: 9, status: failure).scsiController())
    )
    #expect(failed.target == 9)
    #expect(failed.status == failure)
    #expect(!failed.succeeded)
  }

  @Test
  func rejectsMalformedTargetCreationResults() throws {
    let valid = targetCreated(target: 4).payload
    #expect(throws: SCSIControllerRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0B02, payload: Array(valid.dropLast())).scsiController()
    }
    #expect(throws: SCSIControllerRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0B02, payload: valid + [0]).scsiController()
    }
    #expect(throws: SCSIControllerRuntimeError.invalidPayload) {
      try targetCreated(target: 4, reserved: 1).scsiController()
    }
    // A creation payload under another event type is not decoded as a creation result.
    #expect(try DriverEvent(type: 0x0100, payload: valid).scsiController() == nil)
    #expect(throws: SCSIControllerRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0B01, payload: valid).scsiController()
    }
  }

  private func targetCreated(target: UInt64, status: Int32 = 0, reserved: UInt32 = 0) -> DriverEvent
  {
    var payload = Data()
    payload.appendRuntimeInteger(target)
    payload.appendRuntimeInteger(status)
    payload.appendRuntimeInteger(reserved)
    return DriverEvent(type: 0x0B02, payload: Array(payload))
  }

  private func management(
    kind: UInt32,
    target: UInt64,
    logicalUnit: UInt64 = 0,
    taskTag: UInt64 = 0
  ) -> DriverEvent {
    var payload = Data()
    payload.appendRuntimeInteger(kind)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(target)
    payload.appendRuntimeInteger(logicalUnit)
    payload.appendRuntimeInteger(taskTag)
    return DriverEvent(type: 0x0B01, payload: Array(payload))
  }
}

private func parallelTask(from event: SCSIControllerEvent?) -> SCSIParallelTask? {
  guard case .parallelTask(let task) = event else { return nil }
  return task
}

private func targetCreation(from event: SCSIControllerEvent?) -> SCSITargetCreationResult? {
  guard case .targetCreated(let result) = event else { return nil }
  return result
}
