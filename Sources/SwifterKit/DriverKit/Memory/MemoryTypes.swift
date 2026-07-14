import Foundation

/// Device access permitted for a DriverKit memory descriptor.
public enum DriverMemoryDirection: UInt32, Sendable, Hashable {
  /// The device may write into the memory.
  case deviceWrites = 1
  /// The device may read from the memory.
  case deviceReads = 2
  /// The device may read and write the memory.
  case bidirectional = 3
}

/// Resource limits compiled into a generated memory-capable extension.
public struct MemoryPoolConfiguration: Sendable, Hashable {
  /// Maximum simultaneously allocated buffers.
  public let maximumBuffers: UInt32
  /// Maximum capacity of one buffer.
  public let maximumBufferSize: UInt64
  /// Maximum combined capacity of all live buffers.
  public let maximumTotalSize: UInt64

  /// Creates native memory-pool limits.
  public init(
    maximumBuffers: UInt32 = 64,
    maximumBufferSize: UInt64 = 1 << 30,
    maximumTotalSize: UInt64 = 4 << 30
  ) {
    self.maximumBuffers = maximumBuffers
    self.maximumBufferSize = maximumBufferSize
    self.maximumTotalSize = maximumTotalSize
  }
}

/// An opaque reference to a native DriverKit memory descriptor.
public struct DriverMemoryHandle: RawRepresentable, Sendable, Hashable {
  /// The encoded runtime handle.
  public let rawValue: UInt64

  /// Creates a handle from its runtime value.
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// Current metadata for an allocated DriverKit buffer.
public struct DriverMemoryInfo: Sendable, Hashable {
  /// The opaque descriptor handle.
  public let handle: DriverMemoryHandle
  /// The buffer's allocated capacity.
  public let capacity: UInt64
  /// The current valid-data length.
  public let length: UInt64
  /// The device access direction.
  public let direction: DriverMemoryDirection
  /// The requested allocation alignment.
  public let alignment: UInt32

  /// Creates buffer metadata.
  public init(
    handle: DriverMemoryHandle,
    capacity: UInt64,
    length: UInt64,
    direction: DriverMemoryDirection,
    alignment: UInt32
  ) {
    self.handle = handle
    self.capacity = capacity
    self.length = length
    self.direction = direction
    self.alignment = alignment
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 32,
      let direction = DriverMemoryDirection(rawValue: try runtimePayload.readRuntimeInteger(at: 24))
    else { throw DriverMemoryError.invalidPayload }
    self.init(
      handle: DriverMemoryHandle(rawValue: try runtimePayload.readRuntimeInteger(at: 0)),
      capacity: try runtimePayload.readRuntimeInteger(at: 8),
      length: try runtimePayload.readRuntimeInteger(at: 16),
      direction: direction,
      alignment: try runtimePayload.readRuntimeInteger(at: 28)
    )
  }
}

/// One device-visible address range returned by a DMA preparation.
public struct DriverDMASegment: Sendable, Hashable {
  /// The device-visible address.
  public let address: UInt64
  /// The contiguous segment length.
  public let length: UInt64

  /// Creates a DMA address segment.
  public init(address: UInt64, length: UInt64) {
    self.address = address
    self.length = length
  }
}

/// A prepared DMA mapping owned by the native runtime.
public struct DriverDMAMapping: Sendable, Hashable {
  /// Direction flags returned by DriverKit.
  public let flags: UInt64
  /// Device-visible address segments.
  public let segments: [DriverDMASegment]

  /// Creates prepared DMA metadata.
  public init(flags: UInt64, segments: [DriverDMASegment]) {
    self.flags = flags
    self.segments = segments
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 16 else { throw DriverMemoryError.invalidPayload }
    let flags: UInt64 = try runtimePayload.readRuntimeInteger(at: 0)
    let count = Int(try runtimePayload.readRuntimeInteger(at: 8) as UInt32)
    guard try runtimePayload.readRuntimeInteger(at: 12) as UInt32 == 0, count <= 32,
      runtimePayload.count == 16 + count * 16
    else { throw DriverMemoryError.invalidPayload }

    var segments: [DriverDMASegment] = []
    segments.reserveCapacity(count)
    for index in 0..<count {
      let offset = 16 + index * 16
      segments.append(
        DriverDMASegment(
          address: try runtimePayload.readRuntimeInteger(at: offset),
          length: try runtimePayload.readRuntimeInteger(at: offset + 8)
        )
      )
    }
    self.init(flags: flags, segments: segments)
  }
}

/// A memory operation that cannot be encoded or decoded safely.
public enum DriverMemoryError: Error, Sendable, Equatable {
  /// Capacity or length is zero or exceeds another configured bound.
  case invalidSize
  /// The requested alignment is not zero or a power of two.
  case invalidAlignment
  /// The supplied handle is invalid.
  case invalidHandle
  /// An offset and length overflow or exceed the buffer.
  case invalidRange
  /// One runtime transaction exceeds the wire transfer limit.
  case transferTooLarge
  /// DMA address width must be between one and 64 bits.
  case invalidAddressBits
  /// The native runtime returned malformed memory metadata.
  case invalidPayload
}
