import Foundation

/// A USB descriptor request or response that the runtime cannot satisfy.
public enum USBDescriptorError: Error, Sendable, Equatable {
  /// USBDriverKit returned no descriptor.
  case unavailable
  /// The descriptor has this many bytes, more than one runtime message carries.
  case tooLarge(length: Int)
  /// The requested length is zero or larger than one runtime message carries.
  case invalidLength
  /// The device returned bytes that do not form a valid descriptor.
  case malformed
}

/// The transfer type encoded in an endpoint's `bmAttributes`.
public enum USBEndpointTransferType: UInt8, Sendable, Hashable {
  /// A control endpoint.
  case control = 0
  /// An isochronous endpoint.
  case isochronous = 1
  /// A bulk endpoint.
  case bulk = 2
  /// An interrupt endpoint.
  case interrupt = 3
}

/// A standard USB endpoint descriptor.
public struct USBEndpointDescriptor: Sendable, Hashable {
  /// The `bEndpointAddress` value, including the direction bit.
  public let address: UInt8
  /// The `bmAttributes` value.
  public let attributes: UInt8
  /// The `wMaxPacketSize` value.
  public let maxPacketSize: UInt16
  /// The `bInterval` value.
  public let interval: UInt8

  /// Creates an endpoint descriptor.
  public init(address: UInt8, attributes: UInt8, maxPacketSize: UInt16, interval: UInt8) {
    self.address = address
    self.attributes = attributes
    self.maxPacketSize = maxPacketSize
    self.interval = interval
  }

  /// The endpoint number without the direction bit.
  public var number: UInt8 { address & 0x0F }
  /// The data direction of the endpoint.
  public var direction: USBTransferDirection { USBTransferDirection(encodedByte: address) }
  /// The endpoint's transfer type.
  public var transferType: USBEndpointTransferType {
    USBEndpointTransferType(rawValue: attributes & 0x03) ?? .control
  }

  init?(descriptor bytes: ArraySlice<UInt8>) {
    guard bytes.count >= 7, bytes[bytes.startIndex + 1] == 0x05 else { return nil }
    let base = bytes.startIndex
    self.init(
      address: bytes[base + 2],
      attributes: bytes[base + 3],
      maxPacketSize: UInt16(bytes[base + 4]) | UInt16(bytes[base + 5]) << 8,
      interval: bytes[base + 6]
    )
  }
}

/// A standard USB interface descriptor and, when parsed from a configuration, its endpoints.
public struct USBInterfaceDescriptor: Sendable, Hashable {
  /// The `bInterfaceNumber` value.
  public let interfaceNumber: UInt8
  /// The `bAlternateSetting` value.
  public let alternateSetting: UInt8
  /// The `bNumEndpoints` value.
  public let endpointCount: UInt8
  /// The `bInterfaceClass` value.
  public let interfaceClass: UInt8
  /// The `bInterfaceSubClass` value.
  public let interfaceSubclass: UInt8
  /// The `bInterfaceProtocol` value.
  public let interfaceProtocol: UInt8
  /// The `iInterface` string index.
  public let stringIndex: UInt8
  /// Endpoint descriptors that follow the interface in a configuration descriptor.
  public let endpoints: [USBEndpointDescriptor]

  /// Creates an interface descriptor.
  public init(
    interfaceNumber: UInt8,
    alternateSetting: UInt8,
    endpointCount: UInt8,
    interfaceClass: UInt8,
    interfaceSubclass: UInt8,
    interfaceProtocol: UInt8,
    stringIndex: UInt8,
    endpoints: [USBEndpointDescriptor] = []
  ) {
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.endpointCount = endpointCount
    self.interfaceClass = interfaceClass
    self.interfaceSubclass = interfaceSubclass
    self.interfaceProtocol = interfaceProtocol
    self.stringIndex = stringIndex
    self.endpoints = endpoints
  }

  init?(descriptor bytes: ArraySlice<UInt8>, endpoints: [USBEndpointDescriptor] = []) {
    guard bytes.count >= 9, bytes[bytes.startIndex + 1] == 0x04 else { return nil }
    let base = bytes.startIndex
    self.init(
      interfaceNumber: bytes[base + 2],
      alternateSetting: bytes[base + 3],
      endpointCount: bytes[base + 4],
      interfaceClass: bytes[base + 5],
      interfaceSubclass: bytes[base + 6],
      interfaceProtocol: bytes[base + 7],
      stringIndex: bytes[base + 8],
      endpoints: endpoints
    )
  }

  func appending(_ endpoint: USBEndpointDescriptor) -> Self {
    Self(
      interfaceNumber: interfaceNumber,
      alternateSetting: alternateSetting,
      endpointCount: endpointCount,
      interfaceClass: interfaceClass,
      interfaceSubclass: interfaceSubclass,
      interfaceProtocol: interfaceProtocol,
      stringIndex: stringIndex,
      endpoints: endpoints + [endpoint]
    )
  }
}

/// A standard USB device descriptor.
public struct USBDeviceDescriptor: Sendable, Hashable {
  /// The `bcdUSB` specification release.
  public let usbRelease: UInt16
  /// The `bDeviceClass` value.
  public let deviceClass: UInt8
  /// The `bDeviceSubClass` value.
  public let deviceSubclass: UInt8
  /// The `bDeviceProtocol` value.
  public let deviceProtocol: UInt8
  /// The `bMaxPacketSize0` value.
  public let maxPacketSize0: UInt8
  /// The `idVendor` value.
  public let vendorID: UInt16
  /// The `idProduct` value.
  public let productID: UInt16
  /// The `bcdDevice` release.
  public let deviceRelease: UInt16
  /// The `iManufacturer` string index.
  public let manufacturerStringIndex: UInt8
  /// The `iProduct` string index.
  public let productStringIndex: UInt8
  /// The `iSerialNumber` string index.
  public let serialNumberStringIndex: UInt8
  /// The `bNumConfigurations` value.
  public let configurationCount: UInt8

  init(descriptor bytes: [UInt8]) throws {
    guard bytes.count == 18, bytes[0] == 18, bytes[1] == 0x01 else {
      throw USBDescriptorError.malformed
    }
    usbRelease = UInt16(bytes[2]) | UInt16(bytes[3]) << 8
    deviceClass = bytes[4]
    deviceSubclass = bytes[5]
    deviceProtocol = bytes[6]
    maxPacketSize0 = bytes[7]
    vendorID = UInt16(bytes[8]) | UInt16(bytes[9]) << 8
    productID = UInt16(bytes[10]) | UInt16(bytes[11]) << 8
    deviceRelease = UInt16(bytes[12]) | UInt16(bytes[13]) << 8
    manufacturerStringIndex = bytes[14]
    productStringIndex = bytes[15]
    serialNumberStringIndex = bytes[16]
    configurationCount = bytes[17]
  }
}

/// A USB configuration descriptor with its interfaces and endpoints.
public struct USBConfigurationDescriptor: Sendable, Hashable {
  /// The `bConfigurationValue` passed to `SetConfiguration`.
  public let configurationValue: UInt8
  /// The `bNumInterfaces` value.
  public let interfaceCount: UInt8
  /// The `iConfiguration` string index.
  public let stringIndex: UInt8
  /// The `bmAttributes` value.
  public let attributes: UInt8
  /// The `bMaxPower` value, in the device speed's power units.
  public let maxPower: UInt8
  /// Every interface and alternate setting, with the endpoints that follow each one.
  public let interfaces: [USBInterfaceDescriptor]
  /// The complete descriptor, `wTotalLength` bytes, including class-specific descriptors.
  public let bytes: [UInt8]

  init(descriptor bytes: [UInt8]) throws {
    guard bytes.count >= 9, bytes[0] >= 9, bytes[1] == 0x02,
      Int(UInt16(bytes[2]) | UInt16(bytes[3]) << 8) == bytes.count
    else { throw USBDescriptorError.malformed }
    configurationValue = bytes[5]
    interfaceCount = bytes[4]
    stringIndex = bytes[6]
    attributes = bytes[7]
    maxPower = bytes[8]
    self.bytes = bytes

    var interfaces: [USBInterfaceDescriptor] = []
    try Self.walk(bytes, from: Int(bytes[0])) { descriptor in
      switch descriptor[descriptor.startIndex + 1] {
      case 0x04:
        guard let interface = USBInterfaceDescriptor(descriptor: descriptor) else {
          throw USBDescriptorError.malformed
        }
        interfaces.append(interface)
      case 0x05:
        guard let endpoint = USBEndpointDescriptor(descriptor: descriptor) else {
          throw USBDescriptorError.malformed
        }
        if let last = interfaces.popLast() { interfaces.append(last.appending(endpoint)) }
      default: break
      }
    }
    self.interfaces = interfaces
  }

  /// Visits each descriptor in `bytes` after `offset`, rejecting lengths that cannot advance or
  /// that run past the end.
  static func walk(
    _ bytes: [UInt8],
    from offset: Int,
    _ body: (ArraySlice<UInt8>) throws -> Void
  ) throws {
    var offset = offset
    while offset < bytes.count {
      guard bytes.count - offset >= 2 else { throw USBDescriptorError.malformed }
      let length = Int(bytes[offset])
      guard length >= 2, length <= bytes.count - offset else { throw USBDescriptorError.malformed }
      try body(bytes[offset..<offset + length])
      offset += length
    }
  }
}

/// A USB string descriptor.
public struct USBStringDescriptor: Sendable, Hashable {
  /// The UTF-16LE code units after the two-byte header.
  public let codeUnits: [UInt16]

  /// The descriptor text. For string index 0 the code units are language identifiers instead.
  public var string: String { String(decoding: codeUnits, as: UTF16.self) }

  init(descriptor bytes: [UInt8]) throws {
    guard bytes.count >= 2, Int(bytes[0]) == bytes.count, bytes[1] == 0x03 else {
      throw USBDescriptorError.malformed
    }
    // An odd trailing byte is not a complete code unit and is ignored.
    codeUnits = stride(from: 2, to: bytes.count - 1, by: 2).map {
      UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8
    }
  }
}

/// One device capability descriptor from a binary object store (BOS).
public struct USBDeviceCapability: Sendable, Hashable {
  /// The `bDevCapabilityType` value.
  public let type: UInt8
  /// The complete capability descriptor, header included.
  public let bytes: [UInt8]
}

/// A binary object store (BOS) descriptor and its device capabilities.
public struct USBCapabilityDescriptors: Sendable, Hashable {
  /// The device capability descriptors in device order.
  public let capabilities: [USBDeviceCapability]
  /// The complete descriptor, `wTotalLength` bytes.
  public let bytes: [UInt8]

  init(descriptor bytes: [UInt8]) throws {
    guard bytes.count >= 5, bytes[0] >= 5, bytes[1] == 0x0F,
      Int(UInt16(bytes[2]) | UInt16(bytes[3]) << 8) == bytes.count
    else { throw USBDescriptorError.malformed }
    var capabilities: [USBDeviceCapability] = []
    try USBConfigurationDescriptor.walk(bytes, from: Int(bytes[0])) { descriptor in
      let base = descriptor.startIndex
      guard descriptor.count >= 3, descriptor[base + 1] == 0x10 else {
        throw USBDescriptorError.malformed
      }
      capabilities.append(USBDeviceCapability(type: descriptor[base + 2], bytes: Array(descriptor)))
    }
    self.capabilities = capabilities
    self.bytes = bytes
  }
}

extension USBDescriptorError {
  /// Decodes a descriptor response: its full length, then the bytes when they fit.
  static func descriptorBytes(from payload: Data) throws -> [UInt8]? {
    let length: UInt32 = try payload.readRuntimeInteger(at: 0)
    let bytes = Array(payload.dropFirst(4))
    if bytes.isEmpty {
      guard length != 0 else { return nil }
      guard Int(length) > RuntimeMessage.maximumSize - RuntimeMessage.headerSize - 4 else {
        throw USBRuntimeError.invalidResponse
      }
      throw Self.tooLarge(length: Int(length))
    }
    guard bytes.count == Int(length) else { throw USBRuntimeError.invalidResponse }
    return bytes
  }
}
