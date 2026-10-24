// ContextMenuMotion.swift

import CoreGraphics
import Foundation

// MARK: - ContextMenuMotion

/// Touch and motion model of the iOS 27.0 system context menu, recovered from UIKitCore 24A434 in
/// /Users/lev/Developer/CustomContextMenu (App/MenuMotion.swift, Research/Interaction/README.md).
/// Constants come from that disassembly and LLDB readback; none is tuned by eye.
enum ContextMenuMotion {
    /// _UITouchDurationObservingGestureRecognizer: minimumDurationRequired and allowableMovement.
    static let highlightDelay: TimeInterval = 0.15
    static let allowableMovement: CGFloat = 20
    /// Hold duration before the menu opens: 0.4 s on iPhone, 0.325 s on iPad.
    static let phoneHoldDuration: TimeInterval = 0.4
    static let padHoldDuration: TimeInterval = 0.325
    /// com.apple.UIKit.PreviewPlatterPan hysteresis.
    static let panHysteresis: CGFloat = 10
    /// com.apple.UIKit.ContextMenuDismissalTap allowableMovement and maximumTapDuration.
    static let dismissTapMovement: CGFloat = 45
    static let dismissTapDuration: TimeInterval = 1.5
    /// _UIContextMenuSelectionDelayGestureRecognizer timer.
    static let selectionDelay: TimeInterval = 0.15
    /// _UIGravityWellEffect spring, damping 0.6 and response 0.4.
    static let pressSpringDamping = 0.6
    static let pressSpringResponse = 0.4

    static func holdDuration(isPad: Bool) -> TimeInterval {
        isPad ? padHoldDuration : phoneHoldDuration
    }

    /// _UIGravityWellEffect _updateToProgress:state:. Zero until the highlight delay, then linear to 1 at the
    /// hold duration, and it keeps growing past it.
    static func pressProgress(elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        let raw = elapsed / duration
        let delay = highlightDelay / duration
        return CGFloat(min(1, max(0, (raw - delay) / (1 - delay))) + max(0, raw - 1))
    }

    /// The pressed view grows by 8 pt on its longest side at full progress.
    static func pressScale(size: CGSize, progress: CGFloat) -> CGFloat {
        let edge = max(size.width, size.height, 1)
        return 1 + progress * (max(0.9, (edge + 8) / edge) - 1)
    }

    /// _rubberBandedTranslationForGestureTranslation: with rubberbandingEdges 15 and one detent: radial,
    /// tear-off threshold 15, rubber-banding coefficient 0.2.
    static func rubberBand(_ translation: CGPoint) -> CGPoint {
        let distance = hypot(translation.x, translation.y)
        guard distance > 0 else { return .zero }
        let radius = 15 * (1 - 1 / (1 + distance / 15 * 0.2))
        return CGPoint(x: translation.x / distance * radius, y: translation.y / distance * radius)
    }

    /// The preview follows the finger from the first pan location inside it and never moves toward the menu.
    static func platterOffset(location: CGPoint, anchor: CGPoint, menuIsBelow: Bool = true) -> CGPoint {
        let offset = rubberBand(CGPoint(x: location.x - anchor.x, y: location.y - anchor.y))
        return CGPoint(x: offset.x, y: menuIsBelow ? min(offset.y, 0) : max(offset.y, 0))
    }
}

// MARK: - ContextMenuSpring

/// Closed-form damped oscillator. Retargeting keeps position and velocity, so it stays continuous at 60 and
/// 120 Hz.
struct ContextMenuSpring {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat

    var isSettled: Bool { abs(value - target) < 0.0001 && abs(velocity) < 0.001 }

    init(_ value: CGFloat) {
        self.value = value
        self.target = value
    }

    mutating func step(_ dt: TimeInterval, response: Double, damping: Double) {
        guard dt > 0 else { return }
        let omega = 2 * Double.pi / response
        let x = Double(value - target)
        let v = Double(velocity)
        let t = min(dt, 0.1)
        if damping < 1 {
            let decay = damping * omega
            let frequency = omega * sqrt(1 - damping * damping)
            let b = (v + decay * x) / frequency
            let wave = x * cos(frequency * t) + b * sin(frequency * t)
            let derivative = frequency * (b * cos(frequency * t) - x * sin(frequency * t))
            value = target + CGFloat(exp(-decay * t) * wave)
            velocity = CGFloat(exp(-decay * t) * (derivative - decay * wave))
        } else {
            let b = v + omega * x
            value = target + CGFloat((x + b * t) * exp(-omega * t))
            velocity = CGFloat((v - omega * b * t) * exp(-omega * t))
        }
        if isSettled {
            value = target
            velocity = 0
        }
    }
}

// MARK: - ContextMenuTouchSession

/// One touch while the menu is up, mirroring the native recognizers: PreviewPlatterPan (preview or menu,
/// 10 pt), ContextMenuDismissalTap (45 pt, 1.5 s), the 0.15 s selection delay for touches that begin in the
/// menu and the action-scrubbing handoff for touches that begin outside it.
struct ContextMenuTouchSession {
    enum Origin {
        case initiatingPreview
        case preview
        case menu
        case outside
    }

    enum Release: Equatable {
        case keepOpen
        case select(Int)
        case dismiss
    }

    let origin: Origin
    private(set) var start: CGPoint
    private(set) var startTime: TimeInterval
    private(set) var maxDistance: CGFloat = 0
    private(set) var panning = false
    /// _initialLocationInsidePreview: the first pan location inside the preview frame.
    private(set) var panAnchor: CGPoint?
    var highlighted: Int?

    /// Whether the action under the finger at release counts.
    var selectsOnRelease: Bool { origin == .menu || hasHandedOff }

    private var hasHandedOff: Bool { maxDistance > ContextMenuMotion.panHysteresis }

    init(origin: Origin, start: CGPoint, time: TimeInterval) {
        self.origin = origin
        self.start = start
        self.startTime = time
    }

    /// The press ended and the menu opened under the same finger; pan hysteresis restarts there.
    mutating func restart(at point: CGPoint, time: TimeInterval) {
        start = point
        startTime = time
        maxDistance = 0
    }

    mutating func move(to point: CGPoint, insidePreview: Bool) {
        maxDistance = max(maxDistance, hypot(point.x - start.x, point.y - start.y))
        if origin != .outside, !panning, maxDistance > ContextMenuMotion.panHysteresis { panning = true }
        if panning, panAnchor == nil, insidePreview { panAnchor = point }
    }

    /// Touches that begin on the menu wait for the selection delay; on release the action under them counts. Every
    /// other touch, including the finger that opened the menu, reaches the actions through the scrubbing handoff,
    /// which needs the finger to move past its hysteresis first. A finger resting where a lifted preview put the
    /// menu under it therefore selects nothing. The handoff hysteresis is not read back in the source; it uses the
    /// PreviewPlatterPan value, and all 12 native release cases move well past it.
    func allowsHighlight(at time: TimeInterval) -> Bool {
        origin == .menu ? time - startTime >= ContextMenuMotion.selectionDelay : hasHandedOff
    }

    func release(at time: TimeInterval) -> Release {
        if let highlighted { return .select(highlighted) }
        let duration = time - startTime
        switch origin {
        case .initiatingPreview,
             .menu:
            return .keepOpen
        case .preview:
            return !panning && duration <= ContextMenuMotion.dismissTapDuration ? .dismiss : .keepOpen
        case .outside:
            return maxDistance <= ContextMenuMotion.dismissTapMovement
                && duration <= ContextMenuMotion.dismissTapDuration ? .dismiss : .keepOpen
        }
    }
}
