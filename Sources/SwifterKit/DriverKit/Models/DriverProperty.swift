import Foundation

/// A Sendable property-list value used for registry matching and inspection.
public indirect enum DriverProperty: Sendable, Hashable {
  /// A Boolean property.
  case boolean(Bool)
  /// A signed integer property.
  case integer(Int64)
  /// An unsigned integer property.
  case unsignedInteger(UInt64)
  /// A floating-point property.
  case real(Double)
  /// A string property.
  case string(String)
  /// A binary property.
  case data(Data)
  /// An ordered collection.
  case array([Self])
  /// A string-keyed collection.
  case dictionary([String: Self])
}

extension DriverProperty {
  var foundationValue: Any {
    switch self {
    case .boolean(let value): value
    case .integer(let value): value
    case .unsignedInteger(let value): value
    case .real(let value): value
    case .string(let value): value
    case .data(let value): value
    case .array(let values): values.map(\.foundationValue)
    case .dictionary(let values): values.mapValues(\.foundationValue)
    }
  }

  static func decode(_ value: Any) -> DriverProperty? {
    if let value = value as? Bool { return .boolean(value) }
    if let value = decodeNumber(value) { return value }
    if let value = value as? String { return .string(value) }
    if let value = value as? Data { return .data(value) }
    if let values = value as? [Any] { return .array(values.compactMap(Self.decode)) }
    if let values = value as? [String: Any] {
      return .dictionary(values.compactMapValues(Self.decode))
    }
    return nil
  }

  private static func decodeNumber(_ value: Any) -> DriverProperty? {
    let object = value as AnyObject
    guard let encoding = object.objCType, let signedValue = object.int64Value,
      let unsignedValue = object.uint64Value, let realValue = object.doubleValue
    else { return nil }

    let type = String(cString: encoding)
    if type == "f" || type == "d" { return .real(realValue) }
    if type == "Q" || type == "I" || type == "S" || type == "C" {
      return .unsignedInteger(unsignedValue)
    }
    return .integer(signedValue)
  }
}
