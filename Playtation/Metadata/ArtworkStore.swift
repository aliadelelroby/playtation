import AppKit
import Foundation
import ImageIO

/// On-disk cache of downloaded artwork (screenshots and portrait icons) and what was found for each game.
/// Everything lives under Application Support, so later launches work offline.
enum ArtworkStore {
    struct Entry: Codable {
        var query: String
        var source: String
        var remoteID: Int
        var files: [String]
        var fetchedAt: Date
        var quality: Int?
    }

    /// Bump when backdrop download or size rules change so old caches refetch.
    static let shotQuality = 2

    // MARK: Locations

    private static var root: URL { directory("Screenshots") }
    private static var iconDirectory: URL { directory("Icons") }
    private static var manifestURL: URL { root.appendingPathComponent("index.json") }
    private static var metaURL: URL { root.appendingPathComponent("metadata.json") }

    private static func directory(_ name: String) -> URL {
        let url = LibraryStore.directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func safe(_ id: String) -> String {
        id.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
    }

    // MARK: Reading

    static func iconPath(for gameID: String) -> String? {
        let path = iconDirectory.appendingPathComponent(safe(gameID) + ".jpg").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    static func screenshotPaths(for entry: Entry) -> [String] {
        entry.files.compactMap { relative in
            let path = root.appendingPathComponent(relative).path
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    static func isFresh(_ entry: Entry) -> Bool {
        if entry.files.isEmpty || entry.remoteID == 0 {
            return Date().timeIntervalSince(entry.fetchedAt) < 6 * 3_600
        }
        return entry.files.allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
    }

    static func loadManifest() -> [String: Entry] { read(manifestURL) ?? [:] }
    static func saveManifest(_ manifest: [String: Entry]) { write(manifest, to: manifestURL) }
    static func loadMetas() -> [String: GameMeta] { read(metaURL) ?? [:] }
    static func saveMetas(_ metas: [String: GameMeta]) { write(metas, to: metaURL) }

    // MARK: Writing

    static func removeArtwork(gameID: String) {
        try? FileManager.default.removeItem(at: iconDirectory.appendingPathComponent(safe(gameID) + ".jpg"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent(safe(gameID), isDirectory: true))
    }

    /// Downloads the portrait tile art if the game has none yet. Returns true when a new file was written.
    static func ensureIcon(gameID: String, source: String, remoteID: Int) async -> Bool {
        guard remoteID > 0 else { return false }
        let dest = iconDirectory.appendingPathComponent(safe(gameID) + ".jpg")
        if FileManager.default.fileExists(atPath: dest.path) { return false }
        var urls: [URL] = []
        if source == "rawg", let key = RAWGClient.apiKey(), let cover = await RAWGClient.coverURL(id: remoteID, key: key) {
            urls.append(cover)
        }
        urls += SteamStore.portraitURLs(appID: remoteID)
        for url in urls {
            guard let data = await HTTPClient.bytes(url), let jpeg = downsample(data, maxPixel: 1800, minPixel: 400) else { continue }
            if (try? jpeg.write(to: dest, options: .atomic)) != nil { return true }
        }
        return false
    }

    /// Downloads screenshots and returns their paths relative to the cache root.
    static func storeScreenshots(_ urls: [URL], gameID: String) async -> [String] {
        let folderName = safe(gameID)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var relative: [String] = []
        for (index, url) in urls.prefix(8).enumerated() {
            guard let data = await HTTPClient.bytes(url), let jpeg = downsample(data, maxPixel: 3840, minPixel: 900) else { continue }
            let name = "\(index).jpg"
            if (try? jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil {
                relative.append("\(folderName)/\(name)")
            }
        }
        return relative
    }

    // MARK: Helpers

    private static func downsample(_ data: Data, maxPixel: Int, minPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let longest = max(width, height)
        guard longest >= minPixel else { return nil }
        if longest <= maxPixel, data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 {
            return data
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    private static func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
