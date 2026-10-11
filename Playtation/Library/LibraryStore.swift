import Darwin
import Foundation

enum LibraryStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Playtation", isDirectory: true)
    }

    private static var file: URL { directory.appendingPathComponent("library.json") }

    static func load() -> [String: GameRecord] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: GameRecord].self, from: data)) ?? [:]
    }

    static func save(_ records: [String: GameRecord]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func artworkDirectory() -> URL {
        let url = directory.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
