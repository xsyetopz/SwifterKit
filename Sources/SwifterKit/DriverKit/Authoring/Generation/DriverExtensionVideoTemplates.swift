import Foundation

extension DriverExtensionGenerator {
  static func videoConfigurationDeclarations(_ configuration: DriverConfiguration) -> String {
    let declarations = """
      struct SwifterKitVideoFormatConfiguration {
          double frameRate;
          uint64_t frameTimeValue;
          uint32_t frameTimeScale;
          uint32_t codec;
          uint32_t codecFlags;
          uint32_t width;
          uint32_t height;
      };
      struct SwifterKitVideoStreamConfiguration {
          const char* identifier;
          uint32_t direction;
          uint32_t formatStart;
          uint32_t formatCount;
          uint32_t initialFormatIndex;
          uint32_t bufferCount;
          uint32_t dataBufferCapacity;
          uint32_t controlBufferCapacity;
      };
      """

    guard let video = configuration.videoDevice else {
      return declarations + """
        static constexpr char kSwifterKitVideoDeviceUID[] = "";
        static constexpr char kSwifterKitVideoModelUID[] = "";
        static constexpr char kSwifterKitVideoManufacturerUID[] = "";
        static constexpr char kSwifterKitVideoDeviceName[] = "";
        static constexpr uint32_t kSwifterKitVideoTransport = 0;
        static constexpr double kSwifterKitVideoSampleRates[] = {0};
        static constexpr uint32_t kSwifterKitVideoSampleRateCount = 0;
        static constexpr double kSwifterKitVideoInitialSampleRate = 0;
        static constexpr SwifterKitVideoFormatConfiguration kSwifterKitVideoFormats[1] = {};
        static constexpr SwifterKitVideoStreamConfiguration kSwifterKitVideoStreams[1] = {};
        static constexpr uint32_t kSwifterKitVideoStreamCount = 0;
        """ + videoControlConfigurationDeclarations(nil)
    }

    let formats = video.streams.flatMap(\.formats).map { format in
      "    {\(format.frameRate), \(format.frameTimeValue), \(format.frameTimeScale), "
        + "\(format.codec.rawValue), \(format.codecFlags), \(format.width), \(format.height)}"
    }.joined(separator: ",\n")
    var formatStart = 0
    let streams = video.streams.map { stream in
      defer { formatStart += stream.formats.count }
      return "    {\(cString(stream.identifier)), \(stream.direction.rawValue), \(formatStart), "
        + "\(stream.formats.count), \(stream.initialFormatIndex), \(stream.bufferCount), "
        + "\(stream.dataBufferCapacity), \(stream.controlBufferCapacity)}"
    }.joined(separator: ",\n")
    let sampleRates = video.sampleRates.map { String($0) }.joined(separator: ", ")

    return declarations + """
      static constexpr char kSwifterKitVideoDeviceUID[] = \(cString(video.deviceUID));
      static constexpr char kSwifterKitVideoModelUID[] = \(cString(video.modelUID));
      static constexpr char kSwifterKitVideoManufacturerUID[] =
          \(cString(video.manufacturerUID));
      static constexpr char kSwifterKitVideoDeviceName[] = \(cString(video.name));
      static constexpr uint32_t kSwifterKitVideoTransport = \(video.transport.rawValue);
      static constexpr double kSwifterKitVideoSampleRates[] = {\(sampleRates)};
      static constexpr uint32_t kSwifterKitVideoSampleRateCount = \(video.sampleRates.count);
      static constexpr double kSwifterKitVideoInitialSampleRate = \(video.initialSampleRate);
      static constexpr SwifterKitVideoFormatConfiguration kSwifterKitVideoFormats[] = {
      \(formats)
      };
      static constexpr SwifterKitVideoStreamConfiguration kSwifterKitVideoStreams[] = {
      \(streams)
      };
      static constexpr uint32_t kSwifterKitVideoStreamCount = \(video.streams.count);
      """ + videoControlConfigurationDeclarations(video)
  }

  static func videoServiceMethods(enabled: Bool) -> String {
    guard enabled else { return "" }
    return """
          kern_return_t StartVideo() LOCALONLY;
          void StopVideo() LOCALONLY;
          kern_return_t VideoCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          kern_return_t VideoControlEvent(uint32_t kind, uint64_t value) LOCALONLY;
          kern_return_t VideoControlValueEvent(
              uint32_t identifier,
              uint32_t kind,
              const uint32_t* values,
              uint32_t count) LOCALONLY;
          kern_return_t VideoCustomPropertyEvent(
              uint32_t identifier,
              const uint8_t* qualifier,
              uint32_t qualifierLength,
              const uint8_t* value,
              uint32_t valueLength) LOCALONLY;
          kern_return_t VideoStreamEvent(
              uint32_t kind,
              uint32_t streamIndex,
              uint64_t value,
              bool required) LOCALONLY;
          kern_return_t VideoStreamFormatEvent(
              uint32_t streamIndex,
              const IOUserVideoStreamBasicDescription* format) LOCALONLY;
      """
  }

}
