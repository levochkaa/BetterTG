// PhotoDrawingControls.swift

import UIKit

// MARK: - PhotoDrawingToolsView

/// ToolsComponent: the brushes 44 pt apart in the middle of the row, the selected one raised, each in its color.
final class PhotoDrawingToolsView: UIView {
    // MARK: Private

    private static let spacing: CGFloat = 44

    // MARK: Internal

    var onSelect: ((PhotoDrawingTool) -> Void)?

    /// `DrawingState.forVideo` leaves Blur out.
    var tools = PhotoDrawingTool.allCases {
        didSet {
            for (tool, button) in buttons {
                button.isHidden = !tools.contains(tool)
            }
            setNeedsLayout()
        }
    }

    private var buttons = [PhotoDrawingTool: UIButton]()
    private var state = PhotoDrawingToolState.initial

    override init(frame: CGRect) {
        super.init(frame: frame)
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        for tool in PhotoDrawingTool.allCases {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: Self.symbol(for: tool), withConfiguration: configuration), for: .normal)
            button.accessibilityLabel = Self.title(for: tool)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(tool) }, for: .touchUpInside)
            addSubview(button)
            buttons[tool] = button
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutButtons()
    }

    static func symbol(for tool: PhotoDrawingTool) -> String {
        switch tool {
        case .pen: "pencil.tip"
        case .arrow: "arrow.up.right"
        case .marker: "highlighter"
        case .neon: "scribble.variable"
        case .blur: "aqi.medium"
        case .eraser: "eraser"
        }
    }

    static func title(for tool: PhotoDrawingTool) -> String {
        switch tool {
        case .pen: L10n.telegram("Paint.Pen")
        case .arrow: L10n.telegram("Paint.Arrow")
        case .marker: L10n.telegram("Paint.Marker")
        case .neon: L10n.telegram("Paint.Neon")
        case .blur: L10n.betterTG("Accessibility.PhotoEditor.Blur")
        case .eraser: L10n.betterTG("Accessibility.PhotoEditor.Eraser")
        }
    }

    func update(state: PhotoDrawingToolState, animated: Bool) {
        let previousTool = self.state.selectedTool
        self.state = state
        for (tool, button) in buttons {
            let brush = state.brushes[tool]
            button.tintColor = tool.hasColor ? brush?.color.withAlpha(1).uiColor ?? .white : .white
            button.accessibilityTraits = tool == state.selectedTool ? [.button, .selected] : .button
        }
        guard animated, previousTool != state.selectedTool else {
            setNeedsLayout()
            return
        }
        UIView.animate(
            withDuration: 0.7,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.layoutButtons()
        }
    }

    /// The selected brush 12 pt above the others, as ToolsComponent's 18 and 30 pt offsets.
    private func layoutButtons() {
        let left = (bounds.width - Self.spacing * CGFloat(tools.count - 1)) / 2
        for (index, tool) in tools.enumerated() {
            guard let button = buttons[tool] else { continue }
            let isSelected = tool == state.selectedTool
            button.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
            button.center = CGPoint(x: left + Self.spacing * CGFloat(index), y: bounds.midY + (isSelected ? -6 : 6))
            button.alpha = isSelected ? 1 : 0.75
        }
    }
}

// MARK: - PhotoDrawingSizeSlider

/// TextSizeSliderComponent: a wedge at the left edge, half hidden until it is dragged, thick for large sizes at the
/// top and thin at the bottom, with a white knob.
final class PhotoDrawingSizeSlider: UIView, UIGestureRecognizerDelegate {
    // MARK: Internal

    static let size = CGSize(width: 30, height: 240)

    override var accessibilityValue: String? {
        get { "\(Int((value * 100).rounded()))%" }
        set {}
    }

    var onValueChanged: ((CGFloat) -> Void)?
    var onReleased: (() -> Void)?

    private(set) var value: CGFloat = 0.5

    // MARK: Private

    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let maskLayer = CAShapeLayer()
    private let knobContainer = CALayer()
    private let knob = CALayer()
    private var trackingCount = 0
    private var isPanning = false
    private var appliedTracking: Bool?

    private var isTracking: Bool {
        trackingCount > 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isExclusiveTouch = true
        layer.allowsGroupOpacity = true
        backgroundView.isUserInteractionEnabled = false
        backgroundView.contentView.backgroundColor = UIColor(white: 0x88 / 255, alpha: 0.3)
        backgroundView.layer.mask = maskLayer
        addSubview(backgroundView)
        knob.contents = Self.knobImage()?.cgImage
        knobContainer.addSublayer(knob)
        layer.addSublayer(knobContainer)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleTracking(_:)))
        press.minimumPressDuration = 0.01
        press.delegate = self
        addGestureRecognizer(press)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTracking(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Size")
        accessibilityTraits = .adjustable
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func accessibilityIncrement() {
        setValue(value + 0.1)
        onValueChanged?(value)
    }

    override func accessibilityDecrement() {
        setValue(value - 0.1)
        onValueChanged?(value)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        if maskLayer.frame.size != size {
            maskLayer.frame = CGRect(origin: .zero, size: size)
            maskLayer.path = Self.maskPath(size: size, topRadius: 15, bottomRadius: 3).cgPath
        }
        backgroundView.frame = bounds
        knobContainer.frame = bounds
        let knobSide: CGFloat = 52
        CATransaction.begin()
        CATransaction.setDisableActions(isPanning)
        knob.frame = CGRect(
            x: (size.width - knobSide) / 2,
            y: -12 + floor((size.height + 24 - knobSide) * (1 - value)),
            width: knobSide,
            height: knobSide,
        )
        CATransaction.commit()
        updateTrackingTransform(animated: false)
    }

    /// `generateMaskPath`: the wedge between a wide top and a narrow bottom.
    private static func maskPath(size: CGSize, topRadius: CGFloat, bottomRadius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let midX = size.width / 2
        path.addArc(
            withCenter: CGPoint(x: midX, y: topRadius),
            radius: topRadius,
            startAngle: .pi,
            endAngle: 0,
            clockwise: true,
        )
        path.addLine(to: CGPoint(x: midX + bottomRadius, y: size.height - bottomRadius))
        path.addArc(
            withCenter: CGPoint(x: midX, y: size.height - bottomRadius),
            radius: bottomRadius,
            startAngle: 0,
            endAngle: .pi,
            clockwise: true,
        )
        path.close()
        return path
    }

    /// `generateKnobImage`: a white 32 pt circle with a soft shadow.
    private static func knobImage() -> UIImage? {
        let side: CGFloat = 32
        let margin: CGFloat = 10
        let size = CGSize(width: side + margin * 2, height: side + margin * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setShadow(offset: .zero, blur: 9, color: UIColor(white: 0, alpha: 0.3).cgColor)
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: margin, y: margin, width: side, height: side))
        }
    }

    func setValue(_ newValue: CGFloat) {
        value = min(max(newValue, 0), 1)
        if !isTracking {
            setNeedsLayout()
        }
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }

    /// The wedge slides out while it is held and back half under the edge after.
    private func updateTrackingTransform(animated: Bool) {
        guard appliedTracking != isTracking else { return }
        appliedTracking = isTracking
        let changes = {
            self.layer.sublayerTransform = self.isTracking
                ? CATransform3DMakeTranslation(8, 0, 0)
                : CATransform3DMakeTranslation(-self.bounds.width / 2, 0, 0)
            self.knobContainer.sublayerTransform = self.isTracking
                ? CATransform3DIdentity
                : CATransform3DMakeTranslation(4, 0, 0)
        }
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            changes()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            changes()
            CATransaction.commit()
        }
    }

    /// `handlePress` and `handlePan`: the value follows the finger 12 pt in from either end.
    @objc private func handleTracking(_ recognizer: UIGestureRecognizer) {
        guard bounds.height > 0 else { return }
        switch recognizer.state {
        case .began:
            trackingCount += 1
            if recognizer is UIPanGestureRecognizer {
                isPanning = true
            }
            updateTrackingTransform(animated: true)
            track(recognizer)
        case .changed:
            track(recognizer)
        case .cancelled,
             .ended,
             .failed:
            trackingCount = max(0, trackingCount - 1)
            if recognizer is UIPanGestureRecognizer {
                isPanning = false
            }
            updateTrackingTransform(animated: true)
            if !isTracking {
                onReleased?()
            }
        default:
            break
        }
    }

    private func track(_ recognizer: UIGestureRecognizer) {
        let location = recognizer.location(in: self).y - 12
        value = 1 - min(1, max(0, location / (bounds.height - 24)))
        setNeedsLayout()
        layoutIfNeeded()
        onValueChanged?(value)
    }
}

// MARK: - PhotoDrawingColorButton

/// ColorSwatchComponent's main swatch: the color in a rainbow ring.
final class PhotoDrawingColorButton: UIControl {
    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1
        }
    }

    // MARK: Internal

    var color = PhotoDrawingColor.white {
        didSet {
            colorLayer.backgroundColor = color.cgColor
        }
    }

    /// ColorSwatchComponent's main swatch without a color: a preset's color is ringed among the swatches, and
    /// Eraser and Blur have none, so the ring thickens over an empty middle.
    var isColorHidden = false {
        didSet {
            guard isColorHidden != oldValue else { return }
            setNeedsLayout()
        }
    }

    // MARK: Private

    private let ringLayer = CAGradientLayer()
    private let ringMask = CAShapeLayer()
    private let checkerLayer = CALayer()
    private let colorLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        ringLayer.type = .conic
        ringLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        ringLayer.endPoint = CGPoint(x: 0.5, y: 0)
        ringLayer.colors = [0xFF453A, 0xFF8A00, 0xFFD60A, 0x34C759, 0x63E6E2, 0x0A84FF, 0xBF5AF2, 0xFF453A]
            .map { UIColor(rgb: $0).cgColor }
        ringLayer.mask = ringMask
        ringMask.fillColor = nil
        ringMask.strokeColor = UIColor.black.cgColor
        ringMask.lineWidth = 3
        layer.addSublayer(ringLayer)
        layer.addSublayer(checkerLayer)
        layer.addSublayer(colorLayer)
        checkerLayer.backgroundColor = UIColor(patternImage: Self.checkerImage()).cgColor
        accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Color")
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 30
        let ringFrame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        ringLayer.frame = ringFrame
        ringMask.frame = ringLayer.bounds
        let ringInset: CGFloat = isColorHidden ? 7 : 1.5
        ringMask.path = CGPath(ellipseIn: ringLayer.bounds.insetBy(dx: ringInset, dy: ringInset), transform: nil)
        ringMask.lineWidth = isColorHidden ? 12 : 3
        let inner = ringFrame.insetBy(dx: 5.5, dy: 5.5)
        for sublayer in [checkerLayer, colorLayer] {
            sublayer.frame = inner
            sublayer.cornerRadius = inner.width / 2
            sublayer.masksToBounds = true
            sublayer.isHidden = isColorHidden
        }
    }

    /// `generateCheckeredImage`'s tile, under translucent colors.
    static func checkerImage(length: CGFloat = 4) -> UIImage {
        let size = CGSize(width: length * 2, height: length * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0xE1 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: length, height: length))
            context.fill(CGRect(x: length, y: length, width: length, height: length))
        }
    }
}

// MARK: - PhotoDrawingSwatchesView

/// DrawingScreen's eight preset swatches across the screen; the current color's swatch is ringed.
final class PhotoDrawingSwatchesView: UIView {
    // MARK: Internal

    /// `presetColors`.
    static let presetColors = [0xFF453A, 0xFF8A00, 0xFFD60A, 0x34C759, 0x63E6E2, 0x0A84FF, 0xBF5AF2, 0xFFFFFF]
        .map { PhotoDrawingColor(rgb: $0) }

    var onSelect: ((PhotoDrawingColor) -> Void)?

    /// The ringed swatch's color, or none.
    var selectedColor: PhotoDrawingColor? {
        didSet {
            updateSelection()
        }
    }

    // MARK: Private

    private var buttons = [UIButton]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for color in Self.presetColors {
            let button = UIButton(type: .custom)
            button.backgroundColor = color.uiColor
            button.layer.borderColor = UIColor.white.cgColor
            button.accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Color")
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(color) }, for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 24
        let left: CGFloat = 28
        let delta = (bounds.width - left * 2) / CGFloat(max(1, buttons.count - 1))
        for (index, button) in buttons.enumerated() {
            button.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            button.center = CGPoint(x: left + delta * CGFloat(index), y: bounds.midY)
            button.layer.cornerRadius = side / 2
        }
        updateSelection()
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let isSelected = selectedColor.map { $0.rgb == Self.presetColors[index].rgb } ?? false
            button.layer.borderWidth = isSelected ? 2 : 0
            button.transform = isSelected ? CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }
}

// MARK: - PhotoDrawingModeView

/// ModeComponent: Draw and Text, the current one on a light capsule.
final class PhotoDrawingModeView: UIView {
    // MARK: Internal

    var onSelect: ((Int) -> Void)?

    var selectedIndex = 0 {
        didSet {
            setNeedsLayout()
        }
    }

    // MARK: Private

    private let selectionView = UIView()
    private var buttons = [UIButton]()

    init(titles: [String]) {
        super.init(frame: .zero)
        selectionView.backgroundColor = UIColor(white: 1, alpha: 0.15)
        selectionView.isUserInteractionEnabled = false
        addSubview(selectionView)
        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            button.tintColor = .white
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let widths = buttons.map { ceil($0.intrinsicContentSize.width) + 28 }
        var x = (bounds.width - widths.reduce(0, +)) / 2
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: x, y: (bounds.height - 32) / 2, width: widths[index], height: 32)
            button.alpha = index == selectedIndex ? 1 : 0.6
            button.accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
            x += widths[index]
        }
        if buttons.indices.contains(selectedIndex) {
            selectionView.frame = buttons[selectedIndex].frame
            selectionView.layer.cornerRadius = selectionView.bounds.height / 2
        }
    }
}

// MARK: - PhotoDrawingAddButton

/// DrawingScreen's add button: a plus on a small translucent rounded square, touchable over 44 pt.
final class PhotoDrawingAddButton: UIControl {
    // MARK: Internal

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1
        }
    }

    // MARK: Private

    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let iconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundView.isUserInteractionEnabled = false
        backgroundView.contentView.backgroundColor = UIColor(white: 0x88 / 255, alpha: 0.3)
        backgroundView.layer.cornerRadius = 12
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)
        let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = UIImage(systemName: "plus", withConfiguration: configuration)
        iconView.tintColor = .white
        iconView.contentMode = .center
        addSubview(iconView)
        accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Add")
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 24
        let frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        backgroundView.frame = frame
        iconView.frame = frame
    }
}
