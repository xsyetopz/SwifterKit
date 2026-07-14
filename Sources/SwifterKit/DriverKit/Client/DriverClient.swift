/// The concurrency-safe entry point for discovery and connections.
public actor DriverClient {
  private let transport: any DriverTransport

  /// Creates a client backed by native IOKit.
  public init() { self.transport = IOKitDriverTransport() }

  /// Creates a client backed by a custom transport.
  public init(transport: any DriverTransport) { self.transport = transport }

  /// Returns stable descriptions of matching services.
  public func services(matching criteria: DriverServiceMatch) async throws -> [DriverService] {
    try await transport.services(matching: criteria)
  }

  /// Opens a concurrency-safe session.
  public func open(_ service: DriverService, type: UInt32 = 0) async throws -> DriverSession {
    let connection = try await transport.open(service, type: type)
    return DriverSession(service: service, connection: connection)
  }
}
