import Foundation
import Testing

@testable import SwifterKit

@Suite
struct NetworkingCapabilitiesTests {
  @Test
  func encodesLinkQualityBandwidthAndStatusCommands() throws {
    let status = try DriverCommand.reportEthernetLink(
      status: EthernetLinkStatus.active.wakingOnSameNetwork.forcingNotification,
      media: .base1000T
    )
    #expect(status.opcode == 0x0902)
    #expect(status.payload == Data([7, 0, 0, 128, 48, 0, 0, 0]))

    let quality = try DriverCommand.reportEthernetLinkQuality(.off)
    #expect(quality.opcode == 0x0910)
    #expect(quality.requiredCapabilities == .networking)
    #expect(quality.payload == Data([254, 255, 255, 255]))

    let rates = try DriverCommand.reportEthernetDataBandwidths(
      EthernetDataBandwidths(
        maximumInput: 1,
        maximumOutput: 2,
        effectiveInput: 1,
        effectiveOutput: 0
      )
    )
    #expect(rates.opcode == 0x0911)
    #expect(rates.payload.count == 32)
    #expect(rates.payload[8] == 2)
    #expect(rates.payload[16] == 1)
  }

  @Test
  func encodesCountersProxyLimitsAndPollerCommands() throws {
    var counts = EthernetHardwareCounts()
    counts.packetsIn = 3
    counts.noProtocol = 9
    let add = DriverCommand.addEthernetHardwareCounts(counts)
    #expect(add.opcode == 0x0912)
    #expect(add.payload.count == 88)
    #expect(add.payload.first == 3)
    #expect(add.payload[80] == 9)

    var limits = EthernetNICProxyLimits()
    limits.ipv4AddressCount = 1
    limits.ipv6AddressCount = 2
    limits.ipv4KeepAliveCount = 3
    limits.resourceRecordCount = 0x0102
    limits.maximumMDNSDomainLength = 5
    limits.ethernetAddressCount = 6
    limits.resourceRecordBufferSize = 0x0708
    let proxy = DriverCommand.reportEthernetNICProxyLimits(limits)
    #expect(proxy.opcode == 0x0913)
    #expect(proxy.payload == Data([1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 2, 1, 5, 6, 8, 7]))

    #expect(DriverCommand.setEthernetPolling(enabled: true).payload == Data([1, 0, 0, 0]))
    #expect(DriverCommand.setEthernetPolling(enabled: false).opcode == 0x0914)
    let parameters = try DriverCommand.setEthernetPollerParameters(dataRate: 1, pollInterval: 2)
    #expect(parameters.opcode == 0x0915)
    #expect(parameters.payload == Data([1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]))
  }

  @Test
  func rejectsInvalidReports() {
    #expect(throws: EthernetRuntimeError.invalidLinkStatus) {
      try DriverCommand.reportEthernetLink(status: EthernetLinkStatus(rawValue: 0), media: .none)
    }
    #expect(throws: EthernetRuntimeError.invalidLinkQuality) {
      try DriverCommand.reportEthernetLinkQuality(EthernetLinkQuality(rawValue: 101))
    }
    #expect(throws: EthernetRuntimeError.invalidBandwidths) {
      try DriverCommand.reportEthernetDataBandwidths(
        EthernetDataBandwidths(
          maximumInput: 1,
          maximumOutput: 1,
          effectiveInput: 2,
          effectiveOutput: 1
        )
      )
    }
    #expect(throws: EthernetRuntimeError.invalidPollingParameters) {
      try DriverCommand.setEthernetPollerParameters(dataRate: 0)
    }
    #expect(throws: EthernetRuntimeError.invalidPollingParameters) {
      try DriverCommand.setEthernetPollerParameters(dataRate: 1, pollInterval: 1_000_000_001)
    }
  }

  @Test
  func decodesAssistPollingTapAndProxyEvents() throws {
    let assists = event(kind: 12, value: 0x0400_0001, data: [0x01, 0, 0, 0x04])
    #expect(
      try assists.ethernet()
        == .hardwareAssistsChanged(
          assists: [.transmitIPv4HeaderChecksum, .wakeOnMagicPacket],
          mask: [.transmitIPv4HeaderChecksum, .wakeOnMagicPacket]
        )
    )
    #expect(try event(kind: 13, value: 1).ethernet() == .polling(true))
    #expect(try event(kind: 14, value: 3).ethernet() == .packetTap([.input, .output]))

    var proxy = [UInt8](repeating: 0, count: 84)
    proxy[0] = 84
    proxy.replaceSubrange(4..<10, with: [2, 3, 4, 5, 6, 7])
    proxy[10] = 0x40
    let decoded = try event(kind: 15, value: 84, data: proxy).ethernet()
    guard case .nicProxyConfiguration(let configuration) = decoded else {
      Issue.record("expected NIC proxy data")
      return
    }
    #expect(configuration.hardwareAddress == EthernetAddress(2, 3, 4, 5, 6, 7))
    #expect(configuration.flags == 0x40)
    #expect(configuration.data.count == 84)
  }

  @Test
  func rejectsMalformedNewEvents() {
    let invalid = [
      event(kind: 12, value: 2, data: [1, 0, 0, 0]), event(kind: 12, value: 0),
      event(kind: 13, value: 2), event(kind: 14, value: 4),
      event(kind: 15, value: 4, data: [4, 0, 0, 0]),
      event(kind: 15, value: 84, data: [80] + [UInt8](repeating: 0, count: 83)),
    ]
    for value in invalid {
      #expect(throws: EthernetRuntimeError.invalidPayload) { try value.ethernet() }
    }
    for kind: UInt32 in [0, 17] {
      #expect(throws: EthernetRuntimeError.invalidEventKind(kind)) {
        try event(kind: kind, value: 0).ethernet()
      }
    }
  }

  @Test
  func typedCapabilitiesMatchNetworkingDriverKit() {
    #expect(EthernetHardwareAssists.tso4.rawValue == 0x0020_0000)
    #expect(EthernetHardwareAssists.lroSegmentCount.rawValue == 0x4000_0000)
    #expect(EthernetHardwareAssists.all.rawValue == 0x7F62_0007)
    #expect(EthernetFeatureFlags.all.rawValue == 0x0F02_0000)
    #expect(EthernetPacketPoolFlags.all.rawValue == 0x2000_1602)
    #expect(EthernetLinkQuality.good.rawValue == 100)
    let config = EthernetDeviceConfiguration(
      hardwareAddress: EthernetAddress(2, 3, 4, 5, 6, 7),
      hardwareAssists: EthernetHardwareAssists.lro.rawValue
    )
    #expect(config.assists == .lro)
    #expect(config.minimumTransferUnit == 68)
    #expect(config.receivePacketCount == nil)
  }

  private func event(kind: UInt32, value: UInt32, data: [UInt8] = []) -> DriverEvent {
    var payload = Data()
    payload.appendRuntimeInteger(kind)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(value)
    payload.appendRuntimeInteger(UInt32(data.count))
    payload.append(contentsOf: data)
    return DriverEvent(type: 0x0900, payload: [UInt8](payload))
  }
}
