import Foundation

/// A SCSI protocol-characteristics registry key accepted by the controller property calls.
///
/// `IOUserSCSIParallelInterfaceController.iig` lists the valid keys for
/// `UserSetHBAProperties`, `UserRemoveHBAProperties`, and `UserSetTargetProperties`; every value
/// is an `OSString`.
public struct SCSIProtocolPropertyKey: RawRepresentable, Sendable, Hashable {
  /// `kIOPropertyVendorNameKey`; HBA only.
  public static let vendorName = Self(rawValue: "Vendor Name")
  /// `kIOPropertyProductNameKey`; HBA only.
  public static let productName = Self(rawValue: "Product Name")
  /// `kIOPropertyProductRevisionLevelKey`; HBA only.
  public static let productRevisionLevel = Self(rawValue: "Product Revision Level")
  /// `kIOPropertyPortDescriptionKey`; HBA only.
  public static let portDescription = Self(rawValue: "Port Description")
  /// `kIOPropertyPortSpeedKey`; HBA only.
  public static let portSpeed = Self(rawValue: "Port Speed")
  /// `kIOPropertyPortTopologyKey`; HBA only.
  public static let portTopology = Self(rawValue: "Port Topology")
  /// `kIOPropertySCSIParallelSignalingTypeKey`; HBA only.
  public static let parallelSignalingType = Self(rawValue: "SCSI Parallel Signaling Type")
  /// `kIOPropertyFibreChannelCableDescriptionKey`; HBA only.
  public static let fibreChannelCableDescription = Self(rawValue: "Fibre Channel Cabling Type")
  /// `kIOPropertyFibreChannelNodeWorldWideNameKey`.
  public static let fibreChannelNodeWorldWideName = Self(rawValue: "Node World Wide Name")
  /// `kIOPropertyFibreChannelPortWorldWideNameKey`.
  public static let fibreChannelPortWorldWideName = Self(rawValue: "Port World Wide Name")
  /// `kIOPropertyFibreChannelAddressIdentifierKey`.
  public static let fibreChannelAddressIdentifier = Self(rawValue: "Address Identifier")
  /// `kIOPropertyFibreChannelALPAKey`.
  public static let fibreChannelALPA = Self(rawValue: "AL_PA")
  /// `kIOPropertySASAddressKey`.
  public static let sasAddress = Self(rawValue: "SAS Address")

  /// The registry key string.
  public let rawValue: String
  /// Creates a key from its registry string.
  public init(rawValue: String) { self.rawValue = rawValue }
}

/// I/O constraints reported through `UserReportHBAConstraints` while the controller initializes.
///
/// The generated runtime reports every key the header marks as required, so DriverKit never sees
/// a partial dictionary.
public struct SCSIControllerConstraints: Sendable, Hashable {
  /// `kIOMaximumSegmentCountReadKey`.
  public let maximumSegmentCountRead: UInt64
  /// `kIOMaximumSegmentCountWriteKey`.
  public let maximumSegmentCountWrite: UInt64
  /// `kIOMaximumSegmentByteCountReadKey`.
  public let maximumSegmentByteCountRead: UInt64
  /// `kIOMaximumSegmentByteCountWriteKey`.
  public let maximumSegmentByteCountWrite: UInt64
  /// `kIOMinimumSegmentAlignmentByteCountKey`, a power of two.
  public let minimumSegmentAlignmentByteCount: UInt64
  /// `kIOMaximumSegmentAddressableBitCountKey`, from 1 through 64.
  public let maximumSegmentAddressableBitCount: UInt64
  /// `kIOMinimumHBADataAlignmentMaskKey`, a mask of the form `2^n - 1`.
  public let minimumHBADataAlignmentMask: UInt64
  /// Reports `kIOHierarchicalLogicalUnitSupportKey` as true when set.
  public let supportsHierarchicalLogicalUnits: Bool

  /// Creates controller I/O constraints; the generator validates them.
  public init(
    maximumSegmentCountRead: UInt64,
    maximumSegmentCountWrite: UInt64,
    maximumSegmentByteCountRead: UInt64,
    maximumSegmentByteCountWrite: UInt64,
    minimumSegmentAlignmentByteCount: UInt64 = 4,
    maximumSegmentAddressableBitCount: UInt64 = 64,
    minimumHBADataAlignmentMask: UInt64 = 3,
    supportsHierarchicalLogicalUnits: Bool = false
  ) {
    self.maximumSegmentCountRead = maximumSegmentCountRead
    self.maximumSegmentCountWrite = maximumSegmentCountWrite
    self.maximumSegmentByteCountRead = maximumSegmentByteCountRead
    self.maximumSegmentByteCountWrite = maximumSegmentByteCountWrite
    self.minimumSegmentAlignmentByteCount = minimumSegmentAlignmentByteCount
    self.maximumSegmentAddressableBitCount = maximumSegmentAddressableBitCount
    self.minimumHBADataAlignmentMask = minimumHBADataAlignmentMask
    self.supportsHierarchicalLogicalUnits = supportsHierarchicalLogicalUnits
  }

  var isValid: Bool {
    maximumSegmentCountRead > 0 && maximumSegmentCountWrite > 0 && maximumSegmentByteCountRead > 0
      && maximumSegmentByteCountWrite > 0 && minimumSegmentAlignmentByteCount > 0
      && minimumSegmentAlignmentByteCount & (minimumSegmentAlignmentByteCount - 1) == 0
      && (1...64).contains(maximumSegmentAddressableBitCount)
      && minimumHBADataAlignmentMask & (minimumHBADataAlignmentMask &+ 1) == 0
  }
}

/// Limits of the SCSI controller property and task-data commands.
public enum SCSIControllerLimits {
  /// The most properties one set or remove call carries.
  public static let maximumPropertyCount = RuntimeSCSILimits.maximumPropertyCount
  /// The longest property key, in UTF-8 bytes.
  public static let maximumPropertyKeyLength = RuntimeSCSILimits.propertyKeyMaximumLength
  /// The longest property value, in UTF-8 bytes.
  public static let maximumPropertyValueLength = RuntimeSCSILimits.propertyValueMaximumLength
  /// The most task-data bytes one read returns.
  public static let maximumTaskDataReadLength =
    RuntimeMessage.maximumSize - RuntimeMessage.headerSize
  /// The most task-data bytes one write carries.
  public static let maximumTaskDataWriteLength =
    RuntimeMessage.maximumSize - RuntimeMessage.headerSize - RuntimeSchema.commandHeaderSize - 16
}

/// The result of the `UserCreateTargetForID` call that
/// ``DriverContext/scsiCreateTarget(_:properties:)`` queued.
public struct SCSITargetCreationResult: Sendable, Hashable {
  /// The target identifier passed to ``DriverContext/scsiCreateTarget(_:properties:)``.
  public let target: UInt64
  /// The `IOReturn` status of `UserCreateTargetForID`. Zero is success.
  public let status: Int32

  /// Whether DriverKit created the target.
  public var succeeded: Bool { status == 0 }

  init(runtimePayload data: Data) throws {
    guard data.count == 16, try data.readRuntimeInteger(at: 12) as UInt32 == 0 else {
      throw SCSIControllerRuntimeError.invalidPayload
    }
    target = try data.readRuntimeInteger(at: 0)
    status = try data.readRuntimeInteger(at: 8)
  }
}
