# Fast-path programs

Describe short register sequences that the generated extension runs natively, next to the hardware, as bounded data rather than code.

Fast-path programs can use DMA rings and host-shared data queues. The control plane stays in Swift. These paths have not been run on physical hardware.

## Overview

Some device work cannot wait for a round trip to the Swift driver:

- acknowledging an interrupt
- ringing a doorbell after a start sequence
- polling a ready bit before teardown

``DriverConfiguration/fastPath`` declares that work as a ``FastPathConfiguration``. The configuration is a list of ``FastPathProgram`` values built from a closed set of ``FastPathOp`` operations.

A fast path is data, not a transpiler. No Swift code is translated to C++. The generator validates each program and emits it as `static constexpr` tables in the generated `SwifterKitRuntimeConfiguration.h`. The opcodes, row layouts, and limits come from the same Swift schema that renders `SwifterKitRuntimeFastPathSchema.h`. The extension therefore reads the numbers the generator wrote.

The extension runs the tables with one fixed interpreter, `SwifterKitRuntimeFastPathInterpreter.h`. It depends on no framework. The package's tests compile it with the host compiler and run every operation against a fake register file.

The interpreter checks each table again before it runs anything. It rejects a program with `kIOReturnBadArgument` before its first register access, never partway through, when the program has:

- a malformed row
- an out-of-range BAR access
- a budget that does not add up

## Programs and operations

Each program runs from one ``FastPathTrigger``:

- after the provider starts
- before the service stops
- in `InterruptOccurred` for one configured ``InterruptSourceConfiguration``
- when Swift runs it as a command
- once per entry the host hands a to-extension data queue

An interrupt trigger's ``FastPathTrigger/Delivery`` says whether the normal ``InterruptEvent`` still reaches Swift after the program.

A program works in eight 64-bit ``FastPathSlot`` values, zeroed at entry. A command program receives up to four arguments in `v0` onward. A data-available program receives up to four words of its entry.

Its operations can:

- read, write, and read-modify-write a ``FastPathRegister`` in a PCI BAR
- compute with wrapping 64-bit arithmetic and shifts
- poll a register with a bounded iteration count
- delay
- skip forward on a ``FastPathCondition``
- emit slot values to Swift
- fail with an `IOReturn`

There are no backward jumps, so every program terminates.

## Triggers

- term `start`: The extension runs these after the provider opens and before interrupt sources are enabled. It first re-validates every table and checks each BAR in ``FastPathConfiguration/barSizes`` with `IOPCIDevice::GetBARInfo`. When a table fails the check, or a BAR is missing or smaller than declared, the extension refuses the whole fast path with `kIOReturnNoResources`. No program runs, and interrupt events reach Swift as they would without a fast path. Otherwise the start programs run in table order. One that ends with a nonzero status refuses the fast path with that status, and the later ones do not run.
- term `stop`: The stop programs run first when the service stops, before any teardown, while the device is still open. No program runs after them.
- term `interrupt`: The source's program runs in `InterruptOccurred`, before the ``InterruptEvent`` is queued. The trigger's ``FastPathTrigger/Delivery`` then decides whether the event follows: ``FastPathTrigger/Delivery/always``, ``FastPathTrigger/Delivery/never``, or ``FastPathTrigger/Delivery/whenProgramEmits`` when the program ran an `emit`. When no program ran, the event is delivered. That happens when the fast path is refused or stopped, or the program was rejected.
- term `command`: ``DriverContext/runFastPathProgram(_:arguments:)`` checks the program index and argument count before sending. It checks them against ``FastPathLimits`` and against ``DriverContext/fastPath``, which ``DriverHost`` sets from the driver's configuration. A failed check throws ``FastPathRuntimeError``. The extension checks them again against its tables. It answers the command exactly once with a ``FastPathResult``: the program's status and its eight slots. A program that times out in a `poll` or runs `fail` still returns a result carrying that status. The call throws only when the request is refused or the fast path does not run.
- term `dataAvailable`: The program runs on the extension's runtime queue once for each entry of the ``FastPathDataQueueDirection/toExtension`` queue it names. It receives the entry's first ``FastPathProgram/argumentCount`` little-endian words in `v0` onward, and zeros for words the entry does not hold. A queue has at most one such program. See Data queues below.

An `emit` queues a ``FastPathEvent`` that ``DriverEvent/fastPath()`` decodes. It uses the extension's lossy event queue, like interrupt events. When the queue is full, the event is dropped and counted. ``DriverContext/fastPathStatus()`` returns a ``FastPathStatus`` with that drop count and whether the fast path runs.

## Locking

One lock serializes every run. The read-modify-write sequences of an interrupt program, a command, and a start or stop program therefore never interleave.

- The lock is held for exactly one program: at most its 10 ms delay and poll budget, plus its register accesses and emits. A command or interrupt waits at most that long for each program ahead of it.
- Data-available programs take the lock once per entry and release it between entries. A long batch never holds it for more than one program.
- A ``DriverContext/notifyDataQueue(_:)`` doorbell holds the lock while it copies waiting records into the staging queue. It copies at most the queue's record count, at most 64 bytes each, and runs no program. The DataServiced handler that resumes a blocked queue holds the lock for the same bounded copy.
- Every data queue path takes only this lock, never while holding another.

A `delay` of a whole millisecond sleeps with `IOSleep`. Shorter delays and poll intervals spin in `IODelay`.

A PCI reset through ``DriverContext`` can move BARs. The next program therefore resolves every declared BAR again, and refuses the fast path when one no longer fits.

## Rings

``FastPathConfiguration/rings`` declares up to eight ``FastPathRing`` descriptor rings that a program shares with the device.

The extension allocates the rings after the tables and BARs pass their checks, and before the start programs run. It allocates each ring as one `IOBufferMemoryDescriptor`, maps it, and prepares it for DMA with an `IODMACommand` on the PCI device. When the DMA preparation cannot describe a ring as a single segment, the whole fast path is refused with `kIOReturnNoResources`. The rings stay allocated until the stop programs have run. A start program can therefore give the device a ring's address, and a stop program can quiesce it first.

``FastPathRingLayout`` describes a ring's bytes. A 64-byte header comes first, then the entries. The header holds these little-endian 32-bit values:

- the producer index at offset 0
- the consumer index at 4
- the entry size at 8
- the entry count at 12

Ring operations:

- ``FastPathOp/ringLoad(_:entry:fieldOffset:width:into:)`` and ``FastPathOp/ringStore(_:entry:fieldOffset:width:_:)`` access one aligned field of an entry. The entry index is in a slot, masked by the entry count, so an index never leaves the ring.
- ``FastPathOp/ringAdvance(_:_:by:)`` adds to an index, wrapping by the entry count.
- ``FastPathOperand/ringIndex(_:_:)`` reads an index.
- ``FastPathOperand/ringDeviceAddress(_:_:)`` gives the low or high half of entry 0's device address, to write into a device register or a descriptor.

The extension stores an index with release ordering and loads it with acquire ordering. ``DriverContext/mapRing(_:)`` maps the same buffer into the host as ``DriverSharedMemory``, so Swift reads or fills entries in place. A host that writes an index must keep it below the entry count. The interpreter masks what it reads.

The ring allocation and DMA path is compile-checked only. The host test runs the ring operations against a fake ring.

## Data queues

``FastPathConfiguration/dataQueues`` declares up to eight ``FastPathDataQueue`` queues. They move small entries between the extension and the host without a runtime command per entry.

`IODataQueueDispatchSource` cannot share its memory with the host, because its `CopyMemory` is private. Each queue is therefore a host ring the runtime owns: one `IOBufferMemoryDescriptor` that ``DriverContext/mapDataQueue(_:)`` maps into the host as a ``DriverDataQueue``. The extension allocates every host ring after the descriptor rings and before the start programs. It releases them after the stop programs.

### To-host queues

For a ``FastPathDataQueueDirection/toHost`` queue, ``FastPathOp/enqueue(_:slots:)`` appends one to eight slots, eight little-endian bytes each, as one entry.

1. The entry is staged in an `IODataQueueDispatchSource`. The source is sized with `GetDataQueueEntryHeaderSize` to hold one more maximum-size entry than the host ring. A source that fails its `CanEnqueueData(maximumEntrySize, entryCount)` check refuses the fast path.
2. The program checks `CanEnqueueData` and stages with `EnqueueWithCoalesce` on whatever queue ran it. The run sends one `SendDataAvailable` however many entries it staged.
3. On the runtime queue, the DataAvailable handler drains every staging source completely with `IsDataAvailable` and `Dequeue`. It publishes each entry into the host ring.
4. The handler queues one ``FastPathDataQueueEvent`` per queue that published a batch.

Enqueues are lossy like `emit`. An entry that finds the staging source or the host ring full is dropped and counted in the ring header, and the program continues. The event travels on the lossy event queue. Treat it as a hint, and read until ``DriverDataQueue/dequeueValues()`` returns nil.

### Host ring layout

``FastPathDataQueueLayout`` describes the host ring. A 64-byte header comes first, then records of ``FastPathDataQueue/recordStride`` bytes. The header holds:

- the producer and consumer counts at offsets 0 and 4
- the record count at 8
- the record stride at 12
- the maximum entry size at 16
- the direction at 20
- the 64-bit drop count at 24

The counts are free-running 32-bit values. Record `n` lives at slot `n & (entryCount - 1)`. Each record holds its payload byte count, four zero bytes, and the payload.

``DriverDataQueue`` reads a record in place and checks the header's geometry against the mapping and the declaration. It throws ``FastPathDataQueueError`` when the producer is more than the record count ahead, or when a record claims more than the maximum entry size. A corrupt index therefore never moves an access outside the ring. The extension treats a host consumer count the same way: a ring whose counts are too far apart is full.

### To-extension queues

For a ``FastPathDataQueueDirection/toExtension`` queue, the host is the producer. ``DriverDataQueue/enqueue(_:)`` or ``DriverDataQueue/enqueueValues(_:)`` appends a record. ``DriverContext/notifyDataQueue(_:)`` (opcode 0x0F02) rings the doorbell.

Under the fast-path lock, the extension checks the ring before it reads a record:

- The record count and stride come from its own tables, never from the host-writable header.
- The producer count must be at most the record count ahead of the consumer count.
- Each record's size, loaded once, must be nonzero and at most the maximum entry size. Its reserved word must be zero.

The extension moves each valid record into the queue's `IODataQueueDispatchSource` with `Enqueue`. It then advances the consumer count with release ordering. The doorbell is answered exactly once with a ``FastPathDataQueueNotification``: the entries moved, the entries still waiting, and the queue's refusal count. A ring that breaks a rule answers `kIOReturnIOError` in ``FastPathDataQueueNotification/status`` and counts a refusal. Nothing past the bad record is read.

`Enqueue` wakes the runtime queue. There the DataAvailable handler takes one entry per lock acquisition:

1. `Peek` copies the entry's first words.
2. The queue's ``FastPathTrigger/dataAvailable(_:)`` program runs on them.
3. Only then `DequeueWithCoalesce` removes the entry.

An entry that no program runs for is dropped and counted.

Host entries are never dropped for lack of space. A record that finds the staging queue full stays in the host ring, and the doorbell reports it as waiting. The failed `Enqueue` arms the source's DataServiced handler, which `SetDataServicedHandler` installed before the source was enabled. When a coalesced dequeue reports that a producer waits, the consumer calls `SendDataServiced`. The handler then moves the waiting records under the lock. It queues a ``FastPathDataQueueEvent`` whose ``FastPathDataQueueEvent/publishedEntries`` counts them, which tells the host that its ring has space again.

### Test coverage

The staging, publishing, doorbell, and DataServiced paths are compile-checked only. The package's tests run these against a fake staging queue:

- the portable reader and writer
- the interpreter's `enqueue`
- the doorbell's bounds checks
- the data-available consumer

## Limits

``FastPathLimits`` bounds every configuration.

Programs:

- At most 32 programs of at most 64 operations.
- Polls of at most 10,000 reads, with at most 1,000 µs between them.
- Delays of at most 1,000 µs.
- At most 10 ms of delay and worst-case poll waiting per program.

Registers must be aligned to their width and lie inside a BAR size declared in ``FastPathConfiguration/barSizes``. They require ``DriverConfiguration/pciDevice``. Constants must fit the register they are written to.

Rings need:

- power-of-two entry sizes from 8 through 4096 bytes
- counts from 2 through 65,536
- unique identifiers of at most 24 bits
- at most 4 MiB together with their headers
- ``DriverConfiguration/pciDevice``

Data queues need:

- unique identifiers of at most 24 bits
- power-of-two capacities from 4096 bytes through 1 MiB that hold at least two records
- maximum entry sizes that are multiples of 8 from 8 through 64 bytes
- at most 4 MiB together with their headers

An `enqueue` names a to-host queue and at most as many slots as its maximum entry size holds. A `dataAvailable` trigger names a to-extension queue that no other program names.

``FastPathConfiguration/validate(for:)`` enforces each rule. ``DriverExtensionGenerator`` refuses an invalid configuration with ``DriverExtensionGenerationError/invalidFastPathConfiguration(_:)``. The error carries the ``FastPathError`` that names the program and operation. A configuration is never truncated or clamped.

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

### Data queues

- ``FastPathDataQueue``
- ``FastPathDataQueueDirection``
- ``FastPathDataQueueLayout``
- ``FastPathDataQueueEvent``
- ``FastPathDataQueueError``
- ``DriverDataQueue``
- ``DriverContext/mapDataQueue(_:)``
- ``DriverContext/notifyDataQueue(_:)``
- ``FastPathDataQueueNotification``
- ``DriverEvent/fastPathDataQueue()``

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
