import Foundation

extension DriverExtensionGenerator {
  /// Renders the box and clock-device tables that `StartAudioObjects` creates objects from.
  static func audioTopologyDeclarations(_ audio: AudioDeviceConfiguration?) -> String {
    let boxes = audio?.boxes ?? []
    let clocks = audio?.clockDevices ?? []
    let boxRows = boxes.map { box in
      let mask = box.clockDevices.reduce(UInt32(0)) { $0 | (1 << $1) }
      return "    {\(cString(box.uid)), \(cString(box.name)), \(box.transport.rawValue), "
        + "\(box.isAcquirable), \(box.isAcquired), \(box.hasAudio), \(box.hasMIDI), "
        + "\(box.hasVideo), \(box.isProtected), \(box.ownsDevice), \(mask)}"
    }.joined(separator: ",\n")
    var rateStart = 0
    let clockRows = clocks.map { clock in
      defer { rateStart += clock.sampleRates.count }
      let restore = clock.wantsControlsRestored.map { $0 ? 1 : 0 } ?? -1
      return "    {\(cString(clock.deviceUID)), \(cString(clock.modelUID)), "
        + "\(cString(clock.manufacturerUID)), \(cString(clock.name)), "
        + "\(clock.transport.rawValue), \(clock.supportsPrewarming), "
        + "\(clock.zeroTimestampPeriod), \(rateStart), \(clock.sampleRates.count), "
        + "\(clock.initialSampleRate), \(clock.clockDomain), \(clock.clockAlgorithm.rawValue), "
        + "\(clock.clockIsStable), \(clock.isHidden), \(clock.inputLatency), "
        + "\(clock.outputLatency), \(restore)}"
    }.joined(separator: ",\n")
    let boxCapacity = max(boxes.count, 1)
    let rates = clocks.flatMap(\.sampleRates).map { String($0) }.joined(separator: ", ")
    return """

      struct SwifterKitAudioBoxConfiguration {
          const char* uid;
          const char* name;
          uint32_t transport;
          bool isAcquirable;
          bool isAcquired;
          bool hasAudio;
          bool hasMIDI;
          bool hasVideo;
          bool isProtected;
          bool ownsDevice;
          uint32_t clockMask;
      };
      struct SwifterKitAudioClockConfiguration {
          const char* deviceUID;
          const char* modelUID;
          const char* manufacturerUID;
          const char* name;
          uint32_t transport;
          bool supportsPrewarming;
          uint32_t zeroTimestampPeriod;
          uint32_t rateStart;
          uint32_t rateCount;
          double initialSampleRate;
          uint32_t clockDomain;
          uint32_t clockAlgorithm;
          bool clockIsStable;
          bool isHidden;
          uint32_t inputLatency;
          uint32_t outputLatency;
          int32_t wantsControlsRestored;
      };
      static constexpr SwifterKitAudioBoxConfiguration kSwifterKitAudioBoxes[\(boxCapacity)] = {
      \(boxRows)
      };
      static constexpr uint32_t kSwifterKitAudioBoxCount = \(boxes.count);
      static constexpr SwifterKitAudioClockConfiguration
          kSwifterKitAudioClockDevices[\(max(clocks.count, 1))] = {
      \(clockRows)
      };
      static constexpr uint32_t kSwifterKitAudioClockDeviceCount = \(clocks.count);
      static constexpr double kSwifterKitAudioClockSampleRates[\(max(rateStart, 1))] = {\(rates)};
      """
  }

  static func isValid(audioTopology value: AudioDeviceConfiguration) -> Bool {
    let limit = Int(AudioObjectTarget.maximumTableCount)
    guard value.boxes.count <= limit, value.clockDevices.count <= limit else { return false }
    let strings =
      value.boxes.flatMap { [$0.uid, $0.name] }
      + value.clockDevices.flatMap { [$0.deviceUID, $0.modelUID, $0.manufacturerUID, $0.name] }
    let uids = [value.deviceUID] + value.boxes.map(\.uid) + value.clockDevices.map(\.deviceUID)
    let owned = value.boxes.flatMap(\.clockDevices)
    guard strings.allSatisfy({ !$0.isEmpty && !$0.contains("\0") && $0.utf8.count < 256 }),
      Set(uids).count == uids.count, value.boxes.filter(\.ownsDevice).count <= 1,
      Set(owned).count == owned.count, owned.allSatisfy({ Int($0) < value.clockDevices.count })
    else { return false }
    return value.clockDevices.allSatisfy { clock in
      (1...16).contains(clock.sampleRates.count)
        && Set(clock.sampleRates).count == clock.sampleRates.count
        && clock.sampleRates.allSatisfy { $0.isFinite && (8_000...768_000).contains($0) }
        && clock.sampleRates.contains(clock.initialSampleRate)
        && (16...1_048_576).contains(clock.zeroTimestampPeriod)
        && clock.clockAlgorithm.rawValue != 0
    }
  }
}
