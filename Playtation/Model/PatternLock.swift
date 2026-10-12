import CryptoKit
import Foundation

/// The sign-in pattern, kept as a salted hash. It guards the profile screen, not the Mac.
enum PatternLock {
    private static let key = "signInPattern"

    static var isSet: Bool { UserDefaults.standard.string(forKey: key) != nil }

    static func save(_ dots: [Int]) {
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        UserDefaults.standard.set("\(salt.base64EncodedString()):\(digest(dots, salt: salt))", forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func matches(_ dots: [Int]) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: key) else { return true }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let salt = Data(base64Encoded: parts[0]) else { return false }
        return digest(dots, salt: salt) == parts[1]
    }

    private static func digest(_ dots: [Int], salt: Data) -> String {
        var data = salt
        data.append(contentsOf: dots.map { UInt8($0) })
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
