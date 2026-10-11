import Foundation

/// Steam app IDs left in an install folder (steam_appid.txt, AppID= in a config).
enum SteamIdentity {
    static func appID(in directory: String?) -> Int? {
        guard let directory else { return nil }
        let root = URL(fileURLWithPath: directory)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else { return nil }
        if let id = readAppIDFile(root.appendingPathComponent("steam_appid.txt")) { return id }
        if let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension.lowercased() == "ini" {
                if let id = readIniAppID(url) { return id }
            }
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var seen = 0
        var fromIni: Int?
        while let url = enumerator.nextObject() as? URL {
            let depth = url.path.replacingOccurrences(of: directory, with: "").split(separator: "/").count
            if depth > 4 {
                enumerator.skipDescendants()
                continue
            }
            seen += 1
            if seen > 180 { break }
            let name = url.lastPathComponent.lowercased()
            if name == "steam_appid.txt", let id = readAppIDFile(url) { return id }
            if fromIni == nil, name.hasSuffix(".ini"), let id = readIniAppID(url) { fromIni = id }
        }
        return fromIni
    }

    private static func readAppIDFile(_ url: URL) -> Int? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = Int(value.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""), (10...9_999_999).contains(id) else {
            return nil
        }
        return id
    }

    private static func readIniAppID(_ url: URL) -> Int? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 8, size < 64_000, let data = try? Data(contentsOf: url) else { return nil }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .utf16LittleEndian)
            ?? ""
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\bapp[_ ]?id\s*[=:]\s*(\d{3,7})"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let inner = Range(match.range(at: 1), in: text),
              let id = Int(text[inner]),
              (10...9_999_999).contains(id)
        else { return nil }
        return id
    }
}
