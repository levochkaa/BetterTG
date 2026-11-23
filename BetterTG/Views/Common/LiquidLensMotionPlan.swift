// LiquidLensMotionPlan.swift

import CoreGraphics
import Foundation

// MARK: - LiquidLensPositionSegment

/// Where the lens's glass is: moving from `from` at `startTime` to `to` over `duration`, along `progress` (the part of
/// the move done at a fraction of `duration`), or resting at `to` when `duration` is 0. Times are in
/// `LiquidLensMotionPlan`'s timeline.
///
/// A move that starts while the lens is already moving keeps its velocity: on top of the curve it carries the
/// difference between that velocity and the curve's own at its start, decaying like a critically damped spring that
/// settles within the move, and gone exactly at its end. The lens leaves with its momentum and still lands on time.
struct LiquidLensPositionSegment {
    /// How fast the carried velocity decays: a critically damped spring at this many radians per second of the move's
    /// duration settles (to 0.1%) within it.
    static let velocityDecayFactor = 7.0

    let from: CGPoint
    let to: CGPoint
    let startTime: Double
    let duration: Double
    let progress: (Double) -> CGFloat
    /// The velocity at `startTime`, in points per second.
    let initialVelocity: CGPoint

    private let carriedVelocity: CGPoint
    private let velocityDecay: Double

    var endTime: Double {
        startTime + duration
    }

    init(
        from: CGPoint,
        to: CGPoint,
        startTime: Double,
        duration: Double,
        progress: @escaping (Double) -> CGFloat,
        initialVelocity: CGPoint = CGPoint(),
    ) {
        self.from = from
        self.to = to
        self.startTime = startTime
        self.duration = max(0.0, duration)
        self.progress = progress
        self.initialVelocity = initialVelocity

        if self.duration > 0.0 {
            let fraction = 1.0e-4
            let slope = Double(progress(fraction) - progress(0.0)) / fraction / self.duration
            let curveVelocity = CGPoint(x: (to.x - from.x) * CGFloat(slope), y: (to.y - from.y) * CGFloat(slope))
            self.carriedVelocity = CGPoint(
                x: initialVelocity.x - curveVelocity.x,
                y: initialVelocity.y - curveVelocity.y,
            )
            self.velocityDecay = LiquidLensPositionSegment.velocityDecayFactor / self.duration
        } else {
            self.carriedVelocity = CGPoint()
            self.velocityDecay = 0.0
        }
    }

    static func resting(at position: CGPoint, time: Double) -> LiquidLensPositionSegment {
        LiquidLensPositionSegment(from: position, to: position, startTime: time, duration: 0.0, progress: { _ in 1.0 })
    }

    func position(at time: Double) -> CGPoint {
        if duration <= 0.0 || time >= endTime {
            return to
        }
        if time <= startTime {
            return from
        }
        let elapsed = time - startTime
        let progress = progress(elapsed / duration)
        let carried = CGFloat(carriedDisplacement(elapsed: elapsed))
        return CGPoint(
            x: from.x + (to.x - from.x) * progress + carriedVelocity.x * carried,
            y: from.y + (to.y - from.y) * progress + carriedVelocity.y * carried,
        )
    }

    /// The velocity at `time`, in points per second; zero when not moving.
    func velocity(at time: Double) -> CGPoint {
        if duration <= 0.0 || time >= endTime || time < startTime {
            return CGPoint()
        }
        let step = min(1.0e-4, duration * 0.25)
        let lower = max(startTime, time - step)
        let upper = min(endTime, time + step)
        if upper <= lower {
            return CGPoint()
        }
        let a = position(at: lower)
        let b = position(at: upper)
        return CGPoint(x: (b.x - a.x) / CGFloat(upper - lower), y: (b.y - a.y) / CGFloat(upper - lower))
    }

    /// The displacement per unit of carried velocity after `elapsed` seconds: `t·e^(−ωt)`, a critically damped spring
    /// released from rest with unit velocity, less the small cubic that takes out what is left of it at the end of the
    /// move, so that it starts with a slope of 1 and ends at 0 with a slope of 0.
    private func carriedDisplacement(elapsed: Double) -> Double {
        if carriedVelocity.x == 0.0, carriedVelocity.y == 0.0 {
            return 0.0
        }
        let duration = duration
        let decay = velocityDecay
        let endValue = duration * exp(-decay * duration)
        let endSlope = exp(-decay * duration) * (1.0 - decay * duration)
        let a = (3.0 * endValue - endSlope * duration) / (duration * duration)
        let b = (endSlope - 2.0 * endValue / duration) / (duration * duration)
        return elapsed * exp(-decay * elapsed) - (a * elapsed * elapsed + b * elapsed * elapsed * elapsed)
    }
}

/// The progress of a cubic bezier timing curve at `fraction` of its duration, as `CAMediaTimingFunction` computes it:
/// the curve from (0, 0) to (1, 1) with control points (x1, y1) and (x2, y2), solved for x.
func liquidLensBezierProgress(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ fraction: Double) -> CGFloat {
    if fraction <= 0.0 {
        return 0.0
    }
    if fraction >= 1.0 {
        return 1.0
    }
    func sample(_ a: Double, _ b: Double, _ s: Double) -> Double {
        let u = 1.0 - s
        return 3.0 * u * u * s * a + 3.0 * u * s * s * b + s * s * s
    }
    func slope(_ a: Double, _ b: Double, _ s: Double) -> Double {
        let u = 1.0 - s
        return 3.0 * u * u * a + 6.0 * u * s * (b - a) + 3.0 * s * s * (1.0 - b)
    }
    var s = fraction
    for _ in 0..<8 {
        let error = sample(x1, x2, s) - fraction
        if abs(error) < 1.0e-7 {
            return CGFloat(sample(y1, y2, s))
        }
        let derivative = slope(x1, x2, s)
        if abs(derivative) < 1.0e-6 {
            break
        }
        s -= error / derivative
    }
    var lower = 0.0
    var upper = 1.0
    s = fraction
    for _ in 0..<40 {
        let value = sample(x1, x2, s)
        if abs(value - fraction) < 1.0e-7 {
            break
        }
        if value < fraction {
            lower = s
        } else {
            upper = s
        }
        s = (lower + upper) * 0.5
    }
    return CGFloat(sample(y1, y2, s))
}

// MARK: - LiquidLensMotionState

/// The flex's state at an instant: the motion estimate and the springs.
struct LiquidLensMotionState {
    var time: Double
    var motion: LiquidLensMotion
    var animator: LiquidLensFlexAnimator

    init(
        time: Double,
        motion: LiquidLensMotion = LiquidLensMotion(),
        animator: LiquidLensFlexAnimator = LiquidLensFlexAnimator(),
    ) {
        self.time = time
        self.motion = motion
        self.animator = animator
    }

    /// One frame of the flex, as `_UIFlexInteraction` runs one per `UIUpdateLink` tick: while it is active it samples
    /// where the lens is and retargets its springs to the flex of that motion; otherwise its springs settle back.
    mutating func advance(to time: Double, segment: LiquidLensPositionSegment, isFlexActive: Bool, size: CGSize) {
        let deltaTime = time - self.time
        if deltaTime <= 0.0 {
            return
        }
        var target = LiquidLensFlex.identity
        if isFlexActive {
            motion.add(position: segment.position(at: time), timestamp: time)
            target = LiquidLensFlex.target(size: size, velocity: motion.velocity, acceleration: motion.acceleration)
        }
        animator.step(toward: target, size: size, isTracking: isFlexActive, deltaTime: deltaTime)
        self.time = time
    }
}

// MARK: - LiquidLensMotionPlan

/// The lens's motion worked out in advance, for Core Animation to play as keyframes: the position along `segment`
/// and the flex it produces, every 1/120 s from `start` until both are at rest. A change in the middle replaces the
/// plan with one that starts from `state(at:)` of this one, so the flex carries on where it is.
struct LiquidLensMotionPlan {
    static let frameDuration = 1.0 / 120.0
    /// A flex that keeps moving (the lens dragged around) is worked out this far ahead; the next change replans it.
    static let maxDuration = 3.0

    let segment: LiquidLensPositionSegment
    let isFlexActive: Bool
    let size: CGSize
    /// The flex at `startTime` and every frame after it.
    let states: [LiquidLensMotionState]

    var startTime: Double {
        states[0].time
    }

    var endTime: Double {
        states[states.count - 1].time
    }

    /// Whether the lens flexes at all during the plan.
    var hasFlex: Bool {
        states.contains(where: { $0.animator.flex != .identity })
    }

    /// The glass's positions from `startTime` to the end of the move, a frame apart, with their times from
    /// `startTime`; empty when it is not moving.
    var positionKeyframes: [(time: Double, position: CGPoint)] {
        let duration = segment.endTime - startTime
        if duration <= 0.0 {
            return []
        }
        let count = Int(ceil(duration / LiquidLensMotionPlan.frameDuration))
        var result = [(time: Double, position: CGPoint)]()
        result.reserveCapacity(count + 1)
        for frame in 0...count {
            let time = min(duration, Double(frame) * LiquidLensMotionPlan.frameDuration)
            result.append((time, segment.position(at: startTime + time)))
        }
        return result
    }

    init(start: LiquidLensMotionState, segment: LiquidLensPositionSegment, isFlexActive: Bool, size: CGSize) {
        self.segment = segment
        self.isFlexActive = isFlexActive
        self.size = size

        var states: [LiquidLensMotionState] = [start]
        // An inactive flex does not follow the lens: once it has settled, nothing is left to animate.
        if isFlexActive || !start.animator.isSettled {
            var state = start
            let maxFrames = Int(LiquidLensMotionPlan.maxDuration / LiquidLensMotionPlan.frameDuration)
            var frame = 1
            while frame <= maxFrames {
                let time = start.time + Double(frame) * LiquidLensMotionPlan.frameDuration
                state.advance(to: time, segment: segment, isFlexActive: isFlexActive, size: size)
                states.append(state)
                if time >= segment.endTime || !isFlexActive, state.animator.isSettled,
                   abs(state.motion.velocity.x) < 1.0, abs(state.motion.velocity.y) < 1.0
                {
                    break
                }
                frame += 1
            }
        }
        self.states = states
    }

    /// The flex as this plan has it at `time`: the frame before it, run on to `time`.
    func state(at time: Double) -> LiquidLensMotionState {
        if time <= startTime {
            return states[0]
        }
        let index = min(states.count - 1, Int((time - startTime) / LiquidLensMotionPlan.frameDuration))
        var state = states[index]
        state.advance(to: time, segment: segment, isFlexActive: isFlexActive, size: size)
        return state
    }
}
