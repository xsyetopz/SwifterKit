import Foundation
import Testing

@testable import SwifterKit

@Suite
struct MIDIObjectRuntimeContractTests {
  @Test
  func routesEveryMIDIOpcodeThroughTheMIDIFamily() throws {
    try withGeneratedExtension { output in
      let dispatch = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      let group = try section(
        of: dispatch,
        from: "case SwifterKitRuntimeOpcode::MIDISend:",
        to: "return DispatchMIDICommand(context);"
      )
      let opcodes = RuntimeOpcode.allCases.filter { (0x0810...0x0819).contains($0.rawValue) }
      #expect(opcodes.count == 10)
      for opcode in opcodes {
        let name = String(describing: opcode).dropFirst("midi".count)
        #expect(group.contains("case SwifterKitRuntimeOpcode::MIDI\(name):"))
      }
      let family = try section(of: dispatch, from: "DispatchMIDICommand(", to: "#else")
      #expect(family.contains("return RespondToCommand(context, result, response);"))

      let midi = try source("SwifterKitRuntimeMIDI.cpp", in: output)
      let command = try section(of: midi, from: "::MIDICommand(", to: "::MIDIReceived(")
      #expect(
        command.contains("return MIDIObjectCommand(opcode, payload, payloadLength, response);")
      )
    }
  }

  @Test
  func publishesAndReadsMIDIObjectsUnderTheLock() throws {
    try withGeneratedExtension { output in
      let midi = try source("SwifterKitRuntimeMIDI.cpp", in: output)
      let start = try section(of: midi, from: "::StartMIDI()", to: "::StopMIDI()")
      let published = start.range(of: "IOLockLock(ivars->midiLock);\n        device->retain();")
      let publish = try #require(published?.lowerBound)
      let assign = try #require(start.range(of: "ivars->midiDevice = device.get();")?.lowerBound)
      #expect(publish < assign)
      #expect(start.contains("(void)RemoveObject(device.get());"))

      let stop = try section(of: midi, from: "::StopMIDI()", to: "::MIDICommand(")
      let unlock = try #require(stop.range(of: "IOLockUnlock(ivars->midiLock);")?.lowerBound)
      let removal = try #require(stop.range(of: "RemoveObject(device)")?.lowerBound)
      #expect(unlock < removal)

      let send = try section(of: midi, from: "::MIDICommand(", to: "::MIDIReceived(")
      #expect(send.contains("source->retain();"))
      #expect(send.contains("source->release();"))
      let received = try section(of: midi, from: "::MIDIReceived(", to: "::CopyMIDIDevice()")
      #expect(!received.contains("midiLock"))

      let lifecycle = try source("SwifterKitRuntimeLifecycle.cpp", in: output)
      #expect(lifecycle.contains("ivars->midiLock = IOLockAlloc();"))
      let service = try source("SwifterKitRuntimeService.cpp", in: output)
      #expect(service.contains("StopMIDI();\n        IOLockFreeZero(ivars->midiLock);"))
    }
  }

  @Test
  func callsEachMIDIDriverKitMember() throws {
    try withGeneratedExtension { output in
      let objects = try source("SwifterKitRuntimeMIDIObjects.cpp", in: output)
      for call in [
        "GetMIDIObjectForObjectID(index)", "GetObjectID()", "GetOwnerObjectID()", "GetClassID()",
        "GetBaseClassID()", "GetName()", "SetName(name)", "GetPropertyType(Selector(key), &type)",
        "CopyProperty(key.name, &value)", "CopyProperty(Selector(key), &value)",
        "SetProperty(key.name, value)", "SetProperty(Selector(key), value)", "GetProperties()",
        "SetProperties(dictionary)", "GetEntities()", "GetDeviceIsRunning()", "GetSources()",
        "GetDestinations()", "AddEntity(entity)", "RemoveEntity(entity)", "AddSource(source)",
        "RemoveSource(source)", "AddDestination(destination)", "RemoveDestination(destination)",
      ] { #expect(objects.contains(call), Comment(rawValue: call)) }
      let properties = try source("SwifterKitRuntimeMIDIProperties.cpp", in: output)
      let header = try source(RuntimeSchemaHeader.fileName, in: output)
      #expect(
        header.contains("kSwifterKitMIDIPropertyMaximumDepth = \(MIDIPropertyValue.maximumDepth);")
      )
      #expect(
        header.contains(
          "kSwifterKitMIDIPropertyMaximumEntries = \(MIDIPropertyValue.maximumEntries);"
        )
      )
      #expect(
        header.contains("kSwifterKitMIDIMaximumListedObjects = \(MIDIObjectIDList.maximumCount);")
      )
      #expect(properties.contains("depth > kSwifterKitMIDIPropertyMaximumDepth"))
      #expect(objects.contains("count > kSwifterKitMIDIMaximumListedObjects"))
      #expect(properties.contains("dictionary->getObject(key) != nullptr"))
      #expect(
        properties.contains("kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize")
      )
    }
  }

  private func withGeneratedExtension(_ body: (URL) throws -> Void) throws {
    try withTemporaryExtension(
      named: "MIDIObjectDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.midi-objects",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: .midi,
        midiDevice: MIDIDeviceConfiguration(
          driverName: "Objects",
          deviceIdentifier: "Device",
          modelIdentifier: "Model",
          manufacturerIdentifier: "Maker",
          entityName: "Entity",
          protocol: .midi2,
          sourceCount: 2,
          destinationCount: 1
        )
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "24.0")
    ) { output, _ in try body(output) }
  }
}
