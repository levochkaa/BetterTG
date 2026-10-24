// PhotoEditorSliderView.swift

import UIKit

// MARK: - PhotoEditorColors

/// TGPhotoEditorInterfaceAssets' colors for the tools, with the app's tint where Telegram's editor uses its accent.
enum PhotoEditorColors {
    static let accent = UIColor.systemBlue
    /// `panelBackgroundColor` and `toolbarTransparentBackgroundColor`.
    static let panelBackground = UIColor(white: 0, alpha: 0.9)
    /// `editorItemTitleColor`.
    static let itemTitle = UIColor(white: 0x80 / 255, alpha: 1)
    /// `editorActiveItemTitleColor`.
    static let activeItemTitle = UIColor.white
    /// `sliderBackColor`.
    static let sliderBack = UIColor(white: 0x80 / 255, alpha: 0.6)
    /// `sliderTrackColor`.
    static let sliderTrack = UIColor(white: 0xCC / 255, alpha: 1)
    /// `editorButtonSelectionBackgroundColor`.
    static let selectionBackground = UIColor(white: 0xD1 / 255, alpha: 1)
    /// `toolbarSelectedIconColor`.
    static let selectedIcon = UIColor(white: 0x17 / 255, alpha: 1)
    /// `editorItemTitleFont`.
    static let itemTitleFont = UIFont.boldSystemFont(ofSize: 13)
}

// MARK: - PhotoEditorSliderView

/// TGPhotoEditorSliderView as the photo tools use it: a thin line with the part from the start value to the knob
/// filled, the start's mark, and a white knob. The knob moves by how far the touch moves, so a drag anywhere in the
/// row works; with `enablesPanHandling` a horizontal pan drives it and leaves vertical drags to the list, otherwise
/// it tracks touches directly. Ranges below zero keep a dead zone the knob's width around the middle. A double tap
/// calls `onReset`.
final class PhotoEditorSliderView: UIControl {
    // MARK: Internal

    /// `TGPhotoEditorSliderViewMargin`.
    static let margin: CGFloat = 15

    // MARK: Private

    /// `TGPhotoEditorSliderViewInternalMargin`: the knob's padding.
    private static let internalMargin: CGFloat = 7

    /// The 21 pt knob: a 17 pt white circle with a soft shadow.
    private static let knobImage = UIGraphicsImageRenderer(size: CGSize(width: 21, height: 21)).image { context in
        let canvas = context.cgContext
        canvas.setShadow(offset: CGSize(width: 0, height: 0.5), blur: 1.5, color: UIColor(white: 0, alpha: 0.5).cgColor)
        canvas.setFillColor(UIColor.white.cgColor)
        canvas.fillEllipse(in: CGRect(x: 2, y: 2, width: 17, height: 17))
    }

    var minimumValue: CGFloat = 0
    var maximumValue: CGFloat = 1
    var startValue: CGFloat = 0 {
        didSet {
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    var lineSize: CGFloat = 3 {
        didSet { setNeedsDisplay() }
    }

    var trackCornerRadius: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    var backColor = PhotoEditorColors.sliderBack {
        didSet { setNeedsDisplay() }
    }

    var trackColor = PhotoEditorColors.sliderTrack {
        didSet { setNeedsDisplay() }
    }

    var startColor = PhotoEditorColors.sliderTrack {
        didSet { setNeedsDisplay() }
    }

    /// The dark outline the line and knob get while the panel behind them hides.
    var isBordered = false {
        didSet { setNeedsDisplay() }
    }

    var enablesPanHandling = false {
        didSet { panRecognizer.isEnabled = enablesPanHandling }
    }

    /// `hitTestEdgeInsets`: negative insets reach past the frame.
    var hitTestInsets = UIEdgeInsets.zero

    var interactionBegan: (() -> Void)?
    var interactionEnded: (() -> Void)?
    /// `reset`, for a double tap.
    var onReset: (() -> Void)?

    /// `isTracking`: the knob is held.
    private(set) var isKnobTracking = false

    private let knobView = UIImageView()
    private lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
    private let feedbackGenerator = UISelectionFeedbackGenerator()

    private var storedValue: CGFloat = 0
    private var knobTouchStart: CGFloat = 0
    private var knobTouchCenterStart: CGFloat = 0
    private var knobDragCenter: CGFloat = 0
    private var knobStartedDragging = false

    var value: CGFloat {
        get { storedValue }
        set {
            storedValue = min(max(newValue, minimumValue), maximumValue)
            setNeedsLayout()
        }
    }

    /// `startHidden`: a range that starts at its start has no mark.
    private var isStartHidden: Bool {
        abs(startValue - minimumValue) < .ulpOfOne
    }

    private var totalLength: CGFloat {
        bounds.width - Self.internalMargin * 2
    }

    private var knobPosition: CGFloat {
        let center = isKnobTracking ? knobDragCenter : centerPosition(for: value)
        return max(Self.internalMargin, min(Self.internalMargin + center, Self.internalMargin + totalLength))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        knobView.image = Self.knobImage
        knobView.isUserInteractionEnabled = false
        addSubview(knobView)
        panRecognizer.isEnabled = false
        addGestureRecognizer(panRecognizer)
        doubleTapRecognizer.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapRecognizer)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty else { return }
        let knobSize = Self.knobImage.size
        knobView.frame = CGRect(
            x: knobPosition - knobSize.width / 2,
            y: (bounds.height - knobSize.height) / 2,
            width: knobSize.width,
            height: knobSize.height,
        )
        setNeedsDisplay()
    }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        bounds.inset(by: hitTestInsets).contains(point)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panRecognizer else { return true }
        let velocity = panRecognizer.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), maximumValue > minimumValue else { return }
        // Without positions the line reaches 2 pt from the ends while the knob stops at the internal margin.
        let visualMargin: CGFloat = 2
        let visualLength = bounds.width - visualMargin * 2
        let side = bounds.height
        let knob = knobPosition
        let knobSize = Self.knobImage.size
        let startPosition = visualMargin + visualLength / (maximumValue - minimumValue)
            * (abs(minimumValue) + startValue)
        var origin = startPosition
        var track = knob - startPosition
        if track < 0 {
            track = abs(track)
            origin -= track
        }
        let backFrame = CGRect(x: visualMargin, y: (side - lineSize) / 2, width: visualLength, height: lineSize)
        let trackFrame = CGRect(x: origin, y: (side - lineSize) / 2, width: track, height: lineSize)
        let startFrame = CGRect(x: startPosition - 2, y: (side - 12) / 2, width: 4, height: 12)
        let knobFrame = CGRect(
            x: knob - knobSize.width / 2,
            y: (side - knobSize.height) / 2,
            width: knobSize.width,
            height: knobSize.height,
        )
        let borderColor = UIColor(white: 0, alpha: 0.6).cgColor
        if isBordered {
            context.setFillColor(borderColor)
            Self.fill(backFrame.insetBy(dx: -1, dy: -1), cornerRadius: trackCornerRadius * 2, in: context)
            if !isStartHidden {
                Self.fill(startFrame.insetBy(dx: -1, dy: -1), cornerRadius: trackCornerRadius * 2, in: context)
            }
            context.setBlendMode(.copy)
        }
        context.setFillColor(backColor.cgColor)
        Self.fill(backFrame, cornerRadius: trackCornerRadius, in: context)
        context.setBlendMode(.normal)
        context.setFillColor(trackColor.cgColor)
        Self.fill(trackFrame, cornerRadius: trackCornerRadius, in: context)
        if !isStartHidden {
            context.setFillColor(startColor.cgColor)
            Self.fill(startFrame, cornerRadius: trackCornerRadius, in: context)
        }
        if isBordered {
            context.setFillColor(borderColor)
            context.fillEllipse(in: knobFrame.insetBy(dx: 1, dy: 1))
        }
    }

    // MARK: Touch tracking

    override func beginTracking(_ touch: UITouch, with _: UIEvent?) -> Bool {
        if !enablesPanHandling {
            beginKnobTracking(at: touch.location(in: self))
        }
        return true
    }

    override func continueTracking(_ touch: UITouch, with _: UIEvent?) -> Bool {
        if !enablesPanHandling {
            continueKnobTracking(at: touch.location(in: self))
        }
        return true
    }

    override func endTracking(_: UITouch?, with _: UIEvent?) {
        if !enablesPanHandling {
            endKnobTracking()
        }
    }

    override func cancelTracking(with _: UIEvent?) {
        if !enablesPanHandling {
            cancelKnobTracking()
        }
    }

    // MARK: Accessibility

    override func accessibilityIncrement() {
        value += (maximumValue - minimumValue) / 20
        sendActions(for: .valueChanged)
    }

    override func accessibilityDecrement() {
        value -= (maximumValue - minimumValue) / 20
        sendActions(for: .valueChanged)
    }

    private static func fill(_ rect: CGRect, cornerRadius: CGFloat, in context: CGContext) {
        guard cornerRadius > .ulpOfOne else {
            context.fill(rect)
            return
        }
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath)
        context.fillPath()
    }

    /// `centerPositionForValue`.
    private func centerPosition(for sliderValue: CGFloat) -> CGFloat {
        let length = totalLength
        guard minimumValue < 0 else {
            return length / (maximumValue - minimumValue) * (abs(minimumValue) + sliderValue)
        }
        let knob = Self.knobImage.size.width
        if abs(minimumValue) > 1, Int(sliderValue) == 0 {
            return length / 2
        }
        if abs(sliderValue) < 0.01 {
            return length / 2
        }
        let edgeValue = sliderValue > 0 ? maximumValue : minimumValue
        if sliderValue > 0 {
            return (length + knob) / 2 + (length - knob) / 2 * abs(sliderValue / edgeValue)
        }
        return (length - knob) / 2 * abs((edgeValue - sliderValue) / edgeValue)
    }

    /// `valueForCenterPosition`.
    private func valueForCenterPosition(_ position: CGFloat) -> CGFloat {
        let length = totalLength
        var result: CGFloat = 0
        if minimumValue < 0 {
            let knob = Self.knobImage.size.width
            let half = (length - knob) / 2
            guard half > 0 else { return 0 }
            if position < half {
                result = minimumValue + position / half * abs(minimumValue)
            } else if position > (length + knob) / 2 {
                result = (position - (length + knob) / 2) / half * maximumValue
            }
        } else if length > 0 {
            result = minimumValue + position / length * (maximumValue - minimumValue)
        }
        return min(max(result, minimumValue), maximumValue)
    }

    private func beginKnobTracking(at location: CGPoint) {
        isKnobTracking = true
        knobTouchCenterStart = knobView.center.x
        knobTouchStart = location.x
        knobDragCenter = knobTouchCenterStart - Self.internalMargin
        knobStartedDragging = false
        feedbackGenerator.prepare()
    }

    private func continueKnobTracking(at location: CGPoint) {
        if abs(location.x - knobTouchStart) > 1, !knobStartedDragging {
            knobStartedDragging = true
            interactionBegan?()
        }
        knobDragCenter = knobTouchCenterStart - knobTouchStart - Self.internalMargin + location.x
        let previousValue = value
        value = valueForCenterPosition(knobDragCenter)
        let reachedStop = value == minimumValue || value == maximumValue
            || (minimumValue != startValue && value == startValue)
        if previousValue != value, reachedStop {
            feedbackGenerator.selectionChanged()
            feedbackGenerator.prepare()
        }
        setNeedsLayout()
        sendActions(for: .valueChanged)
    }

    private func endKnobTracking() {
        isKnobTracking = false
        sendActions(for: .valueChanged)
        setNeedsLayout()
        interactionEnded?()
    }

    private func cancelKnobTracking() {
        isKnobTracking = false
        setNeedsLayout()
        interactionEnded?()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            beginKnobTracking(at: recognizer.location(in: self))
        case .changed:
            continueKnobTracking(at: recognizer.location(in: self))
        case .ended:
            endKnobTracking()
        case .cancelled,
             .failed:
            cancelKnobTracking()
        default:
            break
        }
    }

    @objc private func handleDoubleTap() {
        onReset?()
    }
}

// MARK: - PhotoEditorHUDView

/// TGPhotoEditorHUDView: the dark pill near the top that names the tool being dragged with its value, or says
/// Original while the photo is held.
final class PhotoEditorHUDView: UIView {
    // MARK: Private

    private let backgroundView = UIView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    // MARK: Internal

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundView.alpha = 0
        backgroundView.backgroundColor = PhotoEditorColors.panelBackground
        backgroundView.layer.cornerRadius = 6
        backgroundView.layer.cornerCurve = .continuous
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = .white
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        valueLabel.textAlignment = .right
        valueLabel.textColor = PhotoEditorColors.accent
        backgroundView.addSubview(titleLabel)
        backgroundView.addSubview(valueLabel)
        addSubview(backgroundView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let padding: CGFloat = 8
        let titleSize = titleLabel.intrinsicContentSize
        titleLabel.frame = CGRect(x: padding, y: 6, width: ceil(titleSize.width), height: ceil(titleSize.height))
        let width = valueLabel.isHidden
            ? titleLabel.frame.width + padding * 2
            : padding * 2 + titleLabel.frame.width + 50 + 3
        valueLabel.frame = CGRect(
            x: width - padding - 50,
            y: 6,
            width: 50,
            height: ceil(valueLabel.intrinsicContentSize.height),
        )
        backgroundView.frame = CGRect(x: (bounds.width - width) / 2, y: 15, width: width, height: 30)
    }

    /// `setText`: a title alone, or hidden for nothing.
    func setText(_ text: String?) {
        guard let text, !text.isEmpty else {
            setHidden(true)
            return
        }
        titleLabel.text = text
        valueLabel.isHidden = true
        setNeedsLayout()
        setHidden(false)
    }

    /// `setTitle:value:`.
    func setTitle(_ title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
        valueLabel.isHidden = false
        setNeedsLayout()
        setHidden(false)
    }

    private func setHidden(_ hidden: Bool) {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.backgroundView.alpha = hidden ? 0 : 1
        }
    }
}
