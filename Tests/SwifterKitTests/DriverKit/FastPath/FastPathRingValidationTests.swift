import Foundation
import Testing

@testable import SwifterKit

/// Ring declarations, ring operations, and ring operands against every limit.
@Suite
struct FastPathRingValidationTests {
  private static let ring = FastPathRing(
    id: 7,
    entrySize: 16,
    entryCount: 4,
    direction: .deviceReads
  )

  private func validate(
    _ operations: [FastPathOp] = [.delay(microseconds: 1)],
    rings: [FastPathRing] = [ring],
    hasPCIDevice: Bool = true
  ) throws(FastPathError) {
    try FastPathConfiguration(
      programs: [FastPathProgram(trigger: .command, operations: operations)],
      rings: rings
    ).validate(interruptSources: [], hasPCIDevice: hasPCIDevice)
  }

  private func refuses(
    _ operations: [FastPathOp] = [.delay(microseconds: 1)],
    rings: [FastPathRing] = [ring],
    with error: FastPathError,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(throws: error, sourceLocation: sourceLocation) {
      try validate(operations, rings: rings)
    }
  }

  private func ring(_ id: UInt32, entrySize: UInt32 = 16, entryCount: UInt32 = 4) -> FastPathRing {
    FastPathRing(id: id, entrySize: entrySize, entryCount: entryCount, direction: .bidirectional)
  }

  @Test
  func acceptsEveryRingOperationAndOperand() throws {
    try validate([
      .ringStore(7, entry: .v0, fieldOffset: 8, width: .bits64, .ringDeviceAddress(7, .low)),
      .ringStore(7, entry: .v0, fieldOffset: 0, width: .bits8, .constant(0xFF)),
      .ringLoad(7, entry: .v1, fieldOffset: 12, width: .bits32, into: .v2),
      .ringAdvance(7, .consumer, by: .ringIndex(7, .producer)),
      .compute(.v3, .add, .ringIndex(7, .consumer)),
      .compute(.v4, .or, .ringDeviceAddress(7, .high)),
    ])
  }

  @Test
  func limitsRingDeclarations() {
    let eight = (0..<8).map { ring(UInt32($0)) }
    #expect(throws: Never.self) { try validate(rings: eight) }
    refuses(rings: eight + [ring(8)], with: .tooManyRings(count: 9))
    refuses(rings: [ring(1), ring(1)], with: .duplicateRing(ring: 1))
    refuses(rings: [ring(0x100_0000)], with: .invalidRing(ring: 0x100_0000))
    #expect(throws: Never.self) { try validate(rings: [ring(0xFF_FFFF)]) }
    for size: UInt32 in [0, 4, 24, 8192] {
      refuses(rings: [ring(2, entrySize: size)], with: .invalidRing(ring: 2))
    }
    for count: UInt32 in [0, 1, 3, 131_072] {
      refuses(rings: [ring(2, entryCount: count)], with: .invalidRing(ring: 2))
    }
    #expect(throws: Never.self) {
      try validate(rings: [ring(2, entrySize: 8, entryCount: 2), ring(3, entrySize: 4096)])
    }
    // 1024 entries of 4096 bytes fill the 4 MiB budget before the headers are counted.
    refuses(
      rings: [ring(4, entrySize: 4096, entryCount: 1024)],
      with: .ringBytesExceeded(bytes: 4 * 1024 * 1024 + 64)
    )
    #expect(throws: FastPathError.ringsWithoutPCIDevice) { try validate(hasPCIDevice: false) }
  }

  @Test
  func refusesUnknownRingsAndOutOfBoundsFields() {
    refuses(
      [.ringLoad(8, entry: .v0, fieldOffset: 0, width: .bits8, into: .v0)],
      with: .unknownRing(program: 0, operation: 0)
    )
    refuses(
      [.delay(microseconds: 1), .compute(.v0, .add, .ringIndex(9, .producer))],
      with: .unknownRing(program: 0, operation: 1)
    )
    refuses(
      [.ringStore(7, entry: .v0, fieldOffset: 0, width: .bits8, .ringDeviceAddress(1, .low))],
      with: .unknownRing(program: 0, operation: 0)
    )
    refuses(
      [.ringAdvance(3, .producer, by: .constant(1))],
      with: .unknownRing(program: 0, operation: 0)
    )
    refuses(
      [.ringLoad(7, entry: .v0, fieldOffset: 12, width: .bits64, into: .v0)],
      with: .ringFieldOutOfBounds(program: 0, operation: 0)
    )
    refuses(
      [.ringLoad(7, entry: .v0, fieldOffset: 16, width: .bits8, into: .v0)],
      with: .ringFieldOutOfBounds(program: 0, operation: 0)
    )
    refuses(
      [.ringStore(7, entry: .v0, fieldOffset: 2, width: .bits32, .constant(0))],
      with: .ringFieldOutOfBounds(program: 0, operation: 0)
    )
    refuses(
      [.ringStore(7, entry: .v0, fieldOffset: 0, width: .bits16, .constant(0x1_0000))],
      with: .valueExceedsWidth(program: 0, operation: 0)
    )
  }
}
