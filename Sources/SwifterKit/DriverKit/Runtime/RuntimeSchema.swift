// The single declaration of the runtime wire protocol's constants.
//
// `RuntimeSchemaHeader` renders these declarations into the checked-in native header
// `Resources/DriverKitExtension/Sources/SwifterKitRuntimeSchema.h`. `RuntimeSchemaTests` fails
// when that header drifts; regenerate it with `SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter
// RuntimeSchemaTests`. Packed payload layouts stay hand-written in `SwifterKitRuntimeProtocol.h`,
// which checks its fixed sizes against the sizes declared here.

/// Fixed wire-protocol values shared by the Swift host and the native extension.
enum RuntimeSchema {
  /// The value that begins every runtime message.
  static let magic: UInt32 = 0x5357_4B54
  /// The oldest protocol version either side speaks.
  static let minimumVersion: UInt16 = 2
  /// The newest protocol version either side speaks.
  static let maximumVersion: UInt16 = 2
  /// The largest complete message, header included, accepted in either direction.
  static let maximumMessageSize = 65_536
  /// The fixed message header size.
  static let headerSize = 24
  /// The fixed command header size that precedes command payload bytes.
  static let commandHeaderSize = 16
  /// The handshake request payload size: minimum version, maximum version, reserved bits.
  static let handshakeRequestSize = 8
  /// The handshake response payload size: version, reserved bits, capabilities.
  static let handshakeResponseSize = 16
}

/// Flags that modify runtime message handling.
enum RuntimeMessageFlag: UInt32, CaseIterable { case expectsResponse = 0x1 }

/// IOKit external-method selectors the runtime user client accepts.
enum RuntimeSelector: UInt32, CaseIterable {
  /// A synchronous runtime message exchange through `IOConnectCallStructMethod`.
  case transact = 0
  /// An asynchronous registration whose completion the extension signals when events are pending.
  case eventNotification = 1
}

/// Capability bits advertised by the native extension during the handshake.
enum RuntimeCapability: UInt64, CaseIterable {
  case memory = 0x1
  case interrupts = 0x2
  case usb = 0x4
  case hid = 0x8
  case pci = 0x10
  case serial = 0x20
  case networking = 0x40
  case audio = 0x80
  case midi = 0x100
  case blockStorage = 0x200
  case scsi = 0x400
  case video = 0x800
}

/// Operations the native extension executes for a command message.
enum RuntimeOpcode: UInt32, CaseIterable {
  case ping = 0
  case pollEvent = 1
  case interruptSetEnabled = 0x0100
  case interruptGetType = 0x0101
  case interruptGetLast = 0x0102
  case usbControlTransfer = 0x0200
  case usbPipeTransfer = 0x0201
  case usbClearStall = 0x0202
  case usbSelectAlternateSetting = 0x0203
  case usbDeviceSetConfiguration = 0x0210
  case usbDeviceReset = 0x0211
  case usbGetDeviceSpeed = 0x0212
  case usbGetDeviceAddress = 0x0213
  case usbGetPortStatus = 0x0214
  case usbGetFrameNumber = 0x0215
  case usbGetCurrentMicroframe = 0x0216
  case usbGetReferenceMicroframe = 0x0217
  case usbCopyDeviceDescriptor = 0x0218
  case usbCopyConfigurationDescriptor = 0x0219
  case usbCopyStringDescriptor = 0x021A
  case usbCopyCapabilityDescriptors = 0x021B
  case usbCopyDescriptor = 0x021C
  case usbCopyInterfaces = 0x021D
  case usbCopyInterfaceDescriptor = 0x021E
  case usbSetIdlePolicy = 0x021F
  case usbGetIdlePolicy = 0x0220
  case usbAbortDeviceRequests = 0x0221
  case usbPipeAsyncIO = 0x0230
  case usbPipeAbort = 0x0231
  case usbPipeSetIdlePolicy = 0x0232
  case usbPipeGetIdlePolicy = 0x0233
  case usbPipeGetDescriptors = 0x0234
  case usbPipeGetSpeed = 0x0235
  case usbPipeGetDeviceAddress = 0x0236
  case usbPipeIsochIO = 0x0237
  case hidSubmitInputReport = 0x0300
  case hidGetRuntimeStatistics = 0x0301
  case pciRead = 0x0400
  case pciWrite = 0x0401
  case pciGetBARInfo = 0x0402
  case pciGetLocation = 0x0403
  case pciFindCapability = 0x0404
  case pciReset = 0x0410
  case pciSaveDeviceState = 0x0411
  case pciRestoreDeviceState = 0x0412
  case pciHasPowerManagement = 0x0413
  case pciEnablePowerManagement = 0x0414
  case pciGetLinkSpeed = 0x0415
  case pciSetLinkSpeed = 0x0416
  case pciSetASPMState = 0x0417
  case pciSetProperties = 0x0418
  case memoryAllocate = 0x0500
  case memoryRelease = 0x0501
  case memorySetLength = 0x0502
  case memoryRead = 0x0503
  case memoryWrite = 0x0504
  case memoryGetInfo = 0x0505
  case memoryPrepareDMA = 0x0506
  case memoryCompleteDMA = 0x0507
  case serialEnqueueReceive = 0x0600
  case serialDequeueTransmit = 0x0601
  case serialSetModemStatus = 0x0602
  case serialReportReceiveErrors = 0x0603
  case blockStorageComplete = 0x0700
  case blockStorageCompleteIO = 0x0701
  case midiSend = 0x0800
  case networkReceive = 0x0900
  case networkCompleteTransmit = 0x0901
  case networkReportLink = 0x0902
  case audioReadStream = 0x0A00
  case audioWriteStream = 0x0A01
  case audioGetIOState = 0x0A02
  case audioUpdateTimestamp = 0x0A03
  case audioRequestSampleRate = 0x0A04
  case audioGetControl = 0x0A05
  case audioSetControl = 0x0A06
  case audioGetCustomProperty = 0x0A07
  case audioSetCustomProperty = 0x0A08
  case scsiCompleteParallelTask = 0x0B00
  case scsiPeripheralSendCDB = 0x0B10
  case scsiPeripheralSuspendServices = 0x0B11
  case scsiPeripheralResumeServices = 0x0B12
  case scsiPeripheralReset = 0x0B13
  case scsiPeripheralReportMediumBlockSize = 0x0B14
  case videoReadBuffer = 0x0C00
  case videoWriteBuffer = 0x0C01
  case videoEnqueueOutput = 0x0C02
  case videoDequeueInput = 0x0C03
  case videoNotifyOutput = 0x0C04
  case videoUpdateTimestamp = 0x0C05
  case videoRequestSampleRate = 0x0C06
  case videoGetControl = 0x0C07
  case videoSetControl = 0x0C08
  case videoGetCustomProperty = 0x0C09
  case videoSetCustomProperty = 0x0C0A
}

/// Types of events the native extension queues for the Swift host.
enum RuntimeEventType: UInt32, CaseIterable {
  case interrupt = 0x0100
  case usbPipeIO = 0x0200
  case usbPipeIsochIO = 0x0201
  case hidReport = 0x0300
  case serial = 0x0600
  case blockStorage = 0x0700
  case midi = 0x0800
  case network = 0x0900
  case audio = 0x0A00
  case scsiParallelTask = 0x0B00
  case scsiManagement = 0x0B01
  case video = 0x0C00
}
