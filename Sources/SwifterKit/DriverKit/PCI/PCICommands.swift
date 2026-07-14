import Foundation

extension DriverCommand {
  /// Creates a PCI configuration-space or aperture read.
  public static func pciRead(
    space: PCIRegisterSpace,
    offset: UInt64,
    width: PCIAccessWidth,
    options: UInt32 = 0
  ) throws -> Self {
    try validatePCI(space: space, offset: offset, width: width)
    return Self(
      opcode: 0x0400,
      requiredCapabilities: .pci,
      payload: pciAccessPayload(
        space: space,
        offset: offset,
        value: 0,
        width: width,
        options: options
      ),
      maximumResponseSize: RuntimeMessage.headerSize + 8
    )
  }

  /// Creates a PCI configuration-space or aperture write.
  public static func pciWrite(
    space: PCIRegisterSpace,
    offset: UInt64,
    value: UInt64,
    width: PCIAccessWidth,
    options: UInt32 = 0
  ) throws -> Self {
    try validatePCI(space: space, offset: offset, width: width)
    guard width == .quadWord || value < UInt64(1) << UInt64(width.rawValue * 8) else {
      throw PCIRuntimeError.valueOutOfRange
    }
    return Self(
      opcode: 0x0401,
      requiredCapabilities: .pci,
      payload: pciAccessPayload(
        space: space,
        offset: offset,
        value: value,
        width: width,
        options: options
      ),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Creates a query for BAR indices zero through five or expansion ROM index six.
  public static func pciBaseAddressInfo(index: UInt8) throws -> Self {
    guard index <= 6 else { throw PCIRuntimeError.invalidBARIndex }
    return Self(
      opcode: 0x0402,
      requiredCapabilities: .pci,
      payload: Data([index, 0, 0, 0]),
      maximumResponseSize: RuntimeMessage.headerSize + 12
    )
  }

  /// Creates a query for the PCI bus/device/function address.
  public static let pciLocation = Self(
    opcode: 0x0403,
    requiredCapabilities: .pci,
    maximumResponseSize: RuntimeMessage.headerSize + 4
  )

  /// Creates a search for a standard or extended PCI capability.
  public static func pciFindCapability(identifier: UInt32, startingAt offset: UInt64 = 0) -> Self {
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(offset)
    return Self(
      opcode: 0x0404,
      requiredCapabilities: .pci,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 8
    )
  }

  private static func validatePCI(space: PCIRegisterSpace, offset: UInt64, width: PCIAccessWidth)
    throws
  {
    if case .configuration = space {
      guard width != .quadWord else { throw PCIRuntimeError.invalidConfigurationWidth }
      guard offset <= 4_096 - UInt64(width.rawValue) else {
        throw PCIRuntimeError.configurationOffsetOutOfRange
      }
    }
    guard offset.isMultiple(of: UInt64(width.rawValue)) else {
      throw PCIRuntimeError.misalignedOffset
    }
  }

  private static func pciAccessPayload(
    space: PCIRegisterSpace,
    offset: UInt64,
    value: UInt64,
    width: PCIAccessWidth,
    options: UInt32
  ) -> Data {
    let encodedSpace: UInt8
    let memoryIndex: UInt8
    switch space {
    case .configuration:
      encodedSpace = 0
      memoryIndex = 0
    case .memory(let index):
      encodedSpace = 1
      memoryIndex = index
    }

    var payload = Data(capacity: 24)
    payload.appendRuntimeInteger(offset)
    payload.appendRuntimeInteger(value)
    payload.appendRuntimeInteger(options)
    payload.append(memoryIndex)
    payload.append(width.rawValue)
    payload.append(encodedSpace)
    payload.append(0)
    return payload
  }
}

extension DriverContext {
  /// Reads a PCI configuration-space or aperture register.
  public func pciRead(
    space: PCIRegisterSpace,
    offset: UInt64,
    width: PCIAccessWidth,
    options: UInt32 = 0
  ) async throws -> UInt64 {
    let payload = try await execute(
      .pciRead(space: space, offset: offset, width: width, options: options)
    )
    guard payload.count == 8 else { throw PCIRuntimeError.invalidResponse }
    return try payload.readRuntimeInteger(at: 0)
  }

  /// Writes a PCI configuration-space or aperture register.
  public func pciWrite(
    space: PCIRegisterSpace,
    offset: UInt64,
    value: UInt64,
    width: PCIAccessWidth,
    options: UInt32 = 0
  ) async throws {
    _ = try await execute(
      .pciWrite(space: space, offset: offset, value: value, width: width, options: options)
    )
  }

  /// Returns information about a PCI base-address register.
  public func pciBaseAddressInfo(index: UInt8) async throws -> PCIBaseAddressInfo {
    try await PCIBaseAddressInfo(runtimePayload: execute(try .pciBaseAddressInfo(index: index)))
  }

  /// Returns the device's PCI bus/device/function address.
  public func pciLocation() async throws -> PCILocation {
    try await PCILocation(runtimePayload: execute(.pciLocation))
  }

  /// Finds the next matching PCI capability offset.
  public func pciFindCapability(identifier: UInt32, startingAt offset: UInt64 = 0) async throws
    -> UInt64
  {
    let payload = try await execute(.pciFindCapability(identifier: identifier, startingAt: offset))
    guard payload.count == 8 else { throw PCIRuntimeError.invalidResponse }
    return try payload.readRuntimeInteger(at: 0)
  }
}
