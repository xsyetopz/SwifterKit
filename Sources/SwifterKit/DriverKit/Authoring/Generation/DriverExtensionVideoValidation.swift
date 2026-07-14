import Foundation

extension DriverExtensionGenerator {
  static func isValid(video value: VideoDeviceConfiguration) -> Bool {
    let strings =
      [value.deviceUID, value.modelUID, value.manufacturerUID, value.name]
      + value.streams.map(\.identifier)
    guard strings.allSatisfy({ !$0.isEmpty && !$0.contains("\0") && $0.utf8.count < 256 }),
      (1...16).contains(value.sampleRates.count),
      Set(value.sampleRates).count == value.sampleRates.count,
      value.sampleRates.allSatisfy({ $0.isFinite && $0 > 0 }),
      value.sampleRates.contains(value.initialSampleRate), (1...8).contains(value.streams.count),
      Set(value.streams.map(\.identifier)).count == value.streams.count, value.controls.count <= 64,
      value.customProperties.count <= 32
    else { return false }

    var totalCapacity: UInt64 = 0
    for stream in value.streams {
      guard (1...16).contains(stream.formats.count),
        Int(stream.initialFormatIndex) < stream.formats.count,
        (1...32).contains(stream.bufferCount), (1...16_777_216).contains(stream.dataBufferCapacity),
        (1...1_048_576).contains(stream.controlBufferCapacity),
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

    let controlIDs = value.controls.map { $0.metadata.identifier }
    guard controlIDs.allSatisfy({ $0 != 0 }), Set(controlIDs).count == controlIDs.count,
      value.controls.allSatisfy(isValid(videoControl:))
    else { return false }
    let propertyIDs = value.customProperties.map(\.identifier)
    return propertyIDs.allSatisfy { $0 != 0 } && Set(propertyIDs).count == propertyIDs.count
      && value.customProperties.allSatisfy { property in
        property.selector != 0 && !property.values.isEmpty && property.values.count <= 32
          && property.values.allSatisfy { qualifier, data in
            !qualifier.isEmpty && !qualifier.contains("\0") && !data.contains("\0")
              && qualifier.utf8.count <= 255 && data.utf8.count <= 4_096
          }
      }
  }

  static func isValid(videoControl value: VideoControlConfiguration) -> Bool {
    let metadata = value.metadata
    guard !metadata.name.isEmpty, !metadata.name.contains("\0"), metadata.name.utf8.count < 256,
      metadata.controlClass.rawValue != 0
    else { return false }
    switch value {
    case .boolean: return true
    case .direction: return metadata.controlClass == .direction
    case .level(let level):
      return level.initialDecibels.isFinite && level.minimumDecibels.isFinite
        && level.maximumDecibels.isFinite && level.minimumDecibels <= level.initialDecibels
        && level.initialDecibels <= level.maximumDecibels
    case .selector(let selector):
      let values = selector.values.map(\.value)
      let names = selector.values.map(\.name)
      return !values.isEmpty && values.count <= 32 && Set(values).count == values.count
        && !selector.initialValues.isEmpty && selector.initialValues.count <= 32
        && Set(selector.initialValues).count == selector.initialValues.count
        && selector.initialValues.allSatisfy(Set(values).contains)
        && names.allSatisfy { !$0.isEmpty && !$0.contains("\0") && $0.utf8.count < 256 }
    case .slider(let slider):
      return slider.minimumValue <= slider.initialValue
        && slider.initialValue <= slider.maximumValue
    case .stereoPan(let pan):
      return pan.initialValue.isFinite && (-1...1).contains(pan.initialValue)
        && pan.leftChannel != pan.rightChannel
    }
  }
}
