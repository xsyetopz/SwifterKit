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
  case usbAsyncDeviceRequest = 0x0240
  case usbPipeCreateBundleRing = 0x0250
  case usbPipeEnqueueBundled = 0x0251
  case usbPipeReleaseBundleRing = 0x0252
  case usbPipeAdjust = 0x0260
  case hidSubmitInputReport = 0x0300
  case hidGetRuntimeStatistics = 0x0301
  case hidCompleteGetReport = 0x0310
  case hidCopyElements = 0x0311
  case hidGetElementValue = 0x0312
  case hidSetElementValue = 0x0313
  case hidCommitElement = 0x0314
  case hidCommitElements = 0x0315
  case hidElementConformsTo = 0x0316
  case hidInterfaceGetReport = 0x0317
  case hidInterfaceSetReport = 0x0318
  case hidInterfaceProcessReport = 0x0319
  case hidDispatchKeyboard = 0x0320
  case hidDispatchRelativePointer = 0x0321
  case hidDispatchAbsolutePointer = 0x0322
  case hidDispatchScroll = 0x0323
  case hidDispatchDigitizerStylus = 0x0324
  case hidDispatchDigitizerTouches = 0x0325
  case hidDispatchDigitizerCollection = 0x0326
  case hidDispatchGameController = 0x0327
  case hidDispatchExtendedGameController = 0x0328
  case hidSetLED = 0x0329
  case hidSetLEDState = 0x032A
  case hidServiceConformsTo = 0x032B
  case hidSetEventDriverCategories = 0x032C
  case hidDeviceGetReport = 0x0330
  case hidDeviceSetProtocol = 0x0331
  case hidDeviceSetIdle = 0x0332
  case hidDeviceSetIdlePolicy = 0x0333
  case hidDeviceReset = 0x0334
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
  case networkReportLinkQuality = 0x0910
  case networkReportDataBandwidths = 0x0911
  case networkAddHardwareCounts = 0x0912
  case networkReportNICProxyLimits = 0x0913
  case networkSetPolling = 0x0914
  case networkSetPollerParameters = 0x0915
  case networkReceivePackets = 0x0920
  case networkCompleteTransmits = 0x0921
  case networkSetQueueEnabled = 0x0922
  case networkPurgeTransmitQueue = 0x0923
  case networkServiceTransmitQueue = 0x0924
  case networkCompleteInterfaceCommand = 0x0925
  case audioReadStream = 0x0A00
  case audioWriteStream = 0x0A01
  case audioGetIOState = 0x0A02
  case audioUpdateTimestamp = 0x0A03
  case audioRequestSampleRate = 0x0A04
  case audioGetControl = 0x0A05
  case audioSetControl = 0x0A06
  case audioGetCustomProperty = 0x0A07
  case audioSetCustomProperty = 0x0A08
  case audioGetObjectInfo = 0x0A10
  case audioSetObjectName = 0x0A11
  case audioGetElementName = 0x0A12
  case audioSetElementName = 0x0A13
  case audioPropertiesChanged = 0x0A14
  case audioGetBoxState = 0x0A15
  case audioSetBoxProperty = 0x0A16
  case audioSetBoxOwnership = 0x0A17
  case audioGetClockDeviceState = 0x0A18
  case audioSetClockDeviceProperty = 0x0A19
  case audioSetClockSampleRates = 0x0A1A
  case audioUpdateClockTimestamp = 0x0A1B
  case audioRequestClockSampleRate = 0x0A1C
  case audioCompleteRequest = 0x0A1D
  case audioGetDeviceState = 0x0A20
  case audioSetDeviceProperty = 0x0A21
  case audioSetPreferredChannelLayout = 0x0A22
  case audioGetStreamState = 0x0A23
  case audioSetStreamProperty = 0x0A24
  case audioGetControlInfo = 0x0A25
  case audioSetControlProperty = 0x0A26
  case audioRemoveSelectorItems = 0x0A27
  case audioGetCustomPropertyInfo = 0x0A28
  case audioSetMemberAttachment = 0x0A29
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
  case videoGetObjectInfo = 0x0C10
  case videoSetObjectName = 0x0C11
  case videoGetElementName = 0x0C12
  case videoSetElementName = 0x0C13
  case videoPropertiesChanged = 0x0C14
  case videoGetBoxState = 0x0C15
  case videoSetBoxProperty = 0x0C16
  case videoSetBoxOwnership = 0x0C17
  case videoGetClockDeviceState = 0x0C18
  case videoSetClockDeviceProperty = 0x0C19
  case videoSetClockSampleRates = 0x0C1A
  case videoUpdateClockTimestamp = 0x0C1B
  case videoRequestClockSampleRate = 0x0C1C
  case videoCompleteRequest = 0x0C1D
  case videoNotifyBufferQueue = 0x0C1E
  case videoSetCustomPropertyOwner = 0x0C1F
  case serviceSetProperties = 0x0D00
  case serviceCopyProperties = 0x0D01
  case serviceRemoveProperty = 0x0D02
  case serviceSearchProperty = 0x0D03
  case serviceCopyProviderProperties = 0x0D04
  case serviceCopyName = 0x0D05
  case serviceGetRegistryEntryID = 0x0D06
  case serviceChangePowerState = 0x0D10
  case serviceSetPowerOverride = 0x0D11
  case serviceCreatePMAssertion = 0x0D12
  case serviceReleasePMAssertion = 0x0D13
  case serviceCompletePowerState = 0x0D14
  case serviceAdjustBusy = 0x0D20
  case serviceGetBusyState = 0x0D21
  case serviceRequireMaxBusStall = 0x0D22
  case serviceTerminate = 0x0D23
  case serviceCopySystemStateItem = 0x0D30
  case serviceCreateSystemStateItem = 0x0D31
  case serviceSetSystemStateItem = 0x0D32
  case serviceSendCoreAnalyticsEvent = 0x0D33
  case timerStart = 0x0E00
  case timerCancel = 0x0E01
  case watchServices = 0x0E10
  case watchSystemState = 0x0E11
  case watchCancel = 0x0E12
  case reporterUpdate = 0x0E20
  case reporterRead = 0x0E21
}

/// Types of events the native extension queues for the Swift host.
enum RuntimeEventType: UInt32, CaseIterable {
  case interrupt = 0x0100
  case usbPipeIO = 0x0200
  case usbPipeIsochIO = 0x0201
  case usbDeviceRequest = 0x0210
  case usbPipeBundledIO = 0x0220
  case hidReport = 0x0300
  case hidInputReport = 0x0310
  case hidElementValues = 0x0311
  case hidGetReportRequest = 0x0312
  case hidLEDState = 0x0313
  case hidProperties = 0x0314
  case serial = 0x0600
  case usbSerialPacket = 0x0610
  case blockStorage = 0x0700
  case midi = 0x0800
  case network = 0x0900
  case audio = 0x0A00
  case audioObject = 0x0A01
  case scsiParallelTask = 0x0B00
  case scsiManagement = 0x0B01
  case video = 0x0C00
  case videoObject = 0x0C01
  case servicePowerState = 0x0D00
  case timer = 0x0E00
  case watchServices = 0x0E10
  case watchSystemState = 0x0E11
}
