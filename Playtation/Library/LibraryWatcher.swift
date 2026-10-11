import AppKit
import CoreServices

/// Keeps the library current without a manual rescan: watches the CrossOver bottles, the Steam
/// library folders, mounted drives and the clock, and calls `onChange` once things settle.
final class LibraryWatcher {
    var onChange: (() -> Void)?

    private var stream: FSEventStreamRef?
    private var roots: [String] = []
    private var pending: DispatchWorkItem?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "playtation.library-watcher")

    /// Paths worth a rescan. Everything else under a bottle (game saves, Wine registry) is noise.
    private static let markers = [
        "/desktopdata/cxmenu/", "/steamapps/appmanifest_", "libraryfolders.vdf", "cxbottle.conf", "/Start Menu/"
    ]

    static func bottleRoots() -> [String] {
        [NSHomeDirectory() + "/Library/Application Support/CrossOver/Bottles", "/Library/Application Support/CrossOver/Bottles"]
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    func start() {
        update(extra: [])
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.schedule(after: 2.0)
            })
        }
        // Safety net for changes the file events can't see, such as a game installed on an unmounted drive.
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            self?.schedule(after: 0.1)
        }
    }

    /// Restarts the stream when the set of watched folders changes (a new Steam library, a new bottle).
    func update(extra: [String]) {
        let next = Array(Set(Self.bottleRoots() + extra)).sorted()
        guard next != roots else { return }
        roots = next
        stop()
        guard !next.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<LibraryWatcher>.fromOpaque(info).takeUnretainedValue()
            // Only valid because the stream is created with kFSEventStreamCreateFlagUseCFTypes.
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.handle(Array(list.prefix(count)))
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, next as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func handle(_ paths: [String]) {
        let bottleParents = Set(Self.bottleRoots())
        let relevant = paths.contains { path in
            if bottleParents.contains((path as NSString).deletingLastPathComponent) { return true }
            return Self.markers.contains { path.contains($0) }
        }
        if relevant { schedule(after: 1.2) }
    }

    private func schedule(after delay: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange?() }
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
        timer?.invalidate()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
