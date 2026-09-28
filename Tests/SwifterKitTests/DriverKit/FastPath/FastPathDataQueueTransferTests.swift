import Foundation
import Testing

@testable import SwifterKit

/// Runs `SwifterKitRuntimeFastPathDataQueueTransfer.h` on the host against a fake staging queue:
/// - The extension's doorbell move out of a to-extension host ring.
/// - Its corrupt-ring refusals.
/// - The data-available consumer that runs the interpreter on each entry.
@Suite
struct FastPathDataQueueTransferTests {
  /// Queue 4 holds 64 records of 64 bytes (32-byte entries). Program 0 consumes it.
  static let configuration = FastPathConfiguration(
    programs: [
      FastPathProgram(
        trigger: .dataAvailable(4),
        argumentCount: 3,
        operations: [
          .compute(.v3, .add, .value(.v0)), .compute(.v3, .add, .value(.v1)),
          .enqueue(3, slots: [.v3, .v2]),
        ]
      )
    ],
    dataQueues: [
      FastPathDataQueue(id: 3, capacityBytes: 4096, maximumEntrySize: 16, direction: .toHost),
      FastPathDataQueue(id: 4, capacityBytes: 4096, maximumEntrySize: 32, direction: .toExtension),
    ]
  )

  static let expected = [
    // Two records fit the staging queue. The third waits and arms DataServiced.
    "take moved=2 waiting=1 blocked=1 corrupt=0 consumer=2 log=E8,E24,full",
    // Each entry runs the program on its first words, then is dequeued. The first dequeue after
    // the failed enqueue reports DataServiced, which is sent only after it.
    "consume ran=1 status=0 slots=5,0,0,5,0,0,0,0 queued=5:0 log=K,D,S",
    "consume ran=1 status=0 slots=1,2,3,3,0,0,0,0 queued=3:3 log=K,D",
    "resume moved=1 waiting=0 blocked=0 corrupt=0 consumer=3 log=E32",
    "consume ran=1 status=0 slots=7,0,0,7,0,0,0,0 queued=7:0 log=K,D", "empty ran=0 log=",
    "words 1122334455667788,99AABBCC,0,0",
    // A corrupt ring is refused before any record is read, or at the first bad record.
    "producer-ahead moved=0 waiting=0 blocked=0 corrupt=1 consumer=0 log=",
    "consumer-ahead moved=0 waiting=0 blocked=0 corrupt=1 consumer=5 log=",
    "size-zero moved=0 waiting=0 blocked=0 corrupt=1 consumer=0 log=",
    "size-over moved=0 waiting=0 blocked=0 corrupt=1 consumer=0 log=",
    "reserved moved=0 waiting=0 blocked=0 corrupt=1 consumer=0 log=",
    "second-bad moved=1 waiting=0 blocked=0 corrupt=1 consumer=1 log=E8",
    // The header's geometry is the host's to write, so it is never used for addressing.
    "header-geometry moved=64 waiting=0 blocked=0 corrupt=0 consumer=64 log=64",
    "wrapped moved=2 waiting=0 blocked=0 corrupt=0 consumer=1 log=E8,E8",
  ]

  @Test
  func configurationIsValidInSwift() throws {
    try Self.configuration.validate(interruptSources: [], hasPCIDevice: false)
  }

  @Test(.enabled(if: FastPathInterpreterTests.hostCompilerAvailable))
  func transferChecksTheHostRingAndConsumerRunsEachEntry() throws {
    let output = try Self.runHarness()
    #expect(output == Self.expected)
  }

  private static func runHarness() throws -> [String] {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let tables = """
      #include "SwifterKitRuntimeFastPathSchema.h"

      \(DriverExtensionGenerator.fastPathDeclarations(configuration))

      """
    try Data(tables.utf8).write(to: directory.appendingPathComponent("FastPathTables.h"))
    let harness = directory.appendingPathComponent("Harness.cpp")
    try Data(fastPathDataQueueTransferHarness.utf8).write(to: harness)
    let executable = directory.appendingPathComponent("Harness")
    let build = try runTool(
      "/usr/bin/xcrun",
      [
        "--sdk", "macosx", "clang++", "-std=c++20", "-Wall", "-Wextra", "-Werror",
        "-fno-exceptions", "-fno-rtti", "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
        "-I", checkedInNativeSources.path, "-I", directory.path, harness.path, "-o",
        executable.path,
      ],
      driverKitXcode: false
    )
    try #require(build.status == 0, Comment(rawValue: build.output))
    let run = try runTool(executable.path, [], driverKitXcode: false, timeout: hostHarnessTimeout)
    try #require(run.status == 0, Comment(rawValue: run.output))
    return run.output.split(separator: "\n").map(String.init)
  }
}

private let fastPathDataQueueTransferHarness = #"""
  #include <stdio.h>
  #include <stdlib.h>
  #include <string.h>

  #include "SwifterKitRuntimeFastPathDataQueueTransfer.h"
  #include "FastPathTables.h"

  namespace {
      constexpr SwifterKitFastPathTables kTables = {
          kSwifterKitFastPathPrograms, kSwifterKitFastPathProgramCount,
          kSwifterKitFastPathOperations, kSwifterKitFastPathOperationCount,
          kSwifterKitFastPathTriggers, kSwifterKitFastPathTriggerCount,
          kSwifterKitFastPathBARSizes, kSwifterKitFastPathBARSizeCount,
          kSwifterKitFastPathRings, kSwifterKitFastPathRingCount,
          kSwifterKitFastPathDataQueues, kSwifterKitFastPathDataQueueCount};
      const SwifterKitFastPathDataQueue& kInbound = kSwifterKitFastPathDataQueues[1];

      struct Log {
          char text[1024] = {};
          size_t length = 0;
          void Add(const char* item) {
              length += snprintf(text + length, sizeof(text) - length, "%s%s",
                  length == 0 ? "" : ",", item);
              if (length >= sizeof(text)) {
                  abort();
              }
          }
      };

      // An IODataQueueDispatchSource stand-in: a FIFO of `capacity` entries that arms
      // DataServiced when an Enqueue finds it full, as DriverKit's does.
      struct Staging {
          uint8_t data[64][32] = {};
          uint32_t sizes[64] = {};
          uint32_t head = 0;
          uint32_t count = 0;
          uint32_t capacity = 2;
          bool armed = false;
          bool quiet = false;
          Log log;

          SwifterKitFastPathStagingResult Enqueue(const uint8_t* payload, uint32_t size) {
              if (count == capacity || size > 32) {
                  armed = true;
                  log.Add("full");
                  return SwifterKitFastPathStagingResult::Full;
              }
              const uint32_t slot = (head + count) % 64;
              memcpy(data[slot], payload, size);
              sizes[slot] = size;
              count += 1;
              char item[16];
              snprintf(item, sizeof(item), "E%u", size);
              if (!quiet) {
                  log.Add(item);
              }
              return SwifterKitFastPathStagingResult::Enqueued;
          }
          bool Peek(uint64_t* words) {
              if (count == 0) {
                  return false;
              }
              SwifterKitFastPathEntryWords(data[head], sizes[head], words);
              log.Add("K");
              return true;
          }
          bool DequeueWithCoalesce(bool* sendDataServiced) {
              if (count == 0) {
                  return false;
              }
              *sendDataServiced = armed;
              armed = false;
              head = (head + 1) % 64;
              count -= 1;
              log.Add("D");
              return true;
          }
          void SendDataServiced() { log.Add("S"); }
      };

      // The program's register and ring accesses never run. Enqueue records what it queued.
      struct Access {
          uint64_t queued[2] = {};
          uint64_t Read(uint32_t, uint64_t, uint32_t) { abort(); }
          void Write(uint32_t, uint64_t, uint32_t, uint64_t) { abort(); }
          void Delay(uint32_t) { abort(); }
          uint64_t RingLoad(uint32_t, uint64_t, uint32_t) { abort(); }
          void RingStore(uint32_t, uint64_t, uint32_t, uint64_t) { abort(); }
          uint32_t RingIndex(uint32_t, uint32_t) { abort(); }
          void SetRingIndex(uint32_t, uint32_t, uint32_t) { abort(); }
          uint64_t RingDeviceAddress(uint32_t) { abort(); }
          void Enqueue(uint32_t queue, const uint64_t* values, uint32_t count) {
              if (queue != 0 || count != 2) {
                  abort();
              }
              memcpy(queued, values, sizeof(queued));
          }
          void Emit(const uint64_t*, uint32_t) { abort(); }
      };

      struct Ring {
          alignas(4096) uint8_t bytes[kSwifterKitFastPathDataQueueHeaderSize + 4096] = {};
          uint64_t Address() { return reinterpret_cast<uintptr_t>(bytes); }
          uint32_t* Field(uint32_t offset) { return reinterpret_cast<uint32_t*>(bytes + offset); }
          uint32_t& Producer() { return *Field(kSwifterKitFastPathDataQueueProducerOffset); }
          uint32_t& Consumer() { return *Field(kSwifterKitFastPathDataQueueConsumerOffset); }
          // Writes record `index` as the host does, then publishes it.
          void Write(uint32_t index, uint32_t size, uint32_t reserved, uint64_t first,
              uint64_t second = 0) {
              uint8_t* record = bytes + kSwifterKitFastPathDataQueueHeaderSize + (index % 64) * 64;
              memcpy(record, &size, 4);
              memcpy(record + 4, &reserved, 4);
              memcpy(record + 8, &first, 8);
              memcpy(record + 16, &second, 8);
              Producer() = index + 1;
          }
      };

      void Print(const char* name, const SwifterKitFastPathTransfer& transfer, Ring& ring,
          Staging& staging) {
          printf("%s moved=%u waiting=%u blocked=%d corrupt=%d consumer=%u log=%s\n", name,
              transfer.moved, transfer.waiting, transfer.blocked ? 1 : 0,
              transfer.corrupt ? 1 : 0, ring.Consumer(), staging.log.text);
          staging.log = Log();
      }

      void Consume(const char* name, Staging& staging) {
          const uint32_t program = SwifterKitFastPathTriggeredProgram(
              kTables, SwifterKitFastPathTriggerKind::DataAvailable, 1);
          SwifterKitFastPathBARSizes bars = {};
          SwifterKitFastPathOutcome outcome = {};
          Access access;
          if (!SwifterKitFastPathIsValidConfiguration(kTables, nullptr, 0, &bars)) {
              abort();
          }
          const bool ran = SwifterKitFastPathConsumeEntry(staging, [&](const uint64_t* words) {
              outcome = SwifterKitFastPathExecute(kTables, program, bars, words,
                  kTables.programs[program].argumentCount, access);
          });
          if (!ran) {
              printf("%s ran=0 log=%s\n", name, staging.log.text);
              return;
          }
          printf("%s ran=1 status=%X slots=", name, outcome.status);
          for (uint32_t slot = 0; slot < kSwifterKitFastPathSlotCount; ++slot) {
              printf("%s%llX", slot == 0 ? "" : ",",
                  static_cast<unsigned long long>(outcome.slots[slot]));
          }
          printf(" queued=%llX:%llX log=%s\n", static_cast<unsigned long long>(access.queued[0]),
              static_cast<unsigned long long>(access.queued[1]), staging.log.text);
          staging.log = Log();
      }

      template<typename Corrupt>
      void Refuse(const char* name, Corrupt corrupt) {
          Ring ring;
          Staging staging;
          corrupt(ring);
          Print(name, SwifterKitFastPathTakeHostRecords(kInbound, ring.Address(), staging), ring,
              staging);
      }
  }  // namespace

  int main() {
      Ring ring;
      Staging staging;
      ring.Write(0, 8, 0, 5);
      ring.Write(1, 24, 0, 1, 2);
      memcpy(ring.bytes + kSwifterKitFastPathDataQueueHeaderSize + 64 + 24, "\3\0\0\0\0\0\0\0", 8);
      ring.Write(2, 32, 0, 7);
      Print("take", SwifterKitFastPathTakeHostRecords(kInbound, ring.Address(), staging), ring,
          staging);
      Consume("consume", staging);
      Consume("consume", staging);
      Print("resume", SwifterKitFastPathTakeHostRecords(kInbound, ring.Address(), staging), ring,
          staging);
      Consume("consume", staging);
      Consume("empty", staging);

      uint64_t words[kSwifterKitFastPathMaximumArguments] = {9, 9, 9, 9};
      const uint8_t entry[12] = {0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0xCC, 0xBB,
          0xAA, 0x99};
      SwifterKitFastPathEntryWords(entry, sizeof(entry), words);
      printf("words %llX,%llX,%llX,%llX\n", static_cast<unsigned long long>(words[0]),
          static_cast<unsigned long long>(words[1]), static_cast<unsigned long long>(words[2]),
          static_cast<unsigned long long>(words[3]));

      Refuse("producer-ahead", [](Ring& r) { r.Producer() = 65; });
      Refuse("consumer-ahead", [](Ring& r) { r.Consumer() = 5; });
      Refuse("size-zero", [](Ring& r) { r.Write(0, 0, 0, 1); });
      Refuse("size-over", [](Ring& r) { r.Write(0, 33, 0, 1); });
      Refuse("reserved", [](Ring& r) { r.Write(0, 8, 1, 1); });
      Refuse("second-bad", [](Ring& r) {
          r.Write(0, 8, 0, 1);
          r.Write(1, 0xFFFFFFFF, 0, 1);
      });

      Ring hostile;
      Staging roomy;
      roomy.capacity = 64;
      roomy.quiet = true;
      *hostile.Field(kSwifterKitFastPathDataQueueEntryCountOffset) = 0xFFFFFFFF;
      *hostile.Field(kSwifterKitFastPathDataQueueStrideOffset) = 0x80000000;
      for (uint32_t index = 0; index < 64; ++index) {
          hostile.Write(index, 32, 0, index);
      }
      roomy.log.Add("64");
      Print("header-geometry",
          SwifterKitFastPathTakeHostRecords(kInbound, hostile.Address(), roomy), hostile, roomy);

      Ring wrapped;
      Staging next;
      wrapped.Consumer() = 0xFFFFFFFF;
      wrapped.Write(0xFFFFFFFF, 8, 0, 1);
      wrapped.Write(0, 8, 0, 2);
      Print("wrapped", SwifterKitFastPathTakeHostRecords(kInbound, wrapped.Address(), next),
          wrapped, next);
      return 0;
  }
  """#
