import Foundation

extension DriverExtensionGenerator {
  static func isValid(video value: VideoDeviceConfiguration) -> Bool {
    let limits = RuntimeVideoLimits.self
    let strings =
      [value.deviceUID, value.modelUID, value.manufacturerUID, value.name]
      + value.streams.map(\.identifier)
    guard strings.allSatisfy(isValidVideoName),
      (1...limits.maximumSampleRates).contains(value.sampleRates.count),
      Set(value.sampleRates).count == value.sampleRates.count,
      value.sampleRates.allSatisfy({ $0.isFinite && $0 > 0 }),
      value.sampleRates.contains(value.initialSampleRate),
      (1...limits.maximumStreams).contains(value.streams.count),
      Set(value.streams.map(\.identifier)).count == value.streams.count,
      value.controls.count <= limits.maximumControls,
      value.customProperties.count <= limits.maximumCustomProperties, isValid(videoTopology: value)
    else { return false }

    var totalCapacity: UInt64 = 0
    for stream in value.streams {
      guard (1...limits.maximumStreamFormats).contains(stream.formats.count),
        Int(stream.initialFormatIndex) < stream.formats.count,
        (1...limits.maximumBuffers).contains(Int(stream.bufferCount)),
        (1...16_777_216).contains(stream.dataBufferCapacity),
        (1...limits.maximumControlCapacity).contains(Int(stream.controlBufferCapacity)),
        stream.formats.allSatisfy({
          $0.frameRate.isFinite && $0.frameRate > 0 && $0.frameTimeValue > 0
            && $0.frameTimeScale > 0 && $0.codec.rawValue != 0 && $0.width > 0 && $0.height > 0
        })
      else { return false }
      totalCapacity +=
        UInt64(stream.bufferCount)
        * (UInt64(stream.dataBufferCapacity) + UInt64(stream.controlBufferCapacity))
    }
    guard totalCapacity <= 268_435_456 else { return false }

    guard hasUniqueNonzeroIdentifiers(value.controls.map(\.metadata.identifier)),
      value.controls.allSatisfy(isValid(videoControl:))
    else { return false }
    return areValidMediaCustomProperties(
      value.customProperties.map { ($0.identifier, $0.selector, $0.values) },
      valueMaximumLength: limits.customPropertyValueMaximumLength,
      isValidName: isValidVideoName
    )
  }

  static func isValid(videoControl value: VideoControlConfiguration) -> Bool {
    let metadata = value.metadata
    guard isValidVideoName(metadata.name), metadata.controlClass.rawValue != 0 else { return false }
    switch value {
    case .boolean: return true
    case .direction: return metadata.controlClass == .direction
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
        maximum: RuntimeVideoLimits.maximumSelectorItems,
        isValidName: isValidVideoName
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
  static func isValidVideoName(_ name: String) -> Bool {
    !name.isEmpty && !name.contains("\0") && name.utf8.count <= RuntimeVideoLimits.nameMaximumLength
  }
}
