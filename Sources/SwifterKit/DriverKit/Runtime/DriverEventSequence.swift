/// Events from the internal DriverKit runtime, delivered as the extension reports them.
///
/// Create a sequence with ``DriverRuntimeConnection/events()``. Iteration takes queued events
/// until the extension's queue is empty, then waits for the extension's notification that more
/// events are pending; it never sleeps and polls. Notifications that arrive while events are being
/// taken coalesce into one more pass over the queue, so an event queued at any point is delivered.
///
/// The sequence ends when the connection closes or a later ``DriverRuntimeConnection/events()``
/// call replaces its registration. Iteration throws `CancellationError` when the iterating task is
/// cancelled, and rethrows other transport and protocol errors.
public struct DriverEventSequence: AsyncSequence, Sendable {
  /// The element type.
  public typealias Element = DriverEvent

  private let runtime: DriverRuntimeConnection
  private let notifications: AsyncStream<Void>

  init(runtime: DriverRuntimeConnection, notifications: AsyncStream<Void>) {
    self.runtime = runtime
    self.notifications = notifications
  }

  /// Creates an iterator. Iterate a sequence from one task at a time.
  public func makeAsyncIterator() -> Iterator {
    Iterator(runtime: runtime, notifications: notifications.makeAsyncIterator())
  }

  /// Takes events until the queue is empty, then waits for a notification.
  public struct Iterator: AsyncIteratorProtocol {
    private let runtime: DriverRuntimeConnection
    private var notifications: AsyncStream<Void>.Iterator

    init(runtime: DriverRuntimeConnection, notifications: AsyncStream<Void>.Iterator) {
      self.runtime = runtime
      self.notifications = notifications
    }

    /// Returns the next event, or nil after the connection closes.
    public mutating func next() async throws -> DriverEvent? {
      while true {
        try Task.checkCancellation()
        do {
          if let event = try await runtime.nextEvent() { return event }
        } catch DriverRuntimeError.closed { return nil }
        // The empty poll armed the extension; the next queued event sends a notification.
        guard await notifications.next() != nil else {
          try Task.checkCancellation()
          return nil
        }
      }
    }
  }
}
