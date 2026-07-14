/// A transport capable of discovering and opening DriverKit services.
public protocol DriverTransport: Sendable {
  /// Returns services matching registry criteria.
  func services(matching criteria: DriverServiceMatch) async throws -> [DriverService]

  /// Opens a user-client connection.
  func open(_ service: DriverService, type: UInt32) async throws -> any DriverConnection
}

/// An open low-level user-client connection.
public protocol DriverConnection: Sendable {
  /// Invokes one external method.
  func call(_ request: DriverRequest) async throws -> DriverResponse

  /// Closes the connection idempotently.
  func close() async
}
