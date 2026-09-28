import Foundation

extension DriverCommand {
  /// Reads the identity of an AudioDriverKit object.
  public static func audioObjectInfo(_ target: AudioObjectTarget) throws -> Self {
    Self(
      opcode: .audioGetObjectInfo,
      requiredCapabilities: .audio,
      payload: try audioTargetPayload(target),
      maximumResponseSize: RuntimeMessage.headerSize + 32 + RuntimeAudioLimits.nameMaximumLength * 2
    )
  }

  /// Renames an AudioDriverKit object with `SetName`.
  public static func audioSetObjectName(_ target: AudioObjectTarget, name: String) throws -> Self {
    let bytes = try audioName(name)
    var payload = try audioTargetPayload(target)
    payload.appendRuntimeInteger(UInt32(bytes.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(bytes)
    return Self(
      opcode: .audioSetObjectName,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads an element name, category name, or number name from an object.
  public static func audioElementName(
    _ target: AudioObjectTarget,
    kind: AudioElementNameKind,
    element: UInt32,
    scope: AudioObjectScope
  ) throws -> Self {
    Self(
      opcode: .audioGetElementName,
      requiredCapabilities: .audio,
      payload: try audioElementPayload(target, kind, element, scope, length: 0),
      maximumResponseSize: RuntimeMessage.headerSize + RuntimeAudioLimits.nameMaximumLength
    )
  }

  /// Sets an element name, category name, or number name on an object.
  public static func audioSetElementName(
    _ target: AudioObjectTarget,
    kind: AudioElementNameKind,
    element: UInt32,
    scope: AudioObjectScope,
    name: String
  ) throws -> Self {
    let bytes = try audioName(name)
    var payload = try audioElementPayload(target, kind, element, scope, length: UInt32(bytes.count))
    payload.append(bytes)
    return Self(
      opcode: .audioSetElementName,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Tells the host that properties of an object changed, through `PropertiesChanged`.
  public static func audioPropertiesChanged(
    _ target: AudioObjectTarget,
    selectors: [UInt32]
  ) throws -> Self {
    guard target != .driver,
      (1...RuntimeAudioLimits.maximumChangedProperties).contains(selectors.count),
      !selectors.contains(0)
    else { throw AudioRuntimeError.invalidPropertySelectors }
    var payload = try audioTargetPayload(target)
    payload.appendRuntimeInteger(UInt32(selectors.count))
    payload.appendRuntimeInteger(UInt32(0))
    for selector in selectors { payload.appendRuntimeInteger(selector) }
    return Self(
      opcode: .audioPropertiesChanged,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads a box's state.
  public static func audioBoxState(_ box: UInt32) throws -> Self {
    Self(
      opcode: .audioGetBoxState,
      requiredCapabilities: .audio,
      payload: try audioTargetPayload(.box(box)),
      maximumResponseSize: RuntimeMessage.headerSize + 16
    )
  }

  /// Changes one box property.
  public static func audioSetBoxProperty(_ box: UInt32, _ property: AudioBoxProperty) throws -> Self
  {
    let fields = property.runtimeFields
    return Self(
      opcode: .audioSetBoxProperty,
      requiredCapabilities: .audio,
      payload: try audioIndexedPayload(.box(box), fields.selector, fields.value),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Adds the device or a clock device to a box, or removes it.
  public static func audioSetBoxOwnership(
    _ box: UInt32,
    target: AudioObjectTarget,
    owned: Bool
  ) throws -> Self {
    switch target {
    case .device, .clockDevice: break
    default: throw AudioRuntimeError.invalidObjectTarget
    }
    var payload = try audioTargetPayload(.box(box))
    let fields = try target.validated().runtimeFields
    payload.appendRuntimeInteger(fields.kind)
    payload.appendRuntimeInteger(fields.index)
    payload.appendRuntimeInteger(UInt32(owned ? 1 : 0))
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: .audioSetBoxOwnership,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads the clock state of the audio device or a clock device.
  public static func audioClockDeviceState(_ target: AudioObjectTarget) throws -> Self {
    switch target {
    case .device, .clockDevice: break
    default: throw AudioRuntimeError.invalidObjectTarget
    }
    return Self(
      opcode: .audioGetClockDeviceState,
      requiredCapabilities: .audio,
      payload: try audioTargetPayload(target),
      maximumResponseSize: RuntimeMessage.headerSize + 80 + RuntimeAudioLimits
        .maximumReportedSampleRates * 8
    )
  }

  /// Changes one clock-device property.
  public static func audioSetClockDeviceProperty(
    _ index: UInt32,
    _ property: AudioClockDeviceProperty
  ) throws -> Self {
    if case .zeroTimestampPeriod(let period) = property,
      !(RuntimeAudioLimits.minimumZeroTimestampPeriod...RuntimeAudioLimits.maximumFrameCount)
        .contains(Int(period))
    {
      throw AudioRuntimeError.invalidPayload
    }
    let fields = property.runtimeFields
    return Self(
      opcode: .audioSetClockDeviceProperty,
      requiredCapabilities: .audio,
      payload: try audioIndexedPayload(.clockDevice(index), fields.selector, fields.value),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Replaces a clock device's available sample rates.
  public static func audioSetClockSampleRates(
    _ index: UInt32,
    _ sampleRates: [Double]
  ) throws -> Self {
    guard (1...RuntimeAudioLimits.maximumSampleRates).contains(sampleRates.count),
      Set(sampleRates).count == sampleRates.count, sampleRates.allSatisfy(isValidAudioRate)
    else { throw AudioRuntimeError.invalidSampleRates }
    var payload = try audioTargetPayload(.clockDevice(index))
    payload.appendRuntimeInteger(UInt32(sampleRates.count))
    payload.appendRuntimeInteger(UInt32(0))
    for rate in sampleRates { payload.appendRuntimeInteger(rate.bitPattern) }
    return Self(
      opcode: .audioSetClockSampleRates,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reports a hardware-derived zero timestamp for a clock device.
  public static func audioUpdateClockTimestamp(
    _ index: UInt32,
    sampleTime: UInt64,
    hostTime: UInt64
  ) throws -> Self {
    var payload = try audioTargetPayload(.clockDevice(index))
    payload.appendRuntimeInteger(sampleTime)
    payload.appendRuntimeInteger(hostTime)
    return Self(
      opcode: .audioUpdateClockTimestamp,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Requests a host-coordinated sample-rate change on a clock device.
  public static func audioRequestClockSampleRate(
    _ index: UInt32,
    _ sampleRate: Double
  ) throws -> Self {
    guard isValidAudioRate(sampleRate) else { throw AudioRuntimeError.invalidSampleRates }
    return Self(
      opcode: .audioRequestClockSampleRate,
      requiredCapabilities: .audio,
      payload: try audioIndexedPayload(.clockDevice(index), 0, sampleRate.bitPattern),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Answers a required ``AudioObjectEvent`` request.
  ///
  /// The box takes the requested acquired state before its callback reports success, as
  /// `IOUserAudioBox` requires:
  ///
  /// - Accept: the box keeps that state.
  /// - Reject: the box restores the previous state and calls `SetAcquisitionFailure` with
  ///   `failure`, or `kIOReturnError` when `failure` is zero.
  ///
  /// A clock device likewise takes the requested sample rate before its callback reports
  /// success:
  ///
  /// - Accept: the clock device keeps that rate and reports `clockDeviceSampleRateChanged`.
  /// - Reject: the clock device restores the previous rate through a device configuration
  ///   change, unless the rate changed again.
  public static func audioCompleteRequest(
    requestID: UInt32,
    accept: Bool,
    failure: Int32 = 0
  ) throws -> Self {
    guard requestID != 0, !accept || failure == 0 else { throw AudioRuntimeError.invalidPayload }
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(UInt32(accept ? 1 : 0))
    payload.appendRuntimeInteger(failure)
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: .audioCompleteRequest,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  static func isValidAudioRate(_ rate: Double) -> Bool {
    rate.isFinite
      && (RuntimeAudioLimits.minimumSampleRate...RuntimeAudioLimits.maximumSampleRate).contains(
        rate
      )
  }

  private static func audioTargetPayload(_ target: AudioObjectTarget) throws -> Data {
    let fields = try target.validated().runtimeFields
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(fields.kind)
    payload.appendRuntimeInteger(fields.index)
    return payload
  }

  private static func audioIndexedPayload(
    _ target: AudioObjectTarget,
    _ selector: UInt32,
    _ value: UInt64
  ) throws -> Data {
    var payload = try audioTargetPayload(target)
    payload.appendRuntimeInteger(selector)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(value)
    return payload
  }

  private static func audioElementPayload(
    _ target: AudioObjectTarget,
    _ kind: AudioElementNameKind,
    _ element: UInt32,
    _ scope: AudioObjectScope,
    length: UInt32
  ) throws -> Data {
    guard target != .driver else { throw AudioRuntimeError.invalidObjectTarget }
    var payload = try audioTargetPayload(target)
    payload.appendRuntimeInteger(kind.rawValue)
    payload.appendRuntimeInteger(element)
    payload.appendRuntimeInteger(scope.rawValue)
    payload.appendRuntimeInteger(length)
    return payload
  }

  private static func audioName(_ name: String) throws -> Data {
    let bytes = Data(name.utf8)
    guard !bytes.isEmpty, bytes.count <= RuntimeAudioLimits.nameMaximumLength, !bytes.contains(0)
    else { throw AudioRuntimeError.invalidName }
    return bytes
  }
}

extension DriverContext {
  /// Reads the identity of an AudioDriverKit object.
  public func audioObjectInfo(_ target: AudioObjectTarget) async throws -> AudioObjectInfo {
    try AudioObjectInfo(runtimePayload: await execute(.audioObjectInfo(target)))
  }

  /// Renames an AudioDriverKit object.
  public func audioSetObjectName(_ target: AudioObjectTarget, name: String) async throws {
    _ = try await execute(.audioSetObjectName(target, name: name))
  }

  /// Reads an element name, category name, or number name.
  public func audioElementName(
    _ target: AudioObjectTarget,
    kind: AudioElementNameKind,
    element: UInt32,
    scope: AudioObjectScope = .global
  ) async throws -> String {
    let data = try await execute(
      .audioElementName(target, kind: kind, element: element, scope: scope)
    )
    guard data.count <= RuntimeAudioLimits.nameMaximumLength,
      let name = String(data: data, encoding: .utf8)
    else { throw AudioRuntimeError.invalidPayload }
    return name
  }

  /// Sets an element name, category name, or number name.
  public func audioSetElementName(
    _ target: AudioObjectTarget,
    kind: AudioElementNameKind,
    element: UInt32,
    scope: AudioObjectScope = .global,
    name: String
  ) async throws {
    _ = try await execute(
      .audioSetElementName(target, kind: kind, element: element, scope: scope, name: name)
    )
  }

  /// Tells the host that properties of an object changed.
  public func audioPropertiesChanged(_ target: AudioObjectTarget, selectors: [UInt32]) async throws
  { _ = try await execute(.audioPropertiesChanged(target, selectors: selectors)) }

  /// Reads a box's state.
  public func audioBoxState(_ box: UInt32) async throws -> AudioBoxState {
    try AudioBoxState(runtimePayload: await execute(.audioBoxState(box)))
  }

  /// Changes one box property.
  public func audioSetBoxProperty(_ box: UInt32, _ property: AudioBoxProperty) async throws {
    _ = try await execute(.audioSetBoxProperty(box, property))
  }

  /// Adds the device or a clock device to a box, or removes it.
  public func audioSetBoxOwnership(
    _ box: UInt32,
    target: AudioObjectTarget,
    owned: Bool
  ) async throws { _ = try await execute(.audioSetBoxOwnership(box, target: target, owned: owned)) }

  /// Reads the clock state of the audio device or a clock device.
  public func audioClockDeviceState(
    _ target: AudioObjectTarget
  ) async throws -> AudioClockDeviceState {
    try AudioClockDeviceState(runtimePayload: await execute(.audioClockDeviceState(target)))
  }

  /// Changes one clock-device property.
  public func audioSetClockDeviceProperty(
    _ index: UInt32,
    _ property: AudioClockDeviceProperty
  ) async throws { _ = try await execute(.audioSetClockDeviceProperty(index, property)) }

  /// Replaces a clock device's available sample rates.
  public func audioSetClockSampleRates(_ index: UInt32, _ sampleRates: [Double]) async throws {
    _ = try await execute(.audioSetClockSampleRates(index, sampleRates))
  }

  /// Reports a hardware-derived zero timestamp for a clock device.
  public func audioUpdateClockTimestamp(
    _ index: UInt32,
    sampleTime: UInt64,
    hostTime: UInt64
  ) async throws {
    _ = try await execute(
      .audioUpdateClockTimestamp(index, sampleTime: sampleTime, hostTime: hostTime)
    )
  }

  /// Requests a host-coordinated sample-rate change on a clock device.
  public func audioRequestClockSampleRate(_ index: UInt32, _ sampleRate: Double) async throws {
    _ = try await execute(.audioRequestClockSampleRate(index, sampleRate))
  }

  /// Answers a required ``AudioObjectEvent`` request.
  public func audioCompleteRequest(requestID: UInt32, accept: Bool, failure: Int32 = 0) async throws
  {
    _ = try await execute(
      .audioCompleteRequest(requestID: requestID, accept: accept, failure: failure)
    )
  }
}

extension DriverEvent {
  /// Decodes an AudioDriverKit driver, box, or clock-device event.
  public func audioObject() throws -> AudioObjectEvent? {
    guard type == RuntimeEventType.audioObject.rawValue else { return nil }
    return try AudioObjectEvent(runtimePayload: Data(payload))
  }
}
