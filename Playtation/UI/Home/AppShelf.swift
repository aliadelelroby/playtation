import Combine
import SwiftUI

/// Video and music apps, grouped like the PS5 app shelf. Collapsed it is a folder; once the
/// selection (or the pointer) lands on it, it opens into a panel of square app tiles.
struct AppGroup: View {
    @EnvironmentObject private var model: ConsoleModel
    var apps: [Game]
    var start: Int

    private var open: Bool { model.selected >= start && model.selected < start + apps.count }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if open {
                panel.transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomLeading)))
            } else {
                folder.transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomLeading)))
            }
        }
        .frame(height: 354, alignment: .bottom)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: open)
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(50), spacing: 8), count: 3), spacing: 8) {
                ForEach(apps) { app in
                    if let service = MediaApps.service(for: app) {
                        Image(nsImage: MediaApps.tile(for: service))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            .padding(10)
            .frame(width: 184, height: 132)
            .glassRounded(14, clear: true)
            Text(MediaApps.groupTitle)
                .font(PS.font(14, .medium))
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.leading, 4)
        }
        .frame(width: 184, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hoverTile(start) }
        }
        .onTapGesture { model.focusTile(start) }
    }

    private var panel: some View {
        let columns = Array(repeating: GridItem(.fixed(128), spacing: 12), count: ConsoleModel.appColumns)
        return VStack(alignment: .leading, spacing: 12) {
            Text(MediaApps.groupTitle.uppercased())
                .font(PS.font(13, .bold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.leading, 4)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { offset, app in
                    AppTile(game: app, focused: start + offset == model.selected)
                        .id(app.id)
                        .zIndex(start + offset == model.selected ? 1 : 0)
                        .onHover { inside in
                            if inside { model.hoverTile(start + offset) }
                        }
                        .onTapGesture { model.activateTile(start + offset) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .glassRounded(18, clear: true)
    }
}
