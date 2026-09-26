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
static constexpr uint32_t kSwifterKitFastPathMaximumRings = 8;
static constexpr uint32_t kSwifterKitFastPathMinimumRingEntrySize = 8;
static constexpr uint32_t kSwifterKitFastPathMaximumRingEntrySize = 4096;
static constexpr uint32_t kSwifterKitFastPathMinimumRingEntryCount = 2;
static constexpr uint32_t kSwifterKitFastPathMaximumRingEntryCount = 65536;
static constexpr uint32_t kSwifterKitFastPathMaximumRingBytes = 4194304;
static constexpr uint32_t kSwifterKitFastPathRingHeaderSize = 64;
static constexpr uint32_t kSwifterKitFastPathRingProducerOffset = 0;
static constexpr uint32_t kSwifterKitFastPathRingConsumerOffset = 4;
static constexpr uint32_t kSwifterKitFastPathRingEntrySizeOffset = 8;
static constexpr uint32_t kSwifterKitFastPathRingEntryCountOffset = 12;

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
    RingLoad = 10,
    RingStore = 11,
    RingAdvance = 12,
};

enum class SwifterKitFastPathOperandKind : uint32_t {
    Constant = 0,
    Value = 1,
    RingDeviceAddress = 2,
    RingIndex = 3,
};

enum class SwifterKitFastPathRingAddressHalf : uint32_t {
    Low = 0,
    High = 1,
};

enum class SwifterKitFastPathRingIndex : uint32_t {
    Producer = 0,
    Consumer = 1,
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

enum class SwifterKitFastPathStatus : uint32_t {
    Success = 0x00000000,
    Refused = 0xE00002BE,
    Rejected = 0xE00002C2,
    Timeout = 0xE00002D6,
    NotReady = 0xE00002D8,
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

struct SwifterKitFastPathRing {
    uint32_t id;
    uint32_t entrySize;
    uint32_t entryCount;
    uint32_t direction;
};
static_assert(sizeof(SwifterKitFastPathRing) == 16);

struct SwifterKitFastPathRunRequest {
    uint32_t program;
    uint32_t argumentCount;
    uint64_t arguments[4];
};
static_assert(sizeof(SwifterKitFastPathRunRequest) == 40);

struct SwifterKitFastPathRunResult {
    uint32_t status;
    uint32_t reserved;
    uint64_t values[8];
};
static_assert(sizeof(SwifterKitFastPathRunResult) == 72);

struct SwifterKitFastPathEvent {
    uint32_t program;
    uint32_t count;
    uint64_t values[8];
};
static_assert(sizeof(SwifterKitFastPathEvent) == 72);

struct SwifterKitFastPathStatusReply {
    uint32_t status;
    uint32_t reserved;
    uint64_t droppedEvents;
};
static_assert(sizeof(SwifterKitFastPathStatusReply) == 16);

static constexpr uint64_t kSwifterKitMemoryMaximumHandle = 0xFFFFFF;
static constexpr uint32_t kSwifterKitMemoryMaximumChainLength = 32;
static constexpr uint32_t kSwifterKitMemorySubrangeHeaderSize = 32;
static constexpr uint32_t kSwifterKitMemoryChainHeaderSize = 8;
static constexpr uint32_t kSwifterKitMemoryMaximumClientSegments = 32;
static constexpr uint32_t kSwifterKitMemoryClientHeaderSize = 8;
static constexpr uint32_t kSwifterKitMemoryClientSegmentSize = 16;
static constexpr uint32_t kSwifterKitClientMemoryKindShift = 24;
static constexpr uint32_t kSwifterKitClientMemoryIdentifierMask = 0xFFFFFF;

enum class SwifterKitMemoryStatus : uint32_t {
    InUse = 0xE00002D5,
};

enum class SwifterKitClientMemoryKind : uint32_t {
    MemoryBuffer = 1,
    PacketPool = 2,
    Ring = 3,
    DataQueue = 4,
};

enum class SwifterKitPacketPool : uint32_t {
    Transmit = 0,
    Receive = 1,
};

#endif
