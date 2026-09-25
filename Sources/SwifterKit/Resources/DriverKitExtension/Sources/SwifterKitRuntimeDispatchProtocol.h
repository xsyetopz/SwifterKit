#ifndef SwifterKitRuntimeDispatchProtocol_h
#define SwifterKitRuntimeDispatchProtocol_h

#include <stdint.h>

// Payload layouts for timers and service watches (opcodes 0x0E00-0x0E12) and their lossy
// events. ServiceTimerCommands.swift and ServiceWatchCommands.swift encode the same layouts.

// Timers: at most kSwifterKitMaximumTimers at once. Durations are nanoseconds; a delay or
// leeway is at most kSwifterKitTimerMaximumNanoseconds, and a repeating interval lies in
// kSwifterKitTimerMinimumIntervalNanoseconds...kSwifterKitTimerMaximumNanoseconds.
static constexpr uint32_t kSwifterKitMaximumTimers = 16;
static constexpr uint64_t kSwifterKitTimerMinimumIntervalNanoseconds = 1'000'000ULL;
static constexpr uint64_t kSwifterKitTimerMaximumNanoseconds = 86'400'000'000'000ULL;

// Watches: at most kSwifterKitMaximumServiceWatches service-matching and system-state watches
// together; a state watch names 1...kSwifterKitMaximumWatchedStateItems items.
static constexpr uint32_t kSwifterKitMaximumServiceWatches = 8;
static constexpr uint32_t kSwifterKitMaximumWatchedStateItems = 8;

// Matches kIOServiceNotificationTypeTerminated and kIOServiceNotificationTypeMatched.
enum class SwifterKitServiceWatchKind : uint32_t {
    Terminated = 0,
    Matched = 1,
};

struct __attribute__((packed)) SwifterKitTimerStart {
    uint64_t delay;
    uint64_t interval;
    uint64_t leeway;
};

// A timer or watch identifier, in commands and replies.
struct __attribute__((packed)) SwifterKitDispatchIdentifier {
    uint32_t identifier;
    uint32_t reserved;
};

// kSwifterKitEventTimer. timestamp is clock_gettime_nsec_np(CLOCK_UPTIME_RAW) at the firing.
struct __attribute__((packed)) SwifterKitTimerEvent {
    uint32_t timerID;
    uint32_t reserved;
    uint64_t fireCount;
    uint64_t timestamp;
};

// kSwifterKitEventWatchServices, followed by nameLength bytes of the registry name.
// sequence counts the watch's notifications from 1, so Swift can detect dropped events.
struct __attribute__((packed)) SwifterKitServiceWatchEvent {
    uint32_t watchID;
    uint32_t kind;
    uint64_t sequence;
    uint64_t registryEntryID;
    uint32_t nameLength;
    uint32_t reserved;
};

// kSwifterKitEventWatchSystemState, followed by nameLength bytes of the item name and then the
// item's dictionary in the property encoding, or nothing when the item has no value.
struct __attribute__((packed)) SwifterKitSystemStateEvent {
    uint32_t watchID;
    uint32_t nameLength;
    uint64_t sequence;
};

static_assert(sizeof(SwifterKitTimerStart) == 24);
static_assert(sizeof(SwifterKitDispatchIdentifier) == 8);
static_assert(sizeof(SwifterKitTimerEvent) == 24);
static_assert(sizeof(SwifterKitServiceWatchEvent) == 32);
static_assert(sizeof(SwifterKitSystemStateEvent) == 16);

#endif
