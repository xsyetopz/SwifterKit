import Foundation

/// The direction and semantics of a HID report.
public enum HIDReportType: UInt32, Sendable, Hashable {
  /// Data produced by a device for the host.
  case input = 0
  /// Data produced by the host for a device.
  case output = 1
  /// Bidirectional device configuration data.
  case feature = 2
}

/// One complete HID report transported through the internal runtime.
public struct HIDReport: Sendable, Hashable {
  /// The monotonic timestamp supplied to HIDDriverKit, or zero for the current time.
  public let timestamp: UInt64
  /// The report direction and semantics.
  public let type: HIDReportType
  /// HIDDriverKit option bits; the low byte may contain the report identifier.
  public let options: UInt32
  /// The complete report bytes expected by the report descriptor.
  public let bytes: [UInt8]

  /// Creates a HID report.
  public init(bytes: [UInt8], type: HIDReportType, options: UInt32 = 0, timestamp: UInt64 = 0) {
    self.timestamp = timestamp
    self.type = type
    self.options = options
    self.bytes = bytes
  }

  func encodedRuntimePayload() throws -> Data {
    guard bytes.count <= Int(UInt32.max) else { throw HIDRuntimeError.reportTooLarge }

    var payload = Data(capacity: 24 + bytes.count)
    payload.appendRuntimeInteger(timestamp)
    payload.appendRuntimeInteger(type.rawValue)
    payload.appendRuntimeInteger(options)
    payload.appendRuntimeInteger(UInt32(bytes.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(contentsOf: bytes)
    return payload
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 24 else { throw HIDRuntimeError.invalidReportPayload }

    let data = Data(runtimePayload)
    let timestamp: UInt64 = try data.readRuntimeInteger(at: 0)
    guard let type = HIDReportType(rawValue: try data.readRuntimeInteger(at: 8)) else {
      throw HIDRuntimeError.invalidReportType
    }
    let options: UInt32 = try data.readRuntimeInteger(at: 12)
    let length = Int(try data.readRuntimeInteger(at: 16) as UInt32)
    guard try data.readRuntimeInteger(at: 20) as UInt32 == 0, length == data.count - 24 else {
      throw HIDRuntimeError.invalidReportPayload
    }

    self.init(bytes: Array(data.suffix(length)), type: type, options: options, timestamp: timestamp)
  }
}

/// Static identity and descriptor data for a generated virtual HID device.
public struct HIDDeviceConfiguration: Sendable, Hashable {
  /// The HID report descriptor returned by the generated extension.
  public let reportDescriptor: [UInt8]
  /// The transport name exposed to HID clients.
  public let transport: String
  /// The vendor identifier exposed to HID clients.
  public let vendorID: UInt32
  /// The product identifier exposed to HID clients.
  public let productID: UInt32
  /// The device version exposed to HID clients.
  public let versionNumber: UInt32
  /// The device country code.
  public let countryCode: UInt32
  /// The registry location identifier.
  public let locationID: UInt32
  /// The manufacturer name.
  public let manufacturer: String
  /// The product name.
  public let product: String
  /// The device serial number.
  public let serialNumber: String
  /// The descriptor's primary usage page.
  public let primaryUsagePage: UInt32
  /// The descriptor's primary usage.
  public let primaryUsage: UInt32

  /// Creates virtual HID device metadata.
  public init(
    reportDescriptor: [UInt8],
    transport: String = "Virtual",
    vendorID: UInt32,
    productID: UInt32,
    versionNumber: UInt32 = 1,
    countryCode: UInt32 = 0,
    locationID: UInt32 = 0,
    manufacturer: String,
    product: String,
    serialNumber: String,
    primaryUsagePage: UInt32,
    primaryUsage: UInt32
  ) {
    self.reportDescriptor = reportDescriptor
    self.transport = transport
    self.vendorID = vendorID
    self.productID = productID
    self.versionNumber = versionNumber
    self.countryCode = countryCode
    self.locationID = locationID
    self.manufacturer = manufacturer
    self.product = product
    self.serialNumber = serialNumber
    self.primaryUsagePage = primaryUsagePage
    self.primaryUsage = primaryUsage
  }
}

/// A HID operation or event that cannot be encoded safely.
public enum HIDRuntimeError: Error, Sendable, Equatable {
  /// An empty report cannot be submitted to HIDDriverKit.
  case emptyReport
  /// The report cannot fit in the runtime wire format.
  case reportTooLarge
  /// The native runtime returned an unknown report type.
  case invalidReportType
  /// The native runtime returned a malformed report payload.
  case invalidReportPayload
}
