// PhotoDrawingCanvasView.swift

import CoreImage
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - PhotoDrawingGestureRecognizer

/// DrawingGestureRecognizer: a one-finger pan that starts as the finger lands and gives way to a second finger.
final class PhotoDrawingGestureRecognizer: UIPanGestureRecognizer {
    var shouldBeginAt: ((CGPoint) -> Bool)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first,
              shouldBeginAt?(touch.location(in: view)) ?? true
        else { return }
        super.touchesBegan(touches, with: event)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if touches.count > 1 {
            state = .cancelled
        } else {
            super.touchesMoved(touches, with: event)
        }
    }
}

// MARK: - PhotoDrawingCanvasView

/// DrawingView: the brush strokes over the whole photo in the painting's pixels, the stroke being drawn over them,
/// Undo and Redo of strokes and of added or removed entities, Clear All, and holding still to fill the painting.
final class PhotoDrawingCanvasView: UIView, UIGestureRecognizerDelegate {
    // MARK: Internal

    /// `NavigationState`.
    struct NavigationState: Equatable {
        var canUndo = false
        var canRedo = false
        var canClear = false
        var isDrawing = false
    }

    // MARK: Private

    private enum Operation {
        case clearAll(CGRect)
        case slice(Slice)
        case addEntity(UUID)
        case removeEntity(PhotoDrawingEntity, index: Int)
    }

    /// DrawingSlice: what an area of the strokes held before a change.
    private struct Slice {
        let image: CGImage?
        let rect: CGRect
    }

    private static let blurQueue = DispatchQueue(label: "BetterTG.PhotoDrawingBlur", qos: .userInitiated)

    let drawingSize: CGSize

    var tool = PhotoDrawingTool.pen {
        didSet {
            if tool != oldValue {
                updateBlurredImage()
            }
        }
    }

    var toolColor = PhotoDrawingColor.white
    var toolBrushSize: CGFloat = 0.25

    var stateUpdated: ((NavigationState) -> Void)?
    /// Whether a stroke may start at a point in the gesture view.
    var shouldBegin: ((CGPoint) -> Bool)?
    /// The photo under the painting, for Blur.
    var getFullImage: (() -> UIImage?)?
    var hasEntities: (() -> Bool)?
    /// Undo and Redo of entities: the removed entity with its place, and putting one back.
    var removeEntity: ((UUID) -> (entity: PhotoDrawingEntity, index: Int)?)?
    var restoreEntity: ((PhotoDrawingEntity, Int) -> Void)?
    var removeAllEntities: (() -> Void)?
    /// A stroke started; selections and editing end.
    var drawingBegan: (() -> Void)?

    private(set) var strokes: CGImage?
    private(set) var isDrawing = false

    private let strokesView = UIView()
    private let currentContainer = UIImageView()
    private var hasOpaqueData: Bool
    private var undoStack = [Operation]()
    private var redoStack = [Operation]()
    private var uncommittedElement: PhotoDrawingElement?
    private var currentRenderView: UIView?
    private var preparedBlurredImage: CGImage?
    private var previousPointTimestamp: CFTimeInterval?
    private var longPressTimer: Timer?
    private var fillCircleLayer: CAShapeLayer?
    private let feedback = UIImpactFeedbackGenerator(style: .medium)
    private weak var drawingGesture: PhotoDrawingGestureRecognizer?
    private weak var longPressGesture: UILongPressGestureRecognizer?

    /// `drawingData`: the strokes once something was drawn.
    var paintedStrokes: CGImage? {
        undoStack.isEmpty && !hasOpaqueData ? nil : strokes
    }

    var internalState: NavigationState {
        NavigationState(
            canUndo: !undoStack.isEmpty,
            canRedo: !redoStack.isEmpty,
            canClear: !undoStack.isEmpty || hasOpaqueData || (hasEntities?() ?? false),
            isDrawing: isDrawing,
        )
    }

    var isTracking: Bool {
        uncommittedElement != nil
    }

    init(size: CGSize, strokes: CGImage?) {
        self.drawingSize = size
        self.strokes = strokes
        self.hasOpaqueData = strokes != nil
        super.init(frame: CGRect(origin: .zero, size: size))
        backgroundColor = .clear
        isUserInteractionEnabled = false
        strokesView.frame = bounds
        strokesView.isUserInteractionEnabled = false
        strokesView.layer.contents = strokes
        addSubview(strokesView)
        currentContainer.frame = bounds
        currentContainer.isUserInteractionEnabled = false
        currentContainer.contentMode = .scaleToFill
        addSubview(currentContainer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    /// Holding still on an entity or beside a selection doesn't fill the painting.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === longPressGesture, let shouldBegin else { return true }
        return shouldBegin(gestureRecognizer.location(in: gestureRecognizer.view))
    }

    /// The brush size preview's width in the painting: the pen's width at that size.
    func brushPreviewWidth(for size: CGFloat) -> CGFloat {
        PhotoDrawingPenElement.lineWidth(size, drawingSize: drawingSize)
    }

    /// The drawing gestures go on the view the painting sits in, so a stroke may start outside the photo.
    func attachGestures(to gestureView: UIView) {
        let gesture = PhotoDrawingGestureRecognizer(target: self, action: #selector(handleDrawing(_:)))
        gesture.delegate = self
        gesture.maximumNumberOfTouches = 1
        gesture.shouldBeginAt = { [weak self] point in
            guard let self else { return false }
            if let shouldBegin, !shouldBegin(point) {
                return false
            }
            if undoStack.isEmpty, !hasOpaqueData, tool == .eraser {
                return false
            }
            if tool == .blur, preparedBlurredImage == nil {
                return false
            }
            if let pen = uncommittedElement as? PhotoDrawingPenElement, pen.isFinishingArrow {
                return false
            }
            return true
        }
        gestureView.addGestureRecognizer(gesture)
        drawingGesture = gesture
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        press.minimumPressDuration = 0.45
        press.allowableMovement = 2
        press.delegate = self
        gestureView.addGestureRecognizer(press)
        longPressGesture = press
    }

    func setGesturesEnabled(_ isEnabled: Bool) {
        drawingGesture?.isEnabled = isEnabled
        longPressGesture?.isEnabled = isEnabled
        if !isEnabled {
            cancelDrawing()
        }
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }

    /// A stroke still drawing out its arrowhead or waiting to be committed is committed now.
    func commitPendingStroke() {
        guard uncommittedElement != nil, !isDrawing else { return }
        finishDrawing(rect: CGRect(origin: .zero, size: drawingSize), animated: false)
    }

    func undo() {
        guard let operation = undoStack.popLast() else { return }
        switch operation {
        case .clearAll(let rect):
            if let slice = slice(for: rect) {
                redoStack.append(.slice(slice))
            }
            crossDissolve {
                self.setStrokes(nil)
            }
            updateBlurredImage()
        case .slice(let slice):
            if let current = self.slice(for: slice.rect) {
                redoStack.append(.slice(current))
            }
            crossDissolve {
                self.apply(slice)
            }
            updateBlurredImage()
        case .addEntity(let id):
            if let removed = removeEntity?(id) {
                redoStack.append(.removeEntity(removed.entity, index: removed.index))
            }
        case .removeEntity(let entity, let index):
            restoreEntity?(entity, index)
            redoStack.append(.addEntity(entity.id))
        }
        updateInternalState()
    }

    func redo() {
        guard let operation = redoStack.popLast() else { return }
        switch operation {
        case .clearAll:
            break
        case .slice(let slice):
            if !undoStack.isEmpty || hasOpaqueData, let current = self.slice(for: slice.rect) {
                undoStack.append(.slice(current))
            } else {
                undoStack.append(.clearAll(slice.rect))
            }
            crossDissolve {
                self.apply(slice)
            }
            updateBlurredImage()
        case .addEntity(let id):
            if let removed = removeEntity?(id) {
                undoStack.append(.removeEntity(removed.entity, index: removed.index))
            }
        case .removeEntity(let entity, let index):
            restoreEntity?(entity, index)
            undoStack.append(.addEntity(entity.id))
        }
        updateInternalState()
    }

    /// `clear`: the strokes and entities go, fading, and nothing is left to undo.
    func clear() {
        cancelDrawing()
        removeAllEntities?()
        undoStack.removeAll()
        redoStack.removeAll()
        hasOpaqueData = false
        let snapshot = UIView(frame: bounds)
        snapshot.layer.contents = strokes
        snapshot.isUserInteractionEnabled = false
        addSubview(snapshot)
        setStrokes(nil)
        UIView.animate(withDuration: 0.2, animations: { snapshot.alpha = 0 }, completion: { _ in
            snapshot.removeFromSuperview()
        })
        updateInternalState()
        updateBlurredImage()
    }

    func onEntityAdded(_ entity: PhotoDrawingEntity) {
        redoStack.removeAll()
        undoStack.append(.addEntity(entity.id))
        updateInternalState()
    }

    func onEntityRemoved(_ entity: PhotoDrawingEntity, index: Int) {
        redoStack.removeAll()
        undoStack.append(.removeEntity(entity, index: index))
        updateInternalState()
    }

    /// The blurred photo and strokes Blur paints with, made again after the strokes change.
    func updateBlurredImage() {
        guard tool == .blur else {
            preparedBlurredImage = nil
            return
        }
        guard let photo = getFullImage?() else { return }
        let strokes = strokes
        let drawingSize = drawingSize
        Self.blurQueue.async { [weak self] in
            let blurred = PhotoDrawingBlur.makeImage(photo: photo, strokes: strokes, drawingSize: drawingSize)
            DispatchQueue.main.async { [weak self] in
                guard let self, tool == .blur else { return }
                preparedBlurredImage = blurred
            }
        }
    }

    private func updateInternalState() {
        stateUpdated?(internalState)
    }

    private func setStrokes(_ image: CGImage?) {
        strokes = image
        strokesView.layer.contents = image
    }

    private func crossDissolve(_ changes: @escaping () -> Void) {
        UIView.transition(with: strokesView, duration: 0.2, options: .transitionCrossDissolve, animations: changes)
    }

    // MARK: Drawing

    @objc private func handleDrawing(_ recognizer: PhotoDrawingGestureRecognizer) {
        let state: PhotoDrawingGestureState =
            switch recognizer.state {
            case .began: .began
            case .changed: .changed
            case .ended: .ended
            default: .cancelled
            }
        let velocity = recognizer.velocity(in: self)
        let point = PhotoDrawingPoint(location: recognizer.location(in: self), velocity: hypot(velocity.x, velocity.y))
        let timestamp = CACurrentMediaTime()
        switch state {
        case .began:
            isDrawing = true
            previousPointTimestamp = timestamp
            if uncommittedElement != nil {
                finishDrawing(rect: CGRect(origin: .zero, size: drawingSize), animated: false)
            }
            drawingBegan?()
            let element = makeElement()
            if let renderView = element.makeRenderView() {
                switch tool {
                case .eraser:
                    strokesView.mask = renderView
                case .blur:
                    currentContainer.image = preparedBlurredImage.map { UIImage(cgImage: $0) }
                    currentContainer.mask = renderView
                default:
                    currentContainer.addSubview(renderView)
                }
                currentRenderView = renderView
            }
            element.updatePath(point, state: state)
            uncommittedElement = element
            updateInternalState()
        case .changed:
            if let previousPointTimestamp, timestamp - previousPointTimestamp < 0.016 {
                return
            }
            previousPointTimestamp = timestamp
            uncommittedElement?.updatePath(point, state: state)
        case .cancelled,
             .ended:
            isDrawing = false
            guard let element = uncommittedElement else {
                updateInternalState()
                return
            }
            element.updatePath(point, state: state)
            if element.isValid {
                let rect = element.bounds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak element] in
                    guard let self, let element, uncommittedElement === element else { return }
                    finishDrawing(rect: rect, animated: true)
                }
            } else {
                cancelDrawing()
            }
            updateInternalState()
        }
    }

    /// `setupNewElement`.
    private func makeElement() -> PhotoDrawingElement {
        switch tool {
        case .arrow,
             .blur,
             .eraser,
             .pen:
            PhotoDrawingPenElement(
                drawingSize: drawingSize,
                color: toolColor,
                lineWidth: toolBrushSize,
                hasArrow: tool == .arrow,
                isEraser: tool == .eraser,
                isBlur: tool == .blur,
                blurredImage: preparedBlurredImage,
            )
        case .marker:
            PhotoDrawingMarkerElement(drawingSize: drawingSize, color: toolColor, lineWidth: toolBrushSize)
        case .neon:
            PhotoDrawingNeonElement(drawingSize: drawingSize, color: toolColor, lineWidth: toolBrushSize)
        }
    }

    /// `finishDrawing`: what the area held goes on the undo stack and the stroke goes into the strokes; an arrow
    /// draws out its head first.
    private func finishDrawing(rect: CGRect, animated: Bool) {
        let complete = { [weak self] in
            guard let self, let element = uncommittedElement else { return }
            guard element.isValid else {
                cancelDrawing()
                return
            }
            if !undoStack.isEmpty || hasOpaqueData, let slice = slice(for: rect) {
                undoStack.append(.slice(slice))
            } else {
                undoStack.append(.clearAll(rect))
            }
            commit(element)
            redoStack.removeAll()
            uncommittedElement = nil
            updateInternalState()
        }
        if animated, let pen = uncommittedElement as? PhotoDrawingPenElement, pen.hasArrow {
            pen.finishArrow(complete)
        } else {
            complete()
        }
    }

    /// `commit`: the strokes again with the element over them.
    private func commit(_ element: PhotoDrawingElement) {
        let width = Int(drawingSize.width)
        let height = Int(drawingSize.height)
        if let context = PhotoDrawing.makeContext(width: width, height: height) {
            let rect = CGRect(origin: .zero, size: drawingSize)
            UIGraphicsPushContext(context)
            if let strokes {
                UIImage(cgImage: strokes).draw(in: rect, blendMode: .copy, alpha: 1)
            }
            context.setBlendMode(.normal)
            element.draw(in: context, size: drawingSize)
            UIGraphicsPopContext()
            setStrokes(context.makeImage())
        }
        removeRenderView()
        if tool == .blur || element is PhotoDrawingFillElement {
            updateBlurredImage()
        }
    }

    /// `cancelDrawing`.
    private func cancelDrawing() {
        uncommittedElement = nil
        removeRenderView()
    }

    private func removeRenderView() {
        currentRenderView?.removeFromSuperview()
        currentRenderView = nil
        strokesView.mask = nil
        currentContainer.mask = nil
        currentContainer.image = nil
    }

    private func slice(for rect: CGRect) -> Slice? {
        let area = normalizedDrawingRect(rect, drawingSize: drawingSize)
        guard let strokes, !area.isEmpty, let image = strokes.cropping(to: area) else { return nil }
        return Slice(image: image, rect: area)
    }

    /// `applySlice`: an area of the strokes put back as it was.
    private func apply(_ slice: Slice) {
        guard let context = PhotoDrawing.makeContext(width: Int(drawingSize.width), height: Int(drawingSize.height))
        else { return }
        UIGraphicsPushContext(context)
        if let strokes {
            UIImage(cgImage: strokes).draw(in: CGRect(origin: .zero, size: drawingSize), blendMode: .copy, alpha: 1)
        }
        if let image = slice.image {
            UIImage(cgImage: image).draw(in: slice.rect, blendMode: .copy, alpha: 1)
        } else {
            context.clear(slice.rect)
        }
        UIGraphicsPopContext()
        setStrokes(context.makeImage())
    }

    // MARK: Fill

    /// `handleLongPress`: holding still fills the painting with the brush's color, clears it with Eraser or blurs it
    /// with Blur, growing a circle from the finger first.
    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            longPressTimer?.invalidate()
            var color = toolColor
            var blurredImage: CGImage?
            switch tool {
            case .marker: color = color.withAlpha(color.alpha * 0.7)
            case .eraser: color = PhotoDrawingColor(red: 0, green: 0, blue: 0, alpha: 0)
            case .blur: blurredImage = preparedBlurredImage
            default: break
            }
            if tool == .blur, blurredImage == nil {
                return
            }
            feedback.prepare()
            let currentTool = tool
            let circle = CAShapeLayer()
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [
                weak self,
                weak circle,
            ] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.cancelDrawing()
                    let fill = {
                        self.uncommittedElement = PhotoDrawingFillElement(
                            drawingSize: self.drawingSize,
                            color: color,
                            blurredImage: blurredImage,
                        )
                        self.finishDrawing(rect: CGRect(origin: .zero, size: self.drawingSize), animated: false)
                    }
                    if currentTool == .eraser || currentTool == .blur {
                        self.crossDissolve(fill)
                    } else {
                        fill()
                    }
                    self.fillCircleLayer = nil
                    circle?.removeFromSuperlayer()
                    self.feedback.impactOccurred()
                }
            }
            guard currentTool != .eraser, currentTool != .blur else { return }
            let side = 160 * max(drawingSize.width, drawingSize.height) / 400
            circle.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            circle.position = location
            circle.path = CGPath(ellipseIn: circle.bounds, transform: nil)
            circle.fillColor = color.cgColor
            layer.addSublayer(circle)
            fillCircleLayer = circle
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 0.01
            animation.toValue = 12
            animation.duration = 0.35
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            circle.add(animation, forKey: "scale")
        case .cancelled,
             .ended,
             .failed:
            longPressTimer?.invalidate()
            longPressTimer = nil
            if let circle = fillCircleLayer {
                fillCircleLayer = nil
                CATransaction.begin()
                CATransaction.setCompletionBlock { circle.removeFromSuperlayer() }
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 1
                animation.toValue = 0
                animation.duration = 0.3
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                circle.add(animation, forKey: "opacity")
                CATransaction.commit()
            }
        default:
            break
        }
    }
}

// MARK: - PhotoDrawingBlur

/// DrawingScreen's `getFullImage` for Blur: the photo and strokes fitted to 256 px and blurred twice over.
private enum PhotoDrawingBlur {
    private static let context = CIContext()

    static func makeImage(photo: UIImage, strokes: CGImage?, drawingSize: CGSize) -> CGImage? {
        let factor = min(256 / max(drawingSize.width, 1), 256 / max(drawingSize.height, 1))
        let width = max(1, Int((drawingSize.width * factor).rounded()))
        let height = max(1, Int((drawingSize.height * factor).rounded()))
        guard let bitmap = PhotoDrawing.makeContext(width: width, height: height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        UIGraphicsPushContext(bitmap)
        photo.draw(in: rect)
        if let strokes {
            UIImage(cgImage: strokes).draw(in: rect)
        }
        UIGraphicsPopContext()
        guard let image = bitmap.makeImage() else { return nil }
        let input = CIImage(cgImage: image)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: input.extent)
        return context.createCGImage(blurred, from: input.extent)
    }
}
