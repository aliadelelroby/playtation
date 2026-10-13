import AppKit
import Collaboration
import SwiftUI

/// Users: who is signed in, what they see, and managing them from Settings > Users.
extension ConsoleModel {
    var currentProfile: Profile {
        profiles.first { $0.id == profileID } ?? profiles.first ?? Profile(id: Profile.ownerID, name: "")
    }

    /// The main user manages everyone; other users can only change their own name and color.
    var signedInAsOwner: Bool { currentProfile.isOwner }

    var otherProfiles: [Profile] { profiles.filter { !$0.isOwner } }

    func displayName(of profile: Profile) -> String {
        if !profile.name.isEmpty { return profile.name }
        return ScreenshotTour.isOn ? "Player" : NSFullUserName()
    }

    /// Only the main user has a picture: the Mac account's.
    func image(of profile: Profile) -> NSImage? {
        guard profile.isOwner, !ScreenshotTour.isOn else { return nil }
        return CBIdentity(name: NSUserName(), authority: CBIdentityAuthority.default())?.image
    }

    func canPlay(_ game: Game) -> Bool {
        guard !currentProfile.isOwner, let users = records[game.id]?.users else { return true }
        return users.contains(profileID)
    }

    func updateProfile(_ id: String, _ mutate: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&profiles[index])
        ProfileStore.save(profiles)
    }

    func recordPlay(_ gameID: String) {
        updateProfile(profileID) {
            var stat = $0.played[gameID] ?? PlayStat()
            stat.lastPlayed = Date()
            stat.playCount += 1
            $0.played[gameID] = stat
        }
    }

    /// Left and right on the profile screen.
    func stepProfile(_ delta: Int) {
        guard profiles.count > 1 else {
            hoverWelcome()
            return
        }
        let index = profiles.firstIndex { $0.id == profileID } ?? 0
        let next = index + delta
        guard profiles.indices.contains(next) else {
            ConsoleFeel.shared.bump()
            return
        }
        ConsoleSound.shared.tick(horizontal: delta)
        ConsoleFeel.shared.tick()
        profileID = profiles[next].id
    }

    /// A click on a card: the first picks it, the second signs in.
    func pickProfile(_ id: String) {
        guard phase == .welcome, !signingIn, !patternOffer else { return }
        if profileID == id {
            confirmWelcome()
        } else {
            ConsoleSound.shared.tick()
            profileID = id
        }
    }

    // MARK: Settings > Users

    enum UserAction: Equatable {
        case rename, color, clearPattern, remove

        var title: String {
            switch self {
            case .rename: return "Rename"
            case .color: return "Change color"
            case .clearPattern: return "Remove sign-in pattern"
            case .remove: return "Remove user"
            }
        }
    }

    var usersRowCount: Int { profiles.count + (signedInAsOwner && profiles.count < Profile.limit ? 1 : 0) }

    func userActions(for id: String) -> [UserAction] {
        guard let profile = profiles.first(where: { $0.id == id }) else { return [] }
        var actions: [UserAction] = [.rename, .color]
        // Your own pattern lives in System; this is how the main user clears a forgotten one.
        if signedInAsOwner, !profile.isOwner, profile.pattern != nil { actions.append(.clearPattern) }
        if signedInAsOwner, !profile.isOwner { actions.append(.remove) }
        return actions
    }

    func confirmUsersRow() {
        if settingsRow < profiles.count {
            let profile = profiles[settingsRow]
            guard signedInAsOwner || profile.id == profileID else {
                ConsoleFeel.shared.bump()
                banner = "Only \(displayName(of: profiles[0])) can change other users."
                return
            }
            openUserMenu(profile.id)
        } else if signedInAsOwner {
            beginNameEntry(.newUser)
        }
    }

    func openUserMenu(_ id: String) {
        ConsoleSound.shared.confirm()
        userMenuIndex = 0
        confirmUserRemove = false
        withAnimation(.easeOut(duration: 0.2)) { userMenuID = id }
    }

    func closeUserMenu() {
        guard userMenuID != nil else { return }
        ConsoleSound.shared.back()
        confirmUserRemove = false
        withAnimation(.easeOut(duration: 0.2)) { userMenuID = nil }
    }

    func stepUserMenu(_ delta: Int) {
        guard let id = userMenuID else { return }
        let count = userActions(for: id).count
        let next = min(count - 1, max(0, userMenuIndex + delta))
        guard next != userMenuIndex else {
            ConsoleFeel.shared.bump()
            return
        }
        ConsoleSound.shared.tick(vertical: delta)
        confirmUserRemove = false
        userMenuIndex = next
    }

    func confirmUserMenu() {
        guard let id = userMenuID else { return }
        let actions = userActions(for: id)
        guard actions.indices.contains(userMenuIndex) else { return }
        switch actions[userMenuIndex] {
        case .rename:
            withAnimation(.easeOut(duration: 0.2)) { userMenuID = nil }
            beginNameEntry(.rename(id))
        case .color:
            ConsoleSound.shared.tick()
            updateProfile(id) { $0.color = ($0.color + 1) % Profile.palette.count }
        case .clearPattern:
            ConsoleSound.shared.confirm()
            updateProfile(id) {
                $0.pattern = nil
                $0.patternOffered = false
            }
            userMenuIndex = 0
            banner = "Pattern removed. \(name(for: id)) can set a new one when signing in."
        case .remove:
            guard confirmUserRemove else {
                ConsoleFeel.shared.bump()
                confirmUserRemove = true
                return
            }
            removeUser(id)
        }
    }

    func removeUser(_ id: String) {
        guard signedInAsOwner, id != Profile.ownerID else { return }
        let name = name(for: id)
        ConsoleSound.shared.confirm()
        withAnimation(.easeOut(duration: 0.2)) {
            userMenuID = nil
            profiles.removeAll { $0.id == id }
        }
        confirmUserRemove = false
        ProfileStore.save(profiles)
        for (gameID, record) in records where record.users?.contains(id) == true {
            records[gameID]?.users = record.users?.filter { $0 != id }
        }
        LibraryStore.save(records)
        settingsRow = min(settingsRow, usersRowCount - 1)
        banner = "Removed \(name)."
    }

    private func name(for id: String) -> String {
        profiles.first { $0.id == id }.map(displayName(of:)) ?? "User"
    }

    // MARK: Names on the on-screen keyboard

    func beginNameEntry(_ target: KeyboardTarget) {
        ConsoleSound.shared.confirm()
        if case .rename(let id) = target, let profile = profiles.first(where: { $0.id == id }) {
            nameDraft = displayName(of: profile)
        } else {
            nameDraft = ""
        }
        kbTarget = target
        kbMode = .letters
        kbShift = nameDraft.isEmpty
        kbRow = 2
        kbCol = 5
        withAnimation(.easeOut(duration: 0.2)) { searching = true }
    }

    func finishNameEntry() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ConsoleFeel.shared.bump()
            return
        }
        ConsoleSound.shared.confirm()
        switch kbTarget {
        case .newUser:
            let used = Set(profiles.map(\.color))
            let color = (0..<Profile.palette.count).first { !used.contains($0) } ?? profiles.count % Profile.palette.count
            profiles.append(Profile(id: UUID().uuidString, name: name, color: color))
            ProfileStore.save(profiles)
            settingsRow = profiles.count - 1
            banner = "Added \(name). Pick their profile when Playtation starts."
        case .rename(let id):
            updateProfile(id) { $0.name = name }
        case .search:
            break
        }
        closeNameEntry()
    }

    func closeNameEntry() {
        withAnimation(.easeOut(duration: 0.2)) { searching = false }
        kbTarget = .search
        nameDraft = ""
        kbShift = false
    }

    // MARK: Game settings > Players

    func playersRowCount() -> Int { signedInAsOwner ? 1 + otherProfiles.count : 1 }

    /// Row 0 is Everyone; the rest switch one user on or off for this game.
    func toggleAccess(_ game: Game, row: Int) {
        guard signedInAsOwner, !otherProfiles.isEmpty else {
            ConsoleFeel.shared.bump()
            return
        }
        let everyone = otherProfiles.map(\.id)
        updateRecord(game.id) { record in
            if row == 0 {
                record.users = nil
                return
            }
            let index = row - 1
            guard everyone.indices.contains(index) else { return }
            var users = record.users ?? everyone
            if let at = users.firstIndex(of: everyone[index]) {
                users.remove(at: at)
            } else {
                users.append(everyone[index])
            }
            record.users = Set(users) == Set(everyone) ? nil : users
        }
    }
}
