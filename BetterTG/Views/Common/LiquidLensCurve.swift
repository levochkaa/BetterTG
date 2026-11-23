// LiquidLensCurve.swift

import CoreGraphics
import Foundation

// MARK: - LiquidLensCurve

/// The curve a lens move follows, so that the lens's planned position (`LiquidLensPositionSegment`) stays in step with
/// what the caller animates alongside it: the part of the move done at a fraction of `duration`.
enum LiquidLensCurve: Equatable {
    /// A cubic bezier timing curve, as `CAMediaTimingFunction(controlPoints:)` draws it.
    case bezier(duration: TimeInterval, x1: Double, y1: Double, x2: Double, y2: Double)
    /// `UIView.animate(springDuration:bounce:)`: a spring whose response is `duration`, played until it settles.
    case spring(duration: TimeInterval, bounce: CGFloat)

    // MARK: Internal

    /// Telegram's `.spring(duration: 0.4)`, which Display draws as this bezier at any duration other than its two
    /// native spring ones.
    static let `default` = LiquidLensCurve.bezier(duration: 0.4, x1: 0.380, y1: 0.700, x2: 0.125, y2: 1.000)

    // MARK: Private

    private static let settlingThreshold: CGFloat = 0.001

    /// How long the move takes: a spring's until it settles within a thousandth of the distance.
    var duration: TimeInterval {
        switch self {
        case .bezier(let duration, _, _, _, _):
            duration
        case .spring(let duration, let bounce):
            Self.settlingDuration(response: duration, bounce: bounce)
        }
    }

    /// SwiftUI's and UIKit's `Spring(duration:bounce:)`: a unit mass whose stiffness gives a period of `response`,
    /// damped by `1 - bounce`, or by `1 / (1 + bounce)` for a negative bounce.
    private static func dampingRatio(bounce: CGFloat) -> Double {
        bounce >= 0 ? Double(1 - bounce) : Double(1 / (1 + bounce))
    }

    /// The spring's position at `time`, released from 0 at rest towards 1.
    private static func springValue(response: TimeInterval, bounce: CGFloat, time: Double) -> CGFloat {
        let omega = 2 * Double.pi / max(0.001, response)
        let zeta = dampingRatio(bounce: bounce)
        let value: Double
        if abs(zeta - 1) < 1e-6 {
            value = 1 - exp(-omega * time) * (1 + omega * time)
        } else if zeta < 1 {
            let dampedOmega = omega * sqrt(1 - zeta * zeta)
            let envelope = exp(-zeta * omega * time)
            value = 1 - envelope * (cos(dampedOmega * time) + zeta * omega / dampedOmega * sin(dampedOmega * time))
        } else {
            let root = sqrt(zeta * zeta - 1)
            let r1 = -omega * (zeta - root)
            let r2 = -omega * (zeta + root)
            value = 1 - (r2 * exp(r1 * time) - r1 * exp(r2 * time)) / (r2 - r1)
        }
        return CGFloat(value)
    }

    /// The last moment the spring is farther than `settlingThreshold` from its target.
    private static func settlingDuration(response: TimeInterval, bounce: CGFloat) -> TimeInterval {
        let step = 1.0 / 1000.0
        let limit = max(0.001, response) * 10
        var settled = step
        var time = step
        while time <= limit {
            if abs(1 - springValue(response: response, bounce: bounce, time: time)) > settlingThreshold {
                settled = time + step
            }
            time += step
        }
        return settled
    }

    /// The progress function over `duration`: 0 at the start, exactly 1 at the end.
    func makeProgress() -> (Double) -> CGFloat {
        switch self {
        case .bezier(_, let x1, let y1, let x2, let y2):
            return { liquidLensBezierProgress(x1, y1, x2, y2, $0) }
        case .spring(let response, let bounce):
            let duration = Self.settlingDuration(response: response, bounce: bounce)
            // What is left of the spring when it is cut off goes in evenly, so the move ends exactly at its target.
            let remainder = 1 - Self.springValue(response: response, bounce: bounce, time: duration)
            return { fraction in
                if fraction <= 0 { return 0 }
                if fraction >= 1 { return 1 }
                let value = Self.springValue(response: response, bounce: bounce, time: fraction * duration)
                return value + remainder * CGFloat(fraction)
            }
        }
    }
}
