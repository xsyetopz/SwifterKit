/// Criteria used to find a DriverKit service in the I/O Registry.
public struct DriverServiceMatch: Sendable, Hashable {
  /// The IOKit service class to enumerate.
  public let serviceClass: String
  /// An optional registry entry name.
  public let name: String?
  /// Required registry properties.
  public let registryProperties: [String: DriverProperty]
  /// An optional user-space class name, such as a DriverKit driver class. The extension turns it
  /// into matching entries with `IOService::CreateUserClassMatchingDictionary` in
  /// ``DriverContext/watchServices(matching:)``. Other lookups ignore it.
  public let userClass: String?

  /// Creates DriverKit service-matching criteria.
  public init(
    serviceClass: String,
    name: String? = nil,
    registryProperties: [String: DriverProperty] = [:],
    userClass: String? = nil
  ) {
    self.serviceClass = serviceClass
    self.name = name
    self.registryProperties = registryProperties
    self.userClass = userClass
  }
}
