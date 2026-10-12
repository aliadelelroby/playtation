import Combine
import SwiftUI

/// Profile gate shown after boot: star field, clock, and the signed-in Mac account.
struct WelcomeView: View {
    @EnvironmentObject private var model: ConsoleModel

    var body: some View {
        ZStack {
            StarField()
            RadialGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03), .clear],
                center: UnitPoint(x: 0.10, y: 0.05),
                startRadius: 0,
                endRadius: 620
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if model.patternPrompt == .unlock {
                unlock
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                profile
                    .transition(.opacity)
            }

            WelcomeClock()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 45)
                .padding(.trailing, 60)

            if model.signingIn {
                signingOverlay
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.patternPrompt == .unlock)
    }

    private var unlock: some View {
        VStack(spacing: 30) {
            HStack(spacing: 14) {
                ProfileMark(image: model.accountImage, name: model.accountName, side: 44)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                Text(model.accountName)
                    .font(PS.font(19, .regular))
                    .foregroundStyle(.white)
            }
            PatternCaption(ink: .white)
            PatternGrid(ink: .white, accent: Color(red: 0.25, green: 0.5, blue: 1), side: 300)
            HStack(spacing: 24) {
                hint("hand.draw", "Draw on touchpad")
                hint("circle", "Back")
            }
            .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private func hint(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(label).font(PS.font(13, .medium))
        }
    }

    private var profile: some View {
        VStack(spacing: 50) {
            VStack(spacing: 12) {
                Text("Welcome Back to PlayStation")
                    .font(PS.font(42, .regular))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                Text("Who's using this controller?")
                    .font(PS.font(19, .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .opacity(model.welcomeIntroduced ? 1 : 0)
            .offset(y: model.welcomeIntroduced ? 0 : -24)

            ProfileCard(name: model.accountName, image: model.accountImage)
                .scaleEffect(model.welcomeIntroduced ? 1.1 : 0.6)
                .opacity(model.welcomeIntroduced ? 1 : 0)
                .onHover { inside in
                    if inside { model.hoverWelcome() }
                }
                .onTapGesture { model.confirmWelcome() }
        }
    }

    private var signingOverlay: some View {
        ZStack {
            Color.black
            TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                let pulse = abs(sin(timeline.date.timeIntervalSinceReferenceDate * .pi))
                Image(systemName: "playstation.logo")
                    .font(.system(size: 78, weight: .regular))
                    .foregroundStyle(.white)
                    .opacity(0.3 + pulse * 0.7)
            }
        }
        .ignoresSafeArea()
    }
}

private struct ProfileCard: View {
    var name: String
    var image: NSImage?

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                ProfileMark(image: image, name: name, side: 168)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                glare
            }
            .frame(width: 180, height: 180)
            .shadow(color: Color(red: 0, green: 0.26, blue: 1).opacity(0.75), radius: 22)
            Text(name)
                .font(PS.font(21, .regular))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.25), radius: 8)
        }
    }

    private var glare: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
            let travel = cycle < 0.3 ? cycle / 0.3 : 1
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 46, height: 280)
                .rotationEffect(.degrees(30))
                .offset(x: -160 + CGFloat(travel) * 320)
        }
        .frame(width: 180, height: 180)
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}

private struct WelcomeClock: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(label)
            .font(PS.font(22, .regular))
            .tracking(0.5)
            .foregroundStyle(Color.white.opacity(0.9))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .onReceive(timer) { now = $0 }
    }

    private var label: String {
        let hour = Calendar.current.component(.hour, from: now)
        let minute = Calendar.current.component(.minute, from: now)
        let suffix = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h, minute, suffix)
    }
}

private struct StarField: View {
    private let stars: [Star] = Star.field(count: 180)
    private let clouds: [Cloud] = Cloud.field()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.008, green: 0.012, blue: 0.031)))
                let width = size.width
                let height = size.height
                for cloud in clouds {
                    let span = width + CGFloat(cloud.radius * 2)
                    var x = CGFloat(cloud.x) * width + CGFloat(time * cloud.drift)
                    x = x.truncatingRemainder(dividingBy: span)
                    if x < 0 { x += span }
                    let y = CGFloat(cloud.y) * height
                    let radius = CGFloat(cloud.radius)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [cloud.color, .clear]),
                            center: CGPoint(x: rect.midX, y: rect.midY),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
                for star in stars {
                    var x = CGFloat(star.x) * width + CGFloat(time * star.vx)
                    var y = CGFloat(star.y) * height + CGFloat(time * star.vy)
                    x = x.truncatingRemainder(dividingBy: width)
                    y = y.truncatingRemainder(dividingBy: height)
                    if x < 0 { x += width }
                    if y < 0 { y += height }
                    let twinkle = 0.35 + 0.65 * abs(sin(time * star.twinkle + star.phase))
                    let side = CGFloat(star.size)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: side, height: side)),
                        with: .color(.white.opacity(star.opacity * twinkle))
                    )
                    if star.size > 1.6 {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - side, y: y - side, width: side * 3, height: side * 3)),
                            with: .color(.white.opacity(0.12 * twinkle))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct Star {
    var x, y, size, opacity, vx, vy, twinkle, phase: Double

    static func field(count: Int) -> [Star] {
        var seed: UInt64 = 0xC0FFEE
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1
            return Double(seed >> 33) / Double(UInt32.max)
        }
        return (0..<count).map { _ in
            Star(
                x: next(),
                y: next(),
                size: 0.6 + next() * 2.2,
                opacity: 0.25 + next() * 0.75,
                vx: (next() - 0.5) * 4,
                vy: (next() - 0.5) * 3,
                twinkle: 0.6 + next() * 1.4,
                phase: next() * .pi * 2
            )
        }
    }
}

private struct Cloud {
    var x, y, radius, drift: Double
    var color: Color

    static func field() -> [Cloud] {
        [
            Cloud(x: 0.15, y: 0.2, radius: 420, drift: 6, color: Color(red: 0.19, green: 0.04, blue: 0.35).opacity(0.22)),
            Cloud(x: 0.72, y: 0.18, radius: 480, drift: -4, color: Color(red: 0.04, green: 0.1, blue: 0.35).opacity(0.2)),
            Cloud(x: 0.48, y: 0.82, radius: 360, drift: 3, color: Color(red: 0.35, green: 0.04, blue: 0.19).opacity(0.12)),
            Cloud(x: 0.88, y: 0.7, radius: 300, drift: -5, color: Color(red: 0, green: 0.26, blue: 1).opacity(0.1))
        ]
    }
}
