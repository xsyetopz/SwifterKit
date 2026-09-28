#ifndef SwifterKitRuntimeHIDProtocol_h
#define SwifterKitRuntimeHIDProtocol_h

#include <stdint.h>

#include "SwifterKitRuntimeSchema.h"

// Packed HID payloads for the 0x031x-0x033x opcodes and events. The Swift encoders in
// Sources/SwifterKit/DriverKit/HID mirror these layouts. Every reserved field must be zero.
// The limits, the element write kind, and the report, delivery, category, and dispatch-state
// bits come from RuntimeSchema+HID.swift.

// Payload of hidCompleteGetReport, followed by length report bytes.
struct __attribute__((packed)) SwifterKitHIDReportCompletion {
    uint32_t requestID;
    int32_t status;
    uint32_t length;
    uint32_t reserved;
};

// Event hidGetReportRequest: the host asked for a report Swift answers.
struct __attribute__((packed)) SwifterKitHIDGetReportRequest {
    uint32_t requestID;
    uint32_t reportType;
    uint32_t options;
    uint32_t capacity;
    uint32_t timeout;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitHIDElementPageRequest {
    uint32_t firstIndex;
    uint32_t maximumCount;
};

// Response header of hidCopyElements, followed by count descriptors.
struct __attribute__((packed)) SwifterKitHIDElementPage {
    uint32_t totalCount;
    uint32_t count;
};

struct __attribute__((packed)) SwifterKitHIDElementDescriptor {
    uint32_t cookie;
    uint32_t parentCookie;
    uint32_t type;
    uint32_t collectionType;
    uint32_t usagePage;
    uint32_t usage;
    uint32_t logicalMinimum;
    uint32_t logicalMaximum;
    uint32_t physicalMinimum;
    uint32_t physicalMaximum;
    uint32_t unit;
    uint32_t unitExponent;
    uint32_t reportID;
    uint32_t reportSize;
    uint32_t reportCount;
    uint32_t flags;
    uint32_t value;
    uint32_t reserved;
    uint64_t timestamp;
};

struct __attribute__((packed)) SwifterKitHIDElementValueRequest {
    uint32_t cookie;
    uint32_t options;
    uint32_t scaleType;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitHIDElementValue {
    uint32_t value;
    uint32_t scaledValue;
    int32_t scaledFixedValue;
    uint32_t reserved;
    uint64_t timestamp;
};

// Payload of hidSetElementValue. A data value is followed by length bytes.
struct __attribute__((packed)) SwifterKitHIDElementWrite {
    uint32_t cookie;
    uint32_t kind;
    uint32_t value;
    uint32_t length;
};

struct __attribute__((packed)) SwifterKitHIDElementCommit {
    uint32_t cookie;
    uint32_t direction;
};

// Payload of hidCommitElements, followed by count cookies.
struct __attribute__((packed)) SwifterKitHIDElementsCommit {
    uint32_t direction;
    uint32_t count;
};

struct __attribute__((packed)) SwifterKitHIDUsageQuery {
    uint32_t cookie;
    uint32_t usagePage;
    uint32_t usage;
    uint32_t reserved;
};

// Payload of the interface and device report commands. Set and process carry length bytes.
struct __attribute__((packed)) SwifterKitHIDReportRequest {
    uint64_t timestamp;
    uint32_t reportType;
    uint32_t reportID;
    uint32_t options;
    uint32_t length;
    uint32_t timeout;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitHIDKeyboardEvent {
    uint64_t timestamp;
    uint32_t usagePage;
    uint32_t usage;
    uint32_t value;
    uint32_t options;
    uint32_t flags;
    uint32_t reserved;
};

// Pointer and scroll dispatches share one layout. A pointer carries buttons in z's slot.
struct __attribute__((packed)) SwifterKitHIDPointerEvent {
    uint64_t timestamp;
    int32_t x;
    int32_t y;
    int32_t z;
    uint32_t buttons;
    uint32_t options;
    uint32_t flags;
};

struct __attribute__((packed)) SwifterKitHIDStylusEvent {
    uint64_t timestamp;
    uint32_t identifier;
    int32_t x;
    int32_t y;
    int32_t tipPressure;
    int32_t barrelPressure;
    int32_t tiltX;
    int32_t tiltY;
    int32_t twist;
    uint32_t pointerType;
    uint32_t effect;
    uint64_t uniqueID;
    uint32_t flags;
    uint32_t reserved;
};

// Payload of hidDispatchDigitizerTouches, followed by count touches.
struct __attribute__((packed)) SwifterKitHIDTouchesHeader {
    uint64_t timestamp;
    uint32_t count;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitHIDTouch {
    uint32_t identifier;
    int32_t x;
    int32_t y;
    uint32_t flags;
};

// Payload of hidDispatchDigitizerCollection, followed by elementCount cookies.
struct __attribute__((packed)) SwifterKitHIDCollectionEvent {
    uint64_t timestamp;
    uint32_t type;
    uint32_t identifier;
    uint32_t parentCookie;
    uint32_t flags;
    int32_t x;
    int32_t y;
    int32_t z;
    uint32_t elementCount;
};

struct __attribute__((packed)) SwifterKitHIDGameControllerEvent {
    uint64_t timestamp;
    int32_t values[16];
    uint32_t flags;
    uint32_t options;
};

struct __attribute__((packed)) SwifterKitHIDExtendedGameControllerEvent {
    SwifterKitHIDGameControllerEvent standard;
    int32_t buttons[6];
};

struct __attribute__((packed)) SwifterKitHIDLEDState {
    uint32_t usagePage;
    uint32_t usage;
    uint32_t on;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitHIDDeviceSetting {
    uint32_t kind;
    uint32_t value;
};

// Event hidElementValues header, followed by count cookie and value pairs.
struct __attribute__((packed)) SwifterKitHIDElementValuesHeader {
    uint64_t timestamp;
    uint32_t reportID;
    uint32_t count;
};

struct __attribute__((packed)) SwifterKitHIDElementValueUpdate {
    uint32_t cookie;
    uint32_t value;
};

static_assert(sizeof(SwifterKitHIDReportCompletion) == 16);
static_assert(sizeof(SwifterKitHIDGetReportRequest) == 24);
static_assert(sizeof(SwifterKitHIDElementPageRequest) == 8);
static_assert(sizeof(SwifterKitHIDElementPage) == 8);
static_assert(sizeof(SwifterKitHIDElementDescriptor) == 80);
static_assert(sizeof(SwifterKitHIDElementValueRequest) == 16);
static_assert(sizeof(SwifterKitHIDElementValue) == 24);
static_assert(sizeof(SwifterKitHIDElementWrite) == 16);
static_assert(sizeof(SwifterKitHIDElementCommit) == 8);
static_assert(sizeof(SwifterKitHIDElementsCommit) == 8);
static_assert(sizeof(SwifterKitHIDUsageQuery) == 16);
static_assert(sizeof(SwifterKitHIDReportRequest) == 32);
static_assert(sizeof(SwifterKitHIDKeyboardEvent) == 32);
static_assert(sizeof(SwifterKitHIDPointerEvent) == 32);
static_assert(sizeof(SwifterKitHIDStylusEvent) == 64);
static_assert(sizeof(SwifterKitHIDTouchesHeader) == 16);
static_assert(sizeof(SwifterKitHIDTouch) == 16);
static_assert(sizeof(SwifterKitHIDCollectionEvent) == 40);
static_assert(sizeof(SwifterKitHIDGameControllerEvent) == 80);
static_assert(sizeof(SwifterKitHIDExtendedGameControllerEvent) == 104);
static_assert(sizeof(SwifterKitHIDLEDState) == 16);
static_assert(sizeof(SwifterKitHIDDeviceSetting) == 8);
static_assert(sizeof(SwifterKitHIDElementValuesHeader) == 16);
static_assert(sizeof(SwifterKitHIDElementValueUpdate) == 8);

#endif
