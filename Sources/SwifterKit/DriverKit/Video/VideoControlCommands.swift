import Foundation

private func videoWireKind(of value: VideoControlValue) -> RuntimeVideoValueKind {
  switch value {
  case .boolean: .boolean
  case .direction: .direction
  case .decibels: .decibels
  case .scalar: .scalar
  case .selector: .selector
  case .slider: .slider
  case .stereoPan: .stereoPan
  }
}

private func videoWireValues(of value: VideoControlValue) -> [UInt32] {
  switch value {
  case .boolean(let value), .direction(let value): [value ? 1 : 0]
  case .decibels(let value), .scalar(let value), .stereoPan(let value): [value.bitPattern]
  case .selector(let values): values
  case .slider(let value): [value]
  }
}

extension VideoControlValue {
  init(runtimePayload: Data) throws {
    let (kind, values) = try runtimePayload.readRuntimeControlWords(
      maximumItems: RuntimeVideoLimits.maximumSelectorItems,
      invalidPayload: VideoRuntimeError.invalidPayload
    )
    switch RuntimeVideoValueKind(rawValue: kind) {
    case .boolean where values == [0]: self = .boolean(false)
    case .boolean where values == [1]: self = .boolean(true)
    case .decibels where values.count == 1: self = .decibels(Float(bitPattern: values[0]))
    case .scalar where values.count == 1: self = .scalar(Float(bitPattern: values[0]))
    case .selector: self = .selector(values)
    case .slider where values.count == 1: self = .slider(values[0])
    case .stereoPan where values.count == 1: self = .stereoPan(Float(bitPattern: values[0]))
    case .direction where values == [0]: self = .direction(false)
    case .direction where values == [1]: self = .direction(true)
    default: throw VideoRuntimeError.invalidPayload
    }
  }
}

extension DriverCommand {
  /// Reads one control using the requested value representation.
  public static func videoGetControl(identifier: UInt32, as kind: VideoControlValueKind) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(kind.rawValue)
    return Self(
      opcode: .videoGetControl,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 16 + RuntimeVideoLimits.maximumSelectorItems
        * 4
    )
  }

  /// Writes one typed control value.
  public static func videoSetControl(identifier: UInt32, value: VideoControlValue) throws -> Self {
    Self(
      opcode: .videoSetControl,
      requiredCapabilities: .video,
      payload: try .runtimeControlPayload(
        identifier: identifier,
        kind: videoWireKind(of: value).rawValue,
        values: videoWireValues(of: value),
        maximumItems: RuntimeVideoLimits.maximumSelectorItems,
        invalidValue: VideoRuntimeError.invalidControlValue
      ),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads a string custom property for one qualifier.
  public static func videoGetCustomProperty(identifier: UInt32, qualifier: String) throws -> Self {
    try videoCustomPropertyCommand(
      opcode: .videoGetCustomProperty,
      identifier: identifier,
      qualifier: qualifier,
      value: nil
    )
  }

  /// Writes a string custom property for one qualifier.
  public static func videoSetCustomProperty(
    identifier: UInt32,
    qualifier: String,
    value: String
  ) throws -> Self {
    try videoCustomPropertyCommand(
      opcode: .videoSetCustomProperty,
      identifier: identifier,
      qualifier: qualifier,
      value: value
    )
  }

  private static func videoCustomPropertyCommand(
    opcode: RuntimeOpcode,
    identifier: UInt32,
    qualifier: String,
    value: String?
  ) throws -> Self {
    try runtimeCustomPropertyCommand(
      opcode: opcode,
      requiredCapabilities: .video,
      identifier: identifier,
      qualifier: qualifier,
      value: value,
      nameMaximumLength: RuntimeVideoLimits.nameMaximumLength,
      valueMaximumLength: RuntimeVideoLimits.customPropertyValueMaximumLength,
      invalidValue: VideoRuntimeError.invalidCustomPropertyValue
    )
  }
}

extension DriverContext {
  /// Reads one control using the requested value representation.
  public func videoControl(
    identifier: UInt32,
    as kind: VideoControlValueKind
  ) async throws -> VideoControlValue {
    try VideoControlValue(
      runtimePayload: await execute(.videoGetControl(identifier: identifier, as: kind))
    )
  }

  /// Writes one typed control value.
  public func videoSetControl(identifier: UInt32, value: VideoControlValue) async throws {
    _ = try await execute(.videoSetControl(identifier: identifier, value: value))
  }

  /// Reads a string custom property for one qualifier.
  public func videoCustomProperty(identifier: UInt32, qualifier: String) async throws -> String {
    let data = try await execute(
      .videoGetCustomProperty(identifier: identifier, qualifier: qualifier)
    )
    guard let value = String(data: data, encoding: .utf8) else {
      throw VideoRuntimeError.invalidPayload
    }
    return value
  }

  /// Writes a string custom property for one qualifier.
  public func videoSetCustomProperty(
    identifier: UInt32,
    qualifier: String,
    value: String
  ) async throws {
    _ = try await execute(
      .videoSetCustomProperty(identifier: identifier, qualifier: qualifier, value: value)
    )
  }
}
