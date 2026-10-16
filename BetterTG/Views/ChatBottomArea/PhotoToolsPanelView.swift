// PhotoToolsPanelView.swift

import UIKit

// MARK: - PhotoToolRowView

/// TGPhotoEditorGenericToolView as the tools list shows it (`explicit`): the tool's name on the left, white once it
/// has a value, the value in the accent color on the right, and the slider under them. While the slider is dragged
/// the labels hide and the slider gets its outline; a double tap puts the tool back to zero.
final class PhotoToolRowView: UIView {
    // MARK: Internal

    let tool: PhotoTool

    /// The new value, and whether it came from a reset.
    var onValueChanged: ((Int, Bool) -> Void)?
    var interactionBegan: (() -> Void)?
    var interactionEnded: (() -> Void)?

    // MARK: Private

    private let sliderView = PhotoEditorSliderView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    var isTracking: Bool {
        sliderView.isKnobTracking
    }

    init(tool: PhotoTool, value: Int) {
        self.tool = tool
        super.init(frame: .zero)
        sliderView.enablesPanHandling = true
        sliderView.minimumValue = CGFloat(tool.minimumValue)
        sliderView.maximumValue = CGFloat(tool.maximumValue)
        sliderView.startValue = 0
        sliderView.lineSize = 2
        sliderView.trackCornerRadius = 1
        sliderView.value = CGFloat(value)
        sliderView.accessibilityLabel = L10n.telegram(tool.titleKey)
        sliderView.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        sliderView.onReset = { [weak self] in self?.reset() }
        sliderView.interactionBegan = { [weak self] in
            guard let self else { return }
            setLabelsHidden(true, animated: false)
            interactionBegan?()
        }
        sliderView.interactionEnded = { [weak self] in
            guard let self else { return }
            setLabelsHidden(false, animated: true)
            interactionEnded?()
        }
        titleLabel.font = PhotoEditorColors.itemTitleFont
        titleLabel.text = L10n.telegram(tool.titleKey)
        titleLabel.isUserInteractionEnabled = false
        valueLabel.font = PhotoEditorColors.itemTitleFont
        valueLabel.textAlignment = .right
        valueLabel.textColor = PhotoEditorColors.accent
        valueLabel.isUserInteractionEnabled = false
        addSubview(sliderView)
        addSubview(titleLabel)
        addSubview(valueLabel)
        update(value: value)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let margin = PhotoEditorSliderView.margin + 7
        titleLabel.frame = CGRect(x: PhotoEditorSliderView.margin + 6, y: 4, width: 160, height: 20)
        sliderView.frame = CGRect(x: margin, y: 19, width: bounds.width - margin * 2, height: 32)
        let valueWidth: CGFloat = 100
        valueLabel.frame = CGRect(
            x: bounds.width - PhotoEditorSliderView.margin - valueWidth - 6,
            y: 4,
            width: valueWidth,
            height: 20,
        )
        // The slider takes touches across the whole row.
        let slider = sliderView.frame
        sliderView.hitTestInsets = UIEdgeInsets(
            top: -slider.minY,
            left: -slider.minX,
            bottom: -(bounds.height - slider.maxY),
            right: -slider.minX,
        )
    }

    func setValue(_ value: Int) {
        sliderView.value = CGFloat(value)
        update(value: value)
    }

    /// `updateColor` with the value label: the name turns white once the tool has a value.
    private func update(value: Int) {
        let stringValue = PhotoTool.stringValue(value, maximumValue: tool.maximumValue)
        valueLabel.text = stringValue
        titleLabel.textColor = stringValue == nil ? PhotoEditorColors.itemTitle : PhotoEditorColors.activeItemTitle
        sliderView.accessibilityValue = stringValue ?? "0.00"
    }

    private func setLabelsHidden(_ hidden: Bool, animated: Bool) {
        sliderView.isBordered = hidden
        let changes = {
            self.titleLabel.alpha = hidden ? 0 : 1
            self.valueLabel.alpha = hidden ? 0 : 1
        }
        if animated {
            UIView.animate(withDuration: 0.15, animations: changes)
        } else {
            titleLabel.layer.removeAllAnimations()
            valueLabel.layer.removeAllAnimations()
            changes()
        }
    }

    /// The slider's `reset`: back to the start value.
    private func reset() {
        sliderView.value = sliderView.startValue
        update(value: 0)
        onValueChanged?(0, true)
    }

    @objc private func sliderValueChanged() {
        let value = Int(sliderView.value.rounded(.down))
        update(value: value)
        onValueChanged?(value, false)
    }
}

// MARK: - PhotoToolsListView

/// TGPhotoEditorCollectionView with its TGPhotoToolCells: the slider tools one under another, scrolled vertically.
/// The row being dragged stays while the others hide.
final class PhotoToolsListView: UIView {
    // MARK: Private

    /// The cells' height and the layout's `minimumLineSpacing`.
    private static let rowHeight: CGFloat = 46
    private static let rowSpacing: CGFloat = 6

    // MARK: Internal

    /// A tool's new value, and whether it came from a reset.
    var onValueChanged: ((PhotoTool, Int, Bool) -> Void)?
    var interactionBegan: (() -> Void)?
    var interactionEnded: (() -> Void)?

    private let scrollView = PhotoToolsScrollView()
    private var rows = [PhotoToolRowView]()

    var isTracking: Bool {
        rows.contains(where: \.isTracking)
    }

    init(values: PhotoToolValues) {
        super.init(frame: .zero)
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        for tool in PhotoTool.allCases {
            let row = PhotoToolRowView(tool: tool, value: values[tool])
            row.onValueChanged = { [weak self, weak row] value, isReset in
                guard let self, let row else { return }
                onValueChanged?(row.tool, value, isReset)
            }
            row.interactionBegan = { [weak self, weak row] in
                guard let self, let row else { return }
                setRowsHidden(true, except: row, animated: false)
                interactionBegan?()
            }
            row.interactionEnded = { [weak self, weak row] in
                guard let self, let row else { return }
                setRowsHidden(false, except: row, animated: true)
                interactionEnded?()
            }
            scrollView.addSubview(row)
            rows.append(row)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        var y: CGFloat = 0
        for row in rows {
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: Self.rowHeight)
            y += Self.rowHeight + Self.rowSpacing
        }
        scrollView.contentSize = CGSize(width: bounds.width, height: max(0, y - Self.rowSpacing))
    }

    func setValues(_ values: PhotoToolValues) {
        for row in rows {
            row.setValue(values[row.tool])
        }
    }

    /// `setCellsHidden:excludeCell:`.
    private func setRowsHidden(_ hidden: Bool, except row: PhotoToolRowView, animated: Bool) {
        let changes = {
            for other in self.rows {
                other.alpha = other === row || !hidden ? 1 : 0
            }
        }
        if animated {
            UIView.animate(withDuration: 0.15, animations: changes)
        } else {
            changes()
        }
    }
}

// MARK: - PhotoToolsScrollView

/// The list scrolls only for vertical drags, so a horizontal one goes to the row's slider, whose pan takes only
/// horizontal ones.
private final class PhotoToolsScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            let velocity = panGestureRecognizer.velocity(in: self)
            if abs(velocity.x) > abs(velocity.y) {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

// MARK: - PhotoTintSwatchView

/// TGPhotoEditorTintSwatchView: a color dot, or a white ring for the clear swatch, with the accent ring around the
/// selected one.
private final class PhotoTintSwatchView: UIControl {
    // MARK: Internal

    /// `TGPhotoEditorTintSwatchSize`.
    static let side: CGFloat = 25

    // MARK: Private

    /// `TGPhotoEditorTintSwatchRadius`, the same selected.
    private static let radius: CGFloat = 9
    /// `TGPhotoEditorTintSwatchSelectionRadius`.
    private static let selectionRadius: CGFloat = 12
    /// `TGPhotoEditorTintSwatchSelectionThickness`.
    private static let selectionThickness: CGFloat = 1.5

    override var isSelected: Bool {
        didSet {
            setNeedsDisplay()
            accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    /// `nil` for the clear swatch.
    var color: UInt32? {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let fillColor = color.map(PhotoTintValue.uiColor(of:)) ?? .white
        context.setFillColor(fillColor.cgColor)
        context.setStrokeColor(fillColor.cgColor)
        context.setLineWidth(Self.selectionThickness)
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        if isSelected {
            context.fillEllipse(in: Self.circle(around: center, radius: Self.radius))
            context.setStrokeColor(PhotoEditorColors.accent.cgColor)
            context.strokeEllipse(in: Self.circle(
                around: center,
                radius: Self.selectionRadius - Self.selectionThickness / 2,
            ))
        } else if color == nil {
            context.strokeEllipse(in: Self.circle(around: center, radius: Self.radius - Self.selectionThickness / 2))
        } else {
            context.fillEllipse(in: Self.circle(around: center, radius: Self.radius))
        }
    }

    private static func circle(around center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

// MARK: - PhotoTintToolView

/// TGPhotoEditorTintToolView: Shadows and Highlights at the top, the clear swatch and seven colors for the chosen
/// half, and its intensity under them, tinted with the color and dimmed while the swatch is clear. Dragging across
/// the swatches picks the one under the finger.
final class PhotoTintToolView: UIView, UIGestureRecognizerDelegate {
    // MARK: Internal

    var onValueChanged: ((PhotoTintValue) -> Void)?

    // MARK: Private

    private let sliderView = PhotoEditorSliderView()
    private let buttonsWrapper = PhotoTintButtonsWrapperView()
    private let shadowsButton = UIButton(type: .custom)
    private let highlightsButton = UIButton(type: .custom)
    private lazy var swatchPanRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleSwatchPan(_:)))
    private var swatchViews = [PhotoTintSwatchView]()
    private var value = PhotoTintValue()
    private var isEditingHighlights = false

    var isTracking: Bool {
        sliderView.isKnobTracking
    }

    private var colors: [UInt32?] {
        let palette = isEditingHighlights ? PhotoTintValue.highlightsColors : PhotoTintValue.shadowsColors
        return [nil] + palette.map { Optional($0) }
    }

    private var selectedColor: UInt32? {
        isEditingHighlights ? value.highlightsColor : value.shadowsColor
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        sliderView.minimumValue = 0
        sliderView.maximumValue = 100
        sliderView.startValue = 0
        sliderView.lineSize = 2
        sliderView.trackCornerRadius = 1
        sliderView.trackColor = .white
        sliderView.accessibilityLabel = L10n.telegram("PhotoEditor.TintTool")
        sliderView.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        addSubview(sliderView)
        buttonsWrapper.frame = bounds
        buttonsWrapper.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(buttonsWrapper)
        for _ in 0...PhotoTintValue.shadowsColors.count {
            let swatchView = PhotoTintSwatchView(frame: CGRect(
                x: 0,
                y: 0,
                width: PhotoTintSwatchView.side,
                height: PhotoTintSwatchView.side,
            ))
            swatchView.addTarget(self, action: #selector(swatchPressed(_:)), for: .touchUpInside)
            buttonsWrapper.addSubview(swatchView)
            swatchViews.append(swatchView)
        }
        swatchPanRecognizer.delegate = self
        buttonsWrapper.addGestureRecognizer(swatchPanRecognizer)
        let modeButtons = [(shadowsButton, "PhotoEditor.ShadowsTint"), (highlightsButton, "PhotoEditor.HighlightsTint")]
        for (button, key) in modeButtons {
            button.frame = CGRect(x: 0, y: 0, width: 120, height: 20)
            button.titleLabel?.font = PhotoEditorColors.itemTitleFont
            button.setTitle(L10n.telegram(key), for: .normal)
            button.setTitleColor(PhotoEditorColors.itemTitle, for: .normal)
            button.setTitleColor(.white, for: .selected)
            button.setTitleColor(.white, for: [.selected, .highlighted])
            button.addTarget(self, action: #selector(modeButtonPressed(_:)), for: .touchDown)
            addSubview(button)
        }
        shadowsButton.isSelected = true
        updateSwatches()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    /// Dragging picks swatches only above the slider.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swatchPanRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        return gestureRecognizer.location(in: self).y < sliderView.frame.minY
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let leftEdge: CGFloat = 30
        let count = CGFloat(swatchViews.count)
        let spacing = (bounds.width - leftEdge * 2 - PhotoTintSwatchView.side * count) / (count - 1)
        for (index, swatchView) in swatchViews.enumerated() {
            swatchView.frame = CGRect(
                x: leftEdge + (PhotoTintSwatchView.side + spacing) * CGFloat(index),
                y: 38,
                width: PhotoTintSwatchView.side,
                height: PhotoTintSwatchView.side,
            )
        }
        sliderView.frame = CGRect(
            x: PhotoEditorSliderView.margin,
            y: 70,
            width: bounds.width - PhotoEditorSliderView.margin * 2,
            height: 32,
        )
        shadowsButton.frame.origin = CGPoint(x: floor(bounds.width / 4 - shadowsButton.frame.width / 2 + 20), y: 10)
        highlightsButton.frame.origin = CGPoint(
            x: floor(bounds.width / 4 * 3 - highlightsButton.frame.width / 2 - 20),
            y: 10,
        )
        let slider = sliderView.frame
        sliderView.hitTestInsets = UIEdgeInsets(
            top: -slider.minY,
            left: -slider.minX,
            bottom: -(bounds.height - slider.maxY),
            right: -slider.minX,
        )
    }

    func setValue(_ value: PhotoTintValue) {
        self.value = value
        updateSwatches()
    }

    /// `setHighlightsColors`, `setSelectedColor` and `updateSliderView` for the half being edited.
    private func updateSwatches() {
        let selected = selectedColor
        for (swatchView, color) in zip(swatchViews, colors) {
            swatchView.color = color
            swatchView.isSelected = swatchView.color == selected
        }
        sliderView.value = CGFloat(isEditingHighlights ? value.highlightsIntensity : value.shadowsIntensity)
        let isEnabled = selected != nil
        sliderView.trackColor = selected.map(PhotoTintValue.uiColor(of:)) ?? .white
        sliderView.alpha = isEnabled ? 1 : 0.3
        sliderView.isUserInteractionEnabled = isEnabled
    }

    @objc private func modeButtonPressed(_ sender: UIButton) {
        let editingHighlights = sender === highlightsButton
        shadowsButton.isSelected = !editingHighlights
        highlightsButton.isSelected = editingHighlights
        guard editingHighlights != isEditingHighlights else { return }
        isEditingHighlights = editingHighlights
        updateSwatches()
    }

    @objc private func swatchPressed(_ sender: PhotoTintSwatchView) {
        if isEditingHighlights {
            value.highlightsColor = sender.color
        } else {
            value.shadowsColor = sender.color
        }
        updateSwatches()
        onValueChanged?(value)
    }

    @objc private func sliderValueChanged() {
        let intensity = Int(sliderView.value.rounded(.down))
        if isEditingHighlights {
            value.highlightsIntensity = intensity
        } else {
            value.shadowsIntensity = intensity
        }
        onValueChanged?(value)
    }

    @objc private func handleSwatchPan(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: buttonsWrapper)
        for swatchView in swatchViews where !swatchView.isSelected {
            if point.x >= swatchView.frame.minX, point.x <= swatchView.frame.maxX {
                swatchPressed(swatchView)
                break
            }
        }
    }
}

// MARK: - PhotoTintButtonsWrapperView

/// TGPhotoEditorTintButtonsWrapperView: it holds the swatches and their drag without taking touches between them.
private final class PhotoTintButtonsWrapperView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }
}

// MARK: - PhotoCurvesPanelView

/// TGPhotoEditorCurvesHistogramView: All, Red, Green and Blue at fifths of the width over the channel's histogram.
final class PhotoCurvesPanelView: UIView {
    // MARK: Private

    /// `histogramViewSize` in portrait: the panel and the toolbar without the tool buttons' strip, under the buttons.
    private static let histogramFrameTop: CGFloat = 34
    private static let histogramHeight: CGFloat = 115 + 49 - 53 - 34

    // MARK: Internal

    var onChannelChanged: ((PhotoCurvesChannel) -> Void)?

    private var buttons = [(channel: PhotoCurvesChannel, button: UIButton)]()
    private let histogramView = PhotoHistogramView()
    private var histogram: PhotoHistogram?
    private var channel = PhotoCurvesChannel.luminance

    override init(frame: CGRect) {
        super.init(frame: frame)
        for channel in PhotoCurvesChannel.allCases {
            let button = UIButton(type: .custom)
            button.frame = CGRect(x: 0, y: 0, width: 80, height: 20)
            button.titleLabel?.font = PhotoEditorColors.itemTitleFont
            button.setTitle(L10n.telegram(channel.titleKey), for: .normal)
            button.setTitleColor(PhotoEditorColors.itemTitle, for: .normal)
            button.setTitleColor(.white, for: .selected)
            button.setTitleColor(.white, for: [.selected, .highlighted])
            button.addTarget(self, action: #selector(channelButtonPressed(_:)), for: .touchDown)
            button.isSelected = channel == .luminance
            addSubview(button)
            buttons.append((channel, button))
        }
        addSubview(histogramView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, item) in buttons.enumerated() {
            item.button.frame.origin = CGPoint(
                x: floor(bounds.width / 5 * CGFloat(index + 1) - item.button.frame.width / 2),
                y: 10,
            )
        }
        histogramView.frame = CGRect(
            x: 0,
            y: Self.histogramFrameTop,
            width: bounds.width,
            height: Self.histogramHeight,
        )
    }

    /// The histogram signal's next value: the edited photo's histogram, shown for the chosen channel.
    func setHistogram(_ histogram: PhotoHistogram) {
        self.histogram = histogram
        histogramView.setBins(histogram[channel], channel: channel)
    }

    @objc private func channelButtonPressed(_ sender: UIButton) {
        guard let pressed = buttons.first(where: { $0.button === sender }) else { return }
        let changed = !sender.isSelected
        for item in buttons {
            item.button.isSelected = item.button === sender
        }
        if changed {
            channel = pressed.channel
            histogramView.setBins(histogram?[pressed.channel], channel: pressed.channel)
            onChannelChanged?(pressed.channel)
        }
    }
}

// MARK: - PhotoHistogramView

/// TGHistogramView: a channel's bins as a Catmull-Rom outline filled with the channel's color, morphing to new bins
/// or another channel over 0.25 s.
final class PhotoHistogramView: UIView {
    // MARK: Private

    /// `TGHistogramGranularity`.
    private static let granularity = 20

    private let shapeLayer = CAShapeLayer()
    private var bins: [CGFloat]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        shapeLayer.fillColor = UIColor.white.cgColor
        layer.addSublayer(shapeLayer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = bounds
        shapeLayer.path = path(for: bins)
        CATransaction.commit()
    }

    /// `setHistogram:type:animated:`, always animated as the curves view calls it.
    func setBins(_ bins: [CGFloat]?, channel: PhotoCurvesChannel) {
        self.bins = bins
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        shapeLayer.path = path(for: bins)
        shapeLayer.fillColor = channel.color.cgColor
        CATransaction.commit()
    }

    /// `_bezierPathForHistogramBins:`: from the bottom left up to the first bin, through the bins on a Catmull-Rom
    /// spline clamped to the view, then down past the right edge.
    private func path(for bins: [CGFloat]?) -> CGPath {
        let path = CGMutablePath()
        guard let bins, bins.count >= 4 else { return path }
        let size = bounds.size
        let xStep = size.width / 255
        func point(at index: Int) -> CGPoint {
            CGPoint(x: CGFloat(index) * xStep, y: (1 - bins[index]) * size.height)
        }
        path.move(to: CGPoint(x: -1, y: size.height))
        path.addLine(to: CGPoint(x: -1, y: (1 - bins[0]) * size.height))
        for index in 1..<(bins.count - 2) {
            let point0 = point(at: index - 1)
            let point1 = point(at: index)
            let point2 = point(at: index + 1)
            let point3 = point(at: index + 2)
            for step in 1..<Self.granularity {
                let t = CGFloat(step) / CGFloat(Self.granularity)
                let tt = t * t
                let ttt = tt * t
                let x = PhotoCurve.catmullRom(point0.x, point1.x, point2.x, point3.x, t: t, tt: tt, ttt: ttt)
                let y = PhotoCurve.catmullRom(point0.y, point1.y, point2.y, point3.y, t: t, tt: tt, ttt: ttt)
                if x > point0.x {
                    path.addLine(to: CGPoint(x: x, y: max(0, min(size.height, y))))
                }
            }
            path.addLine(to: point2)
        }
        path.addLine(to: CGPoint(x: size.width + 1, y: (1 - bins[bins.count - 1]) * size.height))
        path.addLine(to: CGPoint(x: size.width + 1, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - PhotoCurvesAreaView

/// TGPhotoEditorCurvesToolView over the photo: the five segments with their levels at the bottom, the dashed
/// diagonal, and the channel's curve. Dragging up or down in a segment moves its level; a double tap straightens
/// the channel again.
final class PhotoCurvesAreaView: UIView, UIGestureRecognizerDelegate {
    // MARK: Internal

    var onValueChanged: ((PhotoCurvesValue) -> Void)?

    /// The photo's frame in this view, which the curve fills.
    var actualArea = CGRect.zero {
        didSet {
            guard actualArea != oldValue else { return }
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    private(set) var channel = PhotoCurvesChannel.luminance

    // MARK: Private

    private let curveLayer = CAShapeLayer()
    private var levelLabels = [UILabel]()
    private lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var pressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
    private lazy var doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
    private var curves = PhotoCurvesValue()
    /// The level being dragged, from the blacks at 0 to the whites at 4.
    private var activeSegment: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        for _ in 0..<5 {
            let label = UILabel()
            label.font = .systemFont(ofSize: 13)
            label.textAlignment = .center
            label.textColor = UIColor(white: 1, alpha: 0.75)
            label.text = "0.00"
            addSubview(label)
            levelLabels.append(label)
        }
        curveLayer.fillColor = UIColor.clear.cgColor
        curveLayer.lineWidth = 2
        curveLayer.lineCap = .round
        layer.addSublayer(curveLayer)
        panRecognizer.delegate = self
        addGestureRecognizer(panRecognizer)
        pressRecognizer.delegate = self
        pressRecognizer.minimumPressDuration = 0.1
        addGestureRecognizer(pressRecognizer)
        doubleTapRecognizer.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapRecognizer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pressRecognizer || gestureRecognizer === panRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        return actualArea.contains(gestureRecognizer.location(in: self))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let segmentWidth = actualArea.width / 5
        let bottomOffset: CGFloat = 4
        for (index, label) in levelLabels.enumerated() {
            let height = ceil(label.intrinsicContentSize.height)
            label.frame = CGRect(
                x: actualArea.minX + segmentWidth * CGFloat(index),
                y: actualArea.maxY - height - bottomOffset,
                width: segmentWidth,
                height: height,
            )
        }
        updateCurve()
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !actualArea.isEmpty else { return }
        let segmentWidth = actualArea.width / 5
        let lineColor = UIColor(white: 1, alpha: 0.6).cgColor
        context.setStrokeColor(lineColor)
        context.setLineWidth(1 - 1 / max(1, traitCollection.displayScale))
        for index in 1...4 {
            let x = actualArea.minX + segmentWidth * CGFloat(index)
            context.move(to: CGPoint(x: x, y: actualArea.minY))
            context.addLine(to: CGPoint(x: x, y: actualArea.maxY))
            context.strokePath()
        }
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [7, 4])
        context.move(to: CGPoint(x: actualArea.minX, y: actualArea.maxY))
        context.addLine(to: CGPoint(x: actualArea.maxX, y: actualArea.minY))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        gestureRecognizer === pressRecognizer || otherGestureRecognizer === pressRecognizer
    }

    func setValue(_ curves: PhotoCurvesValue, channel: PhotoCurvesChannel) {
        self.curves = curves
        self.channel = channel
        updateCurve()
    }

    /// `updateCurve` and `updateValueLabels`.
    private func updateCurve() {
        let curve = curves[channel]
        for (label, level) in zip(levelLabels, curve.levels) {
            label.text = String(format: "%0.2f", level / 100)
        }
        guard !actualArea.isEmpty else { return }
        let path = UIBezierPath()
        for (index, point) in curve.interpolated().points.enumerated() {
            let viewPoint = CGPoint(x: point.x * actualArea.width, y: (1 - point.y) * actualArea.height)
            if index == 0 {
                path.move(to: viewPoint)
            } else {
                path.addLine(to: viewPoint)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        curveLayer.strokeColor = channel.color.cgColor
        curveLayer.path = path.cgPath
        curveLayer.frame = actualArea
        CATransaction.commit()
    }

    private func selectSegment(at point: CGPoint) {
        guard activeSegment == nil, actualArea.width > 0 else { return }
        let segmentWidth = actualArea.width / 5
        activeSegment = min(4, max(0, Int(((point.x - actualArea.minX) / segmentWidth).rounded(.down))))
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            selectSegment(at: recognizer.location(in: self))
        case .cancelled, .ended, .failed:
            activeSegment = nil
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            selectSegment(at: recognizer.location(in: self))
        case .changed:
            guard let activeSegment else { return }
            let translation = recognizer.translation(in: self)
            let delta = min(2, -translation.y / 8)
            var curve = curves[channel]
            curve.levels[activeSegment] = max(0, min(100, curve.levels[activeSegment] + delta))
            curves[channel] = curve
            updateCurve()
            onValueChanged?(curves)
            recognizer.setTranslation(.zero, in: self)
        case .cancelled, .ended, .failed:
            activeSegment = nil
        default:
            break
        }
    }

    @objc private func handleDoubleTap() {
        curves[channel] = PhotoCurve()
        updateCurve()
        onValueChanged?(curves)
    }
}
