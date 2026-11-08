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

    private let fadeView = UIView()
    private var gestureEntity: StoryTextEntityView?

    var textEntities: [StoryTextEntityView] {
        subviews.compactMap { $0 as? StoryTextEntityView }
    }

    private var editingPosition: CGPoint {
        editingCenter?() ?? CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
    }

    override init(frame _: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        fadeView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        fadeView.frame = bounds
        fadeView.alpha = 0
        fadeView.isUserInteractionEnabled = false
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
        guard !textEntities.isEmpty else { return nil }
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
        entity.beginEditing()
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

/// DrawingTextEntityView with DrawingEntitiesView's new text: SF semibold at displayFontSize for a fontSize of 0.08
/// (48 + 432 × 0.08 pt in story points), 972 pt wide (90% of the story), centred, in the filled style: black glyphs on
/// a
/// white frame drawn per line by DrawingTextLayoutManager, its corners a fifth of the line height. The view is at least
/// 224 pt wide and 20 pt wider than the text.
final class StoryTextEntityView: UIView, UITextViewDelegate {
    static let fontSize: CGFloat = 48 + (480 - 48) * 0.08
    static let textWidth: CGFloat = 972

    var position = CGPoint.zero
    var scale: CGFloat = 1
    var rotation: CGFloat = 0

    private let textView: UITextView

    var isEmpty: Bool {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let storage = NSTextStorage()
        let layoutManager = StoryTextLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: Self.textWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = floor(Self.fontSize * 0.24)
        layoutManager.addTextContainer(container)
        self.textView = UITextView(frame: .zero, textContainer: container)
        super.init(frame: CGRect(x: 0, y: 0, width: 224, height: Self.fontSize * 1.2))
        textView.backgroundColor = .clear
        textView.clipsToBounds = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.keyboardAppearance = .dark
        textView.spellCheckingType = .no
        textView.font = .systemFont(ofSize: Self.fontSize, weight: .semibold)
        textView.textColor = .black
        textView.textAlignment = .center
        // A white frame takes Telegram's 0x0088ff cursor.
        textView.tintColor = UIColor(red: 0, green: 0x88 / 255, blue: 1, alpha: 1)
        textView.delegate = self
        addSubview(textView)
        resize()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
    }

    func beginEditing() {
        position = isEmpty ? center : position
        textView.isEditable = true
        textView.isSelectable = true
        textView.becomeFirstResponder()
    }

    func endEditing() {
        textView.resignFirstResponder()
        textView.isEditable = false
        textView.isSelectable = false
    }

    /// The entity's position, scale and rotation, as DrawingTextEntityView.update applies them.
    func applyPlacement() {
        center = position
        transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
    }

    func textViewDidChange(_: UITextView) {
        resize()
        textView.setNeedsDisplay()
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
    var frameColor: UIColor? = .white

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
