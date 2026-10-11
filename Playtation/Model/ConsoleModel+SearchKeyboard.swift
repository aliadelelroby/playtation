import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

/// State and input for the on-screen search keyboard.
extension ConsoleModel {
    // MARK: Search keyboard

    var kbRows: [[String]] { SearchKeyboardLayout.rows(mode: kbMode, shift: kbShift) }

    /// Row 4 is the function row; every other row is a grid of characters.
    var kbRowCount: Int { SearchKeyboardLayout.rowCount }

    func kbColumns(row: Int) -> Int {
        row < SearchKeyboardLayout.rowCount - 1 ? SearchKeyboardLayout.columns : SearchKeyboardFunction.allCases.count
    }

    func kbMove(horizontal: Int, vertical: Int) {
        if vertical != 0 {
            let next = kbRow + vertical
            guard (0..<kbRowCount).contains(next) else {
                ConsoleFeel.shared.bump()
                return
            }
            let fromCols = Double(kbColumns(row: kbRow))
            let toCols = Double(kbColumns(row: next))
            let center = (Double(kbCol) + 0.5) / fromCols
            kbCol = min(Int(toCols) - 1, max(0, Int(center * toCols)))
            kbRow = next
            ConsoleSound.shared.tick(vertical: vertical)
            return
        }
        let cols = kbColumns(row: kbRow)
        let next = kbCol + horizontal
        guard (0..<cols).contains(next) else {
            // Wrap along the character rows like the PS5 keyboard does.
            if kbRow < kbRowCount - 1 {
                kbCol = horizontal > 0 ? 0 : cols - 1
                ConsoleSound.shared.tick(horizontal: horizontal)
            } else {
                ConsoleFeel.shared.bump()
            }
            return
        }
        kbCol = next
        ConsoleSound.shared.tick(horizontal: horizontal)
    }

    func kbPress() {
        if kbRow < kbRowCount - 1 {
            let rows = kbRows
            guard rows.indices.contains(kbRow), rows[kbRow].indices.contains(kbCol) else { return }
            kbType(rows[kbRow][kbCol])
            return
        }
        kbActivate(SearchKeyboardFunction.allCases[min(kbCol, SearchKeyboardFunction.allCases.count - 1)])
    }

    func kbActivate(_ function: SearchKeyboardFunction) {
        switch function {
        case .shift:
            kbShift.toggle()
            ConsoleSound.shared.tick(vertical: 1)
        case .letters:
            kbMode = .letters
            ConsoleSound.shared.tick(vertical: 1)
        case .symbols:
            kbMode = .symbols
            ConsoleSound.shared.tick(vertical: 1)
        case .accents:
            kbMode = .accents
            ConsoleSound.shared.tick(vertical: 1)
        case .space:
            kbType(" ")
        case .delete:
            kbBackspace()
        case .done:
            finishSearch()
        }
    }

    func kbType(_ text: String) {
        guard query.count < 40 else {
            ConsoleFeel.shared.bump()
            return
        }
        query += text
        ConsoleSound.shared.tick(vertical: 1)
        clampSelection()
    }

    func kbBackspace() {
        guard !query.isEmpty else {
            ConsoleFeel.shared.bump()
            return
        }
        query.removeLast()
        ConsoleSound.shared.tick(vertical: -1)
        clampSelection()
    }
}
