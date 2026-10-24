// ChatActivityIndicatorView.swift

import TDLibKit
import UIKit

// MARK: - ChatActivityIndicatorView

/// ChatTitleActivityNode's indicators, 24 × 16 pt before the activity's text: the typing dots, the voice waves, the
/// recording dot, the upload bar, the game's chomping dot and the sticker eyes, each redrawn through its cycle while
/// on screen.
final class ChatActivityIndicatorView: UIView {
    enum Kind: Equatable {
        case typing
        case recordingVoice
        case recordingVideo
        case uploading
        case playingGame
        case choosingSticker

        /// ChatTitleActivityIndicatorNode's duration for the kind.
        var duration: CFTimeInterval {
            switch self {
            case .recordingVoice,
                 .typing: 0.7
            case .playingGame,
                 .recordingVideo: 0.9
            case .uploading: 1.75
            case .choosingSticker: 2
            }
        }

        var easesInOut: Bool {
            self == .uploading || self == .recordingVideo
        }

        /// The indicator for TDLib's action, as ChatListTypingNode picks the state; an emoji interaction has none.
        init?(action: ChatAction) {
            switch action {
            case .chatActionTyping: self = .typing
            case .chatActionRecordingVoiceNote: self = .recordingVoice
            case .chatActionRecordingVideoNote: self = .recordingVideo
            case .chatActionRecordingVideo,
                 .chatActionUploadingDocument,
                 .chatActionUploadingPhoto,
                 .chatActionUploadingVideo,
                 .chatActionUploadingVideoNote,
                 .chatActionUploadingVoiceNote: self = .uploading
            case .chatActionStartPlayingGame: self = .playingGame
            case .chatActionChoosingSticker: self = .choosingSticker
            case .chatActionCancel,
                 .chatActionChoosingContact,
                 .chatActionChoosingLocation,
                 .chatActionWatchingAnimations: return nil
            }
        }
    }

    static let size = CGSize(width: 24, height: 16)

    override var isHidden: Bool {
        didSet { updateAnimation() }
    }

    var kind = Kind.typing {
        didSet {
            guard kind != oldValue else { return }
            startTime = CACurrentMediaTime()
            setNeedsDisplay()
        }
    }

    var color = UIColor.secondaryLabel {
        didSet { setNeedsDisplay() }
    }

    private var displayLink: CADisplayLink?
    private var startTime = CACurrentMediaTime()

    private var progress: CGFloat {
        let elapsed = (CACurrentMediaTime() - startTime) / kind.duration
        let linear = CGFloat(elapsed - floor(elapsed))
        return kind.easesInOut ? Self.easeInEaseOut(linear) : linear
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimation()
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let color = color.resolvedColor(with: traitCollection)
        switch kind {
        case .typing: Self.drawTyping(context, color: color, progress: progress)
        case .recordingVoice: Self.drawRecordingVoice(context, bounds: bounds, color: color, progress: progress)
        case .recordingVideo: Self.drawRecordingVideo(context, color: color, progress: progress)
        case .uploading: Self.drawUploading(context, color: color, progress: progress)
        case .playingGame: Self.drawPlaying(context, bounds: bounds, color: color, progress: progress)
        case .choosingSticker: Self.drawChoosingSticker(context, bounds: bounds, color: color, progress: progress)
        }
    }

    /// CAMediaTimingFunction's easeInEaseOut, the cubic Bézier through (0.42, 0) and (0.58, 1).
    private static func easeInEaseOut(_ x: CGFloat) -> CGFloat {
        func bezier(_ t: CGFloat, _ p1: CGFloat, _ p2: CGFloat) -> CGFloat {
            3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t
        }
        var low = CGFloat(0)
        var high = CGFloat(1)
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if bezier(mid, 0.42, 0.58) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, 0, 1)
    }

    // MARK: Drawing

    private static func interpolate(_ from: CGFloat, _ to: CGFloat, _ value: CGFloat) -> CGFloat {
        (1 - value) * from + value * to
    }

    /// ChatTypingActivityIndicatorNode: three dots 5.5 pt apart swelling from 3 to 4.5 pt in turn.
    private static func drawTyping(_ context: CGContext, color: UIColor, progress: CGFloat) {
        let minDiameter = CGFloat(3)
        let maxDiameter = CGFloat(4.5)
        func radius(_ offset: CGFloat) -> CGFloat {
            var value = progress + offset
            if value > 1 { value -= floor(value) }
            let diameter =
                if value < 0.4 {
                    interpolate(minDiameter, maxDiameter, value / 0.4)
                } else if value < 0.8 {
                    interpolate(maxDiameter, minDiameter, (value - 0.4) / 0.4)
                } else {
                    minDiameter
                }
            return (max(minDiameter, diameter) - minDiameter) / (maxDiameter - minDiameter) * 1.5
        }
        var alpha = CGFloat(1)
        color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        for (index, offset) in [CGFloat(0.4), 0.2, 0].enumerated() {
            let grow = radius(offset)
            context.setFillColor(color.withAlphaComponent((grow * 0.25 + 0.75) * alpha).cgColor)
            let center = CGPoint(x: 6 + CGFloat(index) * 5.5, y: 9)
            context.fillEllipse(in: CGRect(
                x: center.x - minDiameter / 2 - grow / 2,
                y: center.y - minDiameter / 2 - grow / 2,
                width: minDiameter + grow,
                height: minDiameter + grow,
            ))
        }
    }

    /// ChatRecordingVoiceActivityIndicatorNode: three 36° arcs spreading 5 pt apart and fading at the ends.
    private static func drawRecordingVoice(_ context: CGContext, bounds: CGRect, color: UIColor, progress: CGFloat) {
        context.setStrokeColor(color.cgColor)
        context.setLineCap(.round)
        context.setLineWidth(2)
        let delta = CGFloat(5)
        let origin = CGPoint(x: 3, y: bounds.height / 2 + 1)
        let angle = 18 * CGFloat.pi / 180
        for (index, power) in [CGFloat(50), 10, 10].enumerated() {
            let radius = progress * delta + CGFloat(index) * delta
            context.setAlpha(1 - pow(cos(radius / (3 * delta) * .pi), power))
            context.beginPath()
            context.addArc(center: origin, radius: radius, startAngle: -angle, endAngle: angle, clockwise: false)
            context.strokePath()
        }
        context.setAlpha(1)
    }

    /// ChatRecordingVideoActivityIndicatorNode: a dot pulsing between 3.5 and 2.84 pt.
    private static func drawRecordingVideo(_ context: CGContext, color: UIColor, progress: CGFloat) {
        let phase = progress < 0.5 ? progress / 0.5 : (1 - progress) / 0.5
        let radius = 3.5 - phase * 0.66
        context.setFillColor(color.cgColor)
        context.setAlpha(1 - phase * 0.6)
        context.fillEllipse(in: CGRect(x: 16 - radius, y: 9 - radius, width: radius * 2, height: radius * 2))
        context.setAlpha(1)
    }

    /// ChatUploadingActivityIndicatorNode: a 13 × 4 pt track crossed by a bar of its width.
    private static func drawUploading(_ context: CGContext, color: UIColor, progress: CGFloat) {
        let origin = CGPoint(x: 4 + 1 / 3, y: 7)
        let size = CGSize(width: 13, height: 4)
        var alpha = CGFloat(1)
        color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        context.saveGState()
        let track = UIBezierPath(roundedRect: CGRect(origin: origin, size: size), cornerRadius: 1.25)
        color.withAlphaComponent(alpha * 0.3).setFill()
        track.fill()
        track.addClip()
        color.setFill()
        let offset = interpolate(0, size.width * 2, progress)
        UIBezierPath(
            roundedRect: CGRect(origin: CGPoint(x: origin.x - size.width + offset, y: origin.y), size: size),
            cornerRadius: 1.25,
        ).fill()
        context.restoreGState()
    }

    /// ChatPlayingActivityIndicatorNode: a dot opening and closing its mouth on a row of 2 pt dots.
    private static func drawPlaying(_ context: CGContext, bounds: CGRect, color: UIColor, progress: CGFloat) {
        var alpha = CGFloat(1)
        color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        context.setFillColor(color.withAlphaComponent(alpha * 0.5).cgColor)
        let distance = CGFloat(4)
        var origin = CGPoint(x: (bounds.width - distance * 2) / 2 + 4, y: bounds.height / 2 + 1)
        let dotsProgress = CGFloat(Int(progress * 100) % 50) / 50
        let dotsX = 1.5 + origin.x - distance * dotsProgress
        let dot = CGFloat(1)
        context.fillEllipse(in: CGRect(x: dotsX - dot, y: origin.y - dot, width: dot * 2, height: dot * 2))
        context.fillEllipse(in: CGRect(x: dotsX - dot + distance, y: origin.y - dot, width: dot * 2, height: dot * 2))
        context.setAlpha(dotsProgress)
        context.fillEllipse(in: CGRect(
            x: dotsX - dot + distance * 2,
            y: origin.y - dot,
            width: dot * 2,
            height: dot * 2,
        ))
        context.setAlpha(1)
        let angle = 42 * CGFloat.pi / 180
        let radius = CGFloat(3.5)
        let closing = Int(progress * 4) % 2 == 1
        var bite = CGFloat(Int(progress * 100) % 25) / 25
        if closing { bite = 1 - bite }
        var startAngle = interpolate(0, -angle, bite)
        var endAngle = interpolate(0, angle, bite)
        if bite < .ulpOfOne {
            startAngle = .pi * 2
            endAngle = 0
        }
        origin.x = radius + 4.5
        context.setFillColor(color.cgColor)
        context.beginPath()
        context.move(to: origin)
        context.addArc(center: origin, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        context.fillPath()
    }

    /// ChatChoosingStickerActivityIndicatorNode: two eyes blinking and looking from side to side.
    private static func drawChoosingSticker(_ context: CGContext, bounds: CGRect, color: UIColor, progress: CGFloat) {
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        var height = progress * 4
        if height > 3 {
            height = 4 - height
        } else if height > 2 {
            height -= 2
            height *= height
        } else if height > 1 {
            height = 2 - height
        } else {
            height *= height
        }
        var pupil = progress * 4
        if pupil > 2 { pupil = 3 - pupil }
        pupil = min(1, max(0, pupil))
        pupil *= pupil
        var position = progress * 2
        if position > 1 { position = 2 - position }
        let eyeWidth = CGFloat(6)
        let eyeHeight = 11 - 2 * height
        let eyeOffset = -1 + position * 2
        let pupilSize = CGFloat(4)
        let pupilX = (-1 + pupil * 2) * eyeWidth / 4
        for center in [
            CGPoint(x: bounds.width / 2 - eyeWidth - 1 + eyeOffset, y: bounds.height / 2),
            CGPoint(x: bounds.width / 2 + 1 + eyeOffset, y: bounds.height / 2),
        ] {
            context.strokeEllipse(in: CGRect(
                x: center.x - eyeWidth / 2,
                y: center.y - eyeHeight / 2,
                width: eyeWidth,
                height: eyeHeight,
            ))
            context.fillEllipse(in: CGRect(
                x: center.x - pupilSize / 2 + pupilX,
                y: center.y - pupilSize / 2,
                width: pupilSize,
                height: pupilSize,
            ))
        }
    }

    fileprivate func tick() {
        setNeedsDisplay()
    }

    /// The node's POP animation: progress from 0 to 1 over the kind's duration, repeated while in a window.
    private func updateAnimation() {
        let running = window != nil && !isHidden
        if running, displayLink == nil {
            startTime = CACurrentMediaTime()
            let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !running {
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}

// MARK: - DisplayLinkTarget

/// Holds the indicator weakly, so the display link doesn't keep a row's view alive.
private final class DisplayLinkTarget: NSObject {
    private weak var view: ChatActivityIndicatorView?

    init(_ view: ChatActivityIndicatorView) {
        self.view = view
        super.init()
    }

    @objc func tick() {
        MainActor.assumeIsolated { view?.tick() }
    }
}
