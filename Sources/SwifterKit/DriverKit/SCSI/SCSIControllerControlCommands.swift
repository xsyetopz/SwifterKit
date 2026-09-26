import Foundation

extension DriverCommand {
  /// Creates a target-presence query through `UserTargetPresentForID`.
  public static func scsiTargetPresent(_ target: UInt64) -> Self {
    scsiControl(.scsiTargetPresent, payload: targetPayload(target), responseSize: 4)
  }

  /// Creates a target through `UserCreateTargetForID` with string target properties.
  public static func scsiCreateTarget(
    _ target: UInt64,
    properties: [SCSIProtocolPropertyKey: String] = [:]
  ) throws -> Self {
    scsiControl(
      .scsiCreateTarget,
      payload: try propertyPayload(target: target, properties: properties, allowsEmpty: true)
    )
  }

  /// Destroys a target through `UserDestroyTargetForID`.
  public static func scsiDestroyTarget(_ target: UInt64) -> Self {
    scsiControl(.scsiDestroyTarget, payload: targetPayload(target))
  }

  /// Sets HBA properties through `UserSetHBAProperties`.
  public static func scsiSetControllerProperties(
    _ properties: [SCSIProtocolPropertyKey: String]
  ) throws -> Self {
    scsiControl(
      .scsiSetControllerProperties,
      payload: try propertyPayload(target: 0, properties: properties, allowsEmpty: false)
    )
  }

  /// Removes HBA properties through `UserRemoveHBAProperties`.
  public static func scsiRemoveControllerProperties(
    _ keys: [SCSIProtocolPropertyKey]
  ) throws -> Self {
    scsiControl(.scsiRemoveControllerProperties, payload: try removalPayload(target: 0, keys: keys))
  }

  /// Sets target properties through `UserSetTargetProperties`.
  public static func scsiSetTargetProperties(
    _ properties: [SCSIProtocolPropertyKey: String],
    for target: UInt64
  ) throws -> Self {
    scsiControl(
      .scsiSetTargetProperties,
      payload: try propertyPayload(target: target, properties: properties, allowsEmpty: false)
    )
  }

  /// Removes target properties through `UserRemoveTargetProperties`.
  public static func scsiRemoveTargetProperties(
    _ keys: [SCSIProtocolPropertyKey],
    for target: UInt64
  ) throws -> Self {
    scsiControl(
      .scsiRemoveTargetProperties,
      payload: try removalPayload(target: target, keys: keys)
    )
  }

  /// Propagates a media-parameter change through `UserCallMediaParametersHaveChanged`.
  public static let scsiMediaParametersChanged = scsiControl(
    .scsiMediaParametersChanged,
    payload: Data()
  )

  /// Reads bytes from the data buffer of a pending parallel task.
  public static func scsiReadTaskData(requestID: UInt32, offset: UInt64, count: Int) throws -> Self
  {
    guard requestID != 0, (1...SCSIControllerLimits.maximumTaskDataReadLength).contains(count)
    else { throw SCSIControllerRuntimeError.invalidDataRange }
    return scsiControl(
      .scsiReadTaskData,
      payload: taskDataPayload(requestID: requestID, offset: offset, count: count),
      responseSize: count
    )
  }

  /// Writes bytes into the data buffer of a pending parallel task.
  public static func scsiWriteTaskData(
    requestID: UInt32,
    offset: UInt64,
    bytes: [UInt8]
  ) throws -> Self {
    guard requestID != 0,
      (1...SCSIControllerLimits.maximumTaskDataWriteLength).contains(bytes.count)
    else { throw SCSIControllerRuntimeError.invalidDataRange }
    var payload = taskDataPayload(requestID: requestID, offset: offset, count: bytes.count)
    payload.append(contentsOf: bytes)
    return scsiControl(.scsiWriteTaskData, payload: payload)
  }

  private static func scsiControl(
    _ opcode: RuntimeOpcode,
    payload: Data,
    responseSize: Int = 0
  ) -> Self {
    Self(
      opcode: opcode,
      requiredCapabilities: .scsi,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + responseSize
    )
  }

  private static func targetPayload(_ target: UInt64) -> Data {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(target)
    return payload
  }

  private static func taskDataPayload(requestID: UInt32, offset: UInt64, count: Int) -> Data {
    var payload = Data(capacity: 16 + count)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(UInt32(count))
    payload.appendRuntimeInteger(offset)
    return payload
  }

  private static func propertyPayload(
    target: UInt64,
    properties: [SCSIProtocolPropertyKey: String],
    allowsEmpty: Bool
  ) throws -> Data {
    guard allowsEmpty || !properties.isEmpty,
      properties.count <= SCSIControllerLimits.maximumPropertyCount
    else { throw SCSIControllerRuntimeError.invalidPropertyUpdate }
    var payload = propertyHeader(target: target, count: properties.count)
    for (key, value) in properties.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
      let keyBytes = try validatedKey(key)
      let valueBytes = Array(value.utf8)
      guard valueBytes.count <= SCSIControllerLimits.maximumPropertyValueLength,
        !valueBytes.contains(0)
      else { throw SCSIControllerRuntimeError.invalidPropertyUpdate }
      payload.appendRuntimeInteger(UInt16(keyBytes.count))
      payload.appendRuntimeInteger(UInt16(valueBytes.count))
      payload.append(contentsOf: keyBytes)
      payload.append(contentsOf: valueBytes)
    }
    return payload
  }

  private static func removalPayload(target: UInt64, keys: [SCSIProtocolPropertyKey]) throws -> Data
  {
    guard !keys.isEmpty, keys.count <= SCSIControllerLimits.maximumPropertyCount,
      Set(keys).count == keys.count
    else { throw SCSIControllerRuntimeError.invalidPropertyUpdate }
    var payload = propertyHeader(target: target, count: keys.count)
    for key in keys {
      let keyBytes = try validatedKey(key)
      payload.appendRuntimeInteger(UInt16(keyBytes.count))
      payload.appendRuntimeInteger(UInt16(0))
      payload.append(contentsOf: keyBytes)
    }
    return payload
  }

  private static func propertyHeader(target: UInt64, count: Int) -> Data {
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(target)
    payload.appendRuntimeInteger(UInt32(count))
    payload.appendRuntimeInteger(UInt32(0))
    return payload
  }

  private static func validatedKey(_ key: SCSIProtocolPropertyKey) throws -> [UInt8] {
    let bytes = Array(key.rawValue.utf8)
    guard (1...SCSIControllerLimits.maximumPropertyKeyLength).contains(bytes.count),
      !bytes.contains(0)
    else { throw SCSIControllerRuntimeError.invalidPropertyUpdate }
    return bytes
  }
}

extension DriverContext {
  /// Returns whether DriverKit reports a target present for `target`.
  public func scsiTargetPresent(_ target: UInt64) async throws -> Bool {
    let payload = try await execute(.scsiTargetPresent(target))
    guard payload.count == 4 else { throw SCSIControllerRuntimeError.invalidPayload }
    switch try payload.readRuntimeInteger(at: 0) as UInt32 {
    case 0: return false
    case 1: return true
    default: throw SCSIControllerRuntimeError.invalidPayload
    }
  }

  /// Requests a target; returns once the extension has validated the properties and queued the
  /// create.
  ///
  /// The extension runs `UserCreateTargetForID` on its own queue, because DriverKit probes the
  /// new target with parallel tasks that Swift completes through the same connection. Keep
  /// handling ``DriverEvent/scsiController()`` events, including
  /// ``SCSIControllerEvent/initializeTarget(_:)`` and parallel tasks. When
  /// `UserCreateTargetForID` returns, a ``SCSIControllerEvent/targetCreated(_:)`` event carries
  /// the target and its `IOReturn` status, so a failed create is reported there rather than
  /// thrown here. A call that throws queues nothing and delivers no such event. The event is
  /// required: with no host connected it waits for the next one, and it is lost only when the
  /// host disconnects before taking it or leaves the extension's required event queue full.
  public func scsiCreateTarget(
    _ target: UInt64,
    properties: [SCSIProtocolPropertyKey: String] = [:]
  ) async throws { _ = try await execute(try .scsiCreateTarget(target, properties: properties)) }

  /// Destroys a target created by ``scsiCreateTarget(_:properties:)``.
  public func scsiDestroyTarget(_ target: UInt64) async throws {
    _ = try await execute(.scsiDestroyTarget(target))
  }

  /// Sets HBA registry properties.
  public func scsiSetControllerProperties(
    _ properties: [SCSIProtocolPropertyKey: String]
  ) async throws { _ = try await execute(try .scsiSetControllerProperties(properties)) }

  /// Removes HBA registry properties.
  public func scsiRemoveControllerProperties(_ keys: [SCSIProtocolPropertyKey]) async throws {
    _ = try await execute(try .scsiRemoveControllerProperties(keys))
  }

  /// Sets registry properties on one target.
  public func scsiSetTargetProperties(
    _ properties: [SCSIProtocolPropertyKey: String],
    for target: UInt64
  ) async throws { _ = try await execute(try .scsiSetTargetProperties(properties, for: target)) }

  /// Removes registry properties from one target.
  public func scsiRemoveTargetProperties(
    _ keys: [SCSIProtocolPropertyKey],
    for target: UInt64
  ) async throws { _ = try await execute(try .scsiRemoveTargetProperties(keys, for: target)) }

  /// Tells DriverKit that media parameters changed.
  public func scsiMediaParametersChanged() async throws {
    _ = try await execute(.scsiMediaParametersChanged)
  }

  /// Reads bytes from a pending task's data buffer.
  ///
  /// Requires ``SCSIControllerConfiguration/providesTaskDataBuffers``. The runtime fetches the
  /// buffer with `UserGetDataBuffer` inside `UserProcessParallelTask`, and the header says the
  /// task's ``SCSIParallelTask/bufferIOVMAddress`` mapping is then unusable. The buffer stays
  /// readable until the task completes.
  public func scsiReadTaskData(
    requestID: UInt32,
    offset: UInt64,
    count: Int
  ) async throws -> [UInt8] {
    let payload = try await execute(
      try .scsiReadTaskData(requestID: requestID, offset: offset, count: count)
    )
    guard payload.count == count else { throw SCSIControllerRuntimeError.invalidPayload }
    return Array(payload)
  }

  /// Writes bytes into a pending task's data buffer.
  ///
  /// Requires ``SCSIControllerConfiguration/providesTaskDataBuffers``.
  public func scsiWriteTaskData(requestID: UInt32, offset: UInt64, bytes: [UInt8]) async throws {
    _ = try await execute(
      try .scsiWriteTaskData(requestID: requestID, offset: offset, bytes: bytes)
    )
  }
}
