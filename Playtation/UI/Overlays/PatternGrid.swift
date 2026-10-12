import SwiftUI

/// The 3×3 sign-in grid. Drawn with the DualSense touchpad; the pointer can drag across it too.
struct PatternGrid: View {
    @EnvironmentObject private var model: ConsoleModel
    var ink: Color
    var accent: Color
    var side: CGFloat = 300

    private var color: Color { model.patternFailed ? PS.circle : accent }

    var body: some View {
        let trace = model.pattern
        ZStack {
            Canvas { context, size in
                let points = trace.dots.map { point(PatternTrace.center(of: $0), in: size) }
                var path = Path()
                if let first = points.first {
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    if let finger = trace.finger, !model.patternFailed {
                        path.addLine(to: point(finger, in: size))
                    }
                }
                context.stroke(path, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                for dot in 0..<(PatternTrace.side * PatternTrace.side) {
                    let center = point(PatternTrace.center(of: dot), in: size)
                    if trace.dots.contains(dot) {
                        context.fill(circle(center, 30), with: .color(color.opacity(0.28)))
                    }
                    context.fill(circle(center, 9), with: .color(trace.dots.contains(dot) ? color : ink))
                }
                if let finger = trace.finger {
                    context.fill(circle(point(finger, in: size), 6), with: .color(ink.opacity(0.35)))
                }
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    model.patternPointer(CGPoint(x: drag.location.x / side, y: drag.location.y / side))
                }
                .onEnded { _ in model.patternLift() }
        )
        .modifier(Shake(amount: CGFloat(model.patternShake)))
        .animation(.linear(duration: 0.4), value: model.patternShake)
    }

    private func point(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// Header and status line shown above the grid.
struct PatternCaption: View {
    @EnvironmentObject private var model: ConsoleModel
    var ink: Color

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(PS.font(26, .regular))
                .foregroundStyle(ink)
            Text(model.patternMessage ?? detail)
                .font(PS.font(15, .regular))
                .foregroundStyle(model.patternFailed ? PS.circle : ink.opacity(0.6))
                .animation(nil, value: model.patternMessage)
        }
        .multilineTextAlignment(.center)
    }

    private var title: String {
        switch model.patternPrompt {
        case .create: return "Draw a sign-in pattern"
        case .confirm: return "Draw it again to confirm"
        default: return "Draw your pattern"
        }
    }

    private var detail: String {
        switch model.patternPrompt {
        case .create: return "Use the touchpad and connect at least \(PatternTrace.minimumDots) dots, then lift your finger."
        case .confirm: return "Use the same pattern you just drew."
        default: return "Use the touchpad on your controller."
        }
    }
}

/// Settings panel for setting a new pattern.
struct PatternSetupOverlay: View {
    @EnvironmentObject private var model: ConsoleModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { model.cancelPattern() }
            VStack(spacing: 28) {
                PatternCaption(ink: .black)
                PatternGrid(ink: .black, accent: PS.triangle, side: 280)
                HStack(spacing: 24) {
                    hint("hand.draw", "Draw on touchpad")
                    hint("xmark", "Done")
                    hint("circle", "Cancel")
                }
                .foregroundStyle(.black.opacity(0.55))
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: Corner.panel, style: .continuous).fill(PS.panel))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        }
    }

    private func hint(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(label).font(PS.font(13, .medium))
        }
    }
}

private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}
