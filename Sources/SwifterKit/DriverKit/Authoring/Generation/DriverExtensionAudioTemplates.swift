import Foundation

extension DriverExtensionGenerator {
  static func audioConfigurationDeclarations(_ configuration: DriverConfiguration) -> String {
    let declarations = """
      struct SwifterKitAudioFormatConfiguration {
          double sampleRate;
          uint32_t formatID;
          uint32_t formatFlags;
          uint32_t bytesPerPacket;
          uint32_t framesPerPacket;
          uint32_t bytesPerFrame;
          uint32_t channelsPerFrame;
          uint32_t bitsPerChannel;
      };
      struct SwifterKitAudioStreamConfiguration {
          uint32_t direction;
          const char* name;
          uint32_t formatStart;
          uint32_t formatCount;
          uint32_t initialFormatIndex;
          uint32_t ringBufferFrameCapacity;
      };

      """ + mediaControlStructDeclarations(family: "Audio")

    guard let audio = configuration.audioDevice else {
      return declarations + """
        static constexpr char kSwifterKitAudioDeviceUID[] = "";
        static constexpr char kSwifterKitAudioModelUID[] = "";
        static constexpr char kSwifterKitAudioManufacturerUID[] = "";
        static constexpr char kSwifterKitAudioDeviceName[] = "";
        static constexpr uint32_t kSwifterKitAudioTransport = 0;
        static constexpr bool kSwifterKitAudioSupportsPrewarming = false;
        static constexpr uint32_t kSwifterKitAudioZeroTimestampPeriod = 0;
        static constexpr double kSwifterKitAudioSampleRates[] = {0};
        static constexpr uint32_t kSwifterKitAudioSampleRateCount = 0;
        static constexpr double kSwifterKitAudioInitialSampleRate = 0;
        static constexpr SwifterKitAudioFormatConfiguration kSwifterKitAudioFormats[1] = {};
        static constexpr SwifterKitAudioStreamConfiguration kSwifterKitAudioStreams[1] = {};
        static constexpr uint32_t kSwifterKitAudioStreamCount = 0;

        """ + mediaEmptyControlTables(family: "Audio") + audioTopologyDeclarations(nil)
    }

    let formats = audio.streams.flatMap(\.formats).map { format in
      "    {\(format.sampleRate), \(format.formatID.rawValue), \(format.formatFlags.rawValue), "
        + "\(format.bytesPerPacket), \(format.framesPerPacket), \(format.bytesPerFrame), "
        + "\(format.channelsPerFrame), \(format.bitsPerChannel)}"
    }.joined(separator: ",\n")
    var formatStart = 0
    let streams = audio.streams.map { stream in
      defer { formatStart += stream.formats.count }
      return "    {\(stream.direction.rawValue), \(cString(stream.name)), \(formatStart), "
        + "\(stream.formats.count), \(stream.initialFormatIndex), "
        + "\(stream.ringBufferFrameCapacity)}"
    }.joined(separator: ",\n")

    let sampleRates = audio.sampleRates.map { String($0) }.joined(separator: ", ")

    return declarations + """
      static constexpr char kSwifterKitAudioDeviceUID[] = \(cString(audio.deviceUID));
      static constexpr char kSwifterKitAudioModelUID[] = \(cString(audio.modelUID));
      static constexpr char kSwifterKitAudioManufacturerUID[] =
          \(cString(audio.manufacturerUID));
      static constexpr char kSwifterKitAudioDeviceName[] = \(cString(audio.name));
      static constexpr uint32_t kSwifterKitAudioTransport = \(audio.transport.rawValue);
      static constexpr bool kSwifterKitAudioSupportsPrewarming =
          \(audio.supportsPrewarming ? "true" : "false");
      static constexpr uint32_t kSwifterKitAudioZeroTimestampPeriod =
          \(audio.zeroTimestampPeriod);
      static constexpr double kSwifterKitAudioSampleRates[] = {\(sampleRates)};
      static constexpr uint32_t kSwifterKitAudioSampleRateCount = \(audio.sampleRates.count);
      static constexpr double kSwifterKitAudioInitialSampleRate = \(audio.initialSampleRate);
      static constexpr SwifterKitAudioFormatConfiguration kSwifterKitAudioFormats[] = {
      \(formats)
      };
      static constexpr SwifterKitAudioStreamConfiguration kSwifterKitAudioStreams[] = {
      \(streams)
      };
      static constexpr uint32_t kSwifterKitAudioStreamCount = \(audio.streams.count);

      """
      + mediaControlTables(
        family: "Audio",
        controls: audio.controls.map(mediaControlRow),
        customProperties: audio.customProperties.map {
          MediaCustomPropertyTableRow(
            identifier: $0.identifier,
            selector: $0.selector,
            scope: $0.scope.rawValue,
            element: $0.element,
            isSettable: $0.isSettable,
            values: $0.values
          )
        }
      ) + audioTopologyDeclarations(audio)
  }

  static func mediaControlRow(_ control: AudioControlConfiguration) -> MediaControlTableRow {
    let metadata = control.metadata
    typealias Kind = RuntimeAudioControlKind
    var row = MediaControlTableRow(
      kind: 0,
      identifier: metadata.identifier,
      name: metadata.name,
      isSettable: metadata.isSettable,
      element: metadata.element,
      scope: metadata.scope.rawValue,
      classID: metadata.controlClass.rawValue
    )
    switch control {
    case .boolean(let value):
      (row.kind, row.value, row.maximum) = (Kind.boolean.rawValue, value.initialValue ? 1 : 0, 1)
    case .level(let value):
      row.kind = Kind.level.rawValue
      row.value = value.initialDecibels.bitPattern
      row.minimum = value.minimumDecibels.bitPattern
      row.maximum = value.maximumDecibels.bitPattern
    case .selector(let value):
      row.kind = Kind.selector.rawValue
      row.selector = (value.values.map { ($0.value, $0.name) }, value.initialValues)
    case .slider(let value):
      (row.kind, row.value) = (Kind.slider.rawValue, value.initialValue)
      (row.minimum, row.maximum) = (value.minimumValue, value.maximumValue)
    case .stereoPan(let value):
      (row.kind, row.value) = (Kind.stereoPan.rawValue, value.initialValue.bitPattern)
      (row.auxiliary0, row.auxiliary1) = (value.leftChannel, value.rightChannel)
    }
    return row
  }

  static func audioServiceMethods(enabled: Bool) -> String {
    guard enabled else { return "" }
    return """
      kern_return_t StartAudio() LOCALONLY;
      void StopAudio() LOCALONLY;
      kern_return_t AudioCommand(
          uint32_t opcode,
          const uint8_t* payload,
          uint32_t payloadLength,
          OSData** response) LOCALONLY;
      kern_return_t AudioControlEvent(uint32_t kind, uint64_t value) LOCALONLY;
      kern_return_t AudioControlValueEvent(
          uint32_t identifier,
          uint32_t kind,
          const uint32_t* values,
          uint32_t count) LOCALONLY;
      kern_return_t AudioCustomPropertyEvent(
          uint32_t identifier,
          const uint8_t* qualifier,
          uint32_t qualifierLength,
          const uint8_t* value,
          uint32_t valueLength) LOCALONLY;
      virtual kern_return_t StartDevice(
          IOUserAudioObjectID objectID,
          IOUserAudioStartStopFlags flags) LOCALONLY override;
      virtual kern_return_t StopDevice(
          IOUserAudioObjectID objectID,
          IOUserAudioStartStopFlags flags) LOCALONLY override;
      virtual void AudioRequestTimerOccurred(OSAction* action, uint64_t time)
          TYPE(IOTimerDispatchSource::TimerOccurred);
      kern_return_t StartAudioObjects() LOCALONLY;
      void StopAudioObjects() LOCALONLY;
      kern_return_t StartAudioRequests() LOCALONLY;
      void StopAudioRequests() LOCALONLY;
      kern_return_t AudioObjectCommand(
          uint32_t opcode,
          const uint8_t* payload,
          uint32_t payloadLength,
          OSData** response) LOCALONLY;
      kern_return_t AudioObjectEvent(uint32_t kind, uint32_t index, uint64_t value) LOCALONLY;
      kern_return_t BeginAudioRequest(
          OSObject* object,
          uint32_t kind,
          uint32_t index,
          uint64_t value,
          uint64_t previous) LOCALONLY;
      kern_return_t CompleteAudioRequest(uint32_t requestID, bool accept, int32_t failure)
          LOCALONLY;
      kern_return_t ApplyAudioRequest(
          OSObject* object,
          uint32_t kind,
          uint64_t value,
          uint64_t previous,
          bool accept,
          int32_t failure) LOCALONLY;
      void RejectAudioRequests(int32_t failure) LOCALONLY;
      """
  }
}
