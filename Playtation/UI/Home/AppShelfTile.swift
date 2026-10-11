import Combine
import SwiftUI

struct AppTile: View {
    @EnvironmentObject private var model: ConsoleModel
    var game: Game
    var focused: Bool

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let image = model.tile(for: game) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Color.white.opacity(0.1)
            }
        }
        .frame(width: 128, height: 128)
        .clipShape(card)
        .overlay(card.stroke(Color.white, lineWidth: focused ? 4 : 0))
        .shadow(color: .white.opacity(focused ? 0.3 : 0), radius: focused ? 16 : 0)
        .shadow(color: .black.opacity(focused ? 0.5 : 0.2), radius: focused ? 18 : 6, y: focused ? 10 : 4)
        .opacity(focused ? 1 : 0.82)
        .scaleEffect(focused ? 1.1 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: focused)
    }
}
