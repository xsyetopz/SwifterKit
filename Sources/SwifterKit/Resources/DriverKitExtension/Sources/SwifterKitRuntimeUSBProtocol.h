#ifndef SwifterKitRuntimeUSBProtocol_h
#define SwifterKitRuntimeUSBProtocol_h

#include <stdint.h>

#include "SwifterKitRuntimeProtocol.h"

// Packed payloads for the USB device, interface, and pipe opcodes in 0x0210-0x023F, and for
// the USB pipe completion events. Swift encodes and decodes the same layouts in
// Sources/SwifterKit/DriverKit/USB.

// The largest payload in one command after the runtime and command headers.
static constexpr uint32_t kSwifterKitUSBMaximumCommandPayload =
    kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize
    - kSwifterKitRuntimeCommandHeaderSize;
// The largest payload in one response after the runtime header.
static constexpr uint32_t kSwifterKitUSBMaximumResponsePayload =
    kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize;
// The largest event payload after the runtime header and the event type.
static constexpr uint32_t kSwifterKitUSBMaximumEventPayload =
    kSwifterKitUSBMaximumResponsePayload - sizeof(uint32_t);

// A descriptor response is its full length followed by the bytes when they fit.
static constexpr uint32_t kSwifterKitUSBMaximumDescriptorLength =
    kSwifterKitUSBMaximumResponsePayload - sizeof(uint32_t);
// Interface enumeration stops after this many interfaces.
static constexpr uint32_t kSwifterKitUSBMaximumInterfaces = 256;
// Outstanding AsyncIO and IsochIO requests share this many slots.
static constexpr uint32_t kSwifterKitUSBMaximumPendingTransfers = 32;
static constexpr uint32_t kSwifterKitUSBMaximumIsochronousFrames = 1024;

struct __attribute__((packed)) SwifterKitUSBSetConfiguration {
    uint8_t configurationValue;
    uint8_t matchInterfaces;
    uint16_t reserved;
};

enum : uint8_t {
    kSwifterKitUSBConfigurationCurrent = 0,
    kSwifterKitUSBConfigurationIndex = 1,
    kSwifterKitUSBConfigurationValue = 2,
};

struct __attribute__((packed)) SwifterKitUSBConfigurationRequest {
    uint8_t selector;
    uint8_t value;
    uint16_t reserved;
};

struct __attribute__((packed)) SwifterKitUSBStringRequest {
    uint8_t index;
    uint8_t hasLanguageID;
    uint16_t languageID;
};

struct __attribute__((packed)) SwifterKitUSBDescriptorRequest {
    uint8_t type;
    uint8_t index;
    uint16_t languageID;
    uint8_t requestType;
    uint8_t recipient;
    uint16_t length;
};

struct __attribute__((packed)) SwifterKitUSBFrameTime {
    uint64_t frame;
    uint64_t time;
};

enum : uint8_t {
    kSwifterKitUSBPipeDescriptorsOriginal = 0,
    kSwifterKitUSBPipeDescriptorsCurrentPolicy = 1,
};

struct __attribute__((packed)) SwifterKitUSBPipeRequest {
    uint8_t endpoint;
    uint8_t option;
    uint16_t reserved;
    uint32_t value;
};

struct __attribute__((packed)) SwifterKitUSBPipeDescriptors {
    uint16_t bcdUSB;
    uint8_t endpoint[7];
    uint8_t superSpeedCompanion[6];
    uint8_t superSpeedPlusIsochronousCompanion[8];
};

struct __attribute__((packed)) SwifterKitUSBAsyncIOHeader {
    uint8_t endpoint;
    uint8_t reserved8;
    uint16_t reserved16;
    uint32_t length;
    uint32_t timeout;
    uint32_t reserved32;
};

struct __attribute__((packed)) SwifterKitUSBIsochIOHeader {
    uint8_t endpoint;
    uint8_t reserved8;
    uint16_t frameCount;
    uint32_t reserved32;
    uint64_t firstFrameNumber;
};

struct __attribute__((packed)) SwifterKitUSBPipeIOEvent {
    uint32_t requestID;
    int32_t status;
    uint32_t bytesTransferred;
    uint8_t endpoint;
    uint8_t reserved[3];
    uint64_t timestamp;
};

struct __attribute__((packed)) SwifterKitUSBIsochIOEvent {
    uint32_t requestID;
    int32_t status;
    uint8_t endpoint;
    uint8_t reserved;
    uint16_t frameCount;
    uint32_t dataLength;
};

// The same layout as USBDriverKit's IOUSBIsochronousFrame.
struct __attribute__((packed)) SwifterKitUSBIsochFrame {
    int32_t status;
    uint32_t requestCount;
    uint32_t completeCount;
    uint32_t reserved;
    uint64_t timestamp;
};

// An asynchronous control request uses SwifterKitUSBControlTransferHeader and completes with
// this event, followed by the bytes an IN request read.
struct __attribute__((packed)) SwifterKitUSBDeviceRequestEvent {
    uint32_t requestID;
    int32_t status;
    uint32_t bytesTransferred;
    uint8_t requestType;
    uint8_t reserved[3];
};

// Bundled I/O over a runtime-owned descriptor ring on one bulk pipe.
static constexpr uint32_t kSwifterKitUSBMaximumBundleRings = 4;
static constexpr uint32_t kSwifterKitUSBMaximumBundleRingEntries = 64;
static constexpr uint32_t kSwifterKitUSBMaximumBundleRingBytes = 4U * 1024U * 1024U;
static constexpr uint32_t kSwifterKitUSBMaximumBundledTransfers = 16;

struct __attribute__((packed)) SwifterKitUSBBundleRingRequest {
    uint8_t endpoint;
    uint8_t reserved8;
    uint16_t reserved16;
    uint32_t entryCount;
    uint32_t bufferLength;
    uint32_t reserved32;
};

// Followed by transferCount 32-bit lengths and, for an OUT pipe, the concatenated bytes.
struct __attribute__((packed)) SwifterKitUSBBundledIOHeader {
    uint8_t endpoint;
    uint8_t transferCount;
    uint16_t reserved16;
    uint32_t firstIndex;
    uint32_t timeout;
    uint32_t reserved32;
};

// One ring entry's completion, followed by the bytes an IN transfer read.
struct __attribute__((packed)) SwifterKitUSBBundledIOEvent {
    uint8_t endpoint;
    uint8_t reserved8;
    uint16_t reserved16;
    uint32_t index;
    int32_t status;
    uint32_t bytesTransferred;
};

struct __attribute__((packed)) SwifterKitUSBAdjustPipeRequest {
    uint8_t endpoint;
    uint8_t reserved[3];
    SwifterKitUSBPipeDescriptors descriptors;
    uint8_t reserved8;
};

static constexpr uint32_t kSwifterKitUSBMaximumAsyncRequestInputLength =
    kSwifterKitUSBMaximumEventPayload - sizeof(SwifterKitUSBDeviceRequestEvent);
static constexpr uint32_t kSwifterKitUSBMaximumBundleBufferLength =
    kSwifterKitUSBMaximumEventPayload - sizeof(SwifterKitUSBBundledIOEvent);

static constexpr uint32_t kSwifterKitUSBMaximumAsyncInputLength =
    kSwifterKitUSBMaximumEventPayload - sizeof(SwifterKitUSBPipeIOEvent);
static constexpr uint32_t kSwifterKitUSBMaximumAsyncOutputLength =
    kSwifterKitUSBMaximumCommandPayload - sizeof(SwifterKitUSBAsyncIOHeader);

static_assert(sizeof(SwifterKitUSBSetConfiguration) == 4);
static_assert(sizeof(SwifterKitUSBConfigurationRequest) == 4);
static_assert(sizeof(SwifterKitUSBStringRequest) == 4);
static_assert(sizeof(SwifterKitUSBDescriptorRequest) == 8);
static_assert(sizeof(SwifterKitUSBFrameTime) == 16);
static_assert(sizeof(SwifterKitUSBPipeRequest) == 8);
static_assert(sizeof(SwifterKitUSBPipeDescriptors) == 23);
static_assert(sizeof(SwifterKitUSBAsyncIOHeader) == 16);
static_assert(sizeof(SwifterKitUSBIsochIOHeader) == 16);
static_assert(sizeof(SwifterKitUSBPipeIOEvent) == 24);
static_assert(sizeof(SwifterKitUSBIsochIOEvent) == 16);
static_assert(sizeof(SwifterKitUSBIsochFrame) == 24);
static_assert(kSwifterKitUSBMaximumAsyncInputLength == 65484);
static_assert(kSwifterKitUSBMaximumAsyncOutputLength == 65480);
static_assert(kSwifterKitUSBMaximumDescriptorLength == 65508);
static_assert(sizeof(SwifterKitUSBDeviceRequestEvent) == 16);
static_assert(sizeof(SwifterKitUSBBundleRingRequest) == 16);
static_assert(sizeof(SwifterKitUSBBundledIOHeader) == 16);
static_assert(sizeof(SwifterKitUSBBundledIOEvent) == 16);
static_assert(sizeof(SwifterKitUSBAdjustPipeRequest) == 28);
static_assert(kSwifterKitUSBMaximumAsyncRequestInputLength == 65492);
static_assert(kSwifterKitUSBMaximumBundleBufferLength == 65492);

#endif
