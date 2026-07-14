import Testing

@testable import SwifterKit

@Suite struct DriverKitErrorTests {
  @Test func descriptionIncludesContext() {
    let error = DriverKitError(kind: .ioReturn(-1), operation: "IOServiceOpen", serviceID: 42)

    #expect(error.description.contains("IOServiceOpen"))
    #expect(error.description.contains("-1"))
    #expect(error.description.contains("42"))
  }

  @Test func errorsCompareByAllFields() {
    let first = DriverKitError(kind: .sessionClosed, operation: "call", serviceID: 1)
    let second = DriverKitError(kind: .sessionClosed, operation: "call", serviceID: 1)
    let different = DriverKitError(kind: .sessionClosed, operation: "call", serviceID: 2)

    #expect(first == second)
    #expect(first != different)
  }
}
