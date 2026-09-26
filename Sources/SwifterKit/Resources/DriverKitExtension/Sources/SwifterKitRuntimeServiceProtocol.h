#ifndef SwifterKitRuntimeServiceProtocol_h
#define SwifterKitRuntimeServiceProtocol_h

#include <stdint.h>

#include "SwifterKitRuntimeSchema.h"

// Payload layouts for the IOService operations (opcodes 0x0Dxx) and the power-state event.
// ServicePropertyCoding.swift encodes the same property values.

// Registry property values are tagged, little-endian, and nested at most
// kSwifterKitPropertyMaximumDepth levels deep:
//   Boolean:    tag, uint8_t 0 or 1
//   Number:     tag, uint8_t bit count (8, 16, 32, or 64), uint64_t value
//   String:     tag, uint32_t byte count, UTF-8 bytes without NUL
//   Data:       tag, uint32_t byte count, bytes
//   Array:      tag, uint32_t count, values
//   Dictionary: tag, uint32_t count, then per entry uint32_t key byte count, key, value
// Keys are unique, nonempty, and NUL-free. A payload holds exactly one value. The tags,
// the depth, and kSwifterKitPropertyNameMaximumLength (IOPropertyName and IORegistryPlaneName
// hold 128 bytes including the terminating NUL) come from RuntimeSchema+Service.swift.

struct __attribute__((packed)) SwifterKitServiceSearchHeader {
    uint32_t options;
    uint16_t nameLength;
    uint16_t planeLength;
};

struct __attribute__((packed)) SwifterKitServiceNamedValueHeader {
    uint32_t nameLength;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitServicePMAssertionHeader {
    uint32_t assertionBits;
    uint8_t synced;
    uint8_t reserved[3];
};

struct __attribute__((packed)) SwifterKitServicePowerStateCompletion {
    uint32_t requestID;
    uint32_t reserved;
};

struct __attribute__((packed)) SwifterKitServicePowerStateEvent {
    uint32_t requestID;
    uint32_t powerFlags;
};

static_assert(sizeof(SwifterKitServiceSearchHeader) == 8);
static_assert(sizeof(SwifterKitServiceNamedValueHeader) == 8);
static_assert(sizeof(SwifterKitServicePMAssertionHeader) == 8);
static_assert(sizeof(SwifterKitServicePowerStateCompletion) == 8);
static_assert(sizeof(SwifterKitServicePowerStateEvent) == 8);

#endif
