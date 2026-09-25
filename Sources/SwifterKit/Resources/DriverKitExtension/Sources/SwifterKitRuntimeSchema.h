// Generated from Sources/SwifterKit/DriverKit/Runtime/RuntimeSchema.swift. Do not edit.
// Regenerate: SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter RuntimeSchemaTests

#ifndef SwifterKitRuntimeSchema_h
#define SwifterKitRuntimeSchema_h

#include <stdint.h>

static constexpr uint32_t kSwifterKitRuntimeMagic = 0x53574B54;
static constexpr uint16_t kSwifterKitRuntimeVersionMinimum = 2;
static constexpr uint16_t kSwifterKitRuntimeVersionMaximum = 2;
static constexpr uint32_t kSwifterKitRuntimeMaximumMessageSize = 65536;
static constexpr uint32_t kSwifterKitRuntimeHeaderSize = 24;
static constexpr uint32_t kSwifterKitRuntimeCommandHeaderSize = 16;
static constexpr uint32_t kSwifterKitRuntimeHandshakeRequestSize = 8;
static constexpr uint32_t kSwifterKitRuntimeHandshakeResponseSize = 16;

static constexpr uint32_t kSwifterKitMessageFlagExpectsResponse = 0x1;

static constexpr uint64_t kSwifterKitSelectorTransact = 0;
static constexpr uint64_t kSwifterKitSelectorEventNotification = 1;

static constexpr uint64_t kSwifterKitCapabilityMemory = 0x1;
static constexpr uint64_t kSwifterKitCapabilityInterrupts = 0x2;
static constexpr uint64_t kSwifterKitCapabilityUSB = 0x4;
static constexpr uint64_t kSwifterKitCapabilityHID = 0x8;
static constexpr uint64_t kSwifterKitCapabilityPCI = 0x10;
static constexpr uint64_t kSwifterKitCapabilitySerial = 0x20;
static constexpr uint64_t kSwifterKitCapabilityNetworking = 0x40;
static constexpr uint64_t kSwifterKitCapabilityAudio = 0x80;
static constexpr uint64_t kSwifterKitCapabilityMIDI = 0x100;
static constexpr uint64_t kSwifterKitCapabilityBlockStorage = 0x200;
static constexpr uint64_t kSwifterKitCapabilitySCSI = 0x400;
static constexpr uint64_t kSwifterKitCapabilityVideo = 0x800;

enum class SwifterKitRuntimeMessageKind : uint16_t {
    Handshake = 1,
    Command = 2,
    Response = 3,
    Event = 4,
    Error = 5,
};

enum class SwifterKitRuntimeOpcode : uint32_t {
    Ping = 0x0000,
    PollEvent = 0x0001,
    InterruptSetEnabled = 0x0100,
    InterruptGetType = 0x0101,
    InterruptGetLast = 0x0102,
    USBControlTransfer = 0x0200,
    USBPipeTransfer = 0x0201,
    USBClearStall = 0x0202,
    USBSelectAlternateSetting = 0x0203,
    USBDeviceSetConfiguration = 0x0210,
    USBDeviceReset = 0x0211,
    USBGetDeviceSpeed = 0x0212,
    USBGetDeviceAddress = 0x0213,
    USBGetPortStatus = 0x0214,
    USBGetFrameNumber = 0x0215,
    USBGetCurrentMicroframe = 0x0216,
    USBGetReferenceMicroframe = 0x0217,
    USBCopyDeviceDescriptor = 0x0218,
    USBCopyConfigurationDescriptor = 0x0219,
    USBCopyStringDescriptor = 0x021A,
    USBCopyCapabilityDescriptors = 0x021B,
    USBCopyDescriptor = 0x021C,
    USBCopyInterfaces = 0x021D,
    USBCopyInterfaceDescriptor = 0x021E,
    USBSetIdlePolicy = 0x021F,
    USBGetIdlePolicy = 0x0220,
    USBAbortDeviceRequests = 0x0221,
    USBPipeAsyncIO = 0x0230,
    USBPipeAbort = 0x0231,
    USBPipeSetIdlePolicy = 0x0232,
    USBPipeGetIdlePolicy = 0x0233,
    USBPipeGetDescriptors = 0x0234,
    USBPipeGetSpeed = 0x0235,
    USBPipeGetDeviceAddress = 0x0236,
    USBPipeIsochIO = 0x0237,
    HIDSubmitInputReport = 0x0300,
    HIDGetRuntimeStatistics = 0x0301,
    PCIRead = 0x0400,
    PCIWrite = 0x0401,
    PCIGetBARInfo = 0x0402,
    PCIGetLocation = 0x0403,
    PCIFindCapability = 0x0404,
    PCIReset = 0x0410,
    PCISaveDeviceState = 0x0411,
    PCIRestoreDeviceState = 0x0412,
    PCIHasPowerManagement = 0x0413,
    PCIEnablePowerManagement = 0x0414,
    PCIGetLinkSpeed = 0x0415,
    PCISetLinkSpeed = 0x0416,
    PCISetASPMState = 0x0417,
    PCISetProperties = 0x0418,
    MemoryAllocate = 0x0500,
    MemoryRelease = 0x0501,
    MemorySetLength = 0x0502,
    MemoryRead = 0x0503,
    MemoryWrite = 0x0504,
    MemoryGetInfo = 0x0505,
    MemoryPrepareDMA = 0x0506,
    MemoryCompleteDMA = 0x0507,
    SerialEnqueueReceive = 0x0600,
    SerialDequeueTransmit = 0x0601,
    SerialSetModemStatus = 0x0602,
    SerialReportReceiveErrors = 0x0603,
    BlockStorageComplete = 0x0700,
    BlockStorageCompleteIO = 0x0701,
    MIDISend = 0x0800,
    NetworkReceive = 0x0900,
    NetworkCompleteTransmit = 0x0901,
    NetworkReportLink = 0x0902,
    AudioReadStream = 0x0A00,
    AudioWriteStream = 0x0A01,
    AudioGetIOState = 0x0A02,
    AudioUpdateTimestamp = 0x0A03,
    AudioRequestSampleRate = 0x0A04,
    AudioGetControl = 0x0A05,
    AudioSetControl = 0x0A06,
    AudioGetCustomProperty = 0x0A07,
    AudioSetCustomProperty = 0x0A08,
    SCSICompleteParallelTask = 0x0B00,
    SCSIPeripheralSendCDB = 0x0B10,
    SCSIPeripheralSuspendServices = 0x0B11,
    SCSIPeripheralResumeServices = 0x0B12,
    SCSIPeripheralReset = 0x0B13,
    SCSIPeripheralReportMediumBlockSize = 0x0B14,
    VideoReadBuffer = 0x0C00,
    VideoWriteBuffer = 0x0C01,
    VideoEnqueueOutput = 0x0C02,
    VideoDequeueInput = 0x0C03,
    VideoNotifyOutput = 0x0C04,
    VideoUpdateTimestamp = 0x0C05,
    VideoRequestSampleRate = 0x0C06,
    VideoGetControl = 0x0C07,
    VideoSetControl = 0x0C08,
    VideoGetCustomProperty = 0x0C09,
    VideoSetCustomProperty = 0x0C0A,
    ServiceSetProperties = 0x0D00,
    ServiceCopyProperties = 0x0D01,
    ServiceRemoveProperty = 0x0D02,
    ServiceSearchProperty = 0x0D03,
    ServiceCopyProviderProperties = 0x0D04,
    ServiceCopyName = 0x0D05,
    ServiceGetRegistryEntryID = 0x0D06,
    ServiceChangePowerState = 0x0D10,
    ServiceSetPowerOverride = 0x0D11,
    ServiceCreatePMAssertion = 0x0D12,
    ServiceReleasePMAssertion = 0x0D13,
    ServiceCompletePowerState = 0x0D14,
    ServiceAdjustBusy = 0x0D20,
    ServiceGetBusyState = 0x0D21,
    ServiceRequireMaxBusStall = 0x0D22,
    ServiceTerminate = 0x0D23,
    ServiceCopySystemStateItem = 0x0D30,
    ServiceCreateSystemStateItem = 0x0D31,
    ServiceSetSystemStateItem = 0x0D32,
    ServiceSendCoreAnalyticsEvent = 0x0D33,
    TimerStart = 0x0E00,
    TimerCancel = 0x0E01,
    WatchServices = 0x0E10,
    WatchSystemState = 0x0E11,
    WatchCancel = 0x0E12,
};

static constexpr uint32_t kSwifterKitEventInterrupt = 0x0100;
static constexpr uint32_t kSwifterKitEventUSBPipeIO = 0x0200;
static constexpr uint32_t kSwifterKitEventUSBPipeIsochIO = 0x0201;
static constexpr uint32_t kSwifterKitEventHIDReport = 0x0300;
static constexpr uint32_t kSwifterKitEventSerial = 0x0600;
static constexpr uint32_t kSwifterKitEventBlockStorage = 0x0700;
static constexpr uint32_t kSwifterKitEventMIDI = 0x0800;
static constexpr uint32_t kSwifterKitEventNetwork = 0x0900;
static constexpr uint32_t kSwifterKitEventAudio = 0x0A00;
static constexpr uint32_t kSwifterKitEventSCSIParallelTask = 0x0B00;
static constexpr uint32_t kSwifterKitEventSCSIManagement = 0x0B01;
static constexpr uint32_t kSwifterKitEventVideo = 0x0C00;
static constexpr uint32_t kSwifterKitEventServicePowerState = 0x0D00;
static constexpr uint32_t kSwifterKitEventTimer = 0x0E00;
static constexpr uint32_t kSwifterKitEventWatchServices = 0x0E10;
static constexpr uint32_t kSwifterKitEventWatchSystemState = 0x0E11;

#endif
