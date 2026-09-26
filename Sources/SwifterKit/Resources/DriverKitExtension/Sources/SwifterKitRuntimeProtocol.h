#ifndef SwifterKitRuntimeProtocol_h
#define SwifterKitRuntimeProtocol_h

#include <stdint.h>

// Wire constants, message kinds, opcodes, event types, and capability bits come from the Swift
// schema. Payload layouts below stay hand-written and are checked against the schema sizes.
#include "SwifterKitRuntimeSchema.h"

// DriverExtensionGenerator replaces this placeholder with the configured capability bits.
static constexpr uint64_t kSwifterKitRuntimeCapabilities = 0;

// The largest event payload: a poll response carries the runtime header, the event type, and the
// payload. The event queues reject anything larger, so producers check this same bound first.
static constexpr uint32_t kSwifterKitMaximumEventPayloadLength =
    kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize - sizeof(uint32_t);

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

struct __attribute__((packed)) SwifterKitPCIResetHeader {
    uint32_t type;
    uint32_t options;
};

struct __attribute__((packed)) SwifterKitPCILinkSpeedHeader {
    uint32_t speed;
    uint8_t retrain;
    uint8_t reserved[3];
};

struct __attribute__((packed)) SwifterKitPCIPropertiesHeader {
    uint8_t configSpaceVolatile;
    uint8_t sleepLinkDisable;
    uint8_t sleepReset;
    uint8_t reserved;
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

// Ethernet payloads. The event kinds, packet flags and masks, batch, poll-interval, and queue
// bounds, and the event-header and transmit-metadata sizes come from
// RuntimeSchema+Networking.swift.
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

struct __attribute__((packed)) SwifterKitNetworkBandwidths {
    uint64_t maximumInput;
    uint64_t maximumOutput;
    uint64_t effectiveInput;
    uint64_t effectiveOutput;
};

struct __attribute__((packed)) SwifterKitNetworkHardwareCounts {
    uint64_t packetsIn;
    uint64_t bytesIn;
    uint64_t multicastsIn;
    uint64_t errorsIn;
    uint64_t packetsOut;
    uint64_t bytesOut;
    uint64_t multicastsOut;
    uint64_t errorsOut;
    uint64_t collisions;
    uint64_t dropped;
    uint64_t noProtocol;
};

struct __attribute__((packed)) SwifterKitNetworkPollerParameters {
    uint64_t dataRate;
    uint64_t pollInterval;
};

struct __attribute__((packed)) SwifterKitNetworkEventHeader {
    uint32_t kind;
    uint32_t requestID;
    uint32_t value;
    uint32_t dataLength;
};

// Precedes each transmitted frame in a transmit event.
struct __attribute__((packed)) SwifterKitNetworkTransmitMetadata {
    uint32_t dataOffset;
    uint32_t flags;
    uint32_t serviceClass;
    uint32_t traceID;
    uint32_t checksumFlags;
    uint16_t checksumStart;
    uint16_t checksumStuff;
    uint32_t offloadFlags;
    uint32_t tsoFlags;
    uint16_t tsoSegmentSize;
    uint16_t maximumSegmentSize;
    uint16_t vlanTag;
    uint8_t linkHeaderLength;
    uint8_t reserved;
    uint64_t timestamp;
    uint64_t expiryTime;
    uint64_t memorySegmentOffset;
    uint64_t dataIOVirtualAddress;
};

// Begins a receive or completion batch.
struct __attribute__((packed)) SwifterKitNetworkBatchHeader {
    uint32_t count;
    uint32_t reserved;
};

// Precedes each frame in a receive batch.
struct __attribute__((packed)) SwifterKitNetworkReceivePacket {
    uint32_t length;
    uint32_t dataOffset;
    uint32_t flags;
    uint32_t checksumFlags;
    uint16_t checksumValue;
    uint16_t vlanTag;
    uint8_t linkHeaderLength;
    uint8_t lroFlags;
    uint8_t lroSegmentCount;
    uint8_t reserved0;
    uint32_t traceEvent;
    uint32_t reserved1;
    uint64_t timestamp;
};

// One entry of a completion batch.
struct __attribute__((packed)) SwifterKitNetworkTransmitCompletion {
    uint32_t requestID;
    int32_t status;
    uint32_t flags;
    uint32_t traceEvent;
    uint64_t timestamp;
};

struct __attribute__((packed)) SwifterKitNetworkQueueEnable {
    uint32_t queue;
    uint32_t enabled;
};

// A private SIOCSDRVSPEC or SIOCGDRVSPEC request. ifd_data is a pointer in the caller's address
// space, so only the name, command, and length reach Swift.
struct __attribute__((packed)) SwifterKitNetworkInterfaceCommand {
    char name[16];
    uint64_t command;
    uint64_t length;
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
    uint8_t commandDescriptorBlock[kSwifterKitSCSICommandDescriptorBlockMaximumSize];
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
    uint8_t commandDescriptorBlock[kSwifterKitSCSICommandDescriptorBlockMaximumSize];
    uint32_t featureRequests[kSwifterKitSCSIMaximumFeatureRequests];
};

struct __attribute__((packed)) SwifterKitSCSIManagementEvent {
    uint32_t kind;
    uint32_t reserved;
    uint64_t targetIdentifier;
    uint64_t logicalUnit;
    uint64_t taskTag;
};

// Reports the kern_return_t of a UserCreateTargetForID that SCSICreateTarget queued.
struct __attribute__((packed)) SwifterKitSCSITargetCreatedEvent {
    uint64_t targetIdentifier;
    int32_t status;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitSCSICompletionHeader {
    uint32_t requestID;
    uint32_t featureResultCount;
    uint32_t taskStatus;
    uint32_t serviceResponse;
    uint64_t bytesTransferred;
    uint32_t senseLength;
    uint32_t featureResults[kSwifterKitSCSIMaximumFeatureRequests];
};

// Precedes the entries of the SCSI create-target and property commands. Each entry is a
// SwifterKitSCSIPropertyEntry followed by keyLength key bytes and valueLength value bytes.
struct __attribute__((packed)) SwifterKitSCSIPropertyHeader {
    uint64_t targetIdentifier;
    uint32_t count;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitSCSIPropertyEntry {
    uint16_t keyLength;
    uint16_t valueLength;
};

// Precedes the bytes of SCSIWriteTaskData; SCSIReadTaskData carries only the header.
struct __attribute__((packed)) SwifterKitSCSITaskDataHeader {
    uint32_t requestID;
    uint32_t length;
    uint64_t offset;
};

struct __attribute__((packed)) SwifterKitHandshakeRequest {
    uint16_t minimumVersion;
    uint16_t maximumVersion;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitHandshakeResponse {
    uint16_t version;
    uint16_t reserved16;
    uint32_t reserved32;
    uint64_t capabilities;
};

static_assert(sizeof(SwifterKitRuntimeHeader) == kSwifterKitRuntimeHeaderSize);
static_assert(sizeof(SwifterKitRuntimeCommandHeader) == kSwifterKitRuntimeCommandHeaderSize);
static_assert(sizeof(SwifterKitHandshakeRequest) == kSwifterKitRuntimeHandshakeRequestSize);
static_assert(sizeof(SwifterKitHandshakeResponse) == kSwifterKitRuntimeHandshakeResponseSize);
static_assert(sizeof(SwifterKitInterruptCommandHeader) == 8);
static_assert(sizeof(SwifterKitInterruptEvent) == 24);
static_assert(sizeof(SwifterKitSCSIPeripheralCommandHeader) == 40);
static_assert(sizeof(SwifterKitSCSIPeripheralResponseHeader) == 24);
static_assert(sizeof(SwifterKitSCSIParallelTaskEvent) == 100);
static_assert(sizeof(SwifterKitSCSIManagementEvent) == 32);
static_assert(sizeof(SwifterKitSCSITargetCreatedEvent) == 16);
static_assert(sizeof(SwifterKitSCSICompletionHeader) == 48);
static_assert(sizeof(SwifterKitSCSIPropertyHeader) == 16);
static_assert(sizeof(SwifterKitSCSIPropertyEntry) == 4);
static_assert(sizeof(SwifterKitSCSITaskDataHeader) == 16);
static_assert(sizeof(SwifterKitSerialEvent) == 16);
static_assert(sizeof(SwifterKitNetworkReceiveHeader) == 8);
static_assert(sizeof(SwifterKitNetworkCompletion) == 8);
static_assert(sizeof(SwifterKitNetworkLink) == 8);
static_assert(sizeof(SwifterKitNetworkEventHeader) == kSwifterKitNetworkEventHeaderSize);
static_assert(sizeof(SwifterKitNetworkBandwidths) == 32);
static_assert(sizeof(SwifterKitNetworkHardwareCounts) == 88);
static_assert(sizeof(SwifterKitNetworkPollerParameters) == 16);
static_assert(sizeof(SwifterKitNetworkTransmitMetadata) == kSwifterKitNetworkTransmitMetadataSize);
static_assert(sizeof(SwifterKitNetworkBatchHeader) == 8);
static_assert(sizeof(SwifterKitNetworkReceivePacket) == 40);
static_assert(sizeof(SwifterKitNetworkTransmitCompletion) == 24);
static_assert(sizeof(SwifterKitNetworkQueueEnable) == 8);
static_assert(sizeof(SwifterKitNetworkInterfaceCommand) == 32);
static_assert(sizeof(SwifterKitAudioTransferHeader) == kSwifterKitAudioTransferHeaderSize);
static_assert(sizeof(SwifterKitAudioTimestamp) == 16);
static_assert(sizeof(SwifterKitAudioIOState) == 32);
static_assert(sizeof(SwifterKitAudioEvent) == 16);
static_assert(sizeof(SwifterKitAudioControlGet) == 8);
static_assert(sizeof(SwifterKitAudioControlValueHeader) == 16);
static_assert(sizeof(SwifterKitAudioCustomPropertyHeader) == 16);
static_assert(sizeof(SwifterKitAudioControlEventHeader) == 20);
static_assert(sizeof(SwifterKitAudioCustomPropertyEventHeader) == 20);
static_assert(sizeof(SwifterKitVideoTransferHeader) == kSwifterKitVideoTransferHeaderSize);
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
static_assert(sizeof(SwifterKitPCIResetHeader) == 8);
static_assert(sizeof(SwifterKitPCILinkSpeedHeader) == 8);
static_assert(sizeof(SwifterKitPCIPropertiesHeader) == 4);
static_assert(sizeof(SwifterKitMemoryAllocateHeader) == 32);
static_assert(sizeof(SwifterKitMemoryAccessHeader) == 24);
static_assert(sizeof(SwifterKitMemorySetLengthHeader) == 16);
static_assert(sizeof(SwifterKitMemoryDMAHeader) == 32);
static_assert(sizeof(SwifterKitMemoryInfo) == 32);
static_assert(sizeof(SwifterKitMemoryDMAResponseHeader) == 16);

#endif
