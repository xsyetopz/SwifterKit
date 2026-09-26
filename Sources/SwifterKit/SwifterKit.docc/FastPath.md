# Fast-path programs

Describe short register sequences that the generated extension runs natively, next to the hardware, as bounded data rather than code.

## Overview

Some device work cannot wait for a round trip to the Swift driver: acknowledging an interrupt, ringing a doorbell after a start sequence, or polling a ready bit before teardown. ``DriverConfiguration/fastPath`` declares that work as a ``FastPathConfiguration``, a list of ``FastPathProgram`` values built from a closed set of ``FastPathOp`` operations.

A fast path is data, not a transpiler. No Swift code is translated to C++. The generator validates each program and emits it as `static constexpr` tables in the generated `SwifterKitRuntimeConfiguration.h`. The opcodes, row layouts, and limits come from the same Swift schema that renders `SwifterKitRuntimeFastPathSchema.h`, so the extension reads the numbers the generator wrote.

> Note: This release defines the representation, its validation, and the generated tables. The native interpreter that runs the tables, and the Swift API that runs command programs, land in the next change.

## Programs and operations

Each program runs from one ``FastPathTrigger``: after the provider starts, before the service stops, in `InterruptOccurred` for one configured ``InterruptSourceConfiguration``, or when Swift runs it as a command. An interrupt trigger's ``FastPathTrigger/Delivery`` says whether the normal ``InterruptEvent`` still reaches Swift after the program.

A program works in eight 64-bit ``FastPathSlot`` values, zeroed at entry; a command program receives up to four arguments in `v0` onward. Its operations read, write, and read-modify-write a ``FastPathRegister`` in a PCI BAR, compute with wrapping 64-bit arithmetic and shifts, poll a register with a bounded iteration count, delay, skip forward on a ``FastPathCondition``, emit slot values to Swift, or fail with an `IOReturn`. There are no backward jumps, so every program terminates.

## Limits

``FastPathLimits`` bounds every configuration: at most 32 programs of at most 64 operations, polls of at most 10,000 reads with at most 1,000 µs between them, delays of at most 1,000 µs, and at most 10 ms of delay and worst-case poll waiting per program. Registers must be aligned to their width, lie inside a BAR size declared in ``FastPathConfiguration/barSizes``, and require ``DriverConfiguration/pciDevice``. Constants must fit the register they are written to.

``FastPathConfiguration/validate(for:)`` enforces each rule, and ``DriverExtensionGenerator`` refuses an invalid configuration with ``DriverExtensionGenerationError/invalidFastPathConfiguration(_:)``, carrying the ``FastPathError`` that names the program and operation. A configuration is never truncated or clamped.

## Topics

### Configuration

- ``FastPathConfiguration``
- ``FastPathProgram``
- ``FastPathTrigger``
- ``FastPathLimits``
- ``FastPathError``

### Operations

- ``FastPathOp``
- ``FastPathRegister``
- ``FastPathSlot``
- ``FastPathOperand``
- ``FastPathComputeOperation``
- ``FastPathCondition``
