import Foundation

/// The direction of a USB control or endpoint transfer.
public enum USBTransferDirection: UInt8, Sendable, Hashable {
  /// Host-to-device data.
  case out = 0x00
  /// Device-to-host data.
  case `in` = 0x80

  /// Decodes the direction bit from a request type or endpoint address.
  public init(encodedByte: UInt8) { self = encodedByte & 0x80 == 0 ? .out : .in }
}

/// The setup packet and expected data length for a USB control transfer.
public struct USBControlRequest: Sendable, Hashable {
  /// Direction, type, and recipient bits.
  public let requestType: UInt8
  /// The request identifier.
  public let request: UInt8
  /// Request-specific value.
  public let value: UInt16
  /// Request-specific index.
  public let index: UInt16
  /// Expected data-stage length.
  public let length: UInt16

  /// Creates a USB control request.
  public init(
    requestType: UInt8,
    request: UInt8,
    value: UInt16 = 0,
    index: UInt16 = 0,
    length: UInt16 = 0
  ) {
    self.requestType = requestType
    self.request = request
    self.value = value
    self.index = index
    self.length = length
  }

  /// The data-stage direction.
  public var direction: USBTransferDirection { USBTransferDirection(encodedByte: requestType) }
}

/// The bytes and exact count returned by a USB transfer.
public struct USBTransferResult: Sendable, Hashable {
  /// The number of bytes transferred by USBDriverKit.
  public let bytesTransferred: UInt32
  /// Bytes returned by a device-to-host transfer.
  public let data: [UInt8]

  /// Creates a USB transfer result.
  public init(bytesTransferred: UInt32, data: [UInt8] = []) {
    self.bytesTransferred = bytesTransferred
    self.data = data
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 4 else { throw USBRuntimeError.invalidResponse }
    let count: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let data = Array(runtimePayload.dropFirst(4))
    guard data.isEmpty || data.count == Int(count) else { throw USBRuntimeError.invalidResponse }
    self.init(bytesTransferred: count, data: data)
  }
}

/// USB request-type bit values used to construct `bmRequestType`.
public enum USBRequestType {
  /// Device-to-host direction.
  public static let `in`: UInt8 = 0x80
  /// Host-to-device direction.
  public static let out: UInt8 = 0x00
  /// Standard request type.
  public static let standard: UInt8 = 0x00
  /// Class-specific request type.
  public static let `class`: UInt8 = 0x20
  /// Vendor-specific request type.
  public static let vendor: UInt8 = 0x40
  /// Device recipient.
  public static let device: UInt8 = 0x00
  /// Interface recipient.
  public static let interface: UInt8 = 0x01
  /// Endpoint recipient.
  public static let endpoint: UInt8 = 0x02
  /// Other recipient.
  public static let other: UInt8 = 0x03
}

/// Standard USB request identifiers.
public enum USBRequest {
  /// Returns status bits.
  public static let getStatus: UInt8 = 0x00
  /// Clears a feature selector.
  public static let clearFeature: UInt8 = 0x01
  /// Sets a feature selector.
  public static let setFeature: UInt8 = 0x03
  /// Returns a descriptor.
  public static let getDescriptor: UInt8 = 0x06
  /// Sets a descriptor.
  public static let setDescriptor: UInt8 = 0x07
  /// Returns the active configuration.
  public static let getConfiguration: UInt8 = 0x08
  /// Selects a configuration.
  public static let setConfiguration: UInt8 = 0x09
  /// Returns an interface alternate setting.
  public static let getInterface: UInt8 = 0x0A
  /// Selects an interface alternate setting.
  public static let setInterface: UInt8 = 0x0B
}

/// Hardware matching used by a generated USB interface driver and its entitlement.
public struct USBDeviceConfiguration: Sendable, Hashable {
  /// The USB vendor identifier assigned to the hardware manufacturer.
  public let vendorID: UInt16
  /// Product identifiers supported by the extension, or an empty array for the whole vendor.
  public let productIDs: [UInt16]
  /// Optional mask applied to a single product identifier.
  public let productIDMask: UInt16?
  /// Optional device release number from `bcdDevice`.
  public let deviceRelease: UInt16?
  /// Optional configuration value.
  public let configurationValue: UInt8?
  /// Optional USB device class match.
  public let deviceClass: UInt8?
  /// Optional USB device subclass match.
  public let deviceSubclass: UInt8?
  /// Optional USB device protocol match.
  public let deviceProtocol: UInt8?
  /// Optional interface number match.
  public let interfaceNumber: UInt8?
  /// Optional USB interface class match.
  public let interfaceClass: UInt8?
  /// Optional USB interface subclass match.
  public let interfaceSubclass: UInt8?
  /// Optional USB interface protocol match.
  public let interfaceProtocol: UInt8?

  /// Creates hardware matching for an `IOUSBHostInterface` provider.
  public init(
    vendorID: UInt16,
    productIDs: [UInt16] = [],
    productIDMask: UInt16? = nil,
    deviceRelease: UInt16? = nil,
    configurationValue: UInt8? = nil,
    deviceClass: UInt8? = nil,
    deviceSubclass: UInt8? = nil,
    deviceProtocol: UInt8? = nil,
    interfaceNumber: UInt8? = nil,
    interfaceClass: UInt8? = nil,
    interfaceSubclass: UInt8? = nil,
    interfaceProtocol: UInt8? = nil
  ) {
    self.vendorID = vendorID
    self.productIDs = productIDs
    self.productIDMask = productIDMask
    self.deviceRelease = deviceRelease
    self.configurationValue = configurationValue
    self.deviceClass = deviceClass
    self.deviceSubclass = deviceSubclass
    self.deviceProtocol = deviceProtocol
    self.interfaceNumber = interfaceNumber
    self.interfaceClass = interfaceClass
    self.interfaceSubclass = interfaceSubclass
    self.interfaceProtocol = interfaceProtocol
  }

  var matchingProperties: [String: DriverProperty] {
    var properties: [String: DriverProperty] = ["idVendor": Self.property(vendorID)]
    if productIDs.count == 1, let productID = productIDs.first {
      properties["idProduct"] = Self.property(productID)
    } else if !productIDs.isEmpty {
      properties["idProductArray"] = .array(productIDs.map { Self.property($0) })
    }
    add(productIDMask, as: "idProductMask", to: &properties)
    add(deviceRelease, as: "bcdDevice", to: &properties)
    add(configurationValue, as: "bConfigurationValue", to: &properties)
    add(deviceClass, as: "bDeviceClass", to: &properties)
    add(deviceSubclass, as: "bDeviceSubClass", to: &properties)
    add(deviceProtocol, as: "bDeviceProtocol", to: &properties)
    add(interfaceNumber, as: "bInterfaceNumber", to: &properties)
    add(interfaceClass, as: "bInterfaceClass", to: &properties)
    add(interfaceSubclass, as: "bInterfaceSubClass", to: &properties)
    add(interfaceProtocol, as: "bInterfaceProtocol", to: &properties)
    return properties
  }

  private static func property<T: FixedWidthInteger>(_ value: T) -> DriverProperty {
    .unsignedInteger(UInt64(value))
  }

  private func add<T: FixedWidthInteger>(
    _ value: T?,
    as key: String,
    to properties: inout [String: DriverProperty]
  ) { if let value { properties[key] = Self.property(value) } }
}

/// An invalid USB runtime request or response.
public enum USBRuntimeError: Error, Sendable, Equatable {
  /// Endpoint transfers require at least one byte.
  case emptyTransfer
  /// The payload direction conflicts with the request or endpoint.
  case directionMismatch
  /// The supplied output bytes do not match the declared length.
  case invalidOutputLength
  /// The requested transfer cannot fit in one runtime message.
  case transferTooLarge
  /// The native response has an invalid count or payload.
  case invalidResponse
}
