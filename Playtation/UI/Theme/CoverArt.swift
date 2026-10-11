import AppKit
import CoreText

enum CoverArt {
    static func image(name: String, iconPath: String?, artwork: String?) -> NSImage {
        if let artwork, let photo = NSImage(contentsOfFile: artwork), photo.isValid {
            return photo
        }
        let side = 900
        let icon = iconPath.flatMap { cgImage(at: $0) }
        let palette = palette(for: name, icon: icon)
        guard let cg = render(name: name, icon: icon, palette: palette, side: side) else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }

    /// Portrait posters pass through untouched. Anything else (square app logos, wide banners) is
    /// centered on a gradient built from the logo's own colors so it reads like a console app tile.
    static func tile(from image: NSImage, size: CGSize = CGSize(width: 472, height: 708)) -> NSImage {
        let pixel = image.size
        guard pixel.width > 0, pixel.height > 0 else { return image }
        let ratio = pixel.width / pixel.height
        if ratio >= 0.55 && ratio <= 0.8 { return image }
        var proposed = NSRect(origin: .zero, size: pixel)
        guard let full = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let logo = trimmed(full),
              let cg = renderTile(logo: logo, size: size) else { return image }
        return NSImage(cgImage: cg, size: size)
    }

    /// Full-screen backdrop. Landscape art passes through; posters and logos would be blown up and
    /// cropped badly, so they become a soft color wash (plus the logo, sharp, off to the right).
    static func backdrop(from image: NSImage, size: CGSize = CGSize(width: 1600, height: 900)) -> NSImage {
        let pixel = image.size
        guard pixel.width > 0, pixel.height > 0, pixel.width / pixel.height < 1.4 else { return image }
        var proposed = NSRect(origin: .zero, size: pixel)
        guard let full = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let cg = renderBackdrop(art: full, isPoster: pixel.width / pixel.height <= 0.8, size: size)
        else { return image }
        return NSImage(cgImage: cg, size: size)
    }

    /// Backdrop for a service logo with explicit colors. `whiten` flattens multicolor logos to white.
    static func appBackdrop(logo: CGImage, top: NSColor, bottom: NSColor, whiten: Bool, size: CGSize = CGSize(width: 1600, height: 900)) -> NSImage? {
        var art = logo
        if whiten, let flat = whitened(logo) { art = flat }
        guard let cg = renderBackdrop(art: art, isPoster: false, size: size, colors: (top, bottom)) else { return nil }
        return NSImage(cgImage: cg, size: size)
    }

    private static func whitened(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.draw(image, in: rect)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)
        return ctx.makeImage()
    }

    private static func renderBackdrop(art: CGImage, isPoster: Bool, size: CGSize, colors: (NSColor, NSColor)? = nil) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
        else { return nil }
        let logo = isPoster ? art : (trimmed(art) ?? art)
        let (top, bottom) = colors ?? dominantColors(logo)

        if let gradient = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        if isPoster {
            // Tiny aspect-filled copy scaled back up reads as a blur of the art's own colors.
            let lw = 48, lh = 27
            if let small = CGContext(data: nil, width: lw, height: lh, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) {
                let scale = max(CGFloat(lw) / CGFloat(art.width), CGFloat(lh) / CGFloat(art.height))
                let dw = CGFloat(art.width) * scale, dh = CGFloat(art.height) * scale
                small.interpolationQuality = .high
                small.draw(art, in: CGRect(x: (CGFloat(lw) - dw) / 2, y: (CGFloat(lh) - dh) / 2, width: dw, height: dh))
                if let blurred = small.makeImage() {
                    ctx.saveGState()
                    ctx.setAlpha(0.75)
                    ctx.interpolationQuality = .high
                    ctx.draw(blurred, in: CGRect(origin: .zero, size: size))
                    ctx.restoreGState()
                }
            }
        } else {
            let center = CGPoint(x: size.width * 0.72, y: size.height * 0.52)
            if let glow = CGGradient(
                colorsSpace: space,
                colors: [top.withAlphaComponent(0.9).cgColor, top.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]
            ) {
                ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.height * 0.85, options: [])
            }
            let scale = min(size.height * 0.62 / CGFloat(logo.width), size.height * 0.46 / CGFloat(logo.height))
            let lw = CGFloat(logo.width) * scale, lh = CGFloat(logo.height) * scale
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 40, color: NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.interpolationQuality = .high
            ctx.draw(logo, in: CGRect(x: center.x - lw / 2, y: center.y - lh / 2, width: lw, height: lh))
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    /// Crops fully transparent margins so logos with built-in padding fill the tile properly.
    private static func trimmed(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where buf[(y * w + x) * 4 + 3] > 12 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return image.cropping(to: rect) ?? image
    }

    private static func renderTile(logo: CGImage, size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let (top, bottom) = dominantColors(logo)
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        // Soft glow behind the logo so it lifts off the background.
        if let glow = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1]
        ) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width * 0.8, options: [])
        }

        let box = size.width * 0.62
        let scale = min(box / CGFloat(logo.width), box / CGFloat(logo.height))
        let lw = CGFloat(logo.width) * scale, lh = CGFloat(logo.height) * scale
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.interpolationQuality = .high
        ctx.draw(logo, in: CGRect(x: (size.width - lw) / 2, y: (size.height - lh) / 2, width: lw, height: lh))
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// Two background colors taken from the logo's saturated pixels, darkened so the logo stays legible.
    private static func dominantColors(_ image: CGImage) -> (NSColor, NSColor) {
        let n = 24
        guard let ctx = CGContext(
            data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else { return (NSColor(white: 0.18, alpha: 1), NSColor(white: 0.06, alpha: 1)) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        let buf = data.bindMemory(to: UInt8.self, capacity: n * n * 4)

        // Bucket by hue; weight by saturation so a white glyph doesn't wash out the brand color.
        var weight = [CGFloat](repeating: 0, count: 12)
        var sum = [(CGFloat, CGFloat, CGFloat)](repeating: (0, 0, 0), count: 12)
        var lum: CGFloat = 0, solid: CGFloat = 0
        for i in 0..<(n * n) {
            let a = CGFloat(buf[i * 4 + 3]) / 255
            if a < 0.3 { continue }
            let c = NSColor(srgbRed: CGFloat(buf[i * 4]) / 255 / a, green: CGFloat(buf[i * 4 + 1]) / 255 / a,
                            blue: CGFloat(buf[i * 4 + 2]) / 255 / a, alpha: 1)
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
            c.getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
            lum += bri; solid += 1
            let wgt = sat * sat * max(bri, 0.2)
            let b = min(11, Int(hue * 12))
            weight[b] += wgt
            sum[b].0 += c.redComponent * wgt; sum[b].1 += c.greenComponent * wgt; sum[b].2 += c.blueComponent * wgt
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0.5 else {
            // Mostly white/gray/black logo: neutral charcoal, flipped to a lighter slate for dark logos.
            let dark = solid > 0 && lum / solid < 0.45
            return dark ? (NSColor(white: 0.9, alpha: 1), NSColor(white: 0.62, alpha: 1))
                        : (NSColor(white: 0.22, alpha: 1), NSColor(white: 0.07, alpha: 1))
        }
        let w = weight[best]
        let base = NSColor(srgbRed: sum[best].0 / w, green: sum[best].1 / w, blue: sum[best].2 / w, alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
        base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
        let topColor = NSColor(hue: hue, saturation: min(1, sat * 0.9), brightness: min(0.62, max(0.4, bri * 0.8)), alpha: 1)
        let bottomColor = NSColor(hue: hue, saturation: min(1, sat), brightness: 0.14, alpha: 1)
        return (topColor, bottomColor)
    }

    private static func cgImage(at path: String) -> CGImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        var proposed = NSRect(x: 0, y: 0, width: 512, height: 512)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    private static func palette(for name: String, icon: CGImage?) -> (NSColor, NSColor, NSColor) {
        let n = name.lowercased()
        let brands: [(String, (CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))] = [
            ("spotify", (0.03, 0.10, 0.06), (0.11, 0.73, 0.33)),
            ("youtube", (0.12, 0.02, 0.02), (0.92, 0.12, 0.12)),
            ("twitch", (0.07, 0.04, 0.16), (0.57, 0.27, 1.0)),
            ("netflix", (0.05, 0.02, 0.02), (0.88, 0.04, 0.08)),
            ("disney", (0.02, 0.05, 0.16), (0.10, 0.28, 0.78)),
            ("prime", (0.02, 0.07, 0.12), (0.00, 0.66, 0.88))
        ]
        if let brand = brands.first(where: { n.contains($0.0) }) {
            let deep = NSColor(srgbRed: brand.1.0, green: brand.1.1, blue: brand.1.2, alpha: 1)
            let accent = NSColor(srgbRed: brand.2.0, green: brand.2.1, blue: brand.2.2, alpha: 1)
            return (deep, accent.shadow(withLevel: 0.45) ?? accent, accent)
        }
        if n.contains("red dead") {
            return (
                NSColor(srgbRed: 0.10, green: 0.05, blue: 0.03, alpha: 1),
                NSColor(srgbRed: 0.55, green: 0.22, blue: 0.08, alpha: 1),
                NSColor(srgbRed: 0.93, green: 0.62, blue: 0.28, alpha: 1)
            )
        }
        if n.contains("spider") {
            return (
                NSColor(srgbRed: 0.05, green: 0.06, blue: 0.14, alpha: 1),
                NSColor(srgbRed: 0.62, green: 0.06, blue: 0.10, alpha: 1),
                NSColor(srgbRed: 0.86, green: 0.16, blue: 0.20, alpha: 1)
            )
        }
        if n.contains("football") || n.contains("pes") {
            return (
                NSColor(srgbRed: 0.02, green: 0.08, blue: 0.05, alpha: 1),
                NSColor(srgbRed: 0.05, green: 0.38, blue: 0.18, alpha: 1),
                NSColor(srgbRed: 0.55, green: 0.86, blue: 0.32, alpha: 1)
            )
        }
        let sampled = icon.flatMap(averageColor) ?? NSColor(srgbRed: 0.12, green: 0.28, blue: 0.62, alpha: 1)
        return (
            sampled.shadow(withLevel: 0.72) ?? .black,
            sampled,
            sampled.highlight(withLevel: 0.35) ?? .white
        )
    }

    private static func averageColor(_ image: CGImage) -> NSColor? {
        let w = 20
        let h = 20
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var r = 0, g = 0, b = 0, count = 0
        for i in 0..<(w * h) {
            if buf[i * 4 + 3] < 24 { continue }
            r += Int(buf[i * 4])
            g += Int(buf[i * 4 + 1])
            b += Int(buf[i * 4 + 2])
            count += 1
        }
        guard count > 0 else { return nil }
        return NSColor(
            srgbRed: CGFloat(r) / CGFloat(count) / 255,
            green: CGFloat(g) / CGFloat(count) / 255,
            blue: CGFloat(b) / CGFloat(count) / 255,
            alpha: 1
        )
    }

    private static func render(name: String, icon: CGImage?, palette: (NSColor, NSColor, NSColor), side: Int) -> CGImage? {
        let size = CGSize(width: side, height: side)
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let deep = palette.0
        let mid = palette.1
        let accent = palette.2
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [accent.cgColor, mid.cgColor, deep.cgColor] as CFArray,
            locations: [0, 0.42, 1]
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: size.width, y: 0),
                options: []
            )
        }

        ctx.saveGState()
        ctx.setFillColor(accent.withAlphaComponent(0.45).cgColor)
        ctx.fillEllipse(in: CGRect(x: size.width * 0.28, y: size.height * 0.22, width: size.width * 0.7, height: size.height * 0.7))
        ctx.restoreGState()

        if let icon {
            let length = size.width * 0.5
            let rect = CGRect(
                x: (size.width - length) / 2,
                y: (size.height - length) / 2,
                width: length,
                height: length
            )
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.interpolationQuality = .high
            ctx.draw(icon, in: rect)
            ctx.restoreGState()
        } else {
            let letter = String(name.prefix(1)).uppercased()
            let font = CTFontCreateWithName("Lexend Deca" as CFString, size.width * 0.28, nil)
            let text = NSAttributedString(string: letter, attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.94)
            ])
            let line = CTLineCreateWithAttributedString(text)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(
                x: (size.width - textWidth) / 2,
                y: (size.height - ascent + descent) / 2
            )
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()
    }
}
