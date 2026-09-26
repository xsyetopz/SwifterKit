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

  /// Maps the memory the user client shares for `type` into this process.
  ///
  /// `type` is the `memoryType` the user client's `CopyClientMemoryForType` receives. Pass
  /// `readOnly` when the extension shares the memory read-only. While a mapping of `type` from
  /// this connection is mapped, the connection returns that same instance. ``close()`` unmaps
  /// every mapping the connection returned before it closes.
  func mapMemory(type: UInt32, readOnly: Bool) async throws -> DriverSharedMemory

  /// Closes the connection idempotently.
  func close() async
}
