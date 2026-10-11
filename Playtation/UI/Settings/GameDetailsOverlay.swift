import AppKit
import SwiftUI

struct GameDetailsOverlay: View {
    @EnvironmentObject private var model: ConsoleModel
    var game: Game

    private var meta: GameMeta? { model.meta(for: game) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
                .onTapGesture { model.circle() }
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text(model.displayName(for: game))
                        .font(PS.font(26, .medium))
                        .lineLimit(2)
                    Spacer(minLength: 12)
                    Button("Close") { model.circle() }
                        .buttonStyle(.plain)
                        .font(PS.font(14, .bold))
                        .foregroundStyle(model.panelIndex == 1 ? Color.white : Color.black)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(model.panelIndex == 1 ? Color.black : Color.clear))
                }
                if let meta {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            chipRow(meta)
                            if !meta.summary.isEmpty {
                                Text(meta.summary)
                                    .font(PS.font(14, .regular))
                                    .foregroundStyle(.black.opacity(0.78))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !meta.developers.isEmpty {
                                detail("Developer", meta.developers.joined(separator: ", "))
                            }
                            if !meta.publishers.isEmpty {
                                detail("Publisher", meta.publishers.joined(separator: ", "))
                            }
                            if !meta.released.isEmpty {
                                detail("Released", meta.released)
                            }
                            HStack(spacing: 16) {
                                if let website = meta.website, let url = URL(string: website) {
                                    linkButton("Official site", url)
                                }
                                if let trailer = meta.trailer, let url = URL(string: trailer) {
                                    linkButton("Trailer", url)
                                }
                            }
                            Text(meta.source == "rawg" ? "Data and artwork from RAWG" : "Data and artwork from Steam")
                                .font(PS.font(11, .medium))
                                .foregroundStyle(.black.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 360)
                } else {
                    Text("Looking up this game…")
                        .font(PS.font(14, .regular))
                        .foregroundStyle(.black.opacity(0.55))
                }
                Button(action: model.startSelected) {
                    Text(model.launchingID == game.id ? "Starting" : "Start game")
                        .font(PS.font(14, .bold))
                        .foregroundStyle(model.panelIndex == 0 ? Color.white : Color.black)
                        .frame(width: 140, height: 38)
                        .background(Capsule().fill(model.panelIndex == 0 ? Color.black : PS.startFill))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(width: 620, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Corner.panel, style: .continuous).fill(Color.white))
        }
    }

    private func chipRow(_ meta: GameMeta) -> some View {
        HStack(spacing: 8) {
            if let score = meta.metacritic {
                Text("\(score)")
                    .font(PS.font(12, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(scoreColor(score)))
            }
            if let esrb = meta.esrb, !esrb.isEmpty {
                chip(esrb)
            }
            ForEach(meta.genres.prefix(3), id: \.self) { genre in
                chip(genre)
            }
        }
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(PS.font(12, .bold))
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.black.opacity(0.06)))
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 75 { return Color(red: 0.16, green: 0.62, blue: 0.28) }
        if score >= 50 { return Color(red: 0.95, green: 0.62, blue: 0.07) }
        return Color(red: 0.75, green: 0.18, blue: 0.18)
    }

    private func linkButton(_ title: String, _ url: URL) -> some View {
        Button(title) { NSWorkspace.shared.open(url) }
            .buttonStyle(.plain)
            .font(PS.font(13, .bold))
            .foregroundStyle(.black)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(PS.font(11, .bold))
                .tracking(0.6)
                .foregroundStyle(.black.opacity(0.45))
            Text(value)
                .font(PS.font(13, .regular))
                .textSelection(.enabled)
                .foregroundStyle(.black)
        }
    }
}
