import AppKit
import Combine
import SwiftUI

struct ShellView: View {
    @EnvironmentObject private var model: ConsoleModel
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if model.phase == .shell {
                console
                    .transition(.opacity)
            }
            if model.phase == .welcome {
                WelcomeView()
                    .id("welcome")
                    .zIndex(1)
            }
            if model.phase == .boot {
                BootView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .background(Color.black)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onChange(of: model.phase) { _, _ in
            focused = true
        }
        .onChange(of: model.showSettings) { _, open in
            if !open { focused = true }
        }
        .onKeyPress(phases: [.down, .repeat]) { press in
            handle(press)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
            if model.phase == .shell { ConsoleSound.shared.startMusic() }
        }
    }

    private var settingsScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.circle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("Home")
                    }
                    .font(PS.font(14, .medium))
                    .foregroundStyle(.black.opacity(0.72))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 36)
            .padding(.top, 16)
            SettingsView()
            ControlHints(items: model.settingsInContent
                ? [("arrow.up.arrow.down", "Move"), ("arrow.left.arrow.right", "Adjust"), ("xmark", "Select"), ("circle", "Back")]
                : [("arrow.up.arrow.down", "Section"), ("arrow.right", "Open"), ("l1.rectangle.roundedbottom", "Previous"), ("r1.rectangle.roundedbottom", "Next"), ("circle", "Home")])
        }
        .background(PS.panel.ignoresSafeArea())
    }

    private var console: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                switch model.tab {
                case .home, .library:
                    DashboardView()
                case .settings:
                    settingsScreen
                }
                if let id = model.userMenuID, let profile = model.profiles.first(where: { $0.id == id }) {
                    UserMenuOverlay(profile: profile)
                        .zIndex(6)
                        .transition(.opacity)
                }
                if model.searching {
                    SearchKeyboard()
                        .zIndex(7)
                        .transition(.opacity)
                }
                if model.showPower {
                    PowerMenu()
                        .zIndex(8)
                        .transition(.opacity)
                }
                if model.showSettings, let game = model.currentGame {
                    GameSettingsOverlay(game: game)
                        .transition(.opacity)
                }
                if model.showDetails, let game = model.currentGame {
                    GameDetailsOverlay(game: game)
                        .transition(.opacity)
                }
                if model.showAdd {
                    AddGameOverlay()
                        .zIndex(9)
                }
                if model.patternPrompt != nil, model.patternPrompt != .unlock {
                    PatternSetupOverlay()
                        .zIndex(10)
                        .transition(.opacity)
                }
                if let banner = model.banner {
                    VStack {
                        Spacer()
                        Text(banner)
                            .font(PS.font(13, .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.black.opacity(0.78)))
                            .padding(.bottom, 28)
                    }
                    .transition(.opacity)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_200_000_000)
                            if model.banner == banner { model.banner = nil }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if model.phase == .boot {
            return .handled
        }
        if model.phase == .welcome {
            switch press.key {
            case .return:
                model.confirmWelcome()
            case .escape:
                model.circle()
            case .leftArrow:
                model.moveWelcome(-1)
            case .rightArrow:
                model.moveWelcome(1)
            case .upArrow, .downArrow:
                model.hoverWelcome()
            default:
                break
            }
            return .handled
        }
        if model.patternPrompt != nil {
            switch press.key {
            case .return:
                model.cross()
            case .escape:
                model.circle()
            default:
                break
            }
            return .handled
        }
        if model.showAdd {
            switch press.key {
            case .leftArrow, .rightArrow, .upArrow, .downArrow, .return, .escape:
                if model.addEditing, press.key != .return, press.key != .escape { return .ignored }
                if model.addEditing, press.key == .return { model.addEditing = false; return .handled }
            default:
                return .ignored
            }
        }
        if model.showSettings {
            switch press.key {
            case .leftArrow, .rightArrow, .upArrow, .downArrow, .return, .escape:
                break
            default:
                return .ignored
            }
        }
        if model.searching {
            switch press.key {
            case .escape, .leftArrow, .rightArrow, .upArrow, .downArrow:
                break
            case .return:
                model.finishSearch()
                return .handled
            case .delete, .deleteForward:
                model.kbBackspace()
                return .handled
            default:
                let text = press.characters
                if !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) {
                    model.kbType(text)
                    return .handled
                }
                return .ignored
            }
        }
        switch press.key {
        case .leftArrow:
            model.moveHorizontal(-1)
            return .handled
        case .rightArrow:
            model.moveHorizontal(1)
            return .handled
        case .upArrow:
            model.moveVertical(-1)
            return .handled
        case .downArrow:
            model.moveVertical(1)
            return .handled
        case .return:
            model.cross()
            return .handled
        case .escape:
            model.circle()
            return .handled
        default:
            break
        }
        if model.tab == .settings { return .ignored }
        switch press.characters.lowercased() {
        case "t":
            model.triangle()
        case "i":
            model.square()
        case "p":
            model.psButton()
        case "[", ",":
            model.switchTab(-1)
        case "]", ".":
            model.switchTab(1)
        case "1":
            model.tab = .home
        case "2":
            model.tab = .library
        case "3":
            model.tab = .settings
        default:
            return .ignored
        }
        return .handled
    }
}
