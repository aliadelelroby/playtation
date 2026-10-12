import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ConsoleModel: ObservableObject {
    @Published var phase: Phase = .boot
    @Published var tab: ConsoleTab = .home
    @Published var bottles: [Bottle] = []
    @Published var allGames: [Game] = [] { didSet { gamesCache = nil } }
    @Published var selected = 0
    @Published var records: [String: GameRecord] = [:] { didSet { gamesCache = nil } }
    @Published var loading = true
    @Published var banner: String?
    @Published var launchingID: String?
    /// Set only after the game's Mac process is actually running.
    @Published var runningGameID: String?
    @Published var closingGameID: String?
    @Published var showSettings = false
    @Published var showDetails = false
    @Published var showPower = false
    @Published var showMore = false
    /// The menu under the profile picture on Home.
    @Published var showProfile = false
    @Published var panelIndex = 0
    /// Game settings: the highlight is inside the page, not on the sidebar.
    @Published var gameInContent = false
    @Published var gameRow = 0
    @Published var settingsSection = 0
    @Published var settingsRow = 0
    @Published var settingsInContent = false
    @Published var settingsBottleID: String = ""
    @Published var crossoverPath: String?
    @Published var crossoverVersion: String?
    @Published var bootCue = 0
    /// True once Game Controller reports a pad. Boot stays up until this is set and the PS button is used.
    @Published var controllerConnected = false
    /// True once the boot prompt is on screen. Presses before that are ignored.
    @Published var bootReady = false
    @Published var zone: DashZone = .tiles
    @Published var topIndex = 0
    @Published var heroIndex = 0
    @Published var searching = false
    @Published var showAdd = false
    @Published var addRow = 0
    @Published var addBottleID = ""
    @Published var addCommand = ""
    @Published var addName = ""
    @Published var addEnvironment = ""
    @Published var addEditing = false
    @Published var confirmRemove = false
    var launchers: [CustomLauncher] = CustomLauncherStore.load()
    let watcher = LibraryWatcher()
    @Published var gameResolution = DisplayFit.setting
    @Published var query = "" { didSet { gamesCache = nil } }
    @Published var kbRow = 2
    @Published var kbCol = 5
    @Published var kbShift = false
    @Published var kbMode: SearchKeyboardMode = .letters
    @Published var fullScreen = PlaytationWindow.isFullScreen
    @Published var startFullScreen = PlaytationWindow.prefersFullScreen
    @Published var coverToken = 0
    @Published var artworkRevision = 0
    @Published var metas: [String: GameMeta] = [:]

    enum Phase { case boot, welcome, shell }

    @Published var signingIn = false
    /// Non-nil while a sign-in pattern is being asked for or set up.
    @Published var patternPrompt: PatternPrompt?
    @Published var pattern = PatternTrace()
    @Published var patternMessage: String?
    /// Set briefly after a wrong or rejected pattern so the grid can show it in red.
    @Published var patternFailed = false
    /// Bumped on every failure; the grid shakes when it changes.
    @Published var patternShake = 0
    enum PatternPrompt: Equatable {
        case unlock
        case create
        case confirm([Int])
    }
    /// Stays set once the profile screen has introduced itself, so a redraw cannot play that intro again.
    @Published var welcomeIntroduced = false
    enum DashZone { case top, tiles, hero }
    enum HomeCategory: String, CaseIterable, Identifiable {
        case all, games, apps
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .games: return "Games"
            case .apps: return "Apps"
            }
        }
    }
    @Published var category: HomeCategory = .all { didSet { gamesCache = nil } }

    var covers: [String: NSImage] = [:]
    var icons: [String: NSImage] = [:]
    var tiles: [String: NSImage] = [:]
    var wallpapers: [String: NSImage] = [:]
    var backdrops: [String: [NSImage]] = [:]
    var controllers: ControllerSupport?
    var bootGeneration = 0
    var session: GameSession?
    /// Touched from activation notifications without a main-actor hop. A hop there
    /// crashes MenuBarClientCore while the app is resigning.
    let padGate = PadGate()
    var psDown = false
    var psHoldFired = false
    var psHoldTask: Task<Void, Never>?
    var hoverLockUntil = Date.distantPast
    let relative = RelativeDateTimeFormatter()

    /// Sorting and de-duplicating is expensive and views read this many times per frame.
    var gamesCache: [Game]?

    var games: [Game] {
        if let gamesCache { return gamesCache }
        let result = computeGames()
        gamesCache = result
        return result
    }

    func computeGames() -> [Game] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return deduped(allGames)
            .filter { !(records[$0.id]?.hidden ?? false) }
            .filter { !Self.helperEntry($0) }
            .filter { !$0.isAction || (needle.isEmpty && category != .apps) }
            .filter {
                switch category {
                case .all: return true
                case .games: return !$0.isApp
                case .apps: return $0.isApp
                }
            }
            .filter { needle.isEmpty || displayName(for: $0).localizedCaseInsensitiveContains(needle) }
            .sorted { lhs, rhs in
                let lrank = lhs.isAction ? 3 : (lhs.webURL != nil ? 2 : (lhs.isLauncher ? 1 : 0))
                let rrank = rhs.isAction ? 3 : (rhs.webURL != nil ? 2 : (rhs.isLauncher ? 1 : 0))
                if lrank != rrank { return lrank < rrank }
                let left = records[lhs.id]?.lastPlayed ?? .distantPast
                let right = records[rhs.id]?.lastPlayed ?? .distantPast
                if left != right { return left > right }
                return lhs.order < rhs.order
            }
    }

    /// Launcher shortcuts that aren't games (Steam's support page, its uninstaller and the like).
    static func helperEntry(_ game: Game) -> Bool {
        let name = game.name.lowercased()
        return name.contains("support center") || name.contains("uninstall")
    }

    /// Columns in the app grid. Up and down move by a row while the selection is inside it.
    static let appColumns = 3

    var currentGame: Game? {
        let visible = games
        guard visible.indices.contains(selected) else { return visible.first }
        return visible[selected]
    }

    var accountName: String { ScreenshotTour.isOn ? "Player" : NSFullUserName() }

    var accountImage: NSImage? {
        if ScreenshotTour.isOn { return nil }
        return CBIdentity(name: NSUserName(), authority: CBIdentityAuthority.default())?.image
    }

    init() {
        records = LibraryStore.load()
        relative.unitsStyle = .full
        controllers = ControllerSupport(model: self)
        controllers?.start()
        let gate = padGate
        NotificationCenter.default.addObserver(
            forName: .playtationLaunchFailed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let message = note.userInfo?["message"] as? String
            self?.later {
                $0.launchingID = nil
                $0.shellTookThePad()
                $0.banner = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        watcher.onChange = { [weak self] in
            self?.later { model in
                guard !model.loading else { return }
                model.refresh(silent: true)
            }
        }
        watcher.start()
        NotificationCenter.default.addObserver(forName: .playtationRescan, object: nil, queue: .main) { [weak self] _ in
            self?.later { $0.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .playtationWindowMode, object: nil, queue: .main) { [weak self] _ in
            self?.later {
                $0.startFullScreen = PlaytationWindow.prefersFullScreen
                $0.fullScreen = PlaytationWindow.isFullScreen
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { [weak self] _ in
            self?.later { $0.fullScreen = true }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { [weak self] _ in
            self?.later { $0.fullScreen = false }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            guard gate.playing else { return }
            gate.resignedDuringGame = true
            gate.suspended = true
            ConsoleSound.holdForGameSoon()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard gate.resignedDuringGame, gate.windowShown else { return }
            self?.later {
                guard Self.shellWindowIsFront else { return }
                $0.shellTookThePad()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.later {
                guard Self.shellWindowIsFront else { return }
                $0.shellTookThePad()
            }
        }
    }

    /// Runs after the current menu-bar turn, on the dispatch main executor.
    nonisolated func later(_ body: @escaping @MainActor (ConsoleModel) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                body(self)
            }
        }
    }

    static var shellWindowIsFront: Bool {
        NSApp.isActive && NSApp.windows.contains { $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized }
    }

    func shellOwnsPad() -> Bool { !padGate.suspended }

    func gameTookThePad() {
        padGate.playing = true
        padGate.suspended = true
        ConsoleSound.shared.holdForGame()
        ConsoleFeel.shared.clearTriggers()
    }

    func shellTookThePad() {
        padGate.suspended = false
        controllers?.releaseLatches()
        ConsoleSound.shared.releaseForShell()
        if phase == .shell { ConsoleSound.shared.startMusic() }
    }

    /// Pointer position at the last pad move. SwiftUI fires hover whenever tiles slide under a
    /// resting pointer, which used to yank focus back out of the hero buttons.
    var pointerAtPad = NSEvent.mouseLocation
}
