import Foundation

/// The property scope used by an VideoDriverKit control or custom property.
public struct VideoObjectScope: RawRepresentable, Sendable, Hashable {
  /// The unmodified VideoDriverKit value.
  public let rawValue: UInt32
  /// Creates a value from the supplied VideoDriverKit fields.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Properties that apply to the complete object.
  public static let global = Self(rawValue: 0x676C_6F62)
  /// Properties that apply to the input side.
  public static let input = Self(rawValue: 0x696E_7074)
  /// Properties that apply to the output side.
  public static let output = Self(rawValue: 0x6F75_7470)
  /// Properties that apply to play-through behavior.
  public static let playThrough = Self(rawValue: 0x7074_7275)
}

/// The class identifier reported for an VideoDriverKit control.
public struct VideoControlClass: RawRepresentable, Sendable, Hashable {
  /// The unmodified VideoDriverKit value.
  public let rawValue: UInt32
  /// Creates a value from the supplied VideoDriverKit fields.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// A generic boolean control.
  public static let boolean = Self(rawValue: 0x746F_676C)
  /// A mute control.
  public static let mute = Self(rawValue: 0x6D75_7465)
  /// A solo control.
  public static let solo = Self(rawValue: 0x736F_6C6F)
  /// A jack-presence control.
  public static let jack = Self(rawValue: 0x6A61_636B)
  /// A generic level control.
  public static let level = Self(rawValue: 0x6C65_766C)
  /// A volume control.
  public static let volume = Self(rawValue: 0x766C_6D65)
  /// A generic selector control.
  public static let selector = Self(rawValue: 0x736C_6374)
  /// A data-source selector.
  public static let dataSource = Self(rawValue: 0x6473_7263)
  /// A data-destination selector.
  public static let dataDestination = Self(rawValue: 0x6465_7374)
  /// A clock-source selector.
  public static let clockSource = Self(rawValue: 0x636C_636B)
  /// A generic integer slider.
  public static let slider = Self(rawValue: 0x736C_6472)
  /// A stereo pan control.
  public static let stereoPan = Self(rawValue: 0x7370_616E)
  /// A stream-direction control.
  public static let direction = Self(rawValue: 0x6469_7265)
}

/// Metadata shared by VideoDriverKit controls.
public struct VideoControlMetadata: Sendable, Hashable {
  /// A stable identifier used by Swift runtime commands.
  public let identifier: UInt32
  /// The human-readable name published to the host.
  public let name: String
  /// Whether the host and Swift runtime may change the value.
  public let isSettable: Bool
  /// The VideoDriverKit property element.
  public let element: UInt32
  /// The VideoDriverKit property scope.
  public let scope: VideoObjectScope
  /// The class identifier reported to the host.
  public let controlClass: VideoControlClass

  /// Creates a value from the supplied VideoDriverKit fields.
  public init(
    identifier: UInt32,
    name: String,
    isSettable: Bool = true,
    element: UInt32 = 0,
    scope: VideoObjectScope = .global,
    controlClass: VideoControlClass
  ) {
    self.identifier = identifier
    self.name = name
    self.isSettable = isSettable
    self.element = element
    self.scope = scope
    self.controlClass = controlClass
  }
}

/// Configuration for a boolean VideoDriverKit control.
public struct VideoBooleanControlConfiguration: Sendable, Hashable {
  /// Metadata shared by the control.
  public let metadata: VideoControlMetadata
  /// The value selected when the device is created.
  public let initialValue: Bool
  /// Creates a value from the supplied VideoDriverKit fields.
  public init(metadata: VideoControlMetadata, initialValue: Bool) {
    self.metadata = metadata
    self.initialValue = initialValue
  }
}

/// Configuration for a boolean stream-direction control.
public struct VideoDirectionControlConfiguration: Sendable, Hashable {
  /// Metadata shared by the control.
  public let metadata: VideoControlMetadata
  /// The value selected when the device is created.
  public let initialValue: Bool
  /// Creates a direction control.
  public init(metadata: VideoControlMetadata, initialValue: Bool) {
    self.metadata = metadata
    self.initialValue = initialValue
  }
}

/// Configuration for a decibel and scalar level control.
public struct VideoLevelControlConfiguration: Sendable, Hashable {
  /// Metadata shared by the control.
  public let metadata: VideoControlMetadata
  /// The decibel value selected when the device is created.
  public let initialDecibels: Float
  /// The minimum permitted decibel value.
  public let minimumDecibels: Float
  /// The maximum permitted decibel value.
  public let maximumDecibels: Float
  /// Creates a value from the supplied VideoDriverKit fields.
  public init(
    metadata: VideoControlMetadata,
    initialDecibels: Float,
    minimumDecibels: Float,
    maximumDecibels: Float
  ) {
    self.metadata = metadata
    self.initialDecibels = initialDecibels
    self.minimumDecibels = minimumDecibels
    self.maximumDecibels = maximumDecibels
  }
}

/// A named value offered by a selector control.
public struct VideoSelectorValue: Sendable, Hashable {
  /// The numeric selector value.
  public let value: UInt32
  /// The human-readable name published to the host.
  public let name: String
  /// Creates a value from the supplied VideoDriverKit fields.
  public init(value: UInt32, name: String) {
    self.value = value
    self.name = name
  }
}

/// Configuration for a selector control.
public struct VideoSelectorControlConfiguration: Sendable, Hashable {
  /// Metadata shared by the control.
  public let metadata: VideoControlMetadata
  /// The configured selector values or custom-property pairs.
  public let values: [VideoSelectorValue]
  /// The selector values selected when the device is created.
  public let initialValues: [UInt32]
  /// Creates a value from the supplied VideoDriverKit fields.
  public init(metadata: VideoControlMetadata, values: [VideoSelectorValue], initialValues: [UInt32])
  {
    self.metadata = metadata
    self.values = values
    self.initialValues = initialValues
  }
}

/// Configuration for an integer slider control.
public struct VideoSliderControlConfiguration: Sendable, Hashable {
  /// Metadata shared by the control.
  public let metadata: VideoControlMetadata
  /// The value selected when the device is created.
  public let initialValue: UInt32
  /// The minimum permitted slider value.
  public let minimumValue: UInt32
  /// The maximum permitted slider value.
  public let maximumValue: UInt32
  /// Creates a value from the supplied VideoDriverKit fields.
  public init(
    metadata: VideoControlMetadata,
    initialValue: UInt32,
    minimumValue: UInt32,
    maximumValue: UInt32
  ) {
    self.metadata = metadata
    self.initialValue = initialValue
    self.minimumValue = minimumValue
    self.maximumValue = maximumValue
  }
}

/// Configuration for a stereo pan control.
public struct VideoStereoPanControlConfiguration: Sendable, Hashable {
  /// Metadata shared by the control.
  public let metadata: VideoControlMetadata
  /// The value selected when the device is created.
  public let initialValue: Float
  /// The element representing the left channel.
  public let leftChannel: UInt32
  /// The element representing the right channel.
  public let rightChannel: UInt32
  /// Creates a value from the supplied VideoDriverKit fields.
  public init(
    metadata: VideoControlMetadata,
    initialValue: Float = 0,
    leftChannel: UInt32,
    rightChannel: UInt32
  ) {
    self.metadata = metadata
    self.initialValue = initialValue
    self.leftChannel = leftChannel
    self.rightChannel = rightChannel
  }
}

/// A statically configured VideoDriverKit control.
public enum VideoControlConfiguration: Sendable, Hashable {
  case boolean(VideoBooleanControlConfiguration)
  case direction(VideoDirectionControlConfiguration)
  case level(VideoLevelControlConfiguration)
  case selector(VideoSelectorControlConfiguration)
  case slider(VideoSliderControlConfiguration)
  case stereoPan(VideoStereoPanControlConfiguration)

  var metadata: VideoControlMetadata {
    switch self {
    case .boolean(let value): value.metadata
    case .direction(let value): value.metadata
    case .level(let value): value.metadata
    case .selector(let value): value.metadata
    case .slider(let value): value.metadata
    case .stereoPan(let value): value.metadata
    }
  }
}

/// A string-backed VideoDriverKit custom property.
public struct VideoCustomPropertyConfiguration: Sendable, Hashable {
  /// A stable identifier used by Swift runtime commands.
  public let identifier: UInt32
  /// The custom VideoDriverKit property selector.
  public let selector: UInt32
  /// The VideoDriverKit property scope.
  public let scope: VideoObjectScope
  /// The VideoDriverKit property element.
  public let element: UInt32
  /// Whether the host and Swift runtime may change the value.
  public let isSettable: Bool
  /// The configured selector values or custom-property pairs.
  public let values: [String: String]

  /// Creates a value from the supplied VideoDriverKit fields.
  public init(
    identifier: UInt32,
    selector: UInt32,
    scope: VideoObjectScope = .global,
    element: UInt32 = 0,
    isSettable: Bool = true,
    values: [String: String]
  ) {
    self.identifier = identifier
    self.selector = selector
    self.scope = scope
    self.element = element
    self.isSettable = isSettable
    self.values = values
  }
}

/// The representation requested when reading an VideoDriverKit control.
public enum VideoControlValueKind: UInt32, Sendable, Hashable {
  case boolean = 1
  case decibels = 2
  case scalar = 3
  case selector = 4
  case slider = 5
  case stereoPan = 6
  case direction = 7
}

/// A value read from or written to an VideoDriverKit control.
public enum VideoControlValue: Sendable, Hashable {
  case boolean(Bool)
  case direction(Bool)
  case decibels(Float)
  case scalar(Float)
  case selector([UInt32])
  case slider(UInt32)
  case stereoPan(Float)
}
