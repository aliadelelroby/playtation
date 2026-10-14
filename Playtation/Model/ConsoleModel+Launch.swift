import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

/// Starting, watching and closing games.
extension ConsoleModel {
    /// R2 pulled through the DualSense wall. Starts the highlighted game.
    func startFromTrigger() {
        guard shellOwnsPad() else { return }
        if phase == .welcome {
            confirmWelcome()
            return
        }
        guard phase == .shell, patternPrompt == nil, tab == .home, !showSettings, !showPower else { return }
        startSelected()
    }

    func isRunning(_ game: Game) -> Bool {
        runningGameID == game.id
    }

    func canClose(_ game: Game) -> Bool {
        session?.gameID == game.id
    }

    func focus(gameID: String) {
        if let index = games.firstIndex(where: { $0.id == gameID }) {
            selected = index
        }
        withAnimation { tab = .home }
    }

    func startSelected() {
        guard let game = currentGame, launchingID == nil else { return }
        if game.isAction {
            openAdd()
            return
        }
        if session?.gameID == game.id {
            closeRunningGame()
            return
        }
        if session != nil {
            closeRunningGame()
            let nextID = game.id
            Task { @MainActor in
                for _ in 0..<25 {
                    if self.session == nil { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard self.session == nil, self.currentGame?.id == nextID, self.launchingID == nil else { return }
                guard let next = self.currentGame else { return }
                self.beginLaunch(next)
            }
            return
        }
        beginLaunch(game)
    }

    func closeRunningGame() {
        guard let session, !session.userClosed else { return }
        session.userClosed = true
        closingGameID = session.gameID
        ConsoleFeel.shared.halt()
        banner = "Closing \(session.name)"
        let wineserver = (session.wineBinary as NSString).deletingLastPathComponent.appending("/wineserver")
        if FileManager.default.isExecutableFile(atPath: wineserver) {
            let killer = Process()
            killer.executableURL = URL(fileURLWithPath: wineserver)
            killer.arguments = ["-k"]
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = session.bottlePath
            killer.environment = env
            try? killer.run()
        }
        if session.process.isRunning {
            session.process.terminate()
        }
        let process = session.process
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self.session?.process === process, process.isRunning else { return }
            process.terminate()
            self.clearSession(process)
        }
    }

    func beginLaunch(_ game: Game) {
        guard launchingID == nil else { return }
        if game.isAction {
            openAdd()
            return
        }
        if let service = MediaApps.service(for: game) {
            ConsoleFeel.shared.launch()
            ConsoleSound.shared.stopMusic()
            updateRecord(game.id) {
                $0.lastPlayed = Date()
                $0.playCount += 1
            }
            recordPlay(game.id)
            banner = "Opening \(service.name)"
            MediaApps.open(service)
            return
        }
        if !game.filesAvailable {
            ConsoleFeel.shared.error()
            banner = "\(displayName(for: game)) isn't on a mounted drive."
            return
        }
        showDetails = false
        showMore = false
        showProfile = false
        launchingID = game.id
        hoverLockUntil = Date().addingTimeInterval(2.2)
        pinSelected(to: game.id)
        ConsoleFeel.shared.clearTriggers()
        ConsoleFeel.shared.launch()
        ConsoleSound.shared.stopMusic()
        banner = "Starting \(displayName(for: game))"
        gameTookThePad()
        let env = launchEnvironment(for: game, record: records[game.id] ?? GameRecord())
        let started = Date()
        Task { @MainActor in
            do {
                await PlaytationWindow.yieldToGame()
                _ = DisplayFit.prepare()
                if let path = self.bottle(for: game)?.path {
                    WineControllers.apply(bottlePath: path, wineBinary: game.wineBinary, mode: self.records[game.id]?.controller)
                }
                let steamWasRunning = ProcessProbe.anyRunning(named: "steam.exe")
                let process = try GameLauncher.launch(game, environment: env)
                let running = GameSession(
                    gameID: game.id,
                    name: displayName(for: game),
                    bottlePath: bottle(for: game)?.path ?? "",
                    wineBinary: game.wineBinary,
                    process: process
                )
                if GameLauncher.launchesThroughSteam(game), !steamWasRunning {
                    running.steamToStop = (game.bottleName, game.windowsStart)
                }
                self.session = running
                process.terminationHandler = { proc in
                    Task { @MainActor in
                        self.gameExited(proc, started: started, name: running.name)
                    }
                }
                self.watchLaunch(game, process: process)
            } catch {
                DisplayFit.restore()
                self.shellTookThePad()
                self.launchingID = nil
                ConsoleFeel.shared.error()
                self.banner = "Couldn't start \(self.displayName(for: game))."
                PlaytationLaunch.reveal()
            }
        }
    }

    func watchLaunch(_ game: Game, process: Process) {
        Task { @MainActor in
            let winePID = process.processIdentifier
            let exe = game.executablePath
            let start = game.windowsStart
            // Steam starting hidden in the background can take most of a minute before the game appears.
            let deadline = Date().addingTimeInterval(game.steamAppID == nil ? 20 : 90)
            while Date() < deadline {
                if session?.process !== process { return }
                if !process.isRunning {
                    if launchingID == game.id { launchingID = nil }
                    return
                }
                if ProcessProbe.gameRunning(winePID: winePID, executablePath: exe, windowsStart: start) {
                    let shown = await GameFocus.present(winePID: winePID, executablePath: exe, windowsStart: start)
                    guard session?.process === process, process.isRunning else { return }
                    if shown {
                        markRunning(game)
                        PlaytationShell.leaveForGame()
                        watchAlive(game, process: process)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard session?.process === process else { return }
            launchingID = nil
            if process.isRunning {
                let shown = await GameFocus.present(winePID: winePID, executablePath: exe, windowsStart: start)
                guard session?.process === process, process.isRunning else { return }
                if shown {
                    markRunning(game)
                    PlaytationShell.leaveForGame()
                    watchAlive(game, process: process)
                } else {
                    banner = "\(displayName(for: game)) didn't show a window."
                    watchAlive(game, process: process)
                }
            }
        }
    }

    /// Clears Running if the .exe dies while winewrapper is still listed as our session.
    func watchAlive(_ game: Game, process: Process) {
        Task { @MainActor in
            while session?.process === process {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard session?.process === process else { return }
                if !process.isRunning { return }
                if !ProcessProbe.gameRunning(
                    winePID: process.processIdentifier,
                    executablePath: game.executablePath,
                    windowsStart: game.windowsStart
                ) {
                    gameExited(process, started: Date().addingTimeInterval(-2), name: displayName(for: game))
                    return
                }
            }
        }
    }

    func markRunning(_ game: Game) {
        guard session?.gameID == game.id else { return }
        padGate.windowShown = true
        runningGameID = game.id
        if launchingID == game.id { launchingID = nil }
        var record = records[game.id] ?? GameRecord()
        record.lastPlayed = Date()
        record.playCount += 1
        records[game.id] = record
        LibraryStore.save(records)
        recordPlay(game.id)
        pinSelected(to: game.id)
        if banner?.hasPrefix("Starting") == true { banner = nil }
    }

    func pinSelected(to id: String) {
        if let index = games.firstIndex(where: { $0.id == id }) {
            selected = index
        }
    }

    func gameExited(_ process: Process, started: Date, name: String) {
        guard session?.process === process else { return }
        let closed = session?.userClosed == true
        let gameID = session?.gameID
        // Closing from Playtation already stopped the whole bottle; a game that quit on its own leaves Steam behind.
        if !closed, let ended = session, let steam = ended.steamToStop {
            GameLauncher.shutDownSteam(bottleName: steam.bottle, wineBinary: ended.wineBinary, steamExe: steam.exe)
        }
        clearSession(process)
        if launchingID != nil, launchingID == gameID { launchingID = nil }
        DisplayFit.restore()
        if !closed {
            PlaytationLaunch.reveal()
            let lasted = Date().timeIntervalSince(started)
            // watchAlive lands here while winewrapper may still be alive; terminationStatus
            // raises an ObjC exception on a running Process.
            let failed = !process.isRunning && process.terminationStatus != 0
            if failed, lasted < 4 {
                banner = "CrossOver couldn't start \(name)."
            } else if lasted < 90 {
                banner = "\(name) closed unexpectedly."
            }
        }
    }

    func clearSession(_ process: Process) {
        guard session?.process === process else { return }
        if launchingID == session?.gameID { launchingID = nil }
        session = nil
        runningGameID = nil
        closingGameID = nil
        padGate.playing = false
        padGate.windowShown = false
        padGate.resignedDuringGame = false
        shellTookThePad()
    }
}
