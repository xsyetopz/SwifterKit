#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_FAST_PATH

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IODMACommand.h>
    #include <DriverKit/IOInterruptDispatchSource.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOReturn.h>
    #include <DriverKit/OSData.h>

    #include "SwifterKitRuntimeFastPathInterpreter.h"
    #include "SwifterKitRuntimeMappedMemory.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"

// Fast-path contract:
// - StartFastPath runs after the provider is open and before interrupt sources are enabled.
//   It re-validates every generated table, then checks each declared BAR with GetBARInfo.
//   When a table is invalid, or a BAR is missing or smaller than declared, the fast path is
//   refused with kIOReturnNoResources:
//   - No program runs.
//   - Commands answer with that status.
//   - Interrupt events are delivered as without a fast path.
//   Nothing runs partially.
// - Start programs run in table order. One that ends with a nonzero status refuses the fast
//   path with that status. The later programs do not run.
// - fastPathLock serializes every run, so a program's read-modify-write sequences never
//   interleave with another program's. It is held for one program: at most its 10 ms delay and
//   poll budget plus its register accesses and emits. A caller waits at most that long per
//   program ahead of it.
// - Interrupt programs run in InterruptOccurred before the interrupt event. The event is then
//   delivered according to the trigger's delivery. Command programs answer their command
//   exactly once, with the program's status and slots. Stop programs run first in Stop, before
//   any teardown. After them, no program runs again.
// - Rings are allocated after the tables and BARs check out and before start programs run.
//   This lets a start program hand the device a ring's address. Each ring is one
//   IOBufferMemoryDescriptor of a 64-byte header and its entries. It is mapped into the
//   extension and prepared for DMA with an IODMACommand on the PCI device. A ring the DMA
//   preparation cannot describe as one segment refuses the fast path, and every ring allocated
//   so far is released. The header holds:
//   - the producer index
//   - the consumer index
//   - the entry size
//   - the entry count (offsets kSwifterKitFastPathRing*Offset).
//   Indices are stored with release ordering and loaded with acquire ordering, because the host
//   maps the same buffer through CopyFastPathRingMemory. Rings stay allocated while the device
//   may hold their addresses. StopFastPath completes their DMA and releases them after the stop
//   programs run.
// - Host-shared data queues are created after the rings and released before them. See
//   SwifterKitRuntimeFastPathDataQueues.cpp. A run that enqueued entries signals their staging
//   sources once, before it releases fastPathLock. Data-available programs run on the runtime
//   queue under the same lock, one staged entry per acquisition.
// - emit queues a fast-path event through the lossy EnqueueEvent path. An event the full queue
//   rejects increments fastPathEventDrops, which Swift reads with FastPathStatus.

static_assert(
    SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Success)
    == static_cast<uint32_t>(kIOReturnSuccess));
static_assert(
    SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Refused)
    == static_cast<uint32_t>(kIOReturnNoResources));
static_assert(
    SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Rejected)
    == static_cast<uint32_t>(kIOReturnBadArgument));
static_assert(
    SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Timeout)
    == static_cast<uint32_t>(kIOReturnTimeout));
static_assert(
    SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::NotReady)
    == static_cast<uint32_t>(kIOReturnNotReady));
static_assert(
    SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Corrupt)
    == static_cast<uint32_t>(kIOReturnIOError));

namespace {
    constexpr SwifterKitFastPathTables kTables = {
        .programs = kSwifterKitFastPathPrograms,
        .programCount = kSwifterKitFastPathProgramCount,
        .operations = kSwifterKitFastPathOperations,
        .operationCount = kSwifterKitFastPathOperationCount,
        .triggers = kSwifterKitFastPathTriggers,
        .triggerCount = kSwifterKitFastPathTriggerCount,
        .bars = kSwifterKitFastPathBARSizes,
        .barCount = kSwifterKitFastPathBARSizeCount,
        .rings = kSwifterKitFastPathRings,
        .ringCount = kSwifterKitFastPathRingCount,
        .dataQueues = kSwifterKitFastPathDataQueues,
        .dataQueueCount = kSwifterKitFastPathDataQueueCount,
    };
    // Rings start on a page so the host maps them from their first byte.
    constexpr uint64_t kRingAlignment = 4096;
    // PrepareForDMA fills a caller array of up to 32 segments. A ring must need only one.
    constexpr uint32_t kSegmentCapacity = 32;
    constexpr uint32_t kMicrosecondsPerMillisecond = 1000;
    constexpr uint32_t kMaximumInterruptSources = 32;

    // The interpreter's register interface over the provider's PCI memory. The interpreter only
    // names a BAR whose size StartFastPath checked, at an offset inside that size.
    struct DeviceAccess {
        SwifterKitRuntimeService* service;
        SwifterKitRuntimeService_IVars* state;
        uint32_t program;

        [[nodiscard]] uint64_t Read(
            [[maybe_unused]] uint32_t bar,
            [[maybe_unused]] uint64_t offset,
            [[maybe_unused]] uint32_t width) const {
    #if SWIFTERKIT_ENABLE_PCI
            IOPCIDevice* device = state->pciDevice;
            const uint8_t index = state->fastPathMemoryIndices[bar % kSwifterKitFastPathBARCount];
            switch (width) {
                case 1: {
                    uint8_t value = 0;
                    device->MemoryRead8(index, offset, &value);
                    return value;
                }
                case 2: {
                    uint16_t value = 0;
                    device->MemoryRead16(index, offset, &value);
                    return value;
                }
                case 4: {
                    uint32_t value = 0;
                    device->MemoryRead32(index, offset, &value);
                    return value;
                }
                default: {
                    uint64_t value = 0;
                    device->MemoryRead64(index, offset, &value);
                    return value;
                }
            }
    #else
            return 0;
    #endif
        }

        void Write(
            [[maybe_unused]] uint32_t bar,
            [[maybe_unused]] uint64_t offset,
            [[maybe_unused]] uint32_t width,
            [[maybe_unused]] uint64_t value) const {
    #if SWIFTERKIT_ENABLE_PCI
            IOPCIDevice* device = state->pciDevice;
            const uint8_t index = state->fastPathMemoryIndices[bar % kSwifterKitFastPathBARCount];
            switch (width) {
                case 1:
                    device->MemoryWrite8(index, offset, static_cast<uint8_t>(value));
                    break;
                case 2:
                    device->MemoryWrite16(index, offset, static_cast<uint16_t>(value));
                    break;
                case 4:
                    device->MemoryWrite32(index, offset, static_cast<uint32_t>(value));
                    break;
                default:
                    device->MemoryWrite64(index, offset, value);
                    break;
            }
    #endif
        }

        // A whole millisecond sleeps. Shorter waits spin in IODelay.
        static void Delay(uint32_t microseconds) {
            if (microseconds % kMicrosecondsPerMillisecond == 0) {
                IOSleep(microseconds / kMicrosecondsPerMillisecond);
            } else {
                IODelay(microseconds);
            }
        }

        [[nodiscard]] uint64_t RingBase(uint32_t ring) const {
            return state->fastPathRings[ring % kSwifterKitFastPathMaximumRings].address;
        }

        [[nodiscard]] uint64_t RingLoad(uint32_t ring, uint64_t offset, uint32_t width) const {
            uint64_t value = 0;
            __builtin_memcpy(
                &value,
                SwifterKitMappedPointer(
                    RingBase(ring) + kSwifterKitFastPathRingHeaderSize + offset),
                width);
            return value;
        }

        void RingStore(uint32_t ring, uint64_t offset, uint32_t width, uint64_t value) const {
            __builtin_memcpy(
                SwifterKitMappedPointer(
                    RingBase(ring) + kSwifterKitFastPathRingHeaderSize + offset),
                &value,
                width);
        }

        [[nodiscard]] uint32_t* RingIndexPointer(uint32_t ring, uint32_t index) const {
            return SwifterKitMappedPointer<uint32_t>(
                RingBase(ring)
                + (index == 0 ? kSwifterKitFastPathRingProducerOffset
                              : kSwifterKitFastPathRingConsumerOffset));
        }

        [[nodiscard]] uint32_t RingIndex(uint32_t ring, uint32_t index) const {
            return __atomic_load_n(RingIndexPointer(ring, index), __ATOMIC_ACQUIRE);
        }

        void SetRingIndex(uint32_t ring, uint32_t index, uint32_t value) const {
            __atomic_store_n(RingIndexPointer(ring, index), value, __ATOMIC_RELEASE);
        }

        [[nodiscard]] uint64_t RingDeviceAddress(uint32_t ring) const {
            return state->fastPathRings[ring % kSwifterKitFastPathMaximumRings].deviceAddress;
        }

        void Enqueue(uint32_t queue, const uint64_t* values, uint32_t count) const {
            service->EnqueueFastPathData(queue, values, count);
        }

        void Emit(const uint64_t* values, uint32_t count) const {
            SwifterKitFastPathEvent event = {.program = program, .count = count, .values = {}};
            for (uint32_t index = 0; index < count && index < kSwifterKitFastPathSlotCount;
                 ++index) {
                event.values[index] = values[index];
            }
            if (service->EnqueueEvent(kSwifterKitEventFastPath, &event, sizeof(event))
                != kIOReturnSuccess) {
                state->fastPathEventDrops += 1;
            }
        }
    };

    // Re-validates the tables and resolves each declared BAR to its memory index, refusing the
    // fast path when a BAR is missing or smaller than declared.
    kern_return_t PrepareBARs(SwifterKitRuntimeService_IVars* state) {
        const SwifterKitFastPathBARSizes& bars = state->fastPathBARs;
        for (uint32_t bar = 0; bar < kSwifterKitFastPathBARCount; ++bar) {
            if (bars.sizes[bar] == 0) {
                continue;
            }
    #if SWIFTERKIT_ENABLE_PCI
            uint8_t memoryIndex = 0;
            uint64_t size = 0;
            uint8_t type = 0;
            if (state->pciDevice == nullptr
                || state->pciDevice
                           ->GetBARInfo(static_cast<uint8_t>(bar), &memoryIndex, &size, &type)
                       != kIOReturnSuccess
                || size < bars.sizes[bar]) {
                return kIOReturnNoResources;
            }
            state->fastPathMemoryIndices[bar] = memoryIndex;
    #else
            return kIOReturnNoResources;
    #endif
        }
        state->fastPathBARsStale = false;
        return kIOReturnSuccess;
    }

    void ReleaseRings(SwifterKitRuntimeService_IVars* state) {
        for (auto& ring : state->fastPathRings) {
            if (ring.dmaCommand != nullptr) {
                (void)ring.dmaCommand->CompleteDMA(0);
                OSSafeReleaseNULL(ring.dmaCommand);
            }
            OSSafeReleaseNULL(ring.map);
            OSSafeReleaseNULL(ring.buffer);
            ring = {};
        }
    }

    // Allocates, maps, and zeroes one ring, writes its geometry into the header, and prepares it
    // for DMA as a single segment.
    kern_return_t PrepareRing(
        IOService* provider,
        const SwifterKitFastPathRing& row,
        SwifterKitFastPathRingState* ring) {
        const uint64_t bytes =
            kSwifterKitFastPathRingHeaderSize + uint64_t {row.entrySize} * row.entryCount;
        kern_return_t result =
            IOBufferMemoryDescriptor::Create(row.direction, bytes, kRingAlignment, &ring->buffer);
        if (result == kIOReturnSuccess && ring->buffer != nullptr) {
            result = ring->buffer->SetLength(bytes);
        }
        if (result == kIOReturnSuccess && ring->buffer != nullptr) {
            result = ring->buffer->CreateMapping(0, 0, 0, bytes, 0, &ring->map);
        }
        if (result != kIOReturnSuccess || ring->buffer == nullptr || ring->map == nullptr
            || ring->map->GetAddress() == 0) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        ring->address = ring->map->GetAddress();
        __builtin_memset(SwifterKitMappedPointer(ring->address), 0, bytes);
        *SwifterKitMappedPointer<uint32_t>(ring->address + kSwifterKitFastPathRingEntrySizeOffset) =
            row.entrySize;
        *SwifterKitMappedPointer<uint32_t>(
            ring->address + kSwifterKitFastPathRingEntryCountOffset) = row.entryCount;

        IODMACommandSpecification specification = {};
        specification.maxAddressBits = 64;
        result = IODMACommand::Create(provider, 0, &specification, &ring->dmaCommand);
        if (result != kIOReturnSuccess || ring->dmaCommand == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        uint64_t flags = 0;
        uint32_t segmentCount = kSegmentCapacity;
        IOAddressSegment segments[kSegmentCapacity] = {};
        result = ring->dmaCommand
                     ->PrepareForDMA(0, ring->buffer, 0, bytes, &flags, &segmentCount, segments);
        if (result != kIOReturnSuccess) {
            // Nothing is prepared, so ReleaseRings must not complete it.
            OSSafeReleaseNULL(ring->dmaCommand);
            return result;
        }
        if (segmentCount != 1 || segments[0].length < bytes) {
            return kIOReturnNoResources;
        }
        ring->deviceAddress = segments[0].address + kSwifterKitFastPathRingHeaderSize;
        return kIOReturnSuccess;
    }

    // Prepares every ring on the PCI device, the provider that performs their DMA. Any failure
    // releases the rings prepared so far and refuses the fast path.
    kern_return_t PrepareRings(
        SwifterKitRuntimeService_IVars* state,
        const SwifterKitFastPathTables& tables) {
    #if SWIFTERKIT_ENABLE_PCI
        IOService* const provider = state->pciDevice;
    #else
        IOService* const provider = nullptr;
    #endif
        for (uint32_t index = 0; index < tables.ringCount; ++index) {
            if (provider == nullptr
                || PrepareRing(provider, tables.rings[index], &state->fastPathRings[index])
                       != kIOReturnSuccess) {
                ReleaseRings(state);
                return kIOReturnNoResources;
            }
        }
        return kIOReturnSuccess;
    }

    kern_return_t PrepareFastPath(SwifterKitRuntimeService_IVars* state) {
        uint32_t sources[kMaximumInterruptSources] = {};
        const uint32_t sourceCount = kSwifterKitInterruptSourceCount < kMaximumInterruptSources
                                         ? kSwifterKitInterruptSourceCount
                                         : kMaximumInterruptSources;
        for (uint32_t index = 0; index < sourceCount; ++index) {
            sources[index] = kSwifterKitInterruptIndices[index] & kIOInterruptSourceIndexMask;
        }
        if (!SwifterKitFastPathIsValidConfiguration(
                kTables,
                sources,
                sourceCount,
                &state->fastPathBARs)) {
            return kIOReturnNoResources;
        }
        const kern_return_t result = PrepareBARs(state);
        return result == kIOReturnSuccess ? PrepareRings(state, kTables) : result;
    }

    // Runs one program. The caller holds fastPathLock. Returns the fast path's refusal or stop
    // status when it cannot run. Otherwise returns kIOReturnSuccess with the program's own
    // status in `outcome`.
    kern_return_t ExecuteHoldingLock(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        uint32_t program,
        const uint64_t* arguments,
        uint32_t argumentCount,
        SwifterKitFastPathOutcome* outcome) {
        *outcome = {};
        kern_return_t result = state->fastPathRunning ? kIOReturnSuccess : kIOReturnNotReady;
        // A PCI reset can move BARs. Resolve them again before the next access.
        if (result == kIOReturnSuccess && state->fastPathBARsStale) {
            result = PrepareBARs(state);
            if (result != kIOReturnSuccess) {
                state->fastPathRunning = false;
                state->fastPathRefusal = result;
            }
        }
        if (result == kIOReturnSuccess) {
            DeviceAccess access = {.service = service, .state = state, .program = program};
            *outcome = SwifterKitFastPathExecute(
                kTables,
                program,
                state->fastPathBARs,
                arguments,
                argumentCount,
                access);
            // One DataAvailable per run, however many entries the program enqueued.
            service->SignalFastPathDataQueues();
        }
        return result;
    }

    // Runs one program under fastPathLock.
    kern_return_t RunProgram(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        uint32_t program,
        const uint64_t* arguments,
        uint32_t argumentCount,
        SwifterKitFastPathOutcome* outcome) {
        IOLockLock(state->fastPathLock);
        const kern_return_t result =
            ExecuteHoldingLock(service, state, program, arguments, argumentCount, outcome);
        IOLockUnlock(state->fastPathLock);
        return result;
    }

    // Runs every program of `kind` in table order and returns the first nonzero status.
    kern_return_t RunPrograms(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        SwifterKitFastPathTriggerKind kind) {
        for (uint32_t program = 0; program < kTables.triggerCount; ++program) {
            if (kTables.triggers[program].kind != static_cast<uint32_t>(kind)) {
                continue;
            }
            SwifterKitFastPathOutcome outcome = {};
            const kern_return_t result = RunProgram(service, state, program, nullptr, 0, &outcome);
            if (result != kIOReturnSuccess) {
                return result;
            }
            if (outcome.status != SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Success)) {
                return static_cast<kern_return_t>(outcome.status);
            }
        }
        return kIOReturnSuccess;
    }

    kern_return_t RunCommand(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        SwifterKitFastPathRunRequest request = {};
        if (payloadLength != sizeof(request)) {
            return kIOReturnBadArgument;
        }
        __builtin_memcpy(&request, payload, sizeof(request));
        if (request.argumentCount > kSwifterKitFastPathMaximumArguments) {
            return kIOReturnBadArgument;
        }
        for (uint32_t index = request.argumentCount; index < kSwifterKitFastPathMaximumArguments;
             ++index) {
            if (request.arguments[index] != 0) {
                return kIOReturnBadArgument;
            }
        }
        if (!SwifterKitFastPathIsCommand(kTables, request.program, request.argumentCount)) {
            return kIOReturnBadArgument;
        }
        SwifterKitFastPathOutcome outcome = {};
        const kern_return_t result = RunProgram(
            service,
            state,
            request.program,
            request.arguments,
            request.argumentCount,
            &outcome);
        if (result != kIOReturnSuccess) {
            return result;
        }
        if (!outcome.executed) {
            return static_cast<kern_return_t>(outcome.status);
        }
        SwifterKitFastPathRunResult reply = {.status = outcome.status, .reserved = 0, .values = {}};
        for (uint32_t slot = 0; slot < kSwifterKitFastPathSlotCount; ++slot) {
            reply.values[slot] = outcome.slots[slot];
        }
        *response = OSData::withBytes(&reply, sizeof(reply));
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }
}  // namespace

void SwifterKitRuntimeService::StartFastPath() {
    if (ivars == nullptr || ivars->fastPathLock == nullptr) {
        return;
    }
    IOLockLock(ivars->fastPathLock);
    kern_return_t prepared = PrepareFastPath(ivars);
    if (prepared == kIOReturnSuccess) {
        prepared = StartFastPathDataQueues();
        if (prepared != kIOReturnSuccess) {
            ReleaseRings(ivars);
        }
    }
    ivars->fastPathRunning = prepared == kIOReturnSuccess;
    ivars->fastPathRefusal = prepared;
    IOLockUnlock(ivars->fastPathLock);
    if (prepared != kIOReturnSuccess) {
        return;
    }
    const kern_return_t started = RunPrograms(this, ivars, SwifterKitFastPathTriggerKind::Start);
    if (started != kIOReturnSuccess) {
        IOLockLock(ivars->fastPathLock);
        ivars->fastPathRunning = false;
        ivars->fastPathRefusal = started;
        IOLockUnlock(ivars->fastPathLock);
    }
}

void SwifterKitRuntimeService::StopFastPath() {
    if (ivars == nullptr || ivars->fastPathLock == nullptr) {
        return;
    }
    (void)RunPrograms(this, ivars, SwifterKitFastPathTriggerKind::Stop);
    IOLockLock(ivars->fastPathLock);
    ivars->fastPathRunning = false;
    ivars->fastPathRefusal = kIOReturnNotReady;
    StopFastPathDataQueues();
    ReleaseRings(ivars);
    IOLockUnlock(ivars->fastPathLock);
}

kern_return_t SwifterKitRuntimeService::CopyFastPathRingMemory(
    uint32_t identifier,
    IOMemoryDescriptor** memory) {
    if (ivars == nullptr || ivars->fastPathLock == nullptr || memory == nullptr) {
        return kIOReturnNotReady;
    }
    IOLockLock(ivars->fastPathLock);
    const uint32_t ring = SwifterKitFastPathRingNamed(kTables, identifier);
    kern_return_t result = kIOReturnSuccess;
    if (ring >= kTables.ringCount) {
        result = kIOReturnBadArgument;
    } else if (!ivars->fastPathRunning || ivars->fastPathRings[ring].buffer == nullptr) {
        result = kIOReturnNotReady;
    } else {
        // DriverKit consumes this reference. The ring keeps its own until StopFastPath.
        ivars->fastPathRings[ring].buffer->retain();
        *memory = ivars->fastPathRings[ring].buffer;
    }
    IOLockUnlock(ivars->fastPathLock);
    return result;
}

void SwifterKitRuntimeService::InvalidateFastPathBARs() {
    if (ivars == nullptr || ivars->fastPathLock == nullptr) {
        return;
    }
    IOLockLock(ivars->fastPathLock);
    ivars->fastPathBARsStale = true;
    IOLockUnlock(ivars->fastPathLock);
}

// The caller holds fastPathLock and passes a staged entry's first words. The program receives
// as many as it declares arguments.
bool SwifterKitRuntimeService::RunFastPathDataAvailable(uint32_t queue, const uint64_t* words) {
    const uint32_t program = SwifterKitFastPathTriggeredProgram(
        kTables,
        SwifterKitFastPathTriggerKind::DataAvailable,
        queue);
    if (ivars == nullptr || program >= kTables.programCount) {
        return false;
    }
    SwifterKitFastPathOutcome outcome = {};
    return ExecuteHoldingLock(
               this,
               ivars,
               program,
               words,
               kTables.programs[program].argumentCount,
               &outcome)
               == kIOReturnSuccess
           && outcome.executed;
}

bool SwifterKitRuntimeService::RunFastPathInterrupt(uint32_t sourceIndex) {
    const uint32_t program = SwifterKitFastPathInterruptProgram(kTables, sourceIndex);
    if (ivars == nullptr || ivars->fastPathLock == nullptr || program >= kTables.programCount) {
        return true;
    }
    SwifterKitFastPathOutcome outcome = {};
    const bool ran = RunProgram(this, ivars, program, nullptr, 0, &outcome) == kIOReturnSuccess
                     && outcome.executed;
    return SwifterKitFastPathDeliversInterrupt(
        kTables.triggers[program].delivery,
        ran,
        outcome.emitted);
}

kern_return_t SwifterKitRuntimeService::FastPathCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->fastPathLock == nullptr || response == nullptr
        || (payloadLength != 0 && payload == nullptr)) {
        return kIOReturnBadArgument;
    }
    *response = nullptr;
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::FastPathRun:
            return RunCommand(this, ivars, payload, payloadLength, response);
        case SwifterKitRuntimeOpcode::FastPathDataQueueNotify:
            return NotifyFastPathDataQueue(payload, payloadLength, response);
        case SwifterKitRuntimeOpcode::FastPathStatus: {
            if (payloadLength != 0) {
                return kIOReturnBadArgument;
            }
            IOLockLock(ivars->fastPathLock);
            const kern_return_t status =
                ivars->fastPathRunning
                    ? kIOReturnSuccess
                    : (ivars->fastPathRefusal == kIOReturnSuccess ? kIOReturnNotReady
                                                                  : ivars->fastPathRefusal);
            const SwifterKitFastPathStatusReply reply = {
                .status = static_cast<uint32_t>(status),
                .reserved = 0,
                .droppedEvents = ivars->fastPathEventDrops,
            };
            IOLockUnlock(ivars->fastPathLock);
            *response = OSData::withBytes(&reply, sizeof(reply));
            return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
        default:
            return kIOReturnUnsupported;
    }
}

#endif
