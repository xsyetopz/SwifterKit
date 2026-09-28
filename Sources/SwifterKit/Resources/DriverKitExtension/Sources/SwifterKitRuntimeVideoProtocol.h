#ifndef SwifterKitRuntimeVideoProtocol_h
#define SwifterKitRuntimeVideoProtocol_h

#include <stdint.h>

#include "SwifterKitRuntimeSchema.h"

// Packed payloads for the video object, box, clock-device, queue-notification, and
// custom-property-owner opcodes 0x0C10-0x0C1F and the videoObject event 0x0C01. Every
// multi-byte field is little-endian, as in SwifterKitRuntimeProtocol.h, and every reserved field
// must be zero.

// kind is a kSwifterKitVideoTarget value. Index selects a box or clock device, or holds an
// object ID.
struct __attribute__((packed)) SwifterKitVideoObjectTarget {
    uint32_t kind;
    uint32_t index;
};

// IOUserVideoObject has no owner object ID, so the second word is reserved.
struct __attribute__((packed)) SwifterKitVideoObjectInfoHeader {
    uint32_t objectID;
    uint32_t reserved0;
    uint32_t classID;
    uint32_t baseClassID;
    uint32_t transport;
    uint32_t nameLength;
    uint32_t uidLength;
    uint32_t reserved1;
};

// Heads SetObjectName, PropertiesChanged, and SetClockSampleRates. Count is the byte length of
// the name, or the number of selectors or sample rates that follow.
struct __attribute__((packed)) SwifterKitVideoListHeader {
    SwifterKitVideoObjectTarget target;
    uint32_t count;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitVideoElementNameHeader {
    SwifterKitVideoObjectTarget target;
    uint32_t kind;
    uint32_t element;
    uint32_t scope;
    uint32_t length;
};

// SetBoxProperty, SetClockDeviceProperty, and RequestClockSampleRate (selector zero).
struct __attribute__((packed)) SwifterKitVideoIndexedValue {
    SwifterKitVideoObjectTarget target;
    uint32_t selector;
    uint32_t reserved;
    uint64_t value;
};

struct __attribute__((packed)) SwifterKitVideoBoxOwnership {
    SwifterKitVideoObjectTarget box;
    SwifterKitVideoObjectTarget member;
    uint32_t owned;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitVideoBoxState {
    uint32_t objectID;
    uint32_t transport;
    uint32_t flags;
    int32_t acquisitionFailure;
};

// Followed by rateCount doubles. Flags: 0x1 clock stable, 0x2 alive, 0x4 running, 0x8 hidden.
struct __attribute__((packed)) SwifterKitVideoClockState {
    uint64_t sampleRateBits;
    uint64_t zeroSampleTime;
    uint64_t zeroHostTime;
    uint64_t clientInputSampleTime;
    uint64_t clientOutputSampleTime;
    uint32_t objectID;
    uint32_t clockDomain;
    uint32_t clockAlgorithm;
    uint32_t transport;
    uint32_t transportState;
    uint32_t flags;
    uint32_t inputLatency;
    uint32_t outputLatency;
    uint32_t reserved;
    uint32_t rateCount;
};

struct __attribute__((packed)) SwifterKitVideoClockTimestamp {
    SwifterKitVideoObjectTarget target;
    uint64_t sampleTime;
    uint64_t hostTime;
};

struct __attribute__((packed)) SwifterKitVideoRequestAnswer {
    uint32_t requestID;
    uint32_t accepted;
    int32_t failure;
    uint32_t reserved;
};

// Kind 1 BufferQueueChange, 2 OutputBufferNotification, 3 the stream's SendBufferQueueChange
// (change action zero).
struct __attribute__((packed)) SwifterKitVideoQueueNotification {
    uint32_t kind;
    uint32_t streamIndex;
    uint64_t changeAction;
};

// Owner 0 detached, 1 device, 2 driver.
struct __attribute__((packed)) SwifterKitVideoPropertyOwner {
    uint32_t identifier;
    uint32_t owner;
    uint64_t reserved;
};

// Kinds:
// - 1 device started, 2 device stopped, 3 clock started, 4 clock stopped, 5 clock rate changed.
// - 6 box acquisition request, 7 clock sample-rate request.
// - 8 clock stream format changed (value is the stream object ID).
// - 9 device stream format changed (index zero, value is the stream object ID).
//
// Kinds 6 and 7 are required events with a nonzero request ID. The others carry request ID zero.
struct __attribute__((packed)) SwifterKitVideoObjectEvent {
    uint32_t kind;
    uint32_t index;
    uint32_t requestID;
    uint32_t reserved;
    uint64_t value;
};

// Device, stream, buffer, control, and custom-property opcodes 0x0C20-0x0C2D.
//
// SetDeviceProperty selectors:
// - 1-3 can-be-default input, output, system output (0 or 1).
// - 4-5 input and output safety offsets.
// - 6 preferred stereo channels (left in the low word).
struct __attribute__((packed)) SwifterKitVideoMemberValue {
    uint32_t selector;
    uint32_t reserved;
    uint64_t value;
};

struct __attribute__((packed)) SwifterKitVideoDeviceState {
    uint32_t objectID;
    uint32_t canBeDefaultInput;
    uint32_t canBeDefaultOutput;
    uint32_t canBeDefaultSystemOutput;
    uint32_t inputSafetyOffset;
    uint32_t outputSafetyOffset;
    uint32_t preferredLeft;
    uint32_t preferredRight;
    uint64_t inputSampleTime;
    uint64_t inputHostTime;
    uint64_t outputSampleTime;
    uint64_t outputHostTime;
};

// Followed by count uint32_t channel labels.
struct __attribute__((packed)) SwifterKitVideoChannelLayoutHeader {
    uint32_t isInput;
    uint32_t count;
};

// GetStreamState, GetControlInfo, and GetCustomPropertyInfo carry a zero argument. GetBufferInfo
// carries the buffer index, and GetStreamMemoryObjectID the memory type.
struct __attribute__((packed)) SwifterKitVideoMemberRequest {
    uint32_t identifier;
    uint32_t argument;
};

// SetStreamProperty (identifier is the stream index) and SetControlProperty.
//
// Stream selectors:
// - 1 active, 2 starting channel, 3 terminal type, 4 current format index.
// - 5 buffer capacities (data bytes in the low word, control bytes in the high word).
// - 6 queue entry count. Selectors 5 and 6 wait for PerformDeviceConfigurationChange.
//
// Control selectors: 1 slider range, 2 panning channels, each with the first value in the low
// word.
struct __attribute__((packed)) SwifterKitVideoMemberProperty {
    uint32_t identifier;
    uint32_t selector;
    uint64_t value;
};

// SetBufferProperty selectors, both applied in PerformDeviceConfigurationChange: 1 buffer ID,
// 2 attached to the stream (0 or 1).
struct __attribute__((packed)) SwifterKitVideoBufferProperty {
    uint32_t streamIndex;
    uint32_t bufferIndex;
    uint32_t selector;
    uint32_t reserved;
    uint64_t value;
};

struct __attribute__((packed)) SwifterKitVideoStreamFormat {
    uint64_t frameRateBits;
    uint64_t frameTimeValue;
    uint32_t frameTimeScale;
    uint32_t codec;
    uint32_t codecFlags;
    uint32_t width;
    uint32_t height;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitVideoQueueState {
    uint32_t entryCount;
    uint32_t headIndex;
    uint32_t tailIndex;
    uint32_t reserved;
    uint64_t memoryLength;
};

// Followed by the current format, formatCount available formats, and bufferCount buffer IDs in
// the order of GetBufferList.
struct __attribute__((packed)) SwifterKitVideoStreamState {
    uint32_t objectID;
    uint32_t direction;
    uint32_t terminalType;
    uint32_t startingChannel;
    uint32_t isActive;
    uint32_t isAttached;
    uint32_t formatCount;
    uint32_t bufferCount;
    uint32_t dataCapacity;
    uint32_t controlCapacity;
    SwifterKitVideoQueueState inputQueue;
    SwifterKitVideoQueueState outputQueue;
};

struct __attribute__((packed)) SwifterKitVideoBufferInfo {
    uint32_t objectID;
    uint32_t classID;
    uint32_t baseClassID;
    uint32_t bufferID;
    uint32_t isAttached;
    uint32_t dataMemoryObjectID;
    uint32_t controlMemoryObjectID;
    uint32_t reserved;
    uint64_t dataLength;
    uint64_t controlLength;
    uint64_t outputDataLength;
    uint64_t outputControlLength;
};

// Followed by itemCount selector items: uint32_t value, uint32_t name length, name bytes.
struct __attribute__((packed)) SwifterKitVideoControlInfo {
    uint32_t objectID;
    uint32_t kind;
    uint32_t scope;
    uint32_t element;
    uint32_t isSettable;
    uint32_t isAttached;
    uint32_t sliderMinimum;
    uint32_t sliderMaximum;
    uint32_t panLeft;
    uint32_t panRight;
    uint32_t itemCount;
    uint32_t owningDeviceID;
};

// Followed by count uint32_t selector values.
struct __attribute__((packed)) SwifterKitVideoSelectorRemoval {
    uint32_t identifier;
    uint32_t count;
};

struct __attribute__((packed)) SwifterKitVideoCustomPropertyInfo {
    uint32_t objectID;
    uint32_t selector;
    uint32_t propertyDataType;
    uint32_t qualifierDataType;
    uint32_t owner;
    uint32_t reserved;
};

// Kind: 1 stream (identifier is its index), 2 control.
struct __attribute__((packed)) SwifterKitVideoMemberAttachment {
    uint32_t kind;
    uint32_t identifier;
    uint32_t attached;
    uint32_t reserved;
};

static_assert(sizeof(SwifterKitVideoMemberValue) == 16);
static_assert(sizeof(SwifterKitVideoDeviceState) == 64);
static_assert(sizeof(SwifterKitVideoMemberRequest) == 8);
static_assert(sizeof(SwifterKitVideoMemberProperty) == 16);
static_assert(sizeof(SwifterKitVideoBufferProperty) == 24);
static_assert(sizeof(SwifterKitVideoStreamFormat) == 40);
static_assert(sizeof(SwifterKitVideoStreamState) == 88);
static_assert(sizeof(SwifterKitVideoBufferInfo) == 64);
static_assert(sizeof(SwifterKitVideoControlInfo) == 48);
static_assert(sizeof(SwifterKitVideoCustomPropertyInfo) == 24);
static_assert(sizeof(SwifterKitVideoMemberAttachment) == 16);

#endif
