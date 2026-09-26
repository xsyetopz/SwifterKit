import Foundation

/// One row of the control table that the audio and video runtimes share.
struct MediaControlTableRow {
  var kind: UInt32
  var identifier: UInt32
  var name: String
  var isSettable: Bool
  var element: UInt32
  var scope: UInt32
  var classID: UInt32
  var value: UInt32 = 0
  var minimum: UInt32 = 0
  var maximum: UInt32 = 0
  var auxiliary0: UInt32 = 0
  var auxiliary1: UInt32 = 0
  /// The selector items and initial selections of a selector control.
  var selector: (values: [(value: UInt32, name: String)], initialValues: [UInt32])?
}

/// One row of the custom-property table that the audio and video runtimes share.
struct MediaCustomPropertyTableRow {
  var identifier: UInt32
  var selector: UInt32
  var scope: UInt32
  var element: UInt32
  var isSettable: Bool
  var values: [String: String]
}

extension DriverExtensionGenerator {
  /// Declares the control, selector, and custom-property structs for `family`.
  static func mediaControlStructDeclarations(family: String) -> String {
    """
    struct SwifterKit\(family)ControlConfiguration {
        uint32_t kind;
        uint32_t identifier;
        const char* name;
        bool isSettable;
        uint32_t element;
        uint32_t scope;
        uint32_t classID;
        uint32_t value;
        uint32_t minimum;
        uint32_t maximum;
        uint32_t auxiliary0;
        uint32_t auxiliary1;
        uint32_t selectorStart;
        uint32_t selectorCount;
        uint32_t initialStart;
        uint32_t initialCount;
    };
    struct SwifterKit\(family)SelectorConfiguration {
        uint32_t value;
        const char* name;
    };
    struct SwifterKit\(family)CustomPropertyConfiguration {
        uint32_t identifier;
        uint32_t selector;
        uint32_t scope;
        uint32_t element;
        bool isSettable;
        uint32_t valueStart;
        uint32_t valueCount;
    };
    struct SwifterKit\(family)CustomPropertyValueConfiguration {
        const char* qualifier;
        const char* value;
    };
    """
  }

  /// Declares the box struct for `family`.
  static func mediaBoxStructDeclaration(family: String) -> String {
    """
    struct SwifterKit\(family)BoxConfiguration {
        const char* uid;
        const char* name;
        uint32_t transport;
        bool isAcquirable;
        bool isAcquired;
        bool hasAudio;
        bool hasMIDI;
        bool hasVideo;
        bool isProtected;
        bool ownsDevice;
        uint32_t clockMask;
    };
    """
  }

  /// Renders empty control and custom-property tables for a family without a device.
  static func mediaEmptyControlTables(family: String) -> String {
    let type = "SwifterKit\(family)"
    let name = "kSwifterKit\(family)"
    return """
      static constexpr \(type)ControlConfiguration \(name)Controls[1] = {};
      static constexpr uint32_t \(name)ControlCount = 0;
      static constexpr \(type)SelectorConfiguration \(name)Selectors[1] = {};
      static constexpr uint32_t \(name)SelectorCount = 0;
      static constexpr uint32_t \(name)InitialSelections[1] = {};
      static constexpr \(type)CustomPropertyConfiguration
          \(name)CustomProperties[1] = {};
      static constexpr uint32_t \(name)CustomPropertyCount = 0;
      static constexpr \(type)CustomPropertyValueConfiguration
          \(name)CustomPropertyValues[1] = {};
      """
  }

  /// Renders the control, selector, and custom-property tables for `family`.
  static func mediaControlTables(
    family: String,
    controls: [MediaControlTableRow],
    customProperties: [MediaCustomPropertyTableRow]
  ) -> String {
    var selectorStart = 0
    var initialStart = 0
    let controlRows = controls.map { control -> String in
      var selectorFields: [Int] = [0, 0, 0, 0]
      if let selector = control.selector {
        selectorFields = [
          selectorStart, selector.values.count, initialStart, selector.initialValues.count,
        ]
        selectorStart += selector.values.count
        initialStart += selector.initialValues.count
      }
      return "    {\(control.kind), \(control.identifier), \(cString(control.name)), "
        + "\(control.isSettable ? "true" : "false"), \(control.element), "
        + "\(control.scope), \(control.classID), \(control.value), "
        + "\(control.minimum), \(control.maximum), \(control.auxiliary0), "
        + "\(control.auxiliary1), \(selectorFields[0]), "
        + "\(selectorFields[1]), \(selectorFields[2]), \(selectorFields[3])}"
    }.joined(separator: ",\n")
    let selectors = controls.flatMap { $0.selector?.values ?? [] }.map {
      "    {\($0.value), \(cString($0.name))}"
    }.joined(separator: ",\n")
    let initialSelections = controls.flatMap { $0.selector?.initialValues ?? [] }.map(String.init)
      .joined(separator: ", ")

    var propertyValueStart = 0
    let properties = customProperties.map { property in
      defer { propertyValueStart += property.values.count }
      return "    {\(property.identifier), \(property.selector), \(property.scope), "
        + "\(property.element), \(property.isSettable ? "true" : "false"), "
        + "\(propertyValueStart), \(property.values.count)}"
    }.joined(separator: ",\n")
    let propertyValues = customProperties.flatMap { property in
      property.values.sorted { $0.key < $1.key }
    }.map { "    {\(cString($0.key)), \(cString($0.value))}" }.joined(separator: ",\n")

    let type = "SwifterKit\(family)"
    let name = "kSwifterKit\(family)"
    return """
      static constexpr \(type)ControlConfiguration \(name)Controls[] = {
      \(controlRows)
      };
      static constexpr uint32_t \(name)ControlCount = \(controls.count);
      static constexpr \(type)SelectorConfiguration \(name)Selectors[] = {
      \(selectors)
      };
      static constexpr uint32_t \(name)SelectorCount = \(selectorStart);
      static constexpr uint32_t \(name)InitialSelections[] = {\(initialSelections)};
      static constexpr \(type)CustomPropertyConfiguration
          \(name)CustomProperties[] = {
      \(properties)
      };
      static constexpr uint32_t \(name)CustomPropertyCount =
          \(customProperties.count);
      static constexpr \(type)CustomPropertyValueConfiguration
          \(name)CustomPropertyValues[] = {
      \(propertyValues)
      };
      """
  }
}
