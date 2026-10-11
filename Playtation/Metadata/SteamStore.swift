import Foundation

/// Steam's public store API. It needs no key and covers most PC games.
enum SteamStore {
    private static let detailsEndpoint = "https://store.steampowered.com/api/appdetails"

    /// Exact lookup when the install is a Steam app and the app ID is known.
    static func hit(appID: Int) async -> StoreHit? {
        guard let data = await appData(appID, english: true) else { return nil }
        return StoreHit(source: "steam", remoteID: appID, urls: artwork(id: appID, data: data), meta: meta(data, id: appID))
    }

    /// Search by title and take the best-matching listing.
    static func search(_ query: String) async -> StoreHit? {
        guard var parts = URLComponents(string: "https://store.steampowered.com/api/storesearch/") else { return nil }
        parts.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "l", value: "english"),
            URLQueryItem(name: "cc", value: "us")
        ]
        guard let url = parts.url, let payload = await HTTPClient.json(url) else { return nil }
        let rows = (payload["items"] as? [[String: Any]] ?? []).filter { ($0["type"] as? String ?? "app") == "app" }
        let listings = rows.compactMap { row -> (id: Int, name: String)? in
            guard let name = row["name"] as? String, let id = row["id"] as? Int else { return nil }
            return (id, name)
        }
        guard let best = TitleMatcher.best(query, among: listings),
              let data = await appData(best.id, english: false)
        else { return nil }
        let urls = artwork(id: best.id, data: data)
        guard !urls.isEmpty else { return nil }
        return StoreHit(source: "steam", remoteID: best.id, urls: urls, meta: meta(data, id: best.id))
    }

    static func meta(appID: Int) async -> GameMeta? {
        guard let data = await appData(appID, english: false) else { return nil }
        return meta(data, id: appID)
    }

    // MARK: - Parsing

    private static func appData(_ id: Int, english: Bool) async -> [String: Any]? {
        let suffix = english ? "&l=english" : ""
        guard let url = URL(string: "\(detailsEndpoint)?appids=\(id)\(suffix)"),
              let details = await HTTPClient.json(url),
              let node = details["\(id)"] as? [String: Any],
              (node["success"] as? Bool) == true
        else { return nil }
        return node["data"] as? [String: Any]
    }

    private static func artwork(id: Int, data: [String: Any]) -> [URL] {
        let shots = ((data["screenshots"] as? [[String: Any]]) ?? []).compactMap { row -> URL? in
            guard let text = row["path_full"] as? String else { return nil }
            return URL(string: fullSize(text))
        }
        let extras = ["https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/library_hero_2x.jpg"].compactMap(URL.init(string:))
        var seen = Set<String>()
        return (shots + extras).filter { seen.insert($0.absoluteString).inserted }
    }

    /// Prefer the original screenshot file over Steam's 600×338 thumbs.
    private static func fullSize(_ text: String) -> String {
        text.replacingOccurrences(of: #"\.\d{3,4}x\d{3,4}"#, with: "", options: .regularExpression)
    }

    private static func meta(_ data: [String: Any], id: Int) -> GameMeta {
        let genres = ((data["genres"] as? [[String: Any]]) ?? []).compactMap { $0["description"] as? String }
        let released = (data["release_date"] as? [String: Any])?["date"] as? String ?? ""
        let metacritic = (data["metacritic"] as? [String: Any])?["score"] as? Int
        let age = (data["required_age"] as? Int) ?? (data["required_age"] as? String).flatMap(Int.init) ?? 0
        return GameMeta(
            title: data["name"] as? String ?? "",
            released: released,
            summary: MetadataText.clip(MetadataText.plain(data["short_description"] as? String ?? "")),
            genres: genres,
            developers: data["developers"] as? [String] ?? [],
            publishers: data["publishers"] as? [String] ?? [],
            metacritic: metacritic,
            rating: nil,
            esrb: ageLabel(age),
            website: MetadataText.nonempty(data["website"] as? String),
            trailer: nil,
            source: "steam",
            remoteID: id,
            fetchedAt: Date()
        )
    }

    private static func ageLabel(_ age: Int) -> String? {
        switch age {
        case 18...: return "Adults Only"
        case 17: return "Mature 17+"
        case 13...16: return "Teen"
        case 10...12: return "Everyone 10+"
        case 1...9: return "Everyone"
        default: return nil
        }
    }

    /// Portrait capsule art, used for the tile.
    static func portraitURLs(appID: Int) -> [URL] {
        [
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg",
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg"
        ].compactMap(URL.init(string:))
    }
}
