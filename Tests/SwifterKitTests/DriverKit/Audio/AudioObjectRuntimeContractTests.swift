import Foundation
import Testing

@testable import SwifterKit

@Suite
struct AudioObjectRuntimeContractTests {
  @Test
  func generatesAndBuildsBoxesAndClockDevices() throws {
    try withGeneratedExtension(topology) { output, derivedData in
      let config = try source("SwifterKitRuntimeConfiguration.h", in: output)
      #expect(config.contains("kSwifterKitAudioBoxCount = 2"))
      #expect(config.contains("kSwifterKitAudioClockDeviceCount = 2"))
      #expect(config.contains("1970496032, true, false, true, true, false, false, true, 2}"))
      #expect(config.contains("0, false, true, true, false, false, false, false, 1}"))
      #expect(config.contains("kSwifterKitAudioClockSampleRates[3] = {44100.0, 48000.0, 96000.0}"))
      #expect(config.contains("1835103847, true, true, 12, 34, 1}"))
      #expect(config.contains("1768518246, true, false, 0, 0, -1}"))

      let service = try source("SwifterKitRuntimeService.iig", in: output)
      #expect(service.contains("StartDevice("))
      #expect(service.contains("StopDevice("))
      #expect(service.contains("TYPE(IOTimerDispatchSource::TimerOccurred)"))

      let entitlements = try loadPropertyList(
        at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
      )
      #expect(entitlements["com.apple.developer.driverkit.family.audio"] as? Bool == true)
      // Audio keeps this entitlement; see DriverExtensionGenerator.swift.
      #expect(
        entitlements["com.apple.developer.driverkit.allow-any-userclient-access"] as? Bool == true
      )

      try expectGeneratedExtensionBuilds(at: output, derivedData: derivedData)
    }
  }

  @Test
  func routesEveryAudioObjectOpcodeThroughTheAudioFamily() throws {
    try withGeneratedExtension(topology) { output, _ in
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let group = try section(
        of: dispatch,
        from: "case SwifterKitRuntimeOpcode::AudioReadStream:",
        to: "return DispatchMediaCommand(context);"
      )
      let opcodes = RuntimeOpcode.allCases.filter { (0x0A10...0x0A1D).contains($0.rawValue) }
      #expect(opcodes.count == 14)
      for opcode in opcodes {
        let name = String(describing: opcode)
        #expect(
          group.contains(
            "case SwifterKitRuntimeOpcode::\(name.prefix(1).uppercased())\(name.dropFirst()):"
          )
        )
      }
      let audio = try source("SwifterKitRuntimeAudio.cpp", in: output)
      let command = try section(
        of: audio,
        from: "SwifterKitRuntimeService::AudioCommand(",
        to: "IOLockLock(ivars->audioLock)"
      )
      #expect(
        command.contains("return AudioObjectCommand(opcode, payload, payloadLength, response);")
      )
      let stop = try section(of: audio, from: "::StopAudio()", to: "::AudioControlEvent(")
      let objects = try #require(stop.range(of: "StopAudioObjects();")?.lowerBound)
      let removal = try #require(stop.range(of: "RemoveObject(device)")?.lowerBound)
      #expect(objects < removal)
      #expect(stop.contains("RemoveControlsAndProperties()"))
    }
  }

  @Test
  func pendingRequestsEndExactlyOnce() throws {
    try withGeneratedExtension(topology) { output, _ in
      let requests = try source("SwifterKitRuntimeAudioRequests.cpp", in: output)
      #expect(requests.contains("kAudioRequestTimeoutNanoseconds = 10'000'000'000ULL"))
      #expect(requests.contains("OSSharedPtr<IODispatchQueue> queue = GetWorkQueue();"))
      #expect(requests.contains("EnqueueRequiredEvent(kSwifterKitEventAudioObject"))
      #expect(requests.contains("(void)TakeRequest(ivars, requestID, nullptr);"))
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
      #expect(sharedApply.contains("SetAcquisitionFailure("))
      #expect(sharedApply.contains("SetIsAcquired(accept ? value != 0 : value == 0)"))
      #expect(sharedApply.contains("FinishSampleRateRequest("))
      // Answers also run on the work queue, so they must not take audioLock or any other lock.
      #expect(!apply.contains("audioLock"))
      #expect(!sharedApply.contains("IOLockLock"))
      let sharedBegin = try section(
        of: media,
        from: "kern_return_t SwifterKitBeginRequest(",
        to: "kern_return_t SwifterKitApplyRequest("
      )
      #expect(sharedBegin.contains("object->retain();"))
      #expect(requests.contains("SwifterKitBeginRequest<AudioRequestFamily>("))
      let timer = try section(of: requests, from: "::AudioRequestTimerOccurred_Impl(", to: "#endif")
      #expect(timer.contains("SwifterKitExpireRequests<AudioRequestFamily>("))
      #expect(timer.contains("RejectAudioRequests(kIOReturnTimeout)"))
      let expire = try section(of: media, from: "void SwifterKitExpireRequests(", to: "#endif")
      #expect(expire.contains("SwifterKitEndRequests<Family>(expired, kIOReturnTimeout);"))
      let stop = try section(
        of: requests,
        from: "::StopAudioRequests()",
        to: "::BeginAudioRequest("
      )
      #expect(stop.contains("RejectAudioRequests(kIOReturnAborted);"))

      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let detach = try section(of: events, from: "(void)AnswerPowerState(0);", to: "StopTimers();")
      #expect(detach.contains("RejectAudioRequests(kIOReturnAborted);"))

      let box = try source("SwifterKitRuntimeAudioBox.cpp", in: output)
      #expect(box.contains("return super::HandleChangeAcquireBox(acquire);"))
      let clock = try source("SwifterKitRuntimeAudioClockDevice.cpp", in: output)
      #expect(clock.contains("return super::HandleChangeSampleRate(sampleRate);"))
      #expect(clock.contains("__DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5"))
    }
  }

  @Test
  func clockDeviceTakesTheSampleRateBeforeReportingSuccess() throws {
    try withGeneratedExtension(topology) { output, _ in
      let clock = try source("SwifterKitRuntimeAudioClockDevice.cpp", in: output)
      let handler = try section(
        of: clock,
        from: "::HandleChangeSampleRate(",
        to: "::FinishSampleRateRequest("
      )
      let unchanged = try #require(handler.range(of: "if (previous == sampleRate)")?.lowerBound)
      let set = try #require(handler.range(of: "SetSampleRate(sampleRate);")?.lowerBound)
      let begin = try #require(handler.range(of: "BeginAudioRequest(")?.lowerBound)
      #expect(unchanged < set)
      #expect(set < begin)
      #expect(handler.contains("__builtin_bit_cast(uint64_t, previous)"))
      #expect(handler.contains("(void)SetSampleRate(previous);"))
      #expect(handler.contains("return super::HandleChangeSampleRate(sampleRate);"))
      #expect(!handler.contains("RequestSampleRate(sampleRate)"))

      let finish = try section(of: clock, from: "::FinishSampleRateRequest(", to: "#endif")
      #expect(
        finish.contains(
          "AudioObjectEvent(\n            kSwifterKitAudioObjectEventClockRateChanged,"
        )
      )
      #expect(finish.contains("GetSampleRate() == requested && IsAvailableSampleRate(previous)"))
      #expect(finish.contains("RequestSampleRate(previous)"))

      let requests = try source("SwifterKitRuntimeAudioRequests.cpp", in: output)
      let media = try source("SwifterKitRuntimeMediaRequests.h", in: output)
      #expect(
        media.contains("*slot = {object, requestID, kind, index, value, previous, deadline};")
      )
      #expect(requests.contains("SwifterKitBeginRequest<AudioRequestFamily>("))
      #expect(!requests.contains("starts a device configuration change"))
      #expect(!media.contains("starts a device configuration change"))
    }
  }

  @Test
  func validatesBoxAndClockDeviceTopology() {
    let invalid: [AudioDeviceConfiguration] = [
      device(boxes: [AudioBoxConfiguration(uid: "Device", name: "Box")]),
      device(boxes: [box("A", clocks: [0]), box("B", clocks: [0])], clocks: [clock("C")]),
      device(boxes: [box("A", clocks: [1])], clocks: [clock("C")]),
      device(boxes: [box("A", ownsDevice: true), box("B", ownsDevice: true)]),
      device(boxes: (0..<5).map { box("B\($0)") }),
      device(clocks: [clock("C", rates: [48_000], initial: 44_100)]),
      device(clocks: [clock("C", rates: [48_000], period: 8)]), device(clocks: [clock("")]),
    ]
    for configuration in invalid {
      #expect(!DriverExtensionGenerator.isValid(audio: configuration))
    }
    #expect(DriverExtensionGenerator.isValid(audio: topology))
  }

  private var topology: AudioDeviceConfiguration {
    device(
      boxes: [
        AudioBoxConfiguration(
          uid: "com.example.box.0",
          name: "Rack",
          transport: .usb,
          isAcquirable: true,
          isAcquired: false,
          hasMIDI: true,
          ownsDevice: true,
          clockDevices: [1]
        ), box("com.example.box.1", clocks: [0]),
      ],
      clocks: [
        AudioClockDeviceConfiguration(
          deviceUID: "com.example.clock.0",
          modelUID: "Model",
          manufacturerUID: "Maker",
          name: "Word Clock",
          sampleRates: [44_100, 48_000],
          initialSampleRate: 48_000,
          clockDomain: 7,
          clockAlgorithm: .twelvePointMovingWindowAverage,
          isHidden: true,
          inputLatency: 12,
          outputLatency: 34,
          wantsControlsRestored: true
        ), clock("com.example.clock.1", rates: [96_000], initial: 96_000),
      ]
    )
  }

  private func device(
    boxes: [AudioBoxConfiguration] = [],
    clocks: [AudioClockDeviceConfiguration] = []
  ) -> AudioDeviceConfiguration {
    AudioDeviceConfiguration(
      deviceUID: "Device",
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Audio",
      sampleRates: [48_000],
      initialSampleRate: 48_000,
      streams: [
        AudioStreamConfiguration(
          direction: .output,
          name: "Out",
          formats: [.linearPCM(sampleRate: 48_000, channels: 2)]
        )
      ],
      boxes: boxes,
      clockDevices: clocks
    )
  }

  private func box(
    _ uid: String,
    ownsDevice: Bool = false,
    clocks: [UInt32] = []
  ) -> AudioBoxConfiguration {
    AudioBoxConfiguration(uid: uid, name: "Box", ownsDevice: ownsDevice, clockDevices: clocks)
  }

  private func clock(
    _ uid: String,
    rates: [Double] = [48_000],
    initial: Double = 48_000,
    period: UInt32 = 32_768
  ) -> AudioClockDeviceConfiguration {
    AudioClockDeviceConfiguration(
      deviceUID: uid,
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Clock",
      zeroTimestampPeriod: period,
      sampleRates: rates,
      initialSampleRate: initial
    )
  }

  private func withGeneratedExtension(
    _ audio: AudioDeviceConfiguration,
    _ body: (URL, URL) throws -> Void
  ) throws {
    try withTemporaryExtension(
      named: "AudioObjectDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.audio-objects",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: .audio,
        audioDevice: audio
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0")
    ) { output, root in try body(output, root.appendingPathComponent("DerivedData")) }
  }
}
