import Foundation

/// A negotiated connection between Swift driver behavior and the internal DriverKit runtime.
public actor DriverRuntimeConnection {
  /// The maximum response size accepted by default.
  public static let defaultMaximumResponseSize = RuntimeMessage.maximumSize

  /// Capabilities advertised by the connected extension.
  public private(set) var capabilities: RuntimeCapabilities = []
  /// The protocol version selected by the connected extension during the handshake.
  public private(set) var protocolVersion: RuntimeProtocolVersion = .current

  private var session: DriverSession?
  private var nextRequestID: UInt64 = 1
  private let maximumResponseSize: Int

  private init(session: DriverSession, maximumResponseSize: Int) {
    self.session = session
    self.maximumResponseSize = maximumResponseSize
  }

  /// Opens a protocol session and verifies all required capabilities.
  public static func connect(
    session: DriverSession,
    requiring requiredCapabilities: RuntimeCapabilities = [],
    maximumResponseSize: Int = defaultMaximumResponseSize
  ) async throws -> DriverRuntimeConnection {
    guard maximumResponseSize >= RuntimeMessage.headerSize + RuntimeSchema.handshakeResponseSize
    else { throw DriverRuntimeError.invalidMaximumResponseSize }

    let connection = DriverRuntimeConnection(
      session: session,
      maximumResponseSize: maximumResponseSize
    )
    try await connection.negotiate(requiring: requiredCapabilities)
    return connection
  }

  /// Executes a low-level runtime command after enforcing its capability requirements.
  public func execute(_ command: DriverCommand) async throws -> Data {
    guard capabilities.contains(command.requiredCapabilities) else {
      throw DriverRuntimeError.missingCapabilities(
        required: command.requiredCapabilities,
        available: capabilities
      )
    }

    let response = try await transact(
      kind: .command,
      flags: .expectsResponse,
      payload: command.encodedPayload(),
      responseCapacity: min(maximumResponseSize, command.maximumResponseSize)
    )
    guard response.kind == .response else {
      throw DriverRuntimeError.unexpectedMessageKind(response.kind)
    }
    return response.payload
  }

  /// Registers for event notifications and returns the extension's events as they arrive.
  ///
  /// Registration happens before this method returns, so no event queued afterward goes
  /// unnoticed. See ``DriverEventSequence`` for how the sequence drains, waits, and ends.
  /// Calling this method again replaces the registration; the earlier sequence ends once its
  /// queue is empty.
  public func events() async throws -> DriverEventSequence {
    guard let session else { throw DriverRuntimeError.closed }
    let notifications = try await session.notifications(
      selector: RuntimeSelector.eventNotification.rawValue
    )
    return DriverEventSequence(runtime: self, notifications: notifications)
  }

  /// Takes one queued event from the internal runtime.
  ///
  /// A nil result means no event was queued when the extension handled the request. The
  /// extension then notifies the registered host when the next event is queued.
  func nextEvent() async throws -> DriverEvent? {
    let response = try await transact(
      kind: .command,
      flags: .expectsResponse,
      payload: DriverCommand.pollEvent.encodedPayload(),
      responseCapacity: min(maximumResponseSize, DriverCommand.pollEvent.maximumResponseSize)
    )
    if response.kind == .response, response.payload.isEmpty { return nil }
    guard response.kind == .event, response.payload.count >= MemoryLayout<UInt32>.size else {
      throw DriverRuntimeError.unexpectedMessageKind(response.kind)
    }

    let eventType: UInt32 = try response.payload.readRuntimeInteger(at: 0)
    return DriverEvent(
      type: eventType,
      payload: Array(response.payload.dropFirst(MemoryLayout<UInt32>.size))
    )
  }

  /// Closes the underlying user-client session idempotently.
  public func close() async {
    guard let session else { return }
    self.session = nil
    await session.close()
  }

  private func negotiate(requiring requiredCapabilities: RuntimeCapabilities) async throws {
    let offer = RuntimeHandshakeOffer(versions: RuntimeProtocolVersion.supported)
    let response = try await transact(
      kind: .handshake,
      flags: .expectsResponse,
      payload: offer.encoded(),
      responseCapacity: RuntimeMessage.headerSize + RuntimeSchema.handshakeResponseSize
    )
    guard response.kind == .response else { throw DriverRuntimeError.invalidHandshake }

    let acceptance = try RuntimeHandshakeAcceptance(decoding: response.payload)
    guard acceptance.version == response.version, offer.versions.contains(acceptance.version) else {
      throw DriverRuntimeError.invalidHandshake
    }
    protocolVersion = acceptance.version
    capabilities = acceptance.capabilities
    guard capabilities.contains(requiredCapabilities) else {
      throw DriverRuntimeError.missingCapabilities(
        required: requiredCapabilities,
        available: capabilities
      )
    }
  }

  private func transact(
    kind: RuntimeMessageKind,
    flags: RuntimeMessageFlags,
    payload: Data,
    responseCapacity: Int
  ) async throws -> RuntimeMessage {
    guard let session else { throw DriverRuntimeError.closed }

    // The handshake header carries the newest offered version; later messages use the selected one.
    let request = RuntimeMessage(
      version: protocolVersion,
      kind: kind,
      requestID: reserveRequestID(),
      flags: flags,
      payload: payload
    )
    let rawResponse = try await session.call(
      DriverRequest(
        selector: RuntimeSelector.transact.rawValue,
        structureInput: request.encoded(),
        structureOutputCapacity: responseCapacity
      )
    )
    guard rawResponse.scalarOutput.isEmpty else { throw DriverRuntimeError.unexpectedScalarOutput }

    let response = try RuntimeMessage(decoding: rawResponse.structureOutput)
    guard response.requestID == request.requestID else {
      throw DriverRuntimeError.requestIDMismatch(
        expected: request.requestID,
        received: response.requestID
      )
    }
    guard kind == .handshake || response.version == protocolVersion else {
      throw RuntimeProtocolError.unsupportedVersion(response.version.rawValue)
    }
    return response
  }

  private func reserveRequestID() -> UInt64 {
    let identifier = nextRequestID
    nextRequestID &+= 1
    if nextRequestID == 0 { nextRequestID = 1 }
    return identifier
  }
}

/// A runtime negotiation or transaction failure.
public enum DriverRuntimeError: Error, Sendable, Equatable {
  /// The configured response limit cannot hold a handshake.
  case invalidMaximumResponseSize
  /// The handshake response has an invalid kind or payload.
  case invalidHandshake
  /// The connected extension does not implement required capabilities.
  case missingCapabilities(required: RuntimeCapabilities, available: RuntimeCapabilities)
  /// The response does not correlate to the pending request.
  case requestIDMismatch(expected: UInt64, received: UInt64)
  /// The response kind is invalid for the operation.
  case unexpectedMessageKind(RuntimeMessageKind)
  /// The runtime unexpectedly returned scalar values.
  case unexpectedScalarOutput
  /// The connection has closed.
  case closed
}
