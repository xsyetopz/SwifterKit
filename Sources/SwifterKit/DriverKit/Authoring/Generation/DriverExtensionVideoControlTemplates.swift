import Foundation

extension DriverExtensionGenerator {
  static func videoControlConfigurationDeclarations(_ video: VideoDeviceConfiguration?) -> String {
    let declarations = mediaControlStructDeclarations(family: "Video")
    guard let video else { return declarations + mediaEmptyControlTables(family: "Video") }
    return declarations
      + mediaControlTables(
        family: "Video",
        controls: video.controls.map(mediaControlRow),
        customProperties: video.customProperties.map {
          MediaCustomPropertyTableRow(
            identifier: $0.identifier,
            selector: $0.selector,
            scope: $0.scope.rawValue,
            element: $0.element,
            isSettable: $0.isSettable,
            values: $0.values
          )
        }
      )
  }

  static func mediaControlRow(_ control: VideoControlConfiguration) -> MediaControlTableRow {
    let metadata = control.metadata
    typealias Kind = RuntimeVideoControlKind
    var row = MediaControlTableRow(
      kind: 0,
      identifier: metadata.identifier,
      name: metadata.name,
      isSettable: metadata.isSettable,
      element: metadata.element,
      scope: metadata.scope.rawValue,
      classID: metadata.controlClass.rawValue
    )
    switch control {
    case .boolean(let value):
      (row.kind, row.value, row.maximum) = (Kind.boolean.rawValue, value.initialValue ? 1 : 0, 1)
    case .direction(let value):
      (row.kind, row.value, row.maximum) = (Kind.direction.rawValue, value.initialValue ? 1 : 0, 1)
    case .level(let value):
      row.kind = Kind.level.rawValue
      row.value = value.initialDecibels.bitPattern
      row.minimum = value.minimumDecibels.bitPattern
      row.maximum = value.maximumDecibels.bitPattern
    case .selector(let value):
      row.kind = Kind.selector.rawValue
      row.selector = (value.values.map { ($0.value, $0.name) }, value.initialValues)
    case .slider(let value):
      (row.kind, row.value) = (Kind.slider.rawValue, value.initialValue)
      (row.minimum, row.maximum) = (value.minimumValue, value.maximumValue)
    case .stereoPan(let value):
      (row.kind, row.value) = (Kind.stereoPan.rawValue, value.initialValue.bitPattern)
      (row.auxiliary0, row.auxiliary1) = (value.leftChannel, value.rightChannel)
    }
    return row
  }
}
