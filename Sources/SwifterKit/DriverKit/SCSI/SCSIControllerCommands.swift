import Foundation

extension DriverCommand {
  /// Completes a pending non-bundled SCSI parallel task.
  public static func completeSCSIParallelTask(_ completion: SCSIParallelTaskCompletion) -> Self {
    var payload = Data(capacity: 48 + completion.senseData.count)
    payload.appendRuntimeInteger(completion.requestID)
    payload.appendRuntimeInteger(UInt32(completion.featureResults.count))
    payload.appendRuntimeInteger(completion.taskStatus.rawValue)
    payload.appendRuntimeInteger(completion.serviceResponse.rawValue)
    payload.appendRuntimeInteger(completion.bytesTransferred)
    payload.appendRuntimeInteger(UInt32(completion.senseData.count))
    for index in 0..<5 {
      payload.appendRuntimeInteger(
        index < completion.featureResults.count ? completion.featureResults[index].rawValue : 0
      )
    }
    payload.append(contentsOf: completion.senseData)
    return Self(
      opcode: 0x0B00,
      requiredCapabilities: .scsi,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }
}

extension DriverContext {
  /// Completes a pending non-bundled SCSI parallel task.
  public func completeSCSIParallelTask(_ completion: SCSIParallelTaskCompletion) async throws {
    _ = try await execute(.completeSCSIParallelTask(completion))
  }
}

extension DriverEvent {
  /// Decodes a SCSIControllerDriverKit callback.
  public func scsiController() throws -> SCSIControllerEvent? {
    switch type {
    case 0x0B00: return .parallelTask(try SCSIParallelTask(runtimePayload: Data(payload)))
    case 0x0B01: return try SCSIControllerEvent(managementPayload: Data(payload))
    default: return nil
    }
  }
}

extension SCSIParallelTask {
  init(runtimePayload data: Data) throws {
    guard data.count == 100 else { throw SCSIControllerRuntimeError.invalidPayload }
    let requestCount: UInt32 = try data.readRuntimeInteger(at: 4)
    let commandSize = Int(data[54])
    guard requestCount <= 5, (1...16).contains(commandSize), data[55] == 0 else {
      throw SCSIControllerRuntimeError.invalidPayload
    }
    requestID = try data.readRuntimeInteger(at: 0)
    targetIdentifier = try data.readRuntimeInteger(at: 8)
    controllerTaskIdentifier = try data.readRuntimeInteger(at: 16)
    requestedTransferCount = try data.readRuntimeInteger(at: 24)
    bufferIOVMAddress = try data.readRuntimeInteger(at: 32)
    taskTagIdentifier = try data.readRuntimeInteger(at: 40)
    timeoutMilliseconds = try data.readRuntimeInteger(at: 48)
    taskAttribute = SCSITaskAttribute(rawValue: UInt32(data[52]))
    transferDirection = SCSIDataTransferDirection(rawValue: UInt32(data[53]))
    logicalUnitBytes = Array(data[56..<64])
    commandDescriptorBlock = Array(data[64..<(64 + commandSize)])
    featureRequests = try (0..<Int(requestCount)).map { index in
      SCSIParallelFeatureRequest(rawValue: try data.readRuntimeInteger(at: 80 + index * 4))
    }
  }
}

extension SCSIControllerEvent {
  init(managementPayload data: Data) throws {
    guard data.count == 32, try data.readRuntimeInteger(at: 4) as UInt32 == 0 else {
      throw SCSIControllerRuntimeError.invalidPayload
    }
    let kind: UInt32 = try data.readRuntimeInteger(at: 0)
    let target: UInt64 = try data.readRuntimeInteger(at: 8)
    let logicalUnit: UInt64 = try data.readRuntimeInteger(at: 16)
    let taskTag: UInt64 = try data.readRuntimeInteger(at: 24)
    switch kind {
    case 1: self = .initializeTarget(target)
    case 2:
      self = .taskManagement(
        .abortTask(targetIdentifier: target, logicalUnit: logicalUnit, taskTag: taskTag)
      )
    case 3:
      self = .taskManagement(.abortTaskSet(targetIdentifier: target, logicalUnit: logicalUnit))
    case 4:
      self = .taskManagement(
        .clearAutoContingentAllegiance(targetIdentifier: target, logicalUnit: logicalUnit)
      )
    case 5:
      self = .taskManagement(.clearTaskSet(targetIdentifier: target, logicalUnit: logicalUnit))
    case 6:
      self = .taskManagement(.logicalUnitReset(targetIdentifier: target, logicalUnit: logicalUnit))
    case 7: self = .taskManagement(.targetReset(targetIdentifier: target))
    default: throw SCSIControllerRuntimeError.invalidEventKind(kind)
    }
  }
}
