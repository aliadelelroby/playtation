import AppKit
import ScreenCaptureKit

/// Developer tool for the README images. Launch with `PLAYTATION_CAPTURE_DIR=/some/folder` and the app
/// walks through the main screens, saves a PNG of its own window for each, then quits.
/// It captures only Playtation's window (no Screen Recording permission), uses a generic profile, and does
/// nothing at all unless the variable is set.
@MainActor
enum ScreenshotTour {
    nonisolated static let directory: URL? = {
        guard let path = ProcessInfo.processInfo.environment["PLAYTATION_CAPTURE_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    nonisolated static var isOn: Bool { directory != nil }

    static func run(model: ConsoleModel) async {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await pause(5)
        model.enter()
        await pause(4)

        let games = model.games
        if let index = games.firstIndex(where: { !$0.isApp && !model.backdrops(for: $0).isEmpty }) {
            model.select(index)
        }
        await pause(2.5)
        await save("home", in: directory)

        model.openAdd()
        await pause(2.5)
        await save("add-game", in: directory)
        model.closeAdd()


        await pause(1)
        if let index = model.games.firstIndex(where: { $0.webURL != nil }) {
            model.select(index)
        }
        await pause(2.5)
        await save("apps", in: directory)

        model.select(0)
        await pause(1)
        model.activateTop(0)
        for character in "spider" { model.kbType(String(character)) }
        await pause(1.5)
        await save("search", in: directory)
        model.finishSearch()
        model.query = ""

        await pause(1)
        model.tab = .settings
        model.settingsSection = 2
        await pause(1.2)
        await save("settings", in: directory)

        model.tab = .home
        model.zone = .top
        model.topIndex = 2
        await pause(1)
        model.openProfile()
        await pause(1.5)
        await save("profile-menu", in: directory)
        model.showProfile = false

        // Sample patterns only. Nothing is submitted, so the saved pattern is untouched.
        await pause(1)
        model.beginPatternSetup()
        draw([0, 1, 2, 4, 6, 7, 8], then: nil, model: model)
        await pause(1.5)
        await save("pattern-setup", in: directory)
        model.cancelPattern()

        await pause(1)
        model.phase = .welcome
        model.welcomeIntroduced = true
        model.askForPattern()
        draw([3, 7, 5], then: CGPoint(x: 0.8, y: 0.26), model: model)
        await pause(2)
        await save("pattern-sign-in", in: directory)
        NSApp.terminate(nil)
    }

    /// Slides through the dots the way a finger would, without lifting, so the last line stays live.
    private static func draw(_ dots: [Int], then finger: CGPoint?, model: ConsoleModel) {
        var last: CGPoint?
        let points = dots.map(PatternTrace.center(of:)) + (finger.map { [$0] } ?? [])
        for point in points {
            if let last {
                for step in 1...10 {
                    let t = CGFloat(step) / 10
                    model.patternPointer(CGPoint(x: last.x + (point.x - last.x) * t, y: last.y + (point.y - last.y) * t))
                }
            } else {
                model.patternPointer(point)
            }
            last = point
        }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// ScreenCaptureKit renders the real compositor output (glass, blur, Metal), unlike `cacheDisplay`.
    private static func save(_ name: String, in directory: URL) async {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) else { return }
        let id = CGWindowID(window.windowNumber)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let target = content.windows.first(where: { $0.windowID == id })
        else {
            FileHandle.standardError.write(Data("capture: window not shareable\n".utf8))
            return
        }
        let config = SCStreamConfiguration()
        config.width = Int(target.frame.width * 2)
        config.height = Int(target.frame.height * 2)
        config.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: target)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
