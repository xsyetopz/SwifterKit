#ifndef SwifterKitRuntimeVideoProtocol_h
#define SwifterKitRuntimeVideoProtocol_h

#include <stdint.h>

// Packed payloads for the video object, box, clock-device, queue-notification, and
// custom-property-owner opcodes 0x0C10-0x0C1F and the videoObject event 0x0C01. Every
// multi-byte field is little-endian, as in SwifterKitRuntimeProtocol.h, and every reserved field
// must be zero.

// Target kinds: 0 driver, 1 device, 2 box (index), 3 clock device (index), 4 object (ID).
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

// Heads SetObjectName, PropertiesChanged, and SetClockSampleRates; count is the byte length of
// the name or the number of selectors or sample rates that follow.
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

// Kind 1 BufferQueueChange, 2 OutputBufferNotification.
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

// Kinds: 1 device started, 2 device stopped, 3 clock started, 4 clock stopped, 5 clock rate
// changed, 6 box acquisition request, 7 clock sample-rate request, 8 clock stream format
// changed (value is the stream object ID). Kinds 6 and 7 are required events with a nonzero
// request ID; the others carry request ID zero.
struct __attribute__((packed)) SwifterKitVideoObjectEvent {
    uint32_t kind;
    uint32_t index;
    uint32_t requestID;
    uint32_t reserved;
    uint64_t value;
};

enum : uint32_t {
    kSwifterKitVideoTargetDriver = 0,
    kSwifterKitVideoTargetDevice = 1,
    kSwifterKitVideoTargetBox = 2,
    kSwifterKitVideoTargetClock = 3,
    kSwifterKitVideoTargetObject = 4,
    kSwifterKitVideoObjectTableCount = 4,
    kSwifterKitVideoPendingRequestCount = 8,
    kSwifterKitVideoMaximumSampleRates = 16,
    kSwifterKitVideoEventBoxRequest = 6,
    kSwifterKitVideoEventClockRequest = 7,
    kSwifterKitVideoOwnerDetached = 0,
    kSwifterKitVideoOwnerDevice = 1,
    kSwifterKitVideoOwnerDriver = 2,
};

#endif
