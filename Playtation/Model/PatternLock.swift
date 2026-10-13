import CryptoKit
import Foundation

/// Sign-in patterns, kept as salted hashes on each profile. They guard the profile screen, not the Mac.
enum PatternLock {
    /// Where the single pattern lived before profiles.
    private static let legacyKey = "signInPattern"

    static func seal(_ dots: [Int]) -> String {
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        return "\(salt.base64EncodedString()):\(digest(dots, salt: salt))"
    }

    static func matches(_ dots: [Int], sealed: String?) -> Bool {
        guard let sealed else { return true }
        let parts = sealed.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let salt = Data(base64Encoded: parts[0]) else { return false }
        return digest(dots, salt: salt) == parts[1]
    }

    /// Hands over the pre-profiles pattern once, for the main user, and forgets it.
    static func takeLegacy() -> String? {
        let stored = UserDefaults.standard.string(forKey: legacyKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        return stored
    }

    private static func digest(_ dots: [Int], salt: Data) -> String {
        var data = salt
        data.append(contentsOf: dots.map { UInt8($0) })
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
