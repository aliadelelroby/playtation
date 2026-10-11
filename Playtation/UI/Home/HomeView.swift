import Combine
import SwiftUI

/// Home screen matched to the PS5 dashboard: full-bleed art, tile row, and
/// the title block sitting at the lower left.
struct DashboardView: View {
    @EnvironmentObject private var model: ConsoleModel
    @Namespace private var pillSpace

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backdrop.ignoresSafeArea() }
            .overlay { overlays.allowsHitTesting(false) }
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    categoryBar
                }
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    heroBlock
                        .padding(.leading, 60)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .zIndex(10)
                    tileBlock
                    Color.clear.frame(height: 44)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let game = model.currentGame, let credit = model.shotCredit(for: game) {
                    Text(credit)
                        .font(PS.font(11, .regular))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .padding(.leading, 60)
                        .padding(.bottom, 16)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                hintBar
                    .padding(.trailing, 48)
                    .padding(.bottom, 14)
            }
        .onChange(of: model.query) { _, _ in
            model.clampSelection()
        }
    }

    private var categoryBar: some View {
        HStack(spacing: 10) {
            ShoulderBadge(label: "L1")
            ForEach(ConsoleModel.HomeCategory.allCases) { item in
                let on = model.category == item
                Button { model.setCategory(item) } label: {
                    Text(item.title.uppercased())
                        .font(PS.font(14, .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(on ? 1 : 0.65))
                        .padding(.horizontal, 20)
                        .frame(height: 36)
                        .modifier(PillGlass(on: on, namespace: pillSpace))
                }
                .buttonStyle(.plain)
            }
            ShoulderBadge(label: "R1")
            Spacer()
        }
        .glassGroup(spacing: 12)
        .padding(.leading, 60)
        .padding(.top, 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.category)
    }

    private var hintBar: some View {
        HStack(spacing: 22) {
            hint(.cross, model.currentGame?.webURL == nil ? "Play" : "Open")
            hint(.square, "Details")
            hint(.triangle, "Game settings")
            hint(.search, "Search")
        }
        .opacity(model.searching ? 0 : 1)
    }

    private func hint(_ glyph: PSGlyph.Kind, _ text: String) -> some View {
        HStack(spacing: 9) {
            PSGlyph(kind: glyph)
                .frame(width: 20, height: 20)
            Text(text.uppercased())
                .font(PS.font(12, .bold))
                .tracking(0.8)
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .shadow(color: .black.opacity(0.55), radius: 6)
    }

    private var backdrop: some View {
        HeroBackdrop(game: model.currentGame)
            .ignoresSafeArea()
    }

    private var overlays: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.4), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 250)
            .frame(maxHeight: .infinity, alignment: .top)
            LinearGradient(
                colors: [Color.black.opacity(0.9), Color.black.opacity(0.5), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 400)
            .frame(maxHeight: .infinity, alignment: .bottom)
            LinearGradient(
                colors: [Color.black.opacity(0.6), .clear],
                startPoint: .leading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 30) {
            if !model.query.isEmpty && !model.searching {
                Button { model.activateTop(0) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold))
                        Text(model.query).font(PS.font(16, .medium)).lineLimit(1)
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .opacity(0.7)
                            .onTapGesture { withAnimation { model.query = "" } }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .glassCapsule(clear: true)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            Spacer(minLength: 12)
            iconButton("magnifyingglass", index: 0) { model.activateTop(0) }
            iconButton("gearshape", index: 1) { model.activateTop(1) }
            Button { model.activateTop(2) } label: {
                ProfileMark(image: model.accountImage, name: model.accountName, side: 44)
                    .overlay(Circle().stroke(Color.white.opacity(model.zone == .top && model.topIndex == 2 ? 0.95 : 0.3), lineWidth: 2))
            }
            .buttonStyle(.plain)
            DashClock()
        }
        .padding(.horizontal, 60)
        .padding(.top, 40)
        .frame(height: 100, alignment: .center)
    }

    private func iconButton(_ symbol: String, index: Int, action: @escaping () -> Void) -> some View {
        let focused = model.zone == .top && model.topIndex == index
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.white.opacity(focused ? 1 : 0.85))
                .frame(width: 44, height: 44)
                .glassCircle(clear: true, tint: focused ? Color.white.opacity(0.22) : nil)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    private var tileBlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.loading && model.games.isEmpty {
                HStack(spacing: 14) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Looking through CrossOver")
                        .font(PS.font(16, .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 60)
                .frame(height: 140, alignment: .leading)
            } else if model.games.isEmpty {
                Text(model.bottles.isEmpty ? "CrossOver isn't set up yet" : "No games match")
                    .font(PS.font(20, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 60)
                    .frame(height: 140, alignment: .leading)
            } else {
                tileRow
                    .frame(height: 380)
            }
        }
        .padding(.horizontal, 0)
    }

    private var tileRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 18) {
                    let all = model.games
                    let groupStart = all.firstIndex { $0.webURL != nil }
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, game in
                        if game.webURL == nil {
                            DashTile(
                                game: game,
                                focused: index == model.selected
                            )
                            .id(game.id)
                            .onHover { inside in
                                if inside { model.hoverTile(index) }
                            }
                            .onTapGesture { model.activateTile(index) }
                        } else if index == groupStart {
                            AppGroup(
                                apps: Array(all[index...].filter { $0.webURL != nil }),
                                start: index
                            )
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            .onChange(of: model.currentGame?.id) { _, id in
                guard let id else { return }
                scrollIfNeeded(proxy, to: id)
            }
            .onAppear {
                if let id = model.currentGame?.id {
                    scrollIfNeeded(proxy, to: id)
                }
            }
        }
    }

    private func scrollIfNeeded(_ proxy: ScrollViewProxy, to id: String) {
        guard model.games.count > 4 else { return }
        let transaction = Transaction(animation: .easeOut(duration: 0.22))
        withTransaction(transaction) {
            proxy.scrollTo(id, anchor: .leading)
        }
    }

    private var heroBlock: some View {
        let game = model.currentGame
        return VStack(alignment: .leading, spacing: 0) {
            Text((game.map { model.displayName(for: $0) } ?? "Playtation").uppercased())
                .font(PS.font(50, .bold))
                .tracking(-1)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 18, y: 4)
                .lineLimit(2)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.bottom, 16)
            Text(tagline(game))
                .font(PS.font(18, .regular))
                .foregroundStyle(Color.white.opacity(0.9))
                .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                .lineLimit(2)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.bottom, 28)
            HStack(spacing: 12) {
                Button { model.activateHero(0) } label: {
                    Text(primaryTitle)
                        .font(PS.font(16, .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 28)
                        .frame(height: 44)
                        .glassCapsule(clear: true, tint: startFocused ? Color.white.opacity(0.14) : nil)
                        .scaleEffect(startFocused ? 1.06 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: startFocused)
                }
                .buttonStyle(.plain)
                if game?.hasOptions ?? true {
                Button { model.activateHero(1) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassCircle(clear: true, tint: moreFocused ? Color.white.opacity(0.14) : nil)
                        .scaleEffect(moreFocused ? 1.1 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: moreFocused)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottomLeading) {
                    if model.showMore {
                        moreMenu
                            .offset(x: 56)
                            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomLeading)))
                    }
                }
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.zone)
            .animation(.easeOut(duration: 0.2), value: model.heroIndex)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var moreMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            moreItem("Info", 0)
            moreItem("Game settings", 1)
            moreItem(model.confirmRemove ? "Press again to remove" : "Remove", 2)
        }
        .padding(8)
        .fixedSize()
        .glassRounded(22, clear: true)
    }

    private func moreItem(_ title: String, _ index: Int) -> some View {
        let on = model.panelIndex == index
        return Button {
            model.panelIndex = index
            model.confirmMore()
        } label: {
            Text(title)
                .font(PS.font(14, .bold))
                .foregroundStyle(Color.white)
                .frame(width: 190, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().fill(Color.white.opacity(on ? 0.24 : 0)))
        }
        .buttonStyle(.plain)
    }

    private var startFocused: Bool { model.zone == .hero && model.heroIndex == 0 && !model.showMore }
    private var moreFocused: Bool { (model.zone == .hero && model.heroIndex == 1) || model.showMore }
    private var starting: Bool { model.launchingID != nil && model.launchingID == model.currentGame?.id }

    private var primaryTitle: String {
        guard let game = model.currentGame else { return "Start" }
        if model.closingGameID == game.id { return "Closing" }
        if model.canClose(game) { return "Close" }
        if starting { return "Starting" }
        if game.webURL != nil { return "Open" }
        if game.isAction { return "Add" }
        return "Start"
    }

    private func tagline(_ game: Game?) -> String {
        guard let game else { return "Games installed in CrossOver show up here." }
        if let service = MediaApps.service(for: game) { return service.blurb }
        if game.isAction { return "Run an installer, or add a program that is already in a bottle." }
        if game.isCustom { return model.lastPlayedText(for: game) }
        if model.launchingID == game.id { return "Starting" }
        if model.isRunning(game) { return "Running" }
        if model.canClose(game) { return "No window" }
        if !game.filesAvailable { return "The install drive for this game isn't mounted." }
        if let meta = model.meta(for: game) {
            var bits: [String] = []
            if !meta.genres.isEmpty { bits.append(meta.genres.prefix(3).joined(separator: ", ")) }
            if let year = meta.released.range(of: #"\d{4}"#, options: .regularExpression) {
                bits.append(String(meta.released[year]))
            } else if !meta.released.isEmpty {
                bits.append(meta.released)
            }
            if let developer = meta.developers.first { bits.append(developer) }
            if !bits.isEmpty { return bits.joined(separator: "  ·  ") }
        }
        return model.lastPlayedText(for: game)
    }
}
