import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

/// D-pad, buttons and pointer: moving focus around Home and acting on it.
extension ConsoleModel {
    func select(_ index: Int) {
        let count = games.count
        guard count > 0 else { return }
        let next = min(max(0, index), count - 1)
        guard next != selected else { return }
        selected = next
    }

    func move(_ delta: Int) {
        moveHorizontal(delta)
    }

    func moveHorizontal(_ delta: Int) {
        pointerAtPad = NSEvent.mouseLocation
        guard shellOwnsPad() else { return }
        if phase == .welcome {
            hoverWelcome()
            return
        }
        if searching {
            kbMove(horizontal: delta, vertical: 0)
            return
        }
        if steerPanel(horizontal: delta) { return }
        guard canSteer else { return }
        switch zone {
        case .top:
            let next = min(2, max(0, topIndex + delta))
            guard next != topIndex else {
                ConsoleFeel.shared.bump()
                return
            }
            ConsoleSound.shared.tick(horizontal: delta)
            topIndex = next
        case .tiles:
            let next = selected + delta
            guard games.indices.contains(next) else {
                ConsoleFeel.shared.bump()
                return
            }
            ConsoleSound.shared.tick(horizontal: delta)
            select(next)
        case .hero:
            let next = min(currentGame?.hasOptions == true ? 1 : 0, max(0, heroIndex + delta))
            guard next != heroIndex else {
                ConsoleFeel.shared.bump()
                return
            }
            ConsoleSound.shared.tick(horizontal: delta)
            heroIndex = next
        }
    }

    func moveVertical(_ delta: Int) {
        pointerAtPad = NSEvent.mouseLocation
        guard shellOwnsPad() else { return }
        if phase == .welcome {
            hoverWelcome()
            return
        }
        if searching {
            kbMove(horizontal: 0, vertical: delta)
            return
        }
        if steerPanel(horizontal: nil, vertical: delta) { return }
        guard canSteer else { return }
        if zone == .tiles, let start = games.firstIndex(where: { $0.webURL != nil }), selected >= start {
            let target = selected + delta * Self.appColumns
            if target >= start && target < games.count {
                ConsoleSound.shared.tick(vertical: delta)
                select(target)
                return
            }
        }
        let next: DashZone
        switch zone {
        case .top: next = delta > 0 ? .hero : .top
        case .hero: next = delta > 0 ? .tiles : .top
        case .tiles: next = delta < 0 ? .hero : .tiles
        }
        guard next != zone else {
            ConsoleFeel.shared.bump()
            return
        }
        ConsoleSound.shared.tick(vertical: delta)
        zone = next
        if next == .hero, currentGame?.hasOptions != true { heroIndex = 0 }
    }

    func switchTab(_ delta: Int) {
        moveHorizontal(delta)
    }

    func cross() {
        guard shellOwnsPad() else { return }
        if phase == .boot { return }
        if phase == .welcome {
            confirmWelcome()
            return
        }
        if searching {
            kbPress()
            return
        }
        if showAdd {
            confirmAdd()
            return
        }
        if showMore {
            confirmMore()
            return
        }
        if showDetails {
            if panelIndex == 0 { startSelected() } else { circle() }
            return
        }
        if showPower {
            confirmPower()
            return
        }
        if showSettings {
            confirmGamePanel()
            return
        }
        if tab == .settings {
            confirmSettings()
            return
        }
        guard tab == .home else { return }
        switch zone {
        case .top:
            activateTop(topIndex)
        case .tiles:
            activateTile(selected)
        case .hero:
            activateHero(heroIndex)
        }
    }

    func circle() {
        guard shellOwnsPad() else { return }
        if phase == .boot { return }
        if phase == .welcome {
            returnToBoot()
            return
        }
        if showAdd {
            if addEditing {
                addEditing = false
                return
            }
            closeAdd()
            return
        }
        if showMore {
            confirmRemove = false
            withAnimation(.easeOut(duration: 0.2)) { showMore = false }
            ConsoleSound.shared.back()
            return
        }
        if showPower {
            withAnimation(.easeInOut(duration: 0.4)) { showPower = false }
            ConsoleSound.shared.back()
            return
        }
        if searching {
            withAnimation(.easeOut(duration: 0.2)) {
                searching = false
                query = ""
            }
            ConsoleSound.shared.back()
            return
        }
        if tab == .settings, !showSettings, settingsInContent {
            withAnimation(.easeOut(duration: 0.15)) { settingsInContent = false }
            ConsoleSound.shared.back()
            return
        }
        if showSettings, gameInContent {
            withAnimation(.easeOut(duration: 0.15)) { gameInContent = false }
            ConsoleSound.shared.back()
            return
        }
        if !query.isEmpty, !showSettings, !showDetails, tab == .home {
            withAnimation(.easeOut(duration: 0.2)) { query = "" }
            ConsoleSound.shared.back()
            return
        }
        if showSettings || showDetails || showPower || tab != .home {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSettings = false
                showDetails = false
                showPower = false
                tab = .home
                zone = .tiles
            }
            ConsoleSound.shared.back()
        }
    }

    /// Hover that only counts when the pointer itself moved since the last pad input.
    func hoverTile(_ index: Int) {
        let now = NSEvent.mouseLocation
        guard hypot(now.x - pointerAtPad.x, now.y - pointerAtPad.y) > 3 else { return }
        pointerAtPad = now
        focusTile(index)
    }

    func focusTile(_ index: Int) {
        guard launchingID == nil, Date() >= hoverLockUntil else { return }
        guard canSteer, games.indices.contains(index), index != selected else { return }
        ConsoleSound.shared.tick()
        zone = .tiles
        select(index)
    }

    func activateTile(_ index: Int) {
        guard games.indices.contains(index), currentGame != nil || games.indices.contains(index) else { return }
        if index != selected {
            ConsoleSound.shared.tick()
            select(index)
            zone = .tiles
            return
        }
        ConsoleSound.shared.confirm()
        startSelected()
    }

    func activateTop(_ index: Int) {
        topIndex = index
        zone = .top
        ConsoleSound.shared.confirm()
        switch index {
        case 0:
            withAnimation(.easeOut(duration: 0.2)) { searching.toggle() }
            if searching {
                kbMode = .letters
                kbShift = false
                kbRow = 2
                kbCol = 5
            }
        case 1:
            withAnimation(.easeInOut(duration: 0.25)) {
                tab = .settings
                showPower = false
                showDetails = false
                showSettings = false
                showMore = false
                settingsInContent = false
                settingsRow = 0
            }
        default:
            psButton()
        }
    }

    func activateHero(_ index: Int) {
        heroIndex = index
        zone = .hero
        ConsoleSound.shared.confirm()
        if index == 0 {
            startSelected()
        } else {
            panelIndex = 0
            withAnimation(.easeOut(duration: 0.2)) {
                showMore = true
                showDetails = false
                showSettings = false
                showPower = false
            }
        }
    }

    func confirmMore() {
        ConsoleSound.shared.confirm()
        if panelIndex == 2 {
            removeSelected()
            return
        }
        showMore = false
        if panelIndex == 0 {
            openDetails()
        } else {
            openGameSettings()
        }
    }

    /// L1 toggles shift, R1 finishes. Outside search they step through tiles as before.
    func setCategory(_ next: HomeCategory) {
        guard next != category else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            category = next
            selected = 0
        }
    }

    func cycleCategory(_ delta: Int) {
        let all = HomeCategory.allCases
        let index = all.firstIndex(of: category) ?? 0
        let next = index + delta
        guard all.indices.contains(next) else {
            ConsoleFeel.shared.bump()
            return
        }
        ConsoleSound.shared.tick(horizontal: delta)
        setCategory(all[next])
    }

    func shoulder(_ delta: Int) {
        if !searching, shellOwnsPad(), phase == .shell, tab == .home, canSteer {
            cycleCategory(delta)
            return
        }
        if !searching, shellOwnsPad(), phase == .shell {
            if showSettings {
                let next = min(4, max(0, panelIndex + delta))
                if next != panelIndex {
                    ConsoleSound.shared.tick(horizontal: delta)
                    panelIndex = next
                    gameRow = 0
                    gameInContent = false
                } else {
                    ConsoleFeel.shared.bump()
                }
                return
            }
            if tab == .settings {
                let next = min(2, max(0, settingsSection + delta))
                if next != settingsSection {
                    ConsoleSound.shared.tick(horizontal: delta)
                    settingsSection = next
                    settingsRow = 0
                    settingsInContent = false
                } else {
                    ConsoleFeel.shared.bump()
                }
                return
            }
        }
        guard searching, shellOwnsPad() else {
            moveHorizontal(delta)
            return
        }
        if delta < 0 { kbActivate(.shift) } else { finishSearch() }
    }

    func finishSearch() {
        ConsoleSound.shared.confirm()
        withAnimation(.easeOut(duration: 0.2)) { searching = false }
        selected = 0
        zone = .tiles
    }

    func triangle() {
        guard shellOwnsPad() else { return }
        if searching {
            kbType(" ")
            return
        }
        guard phase == .shell, currentGame != nil else { return }
        ConsoleSound.shared.confirm()
        panelIndex = 0
        gameRow = 0
        gameInContent = false
        withAnimation(.easeInOut(duration: 0.2)) {
            showDetails = false
            showPower = false
            showMore = false
            showSettings = true
            tab = .home
        }
    }

    func square() {
        guard shellOwnsPad() else { return }
        if searching {
            kbBackspace()
            return
        }
        guard phase == .shell, currentGame != nil else { return }
        ConsoleSound.shared.confirm()
        panelIndex = 0
        withAnimation(.easeInOut(duration: 0.2)) {
            showSettings = false
            showPower = false
            showMore = false
            showDetails = true
            tab = .home
        }
    }

    func psButton() {
        guard shellOwnsPad() else { return }
        if phase == .boot { return }
        if phase == .welcome {
            confirmWelcome()
            return
        }
        if showPower {
            withAnimation(.easeInOut(duration: 0.4)) { showPower = false }
            ConsoleSound.shared.back()
            return
        }
        panelIndex = 0
        ConsoleSound.shared.menu()
        withAnimation(.easeInOut(duration: 0.4)) {
            showMore = false
            showSettings = false
            showDetails = false
            showPower = true
        }
    }

    func confirmPower() {
        switch panelIndex {
        case 0:
            withAnimation(.easeInOut(duration: 0.4)) {
                showPower = false
                tab = .home
                zone = .tiles
            }
            ConsoleSound.shared.back()
        case 1:
            withAnimation(.easeInOut(duration: 0.4)) {
                showPower = false
                showSettings = false
                showDetails = false
                showMore = false
                tab = .settings
            }
            ConsoleSound.shared.restoreMusic()
            ConsoleSound.shared.tick()
        case 2:
            rest()
        default:
            quit()
        }
    }

    /// PlayStation button went down or up. A short press opens the app. Holding it returns to Home.
    func controllerPS(pressed: Bool) {
        if phase == .boot {
            if pressed { signalBoot() }
            return
        }
        if pressed {
            guard !psDown else { return }
            psDown = true
            psHoldFired = false
            psHoldTask?.cancel()
            psHoldTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled, self.psDown else { return }
                self.psHoldFired = true
                self.psHeld()
            }
        } else {
            guard psDown else { return }
            psDown = false
            psHoldTask?.cancel()
            psHoldTask = nil
            if !psHoldFired { psClicked() }
        }
    }

    func psClicked() {
        shellTookThePad()
        let front = NSApp.isActive && NSApp.windows.contains { $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized }
        if !front {
            PlaytationLaunch.reveal()
            if phase == .boot { signalBoot() }
            return
        }
        if phase == .boot {
            signalBoot()
            return
        }
        if phase == .welcome {
            confirmWelcome()
            return
        }
        psButton()
    }

    func psHeld() {
        if phase == .boot { return }
        if phase == .welcome, runningGameID == nil {
            PlaytationLaunch.reveal()
            return
        }
        openHome()
    }

    /// Home, with the running game selected so it can be closed or replaced.
    func openHome() {
        shellTookThePad()
        PlaytationLaunch.reveal()
        signingIn = false
        if phase != .shell {
            phase = .shell
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            tab = .home
            showSettings = false
            showDetails = false
            showPower = false
            showMore = false
            searching = false
            zone = .hero
            heroIndex = 0
        }
        if let runningGameID, let index = games.firstIndex(where: { $0.id == runningGameID }) {
            selected = index
        }
        ConsoleSound.shared.confirm()
        ConsoleFeel.shared.armIfNeeded()
    }
}
