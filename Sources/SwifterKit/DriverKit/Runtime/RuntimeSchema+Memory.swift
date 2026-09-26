// Memory-pool wire constants: handle range, composition bounds, release status, and the
// client-memory type encoding that `IOConnectMapMemory64` passes to the runtime user client's
// `CopyClientMemoryForType`.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeFastPathSchema.h`, which
// `SwifterKitRuntimeProtocol.h`, `SwifterKitRuntimeMemory.cpp`, and
// `SwifterKitRuntimeClients.cpp` read, so neither side spells a value twice.

/// Bounds and payload sizes the memory commands share with the extension.
enum RuntimeMemoryLimits {
  /// The largest memory handle; handles fit the client-memory identifier field and wrap to 1.
  static let maximumHandle = UInt64(RuntimeClientMemoryType.identifierMask)
  /// The most descriptors one chain concatenates, the `CreateWithMemoryDescriptors` array size.
  static let maximumChainLength = 32
  /// The bytes of `SwifterKitMemorySubrangeHeader`: handle, offset, length, direction, reserved.
  static let subrangeHeaderSize = 32
  /// The bytes of `SwifterKitMemoryChainHeader`, which precedes the chained handles.
  static let chainHeaderSize = 8
  /// The most host address segments one wrap names, the `CreateMemoryDescriptorFromClient`
  /// array size.
  static let maximumClientSegments = 32
  /// The bytes of `SwifterKitMemoryClientHeader`, which precedes the segments.
  static let clientHeaderSize = 8
  /// The bytes of one segment: a 64-bit address and a 64-bit length, as `IOAddressSegment`.
  static let clientSegmentSize = 16
}

/// The `IOReturn` values memory commands answer with that Swift maps to a typed error. The
/// extension asserts each against its `IOReturn.h` name.
enum RuntimeMemoryStatus: UInt32, CaseIterable {
  /// A release names an entry that a subrange or chain still uses: `kIOReturnBusy`.
  case inUse = 0xE000_02D5
  /// A command or host mapping names wrapped host memory, or a subrange or chain built from it,
  /// that another user client wrapped: `kIOReturnNotPermitted`.
  case notOwner = 0xE000_02E2

  /// The status as the transport reports it in ``DriverKitError/Kind/ioReturn(_:)``.
  var ioReturn: Int32 { Int32(bitPattern: rawValue) }
}

/// What a client-memory type maps, stored in its top bits.
enum RuntimeClientMemoryKind: UInt32, CaseIterable {
  /// A runtime memory-pool entry; the identifier is its ``DriverMemoryHandle``.
  case memoryBuffer = 1
  /// A networking packet pool; the identifier is an ``EthernetPacketPool`` value.
  case packetPool = 2
  /// A fast-path ring; the identifier is its ``FastPathRing/id``.
  case ring = 3
  /// A fast-path data queue's host ring; the identifier is its ``FastPathDataQueue/id``.
  case dataQueue = 4
}

/// The 32-bit `memoryType` of `IOConnectMapMemory64`: a kind above a 24-bit identifier.
struct RuntimeClientMemoryType: Hashable, Sendable {
  /// The bit position of the kind.
  static let kindShift = 24
  /// The identifier bits below the kind.
  static let identifierMask: UInt32 = 0xFF_FFFF

  /// The encoded memory type.
  let rawValue: UInt32

  /// Encodes `identifier` under `kind`; nil when the identifier does not fit.
  init?(kind: RuntimeClientMemoryKind, identifier: UInt64) {
    guard identifier <= UInt64(Self.identifierMask) else { return nil }
    rawValue = kind.rawValue << Self.kindShift | UInt32(identifier)
  }
}

/// Networking packet pools as client-memory identifiers. The public type carries the wire values.
typealias RuntimePacketPool = EthernetPacketPool

extension RuntimeSchemaHeader {
  static func memorySections() -> [[String]] {
    let limits = RuntimeMemoryLimits.self
    return [
      joined(
        constants(
          "uint64_t",
          [("kSwifterKitMemoryMaximumHandle", hex(limits.maximumHandle, digits: 6))]
        ),
        constants(
          "uint32_t",
          [
            ("kSwifterKitMemoryMaximumChainLength", "\(limits.maximumChainLength)"),
            ("kSwifterKitMemorySubrangeHeaderSize", "\(limits.subrangeHeaderSize)"),
            ("kSwifterKitMemoryChainHeaderSize", "\(limits.chainHeaderSize)"),
            ("kSwifterKitMemoryMaximumClientSegments", "\(limits.maximumClientSegments)"),
            ("kSwifterKitMemoryClientHeaderSize", "\(limits.clientHeaderSize)"),
            ("kSwifterKitMemoryClientSegmentSize", "\(limits.clientSegmentSize)"),
            ("kSwifterKitClientMemoryKindShift", "\(RuntimeClientMemoryType.kindShift)"),
            (
              "kSwifterKitClientMemoryIdentifierMask",
              hex(RuntimeClientMemoryType.identifierMask, digits: 6)
            ),
          ]
        )
      ),
      enumeration(
        "SwifterKitMemoryStatus",
        type: "uint32_t",
        cases: RuntimeMemoryStatus.allCases.map { (nativeName($0), hex($0.rawValue, digits: 8)) }
      ),
      enumeration("SwifterKitClientMemoryKind", type: "uint32_t", RuntimeClientMemoryKind.allCases),
      enumeration("SwifterKitPacketPool", type: "uint32_t", RuntimePacketPool.allCases),
    ]
  }
}
