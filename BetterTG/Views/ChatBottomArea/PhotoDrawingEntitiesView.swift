// PhotoDrawingEntitiesView.swift

import UIKit

// MARK: - PhotoDrawingEntityView

/// DrawingEntityView for one entity in the painting's pixels: DrawingSimpleShapeEntityView's and
/// DrawingBubbleEntityView's shape layer, DrawingVectorEntityView's arrow over the whole painting, or
/// DrawingTextEntityView's text view with DrawingTextLayoutManager.
final class PhotoDrawingEntityView: UIView, UITextViewDelegate {
    // MARK: Internal

    let paintingSize: CGSize

    /// The text changed while it is edited.
    var onTextChanged: (() -> Void)?

    private(set) var entity: PhotoDrawingEntity
    private(set) var isEditing = false

    // MARK: Private

    private let shapeLayer = CAShapeLayer()
    private var textView: UITextView?
    private var textStorage: NSTextStorage?
    private var textLayoutManager: PhotoDrawingTextLayoutManager?
    private var textContainer: NSTextContainer?

    /// The view's turn and scale at the entity's place.
    var restingTransform: CGAffineTransform {
        switch entity.content {
        case .shape: CGAffineTransform(rotationAngle: entity.rotation)
        case .vector: .identity
        case .text(let text): CGAffineTransform(rotationAngle: entity.rotation).scaledBy(x: text.scale, y: text.scale)
        }
    }

    init(entity: PhotoDrawingEntity, paintingSize: CGSize) {
        self.entity = entity
        self.paintingSize = paintingSize
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        if case .text = entity.content {
            makeTextView()
        } else {
            shapeLayer.lineCap = .round
            shapeLayer.lineJoin = .round
            layer.addSublayer(shapeLayer)
        }
        update()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func setEntity(_ newEntity: PhotoDrawingEntity) {
        entity = newEntity
        update()
    }

    /// `precisePoint(inside:)`: a stroked shape along its line, a vector along its curve, the rest in its bounds.
    /// `slop` is the touch's reach in the painting.
    func precisePoint(inside point: CGPoint, slop: CGFloat) -> Bool {
        switch entity.content {
        case .shape(let shape):
            let path = PhotoDrawingGeometry.shapePath(shape, paintingSize: paintingSize)
            if shape.drawType == .stroke, shape.kind != .bubble {
                let width = max(PhotoDrawingGeometry.shapeMaximumLineWidth(paintingSize: paintingSize) * 0.8, slop)
                return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
                    .contains(point)
            }
            return path.contains(point)
                || path.copy(strokingWithWidth: slop, lineCap: .round, lineJoin: .round, miterLimit: 1).contains(point)
        case .vector:
            guard let path = shapeLayer.path else { return false }
            return path.contains(point)
                || path.copy(strokingWithWidth: slop, lineCap: .round, lineJoin: .round, miterLimit: 1).contains(point)
        case .text:
            return bounds.contains(point)
        }
    }

    /// `beginEditing`: the text view takes the keyboard with `accessoryView` over it.
    func beginTextEditing(accessoryView: UIView?) {
        guard let textView else { return }
        isEditing = true
        isUserInteractionEnabled = true
        textView.inputAccessoryView = accessoryView
        textView.isEditable = true
        textView.isSelectable = true
        textView.becomeFirstResponder()
    }

    func endTextEditing() {
        guard let textView else { return }
        isEditing = false
        isUserInteractionEnabled = false
        textView.inputAccessoryView = nil
        textView.resignFirstResponder()
        textView.isEditable = false
        textView.isSelectable = false
    }

    func textViewDidChange(_ textView: UITextView) {
        guard case .text(var text) = entity.content else { return }
        text.string = textView.text ?? ""
        let center = center
        let transform = transform
        entity.content = .text(text)
        update()
        // While it is edited the view keeps its place in the middle.
        if isEditing {
            self.transform = transform
            self.center = center
        }
        onTextChanged?()
    }

    // MARK: Private

    private func makeTextView() {
        let storage = NSTextStorage()
        let layoutManager = PhotoDrawingTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        let textView = UITextView(frame: .zero, textContainer: container)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = UIEdgeInsets(
            top: PhotoDrawingTextLayout.verticalInset,
            left: 0,
            bottom: PhotoDrawingTextLayout.verticalInset,
            right: 0,
        )
        textView.keyboardAppearance = .dark
        textView.tintColor = .white
        textView.delegate = self
        addSubview(textView)
        self.textView = textView
        textStorage = storage
        textLayoutManager = layoutManager
        textContainer = container
    }

    private func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        switch entity.content {
        case .shape(let shape):
            transform = .identity
            bounds = CGRect(origin: .zero, size: shape.size)
            center = entity.position
            transform = CGAffineTransform(rotationAngle: entity.rotation)
            shapeLayer.frame = bounds
            shapeLayer.path = PhotoDrawingGeometry.shapePath(shape, paintingSize: paintingSize)
            switch shape.drawType {
            case .fill:
                shapeLayer.fillColor = entity.color.cgColor
                shapeLayer.strokeColor = nil
                shapeLayer.lineWidth = 0
            case .stroke:
                shapeLayer.fillColor = nil
                shapeLayer.strokeColor = entity.color.cgColor
                shapeLayer.lineWidth = PhotoDrawingGeometry.shapeLineWidth(shape.lineWidth, paintingSize: paintingSize)
            }
        case .vector(let vector):
            transform = .identity
            frame = CGRect(origin: .zero, size: paintingSize)
            shapeLayer.frame = bounds
            shapeLayer.path = PhotoDrawingGeometry.vectorPath(vector, paintingSize: paintingSize)
            shapeLayer.fillColor = entity.color.cgColor
            shapeLayer.strokeColor = nil
        case .text(let text):
            updateText(text)
        }
    }

    private func updateText(_ text: PhotoDrawingTextEntity) {
        guard let textView, let textStorage, let textLayoutManager, let textContainer else { return }
        let attributes = PhotoDrawingTextLayout.attributes(text, color: entity.color, paintingSize: paintingSize)
        if textStorage.string != text.string {
            textStorage.setAttributedString(NSAttributedString(string: text.string, attributes: attributes))
        } else {
            textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        }
        textView.typingAttributes = attributes
        PhotoDrawingTextLayout.configure(
            textLayoutManager,
            container: textContainer,
            text: text,
            color: entity.color,
            paintingSize: paintingSize,
        )
        // An empty text keeps one line's height for the caret.
        var measured = text
        if measured.string.isEmpty {
            measured.string = " "
        }
        let size = PhotoDrawingTextLayout.size(of: measured, paintingSize: paintingSize)
        transform = .identity
        bounds = CGRect(origin: .zero, size: size)
        center = entity.position
        transform = CGAffineTransform(rotationAngle: entity.rotation).scaledBy(x: text.scale, y: text.scale)
        textView.frame = bounds
        // The regular style's shadow, as DrawingTextEntityView's text view has.
        let hasShadow = text.style == .regular
        textView.layer.shadowColor = UIColor.black.cgColor
        textView.layer.shadowOpacity = hasShadow ? 0.4 : 0
        textView.layer.shadowOffset = CGSize(width: 0, height: 4)
        textView.layer.shadowRadius = 4
        textLayoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage.length))
        textView.setNeedsDisplay()
    }
}

// MARK: - PhotoDrawingSelectionView

/// DrawingEntitySelectionView in the screen's points: DrawingSimpleShapeEntititySelectionView's eight handles,
/// DrawingBubbleEntitySelectionView's with the tail's, DrawingTextEntititySelectionView's dashed frame with its
/// side handles, and DrawingVectorEntititySelectionView's start, middle and end.
final class PhotoDrawingSelectionView: UIView {
    // MARK: Internal

    enum Handle {
        case topLeft
        case top
        case topRight
        case left
        case right
        case bottomLeft
        case bottom
        case bottomRight
        case tail
        case start
        case mid
        case end
    }

    enum Layout {
        /// A box of `size` around `center` turned by `rotation`, with its `handles` in it.
        case box(center: CGPoint, size: CGSize, rotation: CGFloat, inset: CGFloat, handles: [Handle: CGPoint])
        /// A text's dashed frame with handles at its sides.
        case text(center: CGPoint, size: CGSize, rotation: CGFloat)
        /// A vector's points.
        case points([Handle: CGPoint])
    }

    // MARK: Private

    /// `entitySelectionViewHandleSize`'s reach around a handle.
    private static let handleReach: CGFloat = 22
    private static let handleSide: CGFloat = 9
    private static let handleColor = UIColor(rgb: 0x0A60FF)

    private let borderLayer = CAShapeLayer()
    private var handleLayers = [Handle: CAShapeLayer]()
    private var handlePositions = [Handle: CGPoint]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        borderLayer.fillColor = nil
        borderLayer.strokeColor = UIColor(white: 1, alpha: 0.75).cgColor
        borderLayer.lineCap = .round
        layer.addSublayer(borderLayer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func apply(_ layout: Layout) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        var positions = [Handle: CGPoint]()
        switch layout {
        case .box(let center, let size, let rotation, let inset, let handles):
            // The bounds' origin sits at the box's middle, so the handles are in the box's own points.
            transform = .identity
            bounds = CGRect(
                x: -size.width / 2 - inset,
                y: -size.height / 2 - inset,
                width: size.width + inset * 2,
                height: size.height + inset * 2,
            )
            self.center = center
            transform = CGAffineTransform(rotationAngle: rotation)
            borderLayer.path = nil
            positions = handles
        case .text(let center, let size, let rotation):
            // DrawingTextEntititySelectionView: the dashed frame and its handles 10 pt around the text.
            let inset: CGFloat = 10
            transform = .identity
            bounds = CGRect(
                x: -size.width / 2 - inset,
                y: -size.height / 2 - inset,
                width: size.width + inset * 2,
                height: size.height + inset * 2,
            )
            self.center = center
            transform = CGAffineTransform(rotationAngle: rotation)
            let frame = bounds
            let cornerRadius: CGFloat = 11
            let perimeter = 2 * (frame.width + frame.height - cornerRadius * (4 - .pi))
            let dashLength = perimeter / 12 * 0.25
            borderLayer.lineDashPattern = [NSNumber(value: Double(dashLength)), NSNumber(value: Double(dashLength))]
            borderLayer.lineWidth = 2
            borderLayer.path = CGPath(
                roundedRect: frame,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil,
            )
            positions = [.left: CGPoint(x: frame.minX, y: 0), .right: CGPoint(x: frame.maxX, y: 0)]
        case .points(let points):
            // Over the whole superview, the points in its coordinates.
            let area = superview?.bounds ?? .zero
            transform = .identity
            bounds = CGRect(origin: area.origin, size: area.size)
            center = CGPoint(x: area.midX, y: area.midY)
            borderLayer.path = nil
            positions = points
        }
        handlePositions = positions
        for (handle, handleLayer) in handleLayers where positions[handle] == nil {
            handleLayer.removeFromSuperlayer()
            handleLayers[handle] = nil
        }
        let side = Self.handleSide
        for (handle, position) in positions {
            let handleLayer = handleLayers[handle] ?? makeHandleLayer()
            handleLayers[handle] = handleLayer
            handleLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            handleLayer.path = CGPath(ellipseIn: handleLayer.bounds, transform: nil)
            handleLayer.position = position
        }
    }

    /// The handle under `point`, in the selection's superview, if any.
    func handle(at point: CGPoint) -> Handle? {
        let local = convert(point, from: superview)
        var best: (Handle, CGFloat)?
        for (handle, position) in handlePositions {
            let distance = local.distance(to: position)
            if distance <= Self.handleReach, distance < best?.1 ?? .greatestFiniteMagnitude {
                best = (handle, distance)
            }
        }
        return best?.0
    }

    private func makeHandleLayer() -> CAShapeLayer {
        let handleLayer = CAShapeLayer()
        handleLayer.fillColor = Self.handleColor.cgColor
        handleLayer.strokeColor = UIColor.white.cgColor
        handleLayer.lineWidth = 1 + 1 / max(1, traitCollection.displayScale)
        layer.addSublayer(handleLayer)
        return handleLayer
    }
}

// MARK: - PhotoDrawingEntitiesView

/// DrawingEntitiesView in the painting's pixels: the entities over the strokes in order, the selected one's
/// selection in the screen's points, their gestures, new entities placed as `prepareNewEntity` does, and the text
/// edited in place with the photo dimmed under it.
final class PhotoDrawingEntitiesView: UIView {
    // MARK: Internal

    let paintingSize: CGSize

    /// Where the selection is drawn, in the screen's points.
    weak var selectionOverlay: UIView? {
        didSet {
            selectionOverlay?.addSubview(selectionView)
            updateSelection()
        }
    }

    /// `getEntityCenterPosition`: the middle of the visible photo in the painting.
    var centerPosition: (() -> CGPoint)?
    /// `getEntityInitialRotation`: the angle that turns an entity upright on the screen.
    var initialRotation: (() -> CGFloat)?
    /// TextSettingsComponent over the keyboard while a text is edited.
    var textAccessoryView: UIView?
    var onSelectionChanged: ((PhotoDrawingEntity?) -> Void)?
    /// An entity was added or removed by hand, for undo.
    var onEntityAdded: ((PhotoDrawingEntity) -> Void)?
    var onEntityRemoved: ((PhotoDrawingEntity, Int) -> Void)?
    /// An entity is being moved, sized or turned.
    var onInteractionChanged: ((Bool) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    /// `requestedMenuForEntityView`: a tap on the selected entity.
    var onMenuRequested: ((PhotoDrawingEntity, Bool) -> Void)?

    private(set) var isInteracting = false

    // MARK: Private

    private let selectionView = PhotoDrawingSelectionView()
    private var entityViews = [PhotoDrawingEntityView]()
    private var selectedID: UUID?
    private var editingID: UUID?
    private var editingWasNew = false
    private var editingPrevious: PhotoDrawingEntity?
    private var fadeView: UIView?
    private var activeHandle: PhotoDrawingSelectionView.Handle?
    private var gestureStart: (entity: PhotoDrawingEntity, distance: CGFloat)?
    private var activeGestures = 0

    var entities: [PhotoDrawingEntity] {
        entityViews.map(\.entity)
    }

    var selectedEntity: PhotoDrawingEntity? {
        selectedID.flatMap { view(for: $0)?.entity }
    }

    var hasSelection: Bool {
        selectedID != nil
    }

    var isEditingText: Bool {
        editingID != nil
    }

    // MARK: Private

    /// A touch's reach of 22 points, in the painting.
    private var touchSlop: CGFloat {
        guard let window else { return 44 }
        let origin = convert(CGPoint.zero, to: window)
        let unit = convert(CGPoint(x: 1, y: 0), to: window)
        let scale = max(0.0001, origin.distance(to: unit))
        return 44 / scale
    }

    init(paintingSize: CGSize, entities: [PhotoDrawingEntity]) {
        self.paintingSize = paintingSize
        super.init(frame: CGRect(origin: .zero, size: paintingSize))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for entity in entities {
            insertView(for: entity, at: entityViews.count)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    // MARK: Entities

    /// `prepareNewEntity` then `add`: the entity in the middle of the photo, stepped away from others, upright on
    /// the screen, selected, and a text edited at once.
    func insertNew(_ content: PhotoDrawingEntity.Content, color: PhotoDrawingColor) {
        endEditing()
        var entity = PhotoDrawingEntity(content: content, color: color)
        let isText =
            if case .text = content {
                true
            } else {
                false
            }
        let center = startPosition(relativeTo: nil, onlyVertical: isText)
        let rotation = initialRotation?() ?? 0
        let width = (paintingSize.width * 0.5).rounded()
        switch content {
        case .shape(var shape):
            entity.position = center
            entity.rotation = rotation
            switch shape.kind {
            case .star:
                shape.size = CGSize(width: width, height: width)
            case .bubble:
                shape.size = CGSize(width: width, height: (width * 0.7).rounded())
                shape.tailPosition = CGPoint(x: 0.16, y: width * 0.18)
            case .ellipse, .rectangle:
                shape.size = CGSize(width: width, height: (width * 0.75).rounded())
            }
            entity.content = .shape(shape)
        case .vector(var vector):
            vector.start = CGPoint(x: center.x * 0.5, y: center.y)
            vector.end = CGPoint(x: center.x * 1.5, y: center.y)
            vector.midLength = 0.5
            vector.midHeight = 0
            entity.content = .vector(vector)
        case .text(var text):
            entity.position = center
            entity.rotation = rotation
            text.width = floor(paintingSize.width * 0.9)
            text.fontSize = 0.08
            text.scale = 1
            entity.content = .text(text)
        }
        insertView(for: entity, at: entityViews.count)
        select(entity.id)
        if isText {
            beginEditing(entity.id, isNew: true)
        } else {
            onEntityAdded?(entity)
        }
    }

    /// `duplicateEntity`: a copy a tenth of the painting's width away, selected.
    func duplicate(_ id: UUID) {
        guard let entity = view(for: id)?.entity else { return }
        let offset = (paintingSize.width * 0.1).rounded()
        let isText =
            if case .text = entity.content {
                true
            } else {
                false
            }
        let copy = entity.duplicated(offset: CGPoint(x: isText ? 0 : offset, y: offset))
        insertView(for: copy, at: entityViews.count)
        select(copy.id)
        onEntityAdded?(copy)
    }

    /// The menu's Delete.
    func delete(_ id: UUID) {
        if editingID == id {
            endEditing()
        }
        guard let removed = remove(id) else { return }
        onEntityRemoved?(removed.entity, removed.index)
    }

    /// Takes an entity away without recording it, for undo and redo.
    @discardableResult func remove(_ id: UUID) -> (entity: PhotoDrawingEntity, index: Int)? {
        if editingID == id {
            stopEditing()
        }
        guard let index = entityViews.firstIndex(where: { $0.entity.id == id }) else { return nil }
        let view = entityViews.remove(at: index)
        view.removeFromSuperview()
        if selectedID == id {
            select(nil)
        }
        return (view.entity, index)
    }

    /// Puts an entity back where it was, for undo and redo.
    func restore(_ entity: PhotoDrawingEntity, at index: Int) {
        guard view(for: entity.id) == nil else { return }
        insertView(for: entity, at: min(max(0, index), entityViews.count))
    }

    func removeAll() {
        stopEditing()
        select(nil)
        for view in entityViews {
            view.removeFromSuperview()
        }
        entityViews.removeAll()
    }

    /// `bringToFront`.
    func bringToFront(_ id: UUID) {
        guard let index = entityViews.firstIndex(where: { $0.entity.id == id }) else { return }
        let view = entityViews.remove(at: index)
        entityViews.append(view)
        bringSubviewToFront(view)
    }

    func isTopmost(_ id: UUID) -> Bool {
        entityViews.last?.entity.id == id
    }

    /// Changes an entity's model, its view following.
    func update(_ id: UUID, _ change: (inout PhotoDrawingEntity) -> Void) {
        guard let view = view(for: id) else { return }
        var entity = view.entity
        change(&entity)
        view.setEntity(entity)
        if editingID == id {
            placeEditingView(view, animated: false)
        }
        updateSelection()
        if selectedID == id {
            onSelectionChanged?(entity)
        }
    }

    /// The topmost entity under `point` in the painting.
    func entity(at point: CGPoint) -> PhotoDrawingEntity? {
        let slop = touchSlop
        return entityViews.last { view in
            view.precisePoint(inside: convert(point, to: view), slop: slop)
        }?.entity
    }

    // MARK: Selection

    func select(_ id: UUID?) {
        if let editingID, id != editingID {
            guard id == nil else { return }
            endEditing()
        }
        guard id != selectedID else { return }
        selectedID = id
        updateSelection()
        onSelectionChanged?(selectedEntity)
    }

    /// The selection over the selected entity, in the screen's points; hidden while its text is edited.
    func updateSelection() {
        guard let selectionOverlay, let selectedID, let view = view(for: selectedID), editingID == nil else {
            selectionView.isHidden = true
            return
        }
        selectionView.isHidden = false
        let geometry = screenGeometry(in: selectionOverlay)
        let entity = view.entity
        switch entity.content {
        case .shape(let shape):
            let size = CGSize(width: shape.size.width * geometry.scale, height: shape.size.height * geometry.scale)
            let halfWidth = size.width / 2
            let halfHeight = size.height / 2
            var handles: [PhotoDrawingSelectionView.Handle: CGPoint] = [
                .topLeft: CGPoint(x: -halfWidth, y: -halfHeight),
                .top: CGPoint(x: 0, y: -halfHeight),
                .topRight: CGPoint(x: halfWidth, y: -halfHeight),
                .left: CGPoint(x: -halfWidth, y: 0),
                .right: CGPoint(x: halfWidth, y: 0),
                .bottomLeft: CGPoint(x: -halfWidth, y: halfHeight),
                .bottom: CGPoint(x: 0, y: halfHeight),
                .bottomRight: CGPoint(x: halfWidth, y: halfHeight),
            ]
            if shape.kind == .bubble {
                handles[.tail] = CGPoint(
                    x: -halfWidth + size.width * shape.tailPosition.x,
                    y: halfHeight + shape.tailPosition.y * geometry.scale,
                )
            }
            selectionView.apply(.box(
                center: convert(entity.position, to: selectionOverlay),
                size: size,
                rotation: entity.rotation + geometry.rotation,
                inset: 5.5,
                handles: handles,
            ))
        case .vector(let vector):
            selectionView.apply(.points([
                .start: convert(vector.start, to: selectionOverlay),
                .mid: convert(vector.midPoint, to: selectionOverlay),
                .end: convert(vector.end, to: selectionOverlay),
            ]))
        case .text(let text):
            let scale = text.scale * geometry.scale
            selectionView.apply(.text(
                center: convert(entity.position, to: selectionOverlay),
                size: CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale),
                rotation: entity.rotation + geometry.rotation,
            ))
        }
    }

    /// The selected entity's handle under a point in the selection's overlay.
    func selectionHandle(at point: CGPoint) -> PhotoDrawingSelectionView.Handle? {
        guard !selectionView.isHidden, selectionOverlay != nil else { return nil }
        return selectionView.handle(at: point)
    }

    /// The selected box's or text's frame in `view`, where its menu points; none for an arrow.
    func selectionFrame(in view: UIView) -> CGRect? {
        guard !selectionView.isHidden, let selectionOverlay, let selectedEntity else { return nil }
        if case .vector = selectedEntity.content {
            return nil
        }
        return selectionOverlay.convert(selectionView.frame, to: view)
    }

    // MARK: Text Editing

    /// `beginEditing`: the photo dims and the text sits upright in the middle, taking the keyboard.
    func beginEditing(_ id: UUID, isNew: Bool = false) {
        guard editingID == nil, let view = view(for: id), case .text = view.entity.content else { return }
        select(id)
        editingID = id
        editingWasNew = isNew
        editingPrevious = isNew ? nil : view.entity
        let fadeView = UIView(frame: bounds)
        fadeView.backgroundColor = UIColor(white: 0, alpha: 0.4)
        fadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fadeTapped)))
        insertSubview(fadeView, belowSubview: view)
        self.fadeView = fadeView
        fadeView.alpha = 0
        UIView.animate(withDuration: 0.3) { fadeView.alpha = 1 }
        isUserInteractionEnabled = true
        view.onTextChanged = { [weak self, weak view] in
            guard let self, let view else { return }
            if selectedID == view.entity.id {
                onSelectionChanged?(view.entity)
            }
        }
        view.beginTextEditing(accessoryView: textAccessoryView)
        placeEditingView(view, animated: true)
        updateSelection()
        onEditingChanged?(true)
    }

    /// `endEditing`: Cancel puts the text back as it was, or takes a new one away; an emptied text goes; the text
    /// springs back to its place.
    func endEditing(reset: Bool = false) {
        guard let editingID, let view = view(for: editingID) else { return }
        self.editingID = nil
        view.endTextEditing()
        view.onTextChanged = nil
        isUserInteractionEnabled = false
        if let fadeView {
            self.fadeView = nil
            UIView.animate(withDuration: 0.3, animations: { fadeView.alpha = 0 }, completion: { _ in
                fadeView.removeFromSuperview()
            })
        }
        let isEmpty =
            if case .text(let text) = view.entity.content {
                text.string.isEmpty
            } else {
                true
            }
        if reset {
            if let editingPrevious {
                view.setEntity(editingPrevious)
            } else {
                remove(editingID)
            }
        } else if isEmpty {
            if editingWasNew {
                remove(editingID)
            } else if let removed = remove(editingID) {
                onEntityRemoved?(editingPrevious ?? removed.entity, removed.index)
            }
        } else if editingWasNew {
            onEntityAdded?(view.entity)
        }
        editingPrevious = nil
        let entity = view.entity
        if view.superview != nil {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0) {
                view.transform = view.restingTransform
                view.center = entity.position
            } completion: { _ in
                self.updateSelection()
            }
        }
        updateSelection()
        onEditingChanged?(false)
        if selectedID == entity.id {
            onSelectionChanged?(entity)
        }
    }

    // MARK: Gestures

    /// Whether a pan at `point` in the painting, or at `overlayPoint` on the selection, moves an entity.
    func shouldBeginPan(at point: CGPoint, overlayPoint: CGPoint) -> Bool {
        guard editingID == nil else { return false }
        return selectionHandle(at: overlayPoint) != nil || entity(at: point) != nil
    }

    /// `handlePan`: a handle sizes the selected entity, anywhere else it moves; an unselected entity is selected
    /// first.
    func handlePan(_ recognizer: UIPanGestureRecognizer, overlayPoint: CGPoint) {
        switch recognizer.state {
        case .began:
            activeHandle = selectionHandle(at: overlayPoint)
            if activeHandle == nil, let hit = entity(at: recognizer.location(in: self)), hit.id != selectedID {
                select(hit.id)
            }
            if let selectedEntity {
                let location = recognizer.location(in: self)
                gestureStart = (selectedEntity, selectedEntity.position.distance(to: location))
            }
            setGestureActive(true)
        case .changed:
            guard let selectedID else { return }
            let delta = recognizer.translation(in: self)
            let location = recognizer.location(in: self)
            recognizer.setTranslation(.zero, in: self)
            update(selectedID) { entity in
                self.apply(pan: delta, location: location, handle: self.activeHandle, to: &entity)
            }
        case .cancelled, .ended, .failed:
            activeHandle = nil
            gestureStart = nil
            setGestureActive(false)
        default:
            break
        }
    }

    /// `handlePinch` for the selected entity.
    func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            if recognizer.state == .began {
                setGestureActive(true)
            }
            let scale = recognizer.scale
            recognizer.scale = 1
            guard let selectedID else { return }
            update(selectedID) { entity in
                switch entity.content {
                case .shape(var shape):
                    shape.size = CGSize(width: shape.size.width * scale, height: shape.size.height * scale)
                    entity.content = .shape(shape)
                case .text(var text):
                    text.scale = max(0.1, text.scale * scale)
                    entity.content = .text(text)
                case .vector:
                    break
                }
            }
        case .cancelled, .ended, .failed:
            setGestureActive(false)
        default:
            break
        }
    }

    /// `handleRotate` for the selected entity.
    func handleRotate(_ recognizer: UIRotationGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            if recognizer.state == .began {
                setGestureActive(true)
            }
            let rotation = recognizer.rotation
            recognizer.rotation = 0
            guard let selectedID else { return }
            update(selectedID) { entity in
                if case .vector = entity.content {
                    return
                }
                entity.rotation += rotation
            }
        case .cancelled, .ended, .failed:
            setGestureActive(false)
        default:
            break
        }
    }

    /// `handleTap`: an entity is selected, the selected one asks for its menu, and a tap beside them deselects.
    func handleTap(at point: CGPoint) {
        guard editingID == nil else { return }
        guard let hit = entity(at: point) else {
            select(nil)
            return
        }
        if hit.id == selectedID {
            onMenuRequested?(hit, isTopmost(hit.id))
        } else {
            select(hit.id)
        }
    }

    private func view(for id: UUID) -> PhotoDrawingEntityView? {
        entityViews.first { $0.entity.id == id }
    }

    private func insertView(for entity: PhotoDrawingEntity, at index: Int) {
        let view = PhotoDrawingEntityView(entity: entity, paintingSize: paintingSize)
        entityViews.insert(view, at: index)
        if index + 1 < entityViews.count {
            insertSubview(view, belowSubview: entityViews[index + 1])
        } else {
            addSubview(view)
        }
    }

    /// How the painting shows in `overlay`: its turn and its scale.
    private func screenGeometry(in overlay: UIView) -> (rotation: CGFloat, scale: CGFloat) {
        let origin = convert(CGPoint.zero, to: overlay)
        let unit = convert(CGPoint(x: 1, y: 0), to: overlay)
        return (origin.angle(to: unit), max(0.0001, origin.distance(to: unit)))
    }

    /// `startPosition`: the photo's middle, stepped by a tenth of the width while another entity is near.
    private func startPosition(relativeTo entity: PhotoDrawingEntity?, onlyVertical: Bool) -> CGPoint {
        let offsetLength = (paintingSize.width * 0.1).rounded()
        let offset = CGPoint(x: onlyVertical ? 0 : offsetLength, y: offsetLength)
        if let entity {
            return CGPoint(x: entity.center.x + offset.x, y: entity.center.y + offset.y)
        }
        let minimalDistance = (offsetLength * 0.5).rounded()
        var position = centerPosition?() ?? CGPoint(x: paintingSize.width / 2, y: paintingSize.height / 2)
        for _ in 0..<32 {
            let isOccupied = entityViews.contains { $0.entity.center.distance(to: position) < minimalDistance }
            guard isOccupied else { break }
            position = CGPoint(x: position.x + offset.x, y: position.y + offset.y)
        }
        return position
    }

    /// The edited text upright in the middle of the photo, at the entity's own size.
    private func placeEditingView(_ view: PhotoDrawingEntityView, animated: Bool) {
        let position = centerPosition?() ?? CGPoint(x: paintingSize.width / 2, y: paintingSize.height / 2)
        let rotation = initialRotation?() ?? 0
        let changes = {
            view.transform = CGAffineTransform(rotationAngle: rotation)
            view.center = position
        }
        if animated {
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                usingSpringWithDamping: 0.65,
                initialSpringVelocity: 0,
                animations: changes,
            )
        } else {
            changes()
        }
    }

    private func setGestureActive(_ active: Bool) {
        activeGestures = max(0, activeGestures + (active ? 1 : -1))
        let interacting = activeGestures > 0
        guard interacting != isInteracting else { return }
        isInteracting = interacting
        onInteractionChanged?(interacting)
    }

    /// The selection views' `handlePan`: the shape's sides and corners in its own turned frame with the star's
    /// sides kept equal, the bubble's tail, the text's side handles scaling and turning it about its middle, and
    /// the vector's ends and bend.
    private func apply(
        pan delta: CGPoint,
        location: CGPoint,
        handle: PhotoDrawingSelectionView.Handle?,
        to entity: inout PhotoDrawingEntity,
    ) {
        switch entity.content {
        case .shape(var shape):
            guard let handle else {
                entity.position = CGPoint(x: entity.position.x + delta.x, y: entity.position.y + delta.y)
                return
            }
            if handle == .tail {
                let local = localDelta(delta, rotation: entity.rotation)
                let tail = shape.tailPosition
                shape.tailPosition = CGPoint(
                    x: min(1, max(0, tail.x + local.x / max(1, shape.size.width))),
                    y: min(shape.size.height, max(0, tail.y + local.y)),
                )
                entity.content = .shape(shape)
                return
            }
            resize(&shape, position: &entity.position, rotation: entity.rotation, delta: delta, handle: handle)
            entity.content = .shape(shape)
        case .text(var text):
            guard let handle, handle == .left || handle == .right, let gestureStart else {
                entity.position = CGPoint(x: entity.position.x + delta.x, y: entity.position.y + delta.y)
                return
            }
            guard case .text(let startText) = gestureStart.entity.content, gestureStart.distance > 0 else { return }
            let distance = entity.position.distance(to: location)
            text.scale = max(0.01, startText.scale * distance / gestureStart.distance)
            entity.rotation = handle == .left
                ? location.angle(to: entity.position)
                : entity.position.angle(to: location)
            entity.content = .text(text)
        case .vector(var vector):
            switch handle {
            case .start:
                vector.start = location
            case .end:
                vector.end = location
            case .mid:
                let dx = vector.end.x - vector.start.x
                let dy = vector.end.y - vector.start.y
                let lengthSquared = dx * dx + dy * dy
                if lengthSquared > 0 {
                    let px = location.x - vector.start.x
                    let py = location.y - vector.start.y
                    vector.midLength = (px * dx + py * dy) / lengthSquared
                    vector.midHeight = (py * dx - px * dy) / lengthSquared
                }
            default:
                vector.start = CGPoint(x: vector.start.x + delta.x, y: vector.start.y + delta.y)
                vector.end = CGPoint(x: vector.end.x + delta.x, y: vector.end.y + delta.y)
            }
            entity.content = .vector(vector)
        }
    }

    private func localDelta(_ delta: CGPoint, rotation: CGFloat) -> CGPoint {
        CGPoint(
            x: delta.x * cos(rotation) + delta.y * sin(rotation),
            y: -delta.x * sin(rotation) + delta.y * cos(rotation),
        )
    }

    /// A side or corner handle dragged by `delta`: the opposite side stays, and nothing gets smaller than
    /// `minimumSize`.
    private func resize(
        _ shape: inout PhotoDrawingShapeEntity,
        position: inout CGPoint,
        rotation: CGFloat,
        delta: CGPoint,
        handle: PhotoDrawingSelectionView.Handle,
    ) {
        let local = localDelta(delta, rotation: rotation)
        let minimum = PhotoDrawingGeometry.shapeMinimumSide(paintingSize: paintingSize)
        let isAspectLocked = shape.kind == .star
        var widthSign: CGFloat = 0
        var heightSign: CGFloat = 0
        switch handle {
        case .left: widthSign = -1
        case .right: widthSign = 1
        case .top: heightSign = -1
        case .bottom: heightSign = 1
        case .topLeft: widthSign = -1
            heightSign = -1
        case .topRight: widthSign = 1
            heightSign = -1
        case .bottomLeft: widthSign = -1
            heightSign = 1
        case .bottomRight: widthSign = 1
            heightSign = 1
        default: return
        }
        var newWidth = shape.size.width + local.x * widthSign
        var newHeight = shape.size.height + local.y * heightSign
        if isAspectLocked {
            let side = widthSign != 0 ? newWidth : newHeight
            newWidth = side
            newHeight = side
        }
        newWidth = max(minimum, newWidth)
        newHeight = max(minimum, newHeight)
        // The middle moves half the growth toward the dragged side, in the shape's own turned frame.
        let grownX = (newWidth - shape.size.width) / 2 * widthSign
        let grownY = (newHeight - shape.size.height) / 2 * heightSign
        position = CGPoint(
            x: position.x + grownX * cos(rotation) - grownY * sin(rotation),
            y: position.y + grownX * sin(rotation) + grownY * cos(rotation),
        )
        shape.size = CGSize(width: newWidth, height: newHeight)
    }

    /// The edit ends without touching the entity, as it is taken away.
    private func stopEditing() {
        guard let editingID else { return }
        self.editingID = nil
        editingPrevious = nil
        if let view = view(for: editingID) {
            view.endTextEditing()
            view.onTextChanged = nil
        }
        isUserInteractionEnabled = false
        fadeView?.removeFromSuperview()
        fadeView = nil
        onEditingChanged?(false)
    }

    @objc private func fadeTapped() {
        endEditing()
    }
}

// MARK: - PhotoDrawingTextSettingsView

/// TextSettingsComponent for the selected text: its style, its alignment and its font, under the photo and over the
/// keyboard while the text is edited.
final class PhotoDrawingTextSettingsView: UIView {
    // MARK: Internal

    var onStyle: (() -> Void)?
    var onAlignment: (() -> Void)?
    var onFont: ((PhotoDrawingTextFont) -> Void)?

    // MARK: Private

    private let styleButton = UIButton(type: .system)
    private let alignmentButton = UIButton(type: .system)
    private let fontButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        styleButton.accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.TextStyle")
        styleButton.addAction(UIAction { [weak self] _ in self?.onStyle?() }, for: .touchUpInside)
        alignmentButton.accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Alignment")
        alignmentButton.addAction(UIAction { [weak self] _ in self?.onAlignment?() }, for: .touchUpInside)
        fontButton.accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Font")
        fontButton.showsMenuAsPrimaryAction = true
        fontButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        fontButton.layer.cornerRadius = 8
        fontButton.layer.cornerCurve = .continuous
        fontButton.layer.borderWidth = 1
        fontButton.layer.borderColor = UIColor(white: 1, alpha: 0.5).cgColor
        for button in [styleButton, alignmentButton, fontButton] {
            button.tintColor = .white
            addSubview(button)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 44
        let midY = bounds.midY
        styleButton.frame = CGRect(x: 12, y: midY - side / 2, width: side, height: side)
        alignmentButton.frame = CGRect(x: 12 + side, y: midY - side / 2, width: side, height: side)
        let titleWidth = ceil(fontButton.titleLabel?.intrinsicContentSize.width ?? 0) + 20
        let fontWidth = min(bounds.width - alignmentButton.frame.maxX - 24, titleWidth)
        fontButton.frame = CGRect(
            x: alignmentButton.frame.maxX + 12,
            y: midY - 15,
            width: max(0, fontWidth),
            height: 30,
        )
    }

    func update(text: PhotoDrawingTextEntity) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let styleSymbol =
            switch text.style {
            case .regular: "textformat"
            case .filled: "a.square.fill"
            case .semi: "a.square"
            case .stroke: "character.textbox"
            }
        styleButton.setImage(UIImage(systemName: styleSymbol, withConfiguration: configuration), for: .normal)
        styleButton.accessibilityValue =
            switch text.style {
            case .regular: L10n.telegram("Paint.Regular")
            case .filled, .semi: L10n.telegram("Paint.Framed")
            case .stroke: L10n.telegram("Paint.Outlined")
            }
        let alignmentSymbol =
            switch text.alignment {
            case .left: "text.alignleft"
            case .center: "text.aligncenter"
            case .right: "text.alignright"
            }
        alignmentButton.setImage(UIImage(systemName: alignmentSymbol, withConfiguration: configuration), for: .normal)
        fontButton.setTitle(text.font.title, for: .normal)
        fontButton.menu = UIMenu(children: PhotoDrawingTextFont.allCases.map { font in
            UIAction(title: font.title, state: font == text.font ? .on : .off) { [weak self] _ in
                self?.onFont?(font)
            }
        })
        setNeedsLayout()
    }
}
