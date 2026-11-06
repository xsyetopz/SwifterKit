# Spec Delta

## Purpose

Guarantees that the SwifterKit native runtime can fill buffers it hands to a device with the bytes a driver author sent, without crashing the driver extension.

## ADDED Requirements

### Requirement: USB output transfers carry author bytes
The runtime SHALL copy the author's output bytes into the transfer buffer and submit it for USB control, pipe, and bundled pipe OUT transfers. The extension SHALL NOT fault, whatever the transfer length or endpoint type.

#### Scenario: Interrupt OUT write on first use
- **WHEN** a driver sends a 5-byte interrupt OUT transfer as its first USB write after start
- **THEN** the device receives those 5 bytes and the extension keeps running

#### Scenario: Control transfer with an OUT data stage
- **WHEN** a driver sends a control request with an OUT data stage
- **THEN** the runtime submits the data stage bytes unchanged and completes the request

#### Scenario: Bundled OUT ring reuse
- **WHEN** a driver enqueues OUT transfers on a bundled pipe ring more times than the ring has entries
- **THEN** each entry is refilled with the new bytes and no write faults

### Requirement: HID set-report buffers carry author bytes
The runtime SHALL copy set-report payloads into the report buffer it passes to the HID interface without faulting.

#### Scenario: Interface SetReport
- **WHEN** a driver sends an output or feature report through the HID interface
- **THEN** the interface receives a buffer that holds exactly the payload bytes

### Requirement: SCSI initiator-to-target data carries author bytes
The runtime SHALL copy outbound SCSI data into the data buffer without faulting.

#### Scenario: Write command
- **WHEN** a SCSI peripheral task transfers data from initiator to target
- **THEN** the data buffer holds the outbound bytes before the task is submitted

### Requirement: Author memory writes respect the requested direction
A memory write into author-allocated memory SHALL succeed for every direction the author can request. The direction reported for DMA and composition checks SHALL stay the one the author requested.

#### Scenario: Write into output memory
- **WHEN** an author allocates memory with direction `Out` and writes bytes into it
- **THEN** the write succeeds and a later read returns the same bytes

#### Scenario: Composition still narrows direction
- **WHEN** an author composes a descriptor from an `Out` source and requests `In`
- **THEN** the runtime rejects the composition as it did before this change

### Requirement: Mapped access stays within the mapped length
The runtime SHALL read or write mapped buffer memory only after confirming that the mapping covers the full offset and length. When it does not, the runtime SHALL return an error to the caller instead of touching memory.

#### Scenario: Mapping shorter than the request
- **WHEN** a buffer's mapping is shorter than the bytes a request would copy
- **THEN** the request fails with an error and the extension keeps running

#### Scenario: Offset write past the end
- **WHEN** a write names an offset and length that end past the mapped range
- **THEN** the runtime rejects it and leaves no bytes written

### Requirement: Buffer length changes are checked
The runtime SHALL treat a failed buffer length change as a failed request.

#### Scenario: Length change rejected
- **WHEN** setting a buffer's length fails
- **THEN** the runtime releases the buffer and returns that error

### Requirement: Runtime write sites are checked at test time
The test suite SHALL fail when a generated runtime source writes through a mapping of a buffer allocated only as `kIOMemoryDirectionOut`, writes without a mapped-length check, or discards a length-change result.

#### Scenario: Regression to output-only allocation
- **WHEN** a runtime write site is changed back to allocate `kIOMemoryDirectionOut`
- **THEN** `swift test` fails and names the file

#### Scenario: Regression to an unchecked mapping
- **WHEN** a runtime write site drops its mapped-length check
- **THEN** `swift test` fails and names the file
