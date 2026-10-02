import Foundation

extension DriverCommand {
  /// Creates a registry update through `IOService::SetProperties`.
  public static func setServiceProperties(_ properties: [String: DriverProperty]) throws -> Self {
    guard !properties.isEmpty else { throw ServiceRuntimeError.emptyRequest }
    return service(
      .serviceSetProperties,
      payload: try ServicePropertyCoding.encode(.dictionary(properties))
    )
  }

  /// Creates a registry read through `IOService::CopyProperties`.
  public static let serviceProperties = service(.serviceCopyProperties, responseSize: nil)

  /// Creates a property removal through `IOService::RemoveProperty`.
  public static func removeServiceProperty(named name: String) throws -> Self {
    service(.serviceRemoveProperty, payload: try ServicePropertyCoding.nameBytes(name))
  }

  /// Creates a property search through `IOService::SearchProperty`.
  public static func searchServiceProperty(
    named name: String,
    options: ServicePropertySearchOptions = [],
    plane: String = "IOService"
  ) throws -> Self {
    guard options.subtracting(.all).isEmpty else { throw ServiceRuntimeError.invalidOptions }
    let nameBytes = try ServicePropertyCoding.nameBytes(name)
    let planeBytes = try ServicePropertyCoding.nameBytes(plane)
    var payload = Data(capacity: 8 + nameBytes.count + planeBytes.count)
    payload.appendRuntimeInteger(options.rawValue)
    payload.appendRuntimeInteger(UInt16(nameBytes.count))
    payload.appendRuntimeInteger(UInt16(planeBytes.count))
    payload.append(nameBytes)
    payload.append(planeBytes)
    return service(.serviceSearchProperty, payload: payload, responseSize: nil)
  }

  /// Creates a provider-chain read through `IOService::CopyProviderProperties`.
  ///
  /// With `keys`, only those properties are copied. `nil` copies every supportable property.
  public static func providerProperties(keys: [String]? = nil) throws -> Self {
    guard let keys else { return service(.serviceCopyProviderProperties, responseSize: nil) }
    guard !keys.isEmpty else { throw ServiceRuntimeError.emptyRequest }
    for key in keys { _ = try ServicePropertyCoding.nameBytes(key) }
    let payload = try ServicePropertyCoding.encode(.array(keys.map(DriverProperty.string)))
    return service(.serviceCopyProviderProperties, payload: payload, responseSize: nil)
  }

  /// Creates a registry-name read through `IOService::CopyName`.
  public static let serviceName = service(
    .serviceCopyName,
    responseSize: ServicePropertyCoding.maximumNameLength
  )

  /// Creates a registry-name change through `IOService::SetName`.
  ///
  /// The name must be 1 to 127 UTF-8 bytes without NUL, so it fits `IOServiceName` with its
  /// terminator.
  public static func setServiceName(_ name: String) throws -> Self {
    service(.serviceSetName, payload: try ServicePropertyCoding.nameBytes(name))
  }

  /// Creates a registry-entry identifier read through `IOService::GetRegistryEntryID`.
  public static let registryEntryID = service(.serviceGetRegistryEntryID, responseSize: 8)

  /// Creates a system state item read through the system state notification service's
  /// `StateNotificationItemCopy`.
  public static func systemStateItem(named name: String) throws -> Self {
    try namedValue(.serviceCopySystemStateItem, name: name, value: nil, responseSize: nil)
  }

  /// Creates a system state item through `StateNotificationItemCreate`.
  public static func createSystemStateItem(
    named name: String,
    value: [String: DriverProperty]? = nil
  ) throws -> Self { try namedValue(.serviceCreateSystemStateItem, name: name, value: value) }

  /// Creates a system state item update through `StateNotificationItemSet`.
  public static func setSystemStateItem(
    named name: String,
    value: [String: DriverProperty]
  ) throws -> Self { try namedValue(.serviceSetSystemStateItem, name: name, value: value) }

  /// Creates a CoreAnalytics event through `IOService::CoreAnalyticsSendEvent`.
  public static func sendCoreAnalyticsEvent(
    named name: String,
    payload: [String: DriverProperty]
  ) throws -> Self { try namedValue(.serviceSendCoreAnalyticsEvent, name: name, value: payload) }

  /// A command that needs no capability. `responseSize` is its payload bound, or `nil` for one
  /// full message.
  static func service(
    _ opcode: RuntimeOpcode,
    payload: Data = Data(),
    responseSize: Int? = 0
  ) -> Self {
    Self(
      opcode: opcode,
      payload: payload,
      maximumResponseSize: responseSize.map { RuntimeMessage.headerSize + $0 }
        ?? RuntimeMessage.maximumSize
    )
  }

  private static func namedValue(
    _ opcode: RuntimeOpcode,
    name: String,
    value: [String: DriverProperty]?,
    responseSize: Int? = 0
  ) throws -> Self {
    let nameBytes = try ServicePropertyCoding.nameBytes(name)
    var payload = Data(capacity: 8 + nameBytes.count)
    payload.appendRuntimeInteger(UInt32(nameBytes.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(nameBytes)
    if let value { payload.append(try ServicePropertyCoding.encode(.dictionary(value))) }
    guard payload.count <= ServicePropertyCoding.maximumPayloadSize else {
      throw ServiceRuntimeError.payloadTooLarge
    }
    return service(opcode, payload: payload, responseSize: responseSize)
  }
}

extension DriverContext {
  /// Sets registry properties on the generated service.
  ///
  /// `IOService`'s default implementation rejects the update. A family superclass may accept it.
  /// `.real` values and strings with NUL cannot be stored.
  public func setServiceProperties(_ properties: [String: DriverProperty]) async throws {
    _ = try await execute(try .setServiceProperties(properties))
  }

  /// Returns the generated service's registry properties.
  ///
  /// Numbers return as `.unsignedInteger`, because DriverKit numbers are unsigned. The properties
  /// must fit one runtime message.
  public func serviceProperties() async throws -> [String: DriverProperty] {
    try Self.dictionary(await execute(.serviceProperties))
  }

  /// Removes a registry property from the generated service.
  public func removeServiceProperty(named name: String) async throws {
    _ = try await execute(try .removeServiceProperty(named: name))
  }

  /// Returns a property of the generated service, or of its parents in `plane` with
  /// ``ServicePropertySearchOptions/parents``, or `nil` when none has it.
  public func searchServiceProperty(
    named name: String,
    options: ServicePropertySearchOptions = [],
    plane: String = "IOService"
  ) async throws -> DriverProperty? {
    let reply = try await execute(
      try .searchServiceProperty(named: name, options: options, plane: plane)
    )
    return reply.isEmpty ? nil : try ServicePropertyCoding.decode(reply)
  }

  /// Returns supportable properties of each provider from this service towards the root.
  ///
  /// The runtime reads them with `IOService::CopyProviderProperties`.
  public func providerProperties(keys: [String]? = nil) async throws -> [[String: DriverProperty]] {
    guard
      case .array(let entries) = try await ServicePropertyCoding.decode(
        execute(try .providerProperties(keys: keys))
      )
    else { throw ServiceRuntimeError.invalidPayload }
    return try entries.map { entry in
      guard case .dictionary(let properties) = entry else {
        throw ServiceRuntimeError.invalidPayload
      }
      return properties
    }
  }

  /// Returns the generated service's registry entry name.
  public func serviceName() async throws -> String {
    guard let name = String(data: try await execute(.serviceName), encoding: .utf8) else {
      throw ServiceRuntimeError.invalidPayload
    }
    return name
  }

  /// Sets the generated service's registry entry name through `IOService::SetName`.
  ///
  /// DriverKit copies the name. It must be 1 to 127 UTF-8 bytes without NUL, or this throws
  /// ``ServiceRuntimeError/invalidName(_:)``.
  public func setServiceName(_ name: String) async throws {
    _ = try await execute(try .setServiceName(name))
  }

  /// Returns the generated service's registry entry identifier.
  public func registryEntryID() async throws -> UInt64 {
    let reply = try await execute(.registryEntryID)
    guard reply.count == 8 else { throw ServiceRuntimeError.invalidPayload }
    return try reply.readRuntimeInteger(at: 0)
  }

  /// Returns a system state item, such as `com.apple.iokit.pm.sleepdescription`, or `nil` when
  /// the item has no value.
  ///
  /// The extension calls `IOService::CopySystemStateNotificationService`,
  /// `IOService::StateNotificationItemCopy`.
  public func systemStateItem(named name: String) async throws -> [String: DriverProperty]? {
    let reply = try await execute(try .systemStateItem(named: name))
    return reply.isEmpty ? nil : try Self.dictionary(reply)
  }

  /// Creates a system state item on the system state notification service.
  /// The extension calls `IOService::StateNotificationItemCreate`.
  public func createSystemStateItem(
    named name: String,
    value: [String: DriverProperty]? = nil
  ) async throws { _ = try await execute(try .createSystemStateItem(named: name, value: value)) }

  /// Sets the value of a system state item on the system state notification service.
  /// The extension calls `IOService::StateNotificationItemSet`.
  public func setSystemStateItem(named name: String, value: [String: DriverProperty]) async throws {
    _ = try await execute(try .setSystemStateItem(named: name, value: value))
  }

  /// Posts an event to CoreAnalytics.
  public func sendCoreAnalyticsEvent(
    named name: String,
    payload: [String: DriverProperty]
  ) async throws {
    _ = try await execute(try .sendCoreAnalyticsEvent(named: name, payload: payload))
  }

  private static func dictionary(_ reply: Data) throws -> [String: DriverProperty] {
    guard case .dictionary(let properties) = try ServicePropertyCoding.decode(reply) else {
      throw ServiceRuntimeError.invalidPayload
    }
    return properties
  }
}
