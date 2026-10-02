import Foundation

extension DriverCommand {
  /// The most frames one receive or completion batch carries.
  public static let ethernetMaximumBatch = RuntimeNetworkLimits.maximumBatch

  /// Injects hardware-received frames, each with its packet metadata, in one batch.
  ///
  /// The extension takes an empty packet for every frame before it copies any. A batch the
  /// receive submission queue cannot supply delivers nothing and fails with
  /// `kIOReturnNoResources`.
  public static func ethernetReceive(frames: [EthernetReceivedFrame]) throws -> Self {
    guard (1...ethernetMaximumBatch).contains(frames.count) else {
      throw EthernetRuntimeError.invalidBatch
    }
    var payload = Data(capacity: 8 + frames.reduce(0) { $0 + 40 + $1.frame.count })
    payload.appendRuntimeInteger(UInt32(frames.count))
    payload.appendRuntimeInteger(UInt32(0))
    for entry in frames {
      guard !entry.frame.isEmpty else { throw EthernetRuntimeError.emptyFrame }
      guard entry.metadata.isValid else { throw EthernetRuntimeError.invalidPacketMetadata }
      payload.append(entry.metadata.runtimeHeader(length: entry.frame.count))
      payload.append(entry.frame)
    }
    let limit =
      RuntimeSchema.maximumMessageSize - RuntimeSchema.headerSize - RuntimeSchema.commandHeaderSize
    guard payload.count <= limit else { throw EthernetRuntimeError.frameTooLarge }
    return Self(opcode: .networkReceivePackets, requiredCapabilities: .networking, payload: payload)
  }

  /// Injects one hardware-received frame with its packet metadata.
  public static func ethernetReceive(frame: Data, metadata: EthernetReceiveMetadata) throws -> Self
  { try ethernetReceive(frames: [EthernetReceivedFrame(frame: frame, metadata: metadata)]) }

  /// Completes several transmits at once. Each packet records its status, timestamp, and trace
  /// event before the batch returns through the transmit completion queue.
  public static func completeEthernetTransmits(
    _ completions: [EthernetTransmitCompletion]
  ) throws -> Self {
    let identifiers = Set(completions.map(\.requestID))
    guard (1...ethernetMaximumBatch).contains(completions.count),
      identifiers.count == completions.count, !identifiers.contains(0)
    else { throw EthernetRuntimeError.invalidBatch }
    var payload = Data(capacity: 8 + 24 * completions.count)
    payload.appendRuntimeInteger(UInt32(completions.count))
    payload.appendRuntimeInteger(UInt32(0))
    for completion in completions {
      var flags: UInt32 =
        completion.timestamp == nil ? 0 : RuntimeNetworkPacketFlag.hasTimestamp.rawValue
      if completion.traceEvent != nil { flags |= RuntimeNetworkPacketFlag.hasTraceEvent.rawValue }
      payload.appendRuntimeInteger(completion.requestID)
      payload.appendRuntimeInteger(completion.status)
      payload.appendRuntimeInteger(flags)
      payload.appendRuntimeInteger(completion.traceEvent ?? 0)
      payload.appendRuntimeInteger(completion.timestamp ?? 0)
    }
    return Self(
      opcode: .networkCompleteTransmits,
      requiredCapabilities: .networking,
      payload: payload
    )
  }

  /// Enables or disables one packet queue (`IOUserNetworkPacketQueue::setEnable`).
  public static func setEthernetQueueEnabled(_ queue: EthernetPacketQueue, enabled: Bool) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(queue.rawValue)
    payload.appendRuntimeInteger(enabled ? UInt32(1) : UInt32(0))
    return Self(
      opcode: .networkSetQueueEnabled,
      requiredCapabilities: .networking,
      payload: payload
    )
  }

  /// Drops frames still waiting in the transmit submission queue
  /// (`IOUserNetworkTxSubmissionQueue::purgePackets`).
  public static func purgeEthernetTransmitQueue() -> Self {
    Self(
      opcode: .networkPurgeTransmitQueue,
      requiredCapabilities: .networking,
      payload: Data(count: 4)
    )
  }

  /// Moves frames waiting in the transmit submission queue to Swift now, as the queue's
  /// data-available handler and each poll do.
  public static func serviceEthernetTransmitQueue() -> Self {
    Self(
      opcode: .networkServiceTransmitQueue,
      requiredCapabilities: .networking,
      payload: Data(count: 4)
    )
  }

  /// Answers an ``EthernetInterfaceCommand`` with an `IOReturn` status.
  public static func completeEthernetInterfaceCommand(requestID: UInt32, status: Int32) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(status)
    return Self(
      opcode: .networkCompleteInterfaceCommand,
      requiredCapabilities: .networking,
      payload: payload
    )
  }
}

extension DriverContext {
  /// Injects hardware-received frames, each with its packet metadata, in one batch.
  public func ethernetReceive(frames: [EthernetReceivedFrame]) async throws {
    _ = try await execute(.ethernetReceive(frames: frames))
  }

  /// Injects one hardware-received frame with its packet metadata.
  public func ethernetReceive(frame: Data, metadata: EthernetReceiveMetadata) async throws {
    _ = try await execute(.ethernetReceive(frame: frame, metadata: metadata))
  }

  /// Completes several transmits at once.
  /// The runtime returns the packets through `IOUserNetworkPacketQueue::enqueuePackets`.
  public func completeEthernetTransmits(_ completions: [EthernetTransmitCompletion]) async throws {
    _ = try await execute(.completeEthernetTransmits(completions))
  }

  /// Enables or disables one packet queue.
  public func setEthernetQueueEnabled(_ queue: EthernetPacketQueue, enabled: Bool) async throws {
    _ = try await execute(.setEthernetQueueEnabled(queue, enabled: enabled))
  }

  /// Drops frames still waiting in the transmit submission queue.
  public func purgeEthernetTransmitQueue() async throws {
    _ = try await execute(.purgeEthernetTransmitQueue())
  }

  /// Moves frames waiting in the transmit submission queue to Swift now.
  public func serviceEthernetTransmitQueue() async throws {
    _ = try await execute(.serviceEthernetTransmitQueue())
  }

  /// Answers an ``EthernetInterfaceCommand`` with an `IOReturn` status.
  /// The runtime holds `IOUserNetworkEthernet::processInterfaceCommand` until this answer arrives.
  public func completeEthernetInterfaceCommand(requestID: UInt32, status: Int32) async throws {
    _ = try await execute(.completeEthernetInterfaceCommand(requestID: requestID, status: status))
  }
}
