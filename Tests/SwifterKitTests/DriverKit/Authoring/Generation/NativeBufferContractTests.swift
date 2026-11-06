import Foundation
import Testing

@Suite
struct NativeBufferContractTests {
  private static func nativeFiles() throws -> [(name: String, lines: [Substring])] {
    try FileManager.default.contentsOfDirectory(atPath: checkedInNativeSources.path).filter {
      $0.hasSuffix(".cpp") || $0.hasSuffix(".h")
    }.sorted().map { name in
      let text = try String(
        contentsOf: checkedInNativeSources.appendingPathComponent(name),
        encoding: .utf8
      )
      return (name, text.split(separator: "\n", omittingEmptySubsequences: false))
    }
  }

  @Test
  func everySetLengthResultIsChecked() throws {
    var unchecked: [String] = []
    for file in try Self.nativeFiles() {
      for index in file.lines.indices where file.lines[index].contains("SetLength(") {
        let line = file.lines[index]
        let stored = line.contains("result = ") && !line.contains("void")
        let tested = file.lines[(index + 1)..<min(index + 4, file.lines.endIndex)].contains {
          $0.contains("result == kIOReturnSuccess") || $0.contains("result != kIOReturnSuccess")
            || $0.contains("return result")
        }
        if !stored || !tested { unchecked.append("\(file.name):\(index + 1)") }
      }
    }
    #expect(unchecked.isEmpty, "\(unchecked)")
  }

  private static let mappingsCheckedAtUse = [
    (
      "SwifterKitRuntimeAudioDevice.cpp",
      "->CreateMapping(0, 0, 0, bufferSize, 0, &ivars->maps[index]);",
      "transfer->length > map->GetLength()"
    ),
    (
      "SwifterKitRuntimeAudioMembers.cpp", "descriptor->CreateMapping(0, 0, 0, size, 0, &map);",
      "SwifterKitRuntimeAudioDevice.cpp|transfer->length > map->GetLength()"
    ),
    (
      "SwifterKitRuntimeVideoDevice.cpp",
      "dataDescriptors[streamIndex][bufferIndex]->CreateMapping(",
      "IsValidRange(transfer->byteOffset, transfer->length, map->GetLength())"
    ),
    (
      "SwifterKitRuntimeVideoDevice.cpp",
      "controlDescriptors[streamIndex][bufferIndex]->CreateMapping(",
      "IsValidRange(transfer->byteOffset, transfer->length, map->GetLength())"
    ),
    (
      "SwifterKitRuntimeVideoMembers.cpp",
      "->CreateMapping(0, 0, 0, sizes[plane], 0, &maps[plane][buffer]);",
      "SwifterKitRuntimeVideoDevice.cpp|transfer->length, map->GetLength())"
    ),
    (
      "SwifterKitRuntimeSCSIControl.cpp",
      "length == 0 ? kIOReturnNotFound : (*buffer)->CreateMapping(0, 0, 0, length, 0, map);",
      "task.dataMap->GetLength()"
    ),
    (
      "SwifterKitRuntimeSerial.cpp", "return descriptor->CreateMapping(0, 0, 0, 0, 0, map);",
      "serialArenaMap->GetLength() < sizeof(driverkit::serial::SerialPortInterface)"
    ),
  ]

  private static func mappingVariable(_ line: Substring) -> String? {
    guard let call = line.range(of: "CreateMapping("),
      let end = line[call.upperBound...].firstIndex(of: ")")
    else { return nil }
    let last = line[call.upperBound..<end].split(separator: ",").last ?? ""
    let variable = last.trimmingCharacters(in: .whitespaces)
    return variable.hasPrefix("&") ? String(variable.dropFirst()) : variable
  }

  @Test
  func everyMappingLengthIsChecked() throws {
    let files = try Self.nativeFiles()
    var unchecked: [String] = []
    for file in files {
      for index in file.lines.indices where file.lines[index].contains("CreateMapping(") {
        let line = file.lines[index]
        if let exemption = Self.mappingsCheckedAtUse.first(where: {
          $0.0 == file.name && line.trimmingCharacters(in: .whitespaces).hasSuffix($0.1)
        }) {
          let parts = exemption.2.split(separator: "|")
          let checkFile = parts.count == 2 ? String(parts[0]) : file.name
          let check = String(parts.last ?? "")
          let checked = files.first { $0.name == checkFile }?.lines.contains { $0.contains(check) }
          #expect(checked == true, "\(file.name):\(index + 1) relies on \(checkFile): \(check)")
          continue
        }
        let window = file.lines[index..<min(index + 6, file.lines.endIndex)]
        let compared = Self.mappingVariable(line).map { variable in
          [
            "\(variable)->GetLength() <", "\(variable)->GetLength() >=",
            "(*\(variable))->GetLength() <",
          ].contains { check in window.contains { $0.contains(check) } }
        }
        if compared != true { unchecked.append("\(file.name):\(index + 1)") }
      }
    }
    #expect(unchecked.isEmpty, "\(unchecked)")
  }

  @Test
  func noBufferIsMappedWithMap() throws {
    let mapped = try Self.nativeFiles().flatMap { file in
      file.lines.indices.filter {
        file.lines[$0].contains("->Map(") || file.lines[$0].contains(".Map(")
      }.map { "\(file.name):\($0 + 1)" }
    }
    #expect(mapped.isEmpty, "\(mapped)")
  }

  @Test
  func everyAllocatedBufferIsWritable() throws {
    var outputOnly: [String] = []
    for file in try Self.nativeFiles() {
      let text = file.lines.joined(separator: "\n")
      for call in ["IOBufferMemoryDescriptor::Create(", "CreateIOBuffer("] {
        var searchStart = text.startIndex
        while let found = text.range(of: call, range: searchStart..<text.endIndex) {
          searchStart = found.upperBound
          let rest = text[found.upperBound...]
          let argument = rest[..<(rest.firstIndex(of: ",") ?? rest.endIndex)].trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          let literal =
            argument.contains("kIOMemoryDirection")
            && !argument.replacingOccurrences(of: "kIOMemoryDirectionOutIn", with: "").contains(
              "kIOMemoryDirectionOut"
            )
          if !literal && !argument.hasPrefix("SwifterKitWritableDirection(") {
            let line = text[..<found.lowerBound].filter { $0 == "\n" }.count + 1
            outputOnly.append("\(file.name):\(line)")
          }
        }
      }
    }
    #expect(outputOnly.isEmpty, "\(outputOnly)")
  }

  @Test
  func composedOutputMemoryIsReadOnly() throws {
    let memory = try #require(Self.nativeFiles().first { $0.name == "SwifterKitRuntimeMemory.cpp" })
    let text = memory.lines.joined(separator: "\n")
    #expect(text.contains("direction == kIOMemoryDirectionOut ? kIOMemoryMapReadOnly : 0"))
    #expect(
      text.contains(
        """
        if (write && entry->descriptor == nullptr
                        && entry->direction == kIOMemoryDirectionOut) {
                        return kIOReturnNotWritable;
        """
      )
    )
  }

  @Test
  func poolMemoryKeepsTheAuthorDirection() throws {
    let memory = try #require(Self.nativeFiles().first { $0.name == "SwifterKitRuntimeMemory.cpp" })
    let text = memory.lines.joined(separator: "\n")
    #expect(
      text.contains(
        "IOBufferMemoryDescriptor::Create(\n"
          + "                SwifterKitWritableDirection(header->direction),"
      )
    )
    #expect(text.contains("entry->direction = header->direction;"))
    #expect(text.contains("return (direction & ~source->direction) == 0;"))
    #expect(!text.contains("entry->direction = SwifterKitWritableDirection("))
  }
}
