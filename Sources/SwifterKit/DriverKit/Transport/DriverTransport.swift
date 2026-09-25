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

  /// Registers for asynchronous completions of one external method.
  ///
  /// The connection invokes `selector` asynchronously once. The returned stream yields each time
  /// the user client signals that completion, and buffers at most one pending signal, so signals
  /// sent while nobody awaits the stream coalesce into one element. A later registration finishes
  /// the stream an earlier registration returned. ``close()`` finishes every stream.
  func notifications(selector: UInt32) async throws -> AsyncStream<Void>

  /// Closes the connection idempotently.
  func close() async
}
