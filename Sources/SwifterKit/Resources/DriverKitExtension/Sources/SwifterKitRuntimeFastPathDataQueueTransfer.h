#ifndef SwifterKitRuntimeFastPathDataQueueTransfer_h
#define SwifterKitRuntimeFastPathDataQueueTransfer_h

#include <stddef.h>
#include <stdint.h>

#include "SwifterKitRuntimeFastPathInterpreter.h"
#include "SwifterKitRuntimeMappedMemory.h"

// The portable half of a to-extension data queue, shared by the extension and the host tests.
//
// The host writes a to-extension host ring and can write any bytes into it. Taking records
// trusts nothing in the mapping:
// - The record count and stride come from the generated data queue row, never from the header.
// - The producer count must be at most the record count ahead of the consumer count.
// - Each record's size is loaded once. It must be nonzero, at most the queue's maximum entry
//   size, and followed by a zero word, before a payload byte is read.
// A ring that breaks any rule is refused as corrupt. Nothing more is taken from it.
//
// `Staging` is the extension's staging queue with these members:
// - SwifterKitFastPathStagingResult Enqueue(const uint8_t* payload, uint32_t size)
// - bool Peek(uint64_t* words)
// - bool DequeueWithCoalesce(bool* sendDataServiced)
// - void SendDataServiced()
//
// Enqueue copies `size` bytes into a new entry, or reports that the queue is full. Peek fills
// `words` from the oldest entry with SwifterKitFastPathEntryWords, and returns false when the
// queue is empty. DequeueWithCoalesce removes the oldest entry. It sets its flag when a producer
// that found the queue full should be told it has room. SendDataServiced tells it.

enum class SwifterKitFastPathStagingResult : uint8_t {
    Enqueued,
    Full,
    Failed,
};

// What one pass over a to-extension host ring did.
struct SwifterKitFastPathTransfer {
    // The records moved into the staging queue.
    uint32_t moved;
    // The records still in the host ring. Zero when the ring is corrupt.
    uint32_t waiting;
    // The staging queue was full, so `waiting` records wait for it to free space.
    bool blocked;
    // The ring broke its layout. Nothing more was taken.
    bool corrupt;
};

// Moves every complete record from the to-extension host ring mapped at `address` into
// `staging`, oldest first. Releases each record to the host only after the staging queue holds
// it. Stops at the first record the staging queue has no room for.
template<typename Staging>
SwifterKitFastPathTransfer SwifterKitFastPathTakeHostRecords(
    const SwifterKitFastPathDataQueue& row,
    uint64_t address,
    Staging& staging) {
    SwifterKitFastPathTransfer transfer = {};
    const uint32_t count = SwifterKitFastPathDataQueueEntryCount(row);
    const uint32_t stride = SwifterKitFastPathDataQueueStride(row);
    const uint64_t consumerField = address + kSwifterKitFastPathDataQueueConsumerOffset;
    const uint32_t producer = __atomic_load_n(
        SwifterKitMappedPointer<uint32_t>(address + kSwifterKitFastPathDataQueueProducerOffset),
        __ATOMIC_ACQUIRE);
    uint32_t consumer =
        __atomic_load_n(SwifterKitMappedPointer<uint32_t>(consumerField), __ATOMIC_RELAXED);
    if (count == 0 || producer - consumer > count) {
        transfer.corrupt = true;
        return transfer;
    }
    while (consumer != producer) {
        const uint64_t record = address + kSwifterKitFastPathDataQueueHeaderSize
                                + uint64_t {consumer & (count - 1)} * stride;
        const uint32_t size =
            __atomic_load_n(SwifterKitMappedPointer<uint32_t>(record), __ATOMIC_RELAXED);
        const uint32_t reserved =
            __atomic_load_n(SwifterKitMappedPointer<uint32_t>(record + 4), __ATOMIC_RELAXED);
        if (size == 0 || size > row.maximumEntrySize || reserved != 0) {
            transfer.corrupt = true;
            transfer.waiting = 0;
            return transfer;
        }
        const SwifterKitFastPathStagingResult result = staging.Enqueue(
            SwifterKitMappedPointer(record + kSwifterKitFastPathDataQueueRecordHeaderSize),
            size);
        if (result != SwifterKitFastPathStagingResult::Enqueued) {
            transfer.blocked = result == SwifterKitFastPathStagingResult::Full;
            break;
        }
        consumer += 1;
        __atomic_store_n(
            SwifterKitMappedPointer<uint32_t>(consumerField),
            consumer,
            __ATOMIC_RELEASE);
        transfer.moved += 1;
    }
    transfer.waiting = producer - consumer;
    return transfer;
}

// Copies a staged entry's first words into `words`, little-endian, zero-filling the words and
// bytes the entry does not hold.
inline void SwifterKitFastPathEntryWords(const void* data, size_t size, uint64_t* words) {
    uint8_t bytes[kSwifterKitFastPathMaximumArguments * sizeof(uint64_t)] = {};
    const size_t copied = size < sizeof(bytes) ? size : sizeof(bytes);
    if (data != nullptr) {
        __builtin_memcpy(bytes, data, copied);
    }
    for (uint32_t word = 0; word < kSwifterKitFastPathMaximumArguments; ++word) {
        uint64_t value = 0;
        for (uint32_t byte = 0; byte < sizeof(uint64_t); ++byte) {
            value |= uint64_t {bytes[word * sizeof(uint64_t) + byte]} << (byte * 8);
        }
        words[word] = value;
    }
}

// Consumes the oldest staged entry:
// - Peeks its words.
// - Passes them to `run`.
// - Removes it with DequeueWithCoalesce, sending DataServiced when the dequeue says a producer
//   waits for room.
// Returns false when the queue is empty or refuses the dequeue.
template<typename Staging, typename Run>
bool SwifterKitFastPathConsumeEntry(Staging& staging, Run run) {
    uint64_t words[kSwifterKitFastPathMaximumArguments] = {};
    if (!staging.Peek(words)) {
        return false;
    }
    run(static_cast<const uint64_t*>(words));
    bool sendDataServiced = false;
    if (!staging.DequeueWithCoalesce(&sendDataServiced)) {
        return false;
    }
    if (sendDataServiced) {
        staging.SendDataServiced();
    }
    return true;
}

#endif
