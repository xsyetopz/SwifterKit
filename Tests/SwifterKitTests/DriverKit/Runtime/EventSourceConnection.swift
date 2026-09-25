import Foundation

@testable import SwifterKit

/// A runtime connection that models the extension's event queue and notification rule.
///
/// It follows the native contract in `SwifterKitRuntimeEvents.cpp`: a poll that finds the queue
/// empty arms the registration, and an enqueue that finds it armed disarms it and sends one
/// notification. Registration arms, or notifies at once when events are already queued.
actor EventSourceConnection: DriverConnection {
  let capabilities: RuntimeCapabilities
  private var queue: [DriverEvent] = []
  private var armed = false
  private var continuation: AsyncStream<Void>.Continuation?
  /// Events the next empty poll queues after it arms, before it answers.
  private var afterEmptyPoll: [DriverEvent] = []
  private var failNextPoll = false
  private(set) var pollCount = 0
  private(set) var emptyPollCount = 0
  private(set) var notificationsSent = 0
  private(set) var registrationCount = 0
  private(set) var closeCount = 0

  init(capabilities: RuntimeCapabilities = [], events: [DriverEvent] = []) {
    self.capabilities = capabilities
    self.queue = events
  }

  /// Queues an event as a DriverKit callback would.
  func enqueue(_ event: DriverEvent) {
    queue.append(event)
    guard armed, let continuation else { return }
    armed = false
    notificationsSent += 1
    continuation.yield()
  }

  /// Queues `events` during the next empty poll, after it arms and before it answers.
  func enqueueAfterNextEmptyPoll(_ events: [DriverEvent]) { afterEmptyPoll = events }

  /// Makes the next poll fail as a connection closed while the request was in flight.
  func failNextPollAsClosed() { failNextPoll = true }

  /// Sends a notification regardless of the armed flag.
  func signal() { continuation?.yield() }

  func notifications(selector: UInt32) throws -> AsyncStream<Void> {
    guard selector == RuntimeSelector.eventNotification.rawValue else {
      throw DriverKitError(kind: .ioReturn(-536_870_206), operation: "notifications")
    }
    registrationCount += 1
    continuation?.finish()
    let (stream, continuation) = AsyncStream.makeStream(
      of: Void.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    self.continuation = continuation
    armed = true
    if !queue.isEmpty {
      armed = false
      notificationsSent += 1
      continuation.yield()
    }
    return stream
  }

  func call(_ request: DriverRequest) throws -> DriverResponse {
    guard request.selector == RuntimeSelector.transact.rawValue else {
      throw DriverKitError(kind: .ioReturn(-536_870_206), operation: "call")
    }
    let message = try RuntimeMessage(decoding: request.structureInput)
    switch message.kind {
    case .handshake:
      let acceptance = RuntimeHandshakeAcceptance(version: .current, capabilities: capabilities)
      return try response(.response, message.requestID, acceptance.encoded())
    case .command:
      let opcode: UInt32 = try message.payload.readRuntimeInteger(at: 0)
      guard opcode == RuntimeOpcode.pollEvent.rawValue else {
        return try response(.response, message.requestID, Data())
      }
      return try poll(requestID: message.requestID)
    case .response, .event, .error: throw RuntimeProtocolError.unknownMessageKind
    }
  }

  func close() {
    closeCount += 1
    continuation?.finish()
    continuation = nil
  }

  private func poll(requestID: UInt64) throws -> DriverResponse {
    pollCount += 1
    if failNextPoll {
      failNextPoll = false
      throw DriverKitError(kind: .sessionClosed, operation: "IOConnectCallMethod")
    }
    guard !queue.isEmpty else {
      emptyPollCount += 1
      armed = true
      let late = afterEmptyPoll
      afterEmptyPoll = []
      for event in late { enqueue(event) }
      return try response(.response, requestID, Data())
    }
    let event = queue.removeFirst()
    var payload = Data()
    payload.appendRuntimeInteger(event.type)
    payload.append(contentsOf: event.payload)
    return try response(.event, requestID, payload)
  }

  private func response(
    _ kind: RuntimeMessageKind,
    _ requestID: UInt64,
    _ payload: Data
  ) throws -> DriverResponse {
    DriverResponse(
      structureOutput: try RuntimeMessage(kind: kind, requestID: requestID, payload: payload)
        .encoded()
    )
  }
}

/// Yields until `condition` holds, returning false if it never does.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
  for _ in 0..<10_000 {
    if await condition() { return true }
    await Task.yield()
  }
  return false
}
