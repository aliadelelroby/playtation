import Foundation
import SwiftUI

/// Someone who plays on this Mac. The main user is the Mac account and manages everyone else.
struct Profile: Codable, Identifiable, Equatable, Sendable {
    static let ownerID = "owner"
    static let limit = 8

    var id: String
    /// Empty for the main user until renamed, which shows the Mac account's name.
    var name: String
    var color: Int = 0
    /// Salted hash from `PatternLock.seal`.
    var pattern: String?
    /// Set once the profile screen has asked whether to set a pattern, so it only asks the first time.
    var patternOffered = false
    /// Per-user Last played and play count, keyed by game id. Home sorts by this.
    var played: [String: PlayStat] = [:]

    var isOwner: Bool { id == Self.ownerID }

    init(id: String, name: String, color: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
    }

    /// Missing keys fall back to defaults, so a newer field never makes the file unreadable
    /// (an unreadable file would be replaced by a fresh main user).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try c.decodeIfPresent(Int.self, forKey: .color) ?? 0
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern)
        patternOffered = try c.decodeIfPresent(Bool.self, forKey: .patternOffered) ?? false
        played = try c.decodeIfPresent([String: PlayStat].self, forKey: .played) ?? [:]
    }

    static let palette: [Color] = [
        PS.profile,
        Color(red: 0.33, green: 0.56, blue: 1.0),
        Color(red: 1.0, green: 0.45, blue: 0.62),
        Color(red: 0.30, green: 0.85, blue: 0.58),
        Color(red: 1.0, green: 0.60, blue: 0.25),
        Color(red: 0.68, green: 0.48, blue: 1.0)
    ]

    var tint: Color { Self.palette[((color % Self.palette.count) + Self.palette.count) % Self.palette.count] }
}

struct PlayStat: Codable, Equatable, Sendable {
    var lastPlayed: Date?
    var playCount = 0
}

enum ProfileStore {
    private static var file: URL { LibraryStore.directory.appendingPathComponent("profiles.json") }

    /// Loads everyone. The first run after updating moves the old single-user pattern and history onto the main user.
    static func load(records: [String: GameRecord]) -> [Profile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file),
           let profiles = try? decoder.decode([Profile].self, from: data),
           profiles.contains(where: \.isOwner) {
            return profiles
        }
        var owner = Profile(id: Profile.ownerID, name: "")
        owner.pattern = PatternLock.takeLegacy()
        owner.patternOffered = owner.pattern != nil
        for (id, record) in records where record.lastPlayed != nil || record.playCount > 0 {
            owner.played[id] = PlayStat(lastPlayed: record.lastPlayed, playCount: record.playCount)
        }
        save([owner])
        return [owner]
    }

    /// `defaults write com.playtation.Playtation forgotPattern -bool YES` clears the main user's pattern on the
    /// next launch. Other users' patterns are cleared by the main user from Settings > Users.
    static func clearForgottenPattern(_ profiles: inout [Profile]) {
        guard UserDefaults.standard.bool(forKey: "forgotPattern") else { return }
        UserDefaults.standard.removeObject(forKey: "forgotPattern")
        guard let index = profiles.firstIndex(where: \.isOwner) else { return }
        profiles[index].pattern = nil
        profiles[index].patternOffered = false
        save(profiles)
    }

    static func save(_ profiles: [Profile]) {
        try? FileManager.default.createDirectory(at: LibraryStore.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
