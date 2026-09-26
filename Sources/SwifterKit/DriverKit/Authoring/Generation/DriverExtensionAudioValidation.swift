import Foundation

extension DriverExtensionGenerator {
  static func isValid(audio value: AudioDeviceConfiguration) -> Bool {
    let limits = RuntimeAudioLimits.self
    let strings =
      [value.deviceUID, value.modelUID, value.manufacturerUID, value.name]
      + value.streams.map(\.name)
    guard strings.allSatisfy(isValidAudioName),
      (1...limits.maximumSampleRates).contains(value.sampleRates.count),
      Set(value.sampleRates).count == value.sampleRates.count,
      value.sampleRates.allSatisfy(DriverCommand.isValidAudioRate),
      value.sampleRates.contains(value.initialSampleRate),
      (limits.minimumZeroTimestampPeriod...limits.maximumFrameCount).contains(
        Int(value.zeroTimestampPeriod)
      ), (1...limits.maximumStreams).contains(value.streams.count), isValid(audioTopology: value)
    else { return false }

    guard
      value.streams.allSatisfy({ stream in
        guard (1...limits.maximumStreamFormats).contains(stream.formats.count),
          Int(stream.initialFormatIndex) < stream.formats.count,
          (Int(value.zeroTimestampPeriod)...limits.maximumFrameCount).contains(
            Int(stream.ringBufferFrameCapacity)
          )
        else { return false }
        return stream.formats.allSatisfy { format in
          format.sampleRate.isFinite && value.sampleRates.contains(format.sampleRate)
            && format.formatID.rawValue != 0 && format.bytesPerPacket > 0
            && format.framesPerPacket > 0 && format.bytesPerFrame > 0
            && (1...64).contains(format.channelsPerFrame)
            && (1...64).contains(format.bitsPerChannel)
            && Int(format.bytesPerFrame) * Int(stream.ringBufferFrameCapacity)
              <= limits.maximumRingBufferSize
        }
      }), value.controls.count <= limits.maximumControls,
      value.customProperties.count <= limits.maximumCustomProperties
    else { return false }

    guard hasUniqueNonzeroIdentifiers(value.controls.map(\.metadata.identifier)),
      value.controls.allSatisfy(isValid(audioControl:))
    else { return false }
    return areValidMediaCustomProperties(
      value.customProperties.map { ($0.identifier, $0.selector, $0.values) },
      valueMaximumLength: limits.customPropertyValueMaximumLength,
      isValidName: isValidAudioName
    )
  }

  static func isValid(audioControl value: AudioControlConfiguration) -> Bool {
    let metadata = value.metadata
    guard isValidAudioName(metadata.name), metadata.controlClass.rawValue != 0 else { return false }
    switch value {
    case .boolean: return true
    case .level(let level):
      return isValidMediaLevel(
        initial: level.initialDecibels,
        minimum: level.minimumDecibels,
        maximum: level.maximumDecibels
      )
    case .selector(let selector):
      return isValidMediaSelector(
        values: selector.values.map(\.value),
        names: selector.values.map(\.name),
        initialValues: selector.initialValues,
        maximum: RuntimeAudioLimits.maximumSelectorItems,
        isValidName: isValidAudioName
      )
    case .slider(let slider):
      return slider.minimumValue <= slider.initialValue
        && slider.initialValue <= slider.maximumValue
    case .stereoPan(let pan):
      return pan.initialValue.isFinite && (-1...1).contains(pan.initialValue)
        && pan.leftChannel != pan.rightChannel
    }
  }

  /// Whether a configured name fits the extension's name buffers: non-empty and NUL-free.
  static func isValidAudioName(_ name: String) -> Bool {
    !name.isEmpty && !name.contains("\0") && name.utf8.count <= RuntimeAudioLimits.nameMaximumLength
  }
}
