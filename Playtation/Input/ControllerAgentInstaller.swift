import AppKit
import Foundation

/// Opens the console window when Playtation is running but not in front, or after its window was closed.
enum PlaytationLaunch {
    static var openWindow: (() -> Void)?

    static func reveal() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: \.canBecomeMain) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard PlaytationWindow.prefersFullScreen else { return }
            PlaytationWindow.setFullScreen(true, persist: false)
        }
    }
}

/// Installs the controller helper as a login agent so Start still works after Playtation quits.
enum ControllerAgentInstaller {
    private static let label = "com.playtation.controller"

    static func install() {
        HomeButtonSystem.restoreDelivery()
        guard let helper = helperExecutable() else { return }
        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            let plistURL = agents.appendingPathComponent("\(label).plist")
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist(program: helper.path),
                format: .xml,
                options: 0
            )
            let changed = (try? Data(contentsOf: plistURL)) != data
            if changed {
                try data.write(to: plistURL, options: .atomic)
            }
            let uid = getuid()
            let domain = "gui/\(uid)"
            let service = "\(domain)/\(label)"
            if changed {
                if launchctl(["print", service]) {
                    _ = launchctl(["bootout", service])
                }
                _ = launchctl(["bootstrap", domain, plistURL.path])
            } else if launchctl(["print", service]) {
                _ = launchctl(["kickstart", "-k", service])
            } else {
                _ = launchctl(["bootstrap", domain, plistURL.path])
            }
        } catch {
            NSLog("Playtation controller agent: \(error.localizedDescription)")
        }
    }

    private static func plist(program: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [program],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "ThrottleInterval": 0,
            "LimitLoadToSessionType": "Aqua"
        ]
    }

    private static func helperExecutable() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/PlaytationController.app/Contents/MacOS/PlaytationController")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
