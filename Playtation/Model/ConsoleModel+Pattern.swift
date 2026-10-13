import AppKit
import SwiftUI

/// Sign-in pattern: asking for it on the profile screen and setting it up from Settings.
extension ConsoleModel {
    var hasPattern: Bool { currentProfile.pattern != nil }

    enum ProfileAction: Equatable {
        case setPattern, removePattern, signOut, power

        func title(hasPattern: Bool, sharedConsole: Bool = false) -> String {
            switch self {
            case .setPattern: return hasPattern ? "Change sign-in pattern" : "Set sign-in pattern"
            case .removePattern: return "Remove sign-in pattern"
            case .signOut: return sharedConsole ? "Switch user" : "Sign out"
            case .power: return "Power"
            }
        }
    }

    var profileActions: [ProfileAction] {
        hasPattern ? [.setPattern, .removePattern, .signOut, .power] : [.setPattern, .signOut, .power]
    }

    func openProfile() {
        panelIndex = 0
        withAnimation(.easeOut(duration: 0.2)) {
            showProfile = true
            showMore = false
            showDetails = false
            showSettings = false
            showPower = false
        }
    }

    func confirmProfile() {
        let actions = profileActions
        guard actions.indices.contains(panelIndex) else { return }
        let action = actions[panelIndex]
        withAnimation(.easeOut(duration: 0.2)) { showProfile = false }
        switch action {
        case .setPattern:
            beginPatternSetup()
        case .removePattern:
            removePattern()
        case .signOut:
            signOut()
        case .power:
            psButton()
        }
    }

    /// Back to the profile screen, which asks for the pattern again if one is set.
    func signOut() {
        guard phase == .shell else { return }
        ConsoleSound.shared.back()
        ConsoleSound.shared.stopMusic()
        searching = false
        tab = .home
        zone = .tiles
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

    func askForPattern() {
        openPattern(.unlock, message: nil)
        ConsoleSound.shared.confirm()
    }

    /// First sign-in: ask on the profile screen whether to protect it with a pattern.
    func offerPattern() {
        ConsoleSound.shared.confirm()
        patternOfferChoice = 0
        withAnimation(.easeOut(duration: 0.25)) { patternOffer = true }
    }

    func confirmPatternOffer() {
        guard patternOffer else { return }
        withAnimation(.easeOut(duration: 0.25)) { patternOffer = false }
        if patternOfferChoice == 0 {
            beginPatternSetup()
        } else {
            updateProfile(profileID) { $0.patternOffered = true }
            signIn()
        }
    }

    /// Circle on the offer: back to the profile card. It asks again next time.
    func dismissPatternOffer() {
        guard patternOffer else { return }
        ConsoleSound.shared.back()
        withAnimation(.easeOut(duration: 0.25)) { patternOffer = false }
    }

    func beginPatternSetup() {
        ConsoleSound.shared.confirm()
        withAnimation(.easeOut(duration: 0.2)) {
            openPattern(.create, message: nil)
        }
    }

    func removePattern() {
        guard hasPattern else { return }
        updateProfile(profileID) { $0.pattern = nil }
        ConsoleSound.shared.confirm()
        settingsRow = min(settingsRow, settingsRowCount - 1)
        banner = "Sign-in pattern removed."
        objectWillChange.send()
    }

    func cancelPattern() {
        guard let prompt = patternPrompt else { return }
        ConsoleSound.shared.back()
        withAnimation(.easeOut(duration: 0.2)) {
            patternPrompt = nil
            // Backing out of first-sign-in setup returns to the offer, not the bare profile.
            if phase == .welcome, prompt != .unlock { patternOffer = true }
        }
        pattern.reset()
        patternMessage = nil
        patternFailed = false
    }

    /// A touchpad sample. Both axes run -1...1 with up positive.
    func patternTouch(x: Float, y: Float) {
        patternPointer(CGPoint(x: CGFloat(x + 1) / 2, y: CGFloat(1 - y) / 2))
    }

    /// A point in grid space, from the touchpad or the pointer.
    func patternPointer(_ point: CGPoint) {
        guard patternPrompt != nil, shellOwnsPad(), !signingIn else { return }
        if patternFailed {
            patternFailed = false
            pattern.reset()
        }
        if pattern.move(to: point) {
            ConsoleSound.shared.tick()
            ConsoleFeel.shared.tick()
        }
    }

    /// Finger left the touchpad (or the mouse button came up): that ends the pattern.
    func patternLift() {
        guard patternPrompt != nil else { return }
        pattern.lift()
        if !pattern.isEmpty, !patternFailed { submitPattern() }
    }

    func submitPattern() {
        guard let prompt = patternPrompt, !patternFailed, !signingIn else { return }
        let dots = pattern.dots
        guard !dots.isEmpty else {
            ConsoleFeel.shared.bump()
            return
        }
        if prompt != .unlock, dots.count < PatternTrace.minimumDots {
            rejectPattern("Connect at least \(PatternTrace.minimumDots) dots.")
            return
        }
        switch prompt {
        case .unlock:
            guard PatternLock.matches(dots, sealed: currentProfile.pattern) else {
                rejectPattern("Wrong pattern. Try again.")
                return
            }
            patternPrompt = nil
            pattern.reset()
            patternMessage = nil
            signIn()
        case .create:
            ConsoleSound.shared.confirm()
            pattern.reset()
            patternPrompt = .confirm(dots)
            patternMessage = nil
        case .confirm(let first):
            guard dots == first else {
                rejectPattern("Those didn't match. Draw a new pattern.", restart: true)
                return
            }
            updateProfile(profileID) {
                $0.pattern = PatternLock.seal(dots)
                $0.patternOffered = true
            }
            ConsoleSound.shared.confirm()
            withAnimation(.easeOut(duration: 0.2)) { patternPrompt = nil }
            pattern.reset()
            patternMessage = nil
            if phase == .welcome {
                signIn()
            } else {
                banner = "Sign-in pattern saved."
            }
        }
    }

    private func openPattern(_ prompt: PatternPrompt, message: String?) {
        pattern.reset()
        patternFailed = false
        patternMessage = message
        patternPrompt = prompt
    }

    /// Shows the pattern in red for a moment, then clears it for another go.
    private func rejectPattern(_ message: String, restart: Bool = false) {
        patternFailed = true
        patternMessage = message
        patternShake += 1
        ConsoleFeel.shared.bump()
        ConsoleSound.shared.back()
        if restart { patternPrompt = .create }
        let shake = patternShake
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard self.patternShake == shake, self.patternFailed else { return }
            self.patternFailed = false
            self.pattern.reset()
        }
    }
}
