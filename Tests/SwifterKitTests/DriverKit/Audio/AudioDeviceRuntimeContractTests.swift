import Foundation
import Testing

@testable import SwifterKit

@Suite
struct AudioDeviceRuntimeContractTests {
  private let memberOpcodes = RuntimeOpcode.allCases.filter {
    (0x0A20...0x0A29).contains($0.rawValue)
  }

  @Test
  func generatesAndBuildsDeviceStreamControlAndPropertyCommands() throws {
    try withGeneratedExtension { output, derivedData in
      let members = try source("SwifterKitRuntimeAudioMembers.cpp", in: output)
      #expect(memberOpcodes.count == 10)
      for opcode in memberOpcodes {
        #expect(members.contains("case SwifterKitRuntimeOpcode::\(nativeName(opcode)):"))
      }
      for call in [
        "SetCanBeDefaultSystemOutputDevice(", "GetCurrentClientIOTime(true",
        "SetPreferredInputChannelLayout(", "SetWantsStreamFormatsRestored(",
        "SetIOMemoryDescriptor(descriptor)", "GetNumberAvailableStreamFormats()",
        "GetControlValueDescriptions(", "RemoveControlValueDescriptions(", "SetRange(",
        "SetPanningChannels(", "GetCustomPropertyInfo()", "RemoveStream(",
        "driver->RemoveCustomProperty(property)",
      ] { #expect(members.contains(call), "missing \(call)") }
      let resize = try section(
        of: members,
        from: "::ResizeStreamMemory(",
        to: "::ApplyRingBufferChange("
      )
      #expect(
        resize.contains("RequestDeviceConfigurationChange(kSwifterKitAudioRingBufferChangeAction")
      )
      #expect(!resize.contains("SetIOMemoryDescriptor("))
      let device = try source("SwifterKitRuntimeAudioDevice.cpp", in: output)
      let perform = try section(
        of: device,
        from: "::PerformDeviceConfigurationChange(",
        to: "::AbortDeviceConfigurationChange("
      )
      #expect(perform.contains("return ApplyRingBufferChange();"))
      let apply = try section(of: members, from: "::ApplyRingBufferChange(", to: "::ReadStream(")
      let swap = try section(
        of: String(apply),
        from: "IOLockLock(ivars->ringLock);",
        to: "IOLockUnlock(ivars->ringLock);"
      )
      #expect(!swap.contains("SetIOMemoryDescriptor"))
      #expect(members.contains("ReadMappedStream(transfer, response)"))
      let restore = try section(
        of: members,
        from: "case kSwifterKitAudioDevicePropertyWantsStreamFormatsRestored:",
        to: "default:"
      )
      #expect(restore.contains("__DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5"))
      #expect(restore.contains("return kIOReturnUnsupported;"))
      let teardown = try section(
        of: members,
        from: "::RemoveControlsAndProperties()",
        to: "::MemberCommand("
      )
      #expect(teardown.contains("!ivars->controlDetached[index]"))
      #expect(teardown.contains("->RemoveCustomProperty(property)"))

      let entitlements = try loadPropertyList(
        at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
      )
      #expect(
        entitlements["com.apple.developer.driverkit.allow-any-userclient-access"] as? Bool == true
      )

      try expectGeneratedExtensionBuilds(at: output, derivedData: derivedData)
    }
  }

  @Test
  func routesMemberOpcodesThroughTheAudioFamilyUnderAudioLock() throws {
    try withGeneratedExtension { output, _ in
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let group = try section(
        of: dispatch,
        from: "case SwifterKitRuntimeOpcode::AudioReadStream:",
        to: "return DispatchMediaCommand(context);"
      )
      for opcode in memberOpcodes {
        #expect(group.contains("case SwifterKitRuntimeOpcode::\(nativeName(opcode)):"))
      }
      let audio = try source("SwifterKitRuntimeAudio.cpp", in: output)
      let locked = try section(
        of: audio,
        from: "IOLockLock(ivars->audioLock);\n    SwifterKitRuntimeAudioDevice* device",
        to: "IOLockUnlock(ivars->audioLock);\n    return result;"
      )
      #expect(locked.contains("device->MemberCommand(opcode, payload, payloadLength, response)"))
    }
  }

  @Test
  func boxTakesTheAcquiredStateBeforeReportingSuccess() throws {
    try withGeneratedExtension { output, _ in
      let box = try source("SwifterKitRuntimeAudioBox.cpp", in: output)
      let handler = try section(of: box, from: "::HandleChangeAcquireBox(", to: "#endif")
      let set = try #require(handler.range(of: "SetIsAcquired(acquire)")?.lowerBound)
      let queue = try #require(handler.range(of: "BeginAudioRequest(")?.lowerBound)
      #expect(set < queue)
      #expect(handler.contains("(void)SetIsAcquired(previous);"))
      let unchanged = try #require(handler.range(of: "if (previous == acquire)")?.lowerBound)
      #expect(unchanged < queue)

      let requests = try source("SwifterKitRuntimeAudioRequests.cpp", in: output)
      let apply = try section(
        of: requests,
        from: "::ApplyAudioRequest(",
        to: "::RejectAudioRequests("
      )
      #expect(apply.contains("SwifterKitApplyRequest<AudioRequestFamily>("))
      let media = try source("SwifterKitRuntimeMediaRequests.h", in: output)
      let sharedApply = try section(
        of: media,
        from: "kern_return_t SwifterKitApplyRequest(",
        to: "void SwifterKitEndRequests("
      )
      #expect(sharedApply.contains("SetIsAcquired(accept ? value != 0 : value == 0)"))
    }
  }

  @Test
  func appliesStreamOffsetAndLatencyChangesInsideADeviceConfigurationChange() throws {
    try withGeneratedExtension { output, _ in
      let members = try source("SwifterKitRuntimeAudioMembers.cpp", in: output)
      let property = try section(
        of: members,
        from: "::SetDeviceProperty(",
        to: "case kSwifterKitAudioDevicePropertyPreferredStereoChannels:"
      )
      #expect(!property.contains("return SetInputSafetyOffset("))
      #expect(!property.contains("return SetOutputSafetyOffset("))
      #expect(property.contains("kSwifterKitAudioChangeInputSafetyOffset"))
      let attachment = try section(
        of: members,
        from: "::SetMemberAttachment(",
        to: "if (request->kind == kSwifterKitAudioMemberControl)"
      )
      #expect(!attachment.contains("AddStream("))
      #expect(attachment.contains("kSwifterKitAudioChangeStreamAttachment"))
      let apply = try section(of: members, from: "::ApplyMemberChange(", to: "#endif")
      #expect(apply.contains("AddStream(stream) : RemoveStream(stream)"))
      #expect(apply.contains("return SetInputSafetyOffset(value);"))

      let device = try source("SwifterKitRuntimeAudioDevice.cpp", in: output)
      let perform = try section(
        of: device,
        from: "::PerformDeviceConfigurationChange(",
        to: "::AbortDeviceConfigurationChange("
      )
      #expect(perform.contains("return ApplyMemberChange(changeInfo);"))

      let objects = try source("SwifterKitRuntimeAudioObjects.cpp", in: output)
      let clockSetter = try section(
        of: objects,
        from: "kern_return_t SetClockProperty(",
        to: "case kSwifterKitAudioClockPropertyTransport:"
      )
      #expect(!clockSetter.contains("SetInputLatency("))
      #expect(!clockSetter.contains("SetZeroTimeStampPeriod("))
      #expect(
        clockSetter.contains("SwifterKitRequestAudioMemberChange(clock, selector, 0, number)")
      )
      let clock = try source("SwifterKitRuntimeAudioClockDevice.cpp", in: output)
      let clockPerform = try section(
        of: clock,
        from: "::PerformDeviceConfigurationChange(",
        to: "kClockSampleRateChangeAction)"
      )
      #expect(clockPerform.contains("return SetZeroTimeStampPeriod(value);"))
      #expect(clockPerform.contains("return SetInputLatency(value);"))
    }
  }

  private func nativeName(_ opcode: RuntimeOpcode) -> String {
    let name = String(describing: opcode)
    return name.prefix(1).uppercased() + name.dropFirst()
  }

  private var configuration: AudioDeviceConfiguration {
    let format = AudioStreamFormat.linearPCM(sampleRate: 48_000, channels: 2)
    return AudioDeviceConfiguration(
      deviceUID: "SwifterKit.Members",
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Members",
      sampleRates: [48_000],
      initialSampleRate: 48_000,
      streams: [
        AudioStreamConfiguration(direction: .output, name: "Out", formats: [format]),
        AudioStreamConfiguration(direction: .input, name: "In", formats: [format]),
      ],
      controls: [
        .selector(
          AudioSelectorControlConfiguration(
            metadata: AudioControlMetadata(
              identifier: 3,
              name: "Source",
              scope: .input,
              controlClass: .dataSource
            ),
            values: [
              AudioSelectorValue(value: 1, name: "Line"), AudioSelectorValue(value: 2, name: "Mic"),
            ],
            initialValues: [1]
          )
        ),
        .slider(
          AudioSliderControlConfiguration(
            metadata: AudioControlMetadata(identifier: 4, name: "Blend", controlClass: .slider),
            initialValue: 50,
            minimumValue: 0,
            maximumValue: 100
          )
        ),
        .stereoPan(
          AudioStereoPanControlConfiguration(
            metadata: AudioControlMetadata(
              identifier: 5,
              name: "Pan",
              scope: .output,
              controlClass: .stereoPan
            ),
            leftChannel: 1,
            rightChannel: 2
          )
        ),
      ],
      customProperties: [
        AudioCustomPropertyConfiguration(
          identifier: 20,
          selector: 0x7377_6B70,
          values: ["Mode": "Studio"]
        )
      ]
    )
  }

  private func withGeneratedExtension(_ body: (URL, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("AudioMemberDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.audio-members",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: .audio,
        audioDevice: configuration
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
      at: output
    )
    try body(output, root.appendingPathComponent("DerivedData"))
  }

  private func source(_ name: String, in output: URL) throws -> String {
    try String(
      contentsOf: output.appendingPathComponent("Sources").appendingPathComponent(name),
      encoding: .utf8
    )
  }

  private func section(of text: String, from start: String, to end: String) throws -> Substring {
    let lower = try #require(text.range(of: start)?.lowerBound)
    let upper = try #require(text.range(of: end, range: lower..<text.endIndex)?.lowerBound)
    return text[lower..<upper]
  }
}
