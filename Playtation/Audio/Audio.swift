import AVFoundation
import Foundation

/// Navigation click, profile tones, back tone, and the quiet home theme.
@MainActor
final class ConsoleSound {
    static let shared = ConsoleSound()

    private var navData: Data?
    private var welcomeData: Data?
    private var hoverData: Data?
    private var confirmData: Data?
    private var backData: Data?
    private var menuData: Data?
    private var live: [AVAudioPlayer] = []
    private var music: AVAudioPlayer?
    private var welcomePlayer: AVAudioPlayer?
    private var lastHover = Date.distantPast
    /// Set while a game is in front. Blocks the theme and every UI tone.
    private var quiet = false

    nonisolated static func holdForGameSoon() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                shared.holdForGame()
            }
        }
    }

    private init() {
        navData = Self.resource("nav")
        if let boot = Self.resource("boot") {
            // boot.wav is three phrases: welcome, profile hover, then enter.
            welcomeData = Self.slice(boot, from: 0, to: 1.55)
            hoverData = Self.slice(boot, from: 1.70, to: 2.92)
            confirmData = Self.slice(boot, from: 2.996, to: nil)
        }
        backData = Self.wav(Self.backSamples())
        menuData = Self.wav(Self.menuSamples())
    }

    func tick(horizontal: Int? = nil, vertical: Int? = nil) {
        guard !quiet else { return }
        ConsoleFeel.shared.tick(horizontal: horizontal, vertical: vertical)
        guard let navData else { return }
        play(navData, volume: 0.4)
    }

    /// First phrase, when the profile screen appears.
    func welcome() {
        guard !quiet else { return }
        ConsoleFeel.shared.welcome()
        welcomePlayer?.stop()
        welcomePlayer = start(welcomeData, volume: 0.7)
    }

    /// Second phrase, when a profile is highlighted.
    func hover() {
        guard !quiet else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHover) > 0.35 else { return }
        lastHover = now
        ConsoleFeel.shared.tick()
        welcomePlayer?.stop()
        welcomePlayer = start(hoverData, volume: 0.65)
    }

    /// Third phrase, when a profile is chosen.
    func confirm() {
        guard !quiet else { return }
        ConsoleFeel.shared.confirm()
        welcomePlayer?.stop()
        welcomePlayer = nil
        _ = start(confirmData, volume: 0.75)
    }

    func back() {
        guard !quiet else { return }
        ConsoleFeel.shared.back()
        restoreMusic()
        guard let backData else { return }
        play(backData, volume: 0.8)
    }

    /// Curtain tone when the full-screen menu opens.
    func menu() {
        guard !quiet else { return }
        ConsoleFeel.shared.menu()
        music?.volume = 0.06
        guard let menuData else { return }
        play(menuData, volume: 0.7)
    }

    func restoreMusic() {
        guard music?.isPlaying == true else { return }
        music?.volume = 0.22
    }

    func startMusic() {
        guard !quiet else { return }
        if music?.isPlaying == true { return }
        let data = Self.wav(Self.themeSamples())
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.numberOfLoops = -1
        player.volume = 0.22
        player.prepareToPlay()
        player.play()
        music = player
    }

    func stopMusic() {
        music?.stop()
        music = nil
    }

    /// Stops every Playtation sound so nothing leaks into the game after we quit.
    func silence() {
        stopMusic()
        welcomePlayer?.stop()
        welcomePlayer = nil
        live.forEach { $0.stop() }
        live.removeAll()
    }

    /// Theme, clicks, and menu tones stay off until the shell is in front again.
    func holdForGame() {
        quiet = true
        silence()
    }

    func releaseForShell() {
        quiet = false
    }

    private func play(_ data: Data, volume: Float) {
        _ = start(data, volume: volume)
    }

    @discardableResult
    private func start(_ data: Data?, volume: Float) -> AVAudioPlayer? {
        guard !quiet, let data, let player = try? AVAudioPlayer(data: data) else { return nil }
        player.volume = volume
        player.prepareToPlay()
        player.play()
        live.removeAll { !$0.isPlaying }
        live.append(player)
        return player
    }

    /// Cuts a stereo 16-bit WAV and fades the new edges so the join doesn't click.
    private static func slice(_ data: Data, from startTime: Double, to endTime: Double?) -> Data? {
        guard let pcm = pcmRange(in: data) else { return nil }
        let rate = 48_000
        let frameBytes = 4
        let frames = (pcm.upperBound - pcm.lowerBound) / frameBytes
        let start = min(frames, max(0, Int(startTime * Double(rate))))
        let end = min(frames, endTime.map { Int($0 * Double(rate)) } ?? frames)
        guard end > start else { return nil }
        let byteCount = (end - start) * frameBytes
        let copied = Data(data[pcm.lowerBound + start * frameBytes..<(pcm.lowerBound + start * frameBytes + byteCount)])
        var samples = copied.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        let fade = min(rate / 80, samples.count / 4)
        if fade > 0 {
            for i in 0..<fade {
                let gainIn = Float(i) / Float(fade)
                let gainOut = Float(fade - i) / Float(fade)
                samples[i * 2] = Int16(Float(samples[i * 2]) * gainIn)
                samples[i * 2 + 1] = Int16(Float(samples[i * 2 + 1]) * gainIn)
                let j = samples.count / 2 - 1 - i
                samples[j * 2] = Int16(Float(samples[j * 2]) * gainOut)
                samples[j * 2 + 1] = Int16(Float(samples[j * 2 + 1]) * gainOut)
            }
        }
        return stereoWAV(samples)
    }

    private static func stereoWAV(_ interleaved: [Int16]) -> Data {
        let dataSize = interleaved.count * 2
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u32(_ value: UInt32) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 4))
        }
        func u16(_ value: UInt16) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 2))
        }
        ascii("RIFF")
        u32(UInt32(36 + dataSize))
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)
        u16(2)
        u32(48_000)
        u32(48_000 * 4)
        u16(4)
        u16(16)
        ascii("data")
        u32(UInt32(dataSize))
        interleaved.withUnsafeBufferPointer { buffer in
            data.append(buffer)
        }
        return data
    }

    private static func pcmRange(in data: Data) -> Range<Int>? {
        let marker = Data("data".utf8)
        guard let found = data.range(of: marker), data.count >= found.upperBound + 4 else { return nil }
        let bytes = [UInt8](data[found.upperBound..<(found.upperBound + 4)])
        let size = Int(UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24))
        let start = found.upperBound + 4
        let end = min(data.count, start + size)
        guard end > start else { return nil }
        return start..<end
    }

    private static func resource(_ name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func menuSamples() -> [Int16] {
        let rate = 44_100.0
        let frames = Int(rate * 0.62)
        return (0..<frames).map { i in
            let t = Double(i) / rate
            let drop = 196.0 * pow(0.5, t / 0.55)
            let body = sine(drop, t) * 0.34 + sine(drop * 0.5, t) * 0.18
            let tick = t < 0.04 ? sine(784, t) * (1 - t / 0.04) * 0.12 : 0
            let env = envelope(t, attack: 0.012, release: 0.58, peak: 0.62)
            return pack((body + tick) * env)
        }
    }

    private static func backSamples() -> [Int16] {
        let rate = 44_100.0
        let frames = Int(rate * 0.3)
        return (0..<frames).map { i in
            let t = Double(i) / rate
            let freq = t < 0.08 ? 329.63 : 261.63
            let tone = triangle(freq, t) * envelope(t, attack: 0.005, release: 0.25, peak: 0.28)
            return pack(tone)
        }
    }

    /// Soft A-minor-ish pad, looped. Ends fade so the repeat stays smooth.
    private static func themeSamples() -> [Int16] {
        let rate = 44_100.0
        let seconds = 8.0
        let frames = Int(rate * seconds)
        let notes = [110.0, 165.0, 220.0, 293.66, 330.0]
        return (0..<frames).map { i in
            let t = Double(i) / rate
            let edge = min(1, min(t, seconds - t) / 1.2)
            var sample = 0.0
            for (index, note) in notes.enumerated() {
                let weight = index == 0 ? 0.22 : 0.1
                sample += sine(note, t) * weight
            }
            let sway = 0.85 + 0.15 * sin(2 * .pi * t / seconds)
            return pack(sample * edge * sway * 0.35)
        }
    }

    private static func sine(_ hz: Double, _ t: Double) -> Double {
        sin(2 * .pi * hz * t)
    }

    private static func triangle(_ hz: Double, _ t: Double) -> Double {
        let p = (hz * t).truncatingRemainder(dividingBy: 1)
        return p < 0.5 ? (4 * p - 1) : (3 - 4 * p)
    }

    private static func envelope(_ t: Double, attack: Double, release: Double, peak: Double) -> Double {
        if t < 0 { return 0 }
        if t < attack { return peak * (t / attack) }
        let rest = max(0.001, release)
        return peak * exp(-3.2 * (t - attack) / rest)
    }

    private static func pack(_ sample: Double) -> Int16 {
        let clamped = max(-1, min(1, sample))
        return Int16(clamped * 32_000)
    }

    private static func wav(_ mono: [Int16]) -> Data {
        var stereo: [Int16] = []
        stereo.reserveCapacity(mono.count * 2)
        for sample in mono {
            stereo.append(sample)
            stereo.append(sample)
        }
        let dataSize = stereo.count * 2
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u32(_ value: UInt32) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 4))
        }
        func u16(_ value: UInt16) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 2))
        }
        ascii("RIFF")
        u32(UInt32(36 + dataSize))
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)
        u16(2)
        u32(44_100)
        u32(44_100 * 4)
        u16(4)
        u16(16)
        ascii("data")
        u32(UInt32(dataSize))
        stereo.withUnsafeBufferPointer { buffer in
            data.append(buffer)
        }
        return data
    }
}
