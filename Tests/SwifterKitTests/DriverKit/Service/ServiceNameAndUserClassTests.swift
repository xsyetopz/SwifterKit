import Foundation
import Testing

@testable import SwifterKit

@Suite
struct ServiceNameAndUserClassTests {
  @Test
  func encodesSetName() throws {
    let command = try DriverCommand.setServiceName("my-driver")
    #expect(command.opcode == 0x0D34)
    #expect(command.requiredCapabilities.isEmpty)
    #expect(command.payload == Data("my-driver".utf8))
    #expect(command.maximumResponseSize == RuntimeMessage.headerSize)
  }

  @Test
  func setNameFitsIOServiceName() throws {
    let longest = String(repeating: "a", count: 127)
    #expect(try DriverCommand.setServiceName(longest).payload.count == 127)
    for name in [String(repeating: "a", count: 128), "", "a\0b"] {
      #expect(throws: ServiceRuntimeError.invalidName(name)) {
        try DriverCommand.setServiceName(name)
      }
    }
  }

  @Test
  func watchCarriesUserClass() throws {
    let match = DriverServiceMatch(serviceClass: "IOUserService", userClass: "MyDriver")
    let command = try DriverCommand.watchServices(matching: match)
    #expect(
      try ServicePropertyCoding.decode(command.payload)
        == .dictionary([
          "IOProviderClass": .string("IOUserService"), "IOUserClass": .string("MyDriver"),
        ])
    )
    let plain = try DriverCommand.watchServices(
      matching: DriverServiceMatch(serviceClass: "IOUserService")
    )
    #expect(
      try ServicePropertyCoding.decode(plain.payload)
        == .dictionary(["IOProviderClass": .string("IOUserService")])
    )
    #expect(throws: ServiceRuntimeError.invalidName("")) {
      try DriverCommand.watchServices(
        matching: DriverServiceMatch(serviceClass: "IOUserService", userClass: "")
      )
    }
  }

  @Test
  func schemaMatchesNativeOpcodes() throws {
    #expect(RuntimeOpcode.serviceSetName.rawValue == 0x0D34)
    let header = try String(
      contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(
          "Sources/SwifterKit/Resources/DriverKitExtension/Sources/SwifterKitRuntimeSchema.h"
        ),
      encoding: .utf8
    )
    #expect(header.contains("ServiceSetName = 0x0D34,"))
    #expect(header.contains("NetworkGetBSDName = 0x0926,"))
    #expect(header.contains("HIDGetElementDataValue = 0x0345,"))
    #expect(RuntimeOpcode.networkGetBSDName.rawValue == 0x0926)
    #expect(RuntimeOpcode.hidGetElementDataValue.rawValue == 0x0345)
  }
}
