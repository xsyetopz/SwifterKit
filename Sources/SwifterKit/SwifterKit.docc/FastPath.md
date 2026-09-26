# Fast-path programs

Describe short register sequences that the generated extension runs natively, next to the hardware, as bounded data rather than code.

## Overview

Some device work cannot wait for a round trip to the Swift driver: acknowledging an interrupt, ringing a doorbell after a start sequence, or polling a ready bit before teardown. ``DriverConfiguration/fastPath`` declares that work as a ``FastPathConfiguration``, a list of ``FastPathProgram`` values built from a closed set of ``FastPathOp`` operations.

A fast path is data, not a transpiler. No Swift code is translated to C++. The generator validates each program and emits it as `static constexpr` tables in the generated `SwifterKitRuntimeConfiguration.h`. The opcodes, row layouts, and limits come from the same Swift schema that renders `SwifterKitRuntimeFastPathSchema.h`, so the extension reads the numbers the generator wrote.

The extension runs the tables with one fixed interpreter, `SwifterKitRuntimeFastPathInterpreter.h`. It depends on no framework, so the package's tests compile it with the host compiler and run every operation against a fake register file. The interpreter checks each table again before it runs anything: a program with a malformed row, an out-of-range BAR access, or a budget that does not add up is rejected with `kIOReturnBadArgument` before its first register access, never partway through.

## Programs and operations

Each program runs from one ``FastPathTrigger``: after the provider starts, before the service stops, in `InterruptOccurred` for one configured ``InterruptSourceConfiguration``, or when Swift runs it as a command. An interrupt trigger's ``FastPathTrigger/Delivery`` says whether the normal ``InterruptEvent`` still reaches Swift after the program.

A program works in eight 64-bit ``FastPathSlot`` values, zeroed at entry; a command program receives up to four arguments in `v0` onward. Its operations read, write, and read-modify-write a ``FastPathRegister`` in a PCI BAR, compute with wrapping 64-bit arithmetic and shifts, poll a register with a bounded iteration count, delay, skip forward on a ``FastPathCondition``, emit slot values to Swift, or fail with an `IOReturn`. There are no backward jumps, so every program terminates.

## Triggers

- term `start`: After the provider opens, and before interrupt sources are enabled, the extension re-validates every table and checks each BAR in ``FastPathConfiguration/barSizes`` with `IOPCIDevice::GetBARInfo`. When a table fails the check or a BAR is missing or smaller than declared, the whole fast path is refused with `kIOReturnNoResources`: no program runs, and interrupt events reach Swift as they would without a fast path. Otherwise the start programs run in table order; one that ends with a nonzero status refuses the fast path with that status, and the later ones do not run.
- term `stop`: The stop programs run first when the service stops, before any teardown, while the device is still open. No program runs after them.
- term `interrupt`: The source's program runs in `InterruptOccurred`, before the ``InterruptEvent`` is queued. The trigger's ``FastPathTrigger/Delivery`` then decides whether the event follows: ``FastPathTrigger/Delivery/always``, ``FastPathTrigger/Delivery/never``, or ``FastPathTrigger/Delivery/whenProgramEmits`` when the program ran an `emit`. When no program ran, because the fast path is refused or stopped or the program was rejected, the event is delivered.
- term `command`: ``DriverContext/runFastPathProgram(_:arguments:)`` checks the program index and argument count against ``FastPathLimits`` and against ``DriverContext/fastPath``, which ``DriverHost`` sets from the driver's configuration, and throws ``FastPathRuntimeError`` before sending. The extension checks them again against its tables and answers the command exactly once with a ``FastPathResult``: the program's status and its eight slots. A program that times out in a `poll` or runs `fail` still returns a result carrying that status; the call throws only when the request is refused or the fast path does not run.

An `emit` queues a ``FastPathEvent`` that ``DriverEvent/fastPath()`` decodes. It uses the extension's lossy event queue, like interrupt events: when the queue is full the event is dropped and counted. ``DriverContext/fastPathStatus()`` returns a ``FastPathStatus`` with that drop count and whether the fast path runs.

## Locking

One lock serializes every run, so the read-modify-write sequences of an interrupt program, a command, and a start or stop program never interleave. The lock is held for exactly one program: at most its 10 ms delay and poll budget plus its register accesses and emits. A command or interrupt waits at most that long for each program ahead of it. A `delay` of a whole millisecond sleeps with `IOSleep`; shorter delays and poll intervals spin in `IODelay`.

A PCI reset through ``DriverContext`` can move BARs, so the next program resolves every declared BAR again and refuses the fast path when one no longer fits.

## Rings

``FastPathConfiguration/rings`` declares up to eight ``FastPathRing`` descriptor rings that a program shares with the device. After the tables and BARs pass their checks, and before the start programs run, the extension allocates each ring as one `IOBufferMemoryDescriptor`, maps it, and prepares it for DMA with an `IODMACommand` on the PCI device. A ring the DMA preparation cannot describe as a single segment refuses the whole fast path with `kIOReturnNoResources`. The rings stay allocated until the stop programs have run, so a start program can give the device a ring's address and a stop program can quiesce it first.

``FastPathRingLayout`` describes a ring's bytes: a 64-byte header holding the little-endian 32-bit producer index at offset 0, consumer index at 4, entry size at 8, and entry count at 12, then the entries. ``FastPathOp/ringLoad(_:entry:fieldOffset:width:into:)`` and ``FastPathOp/ringStore(_:entry:fieldOffset:width:_:)`` access one aligned field of the entry whose index is in a slot, masked by the entry count, so an index never leaves the ring. ``FastPathOp/ringAdvance(_:_:by:)`` adds to an index, wrapping by the entry count. ``FastPathOperand/ringIndex(_:_:)`` reads an index, and ``FastPathOperand/ringDeviceAddress(_:_:)`` gives the low or high half of entry 0's device address to write into a device register or a descriptor.

The extension stores an index with release ordering and loads it with acquire ordering. ``DriverContext/mapRing(_:)`` maps the same buffer into the host as ``DriverSharedMemory``, so Swift reads or fills entries in place; a host that writes an index must keep it below the entry count, and the interpreter masks what it reads. The ring allocation and DMA path is compile-checked only; the host test runs the ring operations against a fake ring.

## Limits

``FastPathLimits`` bounds every configuration: at most 32 programs of at most 64 operations, polls of at most 10,000 reads with at most 1,000 µs between them, delays of at most 1,000 µs, and at most 10 ms of delay and worst-case poll waiting per program. Registers must be aligned to their width, lie inside a BAR size declared in ``FastPathConfiguration/barSizes``, and require ``DriverConfiguration/pciDevice``. Constants must fit the register they are written to. Rings need power-of-two entry sizes from 8 through 4096 bytes and counts from 2 through 65,536, unique identifiers of at most 24 bits, at most 4 MiB together with their headers, and ``DriverConfiguration/pciDevice``.

``FastPathConfiguration/validate(for:)`` enforces each rule, and ``DriverExtensionGenerator`` refuses an invalid configuration with ``DriverExtensionGenerationError/invalidFastPathConfiguration(_:)``, carrying the ``FastPathError`` that names the program and operation. A configuration is never truncated or clamped.

## Topics

### Configuration

- ``FastPathConfiguration``
- ``FastPathProgram``
- ``FastPathTrigger``
- ``FastPathLimits``
- ``FastPathError``

### Rings

- ``FastPathRing``
- ``FastPathRingLayout``
- ``FastPathRingAddressHalf``
- ``FastPathRingIndex``
- ``DriverContext/mapRing(_:)``

### Running programs

- ``DriverContext/runFastPathProgram(_:arguments:)``
- ``DriverContext/fastPathStatus()``
- ``DriverEvent/fastPath()``
- ``FastPathResult``
- ``FastPathEvent``
- ``FastPathStatus``
- ``FastPathRuntimeError``

### Operations

- ``FastPathOp``
- ``FastPathRegister``
- ``FastPathSlot``
- ``FastPathOperand``
- ``FastPathComputeOperation``
- ``FastPathCondition``
