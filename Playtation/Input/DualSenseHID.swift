import AppKit
import Foundation
import IOKit.hid

/// GameController often leaves the DualSense PS button unpublished on macOS.
/// This reads the HID report so a press still reaches boot, Home, and the
/// always-on controller helper after Playtation quits.
final class DualSenseHID {
    static let shared = DualSenseHID()

    var onPS: ((Bool) -> Void)?

    private var manager: IOHIDManager?
    private var buffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private var down = false

    func start() {
        guard manager == nil else { return }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDVendorIDKey as String: 0x054C, kIOHIDProductIDKey as String: 0x0CE6],
            [kIOHIDVendorIDKey as String: 0x054C, kIOHIDProductIDKey as String: 0x0DF2]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matching as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DualSenseHID>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DualSenseHID>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, ctx)
        IOHIDManagerRegisterInputReportCallback(mgr, { context, _, _, _, reportID, report, length in
            guard let context, length > 0 else { return }
            Unmanaged<DualSenseHID>.fromOpaque(context).takeUnretainedValue()
                .ingest(reportID: Int(reportID), report: report, length: Int(length))
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
            guard let context else { return }
            Unmanaged<DualSenseHID>.fromOpaque(context).takeUnretainedValue().ingest(value: value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerRegisterInputReportCallback(mgr, nil, nil)
        IOHIDManagerRegisterInputValueCallback(mgr, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        buffers.values.forEach { $0.deallocate() }
        buffers.removeAll()
        manager = nil
        down = false
    }

    private func attach(_ device: IOHIDDevice) {
        let key = ObjectIdentifier(device)
        if let existing = buffers.removeValue(forKey: key) {
            existing.deallocate()
        }
        let size: Int
        if let number = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber {
            size = max(number.intValue, 128)
        } else {
            size = 128
        }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
        buffers[key] = buffer
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { context, _, _, _, reportID, report, length in
            guard let context, length > 0 else { return }
            Unmanaged<DualSenseHID>.fromOpaque(context).takeUnretainedValue()
                .ingest(reportID: Int(reportID), report: report, length: Int(length))
        }, ctx)
    }

    private func detach(_ device: IOHIDDevice) {
        let key = ObjectIdentifier(device)
        if let buffer = buffers.removeValue(forKey: key) {
            buffer.deallocate()
        }
        if down {
            down = false
            onPS?(false)
        }
    }

    private func ingest(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let isPS =
            (page == 0x09 && (usage == 12 || usage == 13 || usage == 14)) ||
            (page == 0x01 && usage == 0x85) ||
            (page == 0x0C && (usage == 0x0223 || usage == 0x0040))
        guard isPS else { return }
        setPS(IOHIDValueGetIntegerValue(value) != 0)
    }

    private func ingest(reportID: Int, report: UnsafeMutablePointer<UInt8>, length: Int) {
        let bytes = UnsafeBufferPointer(start: report, count: length)
        guard let pressed = Self.psPressed(reportID: reportID, bytes: bytes) else { return }
        setPS(pressed)
    }

    private func setPS(_ pressed: Bool) {
        guard pressed != down else { return }
        down = pressed
        if Thread.isMainThread {
            onPS?(pressed)
        } else {
            DispatchQueue.main.async { self.onPS?(pressed) }
        }
    }

    /// USB report 0x01 and Bluetooth report 0x31. PS is bit 0 of the third button byte.
    private static func psPressed(reportID: Int, bytes: UnsafeBufferPointer<UInt8>) -> Bool? {
        let id = reportID != 0 ? reportID : Int(bytes.first ?? 0)
        if id == 0x31 || bytes.first == 0x31 {
            let offset = bytes.first == 0x31 ? 12 : 11
            guard bytes.count > offset else { return nil }
            return bytes[offset] & 0x01 != 0
        }
        if bytes.count > 10, bytes[0] == 0x01 {
            return bytes[10] & 0x01 != 0
        }
        if (id == 0x01 || id == 0) && bytes.count > 9 {
            return bytes[9] & 0x01 != 0
        }
        return nil
    }
}

/// Games Overlay still gets the PS press. We let the event through, then close overlay and open Playtation.
enum HomeButtonSystem {
    static func restoreDelivery() {
        CFPreferencesSetAppValue(
            "bluetoothPrefsMenuLongPressAction" as CFString,
            nil,
            "com.apple.GameController" as CFString
        )
        CFPreferencesAppSynchronize("com.apple.GameController" as CFString)
    }

    static func dismissOverlay() {
        let ids = ["com.apple.games", "com.apple.GameTrampoline"]
        for id in ids {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
                app.hide()
                app.forceTerminate()
            }
        }
    }

    static var gamesIsFrontmost: Bool {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == "com.apple.games" {
            return true
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.games").contains(where: \.isActive)
    }
}
