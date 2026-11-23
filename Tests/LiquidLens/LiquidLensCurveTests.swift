// LiquidLensCurveTests.swift

import CoreGraphics

/// The curves a lens move follows: Telegram's default bezier, and UIKit's spring, which must end exactly on target so
/// that the lens lands where its bounds animation does.
final class LiquidLensCurveTests: XCTestCase {
    func testDefaultIsDisplaysSpringBezier() {
        let progress = LiquidLensCurve.default.makeProgress()
        XCTAssertEqual(LiquidLensCurve.default.duration, 0.4)
        XCTAssertEqual(progress(0.1), 0.205670047, accuracy: 0.000001)
        XCTAssertEqual(progress(0.5), 0.930837858, accuracy: 0.000001)
    }

    func testSpringEndsOnTarget() {
        for bounce: CGFloat in [-0.2, 0, 0.15, 0.3] {
            let curve = LiquidLensCurve.spring(duration: 0.4, bounce: bounce)
            let progress = curve.makeProgress()
            XCTAssertEqual(progress(0), 0)
            XCTAssertEqual(progress(1), 1)
            XCTAssertEqual(progress(0.9999), 1, accuracy: 0.002)
            XCTAssertGreaterThan(curve.duration, 0.4)
            XCTAssertLessThan(curve.duration, 4)
        }
    }

    /// A critically damped spring of 0.4 s settles within a thousandth after 9.23 / (2π / 0.4) s, and never passes
    /// its target; a bounce of 0.15 (damping ratio 0.85) passes it by up to e^(−π·0.85/√(1−0.85²)) ≈ 0.63%, a little
    /// less where the cut-off spring's remainder is spread over the move.
    func testSpringShape() {
        let critical = LiquidLensCurve.spring(duration: 0.4, bounce: 0)
        XCTAssertEqual(critical.duration, 0.588, accuracy: 0.003)
        let criticalProgress = critical.makeProgress()
        var previous: CGFloat = 0
        for frame in 0...120 {
            let value = criticalProgress(Double(frame) / 120)
            XCTAssertTrue(value >= previous)
            XCTAssertTrue(value <= 1)
            previous = value
        }
        let bouncy = LiquidLensCurve.spring(duration: 0.4, bounce: 0.15).makeProgress()
        let peak = (0...120).map { bouncy(Double($0) / 120) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1.004)
        XCTAssertLessThan(peak, 1.0064)
    }
}
