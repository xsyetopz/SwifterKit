// SCSI, block-storage, and serial wire constants.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeSchema.h`, which
// `SwifterKitRuntimeSCSI.cpp`, `SwifterKitRuntimeSCSIControl.cpp`,
// `SwifterKitRuntimeBlockStorage.cpp`, `SwifterKitRuntimeSerial.cpp`, and
// `SwifterKitRuntimeUSBSerial.cpp` read, so neither side spells a value twice.

/// The task-management call a `scsiManagement` event forwards; see
/// `SwifterKitSCSIManagementEvent`.
enum RuntimeSCSIManagementKind: UInt32, CaseIterable {
  case initializeTarget = 1
  case abortTask = 2
  case abortTaskSet = 3
  case clearACA = 4
  case clearTaskSet = 5
  case logicalUnitReset = 6
  case targetReset = 7
}

/// Bounds of the SCSI controller property commands.
enum RuntimeSCSILimits {
  /// The most properties one set or remove command carries.
  static let maximumPropertyCount = 32
  /// The longest property key, in UTF-8 bytes; the wire carries it in a `u16`.
  static let propertyKeyMaximumLength = 127
  /// The longest property value, in UTF-8 bytes; the wire carries it in a `u16`.
  static let propertyValueMaximumLength = 1_024
  /// The most parallel-feature requests or results one task carries,
  /// `kSCSIParallelFeature_TotalFeatureCount`.
  static let maximumFeatureRequests = 5
  /// The longest Command Descriptor Block, `kSCSICDBSize_Maximum`.
  static let commandDescriptorBlockMaximumSize = 16
  /// The most data bytes one peripheral CDB command moves through a runtime message.
  static let peripheralMaximumDataLength = 61_440
}

/// The `IOUserBlockStorageDevice` call a `blockStorage` event forwards.
enum RuntimeBlockStorageRequestKind: UInt32, CaseIterable {
  case eject = 1
  case synchronize = 2
  case unmap = 3
  case read = 4
  case write = 5
}

/// The `IOUserSerial` callback a `serial` event reports.
enum RuntimeSerialEventKind: UInt32, CaseIterable {
  case activate = 1
  case deactivate = 2
  case receiveSpaceAvailable = 3
  case transmitDataAvailable = 4
  case resetFIFO = 5
  case sendBreak = 6
  case programUART = 7
  case programBaudRate = 8
  case programModemControl = 9
  case programLatencyTimer = 10
  case programFlowControl = 11
}

/// The `IOUserUSBSerial` hook a `usbSerialPacket` event copies.
enum RuntimeUSBSerialPacketKind: UInt32, CaseIterable {
  /// `handleRxPacket`, a completed bulk IN transfer.
  case received = 1
  /// `handleInterruptPacket`, a completed interrupt IN transfer.
  case interrupt = 2
}
