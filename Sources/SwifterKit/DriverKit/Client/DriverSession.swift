/// A concurrency-safe session with one user-client connection.
public actor DriverSession {
  /// The service associated with this session.
  nonisolated public let service: DriverService

  private var connection: (any DriverConnection)?

  init(service: DriverService, connection: any DriverConnection) {
    self.service = service
    self.connection = connection
  }

  /// Invokes one low-level external method.
  public func call(_ request: DriverRequest) async throws -> DriverResponse {
    guard let connection else {
      throw DriverKitError(
        kind: .sessionClosed,
        operation: "IOConnectCallMethod",
        serviceID: service.id
      )
    }
    return try await connection.call(request)
  }

  /// Closes the session idempotently.
  public func close() async {
    guard let connection else { return }
    self.connection = nil
    await connection.close()
  }
}
