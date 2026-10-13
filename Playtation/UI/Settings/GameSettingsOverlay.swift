import AppKit
import SwiftUI

struct GameSettingsOverlay: View {
    @EnvironmentObject private var model: ConsoleModel
    var game: Game
    @State private var name: String = ""

    private enum Page: String, CaseIterable, Identifiable {
        case graphics, sync, metal, controller, library, players
        var id: String { rawValue }
        var title: String {
            switch self {
            case .graphics: return "Graphics"
            case .sync: return "Sync"
            case .metal: return "MetalFX"
            case .controller: return "Controller"
            case .library: return "Library"
            case .players: return "Players"
            }
        }
        var index: Int {
            switch self {
            case .graphics: return 0
            case .sync: return 1
            case .metal: return 2
            case .controller: return 3
            case .library: return 4
            case .players: return 5
            }
        }
    }

    private var record: GameRecord { model.records[game.id] ?? GameRecord() }

    private var page: Page {
        switch model.panelIndex {
        case 0: return .graphics
        case 1: return .sync
        case 2: return .metal
        case 3: return .controller
        case 4: return .library
        default: return .players
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.circle() } label: {
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

            HStack(alignment: .top, spacing: 0) {
                sidebar
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(page.title)
                            .font(PS.font(34, .medium))
                            .tracking(-0.8)
                        Text(pageBlurb)
                            .font(PS.font(14, .regular))
                            .foregroundStyle(.black.opacity(0.62))
                            .frame(maxWidth: 640, alignment: .leading)
                        pageContent
                    }
                    .padding(36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            ControlHints(items: model.gameInContent
                ? [("arrow.up.arrow.down", "Move"), ("xmark", "Select"), ("circle", "Back")]
                : [("arrow.up.arrow.down", "Section"), ("arrow.right", "Open"), ("circle", "Close")])
        }
        .background(PS.panel.ignoresSafeArea())
        .onAppear { name = model.displayName(for: game) }
        .onDisappear { commitName() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Game settings")
                .font(PS.font(28, .medium))
                .padding(.bottom, 16)
            ForEach(Page.allCases) { item in
                let selected = page == item
                let aimed = selected && !model.gameInContent
                Button {
                    model.panelIndex = item.index
                    model.gameRow = 0
                    model.gameInContent = false
                } label: {
                    Text(item.title)
                        .font(PS.font(16, selected ? .bold : .medium))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: Corner.row, style: .continuous)
                                .fill(aimed ? Color.white : (selected ? Color.black.opacity(0.05) : Color.clear))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Corner.row, style: .continuous)
                                        .stroke(Color.black.opacity(aimed ? 0.8 : 0), lineWidth: 1.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(game.bottleName)
                .font(PS.font(12, .medium))
                .foregroundStyle(.black.opacity(0.45))
                .padding(.horizontal, 12)
        }
        .padding(28)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var pageBlurb: String {
        switch page {
        case .graphics:
            return "Overrides apply only when Playtation launches \(model.displayName(for: game)). The bottle stays as it is for every other game."
        case .sync:
            return "Fast sync for this game. Bottle default follows whatever \(game.bottleName) is using."
        case .metal:
            return "MetalFX upscaling for the D3DMetal backend. Bottle default leaves the bottle setting alone."
        case .controller:
            return "XInput puts the controller on the XInput list. DirectInput leaves it on the DirectInput list."
        case .library:
            return "How this game shows up on Home. The install folder is the Windows directory CrossOver uses."
        case .players:
            if !model.signedInAsOwner {
                return "Only \(model.displayName(of: model.profiles[0])) can choose who sees this game."
            }
            return model.otherProfiles.isEmpty
                ? "Add users in Settings, under Users, to choose who sees \(model.displayName(for: game))."
                : "Who sees \(model.displayName(for: game)) on Home. You always see every game."
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .graphics:
            VStack(spacing: 10) {
                choice("Bottle default", "Use the bottle's graphics backend.", selected: record.graphics == nil, row: 0) {
                    model.focusGame(section: 0, row: 0)
                    model.updateRecord(game.id) { $0.graphics = nil }
                }
                ForEach(Array(GraphicsBackend.allCases.enumerated()), id: \.element.id) { index, backend in
                    choice(backend.title, backend.blurb, selected: record.graphics == backend.rawValue, row: index + 1) {
                        model.focusGame(section: 0, row: index + 1)
                        model.updateRecord(game.id) { $0.graphics = backend.rawValue }
                    }
                }
            }
        case .sync:
            VStack(spacing: 10) {
                choice("Bottle default", "Use the bottle's sync setting.", selected: record.sync == nil, row: 0) {
                    model.focusGame(section: 1, row: 0)
                    model.updateRecord(game.id) { $0.sync = nil }
                }
                choice("MSync", SyncMode.msync.blurb, selected: record.sync == "msync", row: 1) {
                    model.focusGame(section: 1, row: 1)
                    model.updateRecord(game.id) { $0.sync = "msync" }
                }
                choice("ESync", SyncMode.esync.blurb, selected: record.sync == "esync", row: 2) {
                    model.focusGame(section: 1, row: 2)
                    model.updateRecord(game.id) { $0.sync = "esync" }
                }
                choice("Off", SyncMode.off.blurb, selected: record.sync == "off", row: 3) {
                    model.focusGame(section: 1, row: 3)
                    model.updateRecord(game.id) { $0.sync = "off" }
                }
            }
        case .metal:
            VStack(spacing: 10) {
                choice("Bottle default", "Follow the bottle.", selected: record.metalFX == nil, row: 0) {
                    setMetal(nil, row: 0)
                }
                choice("On", "Turn MetalFX on for this game only.", selected: record.metalFX == true, row: 1) {
                    setMetal(true, row: 1)
                }
                choice("Off", "Turn MetalFX off for this game only.", selected: record.metalFX == false, row: 2) {
                    setMetal(false, row: 2)
                }
            }
        case .controller:
            VStack(spacing: 10) {
                choice("Bottle default", "Leave the controller panel as it is.", selected: record.controller == nil, row: 0) {
                    setController(nil, row: 0)
                }
                choice("DirectInput", "Shows under Connected (DirectInput devices).", selected: record.controller == "dinput", row: 1) {
                    setController("dinput", row: 1)
                }
                choice("XInput", "Shows under Connected (XInput devices).", selected: record.controller == "xinput", row: 2) {
                    setController("xinput", row: 2)
                }
            }
        case .library:
            library
        case .players:
            players
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DISPLAY NAME")
                    .font(PS.font(11, .bold))
                    .tracking(0.6)
                    .foregroundStyle(.black.opacity(0.45))
                TextField("Display name", text: $name)
                    .textFieldStyle(.plain)
                    .font(PS.font(15, .medium))
                    .onSubmit { commitName() }
            }
            .padding(14)
            .frame(maxWidth: 680, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Corner.row, style: .continuous).fill(Color.white.opacity(0.8)))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hide from Home").font(PS.font(15, .bold))
                    Text("It stays in Library, and you can turn it back on from here.")
                        .font(PS.font(13, .regular))
                        .foregroundStyle(.black.opacity(0.7))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { record.hidden },
                    set: { hidden in
                        model.focusGame(section: 4, row: 0)
                        model.updateRecord(game.id) { $0.hidden = hidden }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(14)
            .frame(maxWidth: 680)
            .background(rowPlate(focused: aiming(0)))
            .foregroundStyle(Color.black)

            HStack(spacing: 12) {
                capsule("Choose artwork", aiming(1)) {
                    model.focusGame(section: 4, row: 1)
                    model.chooseArtwork()
                }
                capsule("Use generated art", aiming(2)) {
                    model.focusGame(section: 4, row: 2)
                    model.updateRecord(game.id) { $0.artworkPath = nil }
                }
            }
            if let directory = game.installDirectory {
                capsule("Show install folder", aiming(3)) {
                    model.focusGame(section: 4, row: 3)
                    model.open(directory)
                }
            }
        }
    }

    @ViewBuilder
    private var players: some View {
        let others = model.otherProfiles
        let users = record.users
        VStack(spacing: 10) {
            choice("Everyone", "Every user sees this game.", selected: users == nil, row: 0) {
                model.focusGame(section: 5, row: 0)
                model.toggleAccess(game, row: 0)
            }
            if model.signedInAsOwner {
                ForEach(Array(others.enumerated()), id: \.element.id) { index, profile in
                    let allowed = users.map { $0.contains(profile.id) } ?? true
                    Button {
                        model.focusGame(section: 5, row: index + 1)
                        model.toggleAccess(game, row: index + 1)
                    } label: {
                        HStack(spacing: 12) {
                            ProfileMark(image: nil, name: model.displayName(of: profile), side: 32, color: profile.tint)
                            Text(model.displayName(of: profile)).font(PS.font(15, .bold))
                            Spacer()
                            Image(systemName: allowed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.black.opacity(allowed ? 0.85 : 0.35))
                        }
                        .padding(14)
                        .frame(maxWidth: 680, alignment: .leading)
                        .background(rowPlate(focused: aiming(index + 1)))
                        .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func aiming(_ row: Int) -> Bool {
        model.gameInContent && model.gameRow == row
    }

    private func setMetal(_ value: Bool?, row: Int) {
        model.focusGame(section: 2, row: row)
        model.updateRecord(game.id) { $0.metalFX = value }
    }

    private func setController(_ value: String?, row: Int) {
        model.focusGame(section: 3, row: row)
        model.updateRecord(game.id) { $0.controller = value }
    }

    private func choice(_ title: String, _ detail: String, selected: Bool, row: Int, action: @escaping () -> Void) -> some View {
        let focused = aiming(row)
        return Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .stroke(Color.black.opacity(0.4), lineWidth: 1.5)
                    .background(Circle().fill(selected ? Color.black : Color.clear).padding(4))
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(PS.font(15, .bold))
                    Text(detail)
                        .font(PS.font(13, .regular))
                        .foregroundStyle(.black.opacity(0.62))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: 680, alignment: .leading)
            .background(rowPlate(focused: focused))
            .foregroundStyle(Color.black)
        }
        .buttonStyle(.plain)
    }

    private func rowPlate(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: Corner.row, style: .continuous)
            .fill(Color.white.opacity(focused ? 1 : 0.62))
            .overlay(
                RoundedRectangle(cornerRadius: Corner.row, style: .continuous)
                    .stroke(Color.black.opacity(focused ? 0.82 : 0), lineWidth: 1.5)
            )
    }

    private func capsule(_ title: String, _ focused: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(PS.font(14, .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(focused ? 1 : 0.8))
                        .overlay(Capsule().stroke(Color.black.opacity(focused ? 0.82 : 0), lineWidth: 1.5))
                )
        }
        .buttonStyle(.plain)
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.updateRecord(game.id) {
            $0.displayName = trimmed.isEmpty || trimmed == game.name ? nil : trimmed
        }
    }


}
