import Darwin
import Foundation

enum LibraryScanner {
    static func scan() -> LibrarySnapshot {
        let fm = FileManager.default
        var bottles: [Bottle] = []
        var games: [Game] = []
        var order = 0

        for root in bottleRoots() {
            guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in names.sorted() {
                let path = (root as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                if (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    continue
                }
                let bottle = loadBottle(name: name, path: path)
                bottles.append(bottle)
                let found = loadGames(bottle: bottle, order: &order)
                games.append(contentsOf: found)
            }
        }

        let crossover = locateCrossOver()
        let watch = bottles.flatMap { SteamScanner.libraryFolders(in: $0) }
        return LibrarySnapshot(
            bottles: bottles,
            games: games,
            crossoverPath: crossover?.path,
            crossoverVersion: crossover?.version,
            watchRoots: watch
        )
    }

    private static func bottleRoots() -> [String] {
        let home = NSHomeDirectory() + "/Library/Application Support/CrossOver/Bottles"
        let managed = "/Library/Application Support/CrossOver/Bottles"
        return [home, managed]
    }

    private static func loadBottle(name: String, path: String) -> Bottle {
        let config = (path as NSString).appendingPathComponent("cxbottle.conf")
        let env = BottleFile.readEnvironment(at: config)
        let version = BottleFile.readValue(at: config, section: "Bottle", key: "Version") ?? ""
        let template = BottleFile.readValue(at: config, section: "Bottle", key: "Template") ?? ""
        let bottleID = BottleFile.readValue(at: config, section: "Bottle", key: "BottleID") ?? name
        let msync = env["WINEMSYNC"] == "1"
        let esync = env["WINEESYNC"] == "1"
        let sync: SyncMode = msync ? .msync : (esync ? .esync : .off)
        let updated = (try? FileManager.default.attributesOfItem(atPath: config)[.modificationDate] as? Date) ?? .distantPast
        return Bottle(
            id: bottleID,
            name: name,
            path: path,
            configPath: config,
            version: version,
            template: template,
            backend: GraphicsBackend.parse(env["CX_GRAPHICS_BACKEND"]),
            metalFX: env["D3DM_ENABLE_METALFX"] != "0",
            nvExtensions: env["DXMT_ENABLE_NVEXT"] != "0",
            sync: sync,
            updated: updated
        )
    }

    private static func loadGames(bottle: Bottle, order: inout Int) -> [Game] {
        var games = loadMenuGames(bottle: bottle, order: &order)
        var seenExecutables = Set(games.compactMap { $0.executablePath?.lowercased() })
        var seenNames = Set(games.map { TitleMatcher.clean($0.name).lowercased() })
        guard let wine = wineBinary() else { return games }
        let steamGames = SteamScanner.games(in: bottle, wineBinary: wine, order: &order)
        var merged = Set<Int>()
        for index in games.indices {
            guard let steam = steamTwin(of: games[index], in: steamGames, bottle: bottle), let appID = steam.steamAppID else { continue }
            games[index] = launchedThroughSteam(games[index], like: steam)
            merged.insert(appID)
            if let exe = steam.executablePath?.lowercased() { seenExecutables.insert(exe) }
        }
        for game in steamGames {
            if let appID = game.steamAppID, merged.contains(appID) { continue }
            if let exe = game.executablePath?.lowercased(), !seenExecutables.insert(exe).inserted { continue }
            let cleaned = TitleMatcher.clean(game.name).lowercased()
            if seenNames.contains(cleaned) { continue }
            seenNames.insert(cleaned)
            games.append(game)
        }
        return games
    }

    /// The Steam library entry behind a menu or desktop shortcut: a `steam://rungameid/` link, or an exe
    /// inside a Steam library. Those shortcuts open Steam's full window, so they launch the hidden way instead.
    private static func steamTwin(of game: Game, in steamGames: [Game], bottle: Bottle) -> Game? {
        let candidates = steamGames.filter { GameLauncher.launchesThroughSteam($0) }
        if let appID = steamLinkAppID(game.windowsStart, bottle: bottle) {
            return candidates.first { $0.steamAppID == appID }
        }
        guard let exe = game.executablePath?.lowercased(), exe.contains("/steamapps/common/") else { return nil }
        return candidates.first { $0.executablePath?.lowercased() == exe }
            ?? candidates.first { steam in
                guard let dir = steam.installDirectory?.lowercased() else { return false }
                return exe.hasPrefix(dir + "/")
            }
    }

    /// Keeps the shortcut's tile (id, name, icon) and takes Steam's way of starting it.
    private static func launchedThroughSteam(_ game: Game, like steam: Game) -> Game {
        var game = game
        game.windowsStart = steam.windowsStart
        game.launchArguments = steam.launchArguments
        game.steamAppID = steam.steamAppID
        if game.executablePath == nil {
            game.executablePath = steam.executablePath
            game.installDirectory = steam.installDirectory
        }
        if game.discoveredArt == nil { game.discoveredArt = steam.discoveredArt }
        return game
    }

    private static func steamLinkAppID(_ windowsStart: String, bottle: Bottle) -> Int? {
        guard windowsStart.lowercased().hasSuffix(".url"),
              let native = resolveWindows(windowsStart, bottlePath: bottle.path),
              let text = try? String(contentsOfFile: native, encoding: .utf8)
                ?? String(contentsOfFile: native, encoding: .isoLatin1),
              let regex = try? NSRegularExpression(pattern: #"steam://rungameid/(\d+)"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let inner = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[inner])
    }

    private static func loadMenuGames(bottle: Bottle, order: inout Int) -> [Game] {
        let plistPath = bottle.path + "/desktopdata/cxmenu/cxmenu_macosx.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return []
        }
        var items: [(String, [String: Any])] = []
        collect(node: root, name: "", into: &items)
        var games: [Game] = []
        var seenExecutables = Set<String>()
        for (name, item) in items {
            guard let game = makeGame(menuName: name, item: item, bottle: bottle, order: order) else { continue }
            if let exe = game.executablePath?.lowercased(), !seenExecutables.insert(exe).inserted { continue }
            games.append(game)
            order += 1
        }
        return games
    }

    static func wineBinary() -> String? {
        for root in [NSHomeDirectory() + "/Applications/CrossOver.app", "/Applications/CrossOver.app"] {
            let wine = root + "/Contents/SharedSupport/CrossOver/bin/wine"
            if FileManager.default.isExecutableFile(atPath: wine) { return wine }
        }
        return nil
    }

    static func artwork(in directory: String?) -> String? {
        discoverArt(in: directory)
    }

    private static func collect(node: [String: Any], name: String, into items: inout [(String, [String: Any])]) {
        if node["Command"] != nil {
            items.append((name, node))
            return
        }
        let children = (node["Children"] as? [String: Any]) ?? node
        for key in children.keys.sorted() {
            guard let child = children[key] as? [String: Any] else { continue }
            let childName = key.hasSuffix("/") ? String(key.dropLast()) : key
            collect(node: child, name: childName, into: &items)
        }
    }

    private static func makeGame(menuName: String, item: [String: Any], bottle: Bottle, order: Int) -> Game? {
        let command = (item["Command"] as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' \n")) ?? ""
        guard !command.isEmpty, FileManager.default.fileExists(atPath: command) else { return nil }
        let script = (try? String(contentsOfFile: command, encoding: .utf8)) ?? ""
        guard let launch = parseLaunchScript(script) else { return nil }

        let icon = largestIcon(item["Icon"] as? String)
        let windowsLnk = resolveWindows(launch.start, bottlePath: bottle.path)
        let exe = windowsLnk.flatMap { windowsTargets(in: $0) }?.first
        let nativeExe = exe.flatMap { resolveWindows($0, bottlePath: bottle.path) }
        let lowered = (menuName + " " + (nativeExe ?? "")).lowercased()
        if ["uninstall", "unins000", "crashreport", "vc_redist", "dxsetup"].contains(where: { lowered.contains($0) }) {
            return nil
        }

        let directory = nativeExe.map { ($0 as NSString).deletingLastPathComponent }
        if let nativeExe, isDroppedLastOfUsShortcut(nativeExe) { return nil }

        let title = TitleMatcher.preferredTitle(menu: menuName, executable: nativeExe)
        let id = bottle.id + "::" + (item["RawPath"] as? String ?? menuName)
        return Game(
            id: id,
            name: title,
            menuName: menuName,
            bottleID: bottle.id,
            bottleName: bottle.name,
            iconPath: icon,
            wineBinary: launch.wine,
            windowsStart: launch.start,
            executablePath: nativeExe,
            installDirectory: directory,
            discoveredArt: discoverArt(in: directory),
            order: order,
            steamAppID: SteamIdentity.appID(in: directory)
        )
    }

    /// CrossOver's Start Menu has both Launcher.lnk and tlou-i.lnk. Keep the game exe.
    private static func isDroppedLastOfUsShortcut(_ nativeExe: String) -> Bool {
        let file = URL(fileURLWithPath: nativeExe).lastPathComponent.lowercased()
        let folder = URL(fileURLWithPath: nativeExe).deletingLastPathComponent()
        let tlou = folder.appendingPathComponent("tlou-i.exe").path
        guard FileManager.default.fileExists(atPath: tlou) else { return false }
        return file == "launcher.exe" || file == "tlou-i-l.exe"
    }

    private static func windowsPath(_ native: String, bottlePath: String) -> String? {
        let dos = bottlePath + "/dosdevices"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dos) else { return nil }
        let target = URL(fileURLWithPath: native).standardizedFileURL.path
        for name in names {
            guard name.count == 2, name.hasSuffix(":") else { continue }
            let mount = URL(fileURLWithPath: (dos as NSString).appendingPathComponent(name))
                .resolvingSymlinksInPath()
                .standardizedFileURL.path
            guard target.lowercased().hasPrefix(mount.lowercased()) else { continue }
            let rest = String(target.dropFirst(mount.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return name.uppercased() + "\\" + rest.replacingOccurrences(of: "/", with: "\\")
        }
        return nil
    }

    private static func parseLaunchScript(_ script: String) -> (wine: String, start: String)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"exec\s+"([^"]+)"[\s\S]*?--start\s+"([^"]+)""#
        ) else { return nil }
        let range = NSRange(script.startIndex..., in: script)
        guard let match = regex.firstMatch(in: script, range: range),
              let wineRange = Range(match.range(at: 1), in: script),
              let startRange = Range(match.range(at: 2), in: script) else { return nil }
        return (String(script[wineRange]), String(script[startRange]))
    }

    private static func largestIcon(_ path: String?) -> String? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        let file = url.lastPathComponent
        let hicolor = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard hicolor.lastPathComponent == "hicolor",
              let sizes = try? FileManager.default.contentsOfDirectory(at: hicolor, includingPropertiesForKeys: nil) else {
            return path
        }
        var best = path
        var bestDim = 0
        for sizeDir in sizes {
            let candidate = sizeDir.appendingPathComponent("apps").appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            let dim = Int(sizeDir.lastPathComponent.split(separator: "x").first ?? "") ?? 0
            if dim >= bestDim {
                bestDim = dim
                best = candidate.path
            }
        }
        return best
    }

    private static func resolveWindows(_ windowsPath: String, bottlePath: String) -> String? {
        let normalized = windowsPath.replacingOccurrences(of: "/", with: "\\")
        guard normalized.count > 2, normalized.dropFirst().first == ":" else { return nil }
        let letter = normalized.prefix(1).lowercased()
        let link = bottlePath + "/dosdevices/\(letter):"
        let root = URL(fileURLWithPath: link).resolvingSymlinksInPath()
        let relative = normalized.dropFirst(2).replacingOccurrences(of: "\\", with: "/")
        let trimmed = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        return root.appendingPathComponent(trimmed).path
    }

    private static func windowsTargets(in filePath: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: filePath) else { return nil }
        var found: [String] = []
        if let latin = String(data: data, encoding: .isoLatin1) {
            found.append(contentsOf: extractTargets(from: latin))
        }
        if let wide = String(data: data, encoding: .utf16LittleEndian) {
            found.append(contentsOf: extractTargets(from: wide))
        }
        let preferred = found.filter { !$0.lowercased().contains("start menu") && $0.lowercased().hasSuffix(".exe") }
        let pool = preferred.isEmpty ? found : preferred
        return pool.isEmpty ? nil : pool.sorted { $0.count > $1.count }
    }

    private static func extractTargets(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[A-Za-z]:\\(?:[^\\\r\n\u0000]{1,90}\\)*[^\\\r\n\u0000]{1,90}\.(?:exe|bat|cmd)"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func discoverArt(in directory: String?) -> String? {
        guard let directory else { return nil }
        let folder = URL(fileURLWithPath: directory)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return nil }
        let hints = ["cover", "hero", "background", "poster", "artwork", "splash", "keyart"]
        let images = items.filter { ["png", "jpg", "jpeg", "webp"].contains($0.pathExtension.lowercased()) }
        for url in images {
            let name = url.lastPathComponent.lowercased()
            guard hints.contains(where: { name.contains($0) }) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 40_000 { return url.path }
        }
        return nil
    }

    private static func locateCrossOver() -> (path: String, version: String)? {
        let candidates = [
            NSHomeDirectory() + "/Applications/CrossOver.app",
            "/Applications/CrossOver.app"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let plist = path + "/Contents/Info.plist"
            let version = (NSDictionary(contentsOfFile: plist)?["CFBundleShortVersionString"] as? String) ?? ""
            return (path, version)
        }
        return nil
    }
}
