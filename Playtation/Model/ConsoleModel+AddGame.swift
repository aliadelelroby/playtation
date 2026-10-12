import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

/// The Add Game flow and removing games.
extension ConsoleModel {
    // MARK: Add and remove games

    static let addRowCount = 6

    func openAdd() {
        addBottleID = settingsBottleID.isEmpty ? (bottles.first?.id ?? "") : settingsBottleID
        if !bottles.contains(where: { $0.id == addBottleID }) { addBottleID = bottles.first?.id ?? "" }
        addCommand = ""
        addName = ""
        addEnvironment = ""
        addRow = 0
        addEditing = false
        ConsoleSound.shared.confirm()
        withAnimation(.easeInOut(duration: 0.2)) { showAdd = true }
    }

    func closeAdd() {
        addEditing = false
        withAnimation(.easeInOut(duration: 0.2)) { showAdd = false }
        ConsoleSound.shared.back()
    }

    var addBottle: Bottle? { bottles.first { $0.id == addBottleID } ?? bottles.first }

    var addReady: Bool { !addCommand.isEmpty && addBottle != nil }

    func steerAdd(horizontal: Int, vertical: Int) {
        if addEditing { return }
        if vertical != 0 {
            let next = min(Self.addRowCount - 1, max(0, addRow + vertical))
            guard next != addRow else {
                ConsoleFeel.shared.bump()
                return
            }
            ConsoleSound.shared.tick(vertical: vertical)
            addRow = next
            return
        }
        switch addRow {
        case 0:
            guard !bottles.isEmpty else { return }
            let index = bottles.firstIndex { $0.id == addBottleID } ?? 0
            let next = min(bottles.count - 1, max(0, index + horizontal))
            if next != index {
                ConsoleSound.shared.tick(horizontal: horizontal)
                addBottleID = bottles[next].id
            } else {
                ConsoleFeel.shared.bump()
            }
        case 4, 5:
            // Run and Save sit side by side.
            let next = min(5, max(4, addRow + horizontal))
            if next != addRow {
                ConsoleSound.shared.tick(horizontal: horizontal)
                addRow = next
            }
        default:
            ConsoleFeel.shared.bump()
        }
    }

    func confirmAdd() {
        switch addRow {
        case 0:
            ConsoleSound.shared.tick()
        case 1:
            chooseCommand()
        case 2, 3:
            ConsoleSound.shared.tick()
            addEditing = true
        case 4:
            runAddedCommand()
        default:
            saveAddedLauncher()
        }
    }

    func chooseCommand() {
        let panel = NSOpenPanel()
        panel.title = "Choose a program or installer"
        panel.message = "Pick the .exe, .msi or .bat to run in the bottle."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = []
        if let bottle = addBottle {
            panel.directoryURL = URL(fileURLWithPath: bottle.path + "/drive_c")
        }
        // The shell is full screen; step aside so the panel isn't hidden behind it.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addCommand = url.path
        if addName.isEmpty {
            addName = TitleMatcher.clean(url.deletingPathExtension().lastPathComponent)
        }
    }

    func runAddedCommand() {
        guard addReady, let bottle = addBottle, let wine = LibraryScanner.wineBinary() else {
            ConsoleFeel.shared.error()
            banner = "Choose a bottle and a program first."
            return
        }
        let command = addCommand
        let env = addEnvironment.trimmingCharacters(in: .whitespaces)
        closeAddQuietly()
        banner = "Running \((command as NSString).lastPathComponent)"
        ConsoleSound.shared.confirm()
        Task { @MainActor in
            await PlaytationWindow.yieldToGame()
            do {
                let process = try GameLauncher.runCommand(wine: wine, bottle: bottle.name, command: command, environment: env)
                process.terminationHandler = { _ in
                    Task { @MainActor in
                        PlaytationLaunch.reveal()
                        self.banner = "Finished. Rescanning your library."
                        self.refresh()
                    }
                }
            } catch {
                PlaytationLaunch.reveal()
                self.banner = "Couldn't run that command."
            }
        }
    }

    func closeAddQuietly() {
        addEditing = false
        withAnimation(.easeInOut(duration: 0.2)) { showAdd = false }
    }

    func saveAddedLauncher() {
        guard addReady, let bottle = addBottle else {
            ConsoleFeel.shared.error()
            banner = "Choose a bottle and a program first."
            return
        }
        let name = addName.trimmingCharacters(in: .whitespaces)
        let launcher = CustomLauncher(
            id: UUID().uuidString,
            name: name.isEmpty ? TitleMatcher.clean((addCommand as NSString).lastPathComponent) : name,
            bottleID: bottle.id,
            command: addCommand,
            environment: addEnvironment.trimmingCharacters(in: .whitespaces),
            created: Date()
        )
        launchers.append(launcher)
        CustomLauncherStore.save(launchers)
        closeAddQuietly()
        ConsoleSound.shared.confirm()
        banner = "Saved \(launcher.name) as a launcher."
        refresh()
    }

    /// Custom launchers are deleted. Everything else is hidden from Home. No game files are touched.
    func removeSelected() {
        guard let game = currentGame, game.hasOptions else { return }
        guard confirmRemove else {
            confirmRemove = true
            ConsoleSound.shared.tick()
            return
        }
        confirmRemove = false
        showMore = false
        showProfile = false
        if game.isCustom {
            launchers.removeAll { CustomLauncherStore.idPrefix + $0.id == game.id }
            CustomLauncherStore.save(launchers)
            banner = "Removed \(displayName(for: game))."
            refresh()
        } else {
            updateRecord(game.id) { $0.hidden = true }
            banner = "Removed \(displayName(for: game)) from Home. Its files are untouched."
        }
        ConsoleSound.shared.back()
        clampSelection()
    }
}
