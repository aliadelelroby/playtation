import Combine
import SwiftUI

/// The selected category gets a tinted glass capsule that slides between pills.
struct PillGlass: ViewModifier {
    var on: Bool
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if on {
            content
                .glassCapsule(clear: true, tint: Color.white.opacity(0.1))
                .glassMorph(id: "category", in: namespace)
        } else {
            content
        }
    }
}
