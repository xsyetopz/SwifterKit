import Foundation
import Testing

@testable import SwifterKit

@Suite
struct EthernetBSDNameTests {
  @Test
  func encodesBSDNameRead() {
    let command = DriverCommand.ethernetBSDName
    #expect(command.opcode == 0x0926)
    #expect(command.requiredCapabilities == .networking)
    #expect(command.payload.isEmpty)
    #expect(command.maximumResponseSize == RuntimeMessage.headerSize + 127)
  }
}
