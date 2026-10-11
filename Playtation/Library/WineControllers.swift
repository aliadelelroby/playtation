import Darwin
import Foundation

enum WineControllers {
    /// XInput hides the raw HID device so the pad shows under Connected (XInput devices).
    /// DirectInput leaves that raw device on the DirectInput list.
    static func apply(bottlePath: String, wineBinary: String, mode: String?) {
        let xinput: Bool
        switch mode {
        case "xinput": xinput = true
        case "dinput": xinput = false
        default: return
        }
        let systemPath = (bottlePath as NSString).appendingPathComponent("system.reg")
        let userPath = (bottlePath as NSString).appendingPathComponent("user.reg")
        guard let system = try? String(contentsOfFile: systemPath, encoding: .utf8),
              let user = try? String(contentsOfFile: userPath, encoding: .utf8) else { return }
        let nextSystem = rewriteSystem(system, xinput: xinput)
        let nextUser = rewriteJoysticks(user, xinput: xinput)
        guard nextSystem != system || nextUser != user else { return }
        restartPrefix(bottlePath: bottlePath, wineBinary: wineBinary)
        if let fresh = try? String(contentsOfFile: systemPath, encoding: .utf8) {
            try? rewriteSystem(fresh, xinput: xinput).write(to: URL(fileURLWithPath: systemPath), atomically: true, encoding: .utf8)
        }
        if let fresh = try? String(contentsOfFile: userPath, encoding: .utf8) {
            try? rewriteJoysticks(fresh, xinput: xinput).write(to: URL(fileURLWithPath: userPath), atomically: true, encoding: .utf8)
        }
    }

    private static func rewriteSystem(_ text: String, xinput: Bool) -> String {
        // Hidraw on makes the DualSense a raw DirectInput joystick. XInput hides that
        // device and maps the SDL gamepad onto the XInput list instead.
        var next = setWinebus(text, key: "Enable SDL", value: "dword:00000001")
        next = setWinebus(next, key: "DisableHidraw", value: xinput ? "dword:00000001" : "dword:00000000")
        next = setWinebus(next, key: "Map Controllers", value: xinput ? "dword:00000001" : "dword:00000000")
        return next
    }

    /// The Override button writes `"Wireless Controller"="override"`, which forces DirectInput.
    /// XInput removes that. DirectInput sets it.
    private static func rewriteJoysticks(_ text: String, xinput: Bool) -> String {
        let names = [
            "Wireless Controller",
            "DualSense Wireless Controller",
            "PS5 Controller",
            "Sony Interactive Entertainment Wireless Controller"
        ]
        var lines = text.components(separatedBy: "\n")
        let header = "[Software\\\\Wine\\\\DirectInput\\\\Joysticks]"
        var start = lines.firstIndex(where: { $0.hasPrefix(header) })
        if start == nil {
            lines.append(header)
            lines.append("")
            start = lines.count - 2
        }
        guard let start else { return text }
        var end = start + 1
        while end < lines.count, !lines[end].hasPrefix("[") { end += 1 }
        if xinput {
            lines = lines.enumerated().compactMap { index, line in
                index > start && index < end && line.contains("=\"override\"") ? nil : line
            }
        } else {
            for name in names {
                let wanted = "\"\(name)\"=\"override\""
                if let index = (start..<end).first(where: { lines[$0].hasPrefix("\"\(name)\"=") }) {
                    lines[index] = wanted
                } else {
                    lines.insert(wanted, at: end)
                    end += 1
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func setWinebus(_ text: String, key: String, value: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let header = "[System\\\\CurrentControlSet\\\\Services\\\\winebus]"
        guard let start = lines.firstIndex(where: { $0.hasPrefix(header) }) else { return text }
        var end = start + 1
        while end < lines.count, !lines[end].hasPrefix("[") { end += 1 }
        let wanted = "\"\(key)\"=\(value)"
        if let index = (start..<end).first(where: { lines[$0].hasPrefix("\"\(key)\"=") }) {
            lines[index] = wanted
        } else {
            lines.insert(wanted, at: end)
        }
        return lines.joined(separator: "\n")
    }

    private static func restartPrefix(bottlePath: String, wineBinary: String) {
        let server = ((wineBinary as NSString).deletingLastPathComponent as NSString).appendingPathComponent("wineserver")
        guard FileManager.default.isExecutableFile(atPath: server) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: server)
        task.arguments = ["-k"]
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = bottlePath
        task.environment = environment
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}
