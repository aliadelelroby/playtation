import Foundation

/// Pure title logic: cleaning shortcut names, comparing them with store listings, and picking
/// the best listing. No I/O, so it is covered by unit tests.
enum TitleMatcher {
    // MARK: - Cleaning

    /// Drops launcher/setup words and brackets so "Red Dead Redemption 2 Launcher" searches as the game.
    static func clean(_ name: String) -> String {
        var text = name.replacingOccurrences(of: #"[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
        for word in ["launcher", "setup", "installer", "redistributable", "benchmark"] {
            text = text.replacingOccurrences(of: #"\b\#(word)\b"#, with: "", options: [.caseInsensitive, .regularExpression])
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Comparison key: case, accents, ™/®, "&" and a leading "the" don't matter.
    static func key(_ name: String) -> String {
        let folded = clean(name)
            .replacingOccurrences(of: "™", with: "")
            .replacingOccurrences(of: "®", with: "")
            .replacingOccurrences(of: "&", with: " and ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return folded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Meaningful lowercase words. "PES2021" and "eFootball PES 2021" share `pes` and `2021`.
    static func tokens(_ name: String) -> Set<String> {
        let words = splitAlphanumeric(key(name))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                if stopwords.contains(token) { return false }
                return token.count > 1 || token.allSatisfy(\.isNumber) || romans[token] != nil
            }
        return Set(words)
    }

    // MARK: - Shortcut names

    /// Shortcut names are often just "Spider-Man". The install folder usually has the rest:
    /// Remastered, 2, Miles Morales.
    static func preferredTitle(menu: String, executable: String?) -> String {
        let folder = folderHint(from: executable)
        let exe = executable.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? ""
        let lowered = menu.lowercased()
        if ["launcher", "play", "start", "game"].contains(lowered) {
            if folder.isEmpty { return menu }
            return folder.lowercased().contains("launcher") ? folder : "\(folder) Launcher"
        }
        if lowered == "rdr2" {
            return folder.isEmpty ? "Red Dead Redemption 2" : folder
        }
        if exe.lowercased().hasPrefix("tlou") || lowered.hasPrefix("tlou") {
            return folder.isEmpty ? "The Last of Us Part I" : folder
        }
        return richest(among: [menu, folder, exe], preferring: menu)
    }

    // MARK: - Comparing

    /// Saved titles and store results must not promote a sequel when the install is another part.
    static func compatible(_ title: String, with local: String) -> Bool {
        let wanted = edition(local)
        let got = edition(title)
        if !wanted.numbers.isEmpty && !got.numbers.isEmpty && wanted.numbers.isDisjoint(with: got.numbers) {
            return false
        }
        if isSequel(got.numbers) != isSequel(wanted.numbers) { return false }
        if !wanted.tags.isEmpty && !got.tags.isEmpty && wanted.tags.isDisjoint(with: got.tags) {
            return false
        }
        return true
    }

    /// 0 means "not this game"; 1 means identical. Rewards covering every word of the shortcut name,
    /// tolerates one-letter typos in long words, and rejects soundtracks, DLC and other add-ons.
    static func score(_ query: String, _ candidate: String) -> Double {
        let left = tokens(query)
        let right = tokens(candidate)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if isAddOn(candidate) && !isAddOn(query) { return 0 }

        let matched = matchedWeight(left, right)
        let recall = matched / Double(left.count)
        let precision = matched / Double(right.count)
        var value = recall * 0.65 + precision * 0.35

        let wanted = edition(query)
        let got = edition(candidate)
        if isSequel(got.numbers) && !isSequel(wanted.numbers) { return 0 }
        if isSequel(wanted.numbers) && !isSequel(got.numbers) { value *= 0.25 }
        if !wanted.numbers.isEmpty && !got.numbers.isEmpty && wanted.numbers.isDisjoint(with: got.numbers) {
            return 0
        }
        if !wanted.tags.isEmpty && wanted.tags.isSubset(of: got.tags) { value += 0.1 }
        // An edition the shortcut didn't ask for (Remastered, Miles Morales...) ranks below the plain game.
        for _ in got.tags.subtracting(wanted.tags) { value *= 0.92 }
        // Not a single word in common beyond a number or edition tag is not a match.
        let meaningful = left.subtracting(romans.keys).filter { !$0.allSatisfy(\.isNumber) && !editionTags.contains($0) }
        if !meaningful.isEmpty && matchedWeight(meaningful, right) == 0 { return 0 }
        return min(value, 1)
    }

    /// Lowest score the callers accept.
    static let threshold = 0.5

    /// The best listing for `query`, or nil when nothing is close enough. Earlier results win ties,
    /// because the store already ranked them.
    static func best(_ query: String, among listings: [(id: Int, name: String)]) -> (id: Int, name: String, score: Double)? {
        var best: (id: Int, name: String, score: Double)?
        var bestExtras = Int.max
        let wanted = tokens(query)
        for listing in listings {
            let value = score(query, listing.name)
            guard value >= threshold else { continue }
            let extras = tokens(listing.name).subtracting(wanted).count
            if let current = best {
                if value < current.score - 0.0001 { continue }
                if abs(value - current.score) <= 0.0001 && extras >= bestExtras { continue }
            }
            best = (listing.id, listing.name, value)
            bestExtras = extras
        }
        return best
    }

    // MARK: - Words

    private static let stopwords: Set<String> = ["the", "of", "and", "a", "an", "edition"]

    private static let weakTitles: Set<String> = [
        "bin", "binaries", "win64", "win32", "x64", "x86", "retail", "shipping",
        "game", "games", "bin64", "client", "engine", "redist", "common",
        "launcher", "play", "start", "install", "installer", "program files",
        "program files (x86)", "windows", "system32", "drive_c", "dosdevices"
    ]

    private static let editionTags: Set<String> = [
        "remastered", "remaster", "definitive", "complete", "goty", "enhanced",
        "redux", "miles", "morales", "rebirth", "royal", "ultimate", "gold"
    ]

    /// Words that mark a store listing as something other than the game itself.
    private static let addOnWords: Set<String> = [
        "soundtrack", "ost", "dlc", "demo", "bundle", "artbook", "wallpaper", "beta",
        "playtest", "pass", "pack", "upgrade", "skin", "skins", "server", "sdk", "editor", "tool"
    ]

    private static let romans: [String: String] = [
        "i": "1", "ii": "2", "iii": "3", "iv": "4", "v": "5",
        "vi": "6", "vii": "7", "viii": "8", "ix": "9", "x": "10",
        "xi": "11", "xii": "12", "xiii": "13", "xiv": "14", "xv": "15"
    ]

    private static func isAddOn(_ name: String) -> Bool {
        !tokens(name).isDisjoint(with: addOnWords)
    }

    /// Words in `left` that appear in `right`, counting a one-letter typo in a long word as 0.8.
    private static func matchedWeight(_ left: Set<String>, _ right: Set<String>) -> Double {
        var total = 0.0
        for word in left {
            if right.contains(word) {
                total += 1
            } else if word.count >= 5, right.contains(where: { $0.count >= 5 && editDistance($0, word) <= 1 }) {
                total += 0.8
            }
        }
        return total
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > 1 { return 2 }
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var row = [i + 1]
            for (j, y) in b.enumerated() {
                row.append(min(previous[j + 1] + 1, row[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = row
        }
        return previous[b.count]
    }

    private static func isWeak(_ name: String) -> Bool {
        weakTitles.contains(name.lowercased())
    }

    private static func folderHint(from executable: String?) -> String {
        guard let executable else { return "" }
        var url = URL(fileURLWithPath: executable).deletingLastPathComponent()
        for _ in 0..<5 {
            let name = url.lastPathComponent
            if name.isEmpty { break }
            if !isWeak(name) { return name }
            url.deleteLastPathComponent()
        }
        return ""
    }

    private static func richest(among names: [String], preferring fallback: String) -> String {
        let fallbackTokens = tokens(fallback)
        var best = fallback
        var bestScore = -1
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || isWeak(name) { continue }
            let words = tokens(name)
            if !fallbackTokens.isEmpty && words.isDisjoint(with: fallbackTokens) { continue }
            let value = words.subtracting(fallbackTokens).count * 10 + words.count
            if value > bestScore {
                bestScore = value
                best = name
            }
        }
        return best
    }

    private static func splitAlphanumeric(_ name: String) -> String {
        var text = ""
        var previous: Character?
        for character in name {
            if let previous {
                if previous.isLetter && character.isNumber { text.append(" ") }
                if previous.isNumber && character.isLetter { text.append(" ") }
            }
            text.append(character)
            previous = character
        }
        return text
    }

    private static func edition(_ name: String) -> (numbers: Set<String>, tags: Set<String>) {
        let words = tokens(name)
        var numbers: Set<String> = []
        for word in words {
            if let roman = romans[word] {
                numbers.insert(roman)
            } else if word.allSatisfy(\.isNumber), let value = Int(word),
                      (1...20).contains(value) || (1990...2035).contains(value) {
                numbers.insert(String(value))
            }
        }
        return (numbers, words.intersection(editionTags))
    }

    private static func isSequel(_ numbers: Set<String>) -> Bool {
        numbers.contains { value in
            guard let number = Int(value) else { return false }
            return (2...20).contains(number)
        }
    }
}
