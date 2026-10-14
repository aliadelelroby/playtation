import Foundation

/// The running game: its Wine process and the bottle it lives in.
final class GameSession {
    let gameID: String
    let name: String
    let bottlePath: String
    let wineBinary: String
    let process: Process
    var userClosed = false
    /// steam.exe to shut down when the game exits, set when Playtation started Steam for it.
    var steamToStop: (bottle: String, exe: String)?

    init(gameID: String, name: String, bottlePath: String, wineBinary: String, process: Process) {
        self.gameID = gameID
        self.name = name
        self.bottlePath = bottlePath
        self.wineBinary = wineBinary
        self.process = process
    }
}

/// Tracks whether the shell or the game currently owns the controller.
final class PadGate: @unchecked Sendable {
    var suspended = false
    var resignedDuringGame = false
    var playing = false
    var windowShown = false
}
