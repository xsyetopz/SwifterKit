import Foundation

extension DriverCommand {
  /// Reports the link status, including wake and forced-notification flags, and active media.
  public static func reportEthernetLink(
    status: EthernetLinkStatus,
    media: EthernetMedia
  ) throws -> Self {
    guard status.isValid else { throw EthernetRuntimeError.invalidLinkStatus }
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(status.rawValue)
    payload.appendRuntimeInteger(media.rawValue)
    return Self(opcode: .networkReportLink, requiredCapabilities: .networking, payload: payload)
  }

  /// Reports link quality through `IOUserNetworkEthernet::reportLinkQuality`.
  public static func reportEthernetLinkQuality(_ quality: EthernetLinkQuality) throws -> Self {
    guard quality.isValid else { throw EthernetRuntimeError.invalidLinkQuality }
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(quality.rawValue)
    return Self(
      opcode: .networkReportLinkQuality,
      requiredCapabilities: .networking,
      payload: payload
    )
  }

  /// Reports bandwidths through `IOUserNetworkEthernet::reportDataBandwidths`.
  public static func reportEthernetDataBandwidths(
    _ bandwidths: EthernetDataBandwidths
  ) throws -> Self {
    guard bandwidths.isValid else { throw EthernetRuntimeError.invalidBandwidths }
    var payload = Data(capacity: 32)
    payload.appendRuntimeInteger(bandwidths.maximumInput)
    payload.appendRuntimeInteger(bandwidths.maximumOutput)
    payload.appendRuntimeInteger(bandwidths.effectiveInput)
    payload.appendRuntimeInteger(bandwidths.effectiveOutput)
    return Self(
      opcode: .networkReportDataBandwidths,
      requiredCapabilities: .networking,
      payload: payload
    )
  }

  /// Adds counters through `IOUserNetworkEthernet::addHardwareCountsWithInterfaceStatistics`.
  public static func addEthernetHardwareCounts(_ counts: EthernetHardwareCounts) -> Self {
    var payload = Data(capacity: 88)
    for field in counts.fields { payload.appendRuntimeInteger(field) }
    return Self(
      opcode: .networkAddHardwareCounts,
      requiredCapabilities: .networking,
      payload: payload
    )
  }

  /// Reports NIC proxy capacities through `IOUserNetworkEthernet::reportNicProxyLimits`.
  public static func reportEthernetNICProxyLimits(_ limits: EthernetNICProxyLimits) -> Self {
    var payload = Data(capacity: 16)
    payload.append(limits.ipv4AddressCount)
    payload.append(limits.ipv6AddressCount)
    payload.appendRuntimeInteger(limits.ipv4KeepAliveCount)
    payload.appendRuntimeInteger(limits.ipv6KeepAliveCount)
    payload.appendRuntimeInteger(limits.wakeUDPPortCount)
    payload.appendRuntimeInteger(limits.wakeTCPPortCount)
    payload.appendRuntimeInteger(limits.resourceRecordCount)
    payload.append(limits.maximumMDNSDomainLength)
    payload.append(limits.ethernetAddressCount)
    payload.appendRuntimeInteger(limits.resourceRecordBufferSize)
    return Self(
      opcode: .networkReportNICProxyLimits,
      requiredCapabilities: .networking,
      payload: payload
    )
  }

  /// Enables or disables the configured packet poller.
  public static func setEthernetPolling(enabled: Bool) -> Self {
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(enabled ? UInt32(1) : UInt32(0))
    return Self(opcode: .networkSetPolling, requiredCapabilities: .networking, payload: payload)
  }

  /// Reconfigures the packet poller through `IOUserNetworkPacketPoller::setPollerParameters`.
  public static func setEthernetPollerParameters(
    dataRate: UInt64,
    pollInterval: UInt64 = 0
  ) throws -> Self {
    guard EthernetPacketPolling(dataRate: dataRate, pollInterval: pollInterval).isValid else {
      throw EthernetRuntimeError.invalidPollingParameters
    }
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(dataRate)
    payload.appendRuntimeInteger(pollInterval)
    return Self(
      opcode: .networkSetPollerParameters,
      requiredCapabilities: .networking,
      payload: payload
    )
  }
}

extension DriverContext {
  /// Reports the link status, including wake and forced-notification flags, and active media.
  public func reportEthernetLink(status: EthernetLinkStatus, media: EthernetMedia) async throws {
    _ = try await execute(.reportEthernetLink(status: status, media: media))
  }

  /// Reports link quality to the networking stack.
  public func reportEthernetLinkQuality(_ quality: EthernetLinkQuality) async throws {
    _ = try await execute(.reportEthernetLinkQuality(quality))
  }

  /// Reports maximum and effective bandwidths to the networking stack.
  public func reportEthernetDataBandwidths(_ bandwidths: EthernetDataBandwidths) async throws {
    _ = try await execute(.reportEthernetDataBandwidths(bandwidths))
  }

  /// Adds hardware counters to the interface statistics. Reset them after this returns.
  public func addEthernetHardwareCounts(_ counts: EthernetHardwareCounts) async throws {
    _ = try await execute(.addEthernetHardwareCounts(counts))
  }

  /// Reports NIC proxy capacities. Requires ``EthernetFeatureFlags/nicProxy``.
  public func reportEthernetNICProxyLimits(_ limits: EthernetNICProxyLimits) async throws {
    _ = try await execute(.reportEthernetNICProxyLimits(limits))
  }

  /// Enables or disables the configured packet poller.
  public func setEthernetPolling(enabled: Bool) async throws {
    _ = try await execute(.setEthernetPolling(enabled: enabled))
  }

  /// Reconfigures the packet poller's data rate and interval.
  public func setEthernetPollerParameters(dataRate: UInt64, pollInterval: UInt64 = 0) async throws {
    _ = try await execute(
      .setEthernetPollerParameters(dataRate: dataRate, pollInterval: pollInterval)
    )
  }
}
