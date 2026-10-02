import Foundation

extension DriverCommand {
  /// Reads the identity and name of a MIDIDriverKit object or the driver.
  public static func midiObjectInfo(_ target: MIDIObjectTarget) throws -> Self {
    midiCommand(
      .midiGetObjectInfo,
      try midiTargetPayload(target),
      responseSize: RuntimeMessage.headerSize + 24 + RuntimeMIDIObjectLimits.nameMaximumLength
    )
  }

  /// Renames a MIDIDriverKit object, or the driver, with `SetName`.
  public static func midiSetObjectName(_ target: MIDIObjectTarget, name: String) throws -> Self {
    let bytes = Data(name.utf8)
    guard !bytes.isEmpty, bytes.count <= RuntimeMIDIObjectLimits.nameMaximumLength,
      !bytes.contains(0)
    else { throw MIDIRuntimeError.invalidName }
    var payload = try midiTargetPayload(target)
    payload.appendRuntimeInteger(UInt32(bytes.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(bytes)
    return midiCommand(.midiSetObjectName, payload)
  }

  /// Reads the value type of a property with `GetPropertyType`.
  public static func midiPropertyType(
    _ target: MIDIObjectTarget,
    property: MIDIProperty
  ) throws -> Self {
    var payload = try midiObjectPayload(target)
    payload.append(try MIDIPropertyKey.property(property).runtimePayload())
    return midiCommand(.midiGetPropertyType, payload, responseSize: RuntimeMessage.headerSize + 4)
  }

  /// Copies one property with `CopyProperty`.
  public static func midiCopyProperty(
    _ target: MIDIObjectTarget,
    key: MIDIPropertyKey
  ) throws -> Self {
    var payload = try midiObjectPayload(target)
    payload.append(try key.runtimePayload())
    return midiCommand(.midiCopyProperty, payload, responseSize: RuntimeMessage.maximumSize)
  }

  /// Sets one property with `SetProperty`.
  public static func midiSetProperty(
    _ target: MIDIObjectTarget,
    key: MIDIPropertyKey,
    value: MIDIPropertyValue
  ) throws -> Self {
    var payload = try midiObjectPayload(target)
    payload.append(try key.runtimePayload())
    payload.append(try value.runtimePayload())
    return try midiSizedCommand(.midiSetProperty, payload)
  }

  /// Reads every set property with `GetProperties`.
  public static func midiProperties(_ target: MIDIObjectTarget) throws -> Self {
    midiCommand(
      .midiGetProperties,
      try midiObjectPayload(target),
      responseSize: RuntimeMessage.maximumSize
    )
  }

  /// Sets properties from a dictionary with `SetProperties`.
  ///
  /// The device and entity overrides apply: an `entities` array of dictionaries on the device
  /// goes to each entity, and its count must match the device's entities.
  public static func midiSetProperties(
    _ target: MIDIObjectTarget,
    _ properties: [String: MIDIPropertyValue]
  ) throws -> Self {
    var payload = try midiObjectPayload(target)
    payload.append(try MIDIPropertyValue.dictionary(properties).runtimePayload())
    return try midiSizedCommand(.midiSetProperties, payload)
  }

  /// Reads whether the device is running and which entities it holds.
  public static func midiDeviceState() -> Self {
    midiCommand(
      .midiGetDeviceState,
      Data(),
      responseSize: RuntimeMessage.headerSize + 8 + MIDIObjectIDList.maximumCount * 4
    )
  }

  /// Reads which sources and destinations the entity holds.
  public static func midiEntityMembers() -> Self {
    midiCommand(
      .midiGetEntityMembers,
      Data(),
      responseSize: RuntimeMessage.headerSize + 8 + MIDIObjectIDList.maximumCount * 4
    )
  }

  /// Removes the entity, a source, or a destination from its owner, or adds it back, through a
  /// device configuration change. See ``DriverContext/midiSetMemberAttachment(_:attached:)``.
  public static func midiSetMemberAttachment(_ member: MIDIMember, attached: Bool) throws -> Self {
    var payload = try midiTargetPayload(member.target)
    payload.appendRuntimeInteger(UInt32(attached ? 1 : 0))
    payload.appendRuntimeInteger(UInt32(0))
    return midiCommand(.midiSetMemberAttachment, payload)
  }

  private static func midiCommand(
    _ opcode: RuntimeOpcode,
    _ payload: Data,
    responseSize: Int = RuntimeMessage.headerSize
  ) -> Self {
    Self(
      opcode: opcode,
      requiredCapabilities: .midi,
      payload: payload,
      maximumResponseSize: responseSize
    )
  }

  private static func midiSizedCommand(_ opcode: RuntimeOpcode, _ payload: Data) throws -> Self {
    guard payload.count <= RuntimeMessage.maximumSize - RuntimeMessage.headerSize else {
      throw MIDIRuntimeError.propertyValueTooLarge
    }
    return midiCommand(opcode, payload)
  }

  private static func midiTargetPayload(_ target: MIDIObjectTarget) throws -> Data {
    let fields = try target.validated().runtimeFields
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(fields.kind)
    payload.appendRuntimeInteger(fields.index)
    return payload
  }

  /// Property commands act on `IOUserMIDIObject`, which the driver is not.
  private static func midiObjectPayload(_ target: MIDIObjectTarget) throws -> Data {
    guard target != .driver else { throw MIDIRuntimeError.invalidObjectTarget }
    return try midiTargetPayload(target)
  }
}

extension DriverContext {
  /// Reads the identity and name of a MIDIDriverKit object or the driver.
  /// Calls `IOUserMIDIDriver::GetMIDIObjectForObjectID`, `IOUserMIDIDriver::GetName`,
  /// `IOUserMIDIObject::GetBaseClassID`, `IOUserMIDIObject::GetClassID`,
  /// `IOUserMIDIObject::GetName`, `IOUserMIDIObject::GetObjectID` and
  /// `IOUserMIDIObject::GetOwnerObjectID`.
  public func midiObjectInfo(_ target: MIDIObjectTarget) async throws -> MIDIObjectInfo {
    try MIDIObjectInfo(runtimePayload: await execute(.midiObjectInfo(target)))
  }

  /// Renames a MIDIDriverKit object or the driver.
  /// Calls `IOUserMIDIObject::SetName`.
  public func midiSetObjectName(_ target: MIDIObjectTarget, name: String) async throws {
    _ = try await execute(.midiSetObjectName(target, name: name))
  }

  /// Reads the value type of a property.
  /// Calls `IOUserMIDIObject::GetPropertyType`.
  public func midiPropertyType(
    _ target: MIDIObjectTarget,
    property: MIDIProperty
  ) async throws -> MIDIPropertyType {
    let payload = try await execute(.midiPropertyType(target, property: property))
    guard payload.count == 4,
      let type = MIDIPropertyType(rawValue: try payload.readRuntimeInteger(at: 0))
    else { throw MIDIRuntimeError.invalidPayload }
    return type
  }

  /// Copies one property.
  /// Calls `IOUserMIDIObject::CopyProperty`.
  public func midiCopyProperty(
    _ target: MIDIObjectTarget,
    key: MIDIPropertyKey
  ) async throws -> MIDIPropertyValue {
    try MIDIPropertyValue(runtimePayload: await execute(.midiCopyProperty(target, key: key)))
  }

  /// Sets one property.
  /// Calls `IOUserMIDIObject::SetProperty`.
  public func midiSetProperty(
    _ target: MIDIObjectTarget,
    key: MIDIPropertyKey,
    value: MIDIPropertyValue
  ) async throws { _ = try await execute(.midiSetProperty(target, key: key, value: value)) }

  /// Reads every set property.
  /// Calls `IOUserMIDIObject::GetProperties`.
  public func midiProperties(_ target: MIDIObjectTarget) async throws -> [String: MIDIPropertyValue]
  {
    let value = try MIDIPropertyValue(runtimePayload: await execute(.midiProperties(target)))
    guard case .dictionary(let properties) = value else { throw MIDIRuntimeError.invalidPayload }
    return properties
  }

  /// Sets properties from a dictionary.
  /// Calls `IOUserMIDIObject::SetProperties`.
  public func midiSetProperties(
    _ target: MIDIObjectTarget,
    _ properties: [String: MIDIPropertyValue]
  ) async throws { _ = try await execute(.midiSetProperties(target, properties)) }

  /// Reads whether the device is running and which entities it holds.
  /// Calls `IOUserMIDIDevice::GetEntities`.
  public func midiDeviceState() async throws -> MIDIDeviceState {
    try MIDIDeviceState(runtimePayload: await execute(.midiDeviceState()))
  }

  /// Reads which sources and destinations the entity holds.
  /// Calls `IOUserMIDIEntity::GetDestinations` and `IOUserMIDIEntity::GetSources`.
  public func midiEntityMembers() async throws -> MIDIEntityMembers {
    try MIDIEntityMembers(runtimePayload: await execute(.midiEntityMembers()))
  }

  /// Removes the entity, a source, or a destination from its owner, or adds it back.
  ///
  /// The change alters the device structure, so the runtime requests it through
  /// `IOUserMIDIDevice::RequestDeviceConfigurationChange` and applies it in
  /// `IOUserMIDIDevice::PerformDeviceConfigurationChange`, where I/O is stopped. This call returns
  /// once the host accepts the request, and the host can apply the change later. Read
  /// ``midiDeviceState()`` or ``midiEntityMembers()`` to see the result.
  /// Calls `IOUserMIDIDevice::AddEntity`, `IOUserMIDIDevice::RemoveEntity`,
  /// `IOUserMIDIEntity::AddSource`, `IOUserMIDIEntity::RemoveSource`,
  /// `IOUserMIDIEntity::AddDestination` and `IOUserMIDIEntity::RemoveDestination`.
  public func midiSetMemberAttachment(_ member: MIDIMember, attached: Bool) async throws {
    _ = try await execute(.midiSetMemberAttachment(member, attached: attached))
  }
}
