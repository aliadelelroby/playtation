import AppKit
import ApplicationServices
import CoreGraphics

/// Brings the running game forward and full-screens it. Never prompts for TCC.
enum GameFocus {
    /// True only when the game has a real on-screen window, not a hidden 500×500 splash.
    static func hasVisibleWindow(pids: [pid_t]) -> Bool {
        if AXIsProcessTrusted(), pids.contains(where: { firstWindow($0) != nil }) {
            return true
        }
        guard CGPreflightScreenCaptureAccess() else { return false }
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid) else { return false }
            let bounds = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return (bounds["Width"] ?? 0) >= 640 && (bounds["Height"] ?? 0) >= 400
        }
    }

    @discardableResult
    static func present(winePID: Int32, executablePath: String?, windowsStart: String) async -> Bool {
        let ours = ProcessInfo.processInfo.processIdentifier
        let deadline = Date().addingTimeInterval(20)
        var seen: Date?
        while Date() < deadline {
            let gamePids = ProcessProbe.gameProcessIDs(
                winePID: winePID,
                executablePath: executablePath,
                windowsStart: windowsStart
            ) + ProcessProbe.namedGameIDs(executablePath: executablePath, windowsStart: windowsStart)
            if !gamePids.isEmpty {
                if seen == nil { seen = Date() }
                let unique = Array(Set(
                    (gamePids + ProcessProbe.wineTreeIDs(winePID: winePID))
                        .filter { $0 != ours && $0 > 0 }
                ))
                await fullscreen(unique)
                if hasVisibleWindow(pids: unique) { return true }
                if let seen, Date().timeIntervalSince(seen) > 12 { return hasVisibleWindow(pids: unique) }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    private static func fullscreen(_ pids: [pid_t]) async {
        for pid in pids { activate(pid) }
        try? await Task.sleep(nanoseconds: 250_000_000)
        if AXIsProcessTrusted() {
            for pid in pids {
                placeOnScreen(pid)
                _ = setFullScreen(pid)
            }
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        sendKey(.return, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 220_000_000)
        sendKey(.return, flags: .maskAlternate)
        try? await Task.sleep(nanoseconds: 200_000_000)
        for pid in pids { activate(pid) }
    }

    private static func activate(_ pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        guard AXIsProcessTrusted() else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let window = firstWindow(pid) {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    private static func placeOnScreen(_ pid: pid_t) {
        guard let window = firstWindow(pid) else { return }
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

    @discardableResult
    private static func setFullScreen(_ pid: pid_t) -> Bool {
        guard let window = firstWindow(pid) else { return false }
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanTrue)
        return true
    }

    private static func firstWindow(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement],
              let window = windows.first
        else { return nil }
        return window
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
