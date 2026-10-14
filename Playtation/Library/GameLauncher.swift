import Darwin
import Foundation

enum GameLauncher {
    /// Steam has to be running for most Steam games (Steamworks, DRM), so it starts in the
    /// background with no library, friends or chat windows.
    static let hiddenSteamArguments = ["-silent", "-nofriendsui", "-nochatui"]

    static func launchesThroughSteam(_ game: Game) -> Bool {
        game.steamAppID != nil && game.launchArguments.contains("-applaunch")
    }

    /// Asks the bottle's Steam to quit, the way its own Exit menu item does.
    static func shutDownSteam(bottleName: String, wineBinary: String, steamExe: String) {
        guard FileManager.default.isExecutableFile(atPath: wineBinary) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinary)
        process.arguments = ["--bottle", bottleName, "--no-gui", steamExe, "-shutdown"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Same argv CrossOver's Start Menu scripts use:
    /// `wine --bottle NAME --check --wait-children --start "C:/users/.../Start Menu/Game.lnk"`
    static func launch(_ game: Game, environment: String?) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: game.wineBinary) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: game.wineBinary)
        var unix = ProcessInfo.processInfo.environment
        unix["ROSETTA_ADVERTISE_AVX"] = "1"
        process.environment = unix
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        var arguments = ["--bottle", game.bottleName, "--check", "--wait-children", "--no-gui"]
        if let env = environment, !env.isEmpty {
            arguments.append(contentsOf: ["--env", env])
        }
        // Part I works from CrossOver's launcher shortcut, not from tlou-i.exe directly.
        if isLastOfUs(game), let start = lastOfUsLauncherStart(game) {
            arguments.append(contentsOf: ["--start", start])
            arguments.append(contentsOf: game.launchArguments)
        } else if let launcher = companionLauncher(for: game) {
            arguments.append(contentsOf: ["--workdir", (launcher as NSString).deletingLastPathComponent])
            arguments.append(launcher)
            arguments.append(contentsOf: game.launchArguments)
        } else if isWindowsTarget(game.windowsStart) {
            arguments.append(contentsOf: ["--start", game.windowsStart])
            arguments.append(contentsOf: game.launchArguments)
        } else if let exe = game.executablePath, FileManager.default.fileExists(atPath: exe) {
            arguments.append(exe)
            arguments.append(contentsOf: game.launchArguments)
        } else {
            arguments.append(contentsOf: ["--start", game.windowsStart])
            arguments.append(contentsOf: game.launchArguments)
        }
        process.arguments = arguments
        // Must not attach pipes: closing them when Playtation quits kills Wine.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Own process group so quitting Playtation does not SIGHUP the game.
        _ = setpgid(process.processIdentifier, process.processIdentifier)
        return process
    }

    /// CrossOver's working Part I entry: `wine --start .../launcher.lnk`.
    private static func lastOfUsLauncherStart(_ game: Game) -> String? {
        let folder = NSHomeDirectory()
            + "/Library/Application Support/CrossOver/Bottles/\(game.bottleName)/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu"
        let names = ["launcher.lnk", "Launcher.lnk"]
        guard let name = names.first(where: {
            FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent($0))
        }) else { return nil }
        let start = game.windowsStart.replacingOccurrences(of: "\\", with: "/")
        let dir = (start as NSString).deletingLastPathComponent
        if dir.count >= 3 {
            return (dir as NSString).appendingPathComponent(name)
        }
        return "C:/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/\(name)"
    }

    /// `Launcher.exe` beside the game. Not used for Part I, which goes through its shortcut.
    private static func companionLauncher(for game: Game) -> String? {
        if isLastOfUs(game) { return nil }
        guard let dir = game.installDirectory else { return nil }
        let launcher = (dir as NSString).appendingPathComponent("Launcher.exe")
        guard FileManager.default.fileExists(atPath: launcher) else { return nil }
        return launcher
    }

    private static func isWindowsTarget(_ start: String) -> Bool {
        let path = start.replacingOccurrences(of: "\\", with: "/")
        guard path.count >= 3 else { return false }
        let chars = Array(path)
        return chars[0].isLetter && chars[1] == ":" && chars[2] == "/"
    }

    static func isLastOfUs(_ game: Game) -> Bool {
        let blob = [game.name, game.menuName, game.executablePath, game.windowsStart]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        return blob.contains("tlou") || blob.contains("last of us")
    }
}
