import AppKit
import CoreText
import SwiftUI

@main
struct PlaytationApp: App {
    @StateObject private var model = ConsoleModel()

    init() {
        registerFonts()
        ControllerAgentInstaller.install()
    }

    var body: some Scene {
        WindowGroup(id: "console") {
            RootView()
                .environmentObject(model)
                .background(WindowOpener())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands { PlaytationCommands() }
    }

    private func registerFonts() {
        let sets = [
            Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
            Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil)
        ]
        for url in sets.compactMap({ $0 }).flatMap({ $0 }) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Kept off the main-actor shell. The system menu bar rebuilds this when the app
/// resigns, and reading the shell there crashes in MenuBarClientCore.
private struct PlaytationCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .toolbar) {
            Button("Toggle Full Screen") {
                PlaytationWindow.toggle()
                NotificationCenter.default.post(name: .playtationWindowMode, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
        }
        CommandMenu("Library") {
            Button("Rescan CrossOver") {
                NotificationCenter.default.post(name: .playtationRescan, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

private struct WindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                PlaytationLaunch.openWindow = { openWindow(id: "console") }
            }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: ConsoleModel

    var body: some View {
        ShellView()
            .background(WindowChrome())
            .frame(minWidth: 1100, minHeight: 700)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
                model.refresh()
                PlaytationWindow.applyLaunchPreference()
            }
    }
}

struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowHook() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowHook: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        PlaytationWindow.configure(window)
    }
}

enum PlaytationWindow {
    /// Opt-out only. Full screen is the default; a window is remembered when the user turns it off.
    static let windowedKey = "playtation.windowed"
    private static var watching = false
    private static var launchHandled = false

    private static var yieldingToGame = false

    static var prefersFullScreen: Bool {
        get { !UserDefaults.standard.bool(forKey: windowedKey) }
        set { UserDefaults.standard.set(!newValue, forKey: windowedKey) }
    }

    static var isFullScreen: Bool {
        NSApp.windows.contains { $0.styleMask.contains(.fullScreen) }
    }

    static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.title = "Playtation"
        window.tabbingMode = .disallowed
        window.standardWindowButton(.zoomButton)?.isEnabled = true
        watch()
        enterFullScreenIfPreferred(window)
    }

    static func applyLaunchPreference() {
        watch()
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.canBecomeMain) {
            enterFullScreenIfPreferred(window)
        }
    }

    static func setFullScreen(_ on: Bool, persist: Bool = true) {
        if persist { prefersFullScreen = on }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.canBecomeMain) else { return }
        if window.styleMask.contains(.fullScreen) != on {
            window.toggleFullScreen(nil)
        }
    }

    static func toggle() {
        setFullScreen(!isFullScreen)
    }

    private static func watch() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard !yieldingToGame else { return }
            guard let window = note.object as? NSWindow, window.canBecomeMain else { return }
            enterFullScreenIfPreferred(window)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            guard yieldingToGame else { return }
            yieldingToGame = false
            launchHandled = false
            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.canBecomeMain) {
                enterFullScreenIfPreferred(window)
            }
        }
    }

    /// Leave the fullscreen Space so Wine windows land on the desktop, not a dead Space.
    /// `toggleFullScreen` must run on the main thread — Swift continuations are not MainActor.
    static func yieldToGame() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                yieldingToGame = true
                launchHandled = true
                guard let window = NSApp.windows.first(where: { $0.styleMask.contains(.fullScreen) }) else {
                    cont.resume()
                    return
                }
                var finished = false
                let finish = {
                    guard !finished else { return }
                    finished = true
                    cont.resume()
                }
                var token: NSObjectProtocol?
                token = NotificationCenter.default.addObserver(
                    forName: NSWindow.didExitFullScreenNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    if let token { NotificationCenter.default.removeObserver(token) }
                    finish()
                }
                window.toggleFullScreen(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if let token { NotificationCenter.default.removeObserver(token) }
                    finish()
                }
            }
        }
    }

    private static func enterFullScreenIfPreferred(_ window: NSWindow, attempt: Int = 0) {
        guard prefersFullScreen else {
            launchHandled = true
            return
        }
        if window.styleMask.contains(.fullScreen) {
            launchHandled = true
            return
        }
        guard !launchHandled else { return }
        guard attempt < 25 else { return }
        if window.screen == nil || !window.isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                enterFullScreenIfPreferred(window, attempt: attempt + 1)
            }
            return
        }
        window.toggleFullScreen(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            enterFullScreenIfPreferred(window, attempt: attempt + 1)
        }
    }
}
