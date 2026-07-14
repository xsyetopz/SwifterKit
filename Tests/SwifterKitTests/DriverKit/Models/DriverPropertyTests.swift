import Foundation
import Testing

@testable import SwifterKit

@Suite struct DriverPropertyTests {
  @Test func valuesAreHashable() {
    let values: Set<DriverProperty> = [
      .boolean(true), .integer(-1), .unsignedInteger(1), .real(1.5), .string("value"),
      .data(Data([1, 2])), .array([.integer(1)]), .dictionary(["key": .string("value")]),
    ]
    #expect(values.count == 8)
  }

  @Test func decodesFoundationPropertyList() {
    let value = DriverProperty.decode([
      "enabled": true, "name": "driver", "data": Data([0xAA]), "items": [1, 2],
    ])

    #expect(
      value
        == .dictionary([
          "enabled": .boolean(true), "name": .string("driver"), "data": .data(Data([0xAA])),
          "items": .array([.integer(1), .integer(2)]),
        ])
    )
  }

  @Test func rejectsUnsupportedValues() { #expect(DriverProperty.decode(Date()) == nil) }
}
