import Foundation
import Testing

@testable import SwifterKit

@Suite
struct VideoObjectRuntimeContractTests {
  @Test
  func generatesBoxesAndClockDevices() throws {
    try withGeneratedExtension(topology) { output, _ in
      let config = try source("SwifterKitRuntimeConfiguration.h", in: output)
      #expect(config.contains("kSwifterKitVideoBoxCount = 2"))
      #expect(config.contains("kSwifterKitVideoClockDeviceCount = 2"))
      #expect(config.contains("1970496032, true, false, false, false, true, false, true, 2}"))
      #expect(config.contains("0, false, true, false, false, true, false, false, 1}"))
      #expect(config.contains("kSwifterKitVideoClockSampleRates[3] = {30.0, 60.0, 120.0}"))
      #expect(config.contains("1835103847, true, true, 12, 34}"))
      #expect(config.contains("1768518246, true, false, 0, 0}"))

      let service = try source("SwifterKitRuntimeService.iig", in: output)
      #expect(service.contains("IOUserVideoObjectID objectID,"))
      #expect(service.contains("VideoRequestTimerOccurred(OSAction* action, uint64_t time)"))
      #expect(service.contains("TYPE(IOTimerDispatchSource::TimerOccurred)"))

      let project = try source("../SwifterKitRuntime.xcodeproj/project.pbxproj", in: output)
      for name in [
        "SwifterKitRuntimeVideoBox.iig", "SwifterKitRuntimeVideoBox.cpp",
        "SwifterKitRuntimeVideoClockDevice.iig", "SwifterKitRuntimeVideoClockDevice.cpp",
        "SwifterKitRuntimeVideoObjects.cpp", "SwifterKitRuntimeVideoRequests.cpp",
      ] { #expect(project.contains("\(name) in Sources")) }
    }
  }

  @Test(.enabled(if: DriverKitSDK.supports(deploymentTarget: "27.0")))
  func buildsBoxesAndClockDevices() throws {
    try withGeneratedExtension(topology) { output, derivedData in
      try expectGeneratedExtensionBuilds(at: output, derivedData: derivedData)
    }
  }

  @Test
  func routesEveryVideoObjectOpcodeThroughTheVideoFamily() throws {
    try withGeneratedExtension(topology) { output, _ in
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let group = try section(
        of: dispatch,
        from: "case SwifterKitRuntimeOpcode::VideoRequestSampleRate:",
        to: "return DispatchMediaCommand(context);"
      )
      let opcodes = RuntimeOpcode.allCases.filter { (0x0C10...0x0C1F).contains($0.rawValue) }
      #expect(opcodes.count == 16)
      for opcode in opcodes {
        let name = String(describing: opcode)
        #expect(
          group.contains(
            "case SwifterKitRuntimeOpcode::\(name.prefix(1).uppercased())\(name.dropFirst()):"
          )
        )
      }
      let video = try source("SwifterKitRuntimeVideo.cpp", in: output)
      let command = try section(
        of: video,
        from: "SwifterKitRuntimeService::VideoCommand(",
        to: "IOLockLock(ivars->videoLock)"
      )
      #expect(
        command.contains("return VideoObjectCommand(opcode, payload, payloadLength, response);")
      )
    }
  }

  @Test
  func publishesAndTearsDownTheDeviceUnderTheVideoLock() throws {
    try withGeneratedExtension(topology) { output, _ in
      let video = try source("SwifterKitRuntimeVideo.cpp", in: output)
      let start = try section(of: video, from: "::StartVideo()", to: "::StopVideo()")
      let publish = try #require(start.range(of: "ivars->videoDevice = device;")?.lowerBound)
      let lock = try #require(
        start.range(of: "IOLockLock(ivars->videoLock);", options: .backwards)?.lowerBound
      )
      #expect(lock < publish)
      #expect(start.contains("result = StartVideoObjects();"))

      let stop = try section(of: video, from: "::StopVideo()", to: "::VideoControlEvent(")
      let objects = try #require(stop.range(of: "StopVideoObjects();")?.lowerBound)
      let members = try #require(stop.range(of: "RemoveControlsAndProperties();")?.lowerBound)
      let removal = try #require(stop.range(of: "RemoveObject(device)")?.lowerBound)
      #expect(objects < members && members < removal)

      let controls = try source("SwifterKitRuntimeVideoControls.cpp", in: output)
      let teardown = try section(
        of: controls,
        from: "::RemoveControlsAndProperties()",
        to: "#endif"
      )
      #expect(teardown.contains("RemoveControl(ivars->controls[index])"))
      #expect(teardown.contains("kSwifterKitVideoOwnerDetached"))
      let owner = try section(
        of: controls,
        from: "::SetCustomPropertyOwner(",
        to: "::RemoveControlsAndProperties()"
      )
      #expect(owner.contains("ivars->service->AddCustomProperty(property)"))
      #expect(owner.contains("ivars->service->RemoveCustomProperty(property)"))
      #expect(owner.contains("RemoveCustomProperty(property)"))
    }
  }

  @Test
  func pendingRequestsEndExactlyOnce() throws {
    try withGeneratedExtension(topology) { output, _ in
      let requests = try source("SwifterKitRuntimeVideoRequests.cpp", in: output)
      #expect(requests.contains("kVideoRequestTimeoutNanoseconds = 10'000'000'000ULL"))
      #expect(requests.contains("OSSharedPtr<IODispatchQueue> queue = GetWorkQueue();"))
      #expect(requests.contains("EnqueueRequiredEvent(kSwifterKitEventVideoObject"))
      #expect(requests.contains("(void)TakeRequest(ivars, requestID, nullptr);"))
      let apply = try section(
        of: requests,
        from: "::ApplyVideoRequest(",
        to: "::RejectVideoRequests("
      )
      #expect(apply.contains("SetAcquisitionFailure("))
      #expect(apply.contains("SetIsAcquired(accept ? value != 0 : value == 0)"))
      #expect(apply.contains("RequestSampleRate("))
      // Answers also run on the work queue, so they must not take videoLock.
      #expect(!apply.contains("videoLock"))
      #expect(requests.contains("object->retain();"))
      let stop = try section(
        of: requests,
        from: "::StopVideoRequests()",
        to: "::BeginVideoRequest("
      )
      #expect(stop.contains("RejectVideoRequests(kIOReturnAborted);"))

      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let detach = try section(of: events, from: "(void)AnswerPowerState(0);", to: "StopTimers();")
      #expect(detach.contains("RejectVideoRequests(kIOReturnAborted);"))

      let box = try source("SwifterKitRuntimeVideoBox.cpp", in: output)
      let handler = try section(of: box, from: "::HandleChangeAcquireBox(", to: "#endif")
      let set = try #require(handler.range(of: "SetIsAcquired(acquire);")?.lowerBound)
      let begin = try #require(handler.range(of: "BeginVideoRequest(")?.lowerBound)
      #expect(set < begin)
      #expect(handler.contains("return super::HandleChangeAcquireBox(acquire);"))
      let clock = try source("SwifterKitRuntimeVideoClockDevice.cpp", in: output)
      #expect(clock.contains("kIOReturnNotAttached ? RequestSampleRate(sampleRate)"))
      #expect(clock.contains("VideoObjectEvent(8, ivars->index, streamID)"))
    }
  }

  @Test
  func validatesBoxAndClockDeviceTopology() {
    let invalid: [VideoDeviceConfiguration] = [
      device(boxes: [VideoBoxConfiguration(uid: "Device", name: "Box")]),
      device(boxes: [box("A", clocks: [0]), box("B", clocks: [0])], clocks: [clock("C")]),
      device(boxes: [box("A", clocks: [1])], clocks: [clock("C")]),
      device(boxes: [box("A", ownsDevice: true), box("B", ownsDevice: true)]),
      device(boxes: (0..<5).map { box("B\($0)") }),
      device(clocks: [clock("C", rates: [60], initial: 30)]),
      device(clocks: [clock("C", rates: [0])]), device(clocks: [clock("C", rates: [.nan])]),
      device(clocks: [clock("C", rates: (1...17).map(Double.init), initial: 1)]),
      device(clocks: [clock("")]),
    ]
    for configuration in invalid {
      #expect(!DriverExtensionGenerator.isValid(video: configuration))
    }
    #expect(DriverExtensionGenerator.isValid(video: topology))
  }

  private var topology: VideoDeviceConfiguration {
    device(
      boxes: [
        VideoBoxConfiguration(
          uid: "com.example.box.0",
          name: "Rack",
          transport: .usb,
          isAcquirable: true,
          isAcquired: false,
          ownsDevice: true,
          clockDevices: [1]
        ), box("com.example.box.1", clocks: [0]),
      ],
      clocks: [
        VideoClockDeviceConfiguration(
          deviceUID: "com.example.clock.0",
          modelUID: "Model",
          manufacturerUID: "Maker",
          name: "Reference",
          sampleRates: [30, 60],
          initialSampleRate: 60,
          clockDomain: 7,
          clockAlgorithm: .twelvePointMovingWindowAverage,
          isHidden: true,
          inputLatency: 12,
          outputLatency: 34
        ), clock("com.example.clock.1", rates: [120], initial: 120),
      ]
    )
  }

  private func device(
    boxes: [VideoBoxConfiguration] = [],
    clocks: [VideoClockDeviceConfiguration] = []
  ) -> VideoDeviceConfiguration {
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
      customProperties: [
        VideoCustomPropertyConfiguration(identifier: 3, selector: 0x7377_6B70, values: ["A": "B"])
      ],
      boxes: boxes,
      clockDevices: clocks
    )
  }

  private func box(
    _ uid: String,
    ownsDevice: Bool = false,
    clocks: [UInt32] = []
  ) -> VideoBoxConfiguration {
    VideoBoxConfiguration(uid: uid, name: "Box", ownsDevice: ownsDevice, clockDevices: clocks)
  }

  private func clock(
    _ uid: String,
    rates: [Double] = [60],
    initial: Double = 60
  ) -> VideoClockDeviceConfiguration {
    VideoClockDeviceConfiguration(
      deviceUID: uid,
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Clock",
      sampleRates: rates,
      initialSampleRate: initial
    )
  }

  private func withGeneratedExtension(
    _ video: VideoDeviceConfiguration,
    _ body: (URL, URL) throws -> Void
  ) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("VideoObjectDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.video-objects",
        providerClass: "IOService",
        capabilities: .video,
        videoDevice: video
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "27.0"),
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
