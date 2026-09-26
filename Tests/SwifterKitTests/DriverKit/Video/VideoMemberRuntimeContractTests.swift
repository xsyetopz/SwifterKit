import Foundation
import Testing

@testable import SwifterKit

@Suite
struct VideoMemberRuntimeContractTests {
  @Test(.enabled(if: DriverKitSDK.supports(deploymentTarget: "25.5")))
  func buildsDeviceStreamBufferControlAndPropertyCommands() throws {
    try withGeneratedExtension { output, derivedData in
      let project = try source("../SwifterKitRuntime.xcodeproj/project.pbxproj", in: output)
      #expect(project.contains("SwifterKitRuntimeVideoMembers.cpp in Sources"))
      try expectGeneratedExtensionBuilds(at: output, derivedData: derivedData)
    }
  }

  @Test
  func routesMemberOpcodesThroughTheVideoFamilyUnderVideoLock() throws {
    try withGeneratedExtension { output, _ in
      let opcodes = RuntimeOpcode.allCases.filter { (0x0C20...0x0C2D).contains($0.rawValue) }
      #expect(opcodes.count == 14)
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let group = try section(
        of: dispatch,
        from: "case SwifterKitRuntimeOpcode::VideoRequestSampleRate:",
        to: "return DispatchMediaCommand(context);"
      )
      for opcode in opcodes {
        #expect(group.contains("case SwifterKitRuntimeOpcode::\(nativeName(opcode)):"))
      }
      let video = try source("SwifterKitRuntimeVideo.cpp", in: output)
      let command = try section(of: video, from: "::VideoCommand(", to: "#endif")
      let lock = try #require(command.range(of: "IOLockLock(ivars->videoLock);")?.lowerBound)
      let members = try #require(command.range(of: "device->MemberCommand(")?.lowerBound)
      #expect(lock < members)

      let native = try source("SwifterKitRuntimeVideoMembers.cpp", in: output)
      for opcode in opcodes {
        #expect(native.contains("case SwifterKitRuntimeOpcode::\(nativeName(opcode)):"))
      }
      for call in [
        "SetCanBeDefaultSystemOutputDevice(", "GetBufferList()", "GetInputQueueMemoryDescriptor()",
        "GetOutputQueue()", "GetBufferWithID(", "_GetOutputControlMemoryObjectID(",
        "GetOutputDataMemoryDescriptor(", "SetDataMemoryDescriptor(", "SetControlMemoryDescriptor(",
        "destroyQueues()", "createQueues(", "setBufferID(", "removeAllBuffers()", "addBuffers(",
        "addBuffer(", "enqueueOutputBuffer(", "GetMemoryObjectID(", "GetOwningDeviceID()",
        "SwifterKitCopyDeviceState<VideoMemberFamily>(",
        "SwifterKitSetPreferredChannelLayout<VideoMemberFamily>(",
        "SwifterKitRemoveSelectorItems<VideoMemberFamily>(",
        "SwifterKitCopyCustomPropertyInfo<VideoMemberFamily>(",
      ] { #expect(native.contains(call), "missing \(call)") }
      let shared = try source("SwifterKitRuntimeMediaMembers.h", in: output)
      for call in [
        "SetPreferredInputChannelLayout(", "GetCurrentClientIOTime(false",
        "RemoveControlValueDescriptions(", "GetCustomPropertyInfo()",
      ] { #expect(shared.contains(call), "missing \(call)") }
      // Stream detach runs in the device's PerformDeviceConfigurationChange.
      let device = try source("SwifterKitRuntimeVideoDevice.cpp", in: output)
      #expect(device.contains("SwifterKitApplyStructureChange<VideoStructureFamily>("))
      #expect(shared.contains("RemoveStream("))
    }
  }

  @Test
  func appliesStructuralChangesInsideADeviceConfigurationChange() throws {
    try withGeneratedExtension { output, _ in
      let native = try source("SwifterKitRuntimeVideoMembers.cpp", in: output)
      let request = try section(
        of: native,
        from: "::RequestMemberChange(",
        to: "::ApplyMemberChange("
      )
      #expect(request.contains("return kIOReturnBusy;"))
      #expect(
        request.contains("RequestDeviceConfigurationChange(kSwifterKitVideoMemberChangeAction")
      )
      #expect(!request.contains("SetDataMemoryDescriptor("))
      let properties = try section(
        of: native,
        from: "::SetStreamProperty(",
        to: "::CopyBufferInfo("
      )
      #expect(!properties.contains("createQueues("))
      #expect(!properties.contains("SetDataMemoryDescriptor("))

      let capacity = try section(
        of: native,
        from: "::ApplyBufferCapacity(",
        to: "::ApplyBufferList("
      )
      // VideoDriverKit calls happen before the lock; the lock only swaps the maps.
      let set = try #require(capacity.range(of: "SetDataMemoryDescriptor(")?.lowerBound)
      let lock = try #require(capacity.range(of: "IOLockLock(ivars->bufferLock);")?.lowerBound)
      #expect(set < lock)
      #expect(capacity.contains("ivars->dataCapacity[stream] = sizes[0];"))

      let device = try source("SwifterKitRuntimeVideoDevice.cpp", in: output)
      let perform = try section(
        of: device,
        from: "::PerformDeviceConfigurationChange(",
        to: "::AbortDeviceConfigurationChange("
      )
      #expect(perform.contains("return ApplyMemberChange();"))
      let entry = try section(of: device, from: "::NativeEntry(", to: "::DequeueInput(")
      #expect(entry.contains("ivars->dataCapacity[streamIndex]"))
      #expect(entry.contains("ivars->bufferIDs[streamIndex][entry->bufferID]"))
      #expect(!entry.contains("config.dataBufferCapacity"))
      let read = try section(of: device, from: "::ReadBuffer(", to: "::WriteBuffer(")
      #expect(read.contains("IOLockLock(ivars->bufferLock);"))
      let format = try section(of: device, from: "::StreamFormatChanged(", to: "#endif")
      #expect(format.contains("kSwifterKitVideoObjectEventDeviceFormatChanged,\n            0,"))
      let notify = try section(of: device, from: "::NotifyBufferQueue(", to: "#endif")
      #expect(notify.contains("stream->SendBufferQueueChange()"))
    }
  }

  @Test
  func rollsBackFailedBufferQueueAndListChanges() throws {
    try withGeneratedExtension { output, _ in
      let native = try source("SwifterKitRuntimeVideoMembers.cpp", in: output)
      let capacity = try section(
        of: native,
        from: "::ApplyBufferCapacity(",
        to: "::ApplyBufferList("
      )
      // A failure restores every buffer touched so far, including the half-set one, before the
      // new descriptors are released, and the ivars are swapped only on success.
      let failure = try #require(
        capacity.range(of: "if (result != kIOReturnSuccess) {")?.lowerBound
      )
      let restore = try #require(
        capacity.range(of: "SetDataMemoryDescriptor(ivars->dataDescriptors[stream][buffer])")?
          .lowerBound
      )
      let swap = try #require(capacity.range(of: "IOLockLock(ivars->bufferLock);")?.lowerBound)
      #expect(failure < restore && restore < swap)
      #expect(
        capacity.contains("SetControlMemoryDescriptor(ivars->controlDescriptors[stream][buffer])")
      )
      #expect(capacity.contains("for (uint32_t buffer = 0; buffer < touched; ++buffer)"))

      let list = try section(of: native, from: "::ApplyBufferList(", to: "::EnqueueOutputBuffer(")
      let built = try #require(list.range(of: "previous->setObject(")?.lowerBound)
      let removed = try #require(list.range(of: "target->removeAllBuffers()")?.lowerBound)
      #expect(built < removed)
      #expect(list.contains("(void)target->addBuffers(previous);"))

      let change = try section(
        of: native,
        from: "case kChangeQueueCount:",
        to: "case kChangeBufferID:"
      )
      #expect(change.contains("previous->entryCount"))
      #expect(change.contains("(void)target->createQueues(previousCount, 0);"))
    }
  }

  @Test
  func setsTheControlOwnerBeforeAddingTheControl() throws {
    try withGeneratedExtension { output, _ in
      let controls = try source("SwifterKitRuntimeVideoControls.cpp", in: output)
      let configure = try section(of: controls, from: "::ConfigureControls(", to: "::CopyControl(")
      let owner = try #require(configure.range(of: "_SetOwningDeviceID(GetObjectID())")?.lowerBound)
      let add = try #require(configure.range(of: "AddControl(control)")?.lowerBound)
      #expect(owner < add)
      let members = try source("SwifterKitRuntimeVideoMembers.cpp", in: output)
      let attach = try section(of: members, from: "::SetMemberAttachment(", to: "#endif")
      let reowner = try #require(attach.range(of: "_SetOwningDeviceID(GetObjectID())")?.lowerBound)
      let readd = try #require(attach.range(of: "AddControl(ivars->controls[index])")?.lowerBound)
      #expect(reowner < readd)
    }
  }

  @Test
  func appliesStreamOffsetAndLatencyChangesInsideADeviceConfigurationChange() throws {
    try withGeneratedExtension { output, _ in
      let members = try source("SwifterKitRuntimeVideoMembers.cpp", in: output)
      let property = try section(
        of: members,
        from: "::SetDeviceProperty(",
        to: "case kSwifterKitVideoDevicePropertyPreferredStereoChannels:"
      )
      #expect(!property.contains("return SetInputSafetyOffset("))
      #expect(!property.contains("return SetOutputSafetyOffset("))
      #expect(
        property.contains("SwifterKitRequestVideoStructureChange(this, request->selector, 0, low)")
      )
      let attachment = try section(
        of: members,
        from: "::SetMemberAttachment(",
        to: "if (request->kind != kSwifterKitVideoMemberControl)"
      )
      #expect(!attachment.contains("AddStream("))
      #expect(attachment.contains("kSwifterKitVideoChangeStreamAttachment"))

      let device = try source("SwifterKitRuntimeVideoDevice.cpp", in: output)
      let perform = try section(
        of: device,
        from: "::PerformDeviceConfigurationChange(",
        to: "kSampleRateChangeAction)"
      )
      #expect(perform.contains("return ApplyStructureChange(changeInfo);"))
      let apply = try section(
        of: device,
        from: "::ApplyStructureChange(",
        to: "::AbortDeviceConfigurationChange("
      )
      #expect(
        apply.contains("SwifterKitApplyStructureChange<VideoStructureFamily>(this, ivars, change)")
      )
      let shared = try source("SwifterKitRuntimeMediaMembers.h", in: output)
      let sharedApply = try section(
        of: shared,
        from: "kern_return_t SwifterKitApplyStructureChange(",
        to: "kern_return_t SwifterKitEnqueueControlValueEvent("
      )
      #expect(sharedApply.contains("device->AddStream(stream) : device->RemoveStream(stream)"))
      #expect(sharedApply.contains("return device->SetInputSafetyOffset(value);"))
      #expect(sharedApply.contains("return device->SetOutputSafetyOffset(value);"))

      let objects = try source("SwifterKitRuntimeVideoObjects.cpp", in: output)
      let clockSetter = try section(
        of: objects,
        from: "kern_return_t SetClockProperty(",
        to: "default:"
      )
      #expect(!clockSetter.contains("SetInputLatency("))
      #expect(!clockSetter.contains("SetOutputLatency("))
      #expect(
        clockSetter.contains("SwifterKitRequestVideoStructureChange(clock, selector, 0, number)")
      )
      let clock = try source("SwifterKitRuntimeVideoClockDevice.cpp", in: output)
      let clockPerform = try section(
        of: clock,
        from: "::PerformDeviceConfigurationChange(",
        to: "kClockSampleRateChangeAction)"
      )
      #expect(clockPerform.contains("return SetInputLatency(value);"))
      #expect(clockPerform.contains("return SetOutputLatency(value);"))
    }
  }

  private func nativeName(_ opcode: RuntimeOpcode) -> String {
    let name = String(describing: opcode)
    return name.prefix(1).uppercased() + name.dropFirst()
  }

  private var configuration: VideoDeviceConfiguration {
    let format = VideoStreamFormat(
      frameRate: 60,
      frameTimeScale: 60,
      codec: .bgra32,
      width: 64,
      height: 64
    )
    return VideoDeviceConfiguration(
      deviceUID: "Device",
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Video",
      sampleRates: [60],
      initialSampleRate: 60,
      streams: [
        VideoStreamConfiguration(
          identifier: "Out",
          direction: .output,
          formats: [format],
          dataBufferCapacity: 16_384
        )
      ],
      controls: [
        .slider(
          VideoSliderControlConfiguration(
            metadata: VideoControlMetadata(identifier: 4, name: "Zoom", controlClass: .level),
            initialValue: 1,
            minimumValue: 0,
            maximumValue: 8
          )
        )
      ],
      customProperties: [
        VideoCustomPropertyConfiguration(identifier: 3, selector: 0x7377_6B70, values: ["A": "B"])
      ]
    )
  }

  private func withGeneratedExtension(_ body: (URL, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("VideoMemberDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.video-members",
        providerClass: "IOService",
        capabilities: .video,
        videoDevice: configuration
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "25.5"),
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
