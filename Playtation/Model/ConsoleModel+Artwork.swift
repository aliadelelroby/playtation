import AppKit
import Collaboration
import GameController
import SwiftUI
import UniformTypeIdentifiers

/// Names, metadata, icons, tiles and backdrops for each game.
extension ConsoleModel {
    func displayName(for game: Game) -> String {
        let local = TitleMatcher.clean(game.name)
        let fallback = local.isEmpty ? game.name : local
        let custom = records[game.id]?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty, TitleMatcher.compatible(custom, with: fallback) { return custom }
        if let title = metas[game.id]?.title, !title.isEmpty, TitleMatcher.compatible(title, with: fallback) {
            return title
        }
        return fallback
    }

    func meta(for game: Game) -> GameMeta? {
        guard let meta = metas[game.id] else { return nil }
        guard TitleMatcher.compatible(meta.title, with: TitleMatcher.clean(game.name)) else { return nil }
        return meta
    }

    func icon(for game: Game) -> NSImage? {
        if let cached = icons[game.id] { return cached }
        let image = loadIcon(for: game)
        if let image { icons[game.id] = image }
        return image
    }

    /// Dashboard tile art: posters as-is, logos composed onto a gradient from their own colors.
    func tile(for game: Game) -> NSImage? {
        if let service = MediaApps.service(for: game) { return MediaApps.tile(for: service) }
        if let cached = tiles[game.id] { return cached }
        guard let icon = icon(for: game) else { return nil }
        let image = CoverArt.tile(from: icon)
        tiles[game.id] = image
        return image
    }

    func backdrops(for game: Game) -> [NSImage] {
        if let cached = backdrops[game.id] { return cached }
        let shots = GameCatalog.files(for: game.id).compactMap { NSImage(contentsOfFile: $0) }
        if !shots.isEmpty {
            backdrops[game.id] = shots
            return shots
        }
        if let wall = wallpaper(for: game) {
            return [wall]
        }
        return []
    }

    func shotCredit(for game: Game) -> String? {
        GameCatalog.credit(for: game.id)
    }

    /// A screen-sized copy of the icon, built once so switching games doesn't rescale the original.
    func wallpaper(for game: Game) -> NSImage? {
        if let service = MediaApps.service(for: game) { return MediaApps.backdrop(for: service) }
        if let cached = wallpapers[game.id] { return cached }
        guard let icon = icon(for: game) else { return nil }
        let fitted = CoverArt.backdrop(from: Self.fitted(icon, maxPixel: 1280))
        wallpapers[game.id] = fitted
        return fitted
    }

    func loadIcon(for game: Game) -> NSImage? {
        if let art = records[game.id]?.artworkPath,
           let image = NSImage(contentsOfFile: art), image.isValid {
            return image
        }
        if let path = GameCatalog.icon(for: game.id),
           let image = NSImage(contentsOfFile: path), image.isValid {
            return image
        }
        if let path = game.iconPath,
           let image = NSImage(contentsOfFile: path), image.isValid {
            return image
        }
        return nil
    }

    static func fitted(_ image: NSImage, maxPixel: CGFloat) -> NSImage {
        let source = image.size
        let longest = max(source.width, source.height)
        guard longest > maxPixel, longest > 0 else { return image }
        let scale = maxPixel / longest
        let size = NSSize(width: floor(source.width * scale), height: floor(source.height * scale))
        let result = NSImage(size: size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }

    func cover(for game: Game) -> NSImage {
        let art = records[game.id]?.artworkPath ?? game.discoveredArt
        let key = game.id + "|" + (art ?? "") + "|" + displayName(for: game)
        if let cached = covers[key] { return cached }
        let image = CoverArt.image(name: displayName(for: game), iconPath: game.iconPath, artwork: art)
        covers[key] = image
        return image
    }

    func bottle(for game: Game) -> Bottle? {
        bottles.first { $0.id == game.bottleID }
    }

    func lastPlayedText(for game: Game) -> String {
        guard let date = currentProfile.played[game.id]?.lastPlayed else { return "Not played yet" }
        return "Last played " + relative.localizedString(for: date, relativeTo: Date())
    }
}
