import Foundation

enum GraphicsBackend: String, CaseIterable, Identifiable, Codable {
    case d3dmetal
    case dxmt
    case dxvk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .d3dmetal: return "D3DMetal"
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        }
    }

    var blurb: String {
        switch self {
        case .d3dmetal: return "Apple's Direct3D to Metal path. The usual choice on this Mac."
        case .dxmt: return "DirectX to Metal. Try it when a game misbehaves on D3DMetal."
        case .dxvk: return "Vulkan translation. Heavier, and sometimes more compatible."
        }
    }

    static func parse(_ raw: String?) -> GraphicsBackend {
        switch raw?.lowercased() {
        case "dxmt": return .dxmt
        case "dxvk": return .dxvk
        default: return .d3dmetal
        }
    }
}

enum SyncMode: String, CaseIterable, Identifiable, Codable {
    case msync
    case esync
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .msync: return "MSync"
        case .esync: return "ESync"
        case .off: return "Off"
        }
    }

    var blurb: String {
        switch self {
        case .msync: return "CrossOver's fast synchronisation. Leave this on unless a game stutters."
        case .esync: return "Event-based sync. Worth a try if MSync crashes a game."
        case .off: return "No fast sync. Safest, and the slowest."
        }
    }
}

struct Bottle: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var path: String
    var configPath: String
    var version: String
    var template: String
    var backend: GraphicsBackend
    var metalFX: Bool
    var nvExtensions: Bool
    var sync: SyncMode
    var updated: Date

    var templateTitle: String {
        switch template {
        case "win10_64": return "Windows 10 64-bit"
        case "win11_64": return "Windows 11 64-bit"
        case "win10": return "Windows 10"
        case "win7_64": return "Windows 7 64-bit"
        default: return template.isEmpty ? "Windows bottle" : template.replacingOccurrences(of: "_", with: " ")
        }
    }
}

struct Game: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var menuName: String
    var bottleID: String
    var bottleName: String
    var iconPath: String?
    var wineBinary: String
    var windowsStart: String
    var executablePath: String?
    var installDirectory: String?
    var discoveredArt: String?
    var order: Int
    var launchArguments: [String] = []
    var steamAppID: Int? = nil
    /// Set for streaming/music services, which open a window instead of running through Wine.
    var webURL: String? = nil
    /// Extra `NAME=value` pairs from a saved launcher, passed to Wine as `--env`.
    var customEnvironment: String? = nil

    var isCustom: Bool { id.hasPrefix(CustomLauncherStore.idPrefix) }
    var isAction: Bool { id == CustomLauncherStore.actionID }
    /// Whether the "…" menu (info, game settings, remove) makes sense for this tile.
    var hasOptions: Bool { webURL == nil && !isAction }

    /// Store clients and launchers belong with the apps, not the games.
    var isLauncher: Bool {
        guard webURL == nil else { return false }
        let titles = [name, menuName].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let exact = ["steam", "epic games", "battle.net", "ea app", "ea", "origin", "ubisoft connect", "uplay", "gog galaxy", "itch", "xbox", "discord", "rockstar games launcher"]
        let partial = ["launcher", "battle.net", "epic games store", "gog galaxy", "ubisoft connect", "ea desktop", "bootstrapper"]
        return titles.contains { title in
            exact.contains(title) || partial.contains { title.contains($0) }
        }
    }

    /// Anything that isn't a game: launchers and the video and music services.
    var isApp: Bool { webURL != nil || isLauncher }

    var filesAvailable: Bool {
        guard let executablePath else { return true }
        return FileManager.default.fileExists(atPath: executablePath)
    }
}

struct GameRecord: Codable, Equatable, Sendable {
    var lastPlayed: Date?
    var playCount: Int = 0
    var displayName: String?
    var artworkPath: String?
    var graphics: String?
    var sync: String?
    var metalFX: Bool?
    /// `dinput` leaves the pad as a joystick. `xinput` maps it to an XInput gamepad.
    var controller: String?
    var hidden: Bool = false
}

struct LibrarySnapshot: Sendable {
    var bottles: [Bottle]
    var games: [Game]
    var crossoverPath: String?
    var crossoverVersion: String?
    /// Extra folders for the watcher: Steam libraries that live outside the bottles.
    var watchRoots: [String] = []
}

enum ConsoleTab: String, CaseIterable, Identifiable {
    case home, library, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }
}
