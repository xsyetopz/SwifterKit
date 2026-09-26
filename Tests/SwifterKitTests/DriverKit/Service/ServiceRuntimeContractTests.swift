import Foundation
import Testing

@testable import SwifterKit

@Suite
struct ServiceRuntimeContractTests {
  @Test
  func userClientRoutesEveryServiceOpcodeWithoutACapability() throws {
    try withGeneratedExtension { output in
      let userClient = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let group = try section(
        of: userClient,
        from: "case SwifterKitRuntimeOpcode::ServiceSetProperties:",
        to: "case SwifterKitRuntimeOpcode::InterruptSetEnabled:"
      )
      let serviceOpcodes = RuntimeOpcode.allCases.filter { $0.rawValue & 0xFF00 == 0x0D00 }
      #expect(serviceOpcodes.count == 20)
      for opcode in serviceOpcodes {
        let name = String(describing: opcode)
        let native = name.prefix(1).uppercased() + name.dropFirst()
        #expect(group.contains("case SwifterKitRuntimeOpcode::\(native):"))
      }
      #expect(group.contains("return DispatchServiceCommand(context);"))
      #expect(!group.contains("#if"))
      let dispatch = try section(
        of: userClient,
        from: "kern_return_t DispatchServiceCommand(",
        to: "kern_return_t DispatchInterruptCommand("
      )
      #expect(dispatch.contains("service->ServiceCommand("))
      #expect(!dispatch.contains("#if"))
      // Service replies use RespondWithData, so no family flag may compile it out.
      let helpers = try source("SwifterKitRuntimeUserClientHelpers.h", in: output)
      let respond = try #require(helpers.range(of: "kern_return_t RespondWithData(")?.lowerBound)
      let preceding = helpers[..<respond].split(separator: "\n").last {
        !$0.allSatisfy(\.isWhitespace)
      }
      #expect(preceding?.trimmingCharacters(in: .whitespaces) == "}")
    }
  }

  @Test
  func propertyCodecMatchesSwiftLimits() throws {
    try withGeneratedExtension { output in
      #expect(
        try source("SwifterKitRuntimeServiceProtocol.h", in: output).contains(
          "#include \"SwifterKitRuntimeSchema.h\""
        )
      )
      let protocolHeader = try source(RuntimeSchemaHeader.fileName, in: output)
      #expect(
        protocolHeader.contains(
          "kSwifterKitPropertyMaximumDepth = \(ServicePropertyCoding.maximumDepth);"
        )
      )
      #expect(
        protocolHeader.contains(
          "kSwifterKitPropertyNameMaximumLength = \(ServicePropertyCoding.maximumNameLength);"
        )
      )
      for tag in [ServicePropertyCoding.Tag.boolean, .number, .string, .data, .array, .dictionary] {
        let name = String(describing: tag)
        #expect(
          protocolHeader.contains(
            "\(name.prefix(1).uppercased() + name.dropFirst()) = \(tag.rawValue),"
          )
        )
      }

      let codec = try source("SwifterKitRuntimeServiceProperties.cpp", in: output)
      #expect(codec.contains("count > reader->remaining() / 2"))
      #expect(codec.contains("count > reader->remaining() / 7"))
      #expect(codec.contains("dictionary->getObject(name) != nullptr"))
      #expect(codec.contains("HasNul(key, keyLength)"))
      #expect(codec.contains("depth > kSwifterKitPropertyMaximumDepth"))
      #expect(codec.contains("reader.remaining() != 0"))
      #expect(codec.contains("(bits < 64 && (value >> bits) != 0)"))
      // Wire strings carry no NUL, so they are terminated before OSString copies them.
      #expect(codec.contains("OSString::withCString(copy);"))

      let control = try source("SwifterKitRuntimeServiceControl.cpp", in: output)
      #expect(
        control.contains("kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize;")
      )
      #expect(control.contains("SwifterKitEncodeProperty(value, data, kMaximumResponseLength)"))
      #expect(!control.contains("OSString::withCString(") && !codec.contains("withCString(start"))
      // A missing property is an empty reply, which Swift reads as nil.
      let search = try section(
        of: control,
        from: "case SwifterKitRuntimeOpcode::ServiceSearchProperty:",
        to: "case SwifterKitRuntimeOpcode::ServiceCopyProviderProperties:"
      )
      #expect(search.contains("if (result == kIOReturnNotFound"))
      #expect(search.contains("|| (result == kIOReturnSuccess && property == nullptr)) {"))
    }
  }

  @Test
  func nativeRevalidatesPowerAndBusyRequests() throws {
    try withGeneratedExtension { output in
      let control = try source("SwifterKitRuntimeServiceControl.cpp", in: output)
      for (name, option) in [
        ("CPU", ServicePMAssertionOptions.cpu), ("ForceFullWakeup", .forceFullWakeup),
      ] {
        #expect(control.contains("kPMAssertion\(name) = 0x\(String(option.rawValue, radix: 16));"))
      }
      #expect(control.contains("(header->synced != 0 && bits != kPMAssertionCPU)"))
      let assertion = try section(
        of: control,
        from: "case SwifterKitRuntimeOpcode::ServiceCreatePMAssertion:",
        to: "case SwifterKitRuntimeOpcode::ServiceReleasePMAssertion:"
      )
      #expect(
        assertion.contains(
          "#if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5"
        )
      )
      #expect(assertion.contains("return kIOReturnUnsupported;"))
      #expect(control.contains("return delta == 0 ? kIOReturnBadArgument : AdjustBusy(delta);"))
      for stall in ["None", "5usec", "10usec", "20usec", "25usec", "30usec", "40usec"] {
        #expect(control.contains("case kIOMaxBusStall\(stall):"))
      }
      #expect(control.contains("flags == kIOServicePowerCapabilityLow"))
      #expect(control.contains("completion->requestID == 0 || completion->reserved != 0"))
    }
  }

  @Test
  func everyPowerRequestIsAcknowledgedExactlyOnce() throws {
    try withGeneratedExtension { output in
      let power = try source("SwifterKitRuntimeServicePower.cpp", in: output)
      #expect(power.contains("kPowerStateTimeoutNanoseconds = 10'000'000'000ULL;"))
      let setPower = try section(
        of: power,
        from: "::SetPowerState_Impl(",
        to: "::PowerStateTimerOccurred_Impl("
      )
      // A newer change supersedes the pending one before anything else.
      let supersede = try #require(setPower.range(of: "(void)AnswerPowerState(0);")?.lowerBound)
      let timer = try #require(setPower.range(of: "IOTimerDispatchSource::Create(")?.lowerBound)
      #expect(supersede < timer)
      #expect(setPower.contains("ReleasePowerTimer(ivars);"))
      #expect(setPower.contains("ivars->powerTimer->SetEnableWithCompletion(true, nullptr)"))
      // No host, a stopped service, or a failed timer acknowledges immediately.
      #expect(
        setPower.contains(
          "result == kIOReturnSuccess && !ivars->powerStopped && ivars->eventClient != nullptr;"
        )
      )
      #expect(
        setPower.contains(
          "if (!forward) {\n        return SetPowerState(powerFlags, SUPERDISPATCH);"
        )
      )
      let enqueue = try #require(
        setPower.range(of: "EnqueueRequiredEvent(kSwifterKitEventServicePowerState")?.upperBound
      )
      #expect(setPower[enqueue...].contains("(void)AnswerPowerState(requestID);"))

      let fired = try section(
        of: power,
        from: "::PowerStateTimerOccurred_Impl(",
        to: "::AnswerPowerState("
      )
      #expect(
        fired.contains("if (Now() >= deadline) {\n        (void)AnswerPowerState(requestID);")
      )
      #expect(fired.contains("->WakeAtTime("))

      let answer = try section(of: power, from: "::AnswerPowerState(", to: "::StopPower(")
      let unlock = try #require(answer.range(of: "IOLockUnlock(ivars->eventLock);")?.lowerBound)
      let acknowledge = try #require(
        answer.range(of: "SetPowerState(powerFlags, SUPERDISPATCH)")?.lowerBound
      )
      #expect(unlock < acknowledge)
      #expect(answer.contains("ivars->powerPending = false;"))

      let stop = try #require(power.range(of: "::StopPower(").map { power[$0.lowerBound...] })
      #expect(stop.contains("ivars->powerStopped = true;"))
      #expect(stop.contains("(void)AnswerPowerState(0);"))
      #expect(stop.contains("ReleasePowerTimer(ivars);"))
      #expect(power.contains("(void)state->powerTimer->Cancel(nullptr);"))

      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      let detach = try section(of: events, from: "::DetachEventClient(", to: "::CopyNextEvent(")
      let release = try #require(detach.range(of: "detached->release();")?.lowerBound)
      let answered = try #require(detach.range(of: "(void)AnswerPowerState(0);")?.lowerBound)
      #expect(release < answered)

      let service = try source("SwifterKitRuntimeService.cpp", in: output)
      let stopImpl = try section(
        of: service,
        from: "::Stop_Impl(",
        to: "return Stop(provider, SUPERDISPATCH);"
      )
      #expect(stopImpl.contains("StopPower();"))
      let free = try section(of: service, from: "::free()", to: "IOLockFreeZero(ivars->eventLock);")
      #expect(free.contains("StopPower();"))
    }
  }

  @Test
  func everyServiceInterfaceOverridesSetPowerStatePublicly() throws {
    let configurations = [
      DriverConfiguration(
        bundleIdentifier: "com.example.service",
        providerClass: "IOUserResources",
        capabilities: []
      ),
      DriverConfiguration(
        bundleIdentifier: "com.example.contract-network",
        providerClass: "IOUserResources",
        capabilities: .networking,
        ethernetDevice: EthernetDeviceConfiguration(
          hardwareAddress: EthernetAddress(2, 3, 4, 5, 6, 7)
        )
      ),
    ]
    let checkedIn = try String(
      contentsOf: Self.nativeSources.appendingPathComponent("SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    let interfaces = configurations.map(DriverExtensionGenerator.serviceInterface) + [checkedIn]
    for interface in interfaces {
      let declaration = try #require(
        interface.range(of: "virtual kern_return_t SetPowerState(uint32_t powerFlags) override;")
      )
      #expect(!interface[..<declaration.lowerBound].contains("protected:"))
      #expect(!interface[..<declaration.lowerBound].contains("private:"))
      #expect(interface.contains("TYPE(IOTimerDispatchSource::TimerOccurred);"))
      #expect(interface.contains("#include <DriverKit/IOTimerDispatchSource.iig>"))
      #expect(interface.contains("kern_return_t ServiceCommand("))
    }
  }

  private static let nativeSources = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
    url.deletingLastPathComponent()
  }.appendingPathComponent("Sources/SwifterKit/Resources/DriverKitExtension/Sources")

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("ServiceDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.contract-service",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: []
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
      at: output
    )
    try body(output)
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
