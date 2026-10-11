import AppKit

/// A command the user saved from "Add Game", like CrossOver's "Save Command as a Launcher".
struct CustomLauncher: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var bottleID: String
    var command: String
    var environment: String
    var created: Date
}

enum CustomLauncherStore {
    private static var file: URL { LibraryStore.directory.appendingPathComponent("launchers.json") }

    static func load() -> [CustomLauncher] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CustomLauncher].self, from: data)) ?? []
    }

    static func save(_ launchers: [CustomLauncher]) {
        try? FileManager.default.createDirectory(at: LibraryStore.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(launchers) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static let idPrefix = "custom::"

    /// Turns saved launchers into tiles. Launchers whose bottle is gone are skipped.
    static func games(_ launchers: [CustomLauncher], bottles: [Bottle], wineBinary: String?, firstOrder: Int) -> [Game] {
        guard let wineBinary else { return [] }
        var order = firstOrder
        var games: [Game] = []
        for launcher in launchers {
            guard let bottle = bottles.first(where: { $0.id == launcher.bottleID }) else { continue }
            let directory = (launcher.command as NSString).deletingLastPathComponent
            games.append(Game(
                id: idPrefix + launcher.id,
                name: launcher.name,
                menuName: launcher.name,
                bottleID: bottle.id,
                bottleName: bottle.name,
                iconPath: nil,
                wineBinary: wineBinary,
                windowsStart: "",
                executablePath: launcher.command,
                installDirectory: directory.isEmpty ? nil : directory,
                discoveredArt: LibraryScanner.artwork(in: directory),
                order: order,
                customEnvironment: launcher.environment.isEmpty ? nil : launcher.environment
            ))
            order += 1
        }
        return games
    }

    /// The "Add Game" tile that sits at the end of the Games row.
    static let actionID = "action::add"

    static func addTile() -> Game {
        Game(
            id: actionID, name: "Add Game", menuName: "Add Game", bottleID: "", bottleName: "",
            iconPath: nil, wineBinary: "", windowsStart: "", order: 20_000
        )
    }
}

extension GameLauncher {
    /// Runs one command in a bottle, the way CrossOver's Run Command does. Used for installers.
    static func runCommand(wine: String, bottle: String, command: String, environment: String) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: wine) else { throw CocoaError(.fileNoSuchFile) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: wine)
        var unix = ProcessInfo.processInfo.environment
        unix["ROSETTA_ADVERTISE_AVX"] = "1"
        process.environment = unix
        process.currentDirectoryURL = URL(fileURLWithPath: (command as NSString).deletingLastPathComponent)
        var arguments = ["--bottle", bottle, "--wait-children", "--no-gui"]
        if !environment.isEmpty { arguments.append(contentsOf: ["--env", environment]) }
        arguments.append(command)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
