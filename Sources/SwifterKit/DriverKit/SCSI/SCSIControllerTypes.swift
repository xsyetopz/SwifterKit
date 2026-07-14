import Foundation

/// Static policy reported by a SCSIControllerDriverKit controller.
public struct SCSIControllerConfiguration: Sendable, Hashable {
  /// The initiator identifier assigned to the HBA.
  public let initiatorIdentifier: UInt64
  /// The highest target identifier addressable by the HBA.
  public let highestTargetIdentifier: UInt64
  /// The highest logical unit number addressable by the HBA.
  public let highestLogicalUnitNumber: UInt64
  /// The maximum number of concurrent tasks.
  public let maximumTaskCount: UInt32
  /// The maximum byte count for one DMA transfer.
  public let maximumTransferSize: UInt64
  /// The required DMA segment alignment in bytes.
  public let minimumSegmentAlignment: UInt32
  /// The number of hardware address bits.
  public let addressBitCount: UInt8
  /// The DMA segment representation requested from DriverKit.
  public let dmaSegmentType: SCSIDMASegmentType
  /// The SCSI Parallel Interface negotiation features supported by the HBA.
  public let supportedFeatures: SCSIParallelFeatures
  /// Whether completions include HBA-generated autosense data.
  public let performsAutoSense: Bool
  /// Whether the HBA supports multiple paths to one target.
  public let supportsMultipathing: Bool
  /// The immediate response for forwarded task-management callbacks.
  public let taskManagementResponse: SCSIServiceResponse

  /// Creates static SCSI HBA policy for the generated runtime.
  public init(
    initiatorIdentifier: UInt64,
    highestTargetIdentifier: UInt64,
    highestLogicalUnitNumber: UInt64 = 0,
    maximumTaskCount: UInt32 = 32,
    maximumTransferSize: UInt64 = 1_048_576,
    minimumSegmentAlignment: UInt32 = 1,
    addressBitCount: UInt8 = 64,
    dmaSegmentType: SCSIDMASegmentType = .host64,
    supportedFeatures: SCSIParallelFeatures = [],
    performsAutoSense: Bool = true,
    supportsMultipathing: Bool = false,
    taskManagementResponse: SCSIServiceResponse = .functionRejected
  ) {
    self.initiatorIdentifier = initiatorIdentifier
    self.highestTargetIdentifier = highestTargetIdentifier
    self.highestLogicalUnitNumber = highestLogicalUnitNumber
    self.maximumTaskCount = maximumTaskCount
    self.maximumTransferSize = maximumTransferSize
    self.minimumSegmentAlignment = minimumSegmentAlignment
    self.addressBitCount = addressBitCount
    self.dmaSegmentType = dmaSegmentType
    self.supportedFeatures = supportedFeatures
    self.performsAutoSense = performsAutoSense
    self.supportsMultipathing = supportsMultipathing
    self.taskManagementResponse = taskManagementResponse
  }
}

/// IODMACommand output segment representation used by the controller.
public struct SCSIDMASegmentType: RawRepresentable, Sendable, Hashable {
  /// Uses native-endian 32-bit DMA segments.
  public static let host32 = Self(rawValue: 0)
  /// Uses big-endian 32-bit DMA segments.
  public static let bigEndian32 = Self(rawValue: 1)
  /// Uses little-endian 32-bit DMA segments.
  public static let littleEndian32 = Self(rawValue: 2)
  /// Uses native-endian 64-bit DMA segments.
  public static let host64 = Self(rawValue: 3)
  /// Uses big-endian 64-bit DMA segments.
  public static let bigEndian64 = Self(rawValue: 4)
  /// Uses little-endian 64-bit DMA segments.
  public static let littleEndian64 = Self(rawValue: 5)
  /// The DriverKit wire value.
  public let rawValue: UInt16
  /// Creates a value from its DriverKit raw representation.
  public init(rawValue: UInt16) { self.rawValue = rawValue }
}

/// SCSI Parallel Interface negotiation features.
public struct SCSIParallelFeatures: OptionSet, Sendable, Hashable {
  /// Supports 16-bit wide data transfers.
  public static let wideDataTransfer = Self(rawValue: 1 << 0)
  /// Supports synchronous data transfers.
  public static let synchronousDataTransfer = Self(rawValue: 1 << 1)
  /// Supports quick arbitration and selection.
  public static let quickArbitrationAndSelection = Self(rawValue: 1 << 2)
  /// Supports double-transition transfers.
  public static let doubleTransitionDataTransfers = Self(rawValue: 1 << 3)
  /// Supports information-unit transfers.
  public static let informationUnitTransfers = Self(rawValue: 1 << 4)
  /// The DriverKit wire value.
  public let rawValue: UInt32
  /// Creates a value from its DriverKit raw representation.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// A requested negotiation action for one SCSI parallel feature.
public struct SCSIParallelFeatureRequest: RawRepresentable, Sendable, Hashable {
  /// Keeps the current negotiation state.
  public static let noNegotiation = Self(rawValue: 0)
  /// Attempts negotiation for the feature.
  public static let attemptNegotiation = Self(rawValue: 1)
  /// Clears negotiation for the feature.
  public static let clearNegotiation = Self(rawValue: 2)
  /// The DriverKit wire value.
  public let rawValue: UInt32
  /// Creates a value from its DriverKit raw representation.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// The negotiation result reported for one SCSI parallel feature.
public struct SCSIParallelFeatureResult: RawRepresentable, Sendable, Hashable {
  /// The negotiation state was unchanged.
  public static let unchanged = Self(rawValue: 0)
  /// The negotiation state was cleared.
  public static let cleared = Self(rawValue: 1)
  /// The negotiation succeeded.
  public static let success = Self(rawValue: 2)
  /// The DriverKit wire value.
  public let rawValue: UInt32
  /// Creates a value from its DriverKit raw representation.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// A SCSI task queueing attribute.
public struct SCSITaskAttribute: RawRepresentable, Sendable, Hashable {
  /// A simple queued task.
  public static let simple = Self(rawValue: 0)
  /// An ordered queued task.
  public static let ordered = Self(rawValue: 1)
  /// A head-of-queue task.
  public static let headOfQueue = Self(rawValue: 2)
  /// An auto-contingent-allegiance task.
  public static let autoContingentAllegiance = Self(rawValue: 3)
  /// The DriverKit wire value.
  public let rawValue: UInt32
  /// Creates a value from its DriverKit raw representation.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// Direction of the data phase for a SCSI task.
public struct SCSIDataTransferDirection: RawRepresentable, Sendable, Hashable {
  /// No data phase.
  public static let none = Self(rawValue: 0)
  /// Data moves from initiator to target.
  public static let initiatorToTarget = Self(rawValue: 1)
  /// Data moves from target to initiator.
  public static let targetToInitiator = Self(rawValue: 2)
  /// The DriverKit wire value.
  public let rawValue: UInt32
  /// Creates a value from its DriverKit raw representation.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// DriverKit service response for a SCSI request.
public struct SCSIServiceResponse: RawRepresentable, Sendable, Hashable {
  /// The asynchronous request remains in process.
  public static let requestInProcess = Self(rawValue: 0)
  /// Delivery failed or the target failed.
  public static let deliveryOrTargetFailure = Self(rawValue: 1)
  /// The task completed.
  public static let taskComplete = Self(rawValue: 2)
  /// The linked command completed.
  public static let linkCommandComplete = Self(rawValue: 3)
  /// The task-management function completed.
  public static let functionComplete = Self(rawValue: 4)
  /// The task-management function was rejected.
  public static let functionRejected = Self(rawValue: 5)
  /// The DriverKit wire value.
  public let rawValue: UInt32
  /// Creates a value from its DriverKit raw representation.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// SCSI status byte or DriverKit protocol-layer status.
public struct SCSITaskStatus: RawRepresentable, Sendable, Hashable {
  /// The target returned GOOD status.
  public static let good = Self(rawValue: 0x00)
  /// The target returned CHECK CONDITION.
  public static let checkCondition = Self(rawValue: 0x02)
  /// The target returned BUSY.
  public static let busy = Self(rawValue: 0x08)
  /// The target reported a reservation conflict.
  public static let reservationConflict = Self(rawValue: 0x18)
  /// The target task set is full.
  public static let taskSetFull = Self(rawValue: 0x28)
  /// No target status is available.
  public static let noStatus = Self(rawValue: 0xFF)
  /// The DriverKit wire value.
  public let rawValue: UInt32
  /// Creates a value from its DriverKit raw representation.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// One non-bundled SCSI command forwarded from DriverKit.
public struct SCSIParallelTask: Sendable, Hashable {
  /// The runtime identifier used to complete this request.
  public let requestID: UInt32
  /// The target device identifier.
  public let targetIdentifier: UInt64
  /// The framework controller-task identifier.
  public let controllerTaskIdentifier: UInt64
  /// The maximum bytes requested by the framework.
  public let requestedTransferCount: UInt64
  /// The device-visible address of the task data buffer.
  public let bufferIOVMAddress: UInt64
  /// The queue tag assigned to the task.
  public let taskTagIdentifier: UInt64
  /// The task timeout in milliseconds.
  public let timeoutMilliseconds: UInt32
  /// The task queueing attribute.
  public let taskAttribute: SCSITaskAttribute
  /// The direction of the task data phase.
  public let transferDirection: SCSIDataTransferDirection
  /// The fixed eight-byte logical-unit address.
  public let logicalUnitBytes: [UInt8]
  /// The command descriptor bytes.
  public let commandDescriptorBlock: [UInt8]
  /// The requested feature-negotiation actions.
  public let featureRequests: [SCSIParallelFeatureRequest]
}

/// A completion supplied by Swift for one pending parallel task.
public struct SCSIParallelTaskCompletion: Sendable, Hashable {
  /// The runtime identifier used to complete this request.
  public let requestID: UInt32
  /// The SCSI status returned to DriverKit.
  public let taskStatus: SCSITaskStatus
  /// The service response returned to DriverKit.
  public let serviceResponse: SCSIServiceResponse
  /// The number of bytes transferred by the hardware.
  public let bytesTransferred: UInt64
  /// The feature-negotiation results.
  public let featureResults: [SCSIParallelFeatureResult]
  /// Optional autosense bytes, limited to 256 bytes.
  public let senseData: [UInt8]

  /// Creates a validated completion payload.
  public init(
    requestID: UInt32,
    taskStatus: SCSITaskStatus = .good,
    serviceResponse: SCSIServiceResponse = .taskComplete,
    bytesTransferred: UInt64 = 0,
    featureResults: [SCSIParallelFeatureResult] = [],
    senseData: [UInt8] = []
  ) throws {
    guard featureResults.count <= 5, senseData.count <= 256, taskStatus.rawValue <= UInt8.max,
      serviceResponse.rawValue <= SCSIServiceResponse.functionRejected.rawValue,
      featureResults.allSatisfy({ $0.rawValue <= SCSIParallelFeatureResult.success.rawValue })
    else { throw SCSIControllerRuntimeError.invalidCompletion }
    self.requestID = requestID
    self.taskStatus = taskStatus
    self.serviceResponse = serviceResponse
    self.bytesTransferred = bytesTransferred
    self.featureResults = featureResults
    self.senseData = senseData
  }
}

/// A SCSI task-management function forwarded to Swift.
public enum SCSITaskManagementRequest: Sendable, Hashable {
  case abortTask(targetIdentifier: UInt64, logicalUnit: UInt64, taskTag: UInt64)
  case abortTaskSet(targetIdentifier: UInt64, logicalUnit: UInt64)
  case clearAutoContingentAllegiance(targetIdentifier: UInt64, logicalUnit: UInt64)
  case clearTaskSet(targetIdentifier: UInt64, logicalUnit: UInt64)
  case logicalUnitReset(targetIdentifier: UInt64, logicalUnit: UInt64)
  case targetReset(targetIdentifier: UInt64)
}

/// A controller callback forwarded by the native runtime.
public enum SCSIControllerEvent: Sendable, Hashable {
  case initializeTarget(UInt64)
  case parallelTask(SCSIParallelTask)
  case taskManagement(SCSITaskManagementRequest)
}

/// A malformed SCSI controller event or completion.
public enum SCSIControllerRuntimeError: Error, Sendable, Equatable {
  case invalidPayload
  case invalidEventKind(UInt32)
  case invalidCompletion
}
