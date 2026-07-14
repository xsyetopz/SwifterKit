import Foundation

extension DriverCommand {
  /// Sends a custom CDB through the generated peripheral superclass.
  public static func sendSCSIPeripheralCommand(_ command: SCSIPeripheralCommand) -> Self {
    var payload = Data(capacity: 40 + command.outboundData.count)
    payload.appendRuntimeInteger(command.logicalUnitNumber)
    payload.appendRuntimeInteger(command.timeoutMilliseconds)
    payload.appendRuntimeInteger(command.requestedDataLength)
    payload.append(contentsOf: command.commandDescriptorBlock)
    payload.append(contentsOf: repeatElement(0, count: 16 - command.commandDescriptorBlock.count))
    payload.append(UInt8(command.transferDirection.rawValue))
    payload.append(command.requestedSenseLength)
    payload.append(contentsOf: repeatElement(0, count: 6))
    payload.append(contentsOf: command.outboundData)
    return Self(
      opcode: 0x0B10,
      requiredCapabilities: .scsi,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 24 + Int(command.requestedDataLength)
        + Int(command.requestedSenseLength)
    )
  }

  /// Suspends framework services to gain exclusive peripheral access.
  public static let suspendSCSIPeripheralServices = Self(
    opcode: 0x0B11,
    requiredCapabilities: .scsi,
    maximumResponseSize: RuntimeMessage.headerSize
  )

  /// Resumes framework services after exclusive peripheral access.
  public static let resumeSCSIPeripheralServices = Self(
    opcode: 0x0B12,
    requiredCapabilities: .scsi,
    maximumResponseSize: RuntimeMessage.headerSize
  )

  /// Requests a peripheral bus reset.
  public static let resetSCSIPeripheral = Self(
    opcode: 0x0B13,
    requiredCapabilities: .scsi,
    maximumResponseSize: RuntimeMessage.headerSize + 4
  )

  /// Queries the current medium block size.
  public static let scsiPeripheralMediumBlockSize = Self(
    opcode: 0x0B14,
    requiredCapabilities: .scsi,
    maximumResponseSize: RuntimeMessage.headerSize + 8
  )
}

extension DriverContext {
  /// Sends a custom CDB and returns copied data and sense bytes.
  public func sendSCSIPeripheralCommand(_ command: SCSIPeripheralCommand) async throws
    -> SCSIPeripheralResponse
  { try SCSIPeripheralResponse(runtimePayload: await execute(.sendSCSIPeripheralCommand(command))) }

  /// Suspends framework services to gain exclusive peripheral access.
  public func suspendSCSIPeripheralServices() async throws {
    _ = try await execute(.suspendSCSIPeripheralServices)
  }

  /// Resumes framework services after exclusive peripheral access.
  public func resumeSCSIPeripheralServices() async throws {
    _ = try await execute(.resumeSCSIPeripheralServices)
  }

  /// Requests a peripheral bus reset.
  public func resetSCSIPeripheral() async throws -> SCSIServiceResponse {
    let data = try await execute(.resetSCSIPeripheral)
    guard data.count == 4 else { throw SCSIPeripheralRuntimeError.invalidPayload }
    return SCSIServiceResponse(rawValue: try data.readRuntimeInteger(at: 0))
  }

  /// Returns the current medium block size.
  public func scsiPeripheralMediumBlockSize() async throws -> UInt64 {
    let data = try await execute(.scsiPeripheralMediumBlockSize)
    guard data.count == 8 else { throw SCSIPeripheralRuntimeError.invalidPayload }
    return try data.readRuntimeInteger(at: 0)
  }
}
