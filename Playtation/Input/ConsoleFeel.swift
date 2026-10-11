import AppKit
import CoreHaptics
import GameController

/// DualSense rumble for the shell. Light on navigation, fuller on confirm, launch, and the PS button.
@MainActor
final class ConsoleFeel {
    static let shared = ConsoleFeel()

    private var handles: CHHapticEngine?
    private var left: CHHapticEngine?
    private var right: CHHapticEngine?
    private var trigger: CHHapticEngine?
    private var live: [any CHHapticPatternPlayer] = []
    private var attachedID: ObjectIdentifier?
    private weak var dualPad: GCDualSenseGamepad?
    private var startLatch = false

    func attach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        if attachedID == id, handles != nil {
            armStartTrigger(controller.extendedGamepad as? GCDualSenseGamepad)
            return
        }
        detach()
        attachedID = id
        if let haptics = controller.haptics {
            handles = boot(haptics.createEngine(withLocality: .handles) ?? haptics.createEngine(withLocality: .default))
            if haptics.supportedLocalities.contains(.leftHandle) {
                left = boot(haptics.createEngine(withLocality: .leftHandle))
            }
            if haptics.supportedLocalities.contains(.rightHandle) {
                right = boot(haptics.createEngine(withLocality: .rightHandle))
            }
            if haptics.supportedLocalities.contains(.rightTrigger) {
                trigger = boot(haptics.createEngine(withLocality: .rightTrigger))
            }
            connect()
        }
        armStartTrigger(controller.extendedGamepad as? GCDualSenseGamepad)
    }

    func detach() {
        clearTriggers()
        handles = nil
        left = nil
        right = nil
        trigger = nil
        live.removeAll()
        attachedID = nil
        dualPad = nil
        startLatch = false
    }

    /// R2 stays almost locked until the last millimetre, then the wall drops — the DualSense "weapon" click.
    func armStartTrigger(_ pad: GCDualSenseGamepad?) {
        dualPad = pad
        applyWeapon()
        startLatch = false
    }

    func armIfNeeded() {
        applyWeapon()
    }

    func clearTriggers() {
        dualPad?.rightTrigger.setModeOff()
        dualPad?.leftTrigger.setModeOff()
        startLatch = false
    }

    /// True once when R2 breaks through the hard wall.
    func triggerFired(value: Float, status: GCDualSenseAdaptiveTrigger.Status) -> Bool {
        if value < 0.2 {
            if startLatch { applyWeapon() }
            startLatch = false
            return false
        }
        let snapped = status == .weaponFired || value >= 0.83
        guard snapped, !startLatch else { return false }
        startLatch = true
        flick()
        return true
    }

    private func applyWeapon() {
        dualPad?.rightTrigger.setModeWeaponWithStartPosition(0.04, endPosition: 0.82, resistiveStrength: 1)
    }

    private func flick() {
        snap(trigger ?? handles, intensity: 0.85, sharpness: 0.95)
        play(
            [
                event(.hapticTransient, time: 0, intensity: 0.7, sharpness: 0.9),
                event(.hapticContinuous, time: 0.01, duration: 0.08, intensity: 0.4, sharpness: 0.6)
            ],
            on: handles
        )
    }

    func tick(horizontal: Int? = nil, vertical: Int? = nil) {
        mac(.alignment)
        if horizontal == -1 {
            snap(left, intensity: 0.46, sharpness: 0.88)
            snap(right ?? handles, intensity: 0.14, sharpness: 0.45)
            return
        }
        if horizontal == 1 {
            snap(right, intensity: 0.46, sharpness: 0.88)
            snap(left ?? handles, intensity: 0.14, sharpness: 0.45)
            return
        }
        if vertical != nil {
            snap(handles, intensity: 0.34, sharpness: 0.72)
            return
        }
        snap(handles, intensity: 0.3, sharpness: 0.68)
    }

    func bump() {
        mac(.levelChange)
        play(
            [
                event(.hapticTransient, time: 0, intensity: 0.48, sharpness: 0.22),
                event(.hapticTransient, time: 0.045, intensity: 0.28, sharpness: 0.18)
            ],
            on: handles
        )
    }

    func confirm() {
        mac(.generic)
        play(
            [
                event(.hapticTransient, time: 0, intensity: 0.62, sharpness: 0.42),
                event(.hapticContinuous, time: 0.02, duration: 0.11, intensity: 0.32, sharpness: 0.38),
                event(.hapticTransient, time: 0.09, intensity: 0.4, sharpness: 0.55)
            ],
            on: handles
        )
    }

    func back() {
        mac(.generic)
        play(
            [
                event(.hapticContinuous, time: 0, duration: 0.09, intensity: 0.22, sharpness: 0.18),
                event(.hapticTransient, time: 0.04, intensity: 0.2, sharpness: 0.12)
            ],
            on: handles
        )
    }

    func welcome() {
        swell(duration: 0.42, from: 0.12, peak: 0.4)
    }

    func launch() {
        swell(duration: 0.55, from: 0.18, peak: 0.72)
        play(
            [event(.hapticTransient, time: 0.08, intensity: 0.55, sharpness: 0.35)],
            on: handles
        )
    }

    func halt() {
        play(
            [
                event(.hapticContinuous, time: 0, duration: 0.16, intensity: 0.38, sharpness: 0.2),
                event(.hapticTransient, time: 0.12, intensity: 0.3, sharpness: 0.1)
            ],
            on: handles
        )
    }

    func error() {
        mac(.generic)
        play(
            [
                event(.hapticTransient, time: 0, intensity: 0.7, sharpness: 0.85),
                event(.hapticTransient, time: 0.07, intensity: 0.55, sharpness: 0.7)
            ],
            on: handles
        )
    }

    func ps() {
        play(
            [
                event(.hapticTransient, time: 0, intensity: 0.5, sharpness: 0.5),
                event(.hapticContinuous, time: 0.02, duration: 0.14, intensity: 0.28, sharpness: 0.4)
            ],
            on: handles
        )
    }

    func menu() {
        swell(duration: 0.38, from: 0.16, peak: 0.48)
        play(
            [event(.hapticTransient, time: 0.02, intensity: 0.36, sharpness: 0.3)],
            on: handles
        )
    }

    func connect() {
        play(
            [
                event(.hapticTransient, time: 0, intensity: 0.22, sharpness: 0.7),
                event(.hapticTransient, time: 0.07, intensity: 0.3, sharpness: 0.6),
                event(.hapticTransient, time: 0.16, intensity: 0.42, sharpness: 0.5)
            ],
            on: handles
        )
    }

    private func swell(duration: TimeInterval, from: Float, peak: Float) {
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: from),
                .init(relativeTime: duration * 0.45, value: peak),
                .init(relativeTime: duration, value: 0.02)
            ],
            relativeTime: 0
        )
        play(
            [event(.hapticContinuous, time: 0, duration: duration, intensity: 1, sharpness: 0.28)],
            curves: [curve],
            on: handles
        )
    }

    private func snap(_ engine: CHHapticEngine?, intensity: Float, sharpness: Float) {
        play(
            [event(.hapticTransient, time: 0, intensity: intensity, sharpness: sharpness)],
            on: engine ?? handles
        )
    }

    private func event(
        _ type: CHHapticEvent.EventType,
        time: TimeInterval,
        duration: TimeInterval = 0,
        intensity: Float,
        sharpness: Float
    ) -> CHHapticEvent {
        let parameters = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ]
        if type == .hapticContinuous {
            return CHHapticEvent(eventType: type, parameters: parameters, relativeTime: time, duration: duration)
        }
        return CHHapticEvent(eventType: type, parameters: parameters, relativeTime: time)
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = [], on engine: CHHapticEngine?) {
        guard let engine else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            live.append(player)
            if live.count > 10 { live.removeFirst(live.count - 10) }
        } catch {
            try? engine.start()
        }
    }

    private func boot(_ engine: CHHapticEngine?) -> CHHapticEngine? {
        guard let engine else { return nil }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.resetHandler = { [weak engine] in
            try? engine?.start()
        }
        engine.stoppedHandler = { [weak engine] _ in
            try? engine?.start()
        }
        do {
            try engine.start()
            return engine
        } catch {
            return nil
        }
    }

    private func mac(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
