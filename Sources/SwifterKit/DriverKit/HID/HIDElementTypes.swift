import Foundation

/// The kind of a HID element, from `IOHIDElementType`.
public struct HIDElementType: RawRepresentable, Sendable, Hashable {
  /// The `IOHIDElementType` value.
  public let rawValue: UInt32

  /// Creates an element type from its `IOHIDElementType` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// A miscellaneous input.
  public static let inputMisc = Self(rawValue: 1)
  /// A button input.
  public static let inputButton = Self(rawValue: 2)
  /// An axis input.
  public static let inputAxis = Self(rawValue: 3)
  /// A scan-code input.
  public static let inputScanCodes = Self(rawValue: 4)
  /// An input with no usage, such as padding.
  public static let inputNull = Self(rawValue: 5)
  /// An output.
  public static let output = Self(rawValue: 129)
  /// A feature.
  public static let feature = Self(rawValue: 257)
  /// A collection of other elements.
  public static let collection = Self(rawValue: 513)

  /// Whether the element carries device-to-host input.
  public var isInput: Bool { (1...5).contains(rawValue) }
}

/// The kind of a HID collection element, from `IOHIDElementCollectionType`.
public struct HIDElementCollectionType: RawRepresentable, Sendable, Hashable {
  /// The `IOHIDElementCollectionType` value.
  public let rawValue: UInt32

  /// Creates a collection type from its `IOHIDElementCollectionType` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// A physical collection.
  public static let physical = Self(rawValue: 0)
  /// An application collection.
  public static let application = Self(rawValue: 1)
  /// A logical collection.
  public static let logical = Self(rawValue: 2)
  /// A report collection.
  public static let report = Self(rawValue: 3)
  /// A named-array collection.
  public static let namedArray = Self(rawValue: 4)
  /// A usage-switch collection.
  public static let usageSwitch = Self(rawValue: 5)
  /// A usage-modifier collection.
  public static let usageModifier = Self(rawValue: 6)
}

/// How `IOHIDElement` scales a value before returning it.
public enum HIDValueScaleType: UInt32, Sendable, Hashable {
  /// Scaled to the calibrated range.
  case calibrated = 0
  /// Scaled to the physical range.
  case physical = 1
  /// Scaled by the unit exponent.
  case exponent = 2
}

/// Whether an element commit reads from or writes to the device.
public enum HIDElementCommitDirection: UInt32, Sendable, Hashable {
  /// Issues a get-report and updates the element's value.
  case input = 0
  /// Issues a set-report with the element's value.
  case output = 1
}

/// One element of the provider interface's element tree, as `IOHIDElement` reports it.
///
/// Values are the raw `uint32_t` values `IOHIDElement` returns. Signed logical and physical
/// limits keep their two's-complement bit patterns.
public struct HIDElement: Sendable, Hashable {
  /// The element's cookie, unique within the interface.
  public let cookie: UInt32
  /// The parent collection's cookie, or `nil` for a root element.
  public let parentCookie: UInt32?
  /// The element type.
  public let type: HIDElementType
  /// The collection type. Meaningful when ``type`` is ``HIDElementType/collection``.
  public let collectionType: HIDElementCollectionType
  /// The usage page.
  public let usagePage: UInt32
  /// The usage.
  public let usage: UInt32
  /// The logical minimum.
  public let logicalMinimum: UInt32
  /// The logical maximum.
  public let logicalMaximum: UInt32
  /// The physical minimum.
  public let physicalMinimum: UInt32
  /// The physical maximum.
  public let physicalMaximum: UInt32
  /// The HID unit.
  public let unit: UInt32
  /// The HID unit exponent.
  public let unitExponent: UInt32
  /// The report identifier, or zero when the device uses none.
  public let reportID: UInt32
  /// The size of one report field in bits.
  public let reportSize: UInt32
  /// The number of report fields.
  public let reportCount: UInt32
  /// The HID main-item flags.
  public let flags: UInt32
  /// The most recent value.
  public let value: UInt32
  /// When the value last changed, in mach absolute time.
  public let timestamp: UInt64

  static let encodedSize = 80

  init(runtimePayload data: Data, at offset: Int) throws {
    func word(_ index: Int) throws -> UInt32 { try data.readRuntimeInteger(at: offset + index * 4) }
    guard try word(17) == 0, try word(0) != 0 else { throw HIDRuntimeError.invalidElementPayload }
    cookie = try word(0)
    let parent = try word(1)
    parentCookie = parent == 0 ? nil : parent
    type = HIDElementType(rawValue: try word(2))
    collectionType = HIDElementCollectionType(rawValue: try word(3))
    usagePage = try word(4)
    usage = try word(5)
    logicalMinimum = try word(6)
    logicalMaximum = try word(7)
    physicalMinimum = try word(8)
    physicalMaximum = try word(9)
    unit = try word(10)
    unitExponent = try word(11)
    reportID = try word(12)
    reportSize = try word(13)
    reportCount = try word(14)
    flags = try word(15)
    value = try word(16)
    timestamp = try data.readRuntimeInteger(at: offset + 72)
  }
}

/// One page of the provider interface's element tree.
public struct HIDElementPage: Sendable, Hashable {
  /// The number of elements the interface has.
  public let totalCount: UInt32
  /// The elements in this page, in interface order.
  public let elements: [HIDElement]

  init(runtimePayload data: Data, maximumCount: UInt32) throws {
    let totalCount: UInt32 = try data.readRuntimeInteger(at: 0)
    let count: UInt32 = try data.readRuntimeInteger(at: 4)
    guard count <= maximumCount, count <= totalCount,
      data.count == 8 + Int(count) * HIDElement.encodedSize
    else { throw HIDRuntimeError.invalidElementPayload }
    self.totalCount = totalCount
    elements = try (0..<Int(count)).map {
      try HIDElement(runtimePayload: data, at: 8 + $0 * HIDElement.encodedSize)
    }
  }
}

/// An element's value read through `IOHIDElement`.
public struct HIDElementValue: Sendable, Hashable {
  /// `getValue`'s result.
  public let value: UInt32
  /// `getScaledValue`'s result for the requested scale.
  public let scaledValue: UInt32
  /// `getScaledFixedValue`'s result for the requested scale.
  public let scaledFixedValue: Double
  /// `getTimeStamp`'s result, in mach absolute time.
  public let timestamp: UInt64

  init(runtimePayload data: Data) throws {
    guard data.count == 24, try data.readRuntimeInteger(at: 12) as UInt32 == 0 else {
      throw HIDRuntimeError.invalidElementPayload
    }
    value = try data.readRuntimeInteger(at: 0)
    scaledValue = try data.readRuntimeInteger(at: 4)
    scaledFixedValue = HIDFixed.double(try data.readRuntimeInteger(at: 8))
    timestamp = try data.readRuntimeInteger(at: 16)
  }
}

/// Input element values one report updated, from ``DriverEvent/hidElementValues()``.
public struct HIDElementValues: Sendable, Hashable {
  /// The report's timestamp, in mach absolute time.
  public let timestamp: UInt64
  /// The report identifier.
  public let reportID: UInt32
  /// The new value of each updated element, keyed by cookie.
  public let values: [UInt32: UInt32]

  init(runtimePayload data: Data) throws {
    guard data.count >= 16 else { throw HIDRuntimeError.invalidEventPayload }
    timestamp = try data.readRuntimeInteger(at: 0)
    reportID = try data.readRuntimeInteger(at: 8)
    let count = Int(try data.readRuntimeInteger(at: 12) as UInt32)
    guard count > 0, count <= RuntimeHIDLimits.maximumEventValues, data.count == 16 + count * 8
    else { throw HIDRuntimeError.invalidEventPayload }
    var values: [UInt32: UInt32] = [:]
    for index in 0..<count {
      values[try data.readRuntimeInteger(at: 16 + index * 8)] = try data.readRuntimeInteger(
        at: 20 + index * 8
      )
    }
    guard values.count == count else { throw HIDRuntimeError.invalidEventPayload }
    self.values = values
  }
}

/// Conversions between `Double` and DriverKit's 16.16 `IOFixed`.
enum HIDFixed {
  static func raw(_ value: Double) throws -> Int32 {
    let scaled = (value * 65_536).rounded()
    guard value.isFinite, scaled >= Double(Int32.min), scaled <= Double(Int32.max) else {
      throw HIDRuntimeError.valueOutOfRange
    }
    return Int32(scaled)
  }

  static func double(_ raw: Int32) -> Double { Double(raw) / 65_536 }
}
