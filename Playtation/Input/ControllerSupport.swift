import AppKit
import GameController

/// Binds game controllers to the shell: buttons, sticks, triggers and the PS button.
final class ControllerSupport {
    weak var model: ConsoleModel?
    private var stickLatch = false
    private var triggerLatch = false
    private var lastStart = Date.distantPast

    init(model: ConsoleModel) {
        self.model = model
    }

    func releaseLatches() {
        stickLatch = false
        triggerLatch = false
    }

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playstationNote(_:)),
            name: Notification.Name("com.playtation.psButton"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connect),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(disconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        for controller in GCController.controllers() {
            bind(controller)
        }
        publishConnection()
        GCController.startWirelessControllerDiscovery {}
        DualSenseHID.shared.onPS = { [weak self] pressed in
            Task { @MainActor in
                self?.model?.controllerPS(pressed: pressed)
            }
        }
        DualSenseHID.shared.start()
    }

    @objc private func connect(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        bind(controller)
        publishConnection()
    }

    @objc private func disconnect(_ note: Notification) {
        publishConnection()
    }

    private func publishConnection() {
        let controllers = GCController.controllers()
        Task { @MainActor in
            self.model?.setControllerConnected(!controllers.isEmpty)
            if let controller = controllers.last {
                ConsoleFeel.shared.attach(controller)
            } else {
                ConsoleFeel.shared.detach()
            }
        }
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        Self.claimHomeButton(controller, pad: pad)
        pad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.moveHorizontal(-1) }
        }
        pad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.moveHorizontal(1) }
        }
        pad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.moveVertical(-1) }
        }
        pad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.moveVertical(1) }
        }
        pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.shoulder(-1) }
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.shoulder(1) }
        }
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.cross() }
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.circle() }
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.square() }
        }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.tap(pressed) { $0.triangle() }
        }
        bindHome(controller, pad: pad)
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.startPressed(pressed)
        }
        pad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.startPressed(pressed)
        }
        if let dual = pad as? GCDualSenseGamepad {
            dual.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
                Task { @MainActor in
                    guard ConsoleFeel.shared.triggerFired(value: value, status: dual.rightTrigger.status) else { return }
                    self?.model?.startFromTrigger()
                }
            }
        } else {
            pad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
                guard let self else { return }
                if value < 0.4 {
                    self.triggerLatch = false
                    return
                }
                guard value >= 0.95, !self.triggerLatch else { return }
                self.triggerLatch = true
                Task { @MainActor in
                    self.model?.startFromTrigger()
                }
            }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self else { return }
            if abs(x) < 0.45 && abs(y) < 0.45 {
                self.stickLatch = false
                return
            }
            guard !self.stickLatch else { return }
            self.stickLatch = true
            Task { @MainActor in
                if abs(x) >= abs(y) {
                    self.model?.moveHorizontal(x > 0 ? 1 : -1)
                } else {
                    self.model?.moveVertical(y > 0 ? -1 : 1)
                }
            }
        }
    }

    /// Stops macOS Game Overlay from eating the DualSense PS button while Playtation is frontmost.
    static func claimHomeButton(_ controller: GCController, pad: GCExtendedGamepad) {
        let targets: [GCControllerButtonInput?] = [
            pad.buttonHome,
            controller.physicalInputProfile.buttons[GCInputButtonHome]
        ]
        for button in targets.compactMap({ $0 }) {
            button.preferredSystemGestureState = .disabled
        }
        for (name, input) in controller.physicalInputProfile.buttons {
            let key = name.lowercased()
            if key.contains("home") || key.contains("guide") {
                input.preferredSystemGestureState = .disabled
            }
        }
    }

    private func bindHome(_ controller: GCController, pad: GCExtendedGamepad) {
        var buttons: [GCControllerButtonInput] = []
        if let home = pad.buttonHome { buttons.append(home) }
        if let named = controller.physicalInputProfile.buttons[GCInputButtonHome] {
            buttons.append(named)
        }
        for (name, input) in controller.physicalInputProfile.buttons {
            let key = name.lowercased()
            guard key.contains("home") || key.contains("guide") else { continue }
            buttons.append(input)
        }
        let unique = Array(Set(buttons.map { ObjectIdentifier($0) })).compactMap { id in
            buttons.first { ObjectIdentifier($0) == id }
        }
        for home in unique {
            home.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in
                    self?.model?.controllerPS(pressed: pressed)
                }
            }
            home.valueChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in
                    self?.model?.controllerPS(pressed: pressed)
                }
            }
        }
    }

    @objc private func playstationNote(_ note: Notification) {
        let down = (note.object as? String) == "down"
        Task { @MainActor in
            self.model?.controllerPS(pressed: down)
        }
    }

    /// Options/Menu opens the power menu only while Playtation is the front app.
    /// It must not launch or raise the app. The PS button does that.
    private func startPressed(_ pressed: Bool) {
        guard pressed else { return }
        guard NSApp.isActive, NSApp.windows.contains(where: { $0.canBecomeMain && $0.isVisible }) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastStart) > 0.35 else { return }
        lastStart = now
        Task { @MainActor in
            self.model?.psButton()
        }
    }

    private func tap(_ pressed: Bool, _ action: @escaping @MainActor (ConsoleModel) -> Void) {
        guard pressed else { return }
        Task { @MainActor in
            guard let model = self.model else { return }
            action(model)
        }
    }
}
