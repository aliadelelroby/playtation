import AppKit
import Combine
import SwiftUI

struct ProfileMark: View {
    var image: NSImage?
    var name: String
    var side: CGFloat = 56
    var color: Color = PS.profile

    var body: some View {
        ZStack {
            Circle().fill(color)
            if let image {
                Image(nsImage: Self.circular(image, diameter: side * 2))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(PS.font(max(22, side * 0.36), .bold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .contentShape(Circle())
    }

    private static func circular(_ image: NSImage, diameter: CGFloat) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let result = NSImage(size: size)
        result.lockFocus()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).addClip()
        let source = image.size
        let scale = max(diameter / max(source.width, 1), diameter / max(source.height, 1))
        let draw = NSSize(width: source.width * scale, height: source.height * scale)
        let origin = NSPoint(x: (diameter - draw.width) / 2, y: (diameter - draw.height) / 2)
        image.draw(in: NSRect(origin: origin, size: draw), from: .zero, operation: .copy, fraction: 1)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}
