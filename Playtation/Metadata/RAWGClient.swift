import Foundation

/// RAWG's game database. Used first when the user supplies a key (`RAWG_API_KEY` or `rawg.key`).
enum RAWGClient {
    static func apiKey() -> String? {
        let env = (ProcessInfo.processInfo.environment["RAWG_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty { return env }
        let file = LibraryStore.directory.appendingPathComponent("rawg.key")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static func search(_ query: String, key: String) async -> StoreHit? {
        guard var parts = URLComponents(string: "https://api.rawg.io/api/games") else { return nil }
        parts.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "page_size", value: "12")
        ]
        guard let url = parts.url, let results = await HTTPClient.json(url) else { return nil }
        let listings = (results["results"] as? [[String: Any]] ?? []).compactMap { row -> (id: Int, name: String)? in
            guard let name = row["name"] as? String, let id = row["id"] as? Int else { return nil }
            return (id, name)
        }
        guard let best = TitleMatcher.best(query, among: listings) else { return nil }
        async let detail = endpoint("\(best.id)", key: key)
        async let shots = endpoint("\(best.id)/screenshots", key: key, extra: "&page_size=8")
        async let movies = endpoint("\(best.id)/movies", key: key, extra: "&page_size=4")
        let payload = await detail
        let urls = (((await shots)?["results"] as? [[String: Any]]) ?? []).compactMap { row -> URL? in
            (row["image"] as? String).flatMap(URL.init(string:))
        }
        guard !urls.isEmpty || payload != nil else { return nil }
        let clip = trailer(in: await movies)
        return StoreHit(
            source: "rawg",
            remoteID: best.id,
            urls: Array(urls.prefix(6)),
            meta: payload.map { meta($0, id: best.id, trailer: clip) }
        )
    }

    static func meta(id: Int, key: String) async -> GameMeta? {
        guard let data = await endpoint("\(id)", key: key) else { return nil }
        let movies = await endpoint("\(id)/movies", key: key, extra: "&page_size=1")
        return meta(data, id: id, trailer: trailer(in: movies))
    }

    /// RAWG's cover image, which suits a portrait tile less than Steam's capsule but is better than nothing.
    static func coverURL(id: Int, key: String) async -> URL? {
        let data = await endpoint("\(id)", key: key)
        return (data?["background_image"] as? String).flatMap(URL.init(string:))
    }

    private static func endpoint(_ path: String, key: String, extra: String = "") async -> [String: Any]? {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        guard let url = URL(string: "https://api.rawg.io/api/games/\(path)?key=\(encoded)\(extra)") else { return nil }
        return await HTTPClient.json(url)
    }

    private static func trailer(in payload: [String: Any]?) -> String? {
        ((payload?["results"] as? [[String: Any]]) ?? []).compactMap { row in
            (row["data"] as? [String: Any])?["max"] as? String
        }.first
    }

    private static func meta(_ data: [String: Any], id: Int, trailer: String?) -> GameMeta {
        let names = { (key: String) -> [String] in
            ((data[key] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        }
        return GameMeta(
            title: data["name"] as? String ?? "",
            released: data["released"] as? String ?? "",
            summary: MetadataText.clip(MetadataText.plain(data["description_raw"] as? String ?? "")),
            genres: names("genres"),
            developers: names("developers"),
            publishers: names("publishers"),
            metacritic: (data["metacritic"] as? Int) ?? (data["metacritic"] as? NSNumber)?.intValue,
            rating: MetadataText.double(data["rating"]),
            esrb: (data["esrb_rating"] as? [String: Any])?["name"] as? String,
            website: MetadataText.nonempty(data["website"] as? String),
            trailer: trailer,
            source: "rawg",
            remoteID: id,
            fetchedAt: Date()
        )
    }
}
