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
    let (kind, values) = try runtimePayload.readRuntimeControlWords(
      maximumItems: RuntimeAudioLimits.maximumSelectorItems,
      invalidPayload: AudioRuntimeError.invalidPayload
    )
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
    Self(
      opcode: .audioSetControl,
      requiredCapabilities: .audio,
      payload: try .runtimeControlPayload(
        identifier: identifier,
        kind: audioWireKind(of: value).rawValue,
        values: audioWireValues(of: value),
        maximumItems: RuntimeAudioLimits.maximumSelectorItems,
        invalidValue: AudioRuntimeError.invalidControlValue
      ),
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
    try runtimeCustomPropertyCommand(
      opcode: opcode,
      requiredCapabilities: .audio,
      identifier: identifier,
      qualifier: qualifier,
      value: value,
      nameMaximumLength: RuntimeAudioLimits.nameMaximumLength,
      valueMaximumLength: RuntimeAudioLimits.customPropertyValueMaximumLength,
      invalidValue: AudioRuntimeError.invalidCustomPropertyValue
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
