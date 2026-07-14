/// A stable description of a discovered DriverKit service.
public struct DriverService: Sendable, Hashable, Identifiable {
  /// The I/O Registry entry identifier.
  public let id: UInt64
  /// The registry entry name.
  public let name: String
  /// The service registry path when available.
  public let registryPath: String?
  /// Decoded registry properties.
  public let properties: [String: DriverProperty]

  /// Creates a stable service description.
  public init(
    id: UInt64,
    name: String,
    registryPath: String? = nil,
    properties: [String: DriverProperty] = [:]
  ) {
    self.id = id
    self.name = name
    self.registryPath = registryPath
    self.properties = properties
  }
}
