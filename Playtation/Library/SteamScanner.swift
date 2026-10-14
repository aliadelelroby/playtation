import Foundation

/// Games installed by the Windows Steam client inside a CrossOver bottle.
enum SteamScanner {
    private static let skipNames = [
        "steamworks", "redistributable", "proton", "steam linux", "steamvr",
        "dedicated server", "soundtrack", "sdk", "server content", "playtest"
    ]
    private static let skipAppIDs: Set<Int> = [
        228980, 250820, 1391110, 1628350, 1070560, 1493710
    ]
    private static let junkExe = [
        "uninstall", "unins000", "crashreport", "crashhandler", "vcredist",
        "dxsetup", "unitycrash", "easyanticheat", "eac", "redist"
    ]

    static func games(in bottle: Bottle, wineBinary: String, order: inout Int) -> [Game] {
        guard let steam = install(in: bottle) else { return [] }
        var found: [Game] = []
        var seen = Set<Int>()
        for library in steam.libraries {
            let apps = (library as NSString).appendingPathComponent("steamapps")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: apps) else { continue }
            for name in names where name.hasPrefix("appmanifest_") && name.hasSuffix(".acf") {
                let path = (apps as NSString).appendingPathComponent(name)
                guard let game = makeGame(
                    manifest: path,
                    steam: steam,
                    bottle: bottle,
                    wineBinary: wineBinary,
                    order: order
                ), seen.insert(game.steamAppID ?? 0).inserted else { continue }
                found.append(game)
                order += 1
            }
        }
        return found
    }

    /// Every `steamapps` folder in the bottle, including libraries on other drives.
    static func libraryFolders(in bottle: Bottle) -> [String] {
        guard let steam = install(in: bottle) else { return [] }
        return steam.libraries.map { ($0 as NSString).appendingPathComponent("steamapps") }
    }

    private struct Install {
        var windowsExe: String
        var nativeRoot: String
        var libraries: [String]
    }

    private static func install(in bottle: Bottle) -> Install? {
        var nativeRoot: String?
        var windowsExe: String?
        var libraries: [String] = []
        var seen = Set<String>()

        func addLibrary(_ native: String) {
            let standardized = URL(fileURLWithPath: native).standardizedFileURL.path
            let apps = (standardized as NSString).appendingPathComponent("steamapps")
            guard FileManager.default.fileExists(atPath: apps), seen.insert(standardized.lowercased()).inserted else { return }
            libraries.append(standardized)
        }

        func considerSteamFolder(_ native: String, windows: String) {
            let exe = (native as NSString).appendingPathComponent("steam.exe")
            if FileManager.default.fileExists(atPath: exe), nativeRoot == nil {
                nativeRoot = native
                windowsExe = windows
            }
            addLibrary(native)
            if let extra = libraryFolders(in: native) {
                for path in extra {
                    if let resolved = resolveWindows(path, bottlePath: bottle.path) {
                        addLibrary(resolved)
                    }
                }
            }
        }

        let known: [(String, String)] = [
            (bottle.path + "/drive_c/Program Files (x86)/Steam", "C:\\Program Files (x86)\\Steam\\steam.exe"),
            (bottle.path + "/drive_c/Program Files/Steam", "C:\\Program Files\\Steam\\steam.exe"),
            (bottle.path + "/drive_c/Steam", "C:\\Steam\\steam.exe")
        ]
        for (native, windows) in known {
            considerSteamFolder(native, windows: windows)
        }

        let dos = bottle.path + "/dosdevices"
        if let names = try? FileManager.default.contentsOfDirectory(atPath: dos) {
            for name in names {
                guard name.count == 2, name.hasSuffix(":"), !name.contains("::") else { continue }
                let link = (dos as NSString).appendingPathComponent(name)
                let mount = URL(fileURLWithPath: link).resolvingSymlinksInPath().path
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: mount, isDirectory: &isDir), isDir.boolValue else { continue }
                let letter = name.uppercased()
                for folder in ["Program Files (x86)/Steam", "Program Files/Steam", "Steam", "SteamLibrary", "Games/Steam"] {
                    let native = (mount as NSString).appendingPathComponent(folder)
                    let windows = "\(letter)\\\(folder.replacingOccurrences(of: "/", with: "\\"))\\steam.exe"
                    considerSteamFolder(native, windows: windows)
                }
            }
        }

        guard !libraries.isEmpty else { return nil }
        return Install(
            windowsExe: windowsExe ?? "C:\\Program Files (x86)\\Steam\\steam.exe",
            nativeRoot: nativeRoot ?? libraries[0],
            libraries: libraries
        )
    }

    private static func libraryFolders(in steamRoot: String) -> [String]? {
        let file = steamRoot + "/steamapps/libraryfolders.vdf"
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #""path"\s+"([^"]+)""#, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let inner = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[inner]).replacingOccurrences(of: "\\\\", with: "\\")
        }
    }

    private static func makeGame(
        manifest: String,
        steam: Install,
        bottle: Bottle,
        wineBinary: String,
        order: Int
    ) -> Game? {
        guard let text = try? String(contentsOfFile: manifest, encoding: .utf8) else { return nil }
        guard let appID = Int(acf(text, "appid") ?? ""), appID > 0, !skipAppIDs.contains(appID) else { return nil }
        let flags = Int(acf(text, "StateFlags") ?? "0") ?? 0
        guard flags & 4 != 0 else { return nil }
        let name = acf(text, "name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let lowered = name.lowercased()
        if skipNames.contains(where: { lowered.contains($0) }) { return nil }

        let installName = acf(text, "installdir") ?? ""
        let apps = (manifest as NSString).deletingLastPathComponent
        let directory: String? = installName.isEmpty ? nil : ((apps as NSString).appendingPathComponent("common") as NSString).appendingPathComponent(installName)
        if let directory, !FileManager.default.fileExists(atPath: directory) { return nil }

        let exe = directory.flatMap { primaryExecutable(in: $0, title: name) }
        let title = TitleMatcher.preferredTitle(menu: name, executable: exe)
        let art = capsule(appID: appID, steamRoot: steam.nativeRoot) ?? discoverArt(in: directory)
        let hasSteam = FileManager.default.fileExists(atPath: steam.nativeRoot + "/steam.exe")
        return Game(
            id: bottle.id + "::steam::\(appID)",
            name: title,
            menuName: name,
            bottleID: bottle.id,
            bottleName: bottle.name,
            iconPath: art,
            wineBinary: wineBinary,
            windowsStart: hasSteam ? steam.windowsExe : (exe.flatMap { windowsPath($0, bottle: bottle) } ?? steam.windowsExe),
            executablePath: exe,
            installDirectory: directory,
            discoveredArt: art,
            order: order,
            launchArguments: hasSteam ? GameLauncher.hiddenSteamArguments + ["-applaunch", "\(appID)"] : [],
            steamAppID: appID
        )
    }

    private static func acf(_ text: String, _ key: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\"\(key)\"\\s+\"([^\"]*)\"", options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let inner = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[inner])
    }

    private static func primaryExecutable(in directory: String, title: String) -> String? {
        let root = URL(fileURLWithPath: directory)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let tokens = TitleMatcher.tokens(title)
        var best: (path: String, score: Int)?
        var seen = 0
        while let url = enumerator.nextObject() as? URL {
            let depth = url.path.replacingOccurrences(of: directory, with: "").split(separator: "/").count
            if depth > 4 {
                enumerator.skipDescendants()
                continue
            }
            let folder = url.deletingLastPathComponent().lastPathComponent.lowercased()
            if ["_commonredist", "redist", "easyanticheat", "eac", "dotnet"].contains(folder) {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "exe" else { continue }
            seen += 1
            if seen > 80 { break }
            let file = url.deletingPathExtension().lastPathComponent.lowercased()
            if junkExe.contains(where: { file.contains($0) }) { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let overlap = TitleMatcher.tokens(file).intersection(tokens).count
            let score = overlap * 10_000_000 + min(size, 9_999_999)
            if best == nil || score > best!.score {
                best = (url.path, score)
            }
        }
        return best?.path
    }

    private static func capsule(appID: Int, steamRoot: String) -> String? {
        let cache = steamRoot + "/appcache/librarycache"
        let candidates = [
            "\(cache)/\(appID)/library_600x900.jpg",
            "\(cache)/\(appID)_library_600x900.jpg",
            "\(cache)/\(appID)/header.jpg",
            "\(cache)/\(appID)_header.jpg",
            "\(cache)/\(appID)/library_hero.jpg"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func windowsPath(_ native: String, bottle: Bottle) -> String? {
        let dos = bottle.path + "/dosdevices"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dos) else { return nil }
        let target = URL(fileURLWithPath: native).standardizedFileURL.path
        for name in names {
            guard name.count == 2, name.hasSuffix(":") else { continue }
            let mount = URL(fileURLWithPath: (dos as NSString).appendingPathComponent(name)).resolvingSymlinksInPath().standardizedFileURL.path
            guard target.lowercased().hasPrefix(mount.lowercased()) else { continue }
            let rest = String(target.dropFirst(mount.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return name.uppercased() + "\\" + rest.replacingOccurrences(of: "/", with: "\\")
        }
        return nil
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

    private static func discoverArt(in directory: String?) -> String? {
        LibraryScanner.artwork(in: directory)
    }
}
