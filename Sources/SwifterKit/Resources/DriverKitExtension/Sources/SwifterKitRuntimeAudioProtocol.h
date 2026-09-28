#ifndef SwifterKitRuntimeAudioProtocol_h
#define SwifterKitRuntimeAudioProtocol_h

#include <stdint.h>

#include "SwifterKitRuntimeSchema.h"

// Packed payloads for the audio object, box, and clock-device opcodes 0x0A10-0x0A1D, the
// device, stream, control, and custom-property opcodes 0x0A20-0x0A29, and the
// audioObject event 0x0A01. Every multi-byte field is little-endian, as in
// SwifterKitRuntimeProtocol.h, and every reserved field must be zero.

// kind is a kSwifterKitAudioTarget value. Index selects a box or clock device, or holds an
// object ID.
struct __attribute__((packed)) SwifterKitAudioObjectTarget {
    uint32_t kind;
    uint32_t index;
};

struct __attribute__((packed)) SwifterKitAudioObjectInfoHeader {
    uint32_t objectID;
    uint32_t ownerObjectID;
    uint32_t classID;
    uint32_t baseClassID;
    uint32_t transport;
    uint32_t nameLength;
    uint32_t uidLength;
    uint32_t reserved;
};

// Heads SetObjectName, PropertiesChanged, and SetClockSampleRates. Count is the byte length of
// the name, or the number of selectors or sample rates that follow.
struct __attribute__((packed)) SwifterKitAudioListHeader {
    SwifterKitAudioObjectTarget target;
    uint32_t count;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitAudioElementNameHeader {
    SwifterKitAudioObjectTarget target;
    uint32_t kind;
    uint32_t element;
    uint32_t scope;
    uint32_t length;
};

// SetBoxProperty, SetClockDeviceProperty, and RequestClockSampleRate (selector zero).
struct __attribute__((packed)) SwifterKitAudioIndexedValue {
    SwifterKitAudioObjectTarget target;
    uint32_t selector;
    uint32_t reserved;
    uint64_t value;
};

struct __attribute__((packed)) SwifterKitAudioBoxOwnership {
    SwifterKitAudioObjectTarget box;
    SwifterKitAudioObjectTarget member;
    uint32_t owned;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitAudioBoxState {
    uint32_t objectID;
    uint32_t transport;
    uint32_t flags;
    int32_t acquisitionFailure;
};

struct __attribute__((packed)) SwifterKitAudioClockState {
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
    uint32_t zeroTimestampPeriod;
    uint32_t rateCount;
};

struct __attribute__((packed)) SwifterKitAudioClockTimestamp {
    SwifterKitAudioObjectTarget target;
    uint64_t sampleTime;
    uint64_t hostTime;
};

struct __attribute__((packed)) SwifterKitAudioRequestAnswer {
    uint32_t requestID;
    uint32_t accepted;
    int32_t failure;
    uint32_t reserved;
};

// kind is a kSwifterKitAudioObjectEvent value. BoxRequest and ClockRequest are required events
// with a nonzero request ID. The others carry request ID zero.
struct __attribute__((packed)) SwifterKitAudioObjectEvent {
    uint32_t kind;
    uint32_t index;
    uint32_t requestID;
    uint32_t reserved;
    uint64_t value;
};

// Device, stream, control, and custom-property opcodes 0x0A20-0x0A29.
// SetDeviceProperty selectors are kSwifterKitAudioDeviceProperty values. The can-be-default and
// wants-stream-formats-restored values are 0 or 1. Preferred stereo channels carry the left
// channel in the low word.
struct __attribute__((packed)) SwifterKitAudioMemberValue {
    uint32_t selector;
    uint32_t reserved;
    uint64_t value;
};

struct __attribute__((packed)) SwifterKitAudioDeviceState {
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
struct __attribute__((packed)) SwifterKitAudioChannelLayoutHeader {
    uint32_t isInput;
    uint32_t count;
};

// GetStreamState, GetControlInfo, and GetCustomPropertyInfo requests.
struct __attribute__((packed)) SwifterKitAudioMemberRequest {
    uint32_t identifier;
    uint32_t reserved;
};

// SetStreamProperty (identifier is the stream index, selector a kSwifterKitAudioStreamProperty
// value) and SetControlProperty (selector a kSwifterKitAudioControlProperty value, with the first
// value in the low word).
struct __attribute__((packed)) SwifterKitAudioMemberProperty {
    uint32_t identifier;
    uint32_t selector;
    uint64_t value;
};

struct __attribute__((packed)) SwifterKitAudioStreamFormat {
    uint64_t sampleRateBits;
    uint32_t formatID;
    uint32_t formatFlags;
    uint32_t bytesPerPacket;
    uint32_t framesPerPacket;
    uint32_t bytesPerFrame;
    uint32_t channelsPerFrame;
    uint32_t bitsPerChannel;
    uint32_t reserved;
};

// Followed by the current format and formatCount available formats.
struct __attribute__((packed)) SwifterKitAudioStreamState {
    uint32_t objectID;
    uint32_t direction;
    uint32_t terminalType;
    uint32_t startingChannel;
    uint32_t latency;
    uint32_t isActive;
    uint32_t isAttached;
    uint32_t formatCount;
    uint64_t memoryLength;
};

// Followed by itemCount selector items: uint32_t value, uint32_t name length, name bytes.
struct __attribute__((packed)) SwifterKitAudioControlInfo {
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
    uint32_t reserved;
};

// Followed by count uint32_t selector values.
struct __attribute__((packed)) SwifterKitAudioSelectorRemoval {
    uint32_t identifier;
    uint32_t count;
};

// owner is a kSwifterKitAudioOwner value.
struct __attribute__((packed)) SwifterKitAudioCustomPropertyInfo {
    uint32_t objectID;
    uint32_t selector;
    uint32_t propertyDataType;
    uint32_t qualifierDataType;
    uint32_t owner;
    uint32_t reserved;
};

// kind is a kSwifterKitAudioMember value. A stream's identifier is its index.
struct __attribute__((packed)) SwifterKitAudioMemberAttachment {
    uint32_t kind;
    uint32_t identifier;
    uint32_t owner;
    uint32_t reserved;
};

static_assert(sizeof(SwifterKitAudioObjectTarget) == 8);
static_assert(sizeof(SwifterKitAudioObjectInfoHeader) == 32);
static_assert(sizeof(SwifterKitAudioListHeader) == 16);
static_assert(sizeof(SwifterKitAudioElementNameHeader) == 24);
static_assert(sizeof(SwifterKitAudioIndexedValue) == 24);
static_assert(sizeof(SwifterKitAudioBoxOwnership) == 24);
static_assert(sizeof(SwifterKitAudioBoxState) == 16);
static_assert(sizeof(SwifterKitAudioClockState) == 80);
static_assert(sizeof(SwifterKitAudioClockTimestamp) == 24);
static_assert(sizeof(SwifterKitAudioRequestAnswer) == 16);
static_assert(sizeof(SwifterKitAudioObjectEvent) == 24);
static_assert(sizeof(SwifterKitAudioMemberValue) == 16);
static_assert(sizeof(SwifterKitAudioDeviceState) == 64);
static_assert(sizeof(SwifterKitAudioChannelLayoutHeader) == 8);
static_assert(sizeof(SwifterKitAudioMemberRequest) == 8);
static_assert(sizeof(SwifterKitAudioMemberProperty) == 16);
static_assert(sizeof(SwifterKitAudioStreamFormat) == 40);
static_assert(sizeof(SwifterKitAudioStreamState) == 40);
static_assert(sizeof(SwifterKitAudioControlInfo) == 48);
static_assert(sizeof(SwifterKitAudioSelectorRemoval) == 8);
static_assert(sizeof(SwifterKitAudioCustomPropertyInfo) == 24);
static_assert(sizeof(SwifterKitAudioMemberAttachment) == 16);

#endif
