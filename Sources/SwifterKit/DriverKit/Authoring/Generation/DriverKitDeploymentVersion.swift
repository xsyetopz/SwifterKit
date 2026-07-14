struct DriverKitDeploymentVersion: Comparable, Sendable {
  static let v19 = Self(major: 19, minor: 0)
  static let v20Point4 = Self(major: 20, minor: 4)
  static let v21 = Self(major: 21, minor: 0)
  static let v22 = Self(major: 22, minor: 0)
  static let v24 = Self(major: 24, minor: 0)
  static let v27 = Self(major: 27, minor: 0)

  let major: Int
  let minor: Int

  private init(major: Int, minor: Int) {
    self.major = major
    self.minor = minor
  }

  init?(_ value: String) {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count),
      parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } }),
      let major = Int(parts[0]), let minor = parts.count == 2 ? Int(parts[1]) : 0
    else { return nil }

    self.major = major
    self.minor = minor
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.major < rhs.major || (lhs.major == rhs.major && lhs.minor < rhs.minor)
  }
}
