import Foundation

/// Descriptive details for a game, from RAWG or the Steam store.
struct GameMeta: Codable, Equatable, Sendable {
    var title: String
    var released: String
    var summary: String
    var genres: [String]
    var developers: [String]
    var publishers: [String]
    var metacritic: Int?
    var rating: Double?
    var esrb: String?
    var website: String?
    var trailer: String?
    var source: String
    var remoteID: Int
    var fetchedAt: Date
}

/// One store listing that matched a game: where it came from, its artwork and its details.
struct StoreHit: Sendable {
    var source: String
    var remoteID: Int
    var urls: [URL]
    var meta: GameMeta?
}
