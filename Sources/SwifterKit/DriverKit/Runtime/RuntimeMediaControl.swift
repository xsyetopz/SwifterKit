import Foundation

// The audio and video runtimes encode typed control values and string custom properties with
// one layout. Each family supplies its own limits, opcodes, and errors.

extension Data {
  /// Encodes a typed control value: identifier, kind, word count, a reserved zero, then the words.
  static func runtimeControlPayload(
    identifier: UInt32,
    kind: UInt32,
    values: [UInt32],
    maximumItems: Int,
    invalidValue: some Error
  ) throws -> Data {
    guard !values.isEmpty, values.count <= maximumItems else { throw invalidValue }
    var payload = Data(capacity: 16 + values.count * 4)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(kind)
    payload.appendRuntimeInteger(UInt32(values.count))
    payload.appendRuntimeInteger(UInt32(0))
    for value in values { payload.appendRuntimeInteger(value) }
    return payload
  }

  /// Decodes the kind and words of a typed control value encoded like
  /// ``runtimeControlPayload(identifier:kind:values:maximumItems:invalidValue:)``.
  func readRuntimeControlWords(
    maximumItems: Int,
    invalidPayload: some Error
  ) throws -> (kind: UInt32, values: [UInt32]) {
    guard count >= 16 else { throw invalidPayload }
    let kind: UInt32 = try readRuntimeInteger(at: 4)
    let itemCount: UInt32 = try readRuntimeInteger(at: 8)
    let reserved: UInt32 = try readRuntimeInteger(at: 12)
    guard reserved == 0, itemCount <= maximumItems, count == 16 + Int(itemCount) * 4 else {
      throw invalidPayload
    }
    let values: [UInt32] = try (0..<Int(itemCount)).map { try readRuntimeInteger(at: 16 + $0 * 4) }
    return (kind, values)
  }
}

extension DriverCommand {
  /// Reads (`value` is `nil`) or writes a string custom property for one qualifier.
  static func runtimeCustomPropertyCommand(
    opcode: RuntimeOpcode,
    requiredCapabilities: RuntimeCapabilities,
    identifier: UInt32,
    qualifier: String,
    value: String?,
    nameMaximumLength: Int,
    valueMaximumLength: Int,
    invalidValue: some Error
  ) throws -> Self {
    let qualifierBytes = Data(qualifier.utf8)
    let valueBytes = value.map { Data($0.utf8) } ?? Data()
    guard !qualifierBytes.isEmpty, qualifierBytes.count <= nameMaximumLength,
      valueBytes.count <= valueMaximumLength, !qualifier.contains("\0"),
      value?.contains("\0") != true
    else { throw invalidValue }
    var payload = Data(capacity: 16 + qualifierBytes.count + valueBytes.count)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(UInt32(qualifierBytes.count))
    payload.appendRuntimeInteger(UInt32(valueBytes.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(qualifierBytes)
    payload.append(valueBytes)
    return Self(
      opcode: opcode,
      requiredCapabilities: requiredCapabilities,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + valueMaximumLength
    )
  }
}
