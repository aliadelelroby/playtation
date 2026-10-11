import AppKit
import Combine
import SwiftUI

struct PowerMenu: View {
    @EnvironmentObject private var model: ConsoleModel
    @State private var revealed = false

    private let titles = ["Home", "Settings", "Rest Mode", "Close Playtation"]

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.055, blue: 0.06)
                .onTapGesture { model.circle() }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    ForEach(titles.indices, id: \.self) { index in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 1)
                        }
                        menuRow(titles[index], index: index)
                    }
                }
                .frame(width: 280)
                Spacer(minLength: 0)
            }

            Clock(light: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 36)
                .padding(.trailing, 40)
                .opacity(revealed ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.48)) { revealed = true }
        }
    }

    private func menuRow(_ title: String, index: Int) -> some View {
        let on = model.panelIndex == index
        return Button {
            model.panelIndex = index
            model.confirmPower()
        } label: {
            Text(title)
                .font(PS.font(20, on ? .bold : .medium))
                .foregroundStyle(.white.opacity(on ? 1 : 0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 16)
        .animation(.easeOut(duration: 0.46).delay(0.06 + Double(index) * 0.055), value: revealed)
        .onHover { hovering in
            if hovering { model.panelIndex = index }
        }
    }
}
