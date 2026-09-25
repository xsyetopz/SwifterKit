import Foundation

/// Report types a generated HID device answers when the host requests a report.
public struct HIDGetReportTypes: OptionSet, Sendable, Hashable {
  /// The underlying bit mask.
  public let rawValue: UInt32

  /// Creates a get-report type set from its raw bit mask.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Input reports requested by the host.
  public static let input = Self(rawValue: 1 << 0)
  /// Output reports requested by the host.
  public static let output = Self(rawValue: 1 << 1)
  /// Feature reports requested by the host.
  public static let feature = Self(rawValue: 1 << 2)
  /// Every report type.
  public static let all: Self = [.input, .output, .feature]
}

/// One usage page, with an optional usage, that an event service matches.
public struct HIDUsagePair: Sendable, Hashable {
  /// The HID usage page.
  public let usagePage: UInt32
  /// The usage within the page, or `nil` to match every usage on the page.
  public let usage: UInt32?

  /// Creates a usage pair for `DeviceUsagePairs` matching.
  public init(usagePage: UInt32, usage: UInt32? = nil) {
    self.usagePage = usagePage
    self.usage = usage
  }
}

/// Element categories that `IOUserHIDEventDriver` parses and turns into events.
///
/// A category left out of the set is not parsed, so its elements and reports stay with Swift.
public struct HIDEventDriverCategories: OptionSet, Sendable, Hashable {
  /// The underlying bit mask.
  public let rawValue: UInt32

  /// Creates a category set from its raw bit mask.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Keyboard and consumer keys (`parseKeyboardElement`, `handleKeyboardReport`).
  public static let keyboard = Self(rawValue: 1 << 0)
  /// Relative and absolute pointers (`parsePointerElement`, `handleRelativePointerReport`,
  /// `handleAbsolutePointerReport`).
  public static let pointer = Self(rawValue: 1 << 1)
  /// Scroll wheels (`parseScrollElement`, `handleScrollReport`).
  public static let scroll = Self(rawValue: 1 << 2)
  /// LED outputs (`parseLEDElement`).
  public static let led = Self(rawValue: 1 << 3)
  /// Digitizer transducers (`parseDigitizerElement`, `handleDigitizerReport`).
  public static let digitizer = Self(rawValue: 1 << 4)
  /// Proximity sensors (`parseProximityElement`, `handleProximityReport`).
  public static let proximity = Self(rawValue: 1 << 5)
  /// Game controllers (`parseGameControllerElement`, `handleGameControllerReport`).
  public static let gameController = Self(rawValue: 1 << 6)
  /// Elements no other category claims (`parseRemainingElement`).
  public static let remaining = Self(rawValue: 1 << 7)
  /// Every category.
  public static let all: Self = [
    .keyboard, .pointer, .scroll, .led, .digitizer, .proximity, .gameController, .remaining,
  ]
}

/// The HIDDriverKit superclass of a generated HID event service.
public enum HIDEventServiceClass: Sendable, Hashable {
  /// `IOUserHIDEventService`: Swift reads reports or elements and dispatches every event.
  case eventService
  /// `IOUserHIDEventDriver`: Apple's element parser dispatches events for `categories`, and Swift
  /// handles the remaining elements.
  case eventDriver(categories: HIDEventDriverCategories)
}

/// What a generated HID event service forwards to Swift after each input report.
public struct HIDEventDelivery: OptionSet, Sendable, Hashable {
  /// The underlying bit mask.
  public let rawValue: UInt32

  /// Creates a delivery set from its raw bit mask.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Each input report's bytes, as ``DriverEvent/hidInputReport()``.
  public static let reports = Self(rawValue: 1 << 0)
  /// The input element values each report updated, as ``DriverEvent/hidElementValues()``.
  public static let elementValues = Self(rawValue: 1 << 1)
}

/// A generated HID event service that matches an existing `IOHIDInterface`.
///
/// Set ``DriverConfiguration/providerClass`` to ``providerClass``. Event services need a
/// DriverKit 21.0 or later deployment target and match by ``usagePairs``, ``vendorID``, or both.
public struct HIDEventServiceConfiguration: Sendable, Hashable {
  /// The provider class an event service matches.
  public static let providerClass = "IOHIDInterface"
  /// The most usage pairs one personality may list.
  public static let maximumUsagePairs = 32

  /// The generated superclass.
  public let serviceClass: HIDEventServiceClass
  /// `DeviceUsagePairs` matching; empty matches on vendor and product only.
  public let usagePairs: [HIDUsagePair]
  /// The `VendorID` to match, if any.
  public let vendorID: UInt32?
  /// The `ProductID` to match, if any; requires ``vendorID``.
  public let productID: UInt32?
  /// Report data forwarded to Swift.
  public let delivery: HIDEventDelivery

  /// Creates event-service metadata.
  public init(
    serviceClass: HIDEventServiceClass = .eventService,
    usagePairs: [HIDUsagePair] = [],
    vendorID: UInt32? = nil,
    productID: UInt32? = nil,
    delivery: HIDEventDelivery = .reports
  ) {
    self.serviceClass = serviceClass
    self.usagePairs = usagePairs
    self.vendorID = vendorID
    self.productID = productID
    self.delivery = delivery
  }

  var eventDriverCategories: HIDEventDriverCategories {
    if case .eventDriver(let categories) = serviceClass { return categories }
    return []
  }

  var isValid: Bool {
    let pairsValid =
      usagePairs.count <= Self.maximumUsagePairs && Set(usagePairs).count == usagePairs.count
    return pairsValid && (!usagePairs.isEmpty || vendorID != nil)
      && (productID == nil || vendorID != nil) && eventDriverCategories.subtracting(.all).isEmpty
      && delivery.subtracting([.reports, .elementValues]).isEmpty
  }
}

/// A generated `IOUserUSBHostHIDDevice` that drives a USB HID interface.
///
/// The superclass reads the interface's HID descriptor and interrupt pipes. Set
/// ``DriverConfiguration/providerClass`` to ``USBDeviceConfiguration/interfaceProviderClass``,
/// add ``RuntimeCapabilities/usb`` with a ``USBDeviceConfiguration``, and leave
/// ``DriverConfiguration/hidDevice`` `nil`. The superclass owns the interface, so SwifterKit's USB
/// transfer commands report `kIOReturnNotReady` in this mode.
public struct USBHIDDeviceConfiguration: Sendable, Hashable {
  /// A report descriptor that replaces the device's, or `nil` to keep the device's descriptor.
  public let reportDescriptor: [UInt8]?
  /// Properties merged over the device description the superclass builds.
  public let deviceProperties: [String: DriverProperty]
  /// Host set-report types routed to Swift instead of the device.
  public let acceptedHostReportTypes: HIDHostReportTypes
  /// Host get-report types Swift answers instead of the device.
  public let answeredReportTypes: HIDGetReportTypes
  /// Whether the device's input reports are also delivered to Swift.
  public let deliversInputReports: Bool

  /// Creates USB HID device metadata.
  public init(
    reportDescriptor: [UInt8]? = nil,
    deviceProperties: [String: DriverProperty] = [:],
    acceptedHostReportTypes: HIDHostReportTypes = [],
    answeredReportTypes: HIDGetReportTypes = [],
    deliversInputReports: Bool = false
  ) {
    self.reportDescriptor = reportDescriptor
    self.deviceProperties = deviceProperties
    self.acceptedHostReportTypes = acceptedHostReportTypes
    self.answeredReportTypes = answeredReportTypes
    self.deliversInputReports = deliversInputReports
  }

  /// The tagged encoding of ``deviceProperties``, or `nil` when it cannot be encoded.
  var encodedDeviceProperties: [UInt8]? {
    guard !deviceProperties.isEmpty else { return [] }
    guard deviceProperties.keys.allSatisfy({ (try? ServicePropertyCoding.nameBytes($0)) != nil }),
      let data = try? ServicePropertyCoding.encode(.dictionary(deviceProperties)),
      data.count <= 16_384
    else { return nil }
    return [UInt8](data)
  }

  var isValid: Bool {
    let descriptorValid = reportDescriptor.map { !$0.isEmpty && $0.count <= 65_488 } ?? true
    return descriptorValid && encodedDeviceProperties != nil
      && acceptedHostReportTypes.subtracting(.all).isEmpty
      && answeredReportTypes.subtracting(.all).isEmpty
  }
}
