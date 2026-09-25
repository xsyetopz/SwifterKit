import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverPropertyTests {
  @Test
  func valuesAreHashable() {
    let values: Set<DriverProperty> = [
      .boolean(true), .integer(-1), .unsignedInteger(1), .real(1.5), .string("value"),
      .data(Data([1, 2])), .array([.integer(1)]), .dictionary(["key": .string("value")]),
    ]
    #expect(values.count == 8)
  }

  #if canImport(IOKit)
    @Test
    func decodesFoundationPropertyList() {
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

    @Test
    func decodesRegistryNumbersByCoreFoundationType() {
      var one: Int32 = 1
      var large = Int64.max
      var real = 1.5
      let values: [(CFNumber?, DriverProperty)] = [
        (CFNumberCreate(nil, .sInt32Type, &one), .integer(1)),
        (CFNumberCreate(nil, .sInt64Type, &large), .integer(.max)),
        (CFNumberCreate(nil, .float64Type, &real), .real(1.5)),
      ]
      for (number, expected) in values { #expect(DriverProperty.decode(number as Any) == expected) }
      #expect(DriverProperty.decode(kCFBooleanFalse as Any) == .boolean(false))
      #expect(DriverProperty.decode(kCFBooleanTrue as Any) == .boolean(true))
    }

    @Test
    func rejectsUnsupportedValues() { #expect(DriverProperty.decode(Date()) == nil) }
  #endif
}
