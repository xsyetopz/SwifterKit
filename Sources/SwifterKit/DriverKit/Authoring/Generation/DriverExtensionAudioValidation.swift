import Foundation

extension DriverExtensionGenerator {
  static func isValid(audio value: AudioDeviceConfiguration) -> Bool {
    let strings =
      [value.deviceUID, value.modelUID, value.manufacturerUID, value.name]
      + value.streams.map(\.name)
    guard strings.allSatisfy({ !$0.isEmpty && !$0.contains("\0") && $0.utf8.count < 256 }),
      (1...16).contains(value.sampleRates.count),
      Set(value.sampleRates).count == value.sampleRates.count,
      value.sampleRates.allSatisfy({ $0.isFinite && (8_000...768_000).contains($0) }),
      value.sampleRates.contains(value.initialSampleRate),
      (16...1_048_576).contains(value.zeroTimestampPeriod), (1...8).contains(value.streams.count)
    else { return false }

    guard
      value.streams.allSatisfy({ stream in
        guard (1...16).contains(stream.formats.count),
          Int(stream.initialFormatIndex) < stream.formats.count,
          (value.zeroTimestampPeriod...1_048_576).contains(stream.ringBufferFrameCapacity)
        else { return false }
        return stream.formats.allSatisfy { format in
          format.sampleRate.isFinite && value.sampleRates.contains(format.sampleRate)
            && format.formatID.rawValue != 0 && format.bytesPerPacket > 0
            && format.framesPerPacket > 0 && format.bytesPerFrame > 0
            && (1...64).contains(format.channelsPerFrame)
            && (1...64).contains(format.bitsPerChannel)
            && UInt64(format.bytesPerFrame) * UInt64(stream.ringBufferFrameCapacity) <= 16_777_216
        }
      }), value.controls.count <= 64, value.customProperties.count <= 32
    else { return false }

    let controlIDs = value.controls.map { $0.metadata.identifier }
    guard controlIDs.allSatisfy({ $0 != 0 }), Set(controlIDs).count == controlIDs.count,
      value.controls.allSatisfy(isValid(audioControl:))
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

  static func isValid(audioControl value: AudioControlConfiguration) -> Bool {
    let metadata = value.metadata
    guard !metadata.name.isEmpty, !metadata.name.contains("\0"), metadata.name.utf8.count < 256,
      metadata.controlClass.rawValue != 0
    else { return false }
    switch value {
    case .boolean: return true
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
