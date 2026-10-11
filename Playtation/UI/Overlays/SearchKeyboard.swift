import SwiftUI

enum SearchKeyboardMode { case letters, symbols, accents }

enum SearchKeyboardFunction: CaseIterable {
    case shift, letters, symbols, accents, space, delete, done
}

enum SearchKeyboardLayout {
    static let columns = 11
    /// Four character rows plus the function row.
    static let rowCount = 5

    static func rows(mode: SearchKeyboardMode, shift: Bool) -> [[String]] {
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "@"]
        let body: [[String]]
        switch mode {
        case .letters:
            body = [
                "q w e r t y u i o p #", "a s d f g h j k l ' /", "z x c v b n m , . ? !"
            ].map { $0.split(separator: " ").map(String.init) }
        case .symbols:
            body = [
                "! \" $ % & * ( ) _ - +", "= : ; < > [ ] { } ~ `", "^ | \\ « » © ® ° € £ ¥"
            ].map { $0.split(separator: " ").map(String.init) }
        case .accents:
            body = [
                "à á â ä ã å æ ç è é ê", "ë ì í î ï ñ ò ó ô ö õ", "ø œ ù ú û ü ý ÿ ß ð þ"
            ].map { $0.split(separator: " ").map(String.init) }
        }
        let all = [digits] + body
        return shift ? all.map { $0.map { $0.uppercased() } } : all
    }
}

/// PS5-style on-screen keyboard for the home search. The pad drives it through ConsoleModel.
struct SearchKeyboard: View {
    @EnvironmentObject private var model: ConsoleModel

    private let keyWidth: CGFloat = 66
    private let keyHeight: CGFloat = 58
    private let gap: CGFloat = 4

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(0.9).ignoresSafeArea()
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 28) {
                field
                results
                keyboard
                hints
            }
            .frame(width: columnsWidth)
            .padding(.top, 20)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var columnsWidth: CGFloat {
        CGFloat(SearchKeyboardLayout.columns) * keyWidth + CGFloat(SearchKeyboardLayout.columns - 1) * gap
    }

    private var field: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 2) {
                if model.query.isEmpty {
                    Text("Search games and apps")
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    Text(model.query).foregroundStyle(.white)
                }
                Caret()
                Spacer(minLength: 0)
            }
            .font(PS.font(26, .regular))
            Text(countLabel)
                .font(PS.font(14, .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.12)))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.35)).frame(height: 2).padding(.horizontal, 6)
        }
    }

    private var countLabel: String {
        let count = model.games.count
        if model.query.isEmpty { return "" }
        return count == 0 ? "No matches" : (count == 1 ? "1 result" : "\(count) results")
    }

    private var results: some View {
        HStack(spacing: 12) {
            ForEach(model.games.prefix(9)) { game in
                VStack(spacing: 6) {
                    Group {
                        if let image = model.tile(for: game) {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.12)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(model.displayName(for: game))
                        .font(PS.font(11, .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .frame(width: 72)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 96, alignment: .leading)
        .animation(.easeOut(duration: 0.18), value: model.games.map(\.id))
    }

    private var keyboard: some View {
        VStack(spacing: gap) {
            let rows = model.kbRows
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                HStack(spacing: gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, key in
                        let focused = model.kbRow == r && model.kbCol == c
                        Text(key)
                            .font(PS.font(focused ? 30 : 26, focused ? .bold : .regular))
                            .foregroundStyle(.white)
                            .frame(width: keyWidth, height: keyHeight)
                            .background {
                                if focused {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.2))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white, lineWidth: 2))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.kbRow = r
                                model.kbCol = c
                                model.kbPress()
                            }
                            .animation(.easeOut(duration: 0.1), value: focused)
                    }
                }
            }
            functionRow
        }
    }

    private var functionRow: some View {
        let widths: [CGFloat] = [100, 90, 90, 90, 174, 100, 120]
        return HStack(spacing: gap) {
            ForEach(Array(SearchKeyboardFunction.allCases.enumerated()), id: \.offset) { i, function in
                let focused = model.kbRow == SearchKeyboardLayout.rowCount - 1 && model.kbCol == i
                functionKey(function, focused: focused)
                    .frame(width: widths[i], height: keyHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(focused ? 0.28 : (function == .done ? 0.16 : 0.09)))
                    )
                    .overlay {
                        if focused {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white, lineWidth: 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.kbRow = SearchKeyboardLayout.rowCount - 1
                        model.kbCol = i
                        model.kbActivate(function)
                    }
                    .animation(.easeOut(duration: 0.1), value: focused)
            }
        }
    }

    @ViewBuilder
    private func functionKey(_ function: SearchKeyboardFunction, focused: Bool) -> some View {
        switch function {
        case .shift:
            Image(systemName: model.kbShift ? "shift.fill" : "shift")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        case .letters:
            modeLabel("ABC", active: model.kbMode == .letters)
        case .symbols:
            modeLabel("@#:", active: model.kbMode == .symbols)
        case .accents:
            modeLabel("à", active: model.kbMode == .accents)
        case .space:
            Image(systemName: "space")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        case .delete:
            Image(systemName: "delete.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        case .done:
            Text("Done")
                .font(PS.font(20, .bold))
                .foregroundStyle(.white)
        }
    }

    private func modeLabel(_ text: String, active: Bool) -> some View {
        VStack(spacing: 5) {
            Text(text)
                .font(PS.font(20, .bold))
                .foregroundStyle(.white.opacity(active ? 1 : 0.6))
            Rectangle()
                .fill(Color.white.opacity(active ? 0.9 : 0))
                .frame(width: 34, height: 3)
        }
    }

    private var hints: some View {
        HStack(spacing: 22) {
            hint("xmark.circle", "Select")
            hint("circle", "Cancel")
            hint("square", "Delete")
            hint("triangle", "Space")
            hint("l1.rectangle.roundedbottom", "Shift")
            hint("r2.rectangle.roundedtop", "Done")
        }
        .font(PS.font(13, .medium))
        .foregroundStyle(.white.opacity(0.6))
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
    }
}

private struct Caret: View {
    @State private var on = true

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: 30)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = false }
            }
    }
}
