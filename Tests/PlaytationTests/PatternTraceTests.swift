import CoreGraphics
import XCTest

final class PatternTraceTests: XCTestCase {
    private func trace(_ points: [(CGFloat, CGFloat)]) -> [Int] {
        var trace = PatternTrace()
        points.forEach { trace.move(to: CGPoint(x: $0.0, y: $0.1)) }
        return trace.dots
    }

    func testPicksUpDotsInOrder() {
        XCTAssertEqual(trace([(1 / 6, 1 / 6), (1 / 2, 1 / 6), (1 / 2, 1 / 2), (1 / 2, 5 / 6)]), [0, 1, 4, 7])
    }

    func testFastSwipeDoesNotSkipDots() {
        XCTAssertEqual(trace([(1 / 6, 5 / 6), (5 / 6, 5 / 6)]), [6, 7, 8])
    }

    func testJumpOverUsedDotKeepsOrder() {
        var trace = PatternTrace()
        trace.move(to: PatternTrace.center(of: 4))
        trace.lift()
        trace.move(to: PatternTrace.center(of: 0))
        trace.lift()
        trace.move(to: PatternTrace.center(of: 8))
        XCTAssertEqual(trace.dots, [4, 0, 8])
    }

    func testDiagonalBetweenNeighboursIgnoresCorner() {
        XCTAssertEqual(trace([(1 / 2, 1 / 6), (1 / 6, 1 / 2)]), [1, 3])
    }

    func testJumpOverUnusedMiddleTakesIt() {
        var trace = PatternTrace()
        trace.move(to: PatternTrace.center(of: 0))
        trace.lift()
        trace.move(to: PatternTrace.center(of: 8))
        trace.lift()
        trace.move(to: PatternTrace.center(of: 2))
        XCTAssertEqual(trace.dots, [0, 4, 8, 5, 2])
    }

    func testOpenShapeStaysOpen() {
        // A tick: down the left, across the bottom, up the right. Nothing joins the ends.
        var trace = PatternTrace()
        let path: [(CGFloat, CGFloat)] = [(1 / 6, 1 / 2), (1 / 3, 2 / 3), (1 / 2, 5 / 6), (2 / 3, 2 / 3), (5 / 6, 1 / 2), (5 / 6, 1 / 3), (5 / 6, 1 / 6)]
        path.forEach { trace.move(to: CGPoint(x: $0.0, y: $0.1)) }
        trace.lift()
        XCTAssertEqual(trace.dots, [3, 7, 5, 2])
    }

    func testStrayJumpDoesNotSweepUpDots() {
        var trace = PatternTrace()
        trace.move(to: PatternTrace.center(of: 6))
        trace.move(to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(trace.dots, [6, 4])
        trace.move(to: CGPoint(x: 0.85, y: 0.15))
        XCTAssertEqual(trace.dots, [6, 4, 2])
    }

    func testDotsAreNotRepeated() {
        XCTAssertEqual(trace([(1 / 6, 1 / 6), (1 / 2, 1 / 6), (1 / 6, 1 / 6)]), [0, 1])
    }
}
