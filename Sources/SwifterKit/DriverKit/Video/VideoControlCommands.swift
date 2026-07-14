import Foundation

private func videoWireKind(of value: VideoControlValue) -> UInt32 {
  switch value {
  case .boolean: 1
  case .direction: 7
  case .decibels: 2
  case .scalar: 3
  case .selector: 4
  case .slider: 5
  case .stereoPan: 6
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
    guard runtimePayload.count >= 16 else { throw VideoRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let count: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 12)
    guard reserved == 0, count <= 32, runtimePayload.count == 16 + Int(count) * 4 else {
      throw VideoRuntimeError.invalidPayload
    }
    let values: [UInt32] = try (0..<Int(count)).map {
      try runtimePayload.readRuntimeInteger(at: 16 + $0 * 4)
    }
    switch kind {
    case 1 where values == [0]: self = .boolean(false)
    case 1 where values == [1]: self = .boolean(true)
    case 2 where values.count == 1: self = .decibels(Float(bitPattern: values[0]))
    case 3 where values.count == 1: self = .scalar(Float(bitPattern: values[0]))
    case 4: self = .selector(values)
    case 5 where values.count == 1: self = .slider(values[0])
    case 6 where values.count == 1: self = .stereoPan(Float(bitPattern: values[0]))
    case 7 where values == [0]: self = .direction(false)
    case 7 where values == [1]: self = .direction(true)
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
      opcode: 0x0C07,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 144
    )
  }

  /// Writes one typed control value.
  public static func videoSetControl(identifier: UInt32, value: VideoControlValue) throws -> Self {
    let values = videoWireValues(of: value)
    guard !values.isEmpty, values.count <= 32 else { throw VideoRuntimeError.invalidControlValue }
    var payload = Data(capacity: 16 + values.count * 4)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(videoWireKind(of: value))
    payload.appendRuntimeInteger(UInt32(values.count))
    payload.appendRuntimeInteger(UInt32(0))
    for value in values { payload.appendRuntimeInteger(value) }
    return Self(
      opcode: 0x0C08,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads a string custom property for one qualifier.
  public static func videoGetCustomProperty(identifier: UInt32, qualifier: String) throws -> Self {
    try videoCustomPropertyCommand(
      opcode: 0x0C09,
      identifier: identifier,
      qualifier: qualifier,
      value: nil
    )
  }

  /// Writes a string custom property for one qualifier.
  public static func videoSetCustomProperty(identifier: UInt32, qualifier: String, value: String)
    throws -> Self
  {
    try videoCustomPropertyCommand(
      opcode: 0x0C0A,
      identifier: identifier,
      qualifier: qualifier,
      value: value
    )
  }

  private static func videoCustomPropertyCommand(
    opcode: UInt32,
    identifier: UInt32,
    qualifier: String,
    value: String?
  ) throws -> Self {
    let qualifierBytes = Data(qualifier.utf8)
    let valueBytes = value.map { Data($0.utf8) } ?? Data()
    guard !qualifierBytes.isEmpty, qualifierBytes.count <= 255, valueBytes.count <= 4_096,
      !qualifier.contains("\0"), value?.contains("\0") != true
    else { throw VideoRuntimeError.invalidCustomPropertyValue }
    var payload = Data(capacity: 16 + qualifierBytes.count + valueBytes.count)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(UInt32(qualifierBytes.count))
    payload.appendRuntimeInteger(UInt32(valueBytes.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(qualifierBytes)
    payload.append(valueBytes)
    return Self(
      opcode: opcode,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 4_096
    )
  }
}

extension DriverContext {
  /// Reads one control using the requested value representation.
  public func videoControl(identifier: UInt32, as kind: VideoControlValueKind) async throws
    -> VideoControlValue
  {
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
  public func videoSetCustomProperty(identifier: UInt32, qualifier: String, value: String)
    async throws
  {
    _ = try await execute(
      .videoSetCustomProperty(identifier: identifier, qualifier: qualifier, value: value)
    )
  }
}
