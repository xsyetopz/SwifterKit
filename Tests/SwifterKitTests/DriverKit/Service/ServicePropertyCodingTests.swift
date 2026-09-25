import Foundation
import Testing

@testable import SwifterKit

@Suite
struct ServicePropertyCodingTests {
  @Test
  func encodesTaggedLittleEndianValues() throws {
    #expect(try ServicePropertyCoding.encode(.boolean(true)) == Data([1, 1]))
    #expect(
      try ServicePropertyCoding.encode(.unsignedInteger(0x0102))
        == Data([2, 64, 0x02, 0x01, 0, 0, 0, 0, 0, 0])
    )
    #expect(
      try ServicePropertyCoding.encode(.integer(-1))
        == Data([2, 64] + Array(repeating: 0xFF, count: 8))
    )
    #expect(try ServicePropertyCoding.encode(.string("ab")) == Data([3, 2, 0, 0, 0, 0x61, 0x62]))
    #expect(try ServicePropertyCoding.encode(.data(Data([9]))) == Data([4, 1, 0, 0, 0, 9]))
    #expect(
      try ServicePropertyCoding.encode(.array([.boolean(false)])) == Data([5, 1, 0, 0, 0, 1, 0])
    )
    // Keys are sorted so the encoding is deterministic.
    let dictionary = try ServicePropertyCoding.encode(
      .dictionary(["b": .boolean(true), "a": .boolean(false)])
    )
    #expect(dictionary == Data([6, 2, 0, 0, 0, 1, 0, 0, 0, 0x61, 1, 0, 1, 0, 0, 0, 0x62, 1, 1]))
  }

  @Test
  func roundTripsNestedValues() throws {
    let value = DriverProperty.dictionary([
      "flag": .boolean(true), "count": .unsignedInteger(42), "name": .string("Größe"),
      "bytes": .data(Data([1, 2, 3])), "empty": .data(Data()),
      "list": .array([.string("x"), .dictionary(["inner": .unsignedInteger(7)])]),
    ])
    #expect(try ServicePropertyCoding.decode(ServicePropertyCoding.encode(value)) == value)
    // DriverKit numbers are unsigned, so a signed value returns as its bit pattern.
    #expect(
      try ServicePropertyCoding.decode(ServicePropertyCoding.encode(.integer(-2)))
        == .unsignedInteger(UInt64.max - 1)
    )
  }

  @Test
  func decodesNarrowNativeNumbers() throws {
    #expect(
      try ServicePropertyCoding.decode(Data([2, 8, 0xFF, 0, 0, 0, 0, 0, 0, 0]))
        == .unsignedInteger(255)
    )
    #expect(throws: ServiceRuntimeError.invalidPayload) {
      try ServicePropertyCoding.decode(Data([2, 8, 0, 1, 0, 0, 0, 0, 0, 0]))
    }
    #expect(throws: ServiceRuntimeError.invalidPayload) {
      try ServicePropertyCoding.decode(Data([2, 12, 0, 0, 0, 0, 0, 0, 0, 0]))
    }
  }

  @Test
  func rejectsValuesDriverKitCannotHold() {
    #expect(throws: ServiceRuntimeError.unsupportedProperty) {
      try ServicePropertyCoding.encode(.real(1.5))
    }
    #expect(throws: ServiceRuntimeError.unsupportedProperty) {
      try ServicePropertyCoding.encode(.string("a\0b"))
    }
    #expect(throws: ServiceRuntimeError.invalidName("")) {
      try ServicePropertyCoding.encode(.dictionary(["": .boolean(true)]))
    }
    var nested = DriverProperty.boolean(true)
    for _ in 0..<ServicePropertyCoding.maximumDepth { nested = .array([nested]) }
    #expect(throws: ServiceRuntimeError.propertyTooDeep) {
      try ServicePropertyCoding.encode(nested)
    }
    #expect(throws: ServiceRuntimeError.payloadTooLarge) {
      try ServicePropertyCoding.encode(.data(Data(count: ServicePropertyCoding.maximumPayloadSize)))
    }
  }

  @Test
  func rejectsMalformedReplies() {
    let malformed: [Data] = [
      Data(), Data([7]), Data([1, 2]), Data([1, 1, 0]), Data([3, 2, 0, 0, 0, 0x61]),
      Data([3, 1, 0, 0, 0, 0]), Data([5, 0xFF, 0xFF, 0, 0, 1, 1]),
      Data([6, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1]),
      Data([6, 2, 0, 0, 0, 1, 0, 0, 0, 0x61, 1, 1, 1, 0, 0, 0, 0x61, 1, 0]),
    ]
    for data in malformed {
      #expect(throws: ServiceRuntimeError.invalidPayload) { try ServicePropertyCoding.decode(data) }
    }
    var deep = Data([1, 1])
    for _ in 0..<ServicePropertyCoding.maximumDepth { deep = Data([5, 1, 0, 0, 0]) + deep }
    #expect(throws: ServiceRuntimeError.propertyTooDeep) { try ServicePropertyCoding.decode(deep) }
  }

  @Test
  func validatesRegistryNames() throws {
    #expect(try ServicePropertyCoding.nameBytes("IOService") == Data("IOService".utf8))
    let longest = String(repeating: "n", count: 127)
    #expect(try ServicePropertyCoding.nameBytes(longest).count == 127)
    for name in ["", longest + "n", "a\0"] {
      #expect(throws: ServiceRuntimeError.invalidName(name)) {
        try ServicePropertyCoding.nameBytes(name)
      }
    }
  }
}
