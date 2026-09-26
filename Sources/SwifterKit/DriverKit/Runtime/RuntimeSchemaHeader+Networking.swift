/// Renders the networking schema declarations under the native names the extension uses.
extension RuntimeSchemaHeader {
  static func networkSections() -> [[String]] {
    let network = RuntimeNetworkLimits.self
    let flag = RuntimeNetworkPacketFlag.self
    return [
      joined(
        constants(
          "uint32_t",
          [
            ("kSwifterKitNetworkMaximumBatch", "\(network.maximumBatch)"),
            ("kSwifterKitNetworkEventHeaderSize", "\(network.eventHeaderSize)"),
            ("kSwifterKitNetworkTransmitMetadataSize", "\(network.transmitMetadataSize)"),
            ("kSwifterKitNetworkQueueCount", "\(network.queueCount)"),
          ]
        ),
        constants(
          "uint64_t",
          [("kSwifterKitEthernetMaximumPollInterval", "\(network.maximumPollInterval)ULL")]
        ),
        constants(
          "uint32_t",
          [
            ("kSwifterKitEthernetTapInput", "\(RuntimeNetworkTapMode.input.rawValue)"),
            ("kSwifterKitEthernetTapOutput", "\(RuntimeNetworkTapMode.output.rawValue)"),
          ]
        )
      ), constants("kSwifterKitNetworkEvent", type: "uint32_t", RuntimeNetworkEventKind.allCases),
      constants(
        "uint32_t",
        flag.allCases.map {
          ("kSwifterKitNetworkPacket" + nativeName($0), hex($0.rawValue, digits: 4))
        } + [
          ("kSwifterKitNetworkTransmitFlags", hex(flag.transmit, digits: 4)),
          ("kSwifterKitNetworkReceiveFlags", hex(flag.receive, digits: 4)),
          ("kSwifterKitNetworkCompletionFlags", hex(flag.completion, digits: 4)),
          ("kSwifterKitNetworkRxChecksumFlags", hex(flag.receiveChecksum, digits: 4)),
          ("kSwifterKitNetworkLROFlags", hex(flag.largeReceiveOffload, digits: 4)),
        ]
      ),
    ]
  }
}
