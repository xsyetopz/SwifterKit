import Foundation
import Testing

@testable import SwifterKit

@Suite struct AudioControlTypesTests {
  @Test func preservesControlMetadataAndConfigurations() {
    let metadata = AudioControlMetadata(
      identifier: 7,
      name: "Output Mute",
      scope: .output,
      controlClass: .mute
    )
    let control = AudioControlConfiguration.boolean(
      AudioBooleanControlConfiguration(metadata: metadata, initialValue: false)
    )
    let property = AudioCustomPropertyConfiguration(
      identifier: 8,
      selector: 0x7377_6B70,
      values: ["Mode": "Studio"]
    )
    let format = AudioStreamFormat.linearPCM(sampleRate: 48_000, channels: 2)
    let device = AudioDeviceConfiguration(
      deviceUID: "Device",
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Audio",
      sampleRates: [48_000],
      initialSampleRate: 48_000,
      streams: [AudioStreamConfiguration(direction: .output, name: "Output", formats: [format])],
      controls: [control],
      customProperties: [property]
    )

    #expect(metadata.scope == .output)
    #expect(metadata.controlClass == .mute)
    #expect(device.controls == [control])
    #expect(device.customProperties == [property])
  }

  @Test func exposesDriverKitFourCharacterCodes() {
    #expect(AudioObjectScope.global.rawValue == 0x676C_6F62)
    #expect(AudioObjectScope.input.rawValue == 0x696E_7074)
    #expect(AudioControlClass.volume.rawValue == 0x766C_6D65)
    #expect(AudioControlClass.stereoPan.rawValue == 0x7370_616E)
  }
}
