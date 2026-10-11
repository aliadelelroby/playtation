import Combine
import SwiftUI

struct DashTile: View {
    @EnvironmentObject private var model: ConsoleModel
    var game: Game
    var focused: Bool

    var body: some View {
        let _ = model.artworkRevision
        let card = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            Color.white.opacity(0.05)
            if game.isAction {
                VStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 44, weight: .light))
                    Text("Add Game")
                        .font(PS.font(16, .bold))
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            } else if let image = model.tile(for: game) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(nsImage: model.cover(for: game))
                    .resizable()
                    .scaledToFill()
                VStack {
                    Spacer()
                    Text(model.displayName(for: game))
                        .font(PS.font(15, .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 18)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(card)
        .overlay(alignment: .topTrailing) { badge }
        .overlay(card.stroke(Color.white, lineWidth: focused ? 4 : 0))
        .overlay(card.stroke(Color.white.opacity(focused ? 0 : 0.08), lineWidth: 1))
        .shadow(color: .white.opacity(focused ? 0.28 : 0), radius: focused ? 22 : 0)
        .shadow(color: .black.opacity(focused ? 0.55 : 0.3), radius: focused ? 26 : 10, y: focused ? 14 : 6)
        .opacity(focused ? 1 : (game.filesAvailable ? 0.82 : 0.45))
        .frame(width: width, height: 354, alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: focused)
    }

    private var width: CGFloat { focused ? 236 : 184 }
    private var height: CGFloat { focused ? 354 : 276 }

    @ViewBuilder private var badge: some View {
        if model.isRunning(game) || model.launchingID == game.id {
            HStack(spacing: 6) {
                Circle().fill(model.isRunning(game) ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(model.isRunning(game) ? "Running" : "Starting")
                    .font(PS.font(12, .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Color.black.opacity(0.65)))
            .padding(10)
        } else if !game.filesAvailable {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(0.65)))
                .padding(10)
        }
    }
}
