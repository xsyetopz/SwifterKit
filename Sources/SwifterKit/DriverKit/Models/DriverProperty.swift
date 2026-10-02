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
  ///
  /// DriverKit's `OSNumber` is an unsigned integer and has no floating-point form, so the
  /// extension cannot hold this value. Commands that send properties to the extension, such as
  /// ``DriverContext/setServiceProperties(_:)`` and ``DriverContext/watchServices(matching:)``,
  /// throw ``ServiceRuntimeError/unsupportedProperty`` for it. Generation throws
  /// ``DriverExtensionGenerationError/invalidHIDConfiguration`` when
  /// ``USBHIDDeviceConfiguration/deviceProperties`` contains it. Host-side matching and registry
  /// reads support it.
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
}
