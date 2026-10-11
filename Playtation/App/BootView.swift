import AppKit
import SwiftUI

/// PS5 boot: the family logo, then the controller prompt. Nothing continues until a
/// controller is connected and the PS button is pressed.
struct BootView: View {
    @EnvironmentObject private var model: ConsoleModel
    @State private var started: Date?
    @State private var leavingAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let elapsed = started.map { timeline.date.timeIntervalSince($0) } ?? 0
            let frozen = leavingAt.flatMap { leave in started.map { leave.timeIntervalSince($0) } }
            BootScene(
                elapsed: frozen.map { min(elapsed, $0) } ?? elapsed,
                leave: leavingAt.map { timeline.date.timeIntervalSince($0) } ?? 0,
                armed: model.bootReady && model.controllerConnected && leavingAt == nil,
                onPress: { model.signalBoot() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            started = Date()
            model.armBootPrompt(after: BootTiming.prompt)
        }
        .onDisappear { model.disarmBootPrompt() }
        .onChange(of: model.bootCue) { _, cue in
            guard cue > 0, leavingAt == nil else { return }
            beginExit()
        }
    }

    private func beginExit() {
        leavingAt = Date()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            model.presentWelcome()
        }
    }
}

private enum BootTiming {
    /// Family logo, then a beat of black, then the controller — same beats as the reference intro.
    static let logo: TimeInterval = 3
    static let pause: TimeInterval = 2
    static var prompt: TimeInterval { logo + pause }
    static let textFade: TimeInterval = 2
    static let imageFade: TimeInterval = 5
}

private struct BootScene: View {
    var elapsed: TimeInterval
    var leave: TimeInterval
    var armed: Bool
    var onPress: () -> Void

    var body: some View {
        GeometryReader { geo in
            let vmin = min(geo.size.width, geo.size.height)
            ZStack {
                if elapsed < BootTiming.logo {
                    Image(systemName: "playstation.logo")
                        .font(.system(size: 160, weight: .regular))
                        .foregroundStyle(.white)
                } else {
                    prompt(in: geo.size, vmin: vmin)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    private func prompt(in size: CGSize, vmin: CGFloat) -> some View {
        let gap: CGFloat = 64
        let pad: CGFloat = 32
        let inner = size.height - pad * 2 - gap * 2
        let unit = max(0, inner / 7)
        let row3Mid = pad + unit + gap + unit + gap + unit * 2.5
        let since = max(0, elapsed - BootTiming.prompt)
        let introOpacity = min(1, since / BootTiming.textFade)
        let imageOpacity = min(1, since / BootTiming.imageFade)
        let motion = controllerMotion(since)
        let eased = smooth(min(1, max(0, leave)))
        let shown = elapsed >= BootTiming.prompt

        return ZStack {
            ControllerPrompt(
                vmin: vmin,
                wipe: motion.wipe,
                pulse: motion.pulse,
                imageOpacity: shown ? imageOpacity : 0,
                logoScale: motion.scale,
                armed: armed,
                onPress: onPress
            )
            .position(x: size.width / 2, y: row3Mid)
            .scaleEffect(1 + eased * 2)
            .opacity(1 - eased)

            Button(action: onPress) {
                VStack(spacing: 32) {
                    PS5Wordmark()
                        .frame(width: vmin * 0.22, height: vmin * 0.06)
                    toast(size: max(13, vmin * 0.02))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity((shown ? introOpacity : 0) * (1 - eased))
            .position(x: size.width / 2, y: pad + unit + gap + unit / 2)
            .zIndex(2)
        }
    }

    private func toast(size: CGFloat) -> some View {
        (
            Text("Press the ").font(PS.font(size, .regular))
                + Text("PS").font(PS.font(size, .bold))
                + Text(" button to enable your controller").font(PS.font(size, .regular))
        )
        .foregroundStyle(.white)
        .padding(.horizontal, size * 2)
        .padding(.vertical, size)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    /// The reference intro loops a 3s circle wipe, an expanding pulse, and a PS-button press.
    private func controllerMotion(_ since: TimeInterval) -> (wipe: Double, pulse: CGFloat, scale: CGFloat) {
        let phase = since.truncatingRemainder(dividingBy: 3) / 3
        let wipe = phase < 0.45 ? phase / 0.45 : 1
        let pulse = phase < 0.5 ? 1 + 68 * (phase / 0.5) : 69
        let scale = phase < 0.45 ? 1 + 0.1 * (phase / 0.45) : 1.1
        return (wipe, CGFloat(pulse), CGFloat(scale))
    }

    private func smooth(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }
}

private struct ControllerPrompt: View {
    var vmin: CGFloat
    var wipe: Double
    var pulse: CGFloat
    var imageOpacity: Double
    var logoScale: CGFloat
    var armed: Bool
    var onPress: () -> Void

    /// Sized to sit in the frame with space around it, including fullscreen.
    private var imageWidth: CGFloat { vmin * 0.82 }
    private var imageHeight: CGFloat { imageWidth * (3540 / 5260) }
    /// The PS button is the open pad under the speaker dots, at the artwork's center.
    private var buttonDrop: CGFloat { 0 }

    var body: some View {
        let radius = hypot(imageWidth, imageHeight) / 2 * (0.05 + 0.95 * wipe)
        let logo = max(22, vmin * 0.038)
        ZStack {
            Image("DualSense")
                .resizable()
                .interpolation(.high)
                .frame(width: imageWidth, height: imageHeight)
                .mask {
                    Circle()
                        .frame(width: radius * 2, height: radius * 2)
                        .offset(y: buttonDrop)
                }
                .opacity(imageOpacity)

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: .black.opacity(0), location: 0),
                            .init(color: .black, location: 0.32),
                            .init(color: .black, location: 1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 16, height: 16)
                .scaleEffect(pulse)
                .opacity(imageOpacity)
                .offset(y: buttonDrop)
                .allowsHitTesting(false)

            Button(action: onPress) {
                Image(systemName: "playstation.logo")
                    .font(.system(size: logo, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: logo * 4.4, height: logo * 4.4)
                    .contentShape(Circle())
            }
            .buttonStyle(PSPressStyle(armed: armed))
            .scaleEffect(logoScale)
            .offset(y: buttonDrop)
            .opacity(imageOpacity)
            .onHover { inside in
                if inside && armed {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .accessibilityLabel("PlayStation")
        }
        .frame(width: imageWidth, height: imageHeight)
    }
}

private struct PSPressStyle: ButtonStyle {
    var armed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && armed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The PS5 wordmark from the reference icon, drawn so it stays sharp at any size.
private struct PS5Wordmark: View {
    var body: some View {
        PS5Mark()
            .fill(.white)
            .accessibilityHidden(true)
    }
}

private struct PS5Mark: Shape {
    func path(in rect: CGRect) -> Path {
        let raw = SVGDraw.path(from: Self.icon)
        let scale = min(rect.width / 320, rect.height / 100)
        let fitted = CGSize(width: 320 * scale, height: 100 * scale)
        let origin = CGPoint(
            x: rect.midX - fitted.width / 2,
            y: rect.midY - fitted.height / 2
        )
        let transform = CGAffineTransform(translationX: origin.x, y: origin.y)
            .scaledBy(x: scale, y: scale)
        return raw.applying(transform)
    }

    static let icon = "M207.11,22.44V43a9.37,9.37,0,0,0,9.37,9.37h49.91a9.43,9.43,0,0,1,0,18.85H207.11v6.32H272a15.75,15.75,0,0,0,0-31.49H222.8A3.77,3.77,0,0,1,219,42.31V28.76h66.54V22.44Zm-46.16,0A14.92,14.92,0,0,0,146,37.36V62.81a8.43,8.43,0,0,1-8.43,8.43H108.89v6.32H143A14.92,14.92,0,0,0,158,62.64V37.19a8.43,8.43,0,0,1,8.43-8.43h29.25V22.44Zm-128.68,0v6.32h60a8.66,8.66,0,1,1,0,17.31H47.18A14.92,14.92,0,0,0,32.27,61V77.56H44.19V60.82a8.42,8.42,0,0,1,8.43-8.43H97.84a15,15,0,1,0,0-29.95Z"
}

private enum SVGDraw {
    static func path(from d: String) -> Path {
        var path = Path()
        var index = d.startIndex
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func skip() {
            while index < d.endIndex {
                let character = d[index]
                if character == " " || character == "," || character == "\n" || character == "\t" {
                    index = d.index(after: index)
                } else {
                    break
                }
            }
        }

        func readNumber() -> CGFloat? {
            skip()
            guard index < d.endIndex else { return nil }
            if d[index].isLetter { return nil }
            var end = index
            if d[end] == "+" || d[end] == "-" { end = d.index(after: end) }
            var sawDigit = false
            var sawDot = false
            while end < d.endIndex {
                let character = d[end]
                if character.isNumber {
                    sawDigit = true
                    end = d.index(after: end)
                } else if character == "." && !sawDot {
                    sawDot = true
                    end = d.index(after: end)
                } else {
                    break
                }
            }
            guard sawDigit, let value = Double(d[index..<end]) else { return nil }
            index = end
            return CGFloat(value)
        }

        while index < d.endIndex {
            skip()
            if index >= d.endIndex { break }
            if d[index].isLetter {
                command = d[index]
                index = d.index(after: index)
            }
            switch command {
            case "M", "m":
                guard let x = readNumber(), let y = readNumber() else { return path }
                let point = command == "m"
                    ? CGPoint(x: current.x + x, y: current.y + y)
                    : CGPoint(x: x, y: y)
                path.move(to: point)
                current = point
                start = point
                command = command == "m" ? "l" : "L"
            case "L", "l":
                guard let x = readNumber(), let y = readNumber() else { return path }
                let point = command == "l"
                    ? CGPoint(x: current.x + x, y: current.y + y)
                    : CGPoint(x: x, y: y)
                path.addLine(to: point)
                current = point
            case "H", "h":
                guard let x = readNumber() else { return path }
                current.x = command == "h" ? current.x + x : x
                path.addLine(to: current)
            case "V", "v":
                guard let y = readNumber() else { return path }
                current.y = command == "v" ? current.y + y : y
                path.addLine(to: current)
            case "Z", "z":
                path.closeSubpath()
                current = start
            case "A", "a":
                guard let rx = readNumber(), let ry = readNumber(), let rotation = readNumber(),
                      let large = readNumber(), let sweep = readNumber(),
                      let x = readNumber(), let y = readNumber() else { return path }
                let end = command == "a"
                    ? CGPoint(x: current.x + x, y: current.y + y)
                    : CGPoint(x: x, y: y)
                addArc(
                    to: &path,
                    from: current,
                    to: end,
                    rx: rx,
                    ry: ry,
                    rotation: rotation,
                    large: large != 0,
                    sweep: sweep != 0
                )
                current = end
            default:
                index = d.index(after: index)
            }
        }
        return path
    }

    private static func addArc(
        to path: inout Path,
        from start: CGPoint,
        to end: CGPoint,
        rx rxIn: CGFloat,
        ry ryIn: CGFloat,
        rotation: CGFloat,
        large: Bool,
        sweep: Bool
    ) {
        if start == end { return }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            path.addLine(to: end)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        var rxsq = rx * rx
        var rysq = ry * ry
        let lambda = (x1p * x1p) / rxsq + (y1p * y1p) / rysq
        if lambda > 1 {
            let grown = sqrt(lambda)
            rx *= grown
            ry *= grown
            rxsq = rx * rx
            rysq = ry * ry
        }
        let sign: CGFloat = large == sweep ? -1 : 1
        let numerator = max(0, rxsq * rysq - rxsq * y1p * y1p - rysq * x1p * x1p)
        let denominator = rxsq * y1p * y1p + rysq * x1p * x1p
        let coefficient = sign * sqrt(numerator / max(denominator, 0.0000001))
        let cxp = coefficient * rx * y1p / ry
        let cyp = coefficient * -ry * x1p / rx
        let center = CGPoint(
            x: cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2,
            y: sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2
        )
        func vectorAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var angle = acos(min(1, max(-1, dot / max(length, 0.0000001))))
            if ux * vy - uy * vx < 0 { angle = -angle }
            return angle
        }
        let theta = vectorAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = vectorAngle(
            (x1p - cxp) / rx,
            (y1p - cyp) / ry,
            (-x1p - cxp) / rx,
            (-y1p - cyp) / ry
        )
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        for segment in 0..<segments {
            let t1 = theta + step * CGFloat(segment)
            let t2 = t1 + step
            let alpha = sin(step) * (sqrt(4 + 3 * pow(tan(step / 2), 2)) - 1) / 3
            func point(_ t: CGFloat) -> CGPoint {
                CGPoint(
                    x: center.x + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: center.y + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi
                )
            }
            func derivative(_ t: CGFloat) -> CGPoint {
                CGPoint(
                    x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi
                )
            }
            let from = point(t1)
            let to = point(t2)
            let fromSlope = derivative(t1)
            let toSlope = derivative(t2)
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + alpha * fromSlope.x, y: from.y + alpha * fromSlope.y),
                control2: CGPoint(x: to.x - alpha * toSlope.x, y: to.y - alpha * toSlope.y)
            )
        }
    }
}
