import AppKit
import SwiftUI

enum Corner {
    /// Game icons keep the same squircle at every size.
    static func tile(_ side: CGFloat) -> CGFloat { side * 0.22 }
    /// Dialogs, library groups, and the power menu.
    static let panel: CGFloat = 22
    /// Rows, info cards, and settings choices.
    static let row: CGFloat = 16
    /// Small chrome such as shoulder labels.
    static let chrome: CGFloat = 8
}

enum PS {
    static let panel = Color(red: 0.949, green: 0.949, blue: 0.949)
    static let ink = Color.black
    static let muted = Color.black.opacity(0.55)
    static let startFill = Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255).opacity(0.30)
    static let cross = Color(red: 0.42, green: 0.65, blue: 0.87)
    static let circle = Color(red: 1.0, green: 0.40, blue: 0.40)
    static let square = Color(red: 1.0, green: 0.412, blue: 0.973)
    static let triangle = Color(red: 0.251, green: 0.886, blue: 0.627)
    static let profile = Color(red: 1.0, green: 0.839, blue: 0.125)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.custom("Lexend Deca", size: size).weight(weight)
    }
}

extension View {
    /// Native Liquid Glass on macOS 26 and later, a frosted shape before that. `clear` is the
    /// see-through variant; `tint` is for a white lift on the focused control.
    @ViewBuilder
    func glassCapsule(clear: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(clear: clear, tint: tint), in: Capsule())
        } else {
            self.background(Capsule().fill(.ultraThinMaterial))
        }
    }

    @ViewBuilder
    func glassCircle(clear: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(clear: clear, tint: tint), in: Circle())
        } else {
            self.background(Circle().fill(.ultraThinMaterial))
        }
    }

    @ViewBuilder
    func glassRounded(_ radius: CGFloat, clear: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(clear: clear, tint: tint), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial))
        }
    }

    @available(macOS 26.0, *)
    private static func glass(clear: Bool, tint: Color?) -> Glass {
        let base: Glass = clear ? .clear : .regular
        return tint.map { base.tint($0) } ?? base
    }

    /// Groups nearby glass shapes so they blend and morph together.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    @ViewBuilder
    func glassMorph(id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
