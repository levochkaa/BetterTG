// PhotoBlurToolView.swift

import UIKit

// MARK: - PhotoBlurTypeButton

/// TGPhotoEditorBlurTypeButton: the shape's icon over its name, both in the accent color while selected and dimmed
/// while pressed.
private final class PhotoBlurTypeButton: UIControl {
    override var isSelected: Bool {
        didSet { updateColors() }
    }

    /// Pressing dims at once; letting go brightens over 0.2 s.
    override var isHighlighted: Bool {
        didSet {
            let targetAlpha: CGFloat = isHighlighted ? 0.4 : 1
            guard abs(targetAlpha - alpha) > .ulpOfOne else { return }
            if isHighlighted {
                alpha = targetAlpha
            } else {
                UIView.animate(withDuration: 0.2) { self.alpha = targetAlpha }
            }
        }
    }

    // MARK: Internal

    let type: PhotoBlurType

    // MARK: Private

    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init(type: PhotoBlurType) {
        self.type = type
        super.init(frame: .zero)
        iconView.contentMode = .center
        iconView.image = Self.icon(for: type)
        addSubview(iconView)
        titleLabel.font = PhotoEditorColors.itemTitleFont
        titleLabel.textAlignment = .center
        titleLabel.text = L10n.telegram(type.titleKey)
        addSubview(titleLabel)
        isAccessibilityElement = true
        accessibilityLabel = titleLabel.text
        updateColors()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.frame = CGRect(x: (bounds.width - 50) / 2, y: (bounds.height - 68) / 2, width: 50, height: 50)
        titleLabel.frame = CGRect(x: 0, y: iconView.frame.maxY - 1, width: bounds.width, height: 16)
    }

    /// Editor/BlurOff, BlurRadial and BlurLinear: a rounded square, empty for Off, with two rings for Radial and with
    /// two pairs of bars for Linear.
    private static func icon(for type: PhotoBlurType) -> UIImage {
        let side: CGFloat = 30
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            UIColor.white.setStroke()
            let frame = UIBezierPath(roundedRect: CGRect(x: 5, y: 5, width: 20, height: 20), cornerRadius: 4.5)
            frame.lineWidth = 1.65
            frame.stroke()
            switch type {
            case .off:
                break
            case .radial:
                for radius in [5.5, 2.75] as [CGFloat] {
                    let ring = UIBezierPath(
                        arcCenter: CGPoint(x: side / 2, y: side / 2),
                        radius: radius,
                        startAngle: 0,
                        endAngle: 2 * .pi,
                        clockwise: true,
                    )
                    ring.lineWidth = 1.65
                    ring.stroke()
                }
            case .linear:
                let bars: [(y: CGFloat, inset: CGFloat)] = [(7.5, 9), (11, 11.25), (19, 11.25), (22.5, 9)]
                for bar in bars {
                    let line = UIBezierPath()
                    line.move(to: CGPoint(x: bar.inset, y: bar.y))
                    line.addLine(to: CGPoint(x: side - bar.inset, y: bar.y))
                    line.lineWidth = 1.5
                    line.lineCapStyle = .round
                    line.stroke()
                }
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private func updateColors() {
        iconView.tintColor = isSelected ? PhotoEditorColors.accent : .white
        titleLabel.textColor = isSelected ? PhotoEditorColors.accent : PhotoEditorColors.itemTitle
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

// MARK: - PhotoBlurToolView

/// TGPhotoEditorBlurToolView's portrait panel: Tilt Shift over the Off, Radial and Linear buttons. Choosing another
/// shape hands it back.
final class PhotoBlurToolView: UIView {
    // MARK: Internal

    var onTypeChanged: ((PhotoBlurType) -> Void)?

    // MARK: Private

    private let titleLabel = UILabel()
    private let buttons = PhotoBlurType.allCases.map { PhotoBlurTypeButton(type: $0) }
    private var type = PhotoBlurType.off

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = PhotoEditorColors.itemTitleFont
        titleLabel.textAlignment = .center
        titleLabel.textColor = PhotoEditorColors.itemTitle
        titleLabel.text = L10n.telegram("PhotoEditor.TiltShift")
        addSubview(titleLabel)
        for button in buttons {
            button.addTarget(self, action: #selector(buttonPressed(_:)), for: .touchUpInside)
            addSubview(button)
        }
        updateButtons()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty else { return }
        let width = bounds.width
        titleLabel.frame = CGRect(x: (width - 160) / 2, y: 10, width: 160, height: 20)
        let originsX = [floor(width / 4 - 50), width / 2 - 50, ceil(width * 3 / 4 - 50)]
        for (button, originX) in zip(buttons, originsX) {
            button.frame = CGRect(x: originX, y: bounds.height / 2 - 42, width: 100, height: 100)
        }
    }

    func setType(_ type: PhotoBlurType) {
        self.type = type
        updateButtons()
    }

    private func updateButtons() {
        for button in buttons {
            button.isSelected = button.type == type
        }
    }

    /// `setSelectedBlurType:update:`.
    @objc private func buttonPressed(_ sender: PhotoBlurTypeButton) {
        guard sender.type != type else { return }
        type = sender.type
        updateButtons()
        onTypeChanged?(sender.type)
    }
}

// MARK: - PhotoBlurShapeView

/// TGPhotoEditorRadialBlurView and TGPhotoEditorLinearBlurView: the blur's controls over the photo. Dragging the
/// center moves it, dragging the inner or outer ring (Linear's bars) moves where the blur starts or is full, a pinch
/// scales both, and for Linear dragging away from the bars turns them. The controls dim while touched.
private final class PhotoBlurShapeView: UIView, UIGestureRecognizerDelegate {
    // MARK: Private

    private enum Control {
        case idle
        case center
        case innerRadius
        case outerRadius
        case wholeArea
        case rotation
    }

    /// `TGRadialBlurInsetProximity`: rings closer than this split the band between them.
    private static let insetProximity: CGFloat = 20
    /// `TGRadialBlurViewCenterInset`.
    private static let centerInset: CGFloat = 30
    /// `TGRadialBlurViewRadiusInset`.
    private static let radiusInset: CGFloat = 30

    // MARK: Internal

    let isLinear: Bool
    var onValueChanged: ((PhotoBlurValue) -> Void)?

    /// The photo's size, centered in the view.
    var actualAreaSize = CGSize.zero {
        didSet { setNeedsDisplay() }
    }

    var value = PhotoBlurValue() {
        didSet { setNeedsDisplay() }
    }

    private lazy var pressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
    private lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private var activeControl = Control.idle
    private var startCenterPoint = CGPoint.zero
    private var startDistance: CGFloat = 0
    private var startRadius: CGFloat = 0

    var isTracking: Bool {
        activeControl != .idle
    }

    /// The photo's frame in the view.
    private var actualArea: CGRect {
        CGRect(
            x: (bounds.width - actualAreaSize.width) / 2,
            y: (bounds.height - actualAreaSize.height) / 2,
            width: actualAreaSize.width,
            height: actualAreaSize.height,
        )
    }

    private var shorterSide: CGFloat {
        min(actualAreaSize.width, actualAreaSize.height)
    }

    /// `_actualCenterPoint`: the point is over the photo's width, its height from the top of a square on the width.
    private var actualCenterPoint: CGPoint {
        let area = actualArea
        let offsetY = (actualAreaSize.width - actualAreaSize.height) / 2
        return CGPoint(
            x: area.minX + value.point.x * actualAreaSize.width,
            y: area.minY - offsetY + value.point.y * actualAreaSize.width,
        )
    }

    init(isLinear: Bool) {
        self.isLinear = isLinear
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        pressRecognizer.delegate = self
        pressRecognizer.minimumPressDuration = 0.1
        addGestureRecognizer(pressRecognizer)
        panRecognizer.delegate = self
        addGestureRecognizer(panRecognizer)
        pinchRecognizer.delegate = self
        addGestureRecognizer(pinchRecognizer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pressRecognizer || gestureRecognizer === panRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let location = gestureRecognizer.location(in: self)
        return control(at: location, allowsCenter: gestureRecognizer === panRecognizer) != .idle
    }

    /// White dashes with a soft shadow: Radial's two dashed rings, or Linear's two pairs of dashed lines turned by the
    /// angle, and the center dot.
    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), shorterSide > 0 else { return }
        let center = actualCenterPoint
        let innerRadius = shorterSide * value.falloff
        let outerRadius = shorterSide * value.size
        context.setFillColor(UIColor.white.cgColor)
        context.setShadow(offset: .zero, blur: 2.5, color: UIColor(white: 0, alpha: 0.3).cgColor)
        if isLinear {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: value.angle)
            let space: CGFloat = 6
            let thickness: CGFloat = 1.5
            let lines: [(count: Int, length: CGFloat, offset: CGFloat)] = [(30, 12, innerRadius), (64, 6, outerRadius)]
            for line in lines {
                for index in 0..<line.count {
                    let rightX = CGFloat(index) * (line.length + space)
                    let leftX = -CGFloat(index) * (line.length + space) - space - line.length
                    for y in [-line.offset, line.offset] {
                        context.addRect(CGRect(x: rightX, y: y, width: line.length, height: thickness))
                        context.addRect(CGRect(x: leftX, y: y, width: line.length, height: thickness))
                    }
                }
            }
            context.fillPath()
            context.fillEllipse(in: CGRect(x: -8, y: -8, width: 16, height: 16))
        } else {
            let rings: [(count: Int, space: CGFloat, length: CGFloat, radius: CGFloat)] = [
                (22, 6.15, 10.2, innerRadius),
                (64, 2.02, 3.6, outerRadius),
            ]
            for ring in rings {
                let space = ring.space * .pi / 180
                let length = ring.length * .pi / 180
                for index in 0..<ring.count {
                    let startAngle = CGFloat(index) * (space + length)
                    let arc = CGMutablePath()
                    arc.addArc(
                        center: center,
                        radius: ring.radius,
                        startAngle: startAngle,
                        endAngle: startAngle + length,
                        clockwise: false,
                    )
                    context.addPath(arc.copy(strokingWithWidth: 1.5, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
                }
            }
            context.fillPath()
            context.fillEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        gestureRecognizer === pressRecognizer || otherGestureRecognizer === pressRecognizer
    }

    /// A touch's distance from the center, and the one the rings use: the same for Radial, across the bars for
    /// Linear.
    private func distances(to location: CGPoint) -> (radial: CGFloat, control: CGFloat) {
        let center = actualCenterPoint
        let deltaX = location.x - center.x
        let deltaY = location.y - center.y
        let radial = (deltaX * deltaX + deltaY * deltaY).squareRoot()
        guard isLinear else { return (radial, radial) }
        let angle = value.angle + .pi / 2
        return (radial, abs(deltaX * cos(angle) + deltaY * sin(angle)))
    }

    /// The control a touch at `location` takes: the center within 30 pt, a ring within 30 pt of it unless the rings
    /// are close, and for Linear the rest outside the bars to turn them.
    private func control(at location: CGPoint, allowsCenter: Bool) -> Control {
        guard shorterSide > 0 else { return .idle }
        let measured = distances(to: location)
        let distance = measured.control
        let innerRadius = shorterSide * value.falloff
        let outerRadius = shorterSide * value.size
        let isClose = abs(outerRadius - innerRadius) < Self.insetProximity
        let innerRadiusOuterInset = isClose ? 0 : Self.radiusInset
        let outerRadiusInnerInset = isClose ? 0 : Self.radiusInset
        if allowsCenter, measured.radial < Self.centerInset {
            return .center
        }
        if distance > innerRadius - Self.radiusInset, distance < innerRadius + innerRadiusOuterInset {
            return .innerRadius
        }
        if distance > outerRadius - outerRadiusInnerInset, distance < outerRadius + Self.radiusInset {
            return .outerRadius
        }
        if isLinear, distance <= innerRadius - Self.radiusInset || distance >= outerRadius + Self.radiusInset {
            return .rotation
        }
        return .idle
    }

    private func setSelected(_ isSelected: Bool) {
        UIView.animate(withDuration: 0.16, delay: 0, options: .beginFromCurrentState) {
            self.alpha = isSelected ? 0.6 : 1
        }
    }

    private func update(_ newValue: PhotoBlurValue) {
        guard newValue != value else { return }
        value = newValue
        onValueChanged?(newValue)
    }

    /// The drag's turn: its length in degrees over π·1.15, clockwise or not by the quarter around the center it is
    /// in and its main direction.
    private func rotated(by translation: CGPoint, at location: CGPoint) -> CGFloat {
        let center = actualCenterPoint
        let isVertical = abs(translation.y) > abs(translation.x)
        let isClockwise =
            switch (location.x > center.x, location.y > center.y) {
            case (false, false): isVertical ? translation.y < 0 : translation.x > 0
            case (true, false): isVertical ? translation.y > 0 : translation.x > 0
            case (true, true): isVertical ? translation.y > 0 : translation.x < 0
            case (false, true): isVertical ? translation.y < 0 : translation.x < 0
            }
        let delta = (translation.x * translation.x + translation.y * translation.y).squareRoot()
        let degrees = value.angle * 180 / .pi + delta * (isClockwise ? 1 : -1) / .pi / 1.15
        return degrees * .pi / 180
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            setSelected(true)
        case .cancelled,
             .ended,
             .failed:
            setSelected(false)
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        let distance = distances(to: location).control
        switch recognizer.state {
        case .began:
            activeControl = control(at: location, allowsCenter: true)
            switch activeControl {
            case .center:
                startCenterPoint = actualCenterPoint
            case .innerRadius:
                startDistance = distance
                startRadius = shorterSide * value.falloff
            case .outerRadius:
                startDistance = distance
                startRadius = shorterSide * value.size
            case .idle,
                 .rotation,
                 .wholeArea:
                break
            }
            setSelected(true)
        case .changed:
            var newValue = value
            switch activeControl {
            case .center:
                let translation = recognizer.translation(in: self)
                let area = actualArea
                let newPoint = CGPoint(
                    x: max(area.minX, min(area.maxX, startCenterPoint.x + translation.x)),
                    y: max(area.minY, min(area.maxY, startCenterPoint.y + translation.y)),
                )
                let offsetY = (actualAreaSize.width - actualAreaSize.height) / 2
                newValue.point = CGPoint(
                    x: (newPoint.x - area.minX) / actualAreaSize.width,
                    y: (newPoint.y - area.minY + offsetY) / actualAreaSize.width,
                )
            case .innerRadius:
                let falloff = max(PhotoBlurValue.minimumFalloff, (startRadius + distance - startDistance) / shorterSide)
                newValue.falloff = min(falloff, value.size - PhotoBlurValue.minimumDifference)
            case .outerRadius:
                newValue.size = max(
                    value.falloff + PhotoBlurValue.minimumDifference,
                    (startRadius + distance - startDistance) / shorterSide,
                )
            case .rotation:
                newValue.angle = rotated(by: recognizer.translation(in: self), at: location)
                recognizer.setTranslation(.zero, in: self)
            case .idle,
                 .wholeArea:
                break
            }
            update(newValue)
        case .cancelled,
             .ended,
             .failed:
            activeControl = .idle
            setSelected(false)
        default:
            break
        }
    }

    /// The pinch scales where the blur starts and where it is full.
    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began,
             .changed:
            if recognizer.state == .began {
                activeControl = .wholeArea
                setSelected(true)
            }
            var newValue = value
            newValue.falloff = max(PhotoBlurValue.minimumFalloff, value.falloff * recognizer.scale)
            newValue.size = max(newValue.falloff + PhotoBlurValue.minimumDifference, value.size * recognizer.scale)
            recognizer.scale = 1
            update(newValue)
        case .cancelled,
             .ended,
             .failed:
            activeControl = .idle
            setSelected(false)
        default:
            break
        }
    }
}

// MARK: - PhotoBlurAreaView

/// TGPhotoEditorBlurAreaView: Radial's and Linear's controls over the photo, crossfading as the type changes. Off
/// leaves its touches to the photo.
final class PhotoBlurAreaView: UIView {
    // MARK: Internal

    var onValueChanged: ((PhotoBlurValue) -> Void)?

    /// The photo's size, centered in the view.
    var actualAreaSize = CGSize.zero {
        didSet {
            radialView.actualAreaSize = actualAreaSize
            linearView.actualAreaSize = actualAreaSize
        }
    }

    // MARK: Private

    private let radialView = PhotoBlurShapeView(isLinear: false)
    private let linearView = PhotoBlurShapeView(isLinear: true)
    private var value = PhotoBlurValue()

    var isTracking: Bool {
        radialView.isTracking || linearView.isTracking
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        for shapeView in [radialView, linearView] {
            shapeView.frame = bounds
            shapeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shapeView.alpha = 0
            shapeView.isHidden = true
            shapeView.onValueChanged = { [weak self] newValue in
                guard let self else { return }
                self.value = newValue
                radialView.value = newValue
                linearView.value = newValue
                onValueChanged?(newValue)
            }
            addSubview(shapeView)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }

    /// `setValue:`: the shape fades in over 0.2 s when the type changes.
    func setValue(_ newValue: PhotoBlurValue) {
        let previousType = value.type
        value = newValue
        radialView.value = newValue
        linearView.value = newValue
        guard newValue.type != previousType else { return }
        let type = newValue.type
        if type != .off {
            radialView.isHidden = false
            linearView.isHidden = false
        }
        UIView.animate(withDuration: 0.2) {
            self.radialView.alpha = type == .radial ? 1 : 0
            self.linearView.alpha = type == .linear ? 1 : 0
        } completion: { finished in
            guard finished else { return }
            self.radialView.isHidden = type != .radial
            self.linearView.isHidden = type != .linear
        }
    }
}
