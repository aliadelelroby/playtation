import Foundation

/// Finds details and artwork for each game and keeps them cached.
///
/// For every game, `sync` works out a search title (`TitleMatcher.clean`), reuses cached results when they
/// are still good, and otherwise asks RAWG (if a key is set) and then the Steam store. A store listing is
/// only accepted when `TitleMatcher` agrees it is the same game, so a sequel or a soundtrack never wins.
enum GameCatalog {
    struct Job: Sendable {
        var id: String
        var title: String
        var steamAppID: Int? = nil
    }

    struct SyncOutcome: Sendable {
        var shots = false
        var icons = false
    }

    // MARK: Reading

    static func icon(for gameID: String) -> String? {
        ArtworkStore.iconPath(for: gameID)
    }

    static func meta(for gameID: String) -> GameMeta? {
        guard let meta = ArtworkStore.loadMetas()[gameID], !meta.title.isEmpty else { return nil }
        return meta
    }

    static func files(for gameID: String) -> [String] {
        guard let entry = ArtworkStore.loadManifest()[gameID], ArtworkStore.isFresh(entry) else { return [] }
        return ArtworkStore.screenshotPaths(for: entry)
    }

    static func credit(for gameID: String) -> String? {
        guard let entry = ArtworkStore.loadManifest()[gameID], !entry.files.isEmpty else { return nil }
        switch entry.source {
        case "rawg": return "Artwork from RAWG"
        case "steam": return "Artwork from Steam"
        default: return nil
        }
    }

    // MARK: Syncing

    static func sync(_ jobs: [Job]) async -> SyncOutcome {
        var manifest = ArtworkStore.loadManifest()
        var metas = ArtworkStore.loadMetas()
        var outcome = SyncOutcome()
        var metaChanged = false

        for job in jobs {
            let query = TitleMatcher.clean(job.title)
            guard query.count >= 2 else { continue }

            // The shortcut was renamed: the old artwork belongs to a different search.
            if let entry = manifest[job.id], TitleMatcher.clean(entry.query) != query {
                ArtworkStore.removeArtwork(gameID: job.id)
                outcome.icons = true
            }
            if let meta = metas[job.id], !TitleMatcher.compatible(meta.title, with: query) {
                metas[job.id] = nil
                metaChanged = true
            }

            if let entry = manifest[job.id], isReusable(entry, query: query, job: job) {
                if await fillMeta(for: job, query: query, entry: entry, manifest: manifest, metas: &metas) { metaChanged = true }
                if await ArtworkStore.ensureIcon(gameID: job.id, source: entry.source, remoteID: entry.remoteID) {
                    outcome.icons = true
                }
                continue
            }

            // Two shortcuts for the same game share one download.
            if let shared = manifest.first(where: { $0.key != job.id && isReusable($0.value, query: query, job: job) }) {
                manifest[job.id] = shared.value
                if let donor = metas[shared.key], TitleMatcher.compatible(donor.title, with: query) {
                    metas[job.id] = donor
                    metaChanged = true
                }
                if await ArtworkStore.ensureIcon(gameID: job.id, source: shared.value.source, remoteID: shared.value.remoteID) {
                    outcome.icons = true
                }
                outcome.shots = true
                continue
            }

            let hit = await find(query: query, steamAppID: job.steamAppID)
            ArtworkStore.removeArtwork(gameID: job.id)
            let files = await ArtworkStore.storeScreenshots(hit?.urls ?? [], gameID: job.id)
            manifest[job.id] = ArtworkStore.Entry(
                query: query,
                source: hit?.source ?? "",
                remoteID: hit?.remoteID ?? 0,
                files: files,
                fetchedAt: Date(),
                quality: ArtworkStore.shotQuality
            )
            if let meta = hit?.meta, TitleMatcher.compatible(meta.title, with: query) {
                metas[job.id] = meta
            } else {
                metas[job.id] = nil
            }
            if await ArtworkStore.ensureIcon(gameID: job.id, source: hit?.source ?? "", remoteID: hit?.remoteID ?? 0) {
                outcome.icons = true
            }
            outcome.shots = true
            metaChanged = true
        }

        if outcome.shots { ArtworkStore.saveManifest(manifest) }
        if metaChanged { ArtworkStore.saveMetas(metas) }
        return outcome
    }

    // MARK: Lookup

    /// An exact Steam app ID wins. Otherwise search RAWG, then Steam, then Steam again with hyphens loosened.
    private static func find(query: String, steamAppID: Int?) async -> StoreHit? {
        if let steamAppID, steamAppID > 0 { return await SteamStore.hit(appID: steamAppID) }
        if let key = RAWGClient.apiKey(), let hit = await RAWGClient.search(query, key: key) { return hit }
        if let hit = await SteamStore.search(query) { return hit }
        let loosened = query.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return loosened == query ? nil : await SteamStore.search(loosened)
    }

    private static func details(source: String, remoteID: Int) async -> GameMeta? {
        guard remoteID > 0 else { return nil }
        if source == "rawg", let key = RAWGClient.apiKey() { return await RAWGClient.meta(id: remoteID, key: key) }
        if source == "steam" { return await SteamStore.meta(appID: remoteID) }
        return nil
    }

    // MARK: Cache rules

    /// A cached result is reusable when it matches this search, still has its files, and (for Steam apps)
    /// is for the same app ID.
    private static func isReusable(_ entry: ArtworkStore.Entry, query: String, job: Job) -> Bool {
        TitleMatcher.clean(entry.query) == query
            && ArtworkStore.isFresh(entry)
            && !entry.files.isEmpty
            && entry.remoteID > 0
            && (job.steamAppID == nil || entry.remoteID == job.steamAppID)
            && (entry.quality ?? 0) >= ArtworkStore.shotQuality
    }

    private static func isStale(_ meta: GameMeta?) -> Bool {
        guard let meta else { return true }
        return Date().timeIntervalSince(meta.fetchedAt) > 14 * 86_400
    }

    /// Makes sure a game with cached artwork also has details: borrow from a twin, or refetch when stale.
    /// Returns true when `metas` changed.
    private static func fillMeta(
        for job: Job,
        query: String,
        entry: ArtworkStore.Entry,
        manifest: [String: ArtworkStore.Entry],
        metas: inout [String: GameMeta]
    ) async -> Bool {
        if metas[job.id] == nil {
            let twin = metas.first { key, meta in
                manifest[key]?.query == query && !meta.summary.isEmpty && TitleMatcher.compatible(meta.title, with: query)
            }?.value ?? metas.values.first { meta in
                meta.source == entry.source && meta.remoteID == entry.remoteID
                    && TitleMatcher.compatible(meta.title, with: query)
            }
            if let twin {
                metas[job.id] = twin
                return true
            }
        }
        guard isStale(metas[job.id]),
              let meta = await details(source: entry.source, remoteID: entry.remoteID),
              TitleMatcher.compatible(meta.title, with: query)
        else { return false }
        metas[job.id] = meta
        return true
    }
}
