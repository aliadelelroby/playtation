import AppKit
import ApplicationServices
import CoreGraphics

/// Brings the running game forward and full-screens it. Never prompts for TCC.
enum GameFocus {
    /// Smaller windows are splashes, hidden helpers or toolbars, never the game itself.
    private static let minimumGameSize = CGSize(width: 640, height: 400)

    /// True only when the game has a real on-screen window, not a splash or a hidden 500×500 helper.
    static func hasVisibleWindow(pids: [pid_t]) -> Bool {
        if AXIsProcessTrusted() { return gameWindow(in: pids) != nil }
        return largestScreenWindow(pids) != nil
    }

    /// Waits for the game's real window, then focuses it and fills the screen once.
    /// Slow starters (Steam starting in the background, AIR splash screens) can take most of a minute.
    @discardableResult
    static func present(winePID: Int32, executablePath: String?, windowsStart: String) async -> Bool {
        let ours = ProcessInfo.processInfo.processIdentifier
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            let gamePids = ProcessProbe.gameProcessIDs(
                winePID: winePID,
                executablePath: executablePath,
                windowsStart: windowsStart
            ) + ProcessProbe.namedGameIDs(executablePath: executablePath, windowsStart: windowsStart)
            if !gamePids.isEmpty {
                let pids = Array(Set(
                    (gamePids + ProcessProbe.wineTreeIDs(winePID: winePID))
                        .filter { $0 != ours && $0 > 0 }
                ))
                if hasVisibleWindow(pids: pids) {
                    await fill(pids)
                    return true
                }
                // Splash screen: bring it forward, but leave its size alone.
                for pid in gamePids { activate(pid, window: nil) }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private static func fill(_ pids: [pid_t]) async {
        guard AXIsProcessTrusted(), let (pid, window) = gameWindow(in: pids) else {
            // No Accessibility: the game's own full-screen shortcut is all there is.
            for pid in pids { activate(pid, window: nil) }
            try? await Task.sleep(nanoseconds: 250_000_000)
            sendFullScreenKeys()
            return
        }
        activate(pid, window: window)
        try? await Task.sleep(nanoseconds: 250_000_000)
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: 900_000_000)
        if coversScreen(window) { return }
        // Not every Wine window accepts macOS full screen. Try the game's own shortcut once, then stretch it.
        sendFullScreenKeys()
        try? await Task.sleep(nanoseconds: 900_000_000)
        if coversScreen(window) { return }
        placeOnScreen(window)
        activate(pid, window: window)
    }

    private static func activate(_ pid: pid_t, window: AXUIElement?) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        guard AXIsProcessTrusted() else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let window {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    private static func placeOnScreen(_ window: AXUIElement) {
        let screen = NSScreen.main?.frame ?? .zero
        var origin = CGPoint(x: screen.origin.x, y: 0)
        var size = screen.size
        if let pos = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        }
        if let sz = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func coversScreen(_ window: AXUIElement) -> Bool {
        if let full = attribute(window, "AXFullScreen") as? Bool, full { return true }
        guard let size = size(of: window), let screen = NSScreen.main?.frame.size else { return false }
        return size.width >= screen.width - 2 && size.height >= screen.height - 40
    }

    /// The largest game-sized window across the game's processes, skipping splashes and minimized ones.
    private static func gameWindow(in pids: [pid_t]) -> (pid_t, AXUIElement)? {
        var best: (pid: pid_t, window: AXUIElement, area: CGFloat)?
        for pid in pids {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }
            for window in windows {
                if (attribute(window, kAXMinimizedAttribute) as? Bool) == true { continue }
                guard let size = size(of: window),
                      size.width >= minimumGameSize.width, size.height >= minimumGameSize.height else { continue }
                let area = size.width * size.height
                if best == nil || area > best!.area { best = (pid, window, area) }
            }
        }
        return best.map { ($0.pid, $0.window) }
    }

    /// Without Accessibility: an on-screen window of game size, if Screen Recording lets us see the list.
    private static func largestScreenWindow(_ pids: [pid_t]) -> pid_t? {
        guard CGPreflightScreenCaptureAccess(),
              let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list.first { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid) else { return false }
            let bounds = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return (bounds["Width"] ?? 0) >= minimumGameSize.width && (bounds["Height"] ?? 0) >= minimumGameSize.height
        }.flatMap { $0[kCGWindowOwnerPID as String] as? pid_t }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func size(of window: AXUIElement) -> CGSize? {
        guard let value = attribute(window, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    /// The usual full-screen shortcuts for Wine games. Sent once: sending them again would toggle back out.
    private static func sendFullScreenKeys() {
        sendKey(.return, flags: .maskCommand)
        usleep(220_000)
        sendKey(.return, flags: .maskAlternate)
    }

    private static func sendKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

private extension CGKeyCode {
    static let `return`: CGKeyCode = 0x24
}
