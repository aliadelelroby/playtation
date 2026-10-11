import SwiftUI

/// "Run Command" in Playtation's clothes: pick a bottle and a program, add environment variables,
/// then run it (for installers) or save it as a launcher tile.
struct AddGameOverlay: View {
    @EnvironmentObject private var model: ConsoleModel
    @FocusState private var field: Field?

    private enum Field { case name, environment }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { model.closeAdd() }
            VStack(alignment: .leading, spacing: 12) {
                Text("Add game")
                    .font(PS.font(28, .medium))
                    .tracking(-0.6)
                Text("Run an installer in a bottle, or add a program that is already installed. Save it and it becomes a tile on Home.")
                    .font(PS.font(13, .regular))
                    .foregroundStyle(.black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                bottleRow
                commandRow
                textRow(2, "Name", "Shown on the tile", $model.addName, .name)
                textRow(3, "Environment variables", "NAME=value, separated by spaces", $model.addEnvironment, .environment)

                HStack(spacing: 12) {
                    Spacer()
                    pill("Run", row: 4) { model.addRow = 4; model.runAddedCommand() }
                    pill("Save as launcher", row: 5) { model.addRow = 5; model.saveAddedLauncher() }
                }
                .padding(.top, 6)

                HStack(spacing: 20) {
                    ForEach(Array(hints.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Image(systemName: item.0).font(.system(size: 12, weight: .semibold))
                            Text(item.1).font(PS.font(12, .medium))
                        }
                    }
                }
                .foregroundStyle(.black.opacity(0.5))
                .padding(.top, 2)
            }
            .padding(28)
            .frame(width: 620)
            // The shadow belongs to the card only, so rows stay flat.
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PS.panel)
                    .shadow(color: .black.opacity(0.3), radius: 28, y: 10)
            )
        }
        .onChange(of: model.addEditing) { _, editing in
            if editing { field = model.addRow == 2 ? .name : .environment } else { field = nil }
        }
        .onChange(of: field) { _, now in
            if now == nil { model.addEditing = false }
        }
        .onSubmit { model.addEditing = false; field = nil }
    }

    private var hints: [(String, String)] {
        model.addEditing
            ? [("return", "Done typing"), ("circle", "Cancel")]
            : [("arrow.up.arrow.down", "Move"), ("arrow.left.arrow.right", "Change"), ("xmark", "Select"), ("circle", "Close")]
    }

    private func plate(_ row: Int) -> some View {
        RoundedRectangle(cornerRadius: Corner.row, style: .continuous)
            .fill(model.addRow == row ? Color.black : Color.white.opacity(0.8))
    }

    private func ink(_ row: Int) -> Color { model.addRow == row ? .white : .black }

    private var bottleRow: some View {
        HStack {
            label("Use bottle", "Where the program runs", row: 0)
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "chevron.left").opacity(canStep(-1) ? 1 : 0.3)
                Text(model.addBottle?.name ?? "No bottles")
                    .font(PS.font(14, .bold))
                    .frame(minWidth: 130)
                Image(systemName: "chevron.right").opacity(canStep(1) ? 1 : 0.3)
            }
            .foregroundStyle(ink(0))
        }
        .padding(14)
        .background(plate(0))
        .contentShape(Rectangle())
        .onTapGesture { model.addRow = 0 }
    }

    private func canStep(_ delta: Int) -> Bool {
        guard let index = model.bottles.firstIndex(where: { $0.id == model.addBottleID }) else { return false }
        return model.bottles.indices.contains(index + delta)
    }

    private var commandRow: some View {
        HStack {
            label("Program", model.addCommand.isEmpty ? "Choose an .exe, .msi or .bat" : model.addCommand, row: 1)
            Spacer()
            Text("Browse…")
                .font(PS.font(13, .bold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(ink(1).opacity(0.14)))
                .foregroundStyle(ink(1))
        }
        .padding(14)
        .background(plate(1))
        .contentShape(Rectangle())
        .onTapGesture { model.addRow = 1; model.chooseCommand() }
    }

    private func textRow(_ row: Int, _ title: String, _ hint: String, _ text: Binding<String>, _ which: Field) -> some View {
        HStack(spacing: 16) {
            label(title, hint, row: row)
                .frame(width: 230, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(PS.font(14, .medium))
                .foregroundStyle(ink(row))
                .focused($field, equals: which)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ink(row).opacity(model.addEditing && model.addRow == row ? 0.2 : 0.08)))
                .onTapGesture { model.addRow = row; model.addEditing = true }
        }
        .padding(14)
        .background(plate(row))
    }

    private func label(_ title: String, _ detail: String, row: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(PS.font(15, .bold))
            Text(detail)
                .font(PS.font(12, .regular))
                .foregroundStyle(ink(row).opacity(0.65))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(ink(row))
        .frame(maxWidth: 380, alignment: .leading)
    }

    private func pill(_ title: String, row: Int, _ action: @escaping () -> Void) -> some View {
        let focused = model.addRow == row
        return Button(action: action) {
            Text(title)
                .font(PS.font(14, .bold))
                .foregroundStyle(focused ? Color.white : Color.black)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Capsule().fill(focused ? Color.black : Color.white.opacity(0.8)))
                .opacity(model.addReady ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

private struct ControlHintsInline: View {
    var items: [(String, String)]

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Image(systemName: item.0).font(.system(size: 12, weight: .semibold))
                    Text(item.1).font(PS.font(12, .medium))
                }
            }
        }
        .foregroundStyle(.black.opacity(0.5))
        .padding(.top, 4)
    }
}
