#ifndef SwifterKitRuntimeReportingProtocol_h
#define SwifterKitRuntimeReportingProtocol_h

#include <stdint.h>

#include "SwifterKitRuntimeSchema.h"

// Payload layouts for IOReporting updates and reads (opcodes 0x0E20-0x0E21).
// ServiceReportingCommands.swift encodes the same layouts. The limits, SwifterKitReporterKind,
// and SwifterKitReporterOperation come from RuntimeSchema+Service.swift; the generator enforces
// the limits on the reporter tables.

// The values each SwifterKitReporterOperation reads; every other value must be zero.
//   SetValue, IncrementValue:        values[0] value or increment (simple reporters)
//   SetState:                        values[0] state ID (state reporters)
//   OverrideState, IncrementState:   values[0] state ID, [1] time in state, [2] transitions,
//                                    [3] last transition time (state reporters)
//   TallyValue:                      values[0] value (histogram reporters)
//   OverrideBucket:                  values[0] bucket index, [1] hits, [2] minimum, [3] maximum,
//                                    [4] sum (histogram reporters)

struct __attribute__((packed)) SwifterKitReporterUpdate {
    uint32_t reporterIndex;
    uint32_t operation;
    uint64_t channelID;
    int64_t values[5];
};

// A read of a simple reporter's value (stateID zero) or a state reporter's statistics for one
// state. The reply is SwifterKitReporterReading: a simple reporter fills values[0]; a state
// reporter fills transitions, residency time, and last transition time.
struct __attribute__((packed)) SwifterKitReporterRead {
    uint32_t reporterIndex;
    uint32_t reserved;
    uint64_t channelID;
    uint64_t stateID;
};

struct __attribute__((packed)) SwifterKitReporterReading {
    int64_t values[3];
};

static_assert(sizeof(SwifterKitReporterUpdate) == 56);
static_assert(sizeof(SwifterKitReporterRead) == 24);
static_assert(sizeof(SwifterKitReporterReading) == 24);

#endif
