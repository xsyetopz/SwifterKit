import Foundation
import Testing

@testable import SwifterKit

@Suite struct VideoControlTypesTests {
  @Test func preservesControlMetadataAndConfigurations() {
    let metadata = VideoControlMetadata(
      identifier: 7,
      name: "Output Mute",
      scope: .output,
      controlClass: .mute
    )
    let control = VideoControlConfiguration.boolean(
      VideoBooleanControlConfiguration(metadata: metadata, initialValue: false)
    )
    let property = VideoCustomPropertyConfiguration(
      identifier: 8,
      selector: 0x7377_6B70,
      values: ["Mode": "Studio"]
    )
    let format = VideoStreamFormat(
      frameRate: 60,
      frameTimeScale: 60,
      codec: .bgra32,
      width: 1_920,
      height: 1_080
    )
    let stream = VideoStreamConfiguration(
      identifier: "Output",
      direction: .output,
      formats: [format],
      dataBufferCapacity: 8_294_400
    )
    let device = VideoDeviceConfiguration(
      deviceUID: "Device",
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Video",
      sampleRates: [48_000],
      initialSampleRate: 48_000,
      streams: [stream],
      controls: [control],
      customProperties: [property]
    )

    #expect(metadata.scope == .output)
    #expect(metadata.controlClass == .mute)
    #expect(device.controls == [control])
    #expect(device.customProperties == [property])
  }

  @Test func exposesDriverKitFourCharacterCodes() {
    #expect(VideoObjectScope.global.rawValue == 0x676C_6F62)
    #expect(VideoObjectScope.input.rawValue == 0x696E_7074)
    #expect(VideoControlClass.volume.rawValue == 0x766C_6D65)
    #expect(VideoControlClass.stereoPan.rawValue == 0x7370_616E)
    #expect(VideoControlClass.direction.rawValue == 0x6469_7265)
  }
}
