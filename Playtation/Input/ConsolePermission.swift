import AppKit
import ApplicationServices
import CoreGraphics

/// Asks macOS for Accessibility / Screen Recording only when they are actually missing.
enum ConsolePermission {
    private static var askedThisLaunch = false

    static var canControlWindows: Bool { AXIsProcessTrusted() }
    static var canSeeWindows: Bool { CGPreflightScreenCaptureAccess() }
    static var granted: Bool { canControlWindows && canSeeWindows }

    static func askAtLaunch() {
        askedThisLaunch = true
    }

    @discardableResult
    static func request(openSettingsIfDenied: Bool) async -> Bool {
        if granted { return true }
        if !canControlWindows { promptAccessibility() }
        if !canSeeWindows { promptScreenCapture() }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if granted { return true }
        if openSettingsIfDenied {
            await MainActor.run { explainAndOpenSettings() }
        }
        return granted
    }

    private static func promptAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func promptScreenCapture() {
        if CGPreflightScreenCaptureAccess() { return }
        _ = CGRequestScreenCaptureAccess()
    }

    private static func explainAndOpenSettings() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Playtation needs permission to run games"
        alert.informativeText = "Turn on Accessibility and Screen & System Audio Recording for Playtation. That lets it focus the game, full-screen it, and then quit the console."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !canControlWindows {
            openPrivacy("Privacy_Accessibility")
        }
        if !canSeeWindows {
            openPrivacy("Privacy_ScreenCapture")
        }
    }

    private static func openPrivacy(_ pane: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)",
            "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }
}

enum PlaytationShell {
    static func dismiss() {
        NSApp.hide(nil)
        for window in NSApp.windows where window.canBecomeMain {
            window.orderOut(nil)
        }
    }

    /// Mute and shrink to the Dock. Fullscreen is already left before the game
    /// starts so Wine windows land on the desktop. Do not hide/quit — hide was
    /// covering the game Space, and quit was killing Wine.
    @MainActor
    static func leaveForGame() {
        ConsoleSound.shared.silence()
        for window in NSApp.windows {
            window.miniaturize(nil)
        }
    }
}
