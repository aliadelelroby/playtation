import Combine
import SwiftUI

/// The PlayStation face-button shapes drawn directly, with no circle around them.
struct PSGlyph: View {
    enum Kind { case cross, circle, square, triangle, search }
    var kind: Kind

    var body: some View {
        switch kind {
        case .cross:
            Path { p in
                p.move(to: CGPoint(x: 3, y: 3)); p.addLine(to: CGPoint(x: 17, y: 17))
                p.move(to: CGPoint(x: 17, y: 3)); p.addLine(to: CGPoint(x: 3, y: 17))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        case .circle:
            Circle().stroke(lineWidth: 2.4).padding(2)
        case .square:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).stroke(lineWidth: 2.4).padding(3)
        case .triangle:
            Path { p in
                p.move(to: CGPoint(x: 10, y: 2.5))
                p.addLine(to: CGPoint(x: 18, y: 16.5))
                p.addLine(to: CGPoint(x: 2, y: 16.5))
                p.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
