import Foundation
import Testing

@testable import SwifterKit

/// Data queue declarations and `enqueue` operations against every limit.
@Suite
struct FastPathDataQueueValidationTests {
  private static func queue(
    _ id: UInt32,
    capacity: UInt32 = 4096,
    entry: UInt32 = 16,
    direction: FastPathDataQueueDirection = .toHost
  ) -> FastPathDataQueue {
    FastPathDataQueue(
      id: id,
      capacityBytes: capacity,
      maximumEntrySize: entry,
      direction: direction
    )
  }

  private static let queues = [queue(3), queue(4, direction: .toExtension)]

  private func validate(
    _ operations: [FastPathOp] = [.enqueue(3, slots: [.v0, .v1])],
    queues: [FastPathDataQueue] = queues
  ) throws(FastPathError) {
    try FastPathConfiguration(
      programs: [FastPathProgram(trigger: .command, operations: operations)],
      dataQueues: queues
    ).validate(interruptSources: [], hasPCIDevice: false)
  }

  private func refuses(
    _ operations: [FastPathOp] = [.delay(microseconds: 1)],
    queues: [FastPathDataQueue] = queues,
    with error: FastPathError,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(throws: error, sourceLocation: sourceLocation) {
      try validate(operations, queues: queues)
    }
  }

  @Test
  func acceptsQueuesWithoutAPCIDeviceAndEveryBound() throws {
    try validate()
    try validate(
      [.enqueue(0xFF_FFFF, slots: FastPathSlot.allCases)],
      queues: [
        Self.queue(0xFF_FFFF, capacity: 1_048_576, entry: 64),
        Self.queue(1, capacity: 1_048_576, entry: 8),
        Self.queue(2, capacity: 1_048_576, entry: 8, direction: .toExtension),
      ]
    )
  }

  @Test
  func refusesInvalidDeclarations() {
    let nine = (0..<UInt32(9)).map { Self.queue($0) }
    refuses(queues: nine, with: .tooManyDataQueues(count: 9))
    refuses(queues: [Self.queue(0x100_0000)], with: .invalidDataQueue(queue: 0x100_0000))
    refuses(queues: [Self.queue(1, capacity: 2048)], with: .invalidDataQueue(queue: 1))
    refuses(queues: [Self.queue(1, capacity: 2_097_152)], with: .invalidDataQueue(queue: 1))
    refuses(queues: [Self.queue(1, capacity: 6144)], with: .invalidDataQueue(queue: 1))
    refuses(queues: [Self.queue(1, entry: 0)], with: .invalidDataQueue(queue: 1))
    refuses(queues: [Self.queue(1, entry: 12)], with: .invalidDataQueue(queue: 1))
    refuses(queues: [Self.queue(1, entry: 72)], with: .invalidDataQueue(queue: 1))
    refuses(queues: [Self.queue(1), Self.queue(1)], with: .duplicateDataQueue(queue: 1))
    let large = (0..<UInt32(4)).map { Self.queue($0, capacity: 1_048_576) }
    refuses(queues: large, with: .dataQueueBytesExceeded(bytes: 4 * (1_048_576 + 64)))
  }

  @Test
  func refusesInvalidEnqueues() {
    refuses([.enqueue(9, slots: [.v0])], with: .unknownDataQueue(program: 0, operation: 0))
    refuses(
      [.delay(microseconds: 1), .enqueue(4, slots: [.v0])],
      with: .unknownDataQueue(program: 0, operation: 1)
    )
    refuses([.enqueue(3, slots: [])], with: .invalidEnqueue(program: 0, operation: 0))
    refuses([.enqueue(3, slots: [.v0, .v1, .v2])], with: .invalidEnqueue(program: 0, operation: 0))
    refuses(
      [.enqueue(3, slots: FastPathSlot.allCases + [.v0])],
      queues: [Self.queue(3, entry: 64)],
      with: .invalidEnqueue(program: 0, operation: 0)
    )
  }

  private func validate(triggers: [FastPathTrigger], argumentCount: Int = 0) throws(FastPathError) {
    try FastPathConfiguration(
      programs: triggers.map {
        FastPathProgram(
          trigger: $0,
          argumentCount: argumentCount,
          operations: [.delay(microseconds: 1)]
        )
      },
      dataQueues: Self.queues + [Self.queue(5, direction: .toExtension)]
    ).validate(interruptSources: [], hasPCIDevice: false)
  }

  @Test
  func dataAvailableTriggersNameOneToExtensionQueueEach() throws {
    try validate(triggers: [.dataAvailable(4), .dataAvailable(5)], argumentCount: 4)
    #expect(throws: FastPathError.unknownDataAvailableQueue(program: 1, queue: 9)) {
      try validate(triggers: [.dataAvailable(4), .dataAvailable(9)])
    }
    #expect(throws: FastPathError.unknownDataAvailableQueue(program: 0, queue: 3)) {
      try validate(triggers: [.dataAvailable(3)])
    }
    #expect(throws: FastPathError.duplicateDataAvailableTrigger(program: 2, queue: 4)) {
      try validate(triggers: [.dataAvailable(4), .dataAvailable(5), .dataAvailable(4)])
    }
    #expect(throws: FastPathError.invalidArgumentCount(program: 0, count: 5)) {
      try validate(triggers: [.dataAvailable(4)], argumentCount: 5)
    }
    #expect(throws: FastPathError.argumentsWithoutCommandTrigger(program: 0)) {
      try validate(triggers: [.start], argumentCount: 1)
    }
  }

  @Test
  func dataAvailableTriggerRowNamesTheQueueTableIndex() throws {
    let configuration = FastPathConfiguration(
      programs: [
        FastPathProgram(trigger: .command, operations: [.delay(microseconds: 1)]),
        FastPathProgram(
          trigger: .dataAvailable(4),
          argumentCount: 2,
          operations: [.enqueue(3, slots: [.v0, .v1])]
        ),
      ],
      dataQueues: Self.queues
    )
    try configuration.validate(interruptSources: [], hasPCIDevice: false)
    let tables = DriverExtensionGenerator.fastPathDeclarations(configuration)
    #expect(tables.contains("    {5, 1, 0, 1}"))
  }
}
