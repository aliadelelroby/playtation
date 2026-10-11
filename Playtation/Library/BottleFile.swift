import Darwin
import Foundation

enum BottleFile {
    private static let entry = try! NSRegularExpression(
        pattern: #"^\s*(;;)?\s*"([A-Za-z0-9_]+)"\s*=\s*"(.*)"\s*$"#
    )

    static func readEnvironment(at path: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        return entries(in: "EnvironmentVariables", lines: split(text))
    }

    static func readValue(at path: String, section: String, key: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return entries(in: section, lines: split(text))[key]
    }

    static func updateEnvironment(at path: String, changes: [String: String]) throws {
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        let newline = raw.hasSuffix("\n")
        var lines = split(raw)
        guard let range = sectionRange("EnvironmentVariables", in: lines) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var seen = Set<String>()
        for index in range {
            guard let parsed = parse(lines[index]), let value = changes[parsed.key] else { continue }
            lines[index] = "\"\(parsed.key)\" = \"\(value)\""
            seen.insert(parsed.key)
        }

        let missing = changes.keys.filter { !seen.contains($0) }.sorted()
        if !missing.isEmpty {
            let inserted = missing.map { "\"\($0)\" = \"\(changes[$0]!)\"" }
            lines.insert(contentsOf: inserted, at: range.lowerBound)
        }

        var output = lines.joined(separator: "\n")
        if newline { output += "\n" }
        guard output.contains("[Bottle]"), output.contains("[EnvironmentVariables]"), output.count > 800 else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = URL(fileURLWithPath: path)
        let backup = url.appendingPathExtension("playtation-bak")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func split(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n"), lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func sectionRange(_ name: String, in lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(name)]" }) else {
            return nil
        }
        var end = start + 1
        while end < lines.count {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { break }
            end += 1
        }
        return (start + 1)..<end
    }

    private static func entries(in section: String, lines: [String]) -> [String: String] {
        guard let range = sectionRange(section, in: lines) else { return [:] }
        var values: [String: String] = [:]
        for index in range {
            guard let parsed = parse(lines[index]), !parsed.commented else { continue }
            values[parsed.key] = parsed.value
        }
        return values
    }

    private static func parse(_ line: String) -> (commented: Bool, key: String, value: String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = entry.firstMatch(in: line, range: range),
              let keyRange = Range(match.range(at: 2), in: line),
              let valueRange = Range(match.range(at: 3), in: line) else { return nil }
        let commented = match.range(at: 1).location != NSNotFound
        return (commented, String(line[keyRange]), String(line[valueRange]))
    }
}
