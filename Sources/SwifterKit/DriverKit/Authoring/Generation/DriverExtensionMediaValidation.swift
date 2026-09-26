import Foundation

extension DriverExtensionGenerator {
  /// Whether every identifier is nonzero and unique.
  static func hasUniqueNonzeroIdentifiers(_ identifiers: [UInt32]) -> Bool {
    identifiers.allSatisfy { $0 != 0 } && Set(identifiers).count == identifiers.count
  }

  /// Whether a level control's decibel range is finite and contains its initial value.
  static func isValidMediaLevel(initial: Float, minimum: Float, maximum: Float) -> Bool {
    initial.isFinite && minimum.isFinite && maximum.isFinite && minimum <= initial
      && initial <= maximum
  }

  /// Whether a selector control's items and initial selections fit the runtime tables.
  static func isValidMediaSelector(
    values: [UInt32],
    names: [String],
    initialValues: [UInt32],
    maximum: Int,
    isValidName: (String) -> Bool
  ) -> Bool {
    !values.isEmpty && values.count <= maximum && Set(values).count == values.count
      && !initialValues.isEmpty && initialValues.count <= maximum
      && Set(initialValues).count == initialValues.count
      && initialValues.allSatisfy(Set(values).contains) && names.allSatisfy(isValidName)
  }

  /// Whether string-backed custom properties have unique identifiers and fit the runtime buffers.
  static func areValidMediaCustomProperties(
    _ properties: [(identifier: UInt32, selector: UInt32, values: [String: String])],
    valueMaximumLength: Int,
    isValidName: (String) -> Bool
  ) -> Bool {
    hasUniqueNonzeroIdentifiers(properties.map(\.identifier))
      && properties.allSatisfy { property in
        property.selector != 0 && !property.values.isEmpty && property.values.count <= 32
          && property.values.allSatisfy { qualifier, data in
            isValidName(qualifier) && !data.contains("\0") && data.utf8.count <= valueMaximumLength
          }
      }
  }
}
