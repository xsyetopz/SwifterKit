// HID wire constants: command limits, element writes, and the report, delivery, category, and
// dispatch-state bits.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeSchema.h`, which
// `SwifterKitRuntimeHIDProtocol.h` and the `SwifterKitRuntimeHID*.cpp` sources read, so neither
// side spells a value twice.

/// Bounds of the HID commands and events.
enum RuntimeHIDLimits {
  /// The host get-report requests Swift may answer at once.
  static let maximumPendingReports = 16
  /// The most element descriptors one `hidCopyElements` response carries.
  static let maximumElementPage = 512
  /// The most cookies one commit names.
  static let maximumCookies = 1_024
  /// The most elements one digitizer collection names.
  static let maximumCollectionElements = 64
  /// The most touches one digitizer dispatch carries.
  static let maximumTouches = 64
  /// The most element values one `hidElementValues` event carries.
  static let maximumEventValues = 256
  /// The usage page `hidSetLED` addresses, the HID LED page.
  static let ledUsagePage: UInt32 = 0x08
  /// How far a digitizer collection's ``RuntimeHIDCollectionChange`` bits sit above its
  /// ``RuntimeHIDCollectionFlag`` bits.
  static let collectionChangeShift: UInt32 = 2
}

/// What a `hidSetElementValue` payload carries; see `SwifterKitHIDElementWrite`.
enum RuntimeHIDElementWriteKind: UInt32, CaseIterable {
  /// An integer value.
  case value = 0
  /// Data bytes that follow the payload.
  case data = 1
}

/// Host set-report types a generated device routes to Swift, `HIDHostReportTypes`.
enum RuntimeHIDHostReportType: UInt32, CaseIterable {
  case output = 0x1
  case feature = 0x2
}

/// Host get-report types a generated device answers from Swift, `HIDGetReportTypes`.
enum RuntimeHIDGetReportType: UInt32, CaseIterable {
  case input = 0x1
  case output = 0x2
  case feature = 0x4
}

/// What an event service forwards after each input report, `HIDEventDelivery`.
enum RuntimeHIDEventDelivery: UInt32, CaseIterable {
  case reports = 0x1
  case elementValues = 0x2
}

/// Element categories an `IOUserHIDEventDriver` parses, `HIDEventDriverCategories`.
enum RuntimeHIDEventDriverCategory: UInt32, CaseIterable {
  case keyboard = 0x1
  case pointer = 0x2
  case scroll = 0x4
  case led = 0x8
  case digitizer = 0x10
  case proximity = 0x20
  case gameController = 0x40
  case remaining = 0x80
}

/// Stylus state bits of `hidDispatchDigitizerStylus`, `HIDStylusState`.
enum RuntimeHIDStylusFlag: UInt32, CaseIterable {
  case inRange = 0x1
  case tip = 0x2
  case barrelSwitch = 0x4
  case invert = 0x8
  case eraser = 0x10
  case tipChanged = 0x20
  case positionChanged = 0x40
  case rangeChanged = 0x80
}

/// Touch state bits of `hidDispatchDigitizerTouches`, `HIDTouchState`.
enum RuntimeHIDTouchFlag: UInt32, CaseIterable {
  case inRange = 0x1
  case touch = 0x2
  case touchValid = 0x4
  case touchChanged = 0x8
  case positionChanged = 0x10
  case rangeChanged = 0x20
}

/// State bits of `hidDispatchDigitizerCollection`, below its change bits.
enum RuntimeHIDCollectionFlag: UInt32, CaseIterable {
  case touch = 0x1
  case inRange = 0x2
}

/// Change bits of `hidDispatchDigitizerCollection`, `HIDDigitizerChanges`, before
/// ``RuntimeHIDLimits/collectionChangeShift``.
enum RuntimeHIDCollectionChange: UInt32, CaseIterable {
  case touch = 0x1
  case position = 0x2
  case range = 0x4
}

/// Thumbstick button bits of the game-controller dispatches.
enum RuntimeHIDGameControllerFlag: UInt32, CaseIterable {
  case thumbstickButtonLeft = 0x1
  case thumbstickButtonRight = 0x2
}

extension CaseIterable where Self: RawRepresentable, RawValue: FixedWidthInteger {
  /// Every case's bit, for a bit-set schema enumeration.
  static var allBits: RawValue { allCases.reduce(0) { $0 | $1.rawValue } }
}
