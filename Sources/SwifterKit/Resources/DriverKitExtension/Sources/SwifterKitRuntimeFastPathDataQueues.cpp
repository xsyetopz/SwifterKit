#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_FAST_PATH

    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IODataQueueDispatchSource.h>
    #include <DriverKit/IODispatchQueue.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOReturn.h>
    #include <DriverKit/OSAction.h>

    #include "SwifterKitRuntimeDispatchSources.h"
    #include "SwifterKitRuntimeFastPathInterpreter.h"
    #include "SwifterKitRuntimeMappedMemory.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeServiceState.h"

// Host-shared data queue contract:
// - IODataQueueDispatchSource::CopyMemory is private, so the host cannot map a dispatch source's
//   queue. Each queue is instead a host ring, one IOBufferMemoryDescriptor of a
//   kSwifterKitFastPathDataQueueHeaderSize-byte header and capacityBytes of fixed-stride records
//   that CopyFastPathDataQueueMemory hands to the host, plus an IODataQueueDispatchSource that
//   stages to-host entries between the fast path and the runtime queue. The header's geometry
//   is written once at start; the kSwifterKitFastPathDataQueue*Offset constants place every
//   field.
// - StartFastPathDataQueues runs under fastPathLock after the rings are prepared and before any
//   start program. It creates every host ring and, for to-host queues, a staging source sized
//   with GetDataQueueEntryHeaderSize for one more entry than the host ring holds; a source whose
//   CanEnqueueData(maximumEntrySize, entryCount) check fails refuses the fast path, as does any
//   allocation failure, and everything created so far is released.
// - An `enqueue` runs under fastPathLock on whatever queue ran the program (the interrupt queue
//   for interrupt programs). It checks CanEnqueueData, then stages the entry with
//   EnqueueWithCoalesce; an entry that does not fit is dropped and counted, because fast-path
//   emits are lossy and never fail a program. The DataAvailable notification EnqueueWithCoalesce
//   defers is sent once per run with SendDataAvailable, so a program that enqueues many entries
//   wakes the runtime queue once.
// - FastPathDataAvailable runs on the runtime queue. Under fastPathLock, and only while the fast
//   path runs, it drains every staging source completely (IsDataAvailable and Dequeue) into its
//   host ring. An entry that finds the host ring full, or a consumer index the host corrupted,
//   is dropped and counted; draining never stops early, because DataAvailable fires again only
//   after the source becomes non-empty. Each record is written before the producer index, which
//   is stored with release ordering; the host's consumer index is loaded with acquire ordering.
//   One fastPathDataQueue event per drained queue that published entries tells the host; the
//   event queue is lossy, so the host reads until the ring is empty rather than counting events.
// - StopFastPathDataQueues runs under fastPathLock after fastPathRunning is cleared: it cancels
//   every source and releases the host rings. A host mapping keeps its ring's memory alive.

namespace {
    constexpr uint64_t kPageAlignment = 4096;

    const SwifterKitFastPathDataQueue& QueueRow(uint32_t index) {
        return kSwifterKitFastPathDataQueues[index % kSwifterKitFastPathMaximumDataQueues];
    }

    bool IsToHost(const SwifterKitFastPathDataQueue& row) {
        return row.direction == static_cast<uint32_t>(SwifterKitFastPathDataQueueDirection::ToHost);
    }

    uint32_t* HeaderField(const SwifterKitFastPathDataQueueState& queue, uint32_t offset) {
        return SwifterKitMappedPointer<uint32_t>(queue.address + offset);
    }

    void StoreDrops(const SwifterKitFastPathDataQueueState& queue) {
        __atomic_store_n(
            SwifterKitMappedPointer<uint64_t>(
                queue.address + kSwifterKitFastPathDataQueueDropsOffset),
            queue.drops,
            __ATOMIC_RELEASE);
    }

    void CountDrop(SwifterKitFastPathDataQueueState* queue) {
        queue->drops += 1;
        StoreDrops(*queue);
    }

    // Appends one record to a to-host ring. Returns false when the ring is full or the host's
    // consumer index is more than the record count behind; nothing is written then.
    bool Publish(
        const SwifterKitFastPathDataQueue& row,
        const SwifterKitFastPathDataQueueState& queue,
        const void* data,
        size_t size) {
        const uint32_t count = SwifterKitFastPathDataQueueEntryCount(row);
        const uint32_t stride = SwifterKitFastPathDataQueueStride(row);
        const uint32_t producer = __atomic_load_n(
            HeaderField(queue, kSwifterKitFastPathDataQueueProducerOffset),
            __ATOMIC_RELAXED);
        const uint32_t consumer = __atomic_load_n(
            HeaderField(queue, kSwifterKitFastPathDataQueueConsumerOffset),
            __ATOMIC_ACQUIRE);
        if (producer - consumer >= count || size == 0 || size > row.maximumEntrySize) {
            return false;
        }
        const uint64_t record = queue.address + kSwifterKitFastPathDataQueueHeaderSize
                                + uint64_t {producer & (count - 1)} * stride;
        *SwifterKitMappedPointer<uint32_t>(record) = static_cast<uint32_t>(size);
        *SwifterKitMappedPointer<uint32_t>(record + 4) = 0;
        __builtin_memcpy(
            SwifterKitMappedPointer(record + kSwifterKitFastPathDataQueueRecordHeaderSize),
            data,
            size);
        __atomic_store_n(
            HeaderField(queue, kSwifterKitFastPathDataQueueProducerOffset),
            producer + 1,
            __ATOMIC_RELEASE);
        return true;
    }

    // Allocates, maps, and zeroes one host ring and writes its geometry into the header.
    kern_return_t PrepareHostRing(
        const SwifterKitFastPathDataQueue& row,
        SwifterKitFastPathDataQueueState* queue) {
        const uint64_t bytes =
            kSwifterKitFastPathDataQueueHeaderSize + uint64_t {row.capacityBytes};
        kern_return_t result = IOBufferMemoryDescriptor::Create(
            kIOMemoryDirectionInOut,
            bytes,
            kPageAlignment,
            &queue->buffer);
        if (result == kIOReturnSuccess && queue->buffer != nullptr) {
            result = queue->buffer->SetLength(bytes);
        }
        if (result == kIOReturnSuccess && queue->buffer != nullptr) {
            result = queue->buffer->CreateMapping(0, 0, 0, bytes, 0, &queue->map);
        }
        if (result != kIOReturnSuccess || queue->buffer == nullptr || queue->map == nullptr
            || queue->map->GetAddress() == 0) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        queue->address = queue->map->GetAddress();
        __builtin_memset(SwifterKitMappedPointer(queue->address), 0, bytes);
        *HeaderField(*queue, kSwifterKitFastPathDataQueueEntryCountOffset) =
            SwifterKitFastPathDataQueueEntryCount(row);
        *HeaderField(*queue, kSwifterKitFastPathDataQueueStrideOffset) =
            SwifterKitFastPathDataQueueStride(row);
        *HeaderField(*queue, kSwifterKitFastPathDataQueueMaximumEntrySizeOffset) =
            row.maximumEntrySize;
        *HeaderField(*queue, kSwifterKitFastPathDataQueueDirectionOffset) = row.direction;
        return kIOReturnSuccess;
    }

    // Creates a to-host queue's staging source on the runtime queue and checks that it holds as
    // many maximum-size entries as the host ring.
    kern_return_t PrepareStaging(
        const SwifterKitFastPathDataQueue& row,
        const SwifterKitRuntimeService_IVars* state,
        SwifterKitFastPathDataQueueState* queue) {
        const uint64_t entries = SwifterKitFastPathDataQueueEntryCount(row);
        const uint64_t bytes =
            (entries + 1)
            * (IODataQueueDispatchSource::GetDataQueueEntryHeaderSize() + row.maximumEntrySize);
        kern_return_t result = IODataQueueDispatchSource::Create(
            bytes,
            state->fastPathDataQueueDispatch,
            &queue->staging);
        if (result != kIOReturnSuccess || queue->staging == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        if (queue->staging->CanEnqueueData(row.maximumEntrySize, static_cast<uint32_t>(entries))
            != kIOReturnSuccess) {
            return kIOReturnNoResources;
        }
        result = queue->staging->SetDataAvailableHandler(state->fastPathDataAvailableAction);
        return result == kIOReturnSuccess ? SwifterKitEnableSource(queue->staging) : result;
    }

    void ReleaseDataQueues(SwifterKitRuntimeService_IVars* state) {
        for (auto& queue : state->fastPathDataQueues) {
            if (queue.staging != nullptr) {
                (void)queue.staging->Cancel(nullptr);
            }
            OSSafeReleaseNULL(queue.staging);
            OSSafeReleaseNULL(queue.map);
            OSSafeReleaseNULL(queue.buffer);
            queue = {};
        }
        if (state->fastPathDataAvailableAction != nullptr) {
            (void)state->fastPathDataAvailableAction->Cancel(nullptr);
        }
        OSSafeReleaseNULL(state->fastPathDataAvailableAction);
        OSSafeReleaseNULL(state->fastPathDataQueueDispatch);
    }

    // Moves every staged entry of one to-host queue into its host ring and returns how many
    // were published.
    uint32_t Drain(
        const SwifterKitFastPathDataQueue& row,
        SwifterKitFastPathDataQueueState* queue) {
        struct Batch {
            const SwifterKitFastPathDataQueue* row;
            SwifterKitFastPathDataQueueState* queue;
            uint32_t published;
        } batch = {.row = &row, .queue = queue, .published = 0};
        Batch* const pointer = &batch;
        while (queue->staging->IsDataAvailable()) {
            const kern_return_t result = queue->staging->Dequeue(^(const void* data, size_t size) {
              if (Publish(*pointer->row, *pointer->queue, data, size)) {
                  pointer->published += 1;
              } else {
                  CountDrop(pointer->queue);
              }
            });
            if (result != kIOReturnSuccess) {
                break;
            }
        }
        return batch.published;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartFastPathDataQueues() {
    if (kSwifterKitFastPathDataQueueCount == 0) {
        return kIOReturnSuccess;
    }
    kern_return_t result =
        CopyDispatchQueue(kIOServiceDefaultQueueName, &ivars->fastPathDataQueueDispatch);
    if (result == kIOReturnSuccess) {
        result = CreateActionFastPathDataAvailable(0, &ivars->fastPathDataAvailableAction);
    }
    for (uint32_t index = 0;
         index < kSwifterKitFastPathDataQueueCount && result == kIOReturnSuccess;
         ++index) {
        const SwifterKitFastPathDataQueue& row = QueueRow(index);
        SwifterKitFastPathDataQueueState* queue = &ivars->fastPathDataQueues[index];
        result = PrepareHostRing(row, queue);
        if (result == kIOReturnSuccess && IsToHost(row)) {
            result = PrepareStaging(row, ivars, queue);
        }
    }
    if (result != kIOReturnSuccess) {
        ReleaseDataQueues(ivars);
        return kIOReturnNoResources;
    }
    return kIOReturnSuccess;
}

void SwifterKitRuntimeService::StopFastPathDataQueues() {
    ReleaseDataQueues(ivars);
}

void SwifterKitRuntimeService::EnqueueFastPathData(
    uint32_t queueIndex,
    const uint64_t* values,
    uint32_t count) {
    SwifterKitFastPathDataQueueState* queue =
        &ivars->fastPathDataQueues[queueIndex % kSwifterKitFastPathMaximumDataQueues];
    const uint32_t size = count * static_cast<uint32_t>(sizeof(uint64_t));
    if (queue->staging == nullptr || queue->staging->CanEnqueueData(size) != kIOReturnSuccess) {
        CountDrop(queue);
        return;
    }
    bool sendDataAvailable = false;
    const kern_return_t result =
        queue->staging->EnqueueWithCoalesce(size, &sendDataAvailable, ^(void* data, size_t bytes) {
          __builtin_memcpy(data, values, bytes < size ? bytes : size);
        });
    if (result != kIOReturnSuccess) {
        CountDrop(queue);
        return;
    }
    queue->notify = queue->notify || sendDataAvailable;
}

void SwifterKitRuntimeService::SignalFastPathDataQueues() {
    for (auto& queue : ivars->fastPathDataQueues) {
        if (queue.notify && queue.staging != nullptr) {
            queue.staging->SendDataAvailable();
        }
        queue.notify = false;
    }
}

void SwifterKitRuntimeService::FastPathDataAvailable_Impl([[maybe_unused]] OSAction* action) {
    if (ivars == nullptr || ivars->fastPathLock == nullptr) {
        return;
    }
    IOLockLock(ivars->fastPathLock);
    for (uint32_t index = 0; index < kSwifterKitFastPathDataQueueCount && ivars->fastPathRunning;
         ++index) {
        const SwifterKitFastPathDataQueue& row = QueueRow(index);
        SwifterKitFastPathDataQueueState* queue = &ivars->fastPathDataQueues[index];
        if (!IsToHost(row) || queue->staging == nullptr) {
            continue;
        }
        const uint32_t published = Drain(row, queue);
        if (published != 0) {
            const SwifterKitFastPathDataQueueEvent event = {
                .id = row.id,
                .published = published,
                .droppedEntries = queue->drops,
            };
            (void)EnqueueEvent(kSwifterKitEventFastPathDataQueue, &event, sizeof(event));
        }
    }
    IOLockUnlock(ivars->fastPathLock);
}

kern_return_t SwifterKitRuntimeService::CopyFastPathDataQueueMemory(
    uint32_t identifier,
    IOMemoryDescriptor** memory) {
    if (ivars == nullptr || ivars->fastPathLock == nullptr || memory == nullptr) {
        return kIOReturnNotReady;
    }
    IOLockLock(ivars->fastPathLock);
    uint32_t index = 0;
    while (index < kSwifterKitFastPathDataQueueCount && QueueRow(index).id != identifier) {
        ++index;
    }
    kern_return_t result = kIOReturnSuccess;
    if (index >= kSwifterKitFastPathDataQueueCount) {
        result = kIOReturnBadArgument;
    } else if (!ivars->fastPathRunning || ivars->fastPathDataQueues[index].buffer == nullptr) {
        result = kIOReturnNotReady;
    } else {
        // DriverKit consumes this reference; the queue keeps its own until StopFastPath.
        ivars->fastPathDataQueues[index].buffer->retain();
        *memory = ivars->fastPathDataQueues[index].buffer;
    }
    IOLockUnlock(ivars->fastPathLock);
    return result;
}

#endif
