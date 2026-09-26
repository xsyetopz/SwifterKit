#ifndef SwifterKitRuntimeFastPathInterpreter_h
#define SwifterKitRuntimeFastPathInterpreter_h

#include <stdint.h>

#include "SwifterKitRuntimeFastPathSchema.h"

// The fixed fast-path interpreter. It depends on no framework, so the package's host test
// compiles it with the host compiler and runs it against a fake register file.
//
// The generator validates every table in Swift; the interpreter validates them again ("validate
// on both sides"). SwifterKitFastPathExecute checks every row of a program before the first row
// runs, so a malformed row is rejected with no register access at all, never partway through.
// Every loop is bounded: a program has at most kSwifterKitFastPathMaximumOperations rows, skips
// only move forward, and a poll makes at most kSwifterKitFastPathMaximumPollIterations reads.
//
// Execute reaches the device only through `Access`, a type with these members:
//   uint64_t Read(uint32_t bar, uint64_t offset, uint32_t width);
//   void Write(uint32_t bar, uint64_t offset, uint32_t width, uint64_t value);
//   void Delay(uint32_t microseconds);
//   void Emit(const uint64_t* values, uint32_t count);
// `bar` is a BAR index below kSwifterKitFastPathBARCount, `width` is 1, 2, 4, or 8 bytes, and the
// access lies inside the BAR's declared minimum size.

static_assert((kSwifterKitFastPathSlotCount & (kSwifterKitFastPathSlotCount - 1)) == 0);

// The generated tables a run reads, with their element counts.
struct SwifterKitFastPathTables {
    const SwifterKitFastPathProgram* programs;
    uint32_t programCount;
    const SwifterKitFastPathOperation* operations;
    uint32_t operationCount;
    const SwifterKitFastPathTrigger* triggers;
    uint32_t triggerCount;
    const SwifterKitFastPathBAR* bars;
    uint32_t barCount;
};

// The declared minimum size of each BAR; zero means the BAR is not declared.
struct SwifterKitFastPathBARSizes {
    uint64_t sizes[kSwifterKitFastPathBARCount];
};

// How one run ended: a SwifterKitFastPathStatus value or a fail row's status, whether an emit
// row ran, and the slots when the program ended.
struct SwifterKitFastPathOutcome {
    uint32_t status;
    bool emitted;
    uint64_t slots[kSwifterKitFastPathSlotCount];
};

inline constexpr uint32_t SwifterKitFastPathStatusCode(SwifterKitFastPathStatus status) {
    return static_cast<uint32_t>(status);
}

inline constexpr uint64_t SwifterKitFastPathWidthMask(uint32_t width) {
    return width >= 8 ? UINT64_MAX : (uint64_t {1} << (uint64_t {width} * 8)) - 1;
}

// Keeps a validated slot index inside the slot array.
inline constexpr uint32_t SwifterKitFastPathSlot(uint64_t index) {
    return static_cast<uint32_t>(index) & (kSwifterKitFastPathSlotCount - 1);
}

// Fills `sizes` from the BAR table: each BAR at most once, below the BAR count, reserved zero,
// and with a nonzero size.
inline bool SwifterKitFastPathLoadBARSizes(
    const SwifterKitFastPathTables& tables,
    SwifterKitFastPathBARSizes* sizes) {
    *sizes = {};
    if (tables.barCount > kSwifterKitFastPathBARCount) {
        return false;
    }
    for (uint32_t index = 0; index < tables.barCount; ++index) {
        const SwifterKitFastPathBAR& bar = tables.bars[index];
        if (bar.bar >= kSwifterKitFastPathBARCount || bar.reserved != 0 || bar.minimumSize == 0
            || sizes->sizes[bar.bar] != 0) {
            return false;
        }
        sizes->sizes[bar.bar] = bar.minimumSize;
    }
    return true;
}

namespace swifterkit_fast_path {
    // A register packed as `bar | widthBytes << 8` in `a`, at the offset in `immediate0`.
    inline bool IsValidRegister(
        const SwifterKitFastPathOperation& row,
        const SwifterKitFastPathBARSizes& bars) {
        const uint32_t bar = row.a & 0xFF;
        const uint32_t width = (row.a >> 8) & 0xFF;
        if ((row.a >> 16) != 0 || bar >= kSwifterKitFastPathBARCount
            || (width != 1 && width != 2 && width != 4 && width != 8)) {
            return false;
        }
        const uint64_t size = bars.sizes[bar];
        return size >= width && row.immediate0 % width == 0 && row.immediate0 <= size - width;
    }

    inline uint64_t RegisterMask(const SwifterKitFastPathOperation& row) {
        return SwifterKitFastPathWidthMask((row.a >> 8) & 0xFF);
    }

    inline bool IsValidOperand(uint32_t kind, uint64_t value, uint64_t constantLimit) {
        switch (static_cast<SwifterKitFastPathOperandKind>(kind)) {
            case SwifterKitFastPathOperandKind::Constant:
                return value <= constantLimit;
            case SwifterKitFastPathOperandKind::Value:
                return value < kSwifterKitFastPathSlotCount;
        }
        return false;
    }

    inline bool IsValidCompute(const SwifterKitFastPathOperation& row) {
        const auto operation = static_cast<SwifterKitFastPathComputeOperation>(row.b);
        const bool shift = operation == SwifterKitFastPathComputeOperation::ShiftLeft
                           || operation == SwifterKitFastPathComputeOperation::ShiftRight;
        if (row.a >= kSwifterKitFastPathSlotCount || row.b == 0
            || row.b > static_cast<uint32_t>(SwifterKitFastPathComputeOperation::Subtract)
            || row.immediate0 != 0 || row.immediate2 != 0) {
            return false;
        }
        return IsValidOperand(
            row.c,
            row.immediate1,
            shift ? kSwifterKitFastPathShiftLimit - 1 : UINT64_MAX);
    }

    inline bool IsValidPoll(
        const SwifterKitFastPathOperation& row,
        const SwifterKitFastPathBARSizes& bars,
        uint64_t* budget) {
        if (!IsValidRegister(row, bars) || row.b == 0
            || row.b > kSwifterKitFastPathMaximumPollIterations
            || row.c > kSwifterKitFastPathMaximumPollIntervalMicroseconds) {
            return false;
        }
        const uint64_t mask = RegisterMask(row);
        *budget += uint64_t {row.b} * uint64_t {row.c};
        return row.immediate1 <= mask && row.immediate2 <= mask
               && (row.immediate2 & ~row.immediate1) == 0;
    }

    // An emit row names `b` slots, one per byte of `immediate1` from the lowest; higher bytes
    // are zero.
    inline bool IsValidEmit(const SwifterKitFastPathOperation& row) {
        if (row.a != 0 || row.c != 0 || row.b == 0 || row.b > kSwifterKitFastPathSlotCount
            || row.immediate0 != 0 || row.immediate2 != 0) {
            return false;
        }
        for (uint32_t index = 0; index < kSwifterKitFastPathSlotCount; ++index) {
            const uint64_t slot = (row.immediate1 >> (uint64_t {index} * 8)) & 0xFF;
            if (index < row.b ? slot >= kSwifterKitFastPathSlotCount : slot != 0) {
                return false;
            }
        }
        return true;
    }

    // Checks one row against its opcode's field use (unused fields are zero) and adds its
    // waiting time to `budget`. `remaining` is the number of rows after this one.
    inline bool IsValidOperation(
        const SwifterKitFastPathOperation& row,
        uint32_t remaining,
        const SwifterKitFastPathBARSizes& bars,
        uint64_t* budget) {
        switch (static_cast<SwifterKitFastPathOpcode>(row.opcode)) {
            case SwifterKitFastPathOpcode::Read:
                return IsValidRegister(row, bars) && row.b < kSwifterKitFastPathSlotCount
                       && row.c == 0 && row.immediate1 == 0 && row.immediate2 == 0;
            case SwifterKitFastPathOpcode::Write:
                return IsValidRegister(row, bars) && row.b == 0 && row.immediate2 == 0
                       && IsValidOperand(row.c, row.immediate1, RegisterMask(row));
            case SwifterKitFastPathOpcode::Modify:
                return IsValidRegister(row, bars) && row.b == 0 && row.c == 0
                       && row.immediate1 <= RegisterMask(row)
                       && row.immediate2 <= RegisterMask(row);
            case SwifterKitFastPathOpcode::Compute:
                return IsValidCompute(row);
            case SwifterKitFastPathOpcode::Poll:
                return IsValidPoll(row, bars, budget);
            case SwifterKitFastPathOpcode::Delay:
                *budget += row.b;
                return row.a == 0 && row.b != 0
                       && row.b <= kSwifterKitFastPathMaximumDelayMicroseconds && row.c == 0
                       && row.immediate0 == 0 && row.immediate1 == 0 && row.immediate2 == 0;
            case SwifterKitFastPathOpcode::Skip:
                return row.a < kSwifterKitFastPathSlotCount && row.b != 0 && row.b <= remaining
                       && row.c <= static_cast<uint32_t>(SwifterKitFastPathConditionTest::Nonzero)
                       && row.immediate0 == 0 && row.immediate2 == 0;
            case SwifterKitFastPathOpcode::Emit:
                return IsValidEmit(row);
            case SwifterKitFastPathOpcode::Fail:
                return row.a == 0 && row.b != 0 && row.c == 0 && row.immediate0 == 0
                       && row.immediate1 == 0 && row.immediate2 == 0;
        }
        return false;
    }

    inline uint64_t Operand(uint32_t kind, uint64_t value, const uint64_t* slots) {
        return kind == static_cast<uint32_t>(SwifterKitFastPathOperandKind::Value)
                   ? slots[SwifterKitFastPathSlot(value)]
                   : value;
    }

    // Wrapping arithmetic; a slot shift distance uses its low six bits.
    inline uint64_t Compute(uint32_t operation, uint64_t value, uint64_t operand) {
        const uint64_t distance = operand & (kSwifterKitFastPathShiftLimit - 1);
        switch (static_cast<SwifterKitFastPathComputeOperation>(operation)) {
            case SwifterKitFastPathComputeOperation::And:
                return value & operand;
            case SwifterKitFastPathComputeOperation::Or:
                return value | operand;
            case SwifterKitFastPathComputeOperation::Xor:
                return value ^ operand;
            case SwifterKitFastPathComputeOperation::ShiftLeft:
                return value << distance;
            case SwifterKitFastPathComputeOperation::ShiftRight:
                return value >> distance;
            case SwifterKitFastPathComputeOperation::Add:
                return value + operand;
            case SwifterKitFastPathComputeOperation::Subtract:
                return value - operand;
        }
        return value;
    }
}  // namespace swifterkit_fast_path

// Checks a program row and every operation row it names: the run lies inside the operation
// table, the counts are within the schema limits, each row is valid, and the waiting time is
// within the budget and matches the program row.
inline bool SwifterKitFastPathIsValidProgram(
    const SwifterKitFastPathTables& tables,
    uint32_t program,
    const SwifterKitFastPathBARSizes& bars) {
    if (program >= tables.programCount
        || tables.programCount > kSwifterKitFastPathMaximumPrograms) {
        return false;
    }
    const SwifterKitFastPathProgram& row = tables.programs[program];
    if (row.operationCount == 0 || row.operationCount > kSwifterKitFastPathMaximumOperations
        || row.argumentCount > kSwifterKitFastPathMaximumArguments
        || row.operationStart > tables.operationCount
        || row.operationCount > tables.operationCount - row.operationStart) {
        return false;
    }
    uint64_t budget = 0;
    for (uint32_t index = 0; index < row.operationCount; ++index) {
        if (!swifterkit_fast_path::IsValidOperation(
                tables.operations[row.operationStart + index],
                row.operationCount - index - 1,
                bars,
                &budget)) {
            return false;
        }
    }
    return budget <= kSwifterKitFastPathMaximumDelayBudgetMicroseconds
           && budget == row.delayBudgetMicroseconds;
}

// Checks the whole configuration at start: the BAR table, one trigger per program naming that
// program, known trigger kinds, an interrupt delivery only on interrupt triggers, interrupt
// sources the extension configures and triggers at most once, arguments only on command
// programs, and every program.
inline bool SwifterKitFastPathIsValidConfiguration(
    const SwifterKitFastPathTables& tables,
    const uint32_t* interruptSources,
    uint32_t interruptSourceCount,
    SwifterKitFastPathBARSizes* bars) {
    if (!SwifterKitFastPathLoadBARSizes(tables, bars) || tables.programCount == 0
        || tables.programCount > kSwifterKitFastPathMaximumPrograms
        || tables.triggerCount != tables.programCount) {
        return false;
    }
    for (uint32_t index = 0; index < tables.triggerCount; ++index) {
        const SwifterKitFastPathTrigger& trigger = tables.triggers[index];
        const auto kind = static_cast<SwifterKitFastPathTriggerKind>(trigger.kind);
        const bool interrupt = kind == SwifterKitFastPathTriggerKind::Interrupt;
        if (trigger.program != index || trigger.kind == 0
            || trigger.kind > static_cast<uint32_t>(SwifterKitFastPathTriggerKind::Command)
            || (tables.programs[index].argumentCount != 0
                && kind != SwifterKitFastPathTriggerKind::Command)
            || !SwifterKitFastPathIsValidProgram(tables, index, *bars)) {
            return false;
        }
        if (!interrupt) {
            if (trigger.source != 0 || trigger.delivery != 0) {
                return false;
            }
            continue;
        }
        bool configured = false;
        for (uint32_t source = 0; source < interruptSourceCount; ++source) {
            configured = configured || interruptSources[source] == trigger.source;
        }
        if (!configured || trigger.delivery == 0
            || trigger.delivery
                   > static_cast<uint32_t>(SwifterKitFastPathInterruptDelivery::WhenProgramEmits)) {
            return false;
        }
        for (uint32_t earlier = 0; earlier < index; ++earlier) {
            if (tables.triggers[earlier].kind == trigger.kind
                && tables.triggers[earlier].source == trigger.source) {
                return false;
            }
        }
    }
    return true;
}

// Returns the program an interrupt source triggers, or programCount when none does.
inline uint32_t SwifterKitFastPathInterruptProgram(
    const SwifterKitFastPathTables& tables,
    uint32_t sourceIndex) {
    for (uint32_t index = 0; index < tables.triggerCount; ++index) {
        if (tables.triggers[index].kind
                == static_cast<uint32_t>(SwifterKitFastPathTriggerKind::Interrupt)
            && tables.triggers[index].source == sourceIndex) {
            return index;
        }
    }
    return tables.programCount;
}

// Whether the normal interrupt event still reaches Swift. `ran` is false when no program ran,
// because none is configured or the fast path is refused or stopped; the event is then
// delivered as it is without a fast path.
inline bool SwifterKitFastPathDeliversInterrupt(uint32_t delivery, bool ran, bool emitted) {
    if (!ran) {
        return true;
    }
    switch (static_cast<SwifterKitFastPathInterruptDelivery>(delivery)) {
        case SwifterKitFastPathInterruptDelivery::Always:
            return true;
        case SwifterKitFastPathInterruptDelivery::Never:
            return false;
        case SwifterKitFastPathInterruptDelivery::WhenProgramEmits:
            return emitted;
    }
    return true;
}

// Checks a command request: the program exists, a command trigger runs it, and the argument
// count matches its declaration.
inline bool SwifterKitFastPathIsCommand(
    const SwifterKitFastPathTables& tables,
    uint32_t program,
    uint32_t argumentCount) {
    return program < tables.programCount && program < tables.triggerCount
           && tables.triggers[program].kind
                  == static_cast<uint32_t>(SwifterKitFastPathTriggerKind::Command)
           && tables.programs[program].argumentCount == argumentCount;
}

// Runs one program with `argumentCount` arguments in v0 onward. Every row is re-validated before
// the first one runs; a malformed program or an argument count that differs from the program's
// declaration ends with Rejected and no access.
template<typename Access>
SwifterKitFastPathOutcome SwifterKitFastPathExecute(
    const SwifterKitFastPathTables& tables,
    uint32_t program,
    const SwifterKitFastPathBARSizes& bars,
    const uint64_t* arguments,
    uint32_t argumentCount,
    Access& access) {
    SwifterKitFastPathOutcome outcome = {};
    outcome.status = SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Rejected);
    if (!SwifterKitFastPathIsValidProgram(tables, program, bars)
        || tables.programs[program].argumentCount != argumentCount
        || (argumentCount != 0 && arguments == nullptr)) {
        return outcome;
    }
    const SwifterKitFastPathProgram& row = tables.programs[program];
    for (uint32_t index = 0; index < argumentCount && index < kSwifterKitFastPathMaximumArguments;
         ++index) {
        outcome.slots[index] = arguments[index];
    }
    outcome.status = SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Success);
    uint64_t* const slots = outcome.slots;
    uint32_t index = 0;
    while (index < row.operationCount) {
        const SwifterKitFastPathOperation& operation =
            tables.operations[row.operationStart + index];
        const uint32_t bar = operation.a & 0xFF;
        const uint32_t width = (operation.a >> 8) & 0xFF;
        const uint64_t mask = SwifterKitFastPathWidthMask(width);
        index += 1;
        switch (static_cast<SwifterKitFastPathOpcode>(operation.opcode)) {
            case SwifterKitFastPathOpcode::Read:
                slots[SwifterKitFastPathSlot(operation.b)] =
                    access.Read(bar, operation.immediate0, width) & mask;
                break;
            case SwifterKitFastPathOpcode::Write:
                access.Write(
                    bar,
                    operation.immediate0,
                    width,
                    swifterkit_fast_path::Operand(operation.c, operation.immediate1, slots) & mask);
                break;
            case SwifterKitFastPathOpcode::Modify: {
                const uint64_t value = access.Read(bar, operation.immediate0, width);
                access.Write(
                    bar,
                    operation.immediate0,
                    width,
                    ((value & ~operation.immediate1) | operation.immediate2) & mask);
                break;
            }
            case SwifterKitFastPathOpcode::Compute: {
                uint64_t& value = slots[SwifterKitFastPathSlot(operation.a)];
                value = swifterkit_fast_path::Compute(
                    operation.b,
                    value,
                    swifterkit_fast_path::Operand(operation.c, operation.immediate1, slots));
                break;
            }
            case SwifterKitFastPathOpcode::Poll: {
                // At most `b` reads, with the interval between two reads.
                bool matched = false;
                for (uint32_t read = 0; read < operation.b && !matched; ++read) {
                    if (read != 0 && operation.c != 0) {
                        access.Delay(operation.c);
                    }
                    matched = (access.Read(bar, operation.immediate0, width) & operation.immediate1)
                              == operation.immediate2;
                }
                if (!matched) {
                    outcome.status =
                        SwifterKitFastPathStatusCode(SwifterKitFastPathStatus::Timeout);
                    return outcome;
                }
                break;
            }
            case SwifterKitFastPathOpcode::Delay:
                access.Delay(operation.b);
                break;
            case SwifterKitFastPathOpcode::Skip: {
                const bool zero =
                    (slots[SwifterKitFastPathSlot(operation.a)] & operation.immediate1) == 0;
                const bool nonzero =
                    operation.c == static_cast<uint32_t>(SwifterKitFastPathConditionTest::Nonzero);
                if (zero != nonzero) {
                    index += operation.b;
                }
                break;
            }
            case SwifterKitFastPathOpcode::Emit: {
                uint64_t values[kSwifterKitFastPathSlotCount] = {};
                for (uint32_t slot = 0; slot < operation.b && slot < kSwifterKitFastPathSlotCount;
                     ++slot) {
                    values[slot] = slots[SwifterKitFastPathSlot(
                        operation.immediate1 >> (uint64_t {slot} * 8))];
                }
                access.Emit(values, operation.b);
                outcome.emitted = true;
                break;
            }
            case SwifterKitFastPathOpcode::Fail:
                outcome.status = operation.b;
                return outcome;
        }
    }
    return outcome;
}

#endif
