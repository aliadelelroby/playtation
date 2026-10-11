import AppKit
import CoreGraphics

/// Before a game starts, switch each display to its highest native 1× mode, or to the highest
/// one that fits under the cap chosen in Settings. The previous mode is restored when the game closes.
enum DisplayFit {
    static let defaultsKey = "maxGameResolution"
    /// Stored value: "" for the highest available, "off" to leave the display alone, else "WIDTHxHEIGHT".
    static let off = "off"

    struct Option: Identifiable, Equatable {
        var id: String
        var title: String
    }

    static var setting: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Highest first, so the first entry is the default. The 1× sizes come from the main display.
    static func options() -> [Option] {
        var sizes: [(Int, Int)] = []
        for mode in modes(for: CGMainDisplayID()) where mode.pixelWidth == Int(mode.width) && mode.pixelHeight == Int(mode.height) {
            if !sizes.contains(where: { $0 == (mode.pixelWidth, mode.pixelHeight) }) {
                sizes.append((mode.pixelWidth, mode.pixelHeight))
            }
        }
        sizes.sort { ($0.0 * $0.1) > ($1.0 * $1.1) }
        var list = [Option(id: "", title: "Highest available")]
        list += sizes.map { Option(id: "\($0.0)x\($0.1)", title: "\($0.0) × \($0.1)") }
        list.append(Option(id: off, title: "Don't change"))
        return list
    }

    private static func cap() -> (Int, Int)? {
        let parts = setting.split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private static var saved: [(CGDirectDisplayID, CGDisplayMode)] = []
    private static var watching = false

    @discardableResult
    static func prepare() -> Bool {
        if setting == off { return true }
        watchQuit()
        return applyOneByOne()
    }

    static func restore() {
        guard !saved.isEmpty else { return }
        var config: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success, let config {
            for (id, mode) in saved.reversed() {
                _ = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
            }
            _ = CGCompleteDisplayConfiguration(config, .forSession)
        } else {
            for (id, mode) in saved.reversed() {
                _ = CGDisplaySetDisplayMode(id, mode, nil)
            }
        }
        saved.removeAll()
    }

    private static func applyOneByOne() -> Bool {
        var changed = false
        for id in displays() {
            guard let current = CGDisplayCopyDisplayMode(id),
                  let best = bestMode(for: id),
                  !same(best, current)
            else { continue }
            guard CGDisplaySetDisplayMode(id, best, nil) == .success else { continue }
            saved.append((id, current))
            changed = true
        }
        if changed { Thread.sleep(forTimeInterval: 0.35) }
        return changed || alreadyAtBest()
    }

    private static func alreadyAtBest() -> Bool {
        displays().allSatisfy { id in
            guard let current = CGDisplayCopyDisplayMode(id), let best = bestMode(for: id) else { return false }
            return same(best, current)
        }
    }

    private static func bestMode(for display: CGDirectDisplayID) -> CGDisplayMode? {
        let all = modes(for: display)
        var native = all.filter { $0.pixelWidth == Int($0.width) && $0.pixelHeight == Int($0.height) }
        if let (maxW, maxH) = cap() {
            let fitting = native.filter { $0.pixelWidth <= maxW && $0.pixelHeight <= maxH }
            if !fitting.isEmpty { native = fitting }
        }
        let panelW = native.map(\.pixelWidth).max() ?? all.map(\.pixelWidth).max() ?? 0
        let panelH = native.map(\.pixelHeight).max() ?? all.map(\.pixelHeight).max() ?? 0
        let exact = native.filter { $0.pixelWidth == panelW && $0.pixelHeight == panelH }
        let pool = exact.isEmpty ? (native.isEmpty ? all : native) : exact
        return pool.max { $0.refreshRate < $1.refreshRate }
    }

    private static func watchQuit() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in restore() }
    }

    private static func displays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var list = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &list, &count)
        return Array(list.prefix(Int(count)))
    }

    private static func modes(for display: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let all = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]
            ?? CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode]
            ?? []
        return all.filter { $0.pixelWidth >= 800 && $0.pixelHeight >= 600 }
    }

    private static func score(_ mode: CGDisplayMode) -> (Int, Int, Double) {
        (mode.pixelWidth * mode.pixelHeight, Int(mode.width) * Int(mode.height), mode.refreshRate)
    }

    private static func same(_ a: CGDisplayMode, _ b: CGDisplayMode) -> Bool {
        a.pixelWidth == b.pixelWidth
            && a.pixelHeight == b.pixelHeight
            && Int(a.width) == Int(b.width)
            && Int(a.height) == Int(b.height)
    }
}
