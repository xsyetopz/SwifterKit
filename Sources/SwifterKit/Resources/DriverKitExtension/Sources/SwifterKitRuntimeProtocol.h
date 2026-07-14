#ifndef SwifterKitRuntimeProtocol_h
#define SwifterKitRuntimeProtocol_h

#include <stdint.h>

static constexpr uint32_t kSwifterKitRuntimeMagic = 0x53574B54;
static constexpr uint16_t kSwifterKitRuntimeVersion = 1;
static constexpr uint64_t kSwifterKitRuntimeCapabilities = 0;
static constexpr uint32_t kSwifterKitRuntimeMaximumMessageSize = 65536;

enum class SwifterKitRuntimeMessageKind : uint16_t {
    Handshake = 1,
    Command = 2,
    Response = 3,
    Event = 4,
    Error = 5,
};

enum class SwifterKitRuntimeOpcode : uint32_t {
    Ping = 0,
    PollEvent = 1,
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

struct __attribute__((packed)) SwifterKitRuntimeHeader {
    uint32_t magic;
    uint16_t version;
    uint16_t kind;
    uint64_t requestID;
    uint32_t payloadLength;
    uint32_t flags;
};

struct __attribute__((packed)) SwifterKitRuntimeCommandHeader {
    uint32_t opcode;
    uint32_t reserved;
    uint64_t requiredCapabilities;
};

struct __attribute__((packed)) SwifterKitInterruptCommandHeader {
    uint32_t index;
    uint8_t enabled;
    uint8_t reserved[3];
};

struct __attribute__((packed)) SwifterKitInterruptEvent {
    uint32_t index;
    uint32_t reserved;
    uint64_t count;
    uint64_t time;
};

struct __attribute__((packed)) SwifterKitUSBControlTransferHeader {
    uint8_t requestType;
    uint8_t request;
    uint16_t value;
    uint16_t index;
    uint16_t length;
    uint32_t timeout;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitUSBPipeTransferHeader {
    uint8_t endpoint;
    uint8_t reserved8;
    uint16_t reserved16;
    uint32_t length;
    uint32_t timeout;
    uint32_t reserved32;
};

struct __attribute__((packed)) SwifterKitPCIAccessHeader {
    uint64_t offset;
    uint64_t value;
    uint32_t options;
    uint8_t memoryIndex;
    uint8_t width;
    uint8_t space;
    uint8_t reserved;
};

struct __attribute__((packed)) SwifterKitPCICapabilityHeader {
    uint32_t identifier;
    uint32_t reserved;
    uint64_t searchOffset;
};

struct __attribute__((packed)) SwifterKitMemoryAllocateHeader {
    uint64_t capacity;
    uint64_t length;
    uint64_t alignment;
    uint32_t direction;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitMemoryAccessHeader {
    uint64_t handle;
    uint64_t offset;
    uint32_t length;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitMemorySetLengthHeader {
    uint64_t handle;
    uint64_t length;
};

struct __attribute__((packed)) SwifterKitMemoryDMAHeader {
    uint64_t handle;
    uint64_t offset;
    uint64_t length;
    uint32_t maximumAddressBits;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitMemoryInfo {
    uint64_t handle;
    uint64_t capacity;
    uint64_t length;
    uint32_t direction;
    uint32_t alignment;
};

struct __attribute__((packed)) SwifterKitMemoryDMAResponseHeader {
    uint64_t flags;
    uint32_t segmentCount;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitHIDReportHeader {
    uint64_t timestamp;
    uint32_t reportType;
    uint32_t options;
    uint32_t reportLength;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitHIDRuntimeStatistics {
    uint64_t inputReportAttempts;
    uint64_t inputReportSuccesses;
    uint64_t inputReportFailures;
};

struct __attribute__((packed)) SwifterKitNetworkReceiveHeader {
    uint32_t length;
    uint8_t linkHeaderLength;
    uint8_t reserved[3];
};

struct __attribute__((packed)) SwifterKitNetworkCompletion {
    uint32_t requestID;
    int32_t status;
};

struct __attribute__((packed)) SwifterKitNetworkLink {
    uint32_t status;
    uint32_t media;
};

struct __attribute__((packed)) SwifterKitNetworkEventHeader {
    uint32_t kind;
    uint32_t requestID;
    uint32_t value;
    uint32_t dataLength;
};

struct __attribute__((packed)) SwifterKitAudioTransferHeader {
    uint32_t streamIndex;
    uint32_t reserved0;
    uint64_t byteOffset;
    uint32_t length;
    uint32_t reserved1;
};

struct __attribute__((packed)) SwifterKitAudioTimestamp {
    uint64_t sampleTime;
    uint64_t hostTime;
};

struct __attribute__((packed)) SwifterKitAudioIOState {
    uint64_t sequence;
    uint32_t operation;
    uint32_t frameCount;
    uint64_t sampleTime;
    uint64_t hostTime;
};

struct __attribute__((packed)) SwifterKitAudioEvent {
    uint32_t kind;
    uint32_t reserved;
    uint64_t value;
};

struct __attribute__((packed)) SwifterKitAudioControlGet {
    uint32_t identifier;
    uint32_t kind;
};

struct __attribute__((packed)) SwifterKitAudioControlValueHeader {
    uint32_t identifier;
    uint32_t kind;
    uint32_t valueCount;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitAudioCustomPropertyHeader {
    uint32_t identifier;
    uint32_t qualifierLength;
    uint32_t valueLength;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitAudioControlEventHeader {
    uint32_t eventKind;
    uint32_t identifier;
    uint32_t valueKind;
    uint32_t valueCount;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitAudioCustomPropertyEventHeader {
    uint32_t eventKind;
    uint32_t identifier;
    uint32_t qualifierLength;
    uint32_t valueLength;
    uint32_t reserved;
};

using SwifterKitVideoControlGet = SwifterKitAudioControlGet;
using SwifterKitVideoControlValueHeader = SwifterKitAudioControlValueHeader;
using SwifterKitVideoCustomPropertyHeader = SwifterKitAudioCustomPropertyHeader;
using SwifterKitVideoControlEventHeader = SwifterKitAudioControlEventHeader;
using SwifterKitVideoCustomPropertyEventHeader = SwifterKitAudioCustomPropertyEventHeader;

struct __attribute__((packed)) SwifterKitVideoTransferHeader {
    uint32_t streamIndex;
    uint32_t bufferIndex;
    uint32_t plane;
    uint32_t byteOffset;
    uint32_t length;
    uint32_t reserved0;
    uint32_t reserved1;
    uint32_t reserved2;
};

struct __attribute__((packed)) SwifterKitVideoQueueEntry {
    uint32_t bufferID;
    uint32_t dataOffset;
    uint32_t dataLength;
    uint32_t controlOffset;
    uint32_t controlLength;
    uint32_t reserved[3];
};

struct __attribute__((packed)) SwifterKitVideoTimestamp {
    uint64_t sampleTime;
    uint64_t hostTime;
};

struct __attribute__((packed)) SwifterKitVideoStreamFormatEvent {
    uint32_t kind;
    uint32_t streamIndex;
    double frameRate;
    uint64_t frameTimeValue;
    uint32_t frameTimeScale;
    uint32_t codec;
    uint32_t codecFlags;
    uint32_t width;
    uint32_t height;
    uint32_t reserved0;
    uint32_t reserved1;
};

struct __attribute__((packed)) SwifterKitVideoEvent {
    uint32_t kind;
    uint32_t reserved;
    uint64_t value;
};

struct __attribute__((packed)) SwifterKitMIDIHeader {
    uint32_t endpointIndex;
    uint32_t wordCount;
};

struct __attribute__((packed)) SwifterKitMIDIEventHeader {
    uint32_t kind;
    uint32_t endpointIndex;
    uint32_t wordCount;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitBlockStorageCompletion {
    uint32_t requestID;
    int32_t status;
};

struct __attribute__((packed)) SwifterKitBlockStorageIOCompletion {
    uint32_t requestID;
    int32_t status;
    uint64_t bytesTransferred;
};

struct __attribute__((packed)) SwifterKitBlockStorageRequestHeader {
    uint32_t kind;
    uint32_t requestID;
};

struct __attribute__((packed)) SwifterKitBlockStorageIORequest {
    uint32_t kind;
    uint32_t requestID;
    uint64_t dmaAddress;
    uint64_t byteCount;
    uint64_t startBlock;
    uint64_t blockCount;
    uint32_t options;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitSerialEvent {
    uint32_t kind;
    uint32_t value;
    uint8_t byte0;
    uint8_t byte1;
    uint8_t byte2;
    uint8_t byte3;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitSCSIPeripheralCommandHeader {
    uint64_t logicalUnitNumber;
    uint32_t timeoutMilliseconds;
    uint32_t requestedDataLength;
    uint8_t commandDescriptorBlock[16];
    uint8_t transferDirection;
    uint8_t requestedSenseLength;
    uint8_t reserved[6];
};

struct __attribute__((packed)) SwifterKitSCSIPeripheralResponseHeader {
    uint32_t taskStatus;
    uint32_t serviceResponse;
    uint64_t realizedDataLength;
    uint8_t senseDataValid;
    uint8_t senseLength;
    uint16_t reserved;
    uint32_t dataLength;
};

struct __attribute__((packed)) SwifterKitSCSIParallelTaskEvent {
    uint32_t requestID;
    uint32_t featureRequestCount;
    uint64_t targetIdentifier;
    uint64_t controllerTaskIdentifier;
    uint64_t requestedTransferCount;
    uint64_t bufferIOVMAddress;
    uint64_t taskTagIdentifier;
    uint32_t timeoutMilliseconds;
    uint8_t taskAttribute;
    uint8_t transferDirection;
    uint8_t commandSize;
    uint8_t reserved;
    uint8_t logicalUnitBytes[8];
    uint8_t commandDescriptorBlock[16];
    uint32_t featureRequests[5];
};

struct __attribute__((packed)) SwifterKitSCSIManagementEvent {
    uint32_t kind;
    uint32_t reserved;
    uint64_t targetIdentifier;
    uint64_t logicalUnit;
    uint64_t taskTag;
};

struct __attribute__((packed)) SwifterKitSCSICompletionHeader {
    uint32_t requestID;
    uint32_t featureResultCount;
    uint32_t taskStatus;
    uint32_t serviceResponse;
    uint64_t bytesTransferred;
    uint32_t senseLength;
    uint32_t featureResults[5];
};

struct __attribute__((packed)) SwifterKitHandshakeResponse {
    SwifterKitRuntimeHeader header;
    uint64_t capabilities;
};

static_assert(sizeof(SwifterKitRuntimeHeader) == 24);
static_assert(sizeof(SwifterKitRuntimeCommandHeader) == 16);
static_assert(sizeof(SwifterKitInterruptCommandHeader) == 8);
static_assert(sizeof(SwifterKitInterruptEvent) == 24);
static_assert(sizeof(SwifterKitHandshakeResponse) == 32);
static_assert(sizeof(SwifterKitSCSIPeripheralCommandHeader) == 40);
static_assert(sizeof(SwifterKitSCSIPeripheralResponseHeader) == 24);
static_assert(sizeof(SwifterKitSCSIParallelTaskEvent) == 100);
static_assert(sizeof(SwifterKitSCSIManagementEvent) == 32);
static_assert(sizeof(SwifterKitSCSICompletionHeader) == 48);
static_assert(sizeof(SwifterKitSerialEvent) == 16);
static_assert(sizeof(SwifterKitNetworkReceiveHeader) == 8);
static_assert(sizeof(SwifterKitNetworkCompletion) == 8);
static_assert(sizeof(SwifterKitNetworkLink) == 8);
static_assert(sizeof(SwifterKitNetworkEventHeader) == 16);
static_assert(sizeof(SwifterKitAudioTransferHeader) == 24);
static_assert(sizeof(SwifterKitAudioTimestamp) == 16);
static_assert(sizeof(SwifterKitAudioIOState) == 32);
static_assert(sizeof(SwifterKitAudioEvent) == 16);
static_assert(sizeof(SwifterKitAudioControlGet) == 8);
static_assert(sizeof(SwifterKitAudioControlValueHeader) == 16);
static_assert(sizeof(SwifterKitAudioCustomPropertyHeader) == 16);
static_assert(sizeof(SwifterKitAudioControlEventHeader) == 20);
static_assert(sizeof(SwifterKitAudioCustomPropertyEventHeader) == 20);
static_assert(sizeof(SwifterKitVideoTransferHeader) == 32);
static_assert(sizeof(SwifterKitVideoQueueEntry) == 32);
static_assert(sizeof(SwifterKitVideoTimestamp) == 16);
static_assert(sizeof(SwifterKitVideoEvent) == 16);
static_assert(sizeof(SwifterKitVideoStreamFormatEvent) == 52);
static_assert(sizeof(SwifterKitMIDIHeader) == 8);
static_assert(sizeof(SwifterKitMIDIEventHeader) == 16);
static_assert(sizeof(SwifterKitBlockStorageCompletion) == 8);
static_assert(sizeof(SwifterKitBlockStorageIOCompletion) == 16);
static_assert(sizeof(SwifterKitBlockStorageRequestHeader) == 8);
static_assert(sizeof(SwifterKitBlockStorageIORequest) == 48);
static_assert(sizeof(SwifterKitHIDReportHeader) == 24);
static_assert(sizeof(SwifterKitUSBControlTransferHeader) == 16);
static_assert(sizeof(SwifterKitUSBPipeTransferHeader) == 16);
static_assert(sizeof(SwifterKitPCIAccessHeader) == 24);
static_assert(sizeof(SwifterKitPCICapabilityHeader) == 16);
static_assert(sizeof(SwifterKitMemoryAllocateHeader) == 32);
static_assert(sizeof(SwifterKitMemoryAccessHeader) == 24);
static_assert(sizeof(SwifterKitMemorySetLengthHeader) == 16);
static_assert(sizeof(SwifterKitMemoryDMAHeader) == 32);
static_assert(sizeof(SwifterKitMemoryInfo) == 32);
static_assert(sizeof(SwifterKitMemoryDMAResponseHeader) == 16);

#endif
