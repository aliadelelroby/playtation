import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

/// Library scanning, per-game records and bottle changes.
extension ConsoleModel {
    func refresh(silent: Bool = false) {
        if !silent { loading = true }
        Task.detached {
            let snapshot = LibraryScanner.scan()
            await MainActor.run { self.apply(snapshot) }
        }
    }

    func updateBottle(_ bottle: Bottle, backend: GraphicsBackend? = nil, sync: SyncMode? = nil, metalFX: Bool? = nil, nvExtensions: Bool? = nil) {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        var next = bottles[index]
        if let backend { next.backend = backend }
        if let sync { next.sync = sync }
        if let metalFX { next.metalFX = metalFX }
        if let nvExtensions { next.nvExtensions = nvExtensions }
        bottles[index] = next
        do {
            try BottleFile.updateEnvironment(at: next.configPath, changes: [
                "CX_GRAPHICS_BACKEND": next.backend.rawValue,
                "D3DM_ENABLE_METALFX": next.metalFX ? "1" : "0",
                "DXMT_ENABLE_NVEXT": next.nvExtensions ? "1" : "0",
                "WINEMSYNC": next.sync == .msync ? "1" : "0",
                "WINEESYNC": next.sync == .esync ? "1" : "0"
            ])
            banner = "Saved to the \(next.name) bottle"
        } catch {
            banner = "Couldn't write \(next.name). \(error.localizedDescription)"
        }
    }

    func updateRecord(_ id: String, _ mutate: (inout GameRecord) -> Void) {
        var record = records[id] ?? GameRecord()
        mutate(&record)
        records[id] = record
        covers = covers.filter { !$0.key.hasPrefix(id + "|") }
        icons[id] = nil
        tiles[id] = nil
        wallpapers[id] = nil
        coverToken += 1
        LibraryStore.save(records)
        if !(games.indices.contains(selected)) { selected = 0 }
    }

    func importArtwork(for game: Game, from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let image = NSImage(contentsOf: url) else {
            banner = "That file isn't an image Playtation can use."
            return
        }
        let safe = game.id.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        let dest = LibraryStore.artworkDirectory().appendingPathComponent(safe).appendingPathExtension("jpg")
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
        do {
            try data.write(to: dest, options: .atomic)
            updateRecord(game.id) { $0.artworkPath = dest.path }
        } catch {
            banner = "Couldn't save that artwork."
        }
    }

    func open(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    func openCrossOver() {
        guard let crossoverPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: crossoverPath))
    }

    func rest() {
        withAnimation(.easeInOut(duration: 0.25)) { showPower = false }
        ConsoleSound.shared.stopMusic()
        NSApp.hide(nil)
    }

    func quit() {
        ConsoleSound.shared.stopMusic()
        if session == nil { DisplayFit.restore() }
        NSApp.terminate(nil)
    }

    func apply(_ snapshot: LibrarySnapshot) {
        let currentID = launchingID ?? session?.gameID ?? currentGame?.id
        bottles = snapshot.bottles
        watcher.update(extra: snapshot.watchRoots)
        allGames = snapshot.games
            + CustomLauncherStore.games(launchers, bottles: snapshot.bottles, wineBinary: LibraryScanner.wineBinary(), firstOrder: 5_000)
            + MediaApps.games()
            + [CustomLauncherStore.addTile()]
        crossoverPath = snapshot.crossoverPath
        crossoverVersion = snapshot.crossoverVersion
        loading = false
        if settingsBottleID.isEmpty || !snapshot.bottles.contains(where: { $0.id == settingsBottleID }) {
            settingsBottleID = currentGame?.bottleID ?? snapshot.bottles.first?.id ?? ""
        }
        let visible = games
        if let currentID, let index = visible.firstIndex(where: { $0.id == currentID }) {
            selected = index
        } else {
            selected = 0
        }
        reloadMetas()
        let jobs = allGames.filter { $0.webURL == nil && !$0.isAction }.map { GameCatalog.Job(id: $0.id, title: $0.name, steamAppID: $0.steamAppID) }
        Task {
            let outcome = await GameCatalog.sync(jobs)
            self.reloadMetas()
            if outcome.icons { self.icons.removeAll(); self.tiles.removeAll() }
            if outcome.shots { self.backdrops.removeAll() }
            if outcome.icons || outcome.shots { self.artworkRevision += 1 }
        }
    }

    func reloadMetas() {
        var next: [String: GameMeta] = [:]
        var recordsDirty = false
        for game in allGames {
            if let meta = GameCatalog.meta(for: game.id) { next[game.id] = meta }
            let local = TitleMatcher.clean(game.name)
            if let custom = records[game.id]?.displayName, !custom.isEmpty, !TitleMatcher.compatible(custom, with: local) {
                records[game.id]?.displayName = nil
                recordsDirty = true
            }
        }
        metas = next
        if recordsDirty { LibraryStore.save(records) }
    }

    /// One tile per game. Part I's Steam launcher is a stub. Other games keep Launcher.exe, because starting the game exe alone is rejected. Copies in other bottles stay behind the copy you play, then the busier bottle, then the newest bottle.
    func deduped(_ games: [Game]) -> [Game] {
        var byName: [String: Game] = [:]
        for game in games {
            let key = game.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if let current = byName[key] {
                if prefer(game, over: current) { byName[key] = game }
            } else {
                byName[key] = game
            }
        }
        var byTitle: [String: Game] = [:]
        for game in byName.values {
            let key = TitleMatcher.clean(game.name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if let current = byTitle[key] {
                byTitle[key] = preferPlayable(game, over: current)
            } else {
                byTitle[key] = game
            }
        }
        return Array(byTitle.values)
    }

    func isStubLauncher(_ game: Game) -> Bool {
        guard GameLauncher.isLastOfUs(game) else { return false }
        let exe = URL(fileURLWithPath: game.executablePath ?? "").lastPathComponent.lowercased()
        if exe == "launcher.exe" || exe == "tlou-i-l.exe" { return true }
        let name = (game.name + " " + game.menuName).lowercased()
        return name.contains("launcher")
    }

    func preferPlayable(_ game: Game, over other: Game) -> Game {
        if isStubLauncher(game) != isStubLauncher(other) { return isStubLauncher(game) ? other : game }
        return prefer(game, over: other) ? game : other
    }

    func prefer(_ game: Game, over other: Game) -> Bool {
        func score(_ game: Game) -> (Int, Int, TimeInterval, Int, TimeInterval) {
            let record = records[game.id]
            let plays = record?.playCount ?? 0
            let when = record?.lastPlayed?.timeIntervalSince1970 ?? 0
            let bottlePlays = allGames
                .filter { $0.bottleID == game.bottleID }
                .reduce(0) { $0 + (records[$1.id]?.playCount ?? 0) }
            let bottleWhen = bottles.first { $0.id == game.bottleID }?.updated.timeIntervalSince1970 ?? 0
            return (game.filesAvailable ? 1 : 0, plays, when, bottlePlays, bottleWhen)
        }
        return score(game) > score(other)
    }

    func launchEnvironment(for game: Game, record: GameRecord) -> String? {
        var parts: [String] = []
        if let graphics = record.graphics, !graphics.isEmpty {
            parts.append("CX_GRAPHICS_BACKEND=\(graphics)")
        }
        switch record.sync {
        case "msync":
            parts.append("WINEMSYNC=1")
            parts.append("WINEESYNC=0")
        case "esync":
            parts.append("WINEMSYNC=0")
            parts.append("WINEESYNC=1")
        case "off":
            parts.append("WINEMSYNC=0")
            parts.append("WINEESYNC=0")
        default:
            break
        }
        if let metalFX = record.metalFX {
            parts.append("D3DM_ENABLE_METALFX=\(metalFX ? "1" : "0")")
        }
        if let extra = game.customEnvironment, !extra.isEmpty { parts.append(extra) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
