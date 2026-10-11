import AppKit

/// Streaming and music services shown as tiles next to games. They open as their own
/// app-style windows, preferring an installed native app, then a chromeless browser window.
enum MediaApps {
    struct Service {
        var key: String
        var name: String
        var blurb: String
        var url: String
        var logo: String
        /// Logo color on the tile. Nil keeps the SVG's own colors.
        var mark: String?
        var tile: (r: CGFloat, g: CGFloat, b: CGFloat)
        var tileEnd: (r: CGFloat, g: CGFloat, b: CGFloat)? = nil
        /// Wash color behind the logo on the full-screen backdrop.
        var wash: (r: CGFloat, g: CGFloat, b: CGFloat)
        var bundleIDs: [String] = []
    }

    static let groupTitle = "Video & music"

    static let all: [Service] = [
        Service(key: "spotify", name: "Spotify", blurb: "Music and podcasts", url: "https://open.spotify.com",
                logo: "spotify", mark: "#1ED760", tile: (0.07, 0.07, 0.07), wash: (0.06, 0.42, 0.20),
                bundleIDs: ["com.spotify.client"]),
        Service(key: "youtube", name: "YouTube", blurb: "Videos, music and live streams", url: "https://www.youtube.com/tv",
                logo: "youtube", mark: "#FF0000", tile: (1, 1, 1), wash: (0.55, 0.05, 0.05)),
        Service(key: "twitch", name: "Twitch", blurb: "Live streams and creators", url: "https://www.twitch.tv",
                logo: "twitch", mark: "#9146FF", tile: (0.05, 0.05, 0.07), wash: (0.30, 0.16, 0.58)),
        Service(key: "netflix", name: "Netflix", blurb: "Movies and series", url: "https://www.netflix.com",
                logo: "netflix", mark: "#E50914", tile: (0.05, 0.05, 0.05), wash: (0.50, 0.03, 0.06),
                bundleIDs: ["com.netflix.Netflix"]),
        Service(key: "disney", name: "Disney+", blurb: "Disney, Pixar, Marvel and Star Wars", url: "https://www.disneyplus.com",
                logo: "disneyplus", mark: nil, tile: (1, 1, 1), wash: (0.05, 0.14, 0.50),
                bundleIDs: ["com.disney.disneyplus"]),
        Service(key: "prime", name: "Prime Video", blurb: "Movies, series and originals", url: "https://www.primevideo.com",
                logo: "primevideo", mark: "#FFFFFF", tile: (0.0, 0.62, 0.86), tileEnd: (0.03, 0.14, 0.32),
                wash: (0.0, 0.36, 0.60), bundleIDs: ["com.amazon.aiv.AIVApp"])
    ]

    static let prefix = "app::"

    static func games() -> [Game] {
        all.enumerated().map { index, service in
            Game(
                id: prefix + service.key,
                name: service.name,
                menuName: service.name,
                bottleID: "",
                bottleName: "Apps",
                iconPath: nil,
                wineBinary: "",
                windowsStart: "",
                order: 10_000 + index,
                webURL: service.url
            )
        }
    }

    // MARK: Artwork

    private static var tileCache: [String: NSImage] = [:]
    private static var backdropCache: [String: NSImage] = [:]

    private static func raster(_ service: Service, tint: String?, width: CGFloat) -> CGImage? {
        guard let url = Bundle.main.url(forResource: service.logo, withExtension: "svg"),
              var text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if let tint, let range = text.range(of: "<svg ") {
            text.replaceSubrange(range, with: "<svg fill=\"\(tint)\" ")
        }
        guard let image = NSImage(data: Data(text.utf8)), image.size.width > 0 else { return nil }
        let height = (width * image.size.height / image.size.width).rounded()
        guard let ctx = CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Square app tile: the service's own background with its real logo centered.
    static func tile(for service: Service) -> NSImage {
        if let cached = tileCache[service.key] { return cached }
        let side = 512
        let size = CGSize(width: side, height: side)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: size) }
        let start = NSColor(srgbRed: service.tile.r, green: service.tile.g, blue: service.tile.b, alpha: 1)
        let end = service.tileEnd.map { NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) } ?? start
        if let gradient = CGGradient(colorsSpace: space, colors: [start.cgColor, end.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        if let logo = raster(service, tint: service.mark, width: 720) {
            let box = size.width * 0.58
            let scale = min(box / CGFloat(logo.width), box * 0.7 / CGFloat(logo.height), 1.4)
            let w = CGFloat(logo.width) * scale, h = CGFloat(logo.height) * scale
            ctx.interpolationQuality = .high
            ctx.draw(logo, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
        let image = ctx.makeImage().map { NSImage(cgImage: $0, size: size) } ?? NSImage(size: size)
        tileCache[service.key] = image
        return image
    }

    /// Full-screen backdrop: a wash of the brand color with the logo in white off to the right.
    static func backdrop(for service: Service) -> NSImage {
        if let cached = backdropCache[service.key] { return cached }
        let wash = NSColor(srgbRed: service.wash.r, green: service.wash.g, blue: service.wash.b, alpha: 1)
        let image: NSImage
        if let logo = raster(service, tint: service.mark == nil ? nil : "#FFFFFF", width: 900),
           let art = CoverArt.appBackdrop(logo: logo, top: wash, bottom: wash.shadow(withLevel: 0.82) ?? .black, whiten: service.mark == nil) {
            image = art
        } else {
            image = tile(for: service)
        }
        backdropCache[service.key] = image
        return image
    }

    static func service(for game: Game) -> Service? {
        all.first { prefix + $0.key == game.id }
    }

    /// Chromium browsers can open a URL as a chromeless app window, and they play DRM video.
    private static let browsers = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "org.chromium.Chromium"
    ]

    @discardableResult
    static func open(_ service: Service) -> Bool {
        let workspace = NSWorkspace.shared
        for id in service.bundleIDs {
            if let app = workspace.urlForApplication(withBundleIdentifier: id) {
                workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                return true
            }
        }
        guard let url = URL(string: service.url) else { return false }
        for id in browsers {
            guard let app = workspace.urlForApplication(withBundleIdentifier: id) else { continue }
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = ["--app=\(service.url)", "--start-fullscreen"]
            config.createsNewApplicationInstance = false
            workspace.openApplication(at: app, configuration: config)
            return true
        }
        return workspace.open(url)
    }
}
