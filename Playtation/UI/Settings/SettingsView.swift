import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: ConsoleModel

    enum Section: String, CaseIterable, Identifiable {
        case graphics, storage, system
        var id: String { rawValue }
        var title: String {
            switch self {
            case .graphics: return "Graphics"
            case .storage: return "Storage"
            case .system: return "System"
            }
        }
    }

    private var section: Section { Section.allCases[min(model.settingsSection, Section.allCases.count - 1)] }

    private var bottle: Bottle? { model.settingsBottle }

    private var contentFocused: Bool { model.settingsInContent }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(PS.font(28, .medium))
                    .padding(.bottom, 16)
                ForEach(Array(Section.allCases.enumerated()), id: \.element.id) { index, item in
                    let selected = section == item
                    let aimed = selected && !contentFocused
                    Button {
                        model.settingsSection = index
                        model.settingsInContent = false
                        model.settingsRow = 0
                    } label: {
                        Text(item.title)
                            .font(PS.font(16, selected ? .bold : .medium))
                            .foregroundStyle(aimed ? Color.white : Color.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Corner.row, style: .continuous)
                                    .fill(aimed ? Color.black : (selected ? Color.white : Color.clear))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(28)
            .frame(width: 280)
            .frame(maxHeight: .infinity, alignment: .top)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: 0).id("top")
                        switch section {
                        case .graphics: graphics
                        case .storage: storage
                        case .system: system
                        }
                    }
                    .padding(36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.settingsRow) { _, row in
                    withAnimation(.easeOut(duration: 0.2)) {
                        if row == 0 { proxy.scrollTo("top", anchor: .top) } else { proxy.scrollTo("row\(row)", anchor: .center) }
                    }
                }
                .onChange(of: model.settingsSection) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
        }
        .onAppear {
            if model.settingsBottleID.isEmpty {
                model.settingsBottleID = model.currentGame?.bottleID ?? model.bottles.first?.id ?? ""
            }
        }
    }

    @ViewBuilder
    private var graphics: some View {
        Text("Graphics")
            .font(PS.font(34, .medium))
            .tracking(-0.8)
        Text("These are written into the CrossOver bottle. Every game in that bottle picks them up the next time it starts, unless a game has its own override.")
            .font(PS.font(14, .regular))
            .foregroundStyle(.black.opacity(0.62))
            .frame(maxWidth: 640, alignment: .leading)
        if model.bottles.isEmpty {
            Text("No bottles found.")
                .font(PS.font(14, .medium))
        } else if let bottle {
            Picker("Bottle", selection: $model.settingsBottleID) {
                ForEach(model.bottles) { item in
                    Text(item.name).tag(item.id)
                }
            }
            .pickerStyle(.menu)
            .font(PS.font(14, .medium))
            .frame(width: 260, alignment: .leading)
            .padding(8)
            .background(focusPlate(contentFocused && model.settingsRow == 0))
            .id("row0")

            VStack(spacing: 10) {
                ForEach(Array(GraphicsBackend.allCases.enumerated()), id: \.element.id) { index, backend in
                    choiceRow(title: backend.title, detail: backend.blurb, selected: bottle.backend == backend, focused: contentFocused && model.settingsRow == index + 1) {
                        model.updateBottle(bottle, backend: backend)
                    }
                    .id("row\(index + 1)")
                }
            }
            VStack(spacing: 10) {
                ForEach(Array(SyncMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    choiceRow(title: mode.title, detail: mode.blurb, selected: bottle.sync == mode, focused: contentFocused && model.settingsRow == index + 4) {
                        model.updateBottle(bottle, sync: mode)
                    }
                    .id("row\(index + 4)")
                }
            }
            toggleRow("MetalFX", "Upscaling for the D3DMetal backend.", bottle.metalFX, contentFocused && model.settingsRow == 7) { value in
                model.updateBottle(bottle, metalFX: value)
            }
            .id("row7")
            toggleRow("DXMT NVIDIA extensions", "Enables DXMT_ENABLE_NVEXT in the bottle.", bottle.nvExtensions, contentFocused && model.settingsRow == 8) { value in
                model.updateBottle(bottle, nvExtensions: value)
            }
            .id("row8")
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage")
                .font(PS.font(34, .medium))
            ForEach(Array(model.bottles.enumerated()), id: \.element.id) { index, bottle in
                let aimed = contentFocused && model.settingsRow == index
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bottle.name).font(PS.font(18, .medium))
                        Text(bottle.path)
                            .font(PS.font(12, .regular))
                            .foregroundStyle((aimed ? Color.white : Color.black).opacity(0.65))
                            .lineLimit(1)
                        Text("\(model.allGames.filter { $0.bottleID == bottle.id }.count) shortcuts · \(bottle.backend.title)")
                            .font(PS.font(12, .medium))
                            .foregroundStyle((aimed ? Color.white : Color.black).opacity(0.7))
                    }
                    Spacer()
                    Button("Open") { model.open(bottle.path) }
                        .buttonStyle(.plain)
                        .font(PS.font(14, .bold))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: Corner.row, style: .continuous).fill(aimed ? Color.black : Color.white.opacity(0.8)))
                .foregroundStyle(aimed ? Color.white : Color.black)
                .id("row\(index)")
            }
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System")
                .font(PS.font(34, .medium))
            systemRow("Account", model.accountName)
            systemRow("CrossOver", model.crossoverVersion.map { "Version \($0)" } ?? "Not found")
            systemRow("Application", model.crossoverPath.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? "Install CrossOver to launch games")
            toggleRow(
                "Full Screen",
                "Playtation opens filling the display. Turn this off if you want a window.",
                model.startFullScreen,
                contentFocused && model.settingsRow == 0
            ) { on in
                model.setStartFullScreen(on)
            }
            .id("row0")
            resolutionRow(contentFocused && model.settingsRow == 1).id("row1")
            HStack(spacing: 18) {
                systemButton("Rescan library", contentFocused && model.settingsRow == 2) { model.refresh() }
                systemButton("Open CrossOver", contentFocused && model.settingsRow == 3) { model.openCrossOver() }
            }
            .padding(.top, 8)
            .id("row2")
            patternRow("Sign-in pattern", model.hasPattern ? "Change pattern" : "Set pattern", model.hasPattern
                ? "Asked for after you pick your profile. Drawn on the controller's touchpad."
                : "Ask for a pattern, drawn on the controller's touchpad, after you pick your profile.",
                contentFocused && model.settingsRow == 4) { model.beginPatternSetup() }
            .id("row4")
            if model.hasPattern {
                patternRow("Remove pattern", "Remove", "Sign in without a pattern.", contentFocused && model.settingsRow == 5) { model.removePattern() }
                    .id("row5")
            }
            Text("Hidden games stay out of Home. Turn them back on from a game's settings after you focus it in Library.")
                .font(PS.font(13, .regular))
                .foregroundStyle(.black.opacity(0.55))
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private func resolutionRow(_ focused: Bool) -> some View {
        let options = DisplayFit.options()
        let index = options.firstIndex { $0.id == model.gameResolution } ?? 0
        let ink = focused ? Color.white : Color.black
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Game resolution").font(PS.font(15, .bold))
                    Text("The highest resolution Playtation switches your display to when a game starts. Your display goes back when the game closes.")
                        .font(PS.font(13, .regular))
                        .foregroundStyle(ink.opacity(0.7))
                }
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    Button { model.cycleGameResolution(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                        .opacity(index > 0 ? 1 : 0.3)
                    Text(options[index].title)
                        .font(PS.font(14, .bold))
                        .frame(minWidth: 140)
                    Button { model.cycleGameResolution(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                        .opacity(index < options.count - 1 ? 1 : 0.3)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Capsule().fill(ink.opacity(0.12)))
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sun.max.fill").font(.system(size: 12))
                Text("This exists so HDR keeps working in games. CrossOver's High Resolution option turns HDR off, so leave it off and set the resolution here instead. Pick \"Don't change\" to keep your current display mode.")
                    .font(PS.font(12, .regular))
            }
            .foregroundStyle(ink.opacity(0.7))
        }
        .padding(14)
        .frame(maxWidth: 680, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Corner.row, style: .continuous).fill(focused ? Color.black : Color.white.opacity(0.8)))
        .foregroundStyle(ink)
    }

    private func patternRow(_ title: String, _ action: String, _ detail: String, _ focused: Bool, _ run: @escaping () -> Void) -> some View {
        let ink = focused ? Color.white : Color.black
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(PS.font(15, .bold))
                Text(detail).font(PS.font(13, .regular)).foregroundStyle(ink.opacity(0.7))
            }
            Spacer()
            Button(action: run) {
                Text(action)
                    .font(PS.font(14, .bold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(ink.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 680)
        .background(RoundedRectangle(cornerRadius: Corner.row, style: .continuous).fill(focused ? Color.black : Color.white.opacity(0.8)))
        .foregroundStyle(ink)
    }

    private func systemRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(PS.font(11, .bold))
                .tracking(0.6)
                .foregroundStyle(.black.opacity(0.45))
            Text(value)
                .font(PS.font(15, .medium))
                .textSelection(.enabled)
        }
    }

    private func systemButton(_ title: String, _ focused: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(PS.font(14, .bold))
                .foregroundStyle(focused ? Color.white : Color.black)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(focused ? Color.black : Color.white.opacity(0.8)))
        }
        .buttonStyle(.plain)
    }

    private func focusPlate(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: Corner.row, style: .continuous)
            .fill(on ? Color.black.opacity(0.08) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.row, style: .continuous)
                    .stroke(Color.black, lineWidth: on ? 2 : 0)
            )
    }

    private func choiceRow(title: String, detail: String, selected: Bool, focused: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .stroke((focused ? Color.white : Color.black).opacity(0.55), lineWidth: 1.5)
                    .background(Circle().fill(selected ? (focused ? Color.white : Color.black) : Color.clear).padding(4))
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(PS.font(15, .bold))
                    Text(detail)
                        .font(PS.font(13, .regular))
                        .foregroundStyle((focused ? Color.white : Color.black).opacity(0.7))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: 680, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Corner.row, style: .continuous).fill(focused ? Color.black : Color.white.opacity(selected ? 0.95 : 0.62)))
            .foregroundStyle(focused ? Color.white : Color.black)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, _ detail: String, _ on: Bool, _ focused: Bool = false, _ set: @escaping (Bool) -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(PS.font(15, .bold))
                Text(detail).font(PS.font(13, .regular)).foregroundStyle((focused ? Color.white : Color.black).opacity(0.7))
            }
            Spacer()
            Toggle("", isOn: Binding(get: { on }, set: set))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(14)
        .frame(maxWidth: 680)
        .background(RoundedRectangle(cornerRadius: Corner.row, style: .continuous).fill(focused ? Color.black : Color.white.opacity(0.8)))
        .foregroundStyle(focused ? Color.white : Color.black)
    }
}


/// Footer that tells you what each button does on the current screen.
struct ControlHints: View {
    var items: [(String, String)]

    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 7) {
                    Image(systemName: item.0).font(.system(size: 13, weight: .semibold))
                    Text(item.1).font(PS.font(13, .medium))
                }
            }
        }
        .foregroundStyle(.black.opacity(0.55))
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.black.opacity(0.04))
    }
}
