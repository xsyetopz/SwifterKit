import Foundation

/// A negotiated connection between Swift driver behavior and the internal DriverKit runtime.
public actor DriverRuntimeConnection {
  /// The maximum response size accepted by default.
  public static let defaultMaximumResponseSize = 65_536

  /// Capabilities advertised by the connected extension.
  public private(set) var capabilities: RuntimeCapabilities = []

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
    guard maximumResponseSize >= RuntimeMessage.headerSize + MemoryLayout<UInt64>.size else {
      throw DriverRuntimeError.invalidMaximumResponseSize
    }

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
      flags: [.expectsResponse, .finalFragment],
      payload: command.encodedPayload(),
      responseCapacity: min(maximumResponseSize, command.maximumResponseSize)
    )
    guard response.kind == .response else {
      throw DriverRuntimeError.unexpectedMessageKind(response.kind)
    }
    return response.payload
  }

  /// Polls one queued event from the internal runtime.
  ///
  /// A nil result means no event was queued when the extension handled the request.
  public func nextEvent() async throws -> DriverEvent? {
    let response = try await transact(
      kind: .command,
      flags: [.expectsResponse, .finalFragment],
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
    let response = try await transact(
      kind: .handshake,
      flags: [.expectsResponse, .finalFragment],
      payload: Data(),
      responseCapacity: RuntimeMessage.headerSize + MemoryLayout<UInt64>.size
    )
    guard response.kind == .response, response.payload.count == MemoryLayout<UInt64>.size else {
      throw DriverRuntimeError.invalidHandshake
    }

    let advertised: UInt64 = try response.payload.readRuntimeInteger(at: 0)
    capabilities = RuntimeCapabilities(rawValue: advertised)
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

    let requestID = reserveRequestID()
    let request = RuntimeMessage(kind: kind, requestID: requestID, flags: flags, payload: payload)
    let rawResponse = try await session.call(
      DriverRequest(
        selector: 0,
        structureInput: request.encoded(),
        structureOutputCapacity: responseCapacity
      )
    )
    guard rawResponse.scalarOutput.isEmpty else { throw DriverRuntimeError.unexpectedScalarOutput }

    let response = try RuntimeMessage(decoding: rawResponse.structureOutput)
    guard response.requestID == requestID else {
      throw DriverRuntimeError.requestIDMismatch(expected: requestID, received: response.requestID)
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
