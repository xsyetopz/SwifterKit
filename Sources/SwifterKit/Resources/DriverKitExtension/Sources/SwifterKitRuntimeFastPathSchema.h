// Generated from Sources/SwifterKit/DriverKit/Runtime/RuntimeSchema+FastPath.swift.
// Do not edit.
// Regenerate: SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter RuntimeSchemaTests

#ifndef SwifterKitRuntimeFastPathSchema_h
#define SwifterKitRuntimeFastPathSchema_h

#include <stdint.h>

static constexpr uint32_t kSwifterKitFastPathMaximumPrograms = 32;
static constexpr uint32_t kSwifterKitFastPathMaximumOperations = 64;
static constexpr uint32_t kSwifterKitFastPathSlotCount = 8;
static constexpr uint32_t kSwifterKitFastPathMaximumArguments = 4;
static constexpr uint32_t kSwifterKitFastPathMaximumPollIterations = 10000;
static constexpr uint32_t kSwifterKitFastPathMaximumPollIntervalMicroseconds = 1000;
static constexpr uint32_t kSwifterKitFastPathMaximumDelayMicroseconds = 1000;
static constexpr uint32_t kSwifterKitFastPathMaximumDelayBudgetMicroseconds = 10000;
static constexpr uint32_t kSwifterKitFastPathBARCount = 6;
static constexpr uint32_t kSwifterKitFastPathShiftLimit = 64;

enum class SwifterKitFastPathOpcode : uint32_t {
    Read = 1,
    Write = 2,
    Modify = 3,
    Compute = 4,
    Poll = 5,
    Delay = 6,
    Skip = 7,
    Emit = 8,
    Fail = 9,
};

enum class SwifterKitFastPathOperandKind : uint32_t {
    Constant = 0,
    Value = 1,
};

enum class SwifterKitFastPathComputeOperation : uint32_t {
    And = 1,
    Or = 2,
    Xor = 3,
    ShiftLeft = 4,
    ShiftRight = 5,
    Add = 6,
    Subtract = 7,
};

enum class SwifterKitFastPathConditionTest : uint32_t {
    Zero = 0,
    Nonzero = 1,
};

enum class SwifterKitFastPathTriggerKind : uint32_t {
    Start = 1,
    Stop = 2,
    Interrupt = 3,
    Command = 4,
};

enum class SwifterKitFastPathInterruptDelivery : uint32_t {
    Always = 1,
    Never = 2,
    WhenProgramEmits = 3,
};

struct SwifterKitFastPathProgram {
    uint32_t operationStart;
    uint32_t operationCount;
    uint32_t argumentCount;
    uint32_t delayBudgetMicroseconds;
};
static_assert(sizeof(SwifterKitFastPathProgram) == 16);

struct SwifterKitFastPathOperation {
    uint32_t opcode;
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint64_t immediate0;
    uint64_t immediate1;
    uint64_t immediate2;
};
static_assert(sizeof(SwifterKitFastPathOperation) == 40);

struct SwifterKitFastPathTrigger {
    uint32_t kind;
    uint32_t source;
    uint32_t delivery;
    uint32_t program;
};
static_assert(sizeof(SwifterKitFastPathTrigger) == 16);

struct SwifterKitFastPathBAR {
    uint32_t bar;
    uint32_t reserved;
    uint64_t minimumSize;
};
static_assert(sizeof(SwifterKitFastPathBAR) == 16);

#endif
