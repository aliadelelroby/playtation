import SwiftUI

/// Settings > Users: what can be done to one user.
struct UserMenuOverlay: View {
    @EnvironmentObject private var model: ConsoleModel
    var profile: Profile

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { model.closeUserMenu() }
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    ProfileMark(image: model.image(of: profile), name: model.displayName(of: profile), side: 88, color: profile.tint)
                    Text(model.displayName(of: profile))
                        .font(PS.font(24, .regular))
                    if profile.isOwner {
                        Text("Main user")
                            .font(PS.font(13, .medium))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
                VStack(spacing: 6) {
                    let actions = model.userActions(for: profile.id)
                    ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                        row(action, index: index)
                    }
                }
                HStack(spacing: 24) {
                    hint("arrow.up.arrow.down", "Move")
                    hint("xmark", "Select")
                    hint("circle", "Back")
                }
                .foregroundStyle(.black.opacity(0.55))
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: Corner.panel, style: .continuous).fill(PS.panel))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        }
    }

    private func row(_ action: ConsoleModel.UserAction, index: Int) -> some View {
        let on = model.userMenuIndex == index
        let title = action == .remove && model.confirmUserRemove ? "Press again to remove" : action.title
        return Button {
            model.userMenuIndex = index
            model.confirmUserMenu()
        } label: {
            HStack {
                Text(title)
                    .font(PS.font(15, .bold))
                    .foregroundStyle(action == .remove && model.confirmUserRemove ? PS.circle : (on ? Color.white : Color.black))
                Spacer()
                if action == .color {
                    Circle().fill(profile.tint).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.white.opacity(on ? 0.8 : 0), lineWidth: 1.5))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: Corner.row, style: .continuous).fill(on ? Color.black : Color.white.opacity(0.8)))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { model.userMenuIndex = index }
        }
    }

    private func hint(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(label).font(PS.font(13, .medium))
        }
    }
}
