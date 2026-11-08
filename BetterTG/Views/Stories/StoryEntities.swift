// StoryEntities.swift

import UIKit

// MARK: - StoryEntitiesView

/// MediaEditorScreen's DrawingEntitiesView for a story: a canvas in story coordinates (storyDimensions, 1080 by 1920)
/// that the preview scales onto the story, holding its text entities. A tap on an empty spot adds text, as
/// insertTextEntity does, and a tap on a text edits it; a text moves with a pan and turns and scales with two fingers.
/// While a text is edited the rest fades under 40% black, and a tap on it ends the editing; an emptied text goes.
final class StoryEntitiesView: UIView, UIGestureRecognizerDelegate {
    nonisolated static let size = CGSize(width: 1080, height: 1920)

    var onEditingChange: ((Bool) -> Void)?
    /// Whether a tap on an empty spot may add a text now.
    var shouldInsertText: (() -> Bool)?
    /// Where an edited text stands, in story points: getEntityCenterPosition's centre, or on a screen too short for it
    /// the middle of the story the keyboard leaves in sight.
    var editingCenter: (() -> CGPoint)?

    private(set) var editingEntity: StoryTextEntityView?
    /// TextSettingsComponent over the keyboard while a text is edited.
    let settingsBar = StoryTextSettingsBar()
    /// MediaEditorScreen's DrawingView, under the entities.
    let drawingView = StoryDrawingView(frame: CGRect(origin: .zero, size: StoryEntitiesView.size))

    /// DrawingScreen on: a finger draws, and the entities hold still.
    var isDrawing = false {
        didSet {
            drawingView.isUserInteractionEnabled = isDrawing
            for recognizer in gestureRecognizers ?? [] {
                recognizer.isEnabled = !isDrawing
            }
        }
    }

    private let fadeView = UIView()
    private var gestureEntity: StoryTextEntityView?

    var textEntities: [StoryTextEntityView] {
        subviews.compactMap { $0 as? StoryTextEntityView }
    }

    /// updateEditingPosition: the centre, or for a left or right aligned text 80 pt from that edge.
    private var editingPosition: CGPoint {
        var position = editingCenter?() ?? CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        if let entity = editingEntity {
            let width = entity.bounds.width
            switch entity.alignment {
            case .left: position.x = 80 + width / 2
            case .right: position.x = Self.size.width - 80 - width / 2
            default: break
            }
        }
        return position
    }

    override init(frame _: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        fadeView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        fadeView.frame = bounds
        fadeView.alpha = 0
        fadeView.isUserInteractionEnabled = false
        drawingView.isUserInteractionEnabled = false
        addSubview(drawingView)
        addSubview(fadeView)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
        for recognizer in [pan, pinch, rotation] as [UIGestureRecognizer] {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// insertTextEntity: Telegram's default text, white and filled, at the story's centre.
    func insertText() {
        guard editingEntity == nil else { return }
        let entity = StoryTextEntityView()
        entity.center = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        addSubview(entity)
        beginEditing(entity)
    }

    func endEditing() {
        guard let entity = editingEntity else { return }
        editingEntity = nil
        entity.endEditing()
        UIView.animate(withDuration: 0.3) { self.fadeView.alpha = 0 }
        if entity.isEmpty {
            entity.removeFromSuperview()
        } else {
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                usingSpringWithDamping: 0.65,
                initialSpringVelocity: 0,
            ) { entity.applyPlacement() }
        }
        onEditingChange?(false)
    }

    /// The entities alone on a clear 1080 by 1920 image, or nil without any.
    func renderOverlay() -> UIImage? {
        guard !textEntities.isEmpty || !drawingView.strokes.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let hidden = fadeView.isHidden
        fadeView.isHidden = true
        defer { fadeView.isHidden = hidden }
        return UIGraphicsImageRenderer(size: Self.size, format: format).image { context in
            layer.render(in: context.cgContext)
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        !(gestureRecognizer is UITapGestureRecognizer) && !(otherGestureRecognizer is UITapGestureRecognizer)
    }

    /// updateEditingPosition: the edited text follows the room the keyboard leaves.
    func updateEditingPosition() {
        guard let entity = editingEntity else { return }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0) {
            entity.center = self.editingPosition
        }
    }

    /// DrawingTextEntityView.beginEditing: the text comes to the middle unturned at its own size, over the fade.
    private func beginEditing(_ entity: StoryTextEntityView) {
        editingEntity = entity
        bringSubviewToFront(fadeView)
        bringSubviewToFront(entity)
        UIView.animate(withDuration: 0.3) { self.fadeView.alpha = 1 }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0) {
            entity.transform = .identity
            entity.center = self.editingPosition
        }
        settingsBar.entity = entity
        settingsBar.onChange = { [weak self] in self?.updateEditingPosition() }
        entity.onChange = { [weak self] in self?.updateEditingPosition() }
        entity.beginEditing(accessoryView: settingsBar)
        onEditingChange?(true)
    }

    private func entity(at point: CGPoint) -> StoryTextEntityView? {
        textEntities.reversed().first { entity in
            entity.point(inside: convert(point, to: entity), with: nil)
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        if editingEntity != nil {
            endEditing()
            return
        }
        if let entity = entity(at: gesture.location(in: self)) {
            beginEditing(entity)
        } else if shouldInsertText?() ?? true {
            insertText()
        }
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard editingEntity == nil else { return }
        if gesture.state == .began { gestureEntity = entity(at: gesture.location(in: self)) }
        guard let entity = gestureEntity else { return }
        let translation = gesture.translation(in: self)
        entity.position = CGPoint(x: entity.position.x + translation.x, y: entity.position.y + translation.y)
        entity.applyPlacement()
        gesture.setTranslation(.zero, in: self)
        if gesture.state == .ended || gesture.state == .cancelled { gestureEntity = nil }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard editingEntity == nil else { return }
        if gesture.state == .began, gestureEntity == nil { gestureEntity = entity(at: gesture.location(in: self)) }
        guard let entity = gestureEntity else { return }
        entity.scale = max(0.2, min(entity.scale * gesture.scale, 10))
        entity.applyPlacement()
        gesture.scale = 1
    }

    @objc private func rotated(_ gesture: UIRotationGestureRecognizer) {
        guard editingEntity == nil else { return }
        if gesture.state == .began, gestureEntity == nil { gestureEntity = entity(at: gesture.location(in: self)) }
        guard let entity = gestureEntity else { return }
        entity.rotation += gesture.rotation
        entity.applyPlacement()
        gesture.rotation = 0
    }
}

// MARK: - StoryTextEntityView

/// DrawingTextEntityView with DrawingEntitiesView's new text: SF semibold at displayFontSize (48 + 432 × fontSize story
/// points, fontSize 0.08 to start), 972 pt wide (90% of the story), centred, white in the filled style. The view is at
/// least 224 pt wide and 20 pt wider than the text. The styles follow DrawingTextEntityView.update: regular draws the
/// colour with a shadow, filled a black or white text on a frame in the colour, semi the colour on a 75% black or
/// white frame.
final class StoryTextEntityView: UIView, UITextViewDelegate {
    enum Style {
        case regular
        case filled
        case semi
    }

    /// DrawingScreen's presentFontPicker fonts, nil for San Francisco.
    static let fonts: [(name: String?, title: String)] = [
        (nil, "San Francisco"),
        ("AmericanTypewriter", "Typewriter"),
        ("AvenirNext-DemiBoldItalic", "Avenir Next"),
        ("CourierNewPS-BoldMT", "Courier New"),
        ("Noteworthy-Bold", "Noteworthy"),
        ("Georgia-Bold", "Georgia"),
        ("Papyrus", "Papyrus"),
        ("SnellRoundhand-Bold", "Snell Roundhand"),
    ]

    static let textWidth: CGFloat = 972

    var position = CGPoint.zero
    var scale: CGFloat = 1
    var rotation: CGFloat = 0
    var style = Style.filled
    var alignment = NSTextAlignment.center
    var fontName: String?
    var color = UIColor.white
    /// DrawingTextEntity.fontSize, 0 to 1 between a fortieth and a quarter of the story's height.
    var fontSize: CGFloat = 0.08
    var onChange: (() -> Void)?

    private let textView: UITextView
    private let layoutManager = StoryTextLayoutManager()

    var isEmpty: Bool {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var fontTitle: String {
        Self.fonts.first { $0.name == fontName }?.title ?? "San Francisco"
    }

    init() {
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: Self.textWidth, height: .greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        self.textView = UITextView(frame: .zero, textContainer: container)
        super.init(frame: CGRect(x: 0, y: 0, width: 224, height: 100))
        textView.backgroundColor = .clear
        textView.clipsToBounds = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.keyboardAppearance = .dark
        textView.spellCheckingType = .no
        textView.delegate = self
        addSubview(textView)
        update()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
    }

    /// UIColor.lightness: Rec. 709 luma.
    static func lightness(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: nil) {
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        var white: CGFloat = 0
        return color.getWhite(&white, alpha: nil) ? white : 0
    }

    func beginEditing(accessoryView: UIView?) {
        position = isEmpty ? center : position
        textView.inputAccessoryView = accessoryView
        textView.isEditable = true
        textView.isSelectable = true
        textView.becomeFirstResponder()
    }

    func endEditing() {
        textView.inputAccessoryView = nil
        textView.resignFirstResponder()
        textView.isEditable = false
        textView.isSelectable = false
    }

    /// suspendEditing and resumeEditing around the colour picker.
    func suspendEditing() {
        textView.resignFirstResponder()
    }

    func resumeEditing() {
        textView.becomeFirstResponder()
    }

    /// The entity's position, scale and rotation, as DrawingTextEntityView.update applies them.
    func applyPlacement() {
        center = position
        transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
    }

    /// DrawingTextEntityView.update and updateText: the font, colours, frame, shadow and alignment, then the size.
    func update() {
        let size = 48 + (480 - 48) * fontSize
        let font = fontName.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size, weight: .semibold)
        textView.textContainer.lineFragmentPadding = floor(size * 0.24)
        let lightness = Self.lightness(color)
        let textColor: UIColor
        var cursorColor = UIColor.white
        switch style {
        case .regular:
            textColor = color
            layoutManager.frameColor = nil
        case .filled:
            textColor = lightness > 0.99 ? .black : .white
            cursorColor = lightness > 0.99 ? UIColor(red: 0, green: 0x88 / 255, blue: 1, alpha: 1) : .white
            layoutManager.frameColor = color
        case .semi:
            textColor = color
            layoutManager.frameColor = lightness > 0.7
                ? UIColor.black.withAlphaComponent(0.75)
                : UIColor.white.withAlphaComponent(0.75)
        }
        textView.layer.shadowColor = style == .regular ? UIColor.black.cgColor : nil
        textView.layer.shadowOffset = style == .regular ? CGSize(width: 0, height: 4) : .zero
        textView.layer.shadowOpacity = style == .regular ? 0.4 : 0
        textView.layer.shadowRadius = style == .regular ? 4 : 0
        textView.tintColor = isEmpty ? .white : cursorColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]
        let selection = textView.selectedRange
        textView.attributedText = NSAttributedString(string: textView.text ?? "", attributes: attributes)
        textView.typingAttributes = attributes
        textView.selectedRange = selection
        textView.textAlignment = alignment
        resize()
        textView.setNeedsDisplay()
        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textView.textStorage.length))
    }

    func textViewDidChange(_: UITextView) {
        textView.tintColor = isEmpty ? .white : textView.tintColor
        resize()
        textView.setNeedsDisplay()
        onChange?()
    }

    /// sizeThatFits: the text at the entity's width, at least 224 pt and 20 pt wider than it.
    private func resize() {
        let fitted = textView.sizeThatFits(CGSize(width: Self.textWidth, height: .greatestFiniteMagnitude))
        let center = center
        let transform = transform
        self.transform = .identity
        bounds.size = CGSize(width: max(224, ceil(fitted.width) + 20), height: ceil(fitted.height))
        self.center = center
        self.transform = transform
    }
}

// MARK: - StoryTextLayoutManager

/// DrawingTextLayoutManager's filled frame: each line's used rect, a line within 2.5 radii of its neighbour's edge
/// taking that edge, filled as rounded rects with a fifth of the line height for the corners, and the corners where
/// lines meet filled in or cut out with arcs.
private final class StoryTextLayoutManager: NSLayoutManager {
    var frameColor: UIColor?

    private var rects = [CGRect]()
    private var radius: CGFloat = 8

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let frameColor, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.setBlendMode(.copy)
        context.setFillColor(frameColor.cgColor)
        context.setStrokeColor(frameColor.cgColor)
        prepare()
        let path = UIBezierPath()
        var last = CGRect.null
        for (index, current) in rects.enumerated() {
            radius = current.height * 0.2
            path.append(UIBezierPath(roundedRect: current, cornerRadius: radius))
            if index > 0, abs(last.maxY - current.minY) < 15 {
                appendJoins(to: path, last: last, current: current)
            }
            last = current
        }
        path.fill()
        path.stroke()
        context.restoreGState()
    }

    private func prepare() {
        rects = []
        let string = (textStorage?.string ?? "") as NSString
        enumerateLineFragments(forGlyphRange: NSRange(
            location: 0,
            length: string.length,
        )) { _, usedRect, _, glyphRange, _ in
            let characters = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let substring = string.substring(with: characters)
            guard !substring.trimmingCharacters(in: .newlines).isEmpty else { return }
            var used = usedRect
            if substring.hasSuffix(" ") { used.size.width -= floor(used.height * 0.145) }
            self.rects.append(used)
        }
        guard rects.count >= 2 else { return }
        for index in 1..<rects.count {
            process(index)
        }
    }

    /// processRectIndex: neighbouring lines whose edges nearly line up share the wider edge.
    private func process(_ index: Int) {
        guard rects.count >= 2, index > 0, index < rects.count else { return }
        var last = rects[index - 1]
        var current = rects[index]
        radius = current.height * 0.2
        let doubleRadius = radius * 2.5
        let lastTakes = ((last.minX - current.minX < doubleRadius) && (last.minX > current.minX))
            || ((last.maxX - current.maxX > -doubleRadius) && (last.maxX < current.maxX))
        if lastTakes {
            rects[index - 1] = CGRect(x: current.minX, y: last.minY, width: current.width, height: last.height)
            process(index - 1)
        }
        last = rects[index - 1]
        current = rects[index]
        let currentTakes = ((current.minX - last.minX < doubleRadius) && (current.minX > last.minX))
            || ((current.maxX - last.maxX > -doubleRadius) && (current.maxX < last.maxX))
        if currentTakes {
            rects[index] = CGRect(x: last.minX, y: current.minY, width: last.width, height: current.height)
            process(index + 1)
        }
    }

    private func appendJoins(to path: UIBezierPath, last: CGRect, current: CGRect) {
        let a = current.origin
        let b = CGPoint(x: current.maxX, y: current.minY)
        let c = CGPoint(x: last.minX, y: last.maxY)
        let d = CGPoint(x: last.maxX, y: last.maxY)
        let r = radius
        if a.x - c.x >= 2 * r {
            let add = UIBezierPath(
                arcCenter: CGPoint(x: a.x - r, y: a.y + r), radius: r, startAngle: .pi * 1.5, endAngle: 0,
                clockwise: true,
            )
            add.append(UIBezierPath(
                arcCenter: CGPoint(x: a.x + r, y: a.y + r), radius: r, startAngle: .pi, endAngle: .pi * 1.5,
                clockwise: true,
            ))
            add.addLine(to: CGPoint(x: a.x - r, y: a.y))
            path.append(add)
        }
        if a.x == c.x {
            path.move(to: CGPoint(x: a.x, y: a.y - r))
            path.addLine(to: CGPoint(x: a.x, y: a.y + r))
            path.addArc(
                withCenter: CGPoint(x: a.x + r, y: a.y + r),
                radius: r,
                startAngle: .pi,
                endAngle: .pi * 1.5,
                clockwise: true,
            )
            path.addArc(
                withCenter: CGPoint(x: a.x + r, y: a.y - r),
                radius: r,
                startAngle: .pi * 0.5,
                endAngle: .pi,
                clockwise: true,
            )
        }
        if d.x - b.x >= 2 * r {
            let add = UIBezierPath(
                arcCenter: CGPoint(x: b.x + r, y: b.y + r), radius: r, startAngle: .pi * 1.5, endAngle: .pi,
                clockwise: false,
            )
            add.append(UIBezierPath(
                arcCenter: CGPoint(x: b.x - r, y: b.y + r), radius: r, startAngle: 0, endAngle: .pi * 1.5,
                clockwise: false,
            ))
            add.addLine(to: CGPoint(x: b.x + r, y: b.y))
            path.append(add)
        }
        if d.x == b.x {
            path.move(to: CGPoint(x: b.x, y: b.y - r))
            path.addLine(to: CGPoint(x: b.x, y: b.y + r))
            path.addArc(
                withCenter: CGPoint(x: b.x - r, y: b.y + r),
                radius: r,
                startAngle: 0,
                endAngle: .pi * 1.5,
                clockwise: false,
            )
            path.addArc(
                withCenter: CGPoint(x: b.x - r, y: b.y - r),
                radius: r,
                startAngle: .pi * 0.5,
                endAngle: 0,
                clockwise: false,
            )
        }
        if c.x - a.x >= 2 * r {
            let add = UIBezierPath(
                arcCenter: CGPoint(x: c.x - r, y: c.y - r), radius: r, startAngle: .pi * 0.5, endAngle: 0,
                clockwise: false,
            )
            add.append(UIBezierPath(
                arcCenter: CGPoint(x: c.x + r, y: c.y - r), radius: r, startAngle: .pi, endAngle: .pi * 0.5,
                clockwise: false,
            ))
            add.addLine(to: CGPoint(x: c.x - r, y: c.y))
            path.append(add)
        }
        if b.x - d.x >= 2 * r {
            let add = UIBezierPath(
                arcCenter: CGPoint(x: d.x + r, y: d.y - r), radius: r, startAngle: .pi * 0.5, endAngle: .pi,
                clockwise: true,
            )
            add.append(UIBezierPath(
                arcCenter: CGPoint(x: d.x - r, y: d.y - r), radius: r, startAngle: 0, endAngle: .pi * 0.5,
                clockwise: true,
            ))
            add.addLine(to: CGPoint(x: d.x + r, y: d.y))
            path.append(add)
        }
    }
}

// MARK: - StoryTextSettingsBar

/// TextSettingsComponent, 44 pt over the keyboard: the colour swatch, the style (regular, filled, semi in
/// toggleStyle's turn), the alignment (left, centre, right) and the font in its own face with FontArrow, 16 pt from the
/// right edge, which opens presentFontPicker's fonts.
final class StoryTextSettingsBar: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    weak var entity: StoryTextEntityView? {
        didSet { refresh() }
    }

    var onColor: (() -> Void)?
    var onChange: (() -> Void)?
    /// presentFontPicker from the font button.
    var onFonts: ((UIView) -> Void)?

    private let colorButton = StoryColorSwatchButton()
    private let styleButton = UIButton(type: .custom)
    private let alignmentButton = StoryAlignmentButton()
    private let fontButton = UIButton(type: .custom)
    private let fontLabel = UILabel()
    private let fontArrow = UIImageView(image: UIImage(named: "MediaEditor/FontArrow")?
        .withRenderingMode(.alwaysTemplate))

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        autoresizingMask = .flexibleWidth
        colorButton.onTap = { [weak self] in self?.onColor?() }
        colorButton.onPick = { [weak self] color in
            guard let self, let entity else { return }
            entity.color = color
            entity.update()
            colorButton.color = color
        }
        styleButton.addAction(UIAction { [weak self] _ in self?.toggleStyle() }, for: .touchUpInside)
        alignmentButton.addAction(UIAction { [weak self] _ in self?.toggleAlignment() }, for: .touchUpInside)
        fontButton.layer.cornerRadius = 11
        fontButton.layer.borderColor = UIColor.white.cgColor
        fontButton.clipsToBounds = true
        fontLabel.textColor = .white
        fontLabel.isUserInteractionEnabled = false
        fontButton.addSubview(fontLabel)
        fontButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onFonts?(fontButton)
        }, for: .touchUpInside)
        fontArrow.tintColor = UIColor.white.withAlphaComponent(0.5)
        fontButton.addSubview(fontArrow)
        for view in [colorButton, styleButton, alignmentButton, fontButton] {
            addSubview(view)
        }
        refresh()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// TextSettingsComponent's offsets: the swatch 2 pt in, the style 48 pt on, the alignment 44 pt after it.
    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        colorButton.frame = CGRect(x: 2, y: (height - 44) / 2, width: 44, height: 44)
        styleButton.frame = CGRect(x: 48, y: (height - 44) / 2, width: 44, height: 44)
        alignmentButton.frame = CGRect(x: 92, y: (height - 44) / 2 + 1, width: 44, height: 44)
        let titleSize = fontLabel.sizeThatFits(bounds.size)
        let width = ceil(titleSize.width) + 40
        fontButton.frame = CGRect(x: bounds.width - 16 - width, y: (height - 30) / 2, width: width, height: 30)
        fontButton.layer.borderWidth = 1 - 1 / max(1, traitCollection.displayScale)
        fontLabel.frame = CGRect(
            x: 10,
            y: ((30 - titleSize.height) / 2).rounded(),
            width: ceil(titleSize.width),
            height: ceil(titleSize.height),
        )
        fontArrow.frame = CGRect(x: width - 16 - 8, y: 7, width: 16, height: 16)
    }

    func refresh() {
        guard let entity else { return }
        colorButton.color = entity.color
        let imageName =
            switch entity.style {
            case .regular: "MediaEditor/TextDefault"
            case .filled: "MediaEditor/TextFilled"
            case .semi: "MediaEditor/TextSemi"
            }
        styleButton.setImage(UIImage(named: imageName), for: .normal)
        alignmentButton.alignment = entity.alignment
        fontLabel.text = entity.fontTitle
        let size: CGFloat = 13
        fontLabel.font = entity.fontName.flatMap { UIFont(name: $0, size: size) }
            ?? .systemFont(ofSize: size, weight: .semibold)
        fontButton.accessibilityLabel = entity.fontTitle
        setNeedsLayout()
    }

    /// presentFontPicker's choice.
    func chooseFont(_ name: String?) {
        entity?.fontName = name
        changed()
    }

    private func toggleStyle() {
        guard let entity else { return }
        entity.style =
            switch entity.style {
            case .regular: .filled
            case .filled: .semi
            case .semi: .regular
            }
        changed()
    }

    private func toggleAlignment() {
        guard let entity else { return }
        entity.alignment =
            switch entity.alignment {
            case .left: .center
            case .center: .right
            default: .left
            }
        changed()
    }

    private func changed() {
        entity?.update()
        refresh()
        onChange?()
    }
}

// MARK: - StoryColorSwatchButton

/// ColorSwatchComponent's main swatch: the colour in a 38 pt circle inside RoundSpectrum's 2 pt ring, the ring alone
/// without a colour.
final class StoryColorSwatchButton: UIControl {
    override var isHighlighted: Bool {
        didSet { contentAlpha = isHighlighted ? 0.6 : 1 }
    }

    var color: UIColor? = .white {
        didSet { circle.fillColor = color?.cgColor }
    }

    /// A tap: the full colour picker.
    var onTap: (() -> Void)?
    /// presentFastColorPicker: a colour picked from the spectrum held open under the finger.
    var onPick: ((UIColor) -> Void)?

    private let ring = CALayer()
    private let ringMask = CAShapeLayer()
    private let circle = CAShapeLayer()
    private let fastCircle = CAShapeLayer()
    private var holdTimer: Timer?
    private var holdTriggered = false
    private weak var fastPicker: StoryFastColorPicker?

    private var contentAlpha: CGFloat = 1 {
        didSet {
            ring.opacity = Float(contentAlpha)
            circle.opacity = Float(contentAlpha)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        ring.contents = UIImage(named: "MediaEditor/RoundSpectrum")?.cgImage
        ringMask.fillColor = UIColor.clear.cgColor
        ringMask.strokeColor = UIColor.white.cgColor
        ringMask.lineWidth = 2
        ring.mask = ringMask
        layer.addSublayer(ring)
        circle.fillColor = color?.cgColor
        layer.addSublayer(circle)
        fastCircle.fillColor = UIColor.white.cgColor
        fastCircle.isHidden = true
        layer.addSublayer(fastCircle)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let ringFrame = bounds.insetBy(dx: -1, dy: -1)
        ring.frame = ringFrame
        ringMask.frame = CGRect(origin: .zero, size: ringFrame.size)
        ringMask.path = UIBezierPath(ovalIn: ringMask.bounds.insetBy(dx: 1, dy: 1)).cgPath
        circle.frame = bounds
        circle.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3)).cgPath
        fastCircle.frame = bounds
        fastCircle.path = UIBezierPath(ovalIn: bounds).cgPath
    }

    /// ColorSwatchComponent.beginTracking: past 0.15 s a white circle swells in the swatch, and at 0.4 s the spectrum
    /// opens.
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        holdTriggered = false
        guard onPick != nil, isEnabled else { return super.beginTracking(touch, with: event) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, isTracking, !holdTriggered else { return }
            fastCircle.isHidden = false
            let alpha = CABasicAnimation(keyPath: "opacity")
            alpha.fromValue = 0
            alpha.toValue = 1
            alpha.duration = 0.15
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.57575
            scale.toValue = 1
            scale.duration = 0.25
            fastCircle.add(alpha, forKey: "opacity")
            fastCircle.add(scale, forKey: "scale")
        }
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.openFastPicker() }
        }
        return super.beginTracking(touch, with: event)
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if holdTriggered {
            fastPicker?.pan(to: touch.location(in: nil))
            return true
        }
        return super.continueTracking(touch, with: event)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        finishHold()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        finishHold()
    }

    @objc private func tapped() {
        guard !holdTriggered else { return }
        onTap?()
    }

    private func openFastPicker() {
        guard isTracking, let window, let onPick else { return }
        holdTriggered = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.fastCircle.isHidden = true }
        let frame = convert(bounds, to: window)
        let size = CGSize(width: min(350, window.bounds.width - 8 - 24), height: 296)
        let picker = StoryFastColorPicker(frame: CGRect(
            origin: CGPoint(x: frame.minX + 5, y: frame.maxY - size.height - 6),
            size: size,
        ))
        picker.onPick = onPick
        window.addSubview(picker)
        picker.animateIn()
        fastPicker = picker
    }

    private func finishHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        fastCircle.isHidden = true
        fastPicker?.animateOut()
        fastPicker = nil
    }
}

// MARK: - StoryFastColorPicker

/// ColorSpectrumPickerView: Telegram's spectrum over its grey ramp in a 17 pt round panel that grows out of the
/// swatch's corner over 0.35 s and picks white at first; the finger picks the colour under it, shown in a 26 pt circle
/// inside the 32 pt white knob 33 pt above the finger. Let go, the panel fills with the colour and shrinks back into
/// the swatch.
final class StoryFastColorPicker: UIView {
    var onPick: ((UIColor) -> Void)?

    private let wrapper = UIView()
    private let image = UIImageView()
    private let circleMask = UIView()
    private let maskCircle = CAShapeLayer()
    private let knob = CALayer()
    private let circle = CAShapeLayer()
    private var pixels = [UInt8]()
    private var pixelSize = (width: 0, height: 0)
    private var selected: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        wrapper.frame = bounds
        wrapper.clipsToBounds = true
        wrapper.layer.cornerRadius = 17
        addSubview(wrapper)
        image.frame = bounds
        image.image = Self.spectrum(size: bounds.size)
        wrapper.addSubview(image)
        knob.contents = Self.knobImage().cgImage
        knob.isHidden = true
        layer.addSublayer(knob)
        circle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 26, height: 26)).cgPath
        circle.isHidden = true
        layer.addSublayer(circle)
        readPixels()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// generateSpectrumImage: the Spectrum picture with the Grayscale ramp over it.
    private static func spectrum(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(named: "MediaEditor/Spectrum")?.draw(in: CGRect(origin: .zero, size: size))
            UIImage(named: "MediaEditor/Grayscale")?.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// generateKnobImage: a 32 pt white circle with a 9 pt shadow at 30%.
    private static func knobImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 52, height: 52)).image { context in
            context.cgContext.setShadow(offset: .zero, blur: 9, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: 10, y: 10, width: 32, height: 32))
        }
    }

    func animateIn() {
        circleMask.frame = bounds
        maskCircle.fillColor = UIColor.black.cgColor
        maskCircle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 300, height: 300)).cgPath
        maskCircle.bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        maskCircle.position = CGPoint(x: 15, y: bounds.height - 15)
        circleMask.layer.addSublayer(maskCircle)
        wrapper.mask = circleMask
        maskCircle.transform = CATransform3DMakeScale(3, 3, 1)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.05
        grow.toValue = 3
        grow.duration = 0.35
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.wrapper.mask = nil }
        maskCircle.add(grow, forKey: "grow")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, selected == nil else { return }
            onPick?(.white)
        }
    }

    /// handlePan: the colour under the finger, in window points, kept inside the panel.
    func pan(to point: CGPoint) {
        var location = convert(point, from: nil)
        location.x = max(0, min(bounds.width - 1, location.x))
        location.y = max(0, min(bounds.height - 1, location.y))
        guard let color = color(at: location) else { return }
        selected = color
        onPick?(color)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let knobFrame = CGRect(x: location.x - 16, y: location.y - 16 - 33, width: 32, height: 32)
        knob.frame = knobFrame.insetBy(dx: -10, dy: -10)
        circle.frame = knobFrame.insetBy(dx: 3, dy: 3)
        circle.fillColor = color.cgColor
        knob.isHidden = false
        circle.isHidden = false
        CATransaction.commit()
    }

    func animateOut() {
        if let selected { onPick?(selected) }
        knob.isHidden = true
        circle.isHidden = true
        let filler = UIView(frame: bounds)
        filler.backgroundColor = selected ?? .white
        filler.alpha = 0
        wrapper.addSubview(filler)
        UIView.animate(withDuration: 0.25) { filler.alpha = 1 }
        circleMask.frame = bounds
        if maskCircle.superlayer == nil {
            maskCircle.fillColor = UIColor.black.cgColor
            maskCircle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 300, height: 300)).cgPath
            maskCircle.bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
            circleMask.layer.addSublayer(maskCircle)
        }
        wrapper.mask = circleMask
        maskCircle.position = CGPoint(x: 16, y: bounds.height - 16)
        maskCircle.transform = CATransform3DMakeScale(0.06333, 0.06333, 1)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 3
        shrink.toValue = 0.06333
        shrink.duration = 0.35
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = CGPoint(x: 15, y: bounds.height - 15)
        move.duration = 0.25
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.removeFromSuperview() }
        maskCircle.add(shrink, forKey: "shrink")
        maskCircle.add(move, forKey: "move")
        CATransaction.commit()
    }

    private func readPixels() {
        guard let cgImage = image.image?.cgImage else { return }
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return }
        pixels = buffer
        pixelSize = (width, height)
    }

    /// getColor(at:): the spectrum's pixel under the point.
    private func color(at point: CGPoint) -> UIColor? {
        guard pixelSize.width > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        let x = min(pixelSize.width - 1, Int(point.x / bounds.width * CGFloat(pixelSize.width)))
        let y = min(pixelSize.height - 1, Int(point.y / bounds.height * CGFloat(pixelSize.height)))
        let offset = (y * pixelSize.width + x) * 4
        return UIColor(
            red: CGFloat(pixels[offset]) / 255,
            green: CGFloat(pixels[offset + 1]) / 255,
            blue: CGFloat(pixels[offset + 2]) / 255,
            alpha: 1,
        )
    }
}

// MARK: - StoryAlignmentButton

/// TextAlignmentComponent: four white 2 pt lines, 21 and 13 pt long in turn, 3 pt apart, lined up as the text is.
final class StoryAlignmentButton: UIControl {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    var alignment = NSTextAlignment.center {
        didSet { setNeedsLayout() }
    }

    private let lines = (0..<4).map { _ in CALayer() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for line in lines {
            line.backgroundColor = UIColor.white.cgColor
            line.cornerRadius = 1
            layer.addSublayer(line)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pixel = 1 / max(1, traitCollection.displayScale)
        let height = 2 - pixel
        let spacing = 3 + pixel
        let long: CGFloat = 21
        let short: CGFloat = 13
        let boxHeight = height * 4 + spacing * 3
        let origin = CGPoint(x: (bounds.width - long) / 2, y: (bounds.height - boxHeight) / 2)
        for (index, line) in lines.enumerated() {
            let width = index.isMultiple(of: 2) ? long : short
            let x: CGFloat =
                switch alignment {
                case .left: 0
                case .right: long - width
                default: floor((long - width) / 2)
                }
            line.frame = CGRect(
                x: origin.x + x,
                y: origin.y + CGFloat(index) * (height + spacing),
                width: width,
                height: height,
            )
        }
    }
}

// MARK: - StoryTextSizeSlider

/// TextSizeSliderComponent: a 30 by 240 pt wedge (15 pt round at the top, 3 pt at the bottom) in translucent grey at
/// the screen's edge, half of it out of sight until touched, when it comes 8 pt in; the 32 pt white knob with its
/// shadow stands at the size, top for the largest, and a press or a drag sets the size from the touch.
final class StoryTextSizeSlider: UIView, UIGestureRecognizerDelegate {
    var value: CGFloat = 0.5 {
        didSet { setNeedsLayout() }
    }

    var onChange: ((CGFloat) -> Void)?
    var onRelease: (() -> Void)?

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let backgroundMask = CAShapeLayer()
    private let knobContainer = CALayer()
    private let knob = CALayer()
    private var isTracking = false

    override init(frame _: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 240))
        isExclusiveTouch = true
        background.isUserInteractionEnabled = false
        background.contentView.backgroundColor = UIColor(white: 0x88 / 255, alpha: 0.3)
        background.layer.mask = backgroundMask
        addSubview(background)
        knob.contents = Self.knobImage().cgImage
        knobContainer.addSublayer(knob)
        layer.addSublayer(knobContainer)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(touched(_:)))
        press.minimumPressDuration = 0.01
        press.delegate = self
        addGestureRecognizer(press)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(touched(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        applyTracking(animated: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        background.frame = bounds
        backgroundMask.frame = bounds
        backgroundMask.path = Self.wedge(size: size).cgPath
        knobContainer.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(isTracking)
        knob.frame = CGRect(
            x: ((size.width - 52) / 2).rounded(.down),
            y: -12 + ((size.height + 24 - 52) * (1 - value)).rounded(.down),
            width: 52,
            height: 52,
        )
        CATransaction.commit()
    }

    /// generateMaskPath: the top and bottom arcs joined.
    private static func wedge(size: CGSize) -> UIBezierPath {
        let path = UIBezierPath()
        path.addArc(
            withCenter: CGPoint(x: size.width / 2, y: 15),
            radius: 15,
            startAngle: .pi,
            endAngle: 0,
            clockwise: true,
        )
        path.addArc(
            withCenter: CGPoint(x: size.width / 2, y: size.height - 3),
            radius: 3,
            startAngle: 0,
            endAngle: .pi,
            clockwise: true,
        )
        path.close()
        return path
    }

    /// generateKnobImage: a 32 pt white circle with a 9 pt shadow at 30%.
    private static func knobImage() -> UIImage {
        let side: CGFloat = 32
        let margin: CGFloat = 10
        return UIGraphicsImageRenderer(size: CGSize(width: side + margin * 2, height: side + margin * 2))
            .image { context in
                context.cgContext.setShadow(
                    offset: .zero,
                    blur: 9,
                    color: UIColor.black.withAlphaComponent(0.3).cgColor,
                )
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fillEllipse(in: CGRect(x: margin, y: margin, width: side, height: side))
            }
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func touched(_ gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .began,
             .changed:
            if !isTracking {
                isTracking = true
                applyTracking(animated: true)
            }
            let y = gesture.location(in: self).y - 12
            value = 1 - max(0, min(1, y / (bounds.height - 24)))
            onChange?(value)
        case .cancelled,
             .ended,
             .failed:
            isTracking = false
            applyTracking(animated: true)
            onRelease?()
        default:
            break
        }
    }

    /// Half out of sight at rest, 8 pt in while touched; the knob 4 pt further out at rest.
    private func applyTracking(animated: Bool) {
        let apply = {
            self.layer.sublayerTransform = self.isTracking
                ? CATransform3DMakeTranslation(8, 0, 0)
                : CATransform3DMakeTranslation(-self.bounds.width / 2, 0, 0)
            self.knobContainer.sublayerTransform = self.isTracking
                ? CATransform3DIdentity
                : CATransform3DMakeTranslation(4, 0, 0)
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: apply)
        } else {
            apply()
        }
    }
}
