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
      struct SwifterKitAudioControlConfiguration {
          uint32_t kind;
          uint32_t identifier;
          const char* name;
          bool isSettable;
          uint32_t element;
          uint32_t scope;
          uint32_t classID;
          uint32_t value;
          uint32_t minimum;
          uint32_t maximum;
          uint32_t auxiliary0;
          uint32_t auxiliary1;
          uint32_t selectorStart;
          uint32_t selectorCount;
          uint32_t initialStart;
          uint32_t initialCount;
      };
      struct SwifterKitAudioSelectorConfiguration {
          uint32_t value;
          const char* name;
      };
      struct SwifterKitAudioCustomPropertyConfiguration {
          uint32_t identifier;
          uint32_t selector;
          uint32_t scope;
          uint32_t element;
          bool isSettable;
          uint32_t valueStart;
          uint32_t valueCount;
      };
      struct SwifterKitAudioCustomPropertyValueConfiguration {
          const char* qualifier;
          const char* value;
      };
      """

    guard let audio = configuration.audioDevice else {
      return declarations + """
        static constexpr char kSwifterKitBundleIdentifier[] = "";
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
        static constexpr SwifterKitAudioControlConfiguration kSwifterKitAudioControls[1] = {};
        static constexpr uint32_t kSwifterKitAudioControlCount = 0;
        static constexpr SwifterKitAudioSelectorConfiguration kSwifterKitAudioSelectors[1] = {};
        static constexpr uint32_t kSwifterKitAudioSelectorCount = 0;
        static constexpr uint32_t kSwifterKitAudioInitialSelections[1] = {};
        static constexpr SwifterKitAudioCustomPropertyConfiguration
            kSwifterKitAudioCustomProperties[1] = {};
        static constexpr uint32_t kSwifterKitAudioCustomPropertyCount = 0;
        static constexpr SwifterKitAudioCustomPropertyValueConfiguration
            kSwifterKitAudioCustomPropertyValues[1] = {};
        """
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

    var selectorStart = 0
    var initialStart = 0
    let controls = audio.controls.map { control -> String in
      let metadata = control.metadata
      var fields: [UInt32]
      switch control {
      case .boolean(let value): fields = [1, value.initialValue ? 1 : 0, 0, 1, 0, 0, 0, 0, 0]
      case .level(let value):
        fields = [
          2, value.initialDecibels.bitPattern, value.minimumDecibels.bitPattern,
          value.maximumDecibels.bitPattern, 0, 0, 0, 0, 0,
        ]
      case .selector(let value):
        fields = [
          3, 0, 0, 0, 0, UInt32(selectorStart), UInt32(value.values.count), UInt32(initialStart),
          UInt32(value.initialValues.count),
        ]
        selectorStart += value.values.count
        initialStart += value.initialValues.count
      case .slider(let value):
        fields = [4, value.initialValue, value.minimumValue, value.maximumValue, 0, 0, 0, 0, 0]
      case .stereoPan(let value):
        fields = [5, value.initialValue.bitPattern, 0, 0, value.leftChannel, 0, 0, 0, 0]
      }
      let auxiliary1: UInt32
      if case .stereoPan(let value) = control {
        auxiliary1 = value.rightChannel
      } else {
        auxiliary1 = 0
      }
      return "    {\(fields[0]), \(metadata.identifier), \(cString(metadata.name)), "
        + "\(metadata.isSettable ? "true" : "false"), \(metadata.element), "
        + "\(metadata.scope.rawValue), \(metadata.controlClass.rawValue), \(fields[1]), "
        + "\(fields[2]), \(fields[3]), \(fields[4]), \(auxiliary1), \(fields[5]), "
        + "\(fields[6]), \(fields[7]), \(fields[8])}"
    }.joined(separator: ",\n")
    let selectors = audio.controls.compactMap { control -> [AudioSelectorValue]? in
      guard case .selector(let value) = control else { return nil }
      return value.values
    }.flatMap { $0 }.map { "    {\($0.value), \(cString($0.name))}" }.joined(separator: ",\n")
    let initialSelections = audio.controls.compactMap { control -> [UInt32]? in
      guard case .selector(let value) = control else { return nil }
      return value.initialValues
    }.flatMap { $0 }.map(String.init).joined(separator: ", ")

    var propertyValueStart = 0
    let properties = audio.customProperties.map { property in
      defer { propertyValueStart += property.values.count }
      return "    {\(property.identifier), \(property.selector), \(property.scope.rawValue), "
        + "\(property.element), \(property.isSettable ? "true" : "false"), "
        + "\(propertyValueStart), \(property.values.count)}"
    }.joined(separator: ",\n")
    let propertyValues = audio.customProperties.flatMap { property in
      property.values.sorted { $0.key < $1.key }
    }.map { "    {\(cString($0.key)), \(cString($0.value))}" }.joined(separator: ",\n")
    let sampleRates = audio.sampleRates.map { String($0) }.joined(separator: ", ")

    return declarations + """
      static constexpr char kSwifterKitBundleIdentifier[] =
          \(cString(configuration.bundleIdentifier));
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
      static constexpr SwifterKitAudioControlConfiguration kSwifterKitAudioControls[] = {
      \(controls)
      };
      static constexpr uint32_t kSwifterKitAudioControlCount = \(audio.controls.count);
      static constexpr SwifterKitAudioSelectorConfiguration kSwifterKitAudioSelectors[] = {
      \(selectors)
      };
      static constexpr uint32_t kSwifterKitAudioSelectorCount = \(selectorStart);
      static constexpr uint32_t kSwifterKitAudioInitialSelections[] = {\(initialSelections)};
      static constexpr SwifterKitAudioCustomPropertyConfiguration
          kSwifterKitAudioCustomProperties[] = {
      \(properties)
      };
      static constexpr uint32_t kSwifterKitAudioCustomPropertyCount =
          \(audio.customProperties.count);
      static constexpr SwifterKitAudioCustomPropertyValueConfiguration
          kSwifterKitAudioCustomPropertyValues[] = {
      \(propertyValues)
      };
      """
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
      """
  }
}
