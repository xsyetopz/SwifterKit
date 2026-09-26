import Foundation

extension DriverCommand {
  /// Reads the identity of a VideoDriverKit object.
  public static func videoObjectInfo(_ target: VideoObjectTarget) throws -> Self {
    Self(
      opcode: .videoGetObjectInfo,
      requiredCapabilities: .video,
      payload: try videoTargetPayload(target),
      maximumResponseSize: RuntimeMessage.headerSize + 32 + 255 + 255
    )
  }

  /// Renames a VideoDriverKit object with `SetName`.
  public static func videoSetObjectName(_ target: VideoObjectTarget, name: String) throws -> Self {
    let bytes = try videoName(name)
    var payload = try videoTargetPayload(target)
    payload.appendRuntimeInteger(UInt32(bytes.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(bytes)
    return Self(
      opcode: .videoSetObjectName,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads an element name, category name, or number name from an object.
  public static func videoElementName(
    _ target: VideoObjectTarget,
    kind: VideoElementNameKind,
    element: UInt32,
    scope: VideoObjectScope
  ) throws -> Self {
    Self(
      opcode: .videoGetElementName,
      requiredCapabilities: .video,
      payload: try videoElementPayload(target, kind, element, scope, length: 0),
      maximumResponseSize: RuntimeMessage.headerSize + 255
    )
  }

  /// Sets an element name, category name, or number name on an object.
  public static func videoSetElementName(
    _ target: VideoObjectTarget,
    kind: VideoElementNameKind,
    element: UInt32,
    scope: VideoObjectScope,
    name: String
  ) throws -> Self {
    let bytes = try videoName(name)
    var payload = try videoElementPayload(target, kind, element, scope, length: UInt32(bytes.count))
    payload.append(bytes)
    return Self(
      opcode: .videoSetElementName,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Tells the host that properties of an object changed, through `PropertiesChanged`.
  public static func videoPropertiesChanged(
    _ target: VideoObjectTarget,
    selectors: [UInt32]
  ) throws -> Self {
    guard target != .driver, (1...32).contains(selectors.count), !selectors.contains(0) else {
      throw VideoRuntimeError.invalidPropertySelectors
    }
    var payload = try videoTargetPayload(target)
    payload.appendRuntimeInteger(UInt32(selectors.count))
    payload.appendRuntimeInteger(UInt32(0))
    for selector in selectors { payload.appendRuntimeInteger(selector) }
    return Self(
      opcode: .videoPropertiesChanged,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads a box's state.
  public static func videoBoxState(_ box: UInt32) throws -> Self {
    Self(
      opcode: .videoGetBoxState,
      requiredCapabilities: .video,
      payload: try videoTargetPayload(.box(box)),
      maximumResponseSize: RuntimeMessage.headerSize + 16
    )
  }

  /// Changes one box property.
  public static func videoSetBoxProperty(_ box: UInt32, _ property: VideoBoxProperty) throws -> Self
  {
    let fields = property.runtimeFields
    return Self(
      opcode: .videoSetBoxProperty,
      requiredCapabilities: .video,
      payload: try videoIndexedPayload(.box(box), fields.selector, fields.value),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Adds the device or a clock device to a box, or removes it.
  public static func videoSetBoxOwnership(
    _ box: UInt32,
    target: VideoObjectTarget,
    owned: Bool
  ) throws -> Self {
    switch target {
    case .device, .clockDevice: break
    default: throw VideoRuntimeError.invalidObjectTarget
    }
    var payload = try videoTargetPayload(.box(box))
    let fields = try target.validated().runtimeFields
    payload.appendRuntimeInteger(fields.kind)
    payload.appendRuntimeInteger(fields.index)
    payload.appendRuntimeInteger(UInt32(owned ? 1 : 0))
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: .videoSetBoxOwnership,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads the clock state of the video device or a clock device.
  public static func videoClockDeviceState(_ target: VideoObjectTarget) throws -> Self {
    switch target {
    case .device, .clockDevice: break
    default: throw VideoRuntimeError.invalidObjectTarget
    }
    return Self(
      opcode: .videoGetClockDeviceState,
      requiredCapabilities: .video,
      payload: try videoTargetPayload(target),
      maximumResponseSize: RuntimeMessage.headerSize + 80 + VideoClockDeviceState.maximumSampleRates
        * 8
    )
  }

  /// Changes one clock-device property.
  public static func videoSetClockDeviceProperty(
    _ index: UInt32,
    _ property: VideoClockDeviceProperty
  ) throws -> Self {
    let fields = property.runtimeFields
    return Self(
      opcode: .videoSetClockDeviceProperty,
      requiredCapabilities: .video,
      payload: try videoIndexedPayload(.clockDevice(index), fields.selector, fields.value),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Replaces a clock device's available clock rates.
  public static func videoSetClockSampleRates(
    _ index: UInt32,
    _ sampleRates: [Double]
  ) throws -> Self {
    guard (1...VideoClockDeviceState.maximumSampleRates).contains(sampleRates.count),
      Set(sampleRates).count == sampleRates.count, sampleRates.allSatisfy(isValidVideoRate)
    else { throw VideoRuntimeError.invalidSampleRates }
    var payload = try videoTargetPayload(.clockDevice(index))
    payload.appendRuntimeInteger(UInt32(sampleRates.count))
    payload.appendRuntimeInteger(UInt32(0))
    for rate in sampleRates { payload.appendRuntimeInteger(rate.bitPattern) }
    return Self(
      opcode: .videoSetClockSampleRates,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reports a hardware-derived zero timestamp for a clock device.
  public static func videoUpdateClockTimestamp(
    _ index: UInt32,
    sampleTime: UInt64,
    hostTime: UInt64
  ) throws -> Self {
    var payload = try videoTargetPayload(.clockDevice(index))
    payload.appendRuntimeInteger(sampleTime)
    payload.appendRuntimeInteger(hostTime)
    return Self(
      opcode: .videoUpdateClockTimestamp,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Requests a host-coordinated clock-rate change on a clock device.
  public static func videoRequestClockSampleRate(
    _ index: UInt32,
    _ sampleRate: Double
  ) throws -> Self {
    guard isValidVideoRate(sampleRate) else { throw VideoRuntimeError.invalidSampleRates }
    return Self(
      opcode: .videoRequestClockSampleRate,
      requiredCapabilities: .video,
      payload: try videoIndexedPayload(.clockDevice(index), 0, sampleRate.bitPattern),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Answers a required ``VideoObjectEvent`` request.
  ///
  /// The box takes the requested acquired state before its callback reports success, as
  /// `IOUserVideoBox` requires. Accepting a box request keeps that state; rejecting it restores
  /// the previous state and calls `SetAcquisitionFailure` with `failure`, or `kIOReturnError`
  /// when `failure` is zero. A clock device likewise takes the requested sample rate before its
  /// callback reports success. Accepting a clock-rate request keeps that rate and reports
  /// `clockDeviceSampleRateChanged`; rejecting it restores the previous rate through a device
  /// configuration change, unless the rate changed again.
  public static func videoCompleteRequest(
    requestID: UInt32,
    accept: Bool,
    failure: Int32 = 0
  ) throws -> Self {
    guard requestID != 0, !accept || failure == 0 else { throw VideoRuntimeError.invalidPayload }
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(UInt32(accept ? 1 : 0))
    payload.appendRuntimeInteger(failure)
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: .videoCompleteRequest,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Sends `BufferQueueChange` or `OutputBufferNotification` for a device stream.
  ///
  /// The driver passes the device and stream object IDs; VideoDriverKit documents no
  /// constraints on `changeAction`, so the runtime forwards it unchanged.
  public static func videoNotifyBufferQueue(
    _ notification: VideoBufferQueueNotification,
    streamIndex: UInt32,
    changeAction: UInt64
  ) throws -> Self {
    guard streamIndex < 8 else { throw VideoRuntimeError.invalidStreamIndex }
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(notification.rawValue)
    payload.appendRuntimeInteger(streamIndex)
    payload.appendRuntimeInteger(changeAction)
    return Self(
      opcode: .videoNotifyBufferQueue,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Adds a configured custom property to the device or the driver, or removes it.
  ///
  /// A property must be detached before it moves to another owner.
  public static func videoSetCustomPropertyOwner(
    _ identifier: UInt32,
    owner: VideoCustomPropertyOwner
  ) throws -> Self {
    guard identifier != 0 else { throw VideoRuntimeError.invalidCustomPropertyValue }
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(owner.rawValue)
    payload.appendRuntimeInteger(UInt64(0))
    return Self(
      opcode: .videoSetCustomPropertyOwner,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  private static func isValidVideoRate(_ rate: Double) -> Bool { rate.isFinite && rate > 0 }

  private static func videoTargetPayload(_ target: VideoObjectTarget) throws -> Data {
    let fields = try target.validated().runtimeFields
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(fields.kind)
    payload.appendRuntimeInteger(fields.index)
    return payload
  }

  private static func videoIndexedPayload(
    _ target: VideoObjectTarget,
    _ selector: UInt32,
    _ value: UInt64
  ) throws -> Data {
    var payload = try videoTargetPayload(target)
    payload.appendRuntimeInteger(selector)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(value)
    return payload
  }

  private static func videoElementPayload(
    _ target: VideoObjectTarget,
    _ kind: VideoElementNameKind,
    _ element: UInt32,
    _ scope: VideoObjectScope,
    length: UInt32
  ) throws -> Data {
    guard target != .driver else { throw VideoRuntimeError.invalidObjectTarget }
    var payload = try videoTargetPayload(target)
    payload.appendRuntimeInteger(kind.rawValue)
    payload.appendRuntimeInteger(element)
    payload.appendRuntimeInteger(scope.rawValue)
    payload.appendRuntimeInteger(length)
    return payload
  }

  private static func videoName(_ name: String) throws -> Data {
    let bytes = Data(name.utf8)
    guard !bytes.isEmpty, bytes.count <= 255, !bytes.contains(0) else {
      throw VideoRuntimeError.invalidName
    }
    return bytes
  }
}

extension DriverContext {
  /// Reads the identity of a VideoDriverKit object.
  public func videoObjectInfo(_ target: VideoObjectTarget) async throws -> VideoObjectInfo {
    try VideoObjectInfo(runtimePayload: await execute(.videoObjectInfo(target)))
  }

  /// Renames a VideoDriverKit object.
  public func videoSetObjectName(_ target: VideoObjectTarget, name: String) async throws {
    _ = try await execute(.videoSetObjectName(target, name: name))
  }

  /// Reads an element name, category name, or number name.
  public func videoElementName(
    _ target: VideoObjectTarget,
    kind: VideoElementNameKind,
    element: UInt32,
    scope: VideoObjectScope = .global
  ) async throws -> String {
    let data = try await execute(
      .videoElementName(target, kind: kind, element: element, scope: scope)
    )
    guard data.count <= 255, let name = String(data: data, encoding: .utf8) else {
      throw VideoRuntimeError.invalidPayload
    }
    return name
  }

  /// Sets an element name, category name, or number name.
  public func videoSetElementName(
    _ target: VideoObjectTarget,
    kind: VideoElementNameKind,
    element: UInt32,
    scope: VideoObjectScope = .global,
    name: String
  ) async throws {
    _ = try await execute(
      .videoSetElementName(target, kind: kind, element: element, scope: scope, name: name)
    )
  }

  /// Tells the host that properties of an object changed.
  public func videoPropertiesChanged(_ target: VideoObjectTarget, selectors: [UInt32]) async throws
  { _ = try await execute(.videoPropertiesChanged(target, selectors: selectors)) }

  /// Reads a box's state.
  public func videoBoxState(_ box: UInt32) async throws -> VideoBoxState {
    try VideoBoxState(runtimePayload: await execute(.videoBoxState(box)))
  }

  /// Changes one box property.
  public func videoSetBoxProperty(_ box: UInt32, _ property: VideoBoxProperty) async throws {
    _ = try await execute(.videoSetBoxProperty(box, property))
  }

  /// Adds the device or a clock device to a box, or removes it.
  public func videoSetBoxOwnership(
    _ box: UInt32,
    target: VideoObjectTarget,
    owned: Bool
  ) async throws { _ = try await execute(.videoSetBoxOwnership(box, target: target, owned: owned)) }

  /// Reads the clock state of the video device or a clock device.
  public func videoClockDeviceState(
    _ target: VideoObjectTarget
  ) async throws -> VideoClockDeviceState {
    try VideoClockDeviceState(runtimePayload: await execute(.videoClockDeviceState(target)))
  }

  /// Changes one clock-device property.
  public func videoSetClockDeviceProperty(
    _ index: UInt32,
    _ property: VideoClockDeviceProperty
  ) async throws { _ = try await execute(.videoSetClockDeviceProperty(index, property)) }

  /// Replaces a clock device's available clock rates.
  public func videoSetClockSampleRates(_ index: UInt32, _ sampleRates: [Double]) async throws {
    _ = try await execute(.videoSetClockSampleRates(index, sampleRates))
  }

  /// Reports a hardware-derived zero timestamp for a clock device.
  public func videoUpdateClockTimestamp(
    _ index: UInt32,
    sampleTime: UInt64,
    hostTime: UInt64
  ) async throws {
    _ = try await execute(
      .videoUpdateClockTimestamp(index, sampleTime: sampleTime, hostTime: hostTime)
    )
  }

  /// Requests a host-coordinated clock-rate change on a clock device.
  public func videoRequestClockSampleRate(_ index: UInt32, _ sampleRate: Double) async throws {
    _ = try await execute(.videoRequestClockSampleRate(index, sampleRate))
  }

  /// Answers a required ``VideoObjectEvent`` request.
  public func videoCompleteRequest(requestID: UInt32, accept: Bool, failure: Int32 = 0) async throws
  {
    _ = try await execute(
      .videoCompleteRequest(requestID: requestID, accept: accept, failure: failure)
    )
  }

  /// Sends `BufferQueueChange` or `OutputBufferNotification` for a device stream.
  public func videoNotifyBufferQueue(
    _ notification: VideoBufferQueueNotification,
    streamIndex: UInt32,
    changeAction: UInt64
  ) async throws {
    _ = try await execute(
      .videoNotifyBufferQueue(notification, streamIndex: streamIndex, changeAction: changeAction)
    )
  }

  /// Adds a configured custom property to the device or the driver, or removes it.
  public func videoSetCustomPropertyOwner(
    _ identifier: UInt32,
    owner: VideoCustomPropertyOwner
  ) async throws { _ = try await execute(.videoSetCustomPropertyOwner(identifier, owner: owner)) }
}

extension DriverEvent {
  /// Decodes a VideoDriverKit driver, box, or clock-device event.
  public func videoObject() throws -> VideoObjectEvent? {
    guard type == RuntimeEventType.videoObject.rawValue else { return nil }
    return try VideoObjectEvent(runtimePayload: Data(payload))
  }
}
