import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverEventSequenceTests {
  private static let first = DriverEvent(type: 1, payload: [1])
  private static let second = DriverEvent(type: 2, payload: [2])
  private static let third = DriverEvent(type: 3, payload: [3])

  @Test
  func drainsQueuedEventsAfterOneNotification() async throws {
    let source = EventSourceConnection()
    let runtime = try await makeRuntime(source)
    let events = try await runtime.events()
    #expect(await source.registrationCount == 1)

    let delivery = Task {
      var received: [DriverEvent] = []
      for try await event in events {
        received.append(event)
        if received.count == 3 { break }
      }
      return received
    }
    #expect(await eventually { await source.emptyPollCount == 1 })
    await source.enqueue(Self.first)
    await source.enqueue(Self.second)
    await source.enqueue(Self.third)

    #expect(try await delivery.value == [Self.first, Self.second, Self.third])
    #expect(await source.notificationsSent == 1)
    await runtime.close()
  }

  @Test
  func coalescesNotificationsForEventsQueuedBeforeIteration() async throws {
    let source = EventSourceConnection()
    let runtime = try await makeRuntime(source)
    let events = try await runtime.events()
    await source.enqueue(Self.first)
    await source.enqueue(Self.second)
    await source.signal()
    await source.signal()

    var iterator = events.makeAsyncIterator()
    #expect(try await iterator.next() == Self.first)
    #expect(try await iterator.next() == Self.second)
    #expect(await source.notificationsSent == 1)
    #expect(await source.emptyPollCount == 0)

    // The buffered signals collapse into one element: one empty poll consumes it, the next waits.
    let waiting = Task { [iterator] in
      var iterator = iterator
      return try await iterator.next()
    }
    #expect(await eventually { await source.emptyPollCount == 2 })
    await source.enqueue(Self.third)
    #expect(try await waiting.value == Self.third)
    #expect(await source.emptyPollCount == 2)
    await runtime.close()
  }

  @Test
  func registersBeforeReturningAndNotifiesForAlreadyQueuedEvents() async throws {
    let source = EventSourceConnection(events: [Self.first])
    let runtime = try await makeRuntime(source)
    let events = try await runtime.events()

    #expect(await source.notificationsSent == 1)
    var iterator = events.makeAsyncIterator()
    #expect(try await iterator.next() == Self.first)
    await runtime.close()
  }

  @Test
  func eventQueuedAfterEmptyPollIsNotLost() async throws {
    let source = EventSourceConnection(events: [Self.first])
    let runtime = try await makeRuntime(source)
    let events = try await runtime.events()
    var iterator = events.makeAsyncIterator()
    #expect(try await iterator.next() == Self.first)

    // The event lands after the poll armed the extension but before the host waits.
    await source.enqueueAfterNextEmptyPoll([Self.second])
    #expect(try await iterator.next() == Self.second)
    #expect(await source.notificationsSent == 2)
    await runtime.close()
  }

  @Test
  func eventQueuedWhileDrainingIsTakenWithoutNotification() async throws {
    let source = EventSourceConnection()
    let runtime = try await makeRuntime(source)
    let events = try await runtime.events()
    await source.enqueue(Self.first)
    var iterator = events.makeAsyncIterator()
    #expect(try await iterator.next() == Self.first)

    // The queue has not been seen empty since the notification, so this enqueue stays silent.
    await source.enqueue(Self.second)
    #expect(try await iterator.next() == Self.second)
    #expect(await source.notificationsSent == 1)
    #expect(await source.emptyPollCount == 0)
    await runtime.close()
  }

  @Test
  func cancellationWhileWaitingThrowsCancellationError() async throws {
    let source = EventSourceConnection()
    let runtime = try await makeRuntime(source)
    let events = try await runtime.events()
    let delivery = Task { for try await _ in events {} }
    #expect(await eventually { await source.emptyPollCount == 1 })
    delivery.cancel()

    await #expect(throws: CancellationError.self) { try await delivery.value }
    await runtime.close()
  }

  @Test
  func closeWhileWaitingEndsTheSequence() async throws {
    let source = EventSourceConnection()
    let runtime = try await makeRuntime(source)
    let events = try await runtime.events()
    let delivery = Task {
      var count = 0
      for try await _ in events { count += 1 }
      return count
    }
    #expect(await eventually { await source.emptyPollCount == 1 })
    await runtime.close()

    #expect(try await delivery.value == 0)
    #expect(await source.closeCount == 1)
  }

  @Test
  func closeDuringDrainEndsTheSequence() async throws {
    let source = EventSourceConnection(events: [Self.first])
    let runtime = try await makeRuntime(source)
    let events = try await runtime.events()
    var iterator = events.makeAsyncIterator()
    #expect(try await iterator.next() == Self.first)

    // The connection closes after the runtime sent the poll but before the transport answered.
    await source.failNextPollAsClosed()
    #expect(try await iterator.next() == nil)
    await runtime.close()
  }

  @Test
  func secondRegistrationEndsTheFirstSequence() async throws {
    let source = EventSourceConnection()
    let runtime = try await makeRuntime(source)
    let firstEvents = try await runtime.events()
    _ = try await runtime.events()

    var iterator = firstEvents.makeAsyncIterator()
    #expect(try await iterator.next() == nil)
    #expect(await source.registrationCount == 2)
    await runtime.close()
  }

  @Test
  func eventsRequireAnOpenConnection() async throws {
    let runtime = try await makeRuntime(EventSourceConnection())
    await runtime.close()

    await #expect(throws: DriverRuntimeError.closed) { try await runtime.events() }
  }

  private func makeRuntime(_ source: EventSourceConnection) async throws -> DriverRuntimeConnection
  {
    let session = DriverSession(service: DriverService(id: 1, name: "Events"), connection: source)
    return try await DriverRuntimeConnection.connect(session: session)
  }
}
