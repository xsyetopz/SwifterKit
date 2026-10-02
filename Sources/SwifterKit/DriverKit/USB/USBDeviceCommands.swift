import Foundation

extension DriverCommand {
  /// The largest descriptor one response carries after its four-byte length.
  public static let usbMaximumDescriptorLength =
    RuntimeMessage.maximumSize - RuntimeMessage.headerSize - 4

  /// Creates a command that selects a device configuration. Requires an `IOUSBHostDevice`
  /// provider.
  public static func usbSetConfiguration(_ value: UInt8, matchInterfaces: Bool = true) -> Self {
    usbCommand(.usbDeviceSetConfiguration, payload: Data([value, matchInterfaces ? 1 : 0, 0, 0]))
  }

  /// Creates a command that resets and re-enumerates the device. Requires an `IOUSBHostDevice`
  /// provider.
  public static func usbResetDevice() -> Self { usbCommand(.usbDeviceReset) }

  /// Creates a command that returns the device's operating speed.
  public static func usbDeviceSpeed() -> Self { usbCommand(.usbGetDeviceSpeed, response: 4) }

  /// Creates a command that returns the device's bus address.
  public static func usbDeviceAddress() -> Self { usbCommand(.usbGetDeviceAddress, response: 4) }

  /// Creates a command that returns the status of the device's port.
  public static func usbPortStatus() -> Self { usbCommand(.usbGetPortStatus, response: 4) }

  /// Creates a command that returns the controller's current frame number.
  public static func usbFrameNumber() -> Self { usbCommand(.usbGetFrameNumber, response: 16) }

  /// Creates a command that returns the controller's current microframe number.
  public static func usbCurrentMicroframe() -> Self {
    usbCommand(.usbGetCurrentMicroframe, response: 16)
  }

  /// Creates a command that returns a recent microframe number captured near its boundary.
  public static func usbReferenceMicroframe() -> Self {
    usbCommand(.usbGetReferenceMicroframe, response: 16)
  }

  /// Creates a command that copies the device descriptor.
  public static func usbDeviceDescriptor() -> Self {
    usbCommand(.usbCopyDeviceDescriptor, response: 4 + 18)
  }

  /// Creates a command that copies a configuration descriptor.
  public static func usbConfigurationDescriptor(
    _ selector: USBConfigurationSelector = .current
  ) -> Self {
    let kind: RuntimeUSBConfigurationSelector
    let value: UInt8
    switch selector {
    case .current: (kind, value) = (.current, 0)
    case .index(let index): (kind, value) = (.index, index)
    case .value(let configuration): (kind, value) = (.value, configuration)
    }
    let payload = Data([kind.rawValue, value, 0, 0])
    return usbDescriptorCommand(.usbCopyConfigurationDescriptor, payload: payload)
  }

  /// Creates a command that copies a string descriptor. Without a language identifier,
  /// USBDriverKit uses US English.
  public static func usbStringDescriptor(index: UInt8, languageID: UInt16? = nil) -> Self {
    var payload = Data([index, languageID == nil ? 0 : 1])
    payload.appendRuntimeInteger(languageID ?? 0)
    return usbCommand(.usbCopyStringDescriptor, payload: payload, response: 4 + 255)
  }

  /// Creates a command that copies the device's binary object store (BOS) descriptor.
  public static func usbCapabilityDescriptors() -> Self {
    usbDescriptorCommand(.usbCopyCapabilityDescriptors)
  }

  /// Creates a command that copies any descriptor through USBDriverKit's descriptor cache.
  public static func usbDescriptor(
    type: UInt8,
    index: UInt8 = 0,
    languageID: UInt16 = 0,
    requestType: USBDescriptorRequestType = .standard,
    recipient: USBDescriptorRecipient = .device,
    length: Int
  ) throws -> Self {
    guard length > 0, length <= min(Int(UInt16.max), usbMaximumDescriptorLength) else {
      throw USBDescriptorError.invalidLength
    }
    var payload = Data([type, index])
    payload.appendRuntimeInteger(languageID)
    payload.append(requestType.rawValue)
    payload.append(recipient.rawValue)
    payload.appendRuntimeInteger(UInt16(length))
    return usbCommand(.usbCopyDescriptor, payload: payload, response: 4 + length)
  }

  /// Creates a command that lists the interfaces of the active configuration. Requires an
  /// `IOUSBHostDevice` provider.
  public static func usbInterfaces() -> Self {
    usbCommand(.usbCopyInterfaces, response: 4 + RuntimeUSBLimits.maximumInterfaces * 9)
  }

  /// Creates a command that copies the matched interface's descriptor. Requires an
  /// `IOUSBHostInterface` provider.
  public static func usbInterfaceDescriptor() -> Self {
    usbCommand(.usbCopyInterfaceDescriptor, response: 9)
  }

  /// Creates a command that sets how long the interface waits after its pipes go idle before
  /// the device may suspend. Requires an `IOUSBHostInterface` provider.
  public static func usbSetIdlePolicy(timeout: UInt32) -> Self {
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(timeout)
    return usbCommand(.usbSetIdlePolicy, payload: payload)
  }

  /// Creates a command that returns the interface's idle suspend timeout. Requires an
  /// `IOUSBHostInterface` provider.
  public static func usbIdlePolicy() -> Self { usbCommand(.usbGetIdlePolicy, response: 4) }

  /// Creates a command that asynchronously aborts this driver's default-endpoint requests.
  public static func usbAbortDeviceRequests() -> Self { usbCommand(.usbAbortDeviceRequests) }

  static func usbCommand(_ opcode: RuntimeOpcode, payload: Data = Data(), response: Int = 0) -> Self
  {
    Self(
      opcode: opcode,
      requiredCapabilities: .usb,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + response
    )
  }

  private static func usbDescriptorCommand(_ opcode: RuntimeOpcode, payload: Data = Data()) -> Self
  {
    Self(
      opcode: opcode,
      requiredCapabilities: .usb,
      payload: payload,
      maximumResponseSize: RuntimeMessage.maximumSize
    )
  }
}

extension DriverContext {
  /// Selects a device configuration. When `matchInterfaces` is true, IOKit registers the new
  /// configuration's interfaces for matching. Requires an `IOUSBHostDevice` provider. Calls
  /// `IOUSBHostDevice::SetConfiguration`.
  public func usbSetConfiguration(_ value: UInt8, matchInterfaces: Bool = true) async throws {
    _ = try await execute(.usbSetConfiguration(value, matchInterfaces: matchInterfaces))
  }

  /// Resets and re-enumerates the device. The current device and its driver terminate.
  /// Requires an `IOUSBHostDevice` provider. Calls `IOUSBHostDevice::Reset`.
  public func usbResetDevice() async throws { _ = try await execute(.usbResetDevice()) }

  /// Returns the device's operating speed. Calls `IOUSBHostDevice::GetSpeed`.
  public func usbDeviceSpeed() async throws -> USBDeviceSpeed {
    USBDeviceSpeed(rawValue: UInt8(truncatingIfNeeded: try await usbValue(.usbDeviceSpeed())))
  }

  /// Returns the device's bus address. Calls `IOUSBHostDevice::GetAddress`.
  public func usbDeviceAddress() async throws -> UInt8 {
    UInt8(truncatingIfNeeded: try await usbValue(.usbDeviceAddress()))
  }

  /// Returns the status of the device's port. Calls `IOUSBHostDevice::GetPortStatus` or
  /// `IOUSBHostInterface::GetPortStatus`, depending on the provider.
  public func usbPortStatus() async throws -> USBPortStatus {
    USBPortStatus(rawValue: try await usbValue(.usbPortStatus()))
  }

  /// Returns the controller's current frame number and the current system time. Calls
  /// `IOUSBHostDevice::GetFrameNumber` or `IOUSBHostInterface::GetFrameNumber`, depending on the
  /// provider.
  public func usbFrameNumber() async throws -> USBFrameTime {
    try USBFrameTime(runtimePayload: await execute(.usbFrameNumber()))
  }

  /// Returns the controller's current microframe number. Extensions built with an SDK older
  /// than DriverKit 25 report `kIOReturnUnsupported`. Calls `IOUSBHostDevice::CurrentMicroframe` or
  /// `IOUSBHostInterface::CurrentMicroframe`, depending on the provider.
  public func usbCurrentMicroframe() async throws -> USBFrameTime {
    try USBFrameTime(runtimePayload: await execute(.usbCurrentMicroframe()))
  }

  /// Returns a recent microframe number with a time captured near its boundary. Extensions
  /// built with an SDK older than DriverKit 25 report `kIOReturnUnsupported`. Calls
  /// `IOUSBHostDevice::ReferenceMicroframe` or `IOUSBHostInterface::ReferenceMicroframe`, depending
  /// on the provider.
  public func usbReferenceMicroframe() async throws -> USBFrameTime {
    try USBFrameTime(runtimePayload: await execute(.usbReferenceMicroframe()))
  }

  /// Returns the device descriptor. Copies it with `IOUSBHostDevice::CopyDeviceDescriptor`.
  public func usbDeviceDescriptor() async throws -> USBDeviceDescriptor {
    try USBDeviceDescriptor(descriptor: await usbDescriptorBytes(.usbDeviceDescriptor()))
  }

  /// Returns a configuration descriptor with its interfaces and endpoints. The current
  /// configuration comes from `IOUSBHostInterface::CopyConfigurationDescriptor` or
  /// `IOUSBHostDevice::CopyConfigurationDescriptor`, and a configuration value from
  /// `IOUSBHostDevice::CopyConfigurationDescriptorWithValue`.
  ///
  /// Throws ``USBDescriptorError/tooLarge(length:)`` when the descriptor exceeds one runtime
  /// message.
  public func usbConfigurationDescriptor(
    _ selector: USBConfigurationSelector = .current
  ) async throws -> USBConfigurationDescriptor {
    try USBConfigurationDescriptor(
      descriptor: await usbDescriptorBytes(.usbConfigurationDescriptor(selector))
    )
  }

  /// Returns a string descriptor. Without a language identifier, USBDriverKit uses US English.
  /// Calls `IOUSBHostDevice::CopyStringDescriptor` or `IOUSBHostInterface::CopyStringDescriptor`,
  /// depending on the provider.
  public func usbStringDescriptor(
    index: UInt8,
    languageID: UInt16? = nil
  ) async throws -> USBStringDescriptor {
    try USBStringDescriptor(
      descriptor: await usbDescriptorBytes(
        .usbStringDescriptor(index: index, languageID: languageID)
      )
    )
  }

  /// Returns the device's binary object store (BOS) descriptor, or nil when it has none. Copies it
  /// with `IOUSBHostDevice::CopyCapabilityDescriptors`.
  public func usbCapabilityDescriptors() async throws -> USBCapabilityDescriptors? {
    let payload = try await execute(.usbCapabilityDescriptors())
    return try USBDescriptorError.descriptorBytes(from: payload).map(
      USBCapabilityDescriptors.init(descriptor:)
    )
  }

  /// Returns up to `length` bytes of any descriptor through USBDriverKit's descriptor cache. Calls
  /// `IOUSBHostDevice::CopyDescriptor`.
  public func usbDescriptor(
    type: UInt8,
    index: UInt8 = 0,
    languageID: UInt16 = 0,
    requestType: USBDescriptorRequestType = .standard,
    recipient: USBDescriptorRecipient = .device,
    length: Int
  ) async throws -> [UInt8] {
    try await usbDescriptorBytes(
      .usbDescriptor(
        type: type,
        index: index,
        languageID: languageID,
        requestType: requestType,
        recipient: recipient,
        length: length
      )
    )
  }

  /// Returns the interfaces of the device's active configuration. Requires an
  /// `IOUSBHostDevice` provider. Walks them with `IOUSBHostDevice::CreateInterfaceIterator`,
  /// `IOUSBHostDevice::CopyInterface` and `IOUSBHostDevice::DestroyInterfaceIterator`.
  public func usbInterfaces() async throws -> [USBInterfaceDescriptor] {
    let payload = try await execute(.usbInterfaces())
    let count = Int(try payload.readRuntimeInteger(at: 0) as UInt32)
    guard count <= RuntimeUSBLimits.maximumInterfaces, payload.count == 4 + count * 9 else {
      throw USBRuntimeError.invalidResponse
    }
    let bytes = [UInt8](payload)
    return try (0..<count).map { index in
      let start = 4 + index * 9
      guard let interface = USBInterfaceDescriptor(descriptor: bytes[start..<start + 9]) else {
        throw USBDescriptorError.malformed
      }
      return interface
    }
  }

  /// Returns the matched interface's descriptor for its current alternate setting. Requires an
  /// `IOUSBHostInterface` provider. Calls `IOUSBHostInterface::GetInterfaceDescriptor`.
  public func usbInterfaceDescriptor() async throws -> USBInterfaceDescriptor {
    let bytes = [UInt8](try await execute(.usbInterfaceDescriptor()))
    guard bytes.count == 9, let interface = USBInterfaceDescriptor(descriptor: bytes[...]) else {
      throw USBDescriptorError.malformed
    }
    return interface
  }

  /// Sets how long, in milliseconds, the interface waits after its pipes go idle before the
  /// device may suspend. Requires an `IOUSBHostInterface` provider. Calls
  /// `IOUSBHostInterface::SetIdlePolicy`.
  public func usbSetIdlePolicy(timeout: UInt32) async throws {
    _ = try await execute(.usbSetIdlePolicy(timeout: timeout))
  }

  /// Returns the interface's idle suspend timeout in milliseconds. Requires an
  /// `IOUSBHostInterface` provider. Calls `IOUSBHostInterface::GetIdlePolicy`.
  public func usbIdlePolicy() async throws -> UInt32 { try await usbValue(.usbIdlePolicy()) }

  /// Asynchronously aborts this driver's outstanding default-endpoint requests. Calls
  /// `IOUSBHostDevice::AbortDeviceRequests` or `IOUSBHostInterface::AbortDeviceRequests`, depending
  /// on the provider.
  public func usbAbortDeviceRequests() async throws {
    _ = try await execute(.usbAbortDeviceRequests())
  }

  func usbValue(_ command: DriverCommand) async throws -> UInt32 {
    let payload = try await execute(command)
    guard payload.count == 4 else { throw USBRuntimeError.invalidResponse }
    return try payload.readRuntimeInteger(at: 0)
  }

  private func usbDescriptorBytes(_ command: DriverCommand) async throws -> [UInt8] {
    guard let bytes = try USBDescriptorError.descriptorBytes(from: await execute(command)) else {
      throw USBDescriptorError.unavailable
    }
    return bytes
  }
}
