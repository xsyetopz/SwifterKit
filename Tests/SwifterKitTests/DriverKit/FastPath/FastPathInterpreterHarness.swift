/// A C++ harness that runs `SwifterKitRuntimeFastPathInterpreter.h` against a fake register file.
///
/// It includes `FastPathTables.h`, which the test writes from
/// ``FastPathInterpreterTests/programs`` with the generator's own table emitter, and prints one
/// transcript line per run: the status, whether an `emit` ran, the slots, and every register
/// access, delay, and emitted value in order. Rejection lines report the status and the number of
/// accesses, which must be zero because a malformed program never starts. Ring accesses log as
/// `S`/`L` (store and load at a byte offset from entry 0), `I`/`P` (index read and set), and `A`
/// (device address). A data queue `enqueue` logs as `Q` with the queue index and values.
let fastPathInterpreterHarness = #"""
  #include <stdio.h>
  #include <stdlib.h>
  #include <string.h>

  #include "SwifterKitRuntimeFastPathInterpreter.h"
  #include "FastPathTables.h"

  namespace {
      constexpr uint64_t kReadyRegister = 0x30;

      struct Fake {
          uint8_t memory[kSwifterKitFastPathBARCount][256] = {};
          uint8_t ring[64] = {};
          uint32_t indices[2] = {0x10, 0};
          uint32_t readyAfter = 0;
          uint32_t readyReads = 0;
          uint32_t accesses = 0;
          char log[4096] = {};
          size_t length = 0;

          void Check() {
              if (length >= sizeof(log)) {
                  abort();
              }
          }
          uint64_t Read(uint32_t bar, uint64_t offset, uint32_t width) {
              uint64_t value = 0;
              if (bar == 0 && offset == kReadyRegister) {
                  value = readyReads++ >= readyAfter ? 1 : 0;
              } else {
                  memcpy(&value, &memory[bar][offset], width);
              }
              accesses += 1;
              length += snprintf(log + length, sizeof(log) - length, " R%u+%llX/%u=%llX", bar,
                  static_cast<unsigned long long>(offset), width,
                  static_cast<unsigned long long>(value));
              Check();
              return value;
          }
          void Write(uint32_t bar, uint64_t offset, uint32_t width, uint64_t value) {
              memcpy(&memory[bar][offset], &value, width);
              accesses += 1;
              length += snprintf(log + length, sizeof(log) - length, " W%u+%llX/%u=%llX", bar,
                  static_cast<unsigned long long>(offset), width,
                  static_cast<unsigned long long>(value));
              Check();
          }
          void Delay(uint32_t microseconds) {
              accesses += 1;
              length += snprintf(log + length, sizeof(log) - length, " D%u", microseconds);
              Check();
          }
          void Log(const char* kind, uint32_t ring, uint64_t detail, uint32_t width,
              uint64_t value) {
              accesses += 1;
              length += snprintf(log + length, sizeof(log) - length, " %s%u%c%llX/%u=%llX", kind,
                  ring, kind[0] == 'I' || kind[0] == 'P' ? '.' : '+',
                  static_cast<unsigned long long>(detail), width,
                  static_cast<unsigned long long>(value));
              Check();
          }
          uint64_t RingLoad(uint32_t ringIndex, uint64_t offset, uint32_t width) {
              if (ringIndex != 0 || offset + width > sizeof(ring)) {
                  abort();
              }
              uint64_t value = 0;
              memcpy(&value, &ring[offset], width);
              Log("L", ringIndex, offset, width, value);
              return value;
          }
          void RingStore(uint32_t ringIndex, uint64_t offset, uint32_t width, uint64_t value) {
              if (ringIndex != 0 || offset + width > sizeof(ring)) {
                  abort();
              }
              memcpy(&ring[offset], &value, width);
              Log("S", ringIndex, offset, width, value);
          }
          uint32_t RingIndex(uint32_t ringIndex, uint32_t index) {
              Log("I", ringIndex, index, 4, indices[index & 1]);
              return indices[index & 1];
          }
          void SetRingIndex(uint32_t ringIndex, uint32_t index, uint32_t value) {
              indices[index & 1] = value;
              Log("P", ringIndex, index, 4, value);
          }
          uint64_t RingDeviceAddress(uint32_t ringIndex) {
              Log("A", ringIndex, 0, 8, 0x123456000);
              return 0x123456000;
          }
          void Enqueue(uint32_t queue, const uint64_t* values, uint32_t count) {
              accesses += 1;
              length += snprintf(log + length, sizeof(log) - length, " Q%u", queue);
              for (uint32_t index = 0; index < count; ++index) {
                  length += snprintf(log + length, sizeof(log) - length, ":%llX",
                      static_cast<unsigned long long>(values[index]));
              }
              Check();
          }
          void Emit(const uint64_t* values, uint32_t count) {
              accesses += 1;
              length += snprintf(log + length, sizeof(log) - length, " E");
              for (uint32_t index = 0; index < count; ++index) {
                  length += snprintf(log + length, sizeof(log) - length, ":%llX",
                      static_cast<unsigned long long>(values[index]));
              }
              Check();
          }
      };

      struct Tables {
          SwifterKitFastPathProgram programs[kSwifterKitFastPathProgramCount];
          SwifterKitFastPathOperation operations[kSwifterKitFastPathOperationCount];
          SwifterKitFastPathTrigger triggers[kSwifterKitFastPathTriggerCount];
          SwifterKitFastPathBAR bars[kSwifterKitFastPathBARSizeCount];
          SwifterKitFastPathRing rings[kSwifterKitFastPathRingCount];
          SwifterKitFastPathDataQueue queues[kSwifterKitFastPathDataQueueCount];
          SwifterKitFastPathTables view;

          Tables() {
              memcpy(programs, kSwifterKitFastPathPrograms, sizeof(programs));
              memcpy(operations, kSwifterKitFastPathOperations, sizeof(operations));
              memcpy(triggers, kSwifterKitFastPathTriggers, sizeof(triggers));
              memcpy(bars, kSwifterKitFastPathBARSizes, sizeof(bars));
              memcpy(rings, kSwifterKitFastPathRings, sizeof(rings));
              memcpy(queues, kSwifterKitFastPathDataQueues, sizeof(queues));
              view = {programs, kSwifterKitFastPathProgramCount, operations,
                  kSwifterKitFastPathOperationCount, triggers, kSwifterKitFastPathTriggerCount,
                  bars, kSwifterKitFastPathBARSizeCount, rings, kSwifterKitFastPathRingCount,
                  queues, kSwifterKitFastPathDataQueueCount};
          }
          SwifterKitFastPathOperation& Op(uint32_t program, uint32_t index) {
              return operations[programs[program].operationStart + index];
          }
      };

      void Run(const char* name, uint32_t program, const uint64_t* arguments, uint32_t count,
          Fake& fake) {
          const Tables tables;
          SwifterKitFastPathBARSizes bars = {};
          if (!SwifterKitFastPathLoadBARSizes(tables.view, &bars)) {
              abort();
          }
          const SwifterKitFastPathOutcome outcome =
              SwifterKitFastPathExecute(tables.view, program, bars, arguments, count, fake);
          printf("%s status=%X emitted=%d slots=", name, outcome.status, outcome.emitted ? 1 : 0);
          for (uint32_t slot = 0; slot < kSwifterKitFastPathSlotCount; ++slot) {
              printf("%s%llX", slot == 0 ? "" : ",",
                  static_cast<unsigned long long>(outcome.slots[slot]));
          }
          printf(" log=%s\n", fake.length == 0 ? "" : fake.log + 1);
      }

      template<typename Mutation>
      void Reject(const char* name, uint32_t program, uint32_t count, Mutation mutate) {
          Tables tables;
          mutate(tables);
          const uint64_t arguments[kSwifterKitFastPathMaximumArguments] = {1, 2, 3, 4};
          SwifterKitFastPathBARSizes bars = {};
          const bool loaded = SwifterKitFastPathLoadBARSizes(tables.view, &bars);
          Fake fake;
          const SwifterKitFastPathOutcome outcome =
              SwifterKitFastPathExecute(tables.view, program, bars, arguments, count, fake);
          printf("reject-%s loaded=%d executed=%d status=%X accesses=%u\n", name,
              loaded ? 1 : 0, outcome.executed ? 1 : 0, outcome.status, fake.accesses);
      }

      template<typename Mutation>
      void Configuration(const char* name, const uint32_t* sources, uint32_t count,
          Mutation mutate) {
          Tables tables;
          mutate(tables);
          SwifterKitFastPathBARSizes bars = {};
          printf("config-%s valid=%d\n", name,
              SwifterKitFastPathIsValidConfiguration(tables.view, sources, count, &bars) ? 1 : 0);
      }

      void Valid() {
          const uint64_t pair[] = {0x12345, 0x1122334455667788};
          Fake readWrite;
          readWrite.memory[0][8] = 0xEF;
          readWrite.memory[0][9] = 0xBE;
          readWrite.memory[0][10] = 0xAD;
          readWrite.memory[0][11] = 0xDE;
          Run("read-write", 0, pair, 2, readWrite);
          Fake modify;
          const uint32_t initial = 0x12345678;
          memcpy(&modify.memory[0][0x20], &initial, sizeof(initial));
          modify.memory[2][4] = 0x3C;
          Run("modify", 1, nullptr, 0, modify);
          const uint64_t operands[] = {0x1234, 0x44};
          Fake compute;
          Run("compute", 2, operands, 2, compute);
          Fake pollReady;
          pollReady.readyAfter = 2;
          Run("poll-success", 3, nullptr, 0, pollReady);
          Fake pollTimeout;
          Run("poll-timeout", 4, nullptr, 0, pollTimeout);
          Fake delay;
          Run("delay", 5, nullptr, 0, delay);
          const uint64_t clear[] = {0};
          const uint64_t set[] = {1};
          Fake skipClear;
          Run("skip-clear", 6, clear, 1, skipClear);
          Fake skipSet;
          Run("skip-set", 6, set, 1, skipSet);
          Fake emitBit;
          const uint32_t pending = 0xCAFE00FE;
          memcpy(&emitBit.memory[0][8], &pending, sizeof(pending));
          Run("emit-bit", 7, nullptr, 0, emitBit);
          Fake emitClear;
          emitClear.memory[0][9] = 0x01;
          Run("emit-clear", 7, nullptr, 0, emitClear);
          Fake fail;
          Run("fail", 8, nullptr, 0, fail);
          const uint64_t four[] = {1, 2, 3, 4};
          Fake emitAll;
          Run("emit-all", 9, four, 4, emitAll);
          const uint64_t entry[] = {5, 0xAABBCCDD};
          Fake ring;
          Run("ring", 10, entry, 2, ring);
          Fake enqueue;
          Run("enqueue", 11, pair, 2, enqueue);
      }

      void Malformed() {
          using T = Tables;
          Reject("opcode-zero", 0, 2, [](T& t) { t.Op(0, 0).opcode = 0; });
          Reject("opcode-unknown", 0, 2, [](T& t) { t.Op(0, 0).opcode = 14; });
          Reject("read-slot", 0, 2, [](T& t) { t.Op(0, 0).b = 8; });
          Reject("read-unused-c", 0, 2, [](T& t) { t.Op(0, 0).c = 1; });
          Reject("read-unused-immediate", 0, 2, [](T& t) { t.Op(0, 4).immediate2 = 1; });
          Reject("bar-undeclared", 0, 2, [](T& t) { t.Op(0, 0).a = 1 | 4 << 8; });
          Reject("bar-index", 0, 2, [](T& t) { t.Op(0, 0).a = 6 | 4 << 8; });
          Reject("width", 0, 2, [](T& t) { t.Op(0, 0).a = 3 << 8; });
          Reject("register-high-bits", 0, 2, [](T& t) { t.Op(0, 0).a |= 1 << 16; });
          Reject("misaligned", 0, 2, [](T& t) { t.Op(0, 0).immediate0 = 9; });
          Reject("out-of-bounds", 0, 2, [](T& t) { t.Op(0, 0).immediate0 = 0x100; });
          Reject("end-of-bar", 0, 2, [](T& t) { t.Op(0, 3).immediate0 = 0xFC; });
          Reject("write-wide-constant", 0, 2, [](T& t) { t.Op(0, 2).immediate1 = 0x1AB; });
          Reject("write-operand-kind", 0, 2, [](T& t) { t.Op(0, 1).c = 4; });
          Reject("write-slot", 0, 2, [](T& t) { t.Op(0, 1).immediate1 = 8; });
          Reject("write-unused", 0, 2, [](T& t) { t.Op(0, 2).b = 1; });
          Reject("budget-mismatch", 0, 2, [](T& t) { t.programs[0].delayBudgetMicroseconds = 1; });
          Reject("start-past-table", 0, 2, [](T& t) {
              t.programs[0].operationStart = kSwifterKitFastPathOperationCount - 2;
          });
          Reject("count-zero", 0, 2, [](T& t) { t.programs[0].operationCount = 0; });
          Reject("count-over-limit", 0, 2, [](T& t) { t.programs[0].operationCount = 65; });
          Reject("arguments-over-limit", 0, 5, [](T& t) { t.programs[0].argumentCount = 5; });
          Reject("argument-mismatch", 0, 1, [](T&) {});
          Reject("program-index", 99, 0, [](T&) {});
          Reject("modify-wide-mask", 1, 0, [](T& t) { t.Op(1, 2).immediate2 = 0x1F0; });
          Reject("modify-unused", 1, 0, [](T& t) { t.Op(1, 0).b = 1; });
          Reject("compute-op-zero", 2, 2, [](T& t) { t.Op(2, 0).b = 0; });
          Reject("compute-op-unknown", 2, 2, [](T& t) { t.Op(2, 0).b = 8; });
          Reject("compute-shift", 2, 2, [](T& t) { t.Op(2, 6).immediate1 = 64; });
          Reject("compute-slot", 2, 2, [](T& t) { t.Op(2, 0).a = 8; });
          Reject("compute-operand-kind", 2, 2, [](T& t) { t.Op(2, 0).c = 4; });
          Reject("compute-unused", 2, 2, [](T& t) { t.Op(2, 0).immediate0 = 1; });
          Reject("poll-iterations-zero", 3, 0, [](T& t) { t.Op(3, 0).b = 0; });
          Reject("poll-iterations-over", 3, 0, [](T& t) { t.Op(3, 0).b = 10001; });
          Reject("poll-interval", 3, 0, [](T& t) { t.Op(3, 0).c = 1001; });
          Reject("poll-outside-mask", 3, 0, [](T& t) { t.Op(3, 0).immediate2 = 2; });
          Reject("poll-wide-mask", 3, 0, [](T& t) { t.Op(3, 0).immediate1 = 0x100000001; });
          Reject("poll-budget", 3, 0, [](T& t) {
              t.Op(3, 0).b = 10000;
              t.Op(3, 0).c = 1000;
              t.programs[3].delayBudgetMicroseconds = 10000000;
          });
          Reject("delay-zero", 5, 0, [](T& t) { t.Op(5, 0).b = 0; });
          Reject("delay-over", 5, 0, [](T& t) { t.Op(5, 0).b = 1001; });
          Reject("delay-unused", 5, 0, [](T& t) { t.Op(5, 0).a = 1; });
          Reject("skip-zero", 6, 1, [](T& t) { t.Op(6, 0).b = 0; });
          Reject("skip-past-end", 6, 1, [](T& t) { t.Op(6, 2).b = 2; });
          Reject("skip-test", 6, 1, [](T& t) { t.Op(6, 0).c = 2; });
          Reject("skip-slot", 6, 1, [](T& t) { t.Op(6, 0).a = 8; });
          Reject("emit-zero", 7, 0, [](T& t) { t.Op(7, 2).b = 0; });
          Reject("emit-over", 7, 0, [](T& t) { t.Op(7, 2).b = 9; });
          Reject("emit-slot", 7, 0, [](T& t) { t.Op(7, 2).immediate1 = 8; });
          Reject("emit-extra-byte", 7, 0, [](T& t) { t.Op(7, 4).immediate1 |= 1 << 8; });
          Reject("emit-unused", 7, 0, [](T& t) { t.Op(7, 2).a = 1; });
          Reject("fail-zero", 8, 0, [](T& t) { t.Op(8, 1).b = 0; });
          Reject("fail-unused", 8, 0, [](T& t) { t.Op(8, 1).immediate0 = 1; });
          Reject("bar-smaller", 6, 1, [](T& t) { t.bars[1].minimumSize = 8; });
          Reject("bar-missing", 0, 2, [](T& t) { t.view.barCount = 1; });
          Reject("ring-index", 10, 2, [](T& t) { t.Op(10, 0).a = 1 | 4 << 8; });
          Reject("ring-width", 10, 2, [](T& t) { t.Op(10, 0).a = 3 << 8; });
          Reject("ring-field-bounds", 10, 2, [](T& t) { t.Op(10, 0).immediate0 = 16; });
          Reject("ring-field-misaligned", 10, 2, [](T& t) { t.Op(10, 0).immediate0 = 2; });
          Reject("ring-entry-slot", 10, 2, [](T& t) { t.Op(10, 0).b = 8; });
          Reject("ring-store-wide-constant", 10, 2, [](T& t) {
              t.Op(10, 0).c = 0;
              t.Op(10, 0).immediate1 = 0x100000000;
          });
          Reject("ring-load-slot", 10, 2, [](T& t) { t.Op(10, 1).c = 8; });
          Reject("ring-load-unused", 10, 2, [](T& t) { t.Op(10, 1).immediate1 = 1; });
          Reject("ring-advance-index", 10, 2, [](T& t) { t.Op(10, 2).b = 2; });
          Reject("ring-advance-ring", 10, 2, [](T& t) { t.Op(10, 2).a = 1; });
          Reject("ring-operand-ring", 10, 2, [](T& t) { t.Op(10, 4).immediate1 = 1; });
          Reject("ring-operand-selector", 10, 2, [](T& t) { t.Op(10, 4).immediate1 = 2 << 8; });
          Reject("ring-entry-size", 10, 2, [](T& t) { t.rings[0].entrySize = 24; });
          Reject("ring-entry-count", 10, 2, [](T& t) { t.rings[0].entryCount = 131072; });
          Reject("ring-bytes", 10, 2, [](T& t) {
              t.rings[0].entrySize = 4096;
              t.rings[0].entryCount = 2048;
          });
          Reject("ring-direction", 10, 2, [](T& t) { t.rings[0].direction = 4; });
          Reject("ring-identifier", 10, 2, [](T& t) { t.rings[0].id = 0x1000000; });
          Reject("ring-missing", 10, 2, [](T& t) { t.view.ringCount = 0; });
          Reject("enqueue-queue", 11, 2, [](T& t) { t.Op(11, 0).a = 2; });
          Reject("enqueue-to-extension", 11, 2, [](T& t) { t.Op(11, 0).a = 1; });
          Reject("enqueue-too-wide", 11, 2, [](T& t) { t.Op(11, 0).b = 3; });
          Reject("enqueue-zero", 11, 2, [](T& t) { t.Op(11, 1).b = 0; });
          Reject("enqueue-slot", 11, 2, [](T& t) { t.Op(11, 1).immediate1 = 8; });
          Reject("enqueue-unused", 11, 2, [](T& t) { t.Op(11, 1).c = 1; });
          Reject("queue-capacity", 11, 2, [](T& t) { t.queues[0].capacityBytes = 6144; });
          Reject("queue-entry-size", 11, 2, [](T& t) { t.queues[0].maximumEntrySize = 12; });
          Reject("queue-entry-over", 11, 2, [](T& t) { t.queues[0].maximumEntrySize = 72; });
          Reject("queue-direction", 11, 2, [](T& t) { t.queues[1].direction = 2; });
          Reject("queue-identifier", 11, 2, [](T& t) { t.queues[0].id = 0x1000000; });
          Reject("queue-duplicate", 11, 2, [](T& t) { t.queues[1].id = 3; });
          Reject("queue-missing", 11, 2, [](T& t) { t.view.dataQueueCount = 0; });
      }

      void Configurations() {
          using T = Tables;
          const uint32_t three[] = {3};
          const uint32_t five[] = {5};
          Configuration("valid", three, 1, [](T&) {});
          Configuration("no-source", nullptr, 0, [](T&) {});
          Configuration("wrong-source", five, 1, [](T&) {});
          Configuration("delivery-zero", three, 1, [](T& t) { t.triggers[7].delivery = 0; });
          Configuration("delivery-unknown", three, 1, [](T& t) { t.triggers[7].delivery = 4; });
          Configuration("delivery-on-command", three, 1, [](T& t) { t.triggers[0].delivery = 1; });
          Configuration("source-on-start", three, 1, [](T& t) { t.triggers[5].source = 1; });
          Configuration("kind-zero", three, 1, [](T& t) { t.triggers[5].kind = 0; });
          Configuration("kind-unknown", three, 1, [](T& t) { t.triggers[5].kind = 6; });
          Configuration("program-mismatch", three, 1, [](T& t) { t.triggers[1].program = 0; });
          Configuration("duplicate-interrupt", three, 1, [](T& t) {
              t.triggers[4].kind = 3;
              t.triggers[4].source = 3;
              t.triggers[4].delivery = 1;
          });
          Configuration("arguments-on-start", three, 1, [](T& t) {
              t.programs[5].argumentCount = 1;
          });
          Configuration("trigger-count", three, 1, [](T& t) { t.view.triggerCount -= 1; });
          Configuration("bar-duplicate", three, 1, [](T& t) { t.bars[1].bar = 0; });
          Configuration("bar-zero-size", three, 1, [](T& t) { t.bars[1].minimumSize = 0; });
          Configuration("bar-index", three, 1, [](T& t) { t.bars[1].bar = 6; });
          Configuration("bar-reserved", three, 1, [](T& t) { t.bars[1].reserved = 1; });
          Configuration("malformed-row", three, 1, [](T& t) { t.Op(9, 0).b = 0; });
      }

      void Dispatch() {
          const Tables tables;
          printf("interrupt-program source3=%u source4=%u count=%u\n",
              SwifterKitFastPathInterruptProgram(tables.view, 3),
              SwifterKitFastPathInterruptProgram(tables.view, 4), tables.view.programCount);
          printf("deliver always=%d never=%d emitted=%d silent=%d not-run=%d unknown=%d\n",
              SwifterKitFastPathDeliversInterrupt(1, true, false) ? 1 : 0,
              SwifterKitFastPathDeliversInterrupt(2, true, true) ? 1 : 0,
              SwifterKitFastPathDeliversInterrupt(3, true, true) ? 1 : 0,
              SwifterKitFastPathDeliversInterrupt(3, true, false) ? 1 : 0,
              SwifterKitFastPathDeliversInterrupt(2, false, false) ? 1 : 0,
              SwifterKitFastPathDeliversInterrupt(0, true, false) ? 1 : 0);
          printf("command matching=%d count=%d start=%d interrupt=%d missing=%d\n",
              SwifterKitFastPathIsCommand(tables.view, 0, 2) ? 1 : 0,
              SwifterKitFastPathIsCommand(tables.view, 0, 1) ? 1 : 0,
              SwifterKitFastPathIsCommand(tables.view, 5, 0) ? 1 : 0,
              SwifterKitFastPathIsCommand(tables.view, 7, 0) ? 1 : 0,
              SwifterKitFastPathIsCommand(tables.view, 99, 0) ? 1 : 0);
      }
  }  // namespace

  int main() {
      Valid();
      Malformed();
      Configurations();
      Dispatch();
      return 0;
  }
  """#
