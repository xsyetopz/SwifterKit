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
    HIDSubmitInputReport = 0x0300,
    HIDGetRuntimeStatistics = 0x0301,
    PCIRead = 0x0400,
    PCIWrite = 0x0401,
    PCIGetBARInfo = 0x0402,
    PCIGetLocation = 0x0403,
    PCIFindCapability = 0x0404,
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
};

static constexpr uint32_t kSwifterKitEventInterrupt = 0x0100;
static constexpr uint32_t kSwifterKitEventHIDReport = 0x0300;
static constexpr uint32_t kSwifterKitEventSerial = 0x0600;
static constexpr uint32_t kSwifterKitEventBlockStorage = 0x0700;
static constexpr uint32_t kSwifterKitEventMIDI = 0x0800;
static constexpr uint32_t kSwifterKitEventNetwork = 0x0900;
static constexpr uint32_t kSwifterKitEventAudio = 0x0A00;
static constexpr uint32_t kSwifterKitEventSCSIParallelTask = 0x0B00;
static constexpr uint32_t kSwifterKitEventSCSIManagement = 0x0B01;
static constexpr uint32_t kSwifterKitEventVideo = 0x0C00;

#endif
