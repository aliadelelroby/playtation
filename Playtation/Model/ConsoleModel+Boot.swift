import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

/// Boot screen and welcome flow.
extension ConsoleModel {
    func enter() {
        phase = .shell
        signingIn = false
        ConsoleSound.shared.startMusic()
        ConsoleFeel.shared.armIfNeeded()
    }

    func presentWelcome() {
        guard phase == .boot else { return }
        welcomeIntroduced = false
        phase = .welcome
        ConsoleSound.shared.welcome()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard self.phase == .welcome, !self.signingIn else { return }
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.05)) {
                self.welcomeIntroduced = true
            }
        }
    }

    func hoverWelcome() {
        guard phase == .welcome, !signingIn, welcomeIntroduced else { return }
        ConsoleSound.shared.hover()
    }

    func confirmWelcome() {
        guard phase == .welcome, !signingIn else { return }
        signingIn = true
        ConsoleSound.shared.confirm()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard self.phase == .welcome, self.signingIn else { return }
            self.enter()
        }
    }

    func returnToBoot() {
        guard phase == .welcome, !signingIn else { return }
        ConsoleSound.shared.back()
        ConsoleSound.shared.stopMusic()
        welcomeIntroduced = false
        bootCue = 0
        bootReady = false
        phase = .boot
    }

    /// Starts the five-second wait before the PS button is accepted.
    func armBootPrompt(after delay: TimeInterval = 5) {
        bootReady = false
        bootGeneration += 1
        let generation = bootGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard generation == self.bootGeneration, self.phase == .boot else { return }
            self.bootReady = true
        }
    }

    func disarmBootPrompt() {
        bootGeneration += 1
        bootReady = false
    }

    func setControllerConnected(_ connected: Bool) {
        if controllerConnected != connected {
            controllerConnected = connected
        }
    }

    func signalBoot() {
        guard phase == .boot, bootCue == 0, bootReady, controllerConnected else { return }
        ConsoleFeel.shared.ps()
        bootCue += 1
    }
}
