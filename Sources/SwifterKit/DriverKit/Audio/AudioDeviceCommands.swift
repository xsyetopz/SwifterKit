import Foundation

extension DriverCommand {
  /// The largest stream table, control-selector list, and channel layout the runtime accepts.
  static let audioMaximumStreams = UInt32(RuntimeAudioLimits.maximumStreams)
  static let audioMaximumSelectorItems = RuntimeAudioLimits.maximumSelectorItems
  static let audioMaximumChannelLabels = RuntimeAudioLimits.maximumChannelLabels

  /// Reads device state that has no other typed reader.
  public static func audioDeviceState() -> Self {
    Self(
      opcode: .audioGetDeviceState,
      requiredCapabilities: .audio,
      payload: Data(),
      maximumResponseSize: RuntimeMessage.headerSize + 64
    )
  }

  /// Changes one `IOUserAudioDevice` property.
  public static func audioSetDeviceProperty(_ property: AudioDeviceProperty) throws -> Self {
    if case .preferredStereoChannels(let pair) = property,
      pair.left == 0 || pair.right == 0 || pair.left == pair.right
    {
      throw AudioRuntimeError.invalidPayload
    }
    let fields = property.runtimeFields
    return Self(
      opcode: .audioSetDeviceProperty,
      requiredCapabilities: .audio,
      payload: audioMemberValue(fields.selector, fields.value),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Sets the device's preferred input or output channel layout.
  public static func audioSetPreferredChannelLayout(
    direction: AudioStreamDirection,
    labels: [AudioChannelLabel]
  ) throws -> Self {
    guard (1...audioMaximumChannelLabels).contains(labels.count) else {
      throw AudioRuntimeError.invalidPayload
    }
    var payload = Data(capacity: 8 + labels.count * 4)
    payload.appendRuntimeInteger(UInt32(direction == .input ? 1 : 0))
    payload.appendRuntimeInteger(UInt32(labels.count))
    for label in labels { payload.appendRuntimeInteger(label.rawValue) }
    return Self(
      opcode: .audioSetPreferredChannelLayout,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads the state, formats, and memory length of a configured stream.
  public static func audioStreamState(index: UInt32) throws -> Self {
    guard index < audioMaximumStreams else { throw AudioRuntimeError.invalidStreamIndex }
    return Self(
      opcode: .audioGetStreamState,
      requiredCapabilities: .audio,
      payload: audioIdentifierPayload(index),
      maximumResponseSize: RuntimeMessage.headerSize + 80 + RuntimeAudioLimits.maximumStreamFormats
        * 40
    )
  }

  /// Changes one property of a configured stream.
  public static func audioSetStreamProperty(
    index: UInt32,
    _ property: AudioStreamProperty
  ) throws -> Self {
    guard index < audioMaximumStreams else { throw AudioRuntimeError.invalidStreamIndex }
    switch property {
    case .startingChannel(let channel) where channel == 0,
      .currentFormat(let channel) where channel >= RuntimeAudioLimits.maximumStreamFormats:
      throw AudioRuntimeError.invalidPayload
    case .ringBufferFrameCapacity(let frames)
    where !(RuntimeAudioLimits.minimumZeroTimestampPeriod...RuntimeAudioLimits.maximumFrameCount)
      .contains(Int(frames)):
      throw AudioRuntimeError.invalidPayload
    default: break
    }
    let fields = property.runtimeFields
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(index)
    payload.appendRuntimeInteger(fields.selector)
    payload.appendRuntimeInteger(fields.value)
    return Self(
      opcode: .audioSetStreamProperty,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads the scope, element, range, channels, and selector items of a configured control.
  public static func audioControlInfo(identifier: UInt32) -> Self {
    Self(
      opcode: .audioGetControlInfo,
      requiredCapabilities: .audio,
      payload: audioIdentifierPayload(identifier),
      maximumResponseSize: RuntimeMessage.headerSize + 48 + audioMaximumSelectorItems
        * (8 + RuntimeAudioLimits.nameMaximumLength)
    )
  }

  /// Changes a slider range or stereo-pan channel pair.
  public static func audioSetControlProperty(
    identifier: UInt32,
    _ property: AudioControlProperty
  ) throws -> Self {
    if case .panningChannels(let pair) = property, pair.left == pair.right {
      throw AudioRuntimeError.invalidControlValue
    }
    let fields = property.runtimeFields
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(fields.selector)
    payload.appendRuntimeInteger(fields.value)
    return Self(
      opcode: .audioSetControlProperty,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Removes items from a selector control by value.
  public static func audioRemoveSelectorItems(identifier: UInt32, values: [UInt32]) throws -> Self {
    guard (1...audioMaximumSelectorItems).contains(values.count), Set(values).count == values.count
    else { throw AudioRuntimeError.invalidControlValue }
    var payload = Data(capacity: 8 + values.count * 4)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(UInt32(values.count))
    for value in values { payload.appendRuntimeInteger(value) }
    return Self(
      opcode: .audioRemoveSelectorItems,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads the selector, data types, and owner of a configured custom property.
  public static func audioCustomPropertyInfo(identifier: UInt32) -> Self {
    Self(
      opcode: .audioGetCustomPropertyInfo,
      requiredCapabilities: .audio,
      payload: audioIdentifierPayload(identifier),
      maximumResponseSize: RuntimeMessage.headerSize + 24
    )
  }

  /// Adds a configured stream, control, or custom property to its owner, or removes it.
  ///
  /// Streams and controls attach only to the device. Custom properties attach to the device
  /// or the driver. Detach a member before it moves to another owner.
  public static func audioSetMemberAttachment(
    _ member: AudioMember,
    owner: AudioMemberOwner
  ) throws -> Self {
    let fields = member.runtimeFields
    switch member {
    case .stream(let index) where index >= audioMaximumStreams:
      throw AudioRuntimeError.invalidStreamIndex
    case .stream, .control:
      guard owner != .driver else { throw AudioRuntimeError.invalidObjectTarget }
    case .customProperty: break
    }
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(fields.kind)
    payload.appendRuntimeInteger(fields.identifier)
    payload.appendRuntimeInteger(owner.rawValue)
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: .audioSetMemberAttachment,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  private static func audioMemberValue(_ selector: UInt32, _ value: UInt64) -> Data {
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(selector)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(value)
    return payload
  }

  private static func audioIdentifierPayload(_ identifier: UInt32) -> Data {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(UInt32(0))
    return payload
  }
}

extension DriverContext {
  /// Reads device state that has no other typed reader.
  /// Calls `IOUserAudioDevice::CanBeDefaultInputDevice`,
  /// `IOUserAudioDevice::CanBeDefaultOutputDevice`,
  /// `IOUserAudioDevice::CanBeDefaultSystemOutputDevice`,
  /// `IOUserAudioDevice::GetCurrentClientIOTime`, `IOUserAudioDevice::GetInputSafetyOffset`,
  /// `IOUserAudioDevice::GetOutputSafetyOffset` and
  /// `IOUserAudioDevice::GetPreferredChannelsForStereo`.
  public func audioDeviceState() async throws -> AudioDeviceState {
    try AudioDeviceState(runtimePayload: await execute(.audioDeviceState()))
  }

  /// Changes one `IOUserAudioDevice` property.
  /// Calls `IOUserAudioDevice::SetCanBeDefaultInputDevice`,
  /// `IOUserAudioDevice::SetCanBeDefaultOutputDevice`,
  /// `IOUserAudioDevice::SetCanBeDefaultSystemOutputDevice`,
  /// `IOUserAudioDevice::SetInputSafetyOffset`, `IOUserAudioDevice::SetOutputSafetyOffset`,
  /// `IOUserAudioDevice::SetPreferredChannelsForStereo` and
  /// `IOUserAudioDevice::SetWantsStreamFormatsRestored`.
  public func audioSetDeviceProperty(_ property: AudioDeviceProperty) async throws {
    _ = try await execute(.audioSetDeviceProperty(property))
  }

  /// Sets the device's preferred input or output channel layout.
  /// Calls `IOUserAudioDevice::SetPreferredInputChannelLayout` and
  /// `IOUserAudioDevice::SetPreferredOutputChannelLayout`.
  public func audioSetPreferredChannelLayout(
    direction: AudioStreamDirection,
    labels: [AudioChannelLabel]
  ) async throws {
    _ = try await execute(.audioSetPreferredChannelLayout(direction: direction, labels: labels))
  }

  /// Reads the state, formats, and memory length of a configured stream.
  /// Calls `IOUserAudioStream::GetAvailableStreamFormats`,
  /// `IOUserAudioStream::GetIOMemoryDescriptor`, `IOUserAudioStream::GetLatency`,
  /// `IOUserAudioStream::GetNumberAvailableStreamFormats`, `IOUserAudioStream::GetStartingChannel`,
  /// `IOUserAudioStream::GetStreamDirection`, `IOUserAudioStream::GetStreamIsActive` and
  /// `IOUserAudioStream::GetTerminalType`.
  public func audioStreamState(index: UInt32) async throws -> AudioStreamState {
    try AudioStreamState(runtimePayload: await execute(.audioStreamState(index: index)))
  }

  /// Changes one property of a configured stream.
  /// Calls `IOUserAudioStream::SetIOMemoryDescriptor`, `IOUserAudioStream::SetLatency`,
  /// `IOUserAudioStream::SetStartingChannel`, `IOUserAudioStream::SetStreamIsActive` and
  /// `IOUserAudioStream::SetTerminalType`.
  public func audioSetStreamProperty(index: UInt32, _ property: AudioStreamProperty) async throws {
    _ = try await execute(.audioSetStreamProperty(index: index, property))
  }

  /// Reads the scope, element, range, channels, and selector items of a configured control.
  /// Calls `IOUserAudioControl::GetControlElement`, `IOUserAudioControl::GetControlScope`,
  /// `IOUserAudioControl::GetIsSettable` and `IOUserAudioSelectorControl::GetControlValuesCount`.
  public func audioControlInfo(identifier: UInt32) async throws -> AudioControlInfo {
    try AudioControlInfo(runtimePayload: await execute(.audioControlInfo(identifier: identifier)))
  }

  /// Changes a slider range or stereo-pan channel pair.
  public func audioSetControlProperty(
    identifier: UInt32,
    _ property: AudioControlProperty
  ) async throws {
    _ = try await execute(.audioSetControlProperty(identifier: identifier, property))
  }

  /// Removes items from a selector control by value.
  /// Calls `IOUserAudioSelectorControl::RemoveControlValueDescriptions`.
  public func audioRemoveSelectorItems(identifier: UInt32, values: [UInt32]) async throws {
    _ = try await execute(.audioRemoveSelectorItems(identifier: identifier, values: values))
  }

  /// Reads the selector, data types, and owner of a configured custom property.
  /// Calls `IOUserAudioCustomProperty::GetCustomPropertyInfo`.
  public func audioCustomPropertyInfo(identifier: UInt32) async throws -> AudioCustomPropertyInfo {
    try AudioCustomPropertyInfo(
      runtimePayload: await execute(.audioCustomPropertyInfo(identifier: identifier))
    )
  }

  /// Adds a configured stream, control, or custom property to its owner, or removes it.
  /// Calls `IOUserAudioDevice::RemoveStream` and `IOUserAudioDriver::RemoveCustomProperty`.
  public func audioSetMemberAttachment(_ member: AudioMember, owner: AudioMemberOwner) async throws
  { _ = try await execute(.audioSetMemberAttachment(member, owner: owner)) }
}
