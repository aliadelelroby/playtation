import Combine
import SwiftUI

struct HeroBackdrop: View {
    @EnvironmentObject private var model: ConsoleModel
    var game: Game?
    @State private var base: NSImage?
    @State private var incoming: NSImage?
    @State private var showIncoming = false
    @State private var frames: [NSImage] = []
    @State private var cursor = 0
    private let ticker = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black
            layer(base, visible: !showIncoming)
            layer(incoming, visible: showIncoming)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { reload(animated: false) }
        .onChange(of: game?.id) { _, _ in reload(animated: true) }
        .onChange(of: model.artworkRevision) { _, _ in reload(animated: true) }
        .onChange(of: model.coverToken) { _, _ in reload(animated: true) }
        .onReceive(ticker) { _ in advance() }
    }

    @ViewBuilder
    private func layer(_ image: NSImage?, visible: Bool) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .opacity(visible ? 1 : 0)
                .animation(.easeOut(duration: 0.45), value: visible)
        }
    }

    private func reload(animated: Bool) {
        frames = game.map { model.backdrops(for: $0) } ?? []
        cursor = 0
        present(frames.first, animated: animated)
    }

    private func advance() {
        guard frames.count > 1 else { return }
        cursor = (cursor + 1) % frames.count
        present(frames[cursor], animated: true)
    }

    private func present(_ image: NSImage?, animated: Bool) {
        guard let image else { return }
        if !animated {
            base = image
            showIncoming = false
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if showIncoming {
                base = image
            } else {
                incoming = image
            }
        }
        showIncoming.toggle()
    }
}
