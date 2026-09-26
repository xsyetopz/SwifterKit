import Foundation

private func audioWireKind(of value: AudioControlValue) -> RuntimeAudioValueKind {
  switch value {
  case .boolean: .boolean
  case .decibels: .decibels
  case .scalar: .scalar
  case .selector: .selector
  case .slider: .slider
  case .stereoPan: .stereoPan
  }
}

private func audioWireValues(of value: AudioControlValue) -> [UInt32] {
  switch value {
  case .boolean(let value): [value ? 1 : 0]
  case .decibels(let value), .scalar(let value), .stereoPan(let value): [value.bitPattern]
  case .selector(let values): values
  case .slider(let value): [value]
  }
}

extension AudioControlValue {
  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 16 else { throw AudioRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let count: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 12)
    guard reserved == 0, count <= RuntimeAudioLimits.maximumSelectorItems,
      runtimePayload.count == 16 + Int(count) * 4
    else { throw AudioRuntimeError.invalidPayload }
    let values: [UInt32] = try (0..<Int(count)).map {
      try runtimePayload.readRuntimeInteger(at: 16 + $0 * 4)
    }
    switch RuntimeAudioValueKind(rawValue: kind) {
    case .boolean where values == [0]: self = .boolean(false)
    case .boolean where values == [1]: self = .boolean(true)
    case .decibels where values.count == 1: self = .decibels(Float(bitPattern: values[0]))
    case .scalar where values.count == 1: self = .scalar(Float(bitPattern: values[0]))
    case .selector: self = .selector(values)
    case .slider where values.count == 1: self = .slider(values[0])
    case .stereoPan where values.count == 1: self = .stereoPan(Float(bitPattern: values[0]))
    default: throw AudioRuntimeError.invalidPayload
    }
  }
}

extension DriverCommand {
  /// Reads one control using the requested value representation.
  public static func audioGetControl(identifier: UInt32, as kind: AudioControlValueKind) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(kind.rawValue)
    return Self(
      opcode: .audioGetControl,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 16 + RuntimeAudioLimits.maximumSelectorItems
        * 4
    )
  }

  /// Writes one typed control value.
  public static func audioSetControl(identifier: UInt32, value: AudioControlValue) throws -> Self {
    let values = audioWireValues(of: value)
    guard !values.isEmpty, values.count <= RuntimeAudioLimits.maximumSelectorItems else {
      throw AudioRuntimeError.invalidControlValue
    }
    var payload = Data(capacity: 16 + values.count * 4)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(audioWireKind(of: value).rawValue)
    payload.appendRuntimeInteger(UInt32(values.count))
    payload.appendRuntimeInteger(UInt32(0))
    for value in values { payload.appendRuntimeInteger(value) }
    return Self(
      opcode: .audioSetControl,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads a string custom property for one qualifier.
  public static func audioGetCustomProperty(identifier: UInt32, qualifier: String) throws -> Self {
    try audioCustomPropertyCommand(
      opcode: .audioGetCustomProperty,
      identifier: identifier,
      qualifier: qualifier,
      value: nil
    )
  }

  /// Writes a string custom property for one qualifier.
  public static func audioSetCustomProperty(
    identifier: UInt32,
    qualifier: String,
    value: String
  ) throws -> Self {
    try audioCustomPropertyCommand(
      opcode: .audioSetCustomProperty,
      identifier: identifier,
      qualifier: qualifier,
      value: value
    )
  }

  private static func audioCustomPropertyCommand(
    opcode: RuntimeOpcode,
    identifier: UInt32,
    qualifier: String,
    value: String?
  ) throws -> Self {
    let qualifierBytes = Data(qualifier.utf8)
    let valueBytes = value.map { Data($0.utf8) } ?? Data()
    guard !qualifierBytes.isEmpty, qualifierBytes.count <= RuntimeAudioLimits.nameMaximumLength,
      valueBytes.count <= RuntimeAudioLimits.customPropertyValueMaximumLength,
      !qualifier.contains("\0"), value?.contains("\0") != true
    else { throw AudioRuntimeError.invalidCustomPropertyValue }
    var payload = Data(capacity: 16 + qualifierBytes.count + valueBytes.count)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(UInt32(qualifierBytes.count))
    payload.appendRuntimeInteger(UInt32(valueBytes.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(qualifierBytes)
    payload.append(valueBytes)
    return Self(
      opcode: opcode,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
        + RuntimeAudioLimits.customPropertyValueMaximumLength
    )
  }
}

extension DriverContext {
  /// Reads one control using the requested value representation.
  public func audioControl(
    identifier: UInt32,
    as kind: AudioControlValueKind
  ) async throws -> AudioControlValue {
    try AudioControlValue(
      runtimePayload: await execute(.audioGetControl(identifier: identifier, as: kind))
    )
  }

  /// Writes one typed control value.
  public func audioSetControl(identifier: UInt32, value: AudioControlValue) async throws {
    _ = try await execute(.audioSetControl(identifier: identifier, value: value))
  }

  /// Reads a string custom property for one qualifier.
  public func audioCustomProperty(identifier: UInt32, qualifier: String) async throws -> String {
    let data = try await execute(
      .audioGetCustomProperty(identifier: identifier, qualifier: qualifier)
    )
    guard let value = String(data: data, encoding: .utf8) else {
      throw AudioRuntimeError.invalidPayload
    }
    return value
  }

  /// Writes a string custom property for one qualifier.
  public func audioSetCustomProperty(
    identifier: UInt32,
    qualifier: String,
    value: String
  ) async throws {
    _ = try await execute(
      .audioSetCustomProperty(identifier: identifier, qualifier: qualifier, value: value)
    )
  }
}
