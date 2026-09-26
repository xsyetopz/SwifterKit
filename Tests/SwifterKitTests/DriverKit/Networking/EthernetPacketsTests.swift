import Foundation
import Testing

@testable import SwifterKit

@Suite
struct EthernetPacketsTests {
  @Test
  func decodesTransmitMetadata() throws {
    var metadata = Data()
    metadata.appendRuntimeInteger(UInt32(16))  // dataOffset
    metadata.appendRuntimeInteger(UInt32(0b1110_0101))  // flags
    metadata.appendRuntimeInteger(EthernetServiceClass.interactiveVoice.rawValue)
    metadata.appendRuntimeInteger(UInt32(77))  // traceID
    metadata.appendRuntimeInteger(UInt32(0x0009))  // checksum flags
    metadata.appendRuntimeInteger(UInt16(34))
    metadata.appendRuntimeInteger(UInt16(50))
    metadata.appendRuntimeInteger(UInt32(0x0010_0008))  // offload flags
    metadata.appendRuntimeInteger(UInt32(0x0010_0000))  // TSO flags
    metadata.appendRuntimeInteger(UInt16(1_448))
    metadata.appendRuntimeInteger(UInt16(1_460))
    metadata.appendRuntimeInteger(UInt16(42))  // VLAN
    metadata.append(contentsOf: [14, 0])
    metadata.appendRuntimeInteger(UInt64(1_000))
    metadata.appendRuntimeInteger(UInt64(2_000))
    metadata.appendRuntimeInteger(UInt64(4_096))
    metadata.appendRuntimeInteger(UInt64(0x8000_0000))
    #expect(metadata.count == 72)
    var payload = Data()
    for value: UInt32 in [2, 5, 2, 74] { payload.appendRuntimeInteger(value) }
    payload.append(metadata)
    payload.append(contentsOf: [9, 8])
    guard
      case .transmit(let request) = try DriverEvent(type: 0x0900, payload: [UInt8](payload))
        .ethernet()
    else {
      Issue.record("expected a transmit")
      return
    }
    #expect(request.frame == Data([9, 8]))
    let value = request.metadata
    #expect(value.dataOffset == 16 && value.linkHeaderLength == 14)
    #expect(value.serviceClass == .interactiveVoice && value.traceID == 77)
    #expect(value.isLinkMulticast && !value.isLinkBroadcast && value.isTimestampRequested)
    #expect(!value.isBackgroundTraffic && !value.isRealtimeTraffic)
    #expect(value.timestamp == 1_000 && value.expiryTime == 2_000 && value.vlanTag == 42)
    #expect(value.checksumFlags == [.partial, .tcpIPv4])
    #expect(value.checksumStart == 34 && value.checksumStuffOffset == 50)
    #expect(value.tsoFlags == .ipv4 && value.tsoSegmentSize == 1_448)
    #expect(value.maximumSegmentSize == 1_460 && value.offloadFlags == 0x0010_0008)
    #expect(value.memorySegmentOffset == 4_096 && value.dataIOVirtualAddress == 0x8000_0000)

    // Receive-only flag bits and a short metadata block are rejected.
    var bad = payload
    bad[16 + 5] = 0x01
    #expect(throws: EthernetRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0900, payload: [UInt8](bad)).ethernet()
    }
    #expect(throws: EthernetRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0900, payload: [2, 0, 0, 0, 5, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 7])
        .ethernet()
    }
  }

  @Test
  func encodesReceiveBatchWithMetadata() throws {
    let metadata = EthernetReceiveMetadata(
      dataOffset: 8,
      isLinkMulticast: true,
      checksumFlags: [.ipChecked, .ipValid],
      checksumValue: 0xBEEF,
      lroFlags: .ipv4,
      lroSegmentCount: 3,
      timestamp: 5,
      vlanTag: 9,
      isWakePacket: true,
      traceEvent: 4
    )
    let command = try DriverCommand.ethernetReceive(frame: Data([1, 2]), metadata: metadata)
    #expect(command.opcode == 0x0920)
    var expected = Data()
    for value: UInt32 in [1, 0, 2, 8, 0b1111_1010_0001, 0x0300] {
      expected.appendRuntimeInteger(value)
    }
    expected.appendRuntimeInteger(UInt16(0xBEEF))
    expected.appendRuntimeInteger(UInt16(9))
    expected.append(contentsOf: [14, 1, 3, 0])
    expected.appendRuntimeInteger(UInt32(4))
    expected.appendRuntimeInteger(UInt32(0))
    expected.appendRuntimeInteger(UInt64(5))
    expected.append(contentsOf: [1, 2])
    #expect(command.payload == expected)

    #expect(throws: EthernetRuntimeError.invalidPacketMetadata) {
      try DriverCommand.ethernetReceive(
        frame: Data([1]),
        metadata: EthernetReceiveMetadata(lroFlags: .ipv6)
      )
    }
    #expect(throws: EthernetRuntimeError.invalidBatch) {
      try DriverCommand.ethernetReceive(frames: [])
    }
    #expect(throws: EthernetRuntimeError.frameTooLarge) {
      try DriverCommand.ethernetReceive(frames: [
        EthernetReceivedFrame(frame: Data(repeating: 0, count: 65_449))
      ])
    }
    _ = try DriverCommand.ethernetReceive(frames: [
      EthernetReceivedFrame(frame: Data(repeating: 0, count: 65_448))
    ])
  }

  @Test
  func encodesCompletionsQueuesAndInterfaceCommands() throws {
    let batch = try DriverCommand.completeEthernetTransmits([
      EthernetTransmitCompletion(requestID: 3, status: -1, timestamp: 7, traceEvent: 2)
    ])
    #expect(batch.opcode == 0x0921)
    var expected = Data()
    for value: UInt32 in [1, 0, 3, 0xFFFF_FFFF, 0x0420, 2] { expected.appendRuntimeInteger(value) }
    expected.appendRuntimeInteger(UInt64(7))
    #expect(batch.payload == expected)
    #expect(throws: EthernetRuntimeError.invalidBatch) {
      try DriverCommand.completeEthernetTransmits([
        EthernetTransmitCompletion(requestID: 3), EthernetTransmitCompletion(requestID: 3),
      ])
    }

    let queue = DriverCommand.setEthernetQueueEnabled(.receiveSubmission, enabled: true)
    #expect(queue.opcode == 0x0922 && queue.payload == Data([2, 0, 0, 0, 1, 0, 0, 0]))
    #expect(DriverCommand.purgeEthernetTransmitQueue().opcode == 0x0923)
    #expect(DriverCommand.serviceEthernetTransmitQueue().payload == Data(count: 4))
    let answer = DriverCommand.completeEthernetInterfaceCommand(requestID: 6, status: 0)
    #expect(answer.opcode == 0x0925 && answer.payload == Data([6, 0, 0, 0, 0, 0, 0, 0]))

    var event = Data()
    for value: UInt32 in [16, 6, 0, 32] { event.appendRuntimeInteger(value) }
    event.append(contentsOf: Array("en5".utf8) + [UInt8](repeating: 0, count: 13))
    event.appendRuntimeInteger(UInt64(0x42))
    event.appendRuntimeInteger(UInt64(128))
    guard
      case .interfaceCommand(let request) = try DriverEvent(type: 0x0900, payload: [UInt8](event))
        .ethernet()
    else {
      Issue.record("expected an interface command")
      return
    }
    #expect(request.requestID == 6 && request.interfaceName == "en5")
    #expect(request.command == 0x42 && request.length == 128)
  }

  @Test
  func nativeRuntimeMatchesPacketContract() throws {
    let root = checkedInNativeSources
    func source(_ name: String) throws -> String {
      try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }
    let protocolHeader = try source("SwifterKitRuntimeProtocol.h")
    #expect(
      protocolHeader.contains(
        "static_assert(sizeof(SwifterKitNetworkTransmitMetadata) == "
          + "kSwifterKitNetworkTransmitMetadataSize);"
      )
    )
    #expect(protocolHeader.contains("static_assert(sizeof(SwifterKitNetworkReceivePacket) == 40);"))
    let schema = try source(RuntimeSchemaHeader.fileName)
    #expect(schema.contains("kSwifterKitNetworkTransmitMetadataSize = 72;"))
    #expect(
      schema.contains("kSwifterKitNetworkMaximumBatch = \(DriverCommand.ethernetMaximumBatch);")
    )
    #expect(schema.contains("kSwifterKitNetworkTransmitFlags = 0x00FF;"))
    #expect(schema.contains("kSwifterKitNetworkReceiveFlags = 0x0FA1;"))
    #expect(schema.contains("kSwifterKitNetworkCompletionFlags = 0x0420;"))
    #expect(schema.contains("kSwifterKitNetworkRxChecksumFlags = 0x0F00;"))
    #expect(schema.contains("kSwifterKitNetworkLROFlags = 0x0003;"))
    #expect(schema.contains("kSwifterKitNetworkEventInterfaceCommand = 16;"))
    #expect(schema.contains("kSwifterKitNetworkQueueCount = 4;"))
    let metadata = try source("SwifterKitRuntimeNetworkMetadata.h")
    #expect(metadata.contains("__builtin_available(driverkit 23.0, *)"))
    #expect(metadata.contains("__builtin_available(driverkit 24.0, *)"))
    #expect(metadata.contains("packet->getPacketBufferPool()"))
    let control = try source("SwifterKitRuntimeNetworkControl.cpp")
    #expect(control.contains("kInterfaceCommandTimeoutNanoseconds = 2'000'000'000ULL"))
    #expect(control.contains("ivars->networkCommandID = 0;"))
    #expect(control.contains("return kIOReturnUnsupported;"))
    // A failed transmit returns through the completion queue instead of being freed.
    let packets = try source("SwifterKitRuntimeNetworkPackets.cpp")
    #expect(
      packets.contains("SwifterKitCompleteTransmitPacket(packet, completion->status, 0, 0, 0);")
    )
    #expect(!packets.contains(": kIOReturnAborted;"))
  }
}
