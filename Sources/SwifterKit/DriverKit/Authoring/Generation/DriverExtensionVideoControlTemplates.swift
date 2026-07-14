import Foundation

extension DriverExtensionGenerator {
  static func videoControlConfigurationDeclarations(_ video: VideoDeviceConfiguration?) -> String {
    let declarations = """
      struct SwifterKitVideoControlConfiguration {
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
      struct SwifterKitVideoSelectorConfiguration {
          uint32_t value;
          const char* name;
      };
      struct SwifterKitVideoCustomPropertyConfiguration {
          uint32_t identifier;
          uint32_t selector;
          uint32_t scope;
          uint32_t element;
          bool isSettable;
          uint32_t valueStart;
          uint32_t valueCount;
      };
      struct SwifterKitVideoCustomPropertyValueConfiguration {
          const char* qualifier;
          const char* value;
      };
      """
    guard let video else {
      return declarations + """
        static constexpr SwifterKitVideoControlConfiguration kSwifterKitVideoControls[1] = {};
        static constexpr uint32_t kSwifterKitVideoControlCount = 0;
        static constexpr SwifterKitVideoSelectorConfiguration kSwifterKitVideoSelectors[1] = {};
        static constexpr uint32_t kSwifterKitVideoSelectorCount = 0;
        static constexpr uint32_t kSwifterKitVideoInitialSelections[1] = {};
        static constexpr SwifterKitVideoCustomPropertyConfiguration
            kSwifterKitVideoCustomProperties[1] = {};
        static constexpr uint32_t kSwifterKitVideoCustomPropertyCount = 0;
        static constexpr SwifterKitVideoCustomPropertyValueConfiguration
            kSwifterKitVideoCustomPropertyValues[1] = {};
        """
    }

    var selectorStart = 0
    var initialStart = 0
    let controls = video.controls.map { control -> String in
      let metadata = control.metadata
      let fields: [UInt32]
      switch control {
      case .boolean(let value): fields = [1, value.initialValue ? 1 : 0, 0, 1, 0, 0, 0, 0, 0, 0]
      case .level(let value):
        fields = [
          2, value.initialDecibels.bitPattern, value.minimumDecibels.bitPattern,
          value.maximumDecibels.bitPattern, 0, 0, 0, 0, 0, 0,
        ]
      case .selector(let value):
        fields = [
          3, 0, 0, 0, 0, 0, UInt32(selectorStart), UInt32(value.values.count), UInt32(initialStart),
          UInt32(value.initialValues.count),
        ]
        selectorStart += value.values.count
        initialStart += value.initialValues.count
      case .slider(let value):
        fields = [4, value.initialValue, value.minimumValue, value.maximumValue, 0, 0, 0, 0, 0, 0]
      case .stereoPan(let value):
        fields = [
          5, value.initialValue.bitPattern, 0, 0, value.leftChannel, value.rightChannel, 0, 0, 0, 0,
        ]
      case .direction(let value): fields = [6, value.initialValue ? 1 : 0, 0, 1, 0, 0, 0, 0, 0, 0]
      }
      return "    {\(fields[0]), \(metadata.identifier), \(cString(metadata.name)), "
        + "\(metadata.isSettable ? "true" : "false"), \(metadata.element), "
        + "\(metadata.scope.rawValue), \(metadata.controlClass.rawValue), \(fields[1]), "
        + "\(fields[2]), \(fields[3]), \(fields[4]), \(fields[5]), \(fields[6]), "
        + "\(fields[7]), \(fields[8]), \(fields[9])}"
    }.joined(separator: ",\n")
    let selectors = video.controls.compactMap { control -> [VideoSelectorValue]? in
      guard case .selector(let value) = control else { return nil }
      return value.values
    }.flatMap { $0 }.map { "    {\($0.value), \(cString($0.name))}" }.joined(separator: ",\n")
    let initialSelections = video.controls.compactMap { control -> [UInt32]? in
      guard case .selector(let value) = control else { return nil }
      return value.initialValues
    }.flatMap { $0 }.map(String.init).joined(separator: ", ")

    var propertyValueStart = 0
    let properties = video.customProperties.map { property in
      defer { propertyValueStart += property.values.count }
      return "    {\(property.identifier), \(property.selector), \(property.scope.rawValue), "
        + "\(property.element), \(property.isSettable ? "true" : "false"), "
        + "\(propertyValueStart), \(property.values.count)}"
    }.joined(separator: ",\n")
    let propertyValues = video.customProperties.flatMap { property in
      property.values.sorted { $0.key < $1.key }
    }.map { "    {\(cString($0.key)), \(cString($0.value))}" }.joined(separator: ",\n")

    return declarations + """
      static constexpr SwifterKitVideoControlConfiguration kSwifterKitVideoControls[] = {
      \(controls)
      };
      static constexpr uint32_t kSwifterKitVideoControlCount = \(video.controls.count);
      static constexpr SwifterKitVideoSelectorConfiguration kSwifterKitVideoSelectors[] = {
      \(selectors)
      };
      static constexpr uint32_t kSwifterKitVideoSelectorCount = \(selectorStart);
      static constexpr uint32_t kSwifterKitVideoInitialSelections[] = {\(initialSelections)};
      static constexpr SwifterKitVideoCustomPropertyConfiguration
          kSwifterKitVideoCustomProperties[] = {
      \(properties)
      };
      static constexpr uint32_t kSwifterKitVideoCustomPropertyCount =
          \(video.customProperties.count);
      static constexpr SwifterKitVideoCustomPropertyValueConfiguration
          kSwifterKitVideoCustomPropertyValues[] = {
      \(propertyValues)
      };
      """
  }
}
