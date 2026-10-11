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
        NSApp.terminate(nil)
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
