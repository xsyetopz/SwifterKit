import Foundation

/// A logical-unit superclass supplied by SCSIPeripheralsDriverKit.
public enum SCSIPeripheralDeviceType: UInt8, Sendable, Hashable, CaseIterable {
  /// Type 00 device using SCSI Block Commands.
  case blockCommands = 0
  /// Type 05 device using SCSI Multimedia Commands.
  case multimediaCommands = 5
  /// Type 07 optical-memory device.
  case opticalMemory = 7
}

/// Transfer constraints published by a SCSI logical-unit service.
public struct SCSIPeripheralTransferConstraints: Sendable, Hashable {
  /// Maximum blocks accepted by one read.
  public let maximumBlockCountRead: UInt64?
  /// Maximum blocks accepted by one write.
  public let maximumBlockCountWrite: UInt64?
  /// Maximum bytes accepted by one read.
  public let maximumByteCountRead: UInt64?
  /// Maximum bytes accepted by one write.
  public let maximumByteCountWrite: UInt64?
  /// Maximum DMA segments accepted by one read.
  public let maximumSegmentCountRead: UInt64?
  /// Maximum DMA segments accepted by one write.
  public let maximumSegmentCountWrite: UInt64?
  /// Maximum bytes in each read DMA segment.
  public let maximumSegmentByteCountRead: UInt64?
  /// Maximum bytes in each write DMA segment.
  public let maximumSegmentByteCountWrite: UInt64?
  /// Required byte alignment for DMA segments.
  public let minimumSegmentAlignmentByteCount: UInt64?
  /// Address bits available to each DMA segment.
  public let maximumSegmentAddressableBitCount: UInt64?
  /// Transfer size at which the device reaches saturation.
  public let minimumSaturationByteCount: UInt64?
  /// Maximum swap-write transfer value.
  public let maximumSwapWrite: UInt64?

  /// Creates a set of optional I/O Registry transfer constraints.
  public init(
    maximumBlockCountRead: UInt64? = nil,
    maximumBlockCountWrite: UInt64? = nil,
    maximumByteCountRead: UInt64? = nil,
    maximumByteCountWrite: UInt64? = nil,
    maximumSegmentCountRead: UInt64? = nil,
    maximumSegmentCountWrite: UInt64? = nil,
    maximumSegmentByteCountRead: UInt64? = nil,
    maximumSegmentByteCountWrite: UInt64? = nil,
    minimumSegmentAlignmentByteCount: UInt64? = nil,
    maximumSegmentAddressableBitCount: UInt64? = nil,
    minimumSaturationByteCount: UInt64? = nil,
    maximumSwapWrite: UInt64? = nil
  ) {
    self.maximumBlockCountRead = maximumBlockCountRead
    self.maximumBlockCountWrite = maximumBlockCountWrite
    self.maximumByteCountRead = maximumByteCountRead
    self.maximumByteCountWrite = maximumByteCountWrite
    self.maximumSegmentCountRead = maximumSegmentCountRead
    self.maximumSegmentCountWrite = maximumSegmentCountWrite
    self.maximumSegmentByteCountRead = maximumSegmentByteCountRead
    self.maximumSegmentByteCountWrite = maximumSegmentByteCountWrite
    self.minimumSegmentAlignmentByteCount = minimumSegmentAlignmentByteCount
    self.maximumSegmentAddressableBitCount = maximumSegmentAddressableBitCount
    self.minimumSaturationByteCount = minimumSaturationByteCount
    self.maximumSwapWrite = maximumSwapWrite
  }

  var registryProperties: [String: UInt64] {
    let values: [(String, UInt64?)] = [
      ("IOMaximumBlockCountRead", maximumBlockCountRead),
      ("IOMaximumBlockCountWrite", maximumBlockCountWrite),
      ("IOMaximumByteCountRead", maximumByteCountRead),
      ("IOMaximumByteCountWrite", maximumByteCountWrite),
      ("IOMaximumSegmentCountRead", maximumSegmentCountRead),
      ("IOMaximumSegmentCountWrite", maximumSegmentCountWrite),
      ("IOMaximumSegmentByteCountRead", maximumSegmentByteCountRead),
      ("IOMaximumSegmentByteCountWrite", maximumSegmentByteCountWrite),
      ("IOMinimumSegmentAlignmentByteCount", minimumSegmentAlignmentByteCount),
      ("IOMaximumSegmentAddressableBitCount", maximumSegmentAddressableBitCount),
      ("IOMinimumSaturationByteCount", minimumSaturationByteCount),
      ("IOMaximumSwapWrite", maximumSwapWrite),
    ]
    return Dictionary(
      uniqueKeysWithValues: values.compactMap { key, value in value.map { (key, $0) } }
    )
  }
}

/// Static policy for one SCSI logical-unit peripheral driver.
public struct SCSIPeripheralConfiguration: Sendable, Hashable {
  /// The framework superclass generated for the logical unit.
  public let deviceType: SCSIPeripheralDeviceType
  /// Value returned by the enumeration-time initialization callback.
  public let initializationSucceeds: Bool
  /// Optional transfer constraints published before device enumeration.
  public let transferConstraints: SCSIPeripheralTransferConstraints

  /// Creates peripheral policy for a generated extension.
  public init(
    deviceType: SCSIPeripheralDeviceType,
    initializationSucceeds: Bool = true,
    transferConstraints: SCSIPeripheralTransferConstraints = .init()
  ) {
    self.deviceType = deviceType
    self.initializationSucceeds = initializationSucceeds
    self.transferConstraints = transferConstraints
  }
}

/// One custom Command Descriptor Block request.
public struct SCSIPeripheralCommand: Sendable, Hashable {
  /// Maximum data bytes transported through one runtime call.
  public static let maximumDataLength = 61_440

  /// Logical unit receiving the command.
  public let logicalUnitNumber: UInt64
  /// Command timeout in milliseconds.
  public let timeoutMilliseconds: UInt32
  /// Command Descriptor Block, padded to 16 bytes by the runtime.
  public let commandDescriptorBlock: [UInt8]
  /// Direction of the SCSI data phase.
  public let transferDirection: SCSIDataTransferDirection
  /// Bytes written to the target for an initiator-to-target command.
  public let outboundData: [UInt8]
  /// Requested byte count for a target-to-initiator command.
  public let requestedDataLength: UInt32
  /// Maximum sense bytes requested from the framework.
  public let requestedSenseLength: UInt8

  /// Creates and validates a custom CDB operation.
  public init(
    logicalUnitNumber: UInt64 = 0,
    timeoutMilliseconds: UInt32,
    commandDescriptorBlock: [UInt8],
    transferDirection: SCSIDataTransferDirection = .none,
    outboundData: [UInt8] = [],
    requestedDataLength: UInt32 = 0,
    requestedSenseLength: UInt8 = 0
  ) throws {
    guard (1...16).contains(commandDescriptorBlock.count),
      transferDirection.rawValue <= SCSIDataTransferDirection.targetToInitiator.rawValue,
      outboundData.count <= Self.maximumDataLength, requestedDataLength <= Self.maximumDataLength
    else { throw SCSIPeripheralRuntimeError.invalidCommand }

    switch transferDirection.rawValue {
    case SCSIDataTransferDirection.none.rawValue:
      guard outboundData.isEmpty, requestedDataLength == 0 else {
        throw SCSIPeripheralRuntimeError.invalidCommand
      }
    case SCSIDataTransferDirection.initiatorToTarget.rawValue:
      guard !outboundData.isEmpty, requestedDataLength == UInt32(outboundData.count) else {
        throw SCSIPeripheralRuntimeError.invalidCommand
      }
    case SCSIDataTransferDirection.targetToInitiator.rawValue:
      guard outboundData.isEmpty, requestedDataLength > 0 else {
        throw SCSIPeripheralRuntimeError.invalidCommand
      }
    default: throw SCSIPeripheralRuntimeError.invalidCommand
    }

    self.logicalUnitNumber = logicalUnitNumber
    self.timeoutMilliseconds = timeoutMilliseconds
    self.commandDescriptorBlock = commandDescriptorBlock
    self.transferDirection = transferDirection
    self.outboundData = outboundData
    self.requestedDataLength = requestedDataLength
    self.requestedSenseLength = requestedSenseLength
  }
}

/// Result of a custom peripheral CDB.
public struct SCSIPeripheralResponse: Sendable, Hashable {
  /// SCSI completion status.
  public let taskStatus: SCSITaskStatus
  /// Framework service response.
  public let serviceResponse: SCSIServiceResponse
  /// Bytes the device reports transferring.
  public let realizedDataLength: UInt64
  /// Data read from the target.
  public let data: [UInt8]
  /// Sense-buffer bytes when the framework reports them valid.
  public let senseData: [UInt8]

  init(runtimePayload data: Data) throws {
    guard data.count >= 24 else { throw SCSIPeripheralRuntimeError.invalidPayload }
    let realized: UInt64 = try data.readRuntimeInteger(at: 8)
    let senseValid = data[16]
    let senseLength = Int(data[17])
    let reserved: UInt16 = try data.readRuntimeInteger(at: 18)
    let dataLength: UInt32 = try data.readRuntimeInteger(at: 20)
    let expected = 24 + Int(dataLength) + senseLength
    guard senseValid <= 1, reserved == 0, data.count == expected, realized >= UInt64(dataLength),
      senseValid == 1 || senseLength == 0
    else { throw SCSIPeripheralRuntimeError.invalidPayload }

    taskStatus = SCSITaskStatus(rawValue: try data.readRuntimeInteger(at: 0))
    serviceResponse = SCSIServiceResponse(rawValue: try data.readRuntimeInteger(at: 4))
    realizedDataLength = realized
    self.data = Array(data[24..<(24 + Int(dataLength))])
    senseData = Array(data[(24 + Int(dataLength))..<expected])
  }
}

/// A malformed peripheral configuration, command, or response.
public enum SCSIPeripheralRuntimeError: Error, Sendable, Equatable {
  /// Command fields conflict or exceed the wire limit.
  case invalidCommand
  /// Native response bytes are malformed.
  case invalidPayload
}
