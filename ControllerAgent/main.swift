import AppKit
import GameController

let agent = ControllerLaunchAgent()
let app = NSApplication.shared
GCController.shouldMonitorBackgroundEvents = true
app.setActivationPolicy(.accessory)
app.delegate = agent
app.run()

final class ControllerLaunchAgent: NSObject, NSApplicationDelegate {
    private let bundleID = "com.playtation.Playtation"
    private var lastOpen = Date.distantPast
    private var activity: NSObjectProtocol?
    private var watch: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Playtation DualSense Home button")
        ProcessInfo.processInfo.disableSuddenTermination()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "Listen for DualSense Home button"
        )

        DualSenseHID.shared.onPS = { [weak self] pressed in
            self?.playstationChanged(pressed)
        }
        DualSenseHID.shared.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWoke),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appCameForward(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appCameForward(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        watch = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.redirectAppleGamesIfNeeded()
        }
        RunLoop.main.add(watch!, forMode: .common)

        GCController.controllers().forEach(setup)
        GCController.startWirelessControllerDiscovery {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            GCController.controllers().forEach { self?.setup($0) }
        }
    }

    @objc private func controllerConnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        setup(controller)
    }

    @objc private func systemWoke() {
        DualSenseHID.shared.restart()
        DualSenseHID.shared.onPS = { [weak self] pressed in
            self?.playstationChanged(pressed)
        }
        GCController.controllers().forEach(setup)
        GCController.startWirelessControllerDiscovery {}
    }

    @objc private func appCameForward(_ note: Notification) {
        let launched = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            ?? note.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication
        let id = launched?.bundleIdentifier?.lowercased() ?? ""
        if id == "com.apple.games" || id == "com.apple.gametrampoline" {
            redirectAppleGamesIfNeeded(force: true)
        }
    }

    /// macOS maps the DualSense PS button to Games.app. Treat that as Home and open Playtation instead.
    private func redirectAppleGamesIfNeeded(force: Bool = false) {
        guard force || HomeButtonSystem.gamesIsFrontmost else { return }
        HomeButtonSystem.dismissOverlay()
        openPlaytation()
    }

    private func setup(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let homeButtons = homeInputs(controller, pad: pad)
        for button in homeButtons {
            button.preferredSystemGestureState = .disabled
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.playstationChanged(pressed)
            }
            button.valueChangedHandler = { [weak self] _, _, pressed in
                self?.playstationChanged(pressed)
            }
        }
    }

    private func homeInputs(_ controller: GCController, pad: GCExtendedGamepad) -> [GCControllerButtonInput] {
        var buttons: [GCControllerButtonInput] = []
        if let home = pad.buttonHome { buttons.append(home) }
        if let named = controller.physicalInputProfile.buttons[GCInputButtonHome] { buttons.append(named) }
        for (name, input) in controller.physicalInputProfile.buttons {
            let key = name.lowercased()
            if key.contains("home") || key.contains("guide") || key.contains("logo") {
                buttons.append(input)
            }
        }
        var seen = Set<ObjectIdentifier>()
        return buttons.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private func playstationChanged(_ pressed: Bool) {
        if pressed {
            HomeButtonSystem.dismissOverlay()
            openPlaytation()
            for delay in [0.2, 0.5, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    HomeButtonSystem.dismissOverlay()
                }
            }
        }
        guard playtationIsRunning else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.playtation.psButton"),
            object: pressed ? "down" : "up",
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private var playtationIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func openPlaytation() {
        let now = Date()
        guard now.timeIntervalSince(lastOpen) > 0.6 else { return }
        guard let url = mainAppURL() else { return }
        lastOpen = now
        HomeButtonSystem.dismissOverlay()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", url.path]
        try? task.run()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private func mainAppURL() -> URL? {
        let nested = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if nested.pathExtension == "app",
           Bundle(url: nested)?.bundleIdentifier == bundleID {
            return nested
        }
        if FileManager.default.fileExists(atPath: "/Applications/Playtation.app") {
            return URL(fileURLWithPath: "/Applications/Playtation.app")
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
