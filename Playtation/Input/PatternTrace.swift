import CoreGraphics

/// Turns a finger path over a 3×3 grid into an ordered list of dots, the way a phone pattern lock does.
/// Points are in grid space: 0...1 on both axes, origin top left. Dots are numbered 0...8 row by row.
struct PatternTrace: Equatable {
    static let side = 3
    static let minimumDots = 4
    /// How close to a dot's center, in cell widths, the finger has to pass to pick it up.
    /// Small enough that a diagonal between two dots does not catch their neighbours.
    static let reach: CGFloat = 0.34
    /// Largest move between two samples, in grid units, that is still treated as one slide.
    static let maximumStep: CGFloat = 0.45

    private(set) var dots: [Int] = []
    /// Where the finger is now, or nil while it is lifted.
    private(set) var finger: CGPoint?

    var isEmpty: Bool { dots.isEmpty }

    static func center(of dot: Int) -> CGPoint {
        CGPoint(
            x: (CGFloat(dot % side) + 0.5) / CGFloat(side),
            y: (CGFloat(dot / side) + 0.5) / CGFloat(side)
        )
    }

    /// Moves the finger and returns true when that picked up at least one new dot.
    /// The path from the previous position is walked in small steps so a quick swipe cannot skip a dot.
    @discardableResult
    mutating func move(to point: CGPoint) -> Bool {
        let target = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        let before = dots.count
        var start = finger ?? target
        // A finger cannot cross most of the pad between two samples. A jump that big is a stray
        // sample or a new touch, so only the landing point counts, not the dots along the way.
        if hypot(target.x - start.x, target.y - start.y) > Self.maximumStep { start = target }
        let steps = max(1, Int((hypot(target.x - start.x, target.y - start.y) / 0.02).rounded(.up)))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            pickUp(near: CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
        }
        finger = target
        return dots.count > before
    }

    mutating func lift() {
        finger = nil
    }

    mutating func reset() {
        dots = []
        finger = nil
    }

    private mutating func pickUp(near point: CGPoint) {
        let n = CGFloat(Self.side)
        let col = min(Self.side - 1, Int(point.x * n))
        let row = min(Self.side - 1, Int(point.y * n))
        let dot = row * Self.side + col
        let center = Self.center(of: dot)
        guard hypot(point.x - center.x, point.y - center.y) * n <= Self.reach else { return }
        add(dot)
    }

    /// Adds a dot. Jumping straight over an unused dot (corner to corner, edge to edge) takes it too.
    private mutating func add(_ dot: Int) {
        guard !dots.contains(dot) else { return }
        if let last = dots.last {
            let (r1, c1) = (last / Self.side, last % Self.side)
            let (r2, c2) = (dot / Self.side, dot % Self.side)
            if (r1 + r2) % 2 == 0, (c1 + c2) % 2 == 0 {
                let middle = (r1 + r2) / 2 * Self.side + (c1 + c2) / 2
                if !dots.contains(middle) { dots.append(middle) }
            }
        }
        dots.append(dot)
    }
}
