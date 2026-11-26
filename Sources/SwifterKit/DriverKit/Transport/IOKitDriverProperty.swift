#if canImport(IOKit)
  import CoreFoundation
  import Foundation

  extension DriverProperty {
    // Decodes an I/O Registry property-list value.
    //
    // Booleans and numbers are identified by CoreFoundation type because bridged numbers 0 and
    // 1 also cast to `Bool`. IOKit publishes integers as signed CoreFoundation numbers.
    static func decode(_ value: Any) -> Self? {
      let object = value as CFTypeRef
      let type = CFGetTypeID(object)
      switch type {
      case CFBooleanGetTypeID():
        return unsafe .boolean(CFBooleanGetValue(unsafeDowncast(object, to: CFBoolean.self)))
      case CFNumberGetTypeID(): return unsafe decode(unsafeDowncast(object, to: CFNumber.self))
      default: break
      }
      if let string = value as? String { return .string(string) }
      if let data = value as? Data { return .data(data) }
      if let values = value as? [Any] { return .array(values.compactMap(Self.decode)) }
      if let values = value as? [String: Any] {
        return .dictionary(values.compactMapValues(Self.decode))
      }
      return nil
    }

    private static func decode(_ number: CFNumber) -> Self? {
      if CFNumberIsFloatType(number) {
        var value = 0.0
        return unsafe CFNumberGetValue(number, .float64Type, &value) ? .real(value) : nil
      }
      var value: Int64 = 0
      return unsafe CFNumberGetValue(number, .sInt64Type, &value) ? .integer(value) : nil
    }
  }
#endif
