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
    for index in 0..<RuntimeSCSILimits.maximumFeatureRequests {
      payload.appendRuntimeInteger(
        index < completion.featureResults.count ? completion.featureResults[index].rawValue : 0
      )
    }
    payload.append(contentsOf: completion.senseData)
    return Self(
      opcode: .scsiCompleteParallelTask,
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
    switch RuntimeEventType(rawValue: type) {
    case .scsiParallelTask?:
      return .parallelTask(try SCSIParallelTask(runtimePayload: Data(payload)))
    case .scsiManagement?: return try SCSIControllerEvent(managementPayload: Data(payload))
    case .scsiTargetCreated?:
      return .targetCreated(try SCSITargetCreationResult(runtimePayload: Data(payload)))
    default: return nil
    }
  }
}

extension SCSIParallelTask {
  init(runtimePayload data: Data) throws {
    guard data.count == 100 else { throw SCSIControllerRuntimeError.invalidPayload }
    let requestCount: UInt32 = try data.readRuntimeInteger(at: 4)
    let commandSize = Int(data[54])
    guard requestCount <= RuntimeSCSILimits.maximumFeatureRequests,
      (1...RuntimeSCSILimits.commandDescriptorBlockMaximumSize).contains(commandSize), data[55] == 0
    else { throw SCSIControllerRuntimeError.invalidPayload }
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
    switch RuntimeSCSIManagementKind(rawValue: kind) {
    case .initializeTarget?: self = .initializeTarget(target)
    case .abortTask?:
      self = .taskManagement(
        .abortTask(targetIdentifier: target, logicalUnit: logicalUnit, taskTag: taskTag)
      )
    case .abortTaskSet?:
      self = .taskManagement(.abortTaskSet(targetIdentifier: target, logicalUnit: logicalUnit))
    case .clearACA?:
      self = .taskManagement(
        .clearAutoContingentAllegiance(targetIdentifier: target, logicalUnit: logicalUnit)
      )
    case .clearTaskSet?:
      self = .taskManagement(.clearTaskSet(targetIdentifier: target, logicalUnit: logicalUnit))
    case .logicalUnitReset?:
      self = .taskManagement(.logicalUnitReset(targetIdentifier: target, logicalUnit: logicalUnit))
    case .targetReset?: self = .taskManagement(.targetReset(targetIdentifier: target))
    case nil: throw SCSIControllerRuntimeError.invalidEventKind(kind)
    }
  }
}
