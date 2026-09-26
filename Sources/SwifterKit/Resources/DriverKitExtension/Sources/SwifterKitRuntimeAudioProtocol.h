#ifndef SwifterKitRuntimeAudioProtocol_h
#define SwifterKitRuntimeAudioProtocol_h

#include <stdint.h>

// Packed payloads for the audio object, box, and clock-device opcodes 0x0A10-0x0A1D and the
// audioObject event 0x0A01. Every multi-byte field is little-endian, as in
// SwifterKitRuntimeProtocol.h, and every reserved field must be zero.

// Target kinds: 0 driver, 1 device, 2 box (index), 3 clock device (index), 4 object (ID).
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

// Heads SetObjectName, PropertiesChanged, and SetClockSampleRates; count is the byte length of
// the name or the number of selectors or sample rates that follow.
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

// Kinds: 1 device started, 2 device stopped, 3 clock started, 4 clock stopped, 5 clock rate
// changed, 6 box acquisition request, 7 clock sample-rate request. Kinds 6 and 7 are required
// events with a nonzero request ID; the others carry request ID zero.
struct __attribute__((packed)) SwifterKitAudioObjectEvent {
    uint32_t kind;
    uint32_t index;
    uint32_t requestID;
    uint32_t reserved;
    uint64_t value;
};

enum : uint32_t {
    kSwifterKitAudioTargetDriver = 0,
    kSwifterKitAudioTargetDevice = 1,
    kSwifterKitAudioTargetBox = 2,
    kSwifterKitAudioTargetClock = 3,
    kSwifterKitAudioTargetObject = 4,
    kSwifterKitAudioObjectTableCount = 4,
    kSwifterKitAudioPendingRequestCount = 8,
    kSwifterKitAudioMaximumSampleRates = 64,
    kSwifterKitAudioEventBoxRequest = 6,
    kSwifterKitAudioEventClockRequest = 7,
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

#endif
