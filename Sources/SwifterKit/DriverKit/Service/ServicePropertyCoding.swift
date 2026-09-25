import Foundation

/// The tagged registry-property encoding shared with `SwifterKitRuntimeServiceProtocol.h`.
///
/// Values are little-endian and nest at most ``maximumDepth`` levels. DriverKit's `OSNumber` is
/// unsigned and has no floating-point form, so `.integer` travels as its 64-bit pattern and
/// decodes as `.unsignedInteger`, and `.real` cannot be encoded.
enum ServicePropertyCoding {
  enum Tag: UInt8 {
    case boolean = 1
    case number = 2
    case string = 3
    case data = 4
    case array = 5
    case dictionary = 6
  }

  /// The deepest nesting either side accepts; a top-level value is at depth 1.
  static let maximumDepth = 8
  /// The longest registry name, which DriverKit stores with a NUL in 128 bytes.
  static let maximumNameLength = 127
  /// The largest command payload that fits one runtime message.
  static let maximumPayloadSize =
    RuntimeSchema.maximumMessageSize - RuntimeSchema.headerSize - RuntimeSchema.commandHeaderSize

  /// Encodes one value.
  static func encode(_ value: DriverProperty) throws -> Data {
    var data = Data()
    try encode(value, into: &data, depth: 1)
    return data
  }

  /// Returns a registry name's UTF-8 bytes after checking its length and that it has no NUL.
  static func nameBytes(_ name: String) throws -> Data {
    let bytes = Data(name.utf8)
    guard !bytes.isEmpty, bytes.count <= maximumNameLength, !bytes.contains(0) else {
      throw ServiceRuntimeError.invalidName(name)
    }
    return bytes
  }

  /// Decodes exactly one value, rejecting malformed input and trailing bytes.
  static func decode(_ data: Data) throws -> DriverProperty {
    var reader = Reader(bytes: [UInt8](data))
    let value = try reader.value(depth: 1)
    guard reader.offset == reader.bytes.count else { throw ServiceRuntimeError.invalidPayload }
    return value
  }

  private static func encode(_ value: DriverProperty, into data: inout Data, depth: Int) throws {
    guard depth <= maximumDepth else { throw ServiceRuntimeError.propertyTooDeep }
    switch value {
    case .boolean(let flag): data.append(contentsOf: [Tag.boolean.rawValue, flag ? 1 : 0])
    case .integer(let number): appendNumber(UInt64(bitPattern: number), into: &data)
    case .unsignedInteger(let number): appendNumber(number, into: &data)
    case .real: throw ServiceRuntimeError.unsupportedProperty
    case .string(let string):
      let bytes = Data(string.utf8)
      guard !bytes.contains(0) else { throw ServiceRuntimeError.unsupportedProperty }
      try appendBytes(bytes, tag: .string, into: &data)
    case .data(let bytes): try appendBytes(bytes, tag: .data, into: &data)
    case .array(let elements):
      try appendCount(elements.count, tag: .array, into: &data)
      for element in elements { try encode(element, into: &data, depth: depth + 1) }
    case .dictionary(let entries):
      try appendCount(entries.count, tag: .dictionary, into: &data)
      for key in entries.keys.sorted() {
        let bytes = Data(key.utf8)
        guard !bytes.isEmpty, !bytes.contains(0) else { throw ServiceRuntimeError.invalidName(key) }
        data.appendRuntimeInteger(UInt32(bytes.count))
        data.append(bytes)
        try encode(entries[key, default: .boolean(false)], into: &data, depth: depth + 1)
      }
    }
    guard data.count <= maximumPayloadSize else { throw ServiceRuntimeError.payloadTooLarge }
  }

  private static func appendNumber(_ value: UInt64, into data: inout Data) {
    data.append(contentsOf: [Tag.number.rawValue, 64])
    data.appendRuntimeInteger(value)
  }

  private static func appendCount(_ count: Int, tag: Tag, into data: inout Data) throws {
    guard count <= maximumPayloadSize else { throw ServiceRuntimeError.payloadTooLarge }
    data.append(tag.rawValue)
    data.appendRuntimeInteger(UInt32(count))
  }

  private static func appendBytes(_ bytes: Data, tag: Tag, into data: inout Data) throws {
    try appendCount(bytes.count, tag: tag, into: &data)
    data.append(bytes)
  }

  private struct Reader {
    let bytes: [UInt8]
    var offset = 0

    var remaining: Int { bytes.count - offset }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
      guard count >= 0, count <= remaining else { throw ServiceRuntimeError.invalidPayload }
      defer { offset += count }
      return bytes[offset..<offset + count]
    }

    mutating func integer<T: FixedWidthInteger>(_: T.Type) throws -> T {
      try take(MemoryLayout<T>.size).reversed().reduce(T(0)) { $0 << 8 | T($1) }
    }

    mutating func value(depth: Int) throws -> DriverProperty {
      guard depth <= ServicePropertyCoding.maximumDepth else {
        throw ServiceRuntimeError.propertyTooDeep
      }
      switch Tag(rawValue: try integer(UInt8.self)) {
      case .boolean:
        let flag = try integer(UInt8.self)
        guard flag <= 1 else { throw ServiceRuntimeError.invalidPayload }
        return .boolean(flag == 1)
      case .number:
        let bits = try integer(UInt8.self)
        let number = try integer(UInt64.self)
        guard [8, 16, 32, 64].contains(bits), bits == 64 || number >> bits == 0 else {
          throw ServiceRuntimeError.invalidPayload
        }
        return .unsignedInteger(number)
      case .string:
        let bytes = try take(Int(integer(UInt32.self)))
        guard !bytes.contains(0), let string = String(bytes: bytes, encoding: .utf8) else {
          throw ServiceRuntimeError.invalidPayload
        }
        return .string(string)
      case .data: return .data(Data(try take(Int(integer(UInt32.self)))))
      case .array:
        let count = Int(try integer(UInt32.self))
        guard count <= remaining / 2 else { throw ServiceRuntimeError.invalidPayload }
        return .array(try (0..<count).map { _ in try value(depth: depth + 1) })
      case .dictionary: return .dictionary(try dictionary(depth: depth))
      case nil: throw ServiceRuntimeError.invalidPayload
      }
    }

    private mutating func dictionary(depth: Int) throws -> [String: DriverProperty] {
      let count = Int(try integer(UInt32.self))
      guard count <= remaining / 7 else { throw ServiceRuntimeError.invalidPayload }
      var entries: [String: DriverProperty] = [:]
      for _ in 0..<count {
        let bytes = try take(Int(integer(UInt32.self)))
        guard !bytes.isEmpty, !bytes.contains(0), let key = String(bytes: bytes, encoding: .utf8),
          entries[key] == nil
        else { throw ServiceRuntimeError.invalidPayload }
        entries[key] = try value(depth: depth + 1)
      }
      return entries
    }
  }
}
