import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

/// Details, game settings and Settings page: stepping through rows and applying choices.
extension ConsoleModel {
    func toggleFullScreen() {
        PlaytationWindow.toggle()
        startFullScreen = PlaytationWindow.prefersFullScreen
        fullScreen = PlaytationWindow.isFullScreen
    }

    func setGameResolution(_ id: String) {
        gameResolution = id
        DisplayFit.setting = id
    }

    /// Steps through the resolution presets. Returns false when there is nowhere further to go.
    @discardableResult
    func cycleGameResolution(_ delta: Int) -> Bool {
        let options = DisplayFit.options()
        let current = options.firstIndex { $0.id == gameResolution } ?? 0
        let next = current + delta
        guard options.indices.contains(next) else { return false }
        ConsoleSound.shared.tick(horizontal: delta)
        setGameResolution(options[next].id)
        return true
    }

    func setStartFullScreen(_ on: Bool) {
        startFullScreen = on
        fullScreen = on
        PlaytationWindow.setFullScreen(on)
    }

    func clampSelection() {
        if games.isEmpty {
            selected = 0
        } else if !games.indices.contains(selected) {
            selected = 0
        }
    }

    var canSteer: Bool {
        phase == .shell && tab == .home && !showSettings && !showDetails && !showPower && !showMore && !showProfile && !searching && !showAdd
    }

    /// Moves inside an open panel or the settings page. Returns true when that surface handled the stick.
    func steerPanel(horizontal: Int? = nil, vertical: Int? = nil) -> Bool {
        guard phase == .shell else { return false }
        if showAdd {
            steerAdd(horizontal: horizontal ?? 0, vertical: vertical ?? 0)
            return true
        }
        if showMore {
            if let vertical { stepPanel(vertical, count: 3); confirmRemove = false }
            return true
        }
        if showProfile {
            if let vertical { stepPanel(vertical, count: profileActions.count) }
            return true
        }
        if showDetails {
            if let vertical { stepPanel(vertical, count: 2) }
            return true
        }
        if showPower {
            if let vertical { stepPanel(vertical, count: 4) }
            return true
        }
        if showSettings {
            steerGameSettings(horizontal: horizontal, vertical: vertical)
            return true
        }
        if tab == .settings {
            steerSettings(horizontal: horizontal, vertical: vertical)
            return true
        }
        return false
    }

    func stepPanel(_ delta: Int, count: Int) {
        let next = min(count - 1, max(0, panelIndex + delta))
        guard next != panelIndex else {
            ConsoleFeel.shared.bump()
            return
        }
        ConsoleSound.shared.tick(vertical: delta)
        panelIndex = next
    }

    var gameRowCount: Int {
        switch panelIndex {
        case 0, 1: return 4
        case 2, 3: return 3
        default: return currentGame?.installDirectory == nil ? 3 : 4
        }
    }

    func steerGameSettings(horizontal: Int?, vertical: Int?) {
        if let vertical {
            if gameInContent {
                let next = gameRow + vertical
                if (0..<gameRowCount).contains(next) {
                    ConsoleSound.shared.tick(vertical: vertical)
                    gameRow = next
                } else if vertical > 0, panelIndex < 4 {
                    ConsoleSound.shared.tick(vertical: vertical)
                    panelIndex += 1
                    gameRow = 0
                } else if vertical < 0, panelIndex > 0 {
                    ConsoleSound.shared.tick(vertical: vertical)
                    panelIndex -= 1
                    gameRow = max(0, gameRowCount - 1)
                } else {
                    ConsoleFeel.shared.bump()
                }
            } else {
                let next = min(4, max(0, panelIndex + vertical))
                guard next != panelIndex else {
                    ConsoleFeel.shared.bump()
                    return
                }
                ConsoleSound.shared.tick(vertical: vertical)
                panelIndex = next
                gameRow = 0
            }
        }
        if let horizontal {
            if !gameInContent, horizontal > 0 {
                ConsoleSound.shared.tick(horizontal: horizontal)
                gameInContent = true
                gameRow = 0
                return
            }
            if gameInContent, horizontal < 0 {
                ConsoleSound.shared.tick(horizontal: horizontal)
                gameInContent = false
            } else if horizontal != 0 {
                ConsoleFeel.shared.bump()
            }
        }
    }

    func focusGame(section: Int, row: Int) {
        panelIndex = section
        gameRow = row
        gameInContent = true
    }

    func confirmGamePanel() {
        guard let game = currentGame else { return }
        if !gameInContent {
            ConsoleSound.shared.tick()
            gameInContent = true
            gameRow = 0
            return
        }
        ConsoleSound.shared.confirm()
        switch panelIndex {
        case 0:
            let graphics: [String?] = [nil, "d3dmetal", "dxmt", "dxvk"]
            let value = graphics[min(gameRow, graphics.count - 1)]
            updateRecord(game.id) { $0.graphics = value }
        case 1:
            let sync: [String?] = [nil, "msync", "esync", "off"]
            let value = sync[min(gameRow, sync.count - 1)]
            updateRecord(game.id) { $0.sync = value }
        case 2:
            let metal: [Bool?] = [nil, true, false]
            updateRecord(game.id) { $0.metalFX = metal[min(gameRow, metal.count - 1)] }
        case 3:
            let modes: [String?] = [nil, "dinput", "xinput"]
            updateRecord(game.id) { $0.controller = modes[min(gameRow, modes.count - 1)] }
        default:
            switch gameRow {
            case 0:
                updateRecord(game.id) { $0.hidden.toggle() }
            case 1:
                chooseArtwork()
            case 2:
                updateRecord(game.id) { $0.artworkPath = nil }
            default:
                if let directory = game.installDirectory { open(directory) }
            }
        }
    }

    func chooseArtwork() {
        guard let game = currentGame else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importArtwork(for: game, from: url)
    }

    func steerSettings(horizontal: Int?, vertical: Int?) {
        if let vertical {
            if settingsInContent {
                // Rescan (2) and Open CrossOver (3) sit side by side, so they are one row vertically.
                var next = min(settingsRowCount - 1, max(0, settingsRow + vertical))
                if settingsSection == 2 {
                    if settingsRow == 3, vertical < 0 { next = 1 }
                    if settingsRow == 2 || settingsRow == 3, vertical > 0 { next = 4 }
                    if settingsRow == 4, vertical < 0 { next = 2 }
                }
                guard next != settingsRow else {
                    ConsoleFeel.shared.bump()
                    return
                }
                ConsoleSound.shared.tick(vertical: vertical)
                settingsRow = next
            } else {
                let next = min(2, max(0, settingsSection + vertical))
                guard next != settingsSection else {
                    ConsoleFeel.shared.bump()
                    return
                }
                ConsoleSound.shared.tick(vertical: vertical)
                settingsSection = next
                settingsRow = 0
            }
        }
        if let horizontal {
            if !settingsInContent, horizontal > 0 {
                ConsoleSound.shared.tick(horizontal: horizontal)
                settingsInContent = true
                settingsRow = 0
                return
            }
            if settingsInContent, settingsSection == 0, settingsRow == 0 {
                cycleSettingsBottle(horizontal)
                return
            }
            if settingsInContent, settingsSection == 2, settingsRow == 2, horizontal > 0 {
                ConsoleSound.shared.tick(horizontal: horizontal)
                settingsRow = 3
                return
            }
            if settingsInContent, settingsSection == 2, settingsRow == 3 {
                if horizontal < 0 {
                    ConsoleSound.shared.tick(horizontal: horizontal)
                    settingsRow = 2
                } else if horizontal > 0 {
                    ConsoleFeel.shared.bump()
                }
                return
            }
            if settingsInContent, settingsSection == 2, settingsRow == 1, horizontal != 0 {
                if cycleGameResolution(horizontal) { return }
                if horizontal > 0 {
                    ConsoleFeel.shared.bump()
                    return
                }
            }
            if settingsInContent, horizontal < 0 {
                ConsoleSound.shared.tick(horizontal: horizontal)
                settingsInContent = false
            } else if horizontal != 0 {
                ConsoleFeel.shared.bump()
            }
        }
    }

    var settingsRowCount: Int {
        switch settingsSection {
        case 0: return modelBottlesEmpty ? 1 : 9
        case 1: return max(bottles.count, 1)
        default: return hasPattern ? 6 : 5
        }
    }

    var modelBottlesEmpty: Bool { bottles.isEmpty }

    func cycleSettingsBottle(_ delta: Int) {
        guard !bottles.isEmpty else { return }
        let fallback = bottles.firstIndex { $0.id == (currentGame?.bottleID ?? bottles[0].id) } ?? 0
        let index = bottles.firstIndex { $0.id == settingsBottleID } ?? fallback
        let next = min(bottles.count - 1, max(0, index + delta))
        guard next != index else {
            if delta < 0 {
                settingsInContent = false
            } else {
                ConsoleFeel.shared.bump()
            }
            return
        }
        ConsoleSound.shared.tick(horizontal: delta)
        settingsBottleID = bottles[next].id
    }

    func confirmSettings() {
        if settingsSection == 2, settingsRow >= 4 {
            if settingsRow == 4 { beginPatternSetup() } else { removePattern() }
            return
        }
        guard let bottle = settingsBottle else { return }
        ConsoleSound.shared.confirm()
        switch settingsSection {
        case 0:
            switch settingsRow {
            case 1...3:
                let backend = GraphicsBackend.allCases[settingsRow - 1]
                updateBottle(bottle, backend: backend)
            case 4...6:
                let mode = SyncMode.allCases[settingsRow - 4]
                updateBottle(bottle, sync: mode)
            case 7:
                updateBottle(bottle, metalFX: !bottle.metalFX)
            case 8:
                updateBottle(bottle, nvExtensions: !bottle.nvExtensions)
            default:
                break
            }
        case 1:
            guard bottles.indices.contains(settingsRow) else { return }
            open(bottles[settingsRow].path)
        default:
            if settingsRow == 0 {
                setStartFullScreen(!startFullScreen)
            } else if settingsRow == 1 {
                if !cycleGameResolution(1) { setGameResolution(DisplayFit.options().first?.id ?? "") }
            } else if settingsRow == 2 {
                refresh()
            } else {
                openCrossOver()
            }
        }
    }

    var settingsBottle: Bottle? {
        bottles.first { $0.id == settingsBottleID } ?? bottles.first
    }

    func openDetails() {
        guard currentGame != nil else { return }
        panelIndex = 0
        withAnimation(.easeInOut(duration: 0.2)) {
            showSettings = false
            showPower = false
            showMore = false
            showProfile = false
            showDetails = true
        }
    }

    func openGameSettings() {
        guard currentGame != nil else { return }
        panelIndex = 0
        gameRow = 0
        gameInContent = false
        withAnimation(.easeInOut(duration: 0.2)) {
            showDetails = false
            showPower = false
            showMore = false
            showProfile = false
            showSettings = true
        }
    }
}
