import Darwin
import Foundation

/// Looks at live Mac processes so Home only says Running when the game is actually up.
enum ProcessProbe {
    private static let helpers: Set<String> = [
        "wine", "wine64", "wine32on64", "wineserver", "wineloader",
        "wine-preloader", "wine64-preloader", "start.exe", "explorer.exe",
        "services.exe", "rpcss.exe", "plugplay.exe", "winedevice.exe",
        "svchost.exe", "conhost.exe", "wineboot.exe", "rundll32.exe",
        "tabtip.exe", "msiexec.exe", "winedbg.exe", "cmd.exe",
        "steam.exe", "steamwebhelper.exe", "gameoverlayui.exe",
        "steamerrorreporter.exe", "steamservice.exe"
    ]

    static func gameRunning(winePID: Int32, executablePath: String?, windowsStart: String) -> Bool {
        !gameProcessIDs(winePID: winePID, executablePath: executablePath, windowsStart: windowsStart).isEmpty
            || !namedGameIDs(executablePath: executablePath, windowsStart: windowsStart).isEmpty
    }

    /// PIDs of the actual game .exe under this Wine launch, not wineserver helpers.
    static func gameProcessIDs(winePID: Int32, executablePath: String?, windowsStart: String) -> [pid_t] {
        guard winePID > 0 else { return [] }
        let want = expectedNames(executablePath: executablePath, windowsStart: windowsStart)
        let rows = list()
        if !rows.contains(where: { $0.pid == winePID }) { return [] }
        let tree = Set(descendants(of: winePID, rows: rows))
        return rows.compactMap { row in
            guard tree.contains(row.pid) || row.pid == winePID else { return nil }
            if matches(row.name, want: want) { return row.pid }
            if row.pid != winePID, isGameLike(row.name) { return row.pid }
            return nil
        }
    }

    static func namedGameIDs(executablePath: String?, windowsStart: String) -> [pid_t] {
        let want = expectedNames(executablePath: executablePath, windowsStart: windowsStart)
        guard !want.isEmpty else { return [] }
        return list().compactMap { row in
            matches(row.name, want: want) ? row.pid : nil
        }
    }

    /// Every Mac process spawned from this Wine launch, including preloaders that own the window.
    static func wineTreeIDs(winePID: Int32) -> [pid_t] {
        guard winePID > 0 else { return [] }
        let rows = list()
        guard rows.contains(where: { $0.pid == winePID }) else { return [] }
        return descendants(of: winePID, rows: rows)
    }

    private static func expectedNames(executablePath: String?, windowsStart: String) -> Set<String> {
        var names: Set<String> = []
        if let executablePath {
            names.insert(URL(fileURLWithPath: executablePath).lastPathComponent.lowercased())
        }
        let start = URL(fileURLWithPath: windowsStart.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
        if start.hasSuffix(".exe") { names.insert(start) }
        return names.filter { !$0.isEmpty && !helpers.contains($0) }
    }

    private static func matches(_ raw: String, want: Set<String>) -> Bool {
        let name = raw.lowercased()
        if want.contains(name) { return true }
        return want.contains { candidate in
            name.count >= 12 && (candidate.hasPrefix(name) || name.hasPrefix(candidate))
        }
    }

    private static func isGameLike(_ raw: String) -> Bool {
        let name = raw.lowercased()
        if helpers.contains(name) { return false }
        return name.hasSuffix(".exe") || name.contains(".exe")
    }

    private struct Row {
        var pid: Int32
        var ppid: Int32
        var name: String
    }

    private static func descendants(of root: Int32, rows: [Row]) -> [Int32] {
        let children = Dictionary(grouping: rows, by: \.ppid)
        var seen: Set<Int32> = [root]
        var stack = [root]
        while let pid = stack.popLast() {
            for child in children[pid] ?? [] where seen.insert(child.pid).inserted {
                stack.append(child.pid)
            }
        }
        return Array(seen)
    }

    private static func list() -> [Row] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.stride)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard filled > 0 else { return [] }
        let count = Int(filled) / MemoryLayout<pid_t>.stride
        return pids.prefix(count).compactMap { pid -> Row? in
            guard pid > 0 else { return nil }
            var info = proc_bsdshortinfo()
            let size = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
            let written = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size)
            guard written == size else { return nil }
            return Row(pid: pid, ppid: Int32(info.pbsi_ppid), name: cString(info.pbsi_comm))
        }
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
