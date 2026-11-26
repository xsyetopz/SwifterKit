#if canImport(IOKit)
  import CoreFoundation
  import Foundation
  import IOKit

  var defaultIOKitMainPort: mach_port_t {
    kIOMainPortDefault
  }

  /// Native macOS transport for I/O Registry discovery and user-client connections.
  public actor IOKitDriverTransport: DriverTransport {
    /// Creates a native IOKit transport.
    public init() {}

    /// Returns services matching the supplied registry criteria.
    public func services(matching criteria: DriverServiceMatch) throws -> [DriverService] {
      guard !criteria.serviceClass.isEmpty, unsafe IOServiceMatching(criteria.serviceClass) != nil
      else {
        throw DriverKitError(kind: .invalidServiceClass, operation: "IOServiceMatching")
      }

      var matching: [String: Any] = ["IOProviderClass": criteria.serviceClass]
      if let name = criteria.name { matching["IONameMatch"] = name }
      if !criteria.registryProperties.isEmpty {
        matching["IOPropertyMatch"] = criteria.registryProperties.mapValues(\.foundationValue)
      }

      var iterator: io_iterator_t = 0
      let result = unsafe IOServiceGetMatchingServices(
        defaultIOKitMainPort,
        matching as CFDictionary,
        &iterator
      )
      guard result == kIOReturnSuccess else {
        throw DriverKitError(kind: .ioReturn(result), operation: "IOServiceGetMatchingServices")
      }
      defer { IOObjectRelease(iterator) }

      var services: [DriverService] = []
      while true {
        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { break }
        defer { IOObjectRelease(entry) }
        services.append(describe(entry))
      }
      return services
    }

    /// Opens a user-client connection to a discovered service.
    public func open(_ service: DriverService, type: UInt32) throws -> any DriverConnection {
      let matching = IORegistryEntryIDMatching(service.id)
      let entry = IOServiceGetMatchingService(defaultIOKitMainPort, matching)
      guard entry != 0 else {
        throw DriverKitError(
          kind: .serviceUnavailable,
          operation: "IOServiceGetMatchingService",
          serviceID: service.id
        )
      }
      defer { IOObjectRelease(entry) }

      var connection: io_connect_t = 0
      let result = unsafe IOServiceOpen(entry, mach_task_self_, type, &connection)
      guard result == kIOReturnSuccess else {
        throw DriverKitError(
          kind: .ioReturn(result),
          operation: "IOServiceOpen",
          serviceID: service.id
        )
      }
      return IOKitDriverConnection(connection: connection, serviceID: service.id)
    }

    private func describe(_ entry: io_registry_entry_t) -> DriverService {
      var identifier: UInt64 = 0
      unsafe IORegistryEntryGetRegistryEntryID(entry, &identifier)

      var nameBuffer = [CChar](repeating: 0, count: 128)
      let nameResult = unsafe IORegistryEntryGetName(entry, &nameBuffer)
      let name = nameResult == kIOReturnSuccess ? decodeCString(nameBuffer) ?? "Unknown" : "Unknown"

      var pathBuffer = [CChar](repeating: 0, count: 1_024)
      let pathResult = unsafe IORegistryEntryGetPath(entry, kIOServicePlane, &pathBuffer)
      let path = pathResult == kIOReturnSuccess ? decodeCString(pathBuffer) : nil

      return DriverService(
        id: identifier,
        name: name,
        registryPath: path,
        properties: properties(of: entry)
      )
    }

    private func decodeCString(_ buffer: [CChar]) -> String? {
      let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
      return String(bytes: bytes, encoding: .utf8)
    }

    private func properties(of entry: io_registry_entry_t) -> [String: DriverProperty] {
      var rawProperties: Unmanaged<CFMutableDictionary>?
      let result = unsafe IORegistryEntryCreateCFProperties(
        entry,
        &rawProperties,
        kCFAllocatorDefault,
        0
      )
      guard result == kIOReturnSuccess, let createdProperties = unsafe rawProperties else {
        return [:]
      }

      guard let dictionary = unsafe createdProperties.takeRetainedValue() as? [String: Any] else {
        return [:]
      }
      return dictionary.compactMapValues(DriverProperty.decode)
    }
  }
#endif
