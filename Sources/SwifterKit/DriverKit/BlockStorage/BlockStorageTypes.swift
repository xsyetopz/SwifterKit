import Foundation

/// Static properties reported by a generated block-storage extension.
public struct BlockStorageDeviceConfiguration: Sendable, Hashable {
  /// Total number of addressable logical blocks.
  public let blockCount: UInt64
  /// Bytes in one logical block.
  public let blockSize: UInt32
  /// Maximum bytes in one read or write.
  public let maximumIOSize: UInt32
  /// Maximum requests DriverKit may issue concurrently.
  public let maximumOutstandingIOCount: UInt32
  /// Maximum ranges in one unmap request.
  public let maximumUnmapRegionCount: UInt32
  /// Required byte alignment of device-visible segments.
  public let minimumSegmentAlignment: UInt32
  /// Number of device-visible DMA address bits.
  public let addressBitCount: UInt8
  /// Whether the device accepts unmap requests.
  public let supportsUnmap: Bool
  /// Whether the device supports force-unit-access operations.
  public let supportsForceUnitAccess: Bool
  /// Vendor string reported to the storage stack.
  public let vendor: String
  /// Product string reported to the storage stack.
  public let product: String
  /// Revision string reported to the storage stack.
  public let revision: String
  /// Additional device information reported to the storage stack.
  public let additionalInfo: String
  /// Whether the media can be ejected.
  public let isEjectable: Bool
  /// Whether the media can be removed.
  public let isRemovable: Bool
  /// Whether the media rejects writes.
  public let isWriteProtected: Bool

  /// Creates generated block-device metadata.
  public init(
    blockCount: UInt64,
    blockSize: UInt32,
    maximumIOSize: UInt32,
    maximumOutstandingIOCount: UInt32 = 32,
    maximumUnmapRegionCount: UInt32 = 0,
    minimumSegmentAlignment: UInt32 = 1,
    addressBitCount: UInt8 = 64,
    supportsUnmap: Bool = false,
    supportsForceUnitAccess: Bool = false,
    vendor: String,
    product: String,
    revision: String,
    additionalInfo: String = "",
    isEjectable: Bool = false,
    isRemovable: Bool = false,
    isWriteProtected: Bool = false
  ) {
    self.blockCount = blockCount
    self.blockSize = blockSize
    self.maximumIOSize = maximumIOSize
    self.maximumOutstandingIOCount = maximumOutstandingIOCount
    self.maximumUnmapRegionCount = maximumUnmapRegionCount
    self.minimumSegmentAlignment = minimumSegmentAlignment
    self.addressBitCount = addressBitCount
    self.supportsUnmap = supportsUnmap
    self.supportsForceUnitAccess = supportsForceUnitAccess
    self.vendor = vendor
    self.product = product
    self.revision = revision
    self.additionalInfo = additionalInfo
    self.isEjectable = isEjectable
    self.isRemovable = isRemovable
    self.isWriteProtected = isWriteProtected
  }
}

/// Options attached to a block read or write request.
public struct BlockStorageOptions: OptionSet, Sendable, Hashable {
  /// Encoded DriverKit option flags.
  public let rawValue: UInt32
  /// Bypasses volatile device caches for the operation.
  public static let forceUnitAccess = Self(rawValue: 1 << 0)
  /// Creates options from DriverKit flags.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// One logical block range supplied with an unmap request.
public struct BlockStorageRange: Sendable, Hashable {
  /// First logical block in the range.
  public let startBlock: UInt64
  /// Number of logical blocks in the range.
  public let blockCount: UInt64

  /// Creates a logical block range.
  public init(startBlock: UInt64, blockCount: UInt64) {
    self.startBlock = startBlock
    self.blockCount = blockCount
  }
}

/// One DMA-backed read or write request from BlockStorageDeviceDriverKit.
public struct BlockStorageIORequest: Sendable, Hashable {
  /// Opaque identifier used to complete the request.
  public let requestID: UInt32
  /// Device-visible address of the I/O buffer.
  public let dmaAddress: UInt64
  /// Number of bytes in the I/O buffer.
  public let byteCount: UInt64
  /// First logical block in the operation.
  public let startBlock: UInt64
  /// Number of logical blocks in the operation.
  public let blockCount: UInt64
  /// DriverKit storage options.
  public let options: BlockStorageOptions

  /// Creates a DMA-backed storage request.
  public init(
    requestID: UInt32,
    dmaAddress: UInt64,
    byteCount: UInt64,
    startBlock: UInt64,
    blockCount: UInt64,
    options: BlockStorageOptions = []
  ) {
    self.requestID = requestID
    self.dmaAddress = dmaAddress
    self.byteCount = byteCount
    self.startBlock = startBlock
    self.blockCount = blockCount
    self.options = options
  }
}

/// An asynchronous storage operation that Swift behavior must complete.
public enum BlockStorageRequest: Sendable, Hashable {
  /// Ejects the media and identifies the request for its completion.
  case eject(requestID: UInt32)
  /// Synchronizes the specified block range and identifies the request for its completion.
  case synchronize(requestID: UInt32, startBlock: UInt64, blockCount: UInt64)
  /// Unmaps the block ranges and identifies the request for its completion.
  case unmap(requestID: UInt32, ranges: [BlockStorageRange])
  /// Reads the blocks described by the I/O request from the device.
  case read(BlockStorageIORequest)
  /// Writes the blocks described by the I/O request to the device.
  case write(BlockStorageIORequest)

  /// Opaque identifier used by the matching completion command.
  public var requestID: UInt32 {
    switch self {
    case .eject(let requestID), .synchronize(let requestID, _, _), .unmap(let requestID, _):
      return requestID
    case .read(let request), .write(let request): return request.requestID
    }
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 8 else { throw BlockStorageRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let requestID: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let requestKind = RuntimeBlockStorageRequestKind(rawValue: kind)
    switch requestKind {
    case .eject?:
      guard runtimePayload.count == 8 else { throw BlockStorageRuntimeError.invalidPayload }
      self = .eject(requestID: requestID)
    case .synchronize?:
      guard runtimePayload.count == 24 else { throw BlockStorageRuntimeError.invalidPayload }
      self = .synchronize(
        requestID: requestID,
        startBlock: try runtimePayload.readRuntimeInteger(at: 8),
        blockCount: try runtimePayload.readRuntimeInteger(at: 16)
      )
    case .unmap?:
      guard runtimePayload.count >= 16 else { throw BlockStorageRuntimeError.invalidPayload }
      let count: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
      let expected = 16 + Int(count) * 16
      guard runtimePayload.count == expected else { throw BlockStorageRuntimeError.invalidPayload }
      var ranges: [BlockStorageRange] = []
      ranges.reserveCapacity(Int(count))
      for index in 0..<Int(count) {
        let offset = 16 + index * 16
        ranges.append(
          BlockStorageRange(
            startBlock: try runtimePayload.readRuntimeInteger(at: offset),
            blockCount: try runtimePayload.readRuntimeInteger(at: offset + 8)
          )
        )
      }
      self = .unmap(requestID: requestID, ranges: ranges)
    case .read?, .write?:
      guard runtimePayload.count == 48 else { throw BlockStorageRuntimeError.invalidPayload }
      let options = BlockStorageOptions(
        rawValue: try runtimePayload.readRuntimeInteger(at: 40) as UInt32
      )
      guard options.subtracting(.forceUnitAccess).isEmpty,
        try runtimePayload.readRuntimeInteger(at: 44) as UInt32 == 0
      else { throw BlockStorageRuntimeError.invalidPayload }
      let request = BlockStorageIORequest(
        requestID: requestID,
        dmaAddress: try runtimePayload.readRuntimeInteger(at: 8),
        byteCount: try runtimePayload.readRuntimeInteger(at: 16),
        startBlock: try runtimePayload.readRuntimeInteger(at: 24),
        blockCount: try runtimePayload.readRuntimeInteger(at: 32),
        options: options
      )
      self = requestKind == .read ? .read(request) : .write(request)
    case nil: throw BlockStorageRuntimeError.invalidRequestKind(kind)
    }
  }
}

/// A DriverKit completion status preserved as a signed kernel return code.
public struct BlockStorageCompletionStatus: RawRepresentable, Sendable, Hashable {
  /// Successful DriverKit completion.
  public static let success = Self(rawValue: 0)
  /// Signed kernel return code passed to DriverKit.
  public let rawValue: Int32
  /// Creates a status from a kernel return code.
  public init(rawValue: Int32) { self.rawValue = rawValue }
}

/// A malformed block-storage runtime event.
public enum BlockStorageRuntimeError: Error, Sendable, Equatable {
  /// The runtime payload has an invalid size or contains invalid field values.
  case invalidPayload
  /// The runtime payload contains a request kind that is not defined by the runtime schema.
  case invalidRequestKind(UInt32)
}
