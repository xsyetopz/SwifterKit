/// Criteria used to find a DriverKit service in the I/O Registry.
public struct DriverServiceMatch: Sendable, Hashable {
  /// The IOKit service class to enumerate.
  public let serviceClass: String
  /// An optional registry entry name.
  public let name: String?
  /// Required registry properties.
  public let registryProperties: [String: DriverProperty]

  /// Creates DriverKit service-matching criteria.
  public init(
    serviceClass: String,
    name: String? = nil,
    registryProperties: [String: DriverProperty] = [:]
  ) {
    self.serviceClass = serviceClass
    self.name = name
    self.registryProperties = registryProperties
  }
}
