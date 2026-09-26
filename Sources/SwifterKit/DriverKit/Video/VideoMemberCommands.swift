import Foundation

extension DriverCommand {
  /// The largest stream table, buffer table, selector list, and channel layout the runtime accepts.
  static let videoMaximumStreams: UInt32 = 8
  static let videoMaximumBuffers: UInt32 = 32
  static let videoMaximumSelectorItems = 32
  static let videoMaximumChannelLabels = 64

  /// Reads device state that has no other typed reader.
  public static func videoDeviceState() -> Self {
    Self(
      opcode: .videoGetDeviceState,
      requiredCapabilities: .video,
      payload: Data(),
      maximumResponseSize: RuntimeMessage.headerSize + 64
    )
  }

  /// Changes one `IOUserVideoDevice` property.
  public static func videoSetDeviceProperty(_ property: VideoDeviceProperty) throws -> Self {
    if case .preferredStereoChannels(let pair) = property,
      pair.left == 0 || pair.right == 0 || pair.left == pair.right
    {
      throw VideoRuntimeError.invalidPayload
    }
    let fields = property.runtimeFields
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(fields.selector)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(fields.value)
    return videoMemberCommand(.videoSetDeviceProperty, payload)
  }

  /// Sets the device's preferred input or output channel layout.
  public static func videoSetPreferredChannelLayout(
    direction: VideoStreamDirection,
    labels: [VideoChannelLabel]
  ) throws -> Self {
    guard (1...videoMaximumChannelLabels).contains(labels.count) else {
      throw VideoRuntimeError.invalidPayload
    }
    var payload = Data(capacity: 8 + labels.count * 4)
    payload.appendRuntimeInteger(UInt32(direction == .input ? 1 : 0))
    payload.appendRuntimeInteger(UInt32(labels.count))
    for label in labels { payload.appendRuntimeInteger(label.rawValue) }
    return videoMemberCommand(.videoSetPreferredChannelLayout, payload)
  }

  /// Reads the state, formats, queues, and buffer list of a configured stream.
  public static func videoStreamState(index: UInt32) throws -> Self {
    guard index < videoMaximumStreams else { throw VideoRuntimeError.invalidStreamIndex }
    return videoMemberCommand(
      .videoGetStreamState,
      videoMemberRequest(index, 0),
      response: 128 + 16 * 40 + Int(videoMaximumBuffers) * 4
    )
  }

  /// Changes one property of a configured stream.
  public static func videoSetStreamProperty(
    index: UInt32,
    _ property: VideoStreamProperty
  ) throws -> Self {
    guard index < videoMaximumStreams else { throw VideoRuntimeError.invalidStreamIndex }
    switch property {
    case .startingChannel(0): throw VideoRuntimeError.invalidPayload
    case .currentFormat(let format) where format >= 16: throw VideoRuntimeError.invalidPayload
    case .bufferCapacity(let data, let control)
    where !(1...67_108_864).contains(data) || !(1...1_048_576).contains(control):
      throw VideoRuntimeError.invalidPayload
    case .queueEntryCount(let count) where !(1...256).contains(count):
      throw VideoRuntimeError.invalidPayload
    default: break
    }
    return videoMemberCommand(
      .videoSetStreamProperty,
      videoMemberProperty(index, property.runtimeFields)
    )
  }

  /// Reads the identity and memory of a configured buffer.
  public static func videoBufferInfo(streamIndex: UInt32, bufferIndex: UInt32) throws -> Self {
    guard streamIndex < videoMaximumStreams else { throw VideoRuntimeError.invalidStreamIndex }
    guard bufferIndex < videoMaximumBuffers else { throw VideoRuntimeError.invalidBufferIndex }
    return videoMemberCommand(
      .videoGetBufferInfo,
      videoMemberRequest(streamIndex, bufferIndex),
      response: 64
    )
  }

  /// Changes a configured buffer's ID or stream membership in a device configuration change.
  public static func videoSetBufferProperty(
    streamIndex: UInt32,
    bufferIndex: UInt32,
    _ property: VideoBufferProperty
  ) throws -> Self {
    guard streamIndex < videoMaximumStreams else { throw VideoRuntimeError.invalidStreamIndex }
    guard bufferIndex < videoMaximumBuffers else { throw VideoRuntimeError.invalidBufferIndex }
    if case .bufferID(UInt32.max) = property { throw VideoRuntimeError.invalidPayload }
    let fields = property.runtimeFields
    var payload = Data(capacity: 24)
    payload.appendRuntimeInteger(streamIndex)
    payload.appendRuntimeInteger(bufferIndex)
    payload.appendRuntimeInteger(fields.selector)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(fields.value)
    return videoMemberCommand(.videoSetBufferProperty, payload)
  }

  /// Reads the scope, element, owner, range, channels, and selector items of a configured control.
  public static func videoControlInfo(identifier: UInt32) -> Self {
    videoMemberCommand(
      .videoGetControlInfo,
      videoMemberRequest(identifier, 0),
      response: 48 + videoMaximumSelectorItems * (8 + 255)
    )
  }

  /// Changes a slider range or stereo-pan channel pair.
  public static func videoSetControlProperty(
    identifier: UInt32,
    _ property: VideoControlProperty
  ) throws -> Self {
    if case .panningChannels(let pair) = property, pair.left == pair.right {
      throw VideoRuntimeError.invalidControlValue
    }
    return videoMemberCommand(
      .videoSetControlProperty,
      videoMemberProperty(identifier, property.runtimeFields)
    )
  }

  /// Removes items from a selector control by value.
  public static func videoRemoveSelectorItems(identifier: UInt32, values: [UInt32]) throws -> Self {
    guard (1...videoMaximumSelectorItems).contains(values.count), Set(values).count == values.count
    else { throw VideoRuntimeError.invalidControlValue }
    var payload = Data(capacity: 8 + values.count * 4)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(UInt32(values.count))
    for value in values { payload.appendRuntimeInteger(value) }
    return videoMemberCommand(.videoRemoveSelectorItems, payload)
  }

  /// Reads the selector, data types, and owner of a configured custom property.
  public static func videoCustomPropertyInfo(identifier: UInt32) -> Self {
    videoMemberCommand(.videoGetCustomPropertyInfo, videoMemberRequest(identifier, 0), response: 24)
  }

  /// Adds a configured stream or control to the device, or removes it.
  public static func videoSetMemberAttachment(_ member: VideoMember, attached: Bool) throws -> Self
  {
    let fields = member.runtimeFields
    if case .stream(let index) = member, index >= videoMaximumStreams {
      throw VideoRuntimeError.invalidStreamIndex
    }
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(fields.kind)
    payload.appendRuntimeInteger(fields.identifier)
    payload.appendRuntimeInteger(UInt32(attached ? 1 : 0))
    payload.appendRuntimeInteger(UInt32(0))
    return videoMemberCommand(.videoSetMemberAttachment, payload)
  }

  /// Enqueues a completed output entry through `IOUserVideoStream::enqueueOutputBuffer`.
  ///
  /// Unlike ``videoEnqueueOutput(streamIndex:entry:)``, the runtime looks the buffer up with
  /// `GetBufferWithID`, so a buffer outside the stream's buffer list is rejected.
  public static func videoEnqueueOutputBuffer(
    streamIndex: UInt32,
    entry: VideoBufferQueueEntry
  ) throws -> Self {
    guard streamIndex < videoMaximumStreams else { throw VideoRuntimeError.invalidStreamIndex }
    guard entry.bufferIndex < videoMaximumBuffers else {
      throw VideoRuntimeError.invalidBufferIndex
    }
    var payload = Data(capacity: 36)
    payload.appendRuntimeInteger(streamIndex)
    payload.append(videoEntryPayload(entry))
    return videoMemberCommand(.videoEnqueueOutputBuffer, payload)
  }

  /// Reads `IOUserVideoStream::GetMemoryObjectID` for a memory type, whose upper 16 bits are a
  /// category and lower 16 bits an index.
  public static func videoStreamMemoryObjectID(
    streamIndex: UInt32,
    memoryType: UInt32
  ) throws -> Self {
    guard streamIndex < videoMaximumStreams else { throw VideoRuntimeError.invalidStreamIndex }
    return videoMemberCommand(
      .videoGetStreamMemoryObjectID,
      videoMemberRequest(streamIndex, memoryType),
      response: 8
    )
  }

  private static func videoMemberCommand(
    _ opcode: RuntimeOpcode,
    _ payload: Data,
    response: Int = 0
  ) -> Self {
    Self(
      opcode: opcode,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + response
    )
  }

  private static func videoMemberRequest(_ identifier: UInt32, _ argument: UInt32) -> Data {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(argument)
    return payload
  }

  private static func videoMemberProperty(
    _ identifier: UInt32,
    _ fields: (selector: UInt32, value: UInt64)
  ) -> Data {
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(identifier)
    payload.appendRuntimeInteger(fields.selector)
    payload.appendRuntimeInteger(fields.value)
    return payload
  }
}

extension DriverContext {
  /// Reads device state that has no other typed reader.
  public func videoDeviceState() async throws -> VideoDeviceState {
    try VideoDeviceState(runtimePayload: await execute(.videoDeviceState()))
  }

  /// Changes one `IOUserVideoDevice` property.
  public func videoSetDeviceProperty(_ property: VideoDeviceProperty) async throws {
    _ = try await execute(.videoSetDeviceProperty(property))
  }

  /// Sets the device's preferred input or output channel layout.
  public func videoSetPreferredChannelLayout(
    direction: VideoStreamDirection,
    labels: [VideoChannelLabel]
  ) async throws {
    _ = try await execute(.videoSetPreferredChannelLayout(direction: direction, labels: labels))
  }

  /// Reads the state, formats, queues, and buffer list of a configured stream.
  public func videoStreamState(index: UInt32) async throws -> VideoStreamState {
    try VideoStreamState(runtimePayload: await execute(.videoStreamState(index: index)))
  }

  /// Changes one property of a configured stream.
  public func videoSetStreamProperty(index: UInt32, _ property: VideoStreamProperty) async throws {
    _ = try await execute(.videoSetStreamProperty(index: index, property))
  }

  /// Reads the identity and memory of a configured buffer.
  public func videoBufferInfo(
    streamIndex: UInt32,
    bufferIndex: UInt32
  ) async throws -> VideoBufferInfo {
    try VideoBufferInfo(
      runtimePayload: await execute(
        .videoBufferInfo(streamIndex: streamIndex, bufferIndex: bufferIndex)
      )
    )
  }

  /// Changes a configured buffer's ID or stream membership in a device configuration change.
  public func videoSetBufferProperty(
    streamIndex: UInt32,
    bufferIndex: UInt32,
    _ property: VideoBufferProperty
  ) async throws {
    _ = try await execute(
      .videoSetBufferProperty(streamIndex: streamIndex, bufferIndex: bufferIndex, property)
    )
  }

  /// Reads the scope, element, owner, range, channels, and selector items of a configured control.
  public func videoControlInfo(identifier: UInt32) async throws -> VideoControlInfo {
    try VideoControlInfo(runtimePayload: await execute(.videoControlInfo(identifier: identifier)))
  }

  /// Changes a slider range or stereo-pan channel pair.
  public func videoSetControlProperty(
    identifier: UInt32,
    _ property: VideoControlProperty
  ) async throws {
    _ = try await execute(.videoSetControlProperty(identifier: identifier, property))
  }

  /// Removes items from a selector control by value.
  public func videoRemoveSelectorItems(identifier: UInt32, values: [UInt32]) async throws {
    _ = try await execute(.videoRemoveSelectorItems(identifier: identifier, values: values))
  }

  /// Reads the selector, data types, and owner of a configured custom property.
  public func videoCustomPropertyInfo(identifier: UInt32) async throws -> VideoCustomPropertyInfo {
    try VideoCustomPropertyInfo(
      runtimePayload: await execute(.videoCustomPropertyInfo(identifier: identifier))
    )
  }

  /// Adds a configured stream or control to the device, or removes it.
  public func videoSetMemberAttachment(_ member: VideoMember, attached: Bool) async throws {
    _ = try await execute(.videoSetMemberAttachment(member, attached: attached))
  }

  /// Enqueues a completed output entry through `enqueueOutputBuffer`.
  public func videoEnqueueOutputBuffer(
    streamIndex: UInt32,
    entry: VideoBufferQueueEntry
  ) async throws {
    _ = try await execute(.videoEnqueueOutputBuffer(streamIndex: streamIndex, entry: entry))
  }

  /// Reads `IOUserVideoStream::GetMemoryObjectID` for a memory type.
  public func videoStreamMemoryObjectID(
    streamIndex: UInt32,
    memoryType: UInt32
  ) async throws -> UInt32 {
    let payload = try await execute(
      .videoStreamMemoryObjectID(streamIndex: streamIndex, memoryType: memoryType)
    )
    guard payload.count == 8, try payload.readRuntimeInteger(at: 4) as UInt32 == 0 else {
      throw VideoRuntimeError.invalidPayload
    }
    return try payload.readRuntimeInteger(at: 0)
  }
}
