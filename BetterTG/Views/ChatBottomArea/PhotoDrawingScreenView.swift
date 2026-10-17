// PhotoDrawingScreenView.swift

import UIKit

// MARK: - PhotoDrawingScreenView

/// DrawingScreen as TGPhotoDrawingController shows it in the photo editor's paint tab: the painting over the photo,
/// undo, redo and Clear All along the top, the size slider at the left edge, the brushes over the swatches with the
/// color button and the add button at the sides, and Draw and Text between the editor's Cancel and Done. Text,
/// shapes and arrows sit over the strokes and are selected, moved, sized and turned. Every control fades while a
/// stroke is drawn or an entity is moved. The painting stays over the photo in the tools tab.
final class PhotoDrawingScreenView: UIView, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    // MARK: Private

    private static let controlsAnimationDuration: TimeInterval = 0.2

    // MARK: Internal

    /// The painting's size in pixels, over the whole uncropped photo.
    let paintingSize: CGSize

    /// The controller the color sheet and menus are presented from.
    weak var hostController: UIViewController?
    /// The whole uncropped photo, which Blur paints with.
    var getFullImage: (() -> UIImage?)?
    /// The photo as the paint tab shows it, which the eyedropper picks from.
    var getPreviewImage: (() -> UIImage?)?
    /// The editor's own bars hide with the controls while a stroke is drawn or an entity is moved.
    var onControlsHiddenChanged: ((Bool) -> Void)?
    /// The painting changed: something was drawn, added, undone or cleared.
    var onPaintingChanged: (() -> Void)?

    private let isVideo: Bool
    private let editingBackgroundView = UIView()
    private let paintingOverlayView = UIView()
    private let paintingView = UIView()
    private let canvas: PhotoDrawingCanvasView
    private let entitiesView: PhotoDrawingEntitiesView
    private let selectionOverlayView = UIView()
    private let gestureView = UIView()
    private let controlsView = PhotoDrawingPassthroughView()
    private let bottomGradientLayer = CAGradientLayer()
    private let undoButton = UIButton(type: .system)
    private let redoButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let textCancelButton = UIButton(type: .system)
    private let textDoneButton = UIButton(type: .system)
    private let fillButton = UIButton(type: .system)
    private let arrowButton = UIButton(type: .system)
    private let flipButton = UIButton(type: .system)
    private let sizeSlider = PhotoDrawingSizeSlider()
    private let toolsView = PhotoDrawingToolsView()
    private let textSettingsView = PhotoDrawingTextSettingsView()
    private let swatchesView = PhotoDrawingSwatchesView()
    private let colorButton = PhotoDrawingColorButton()
    private let addButton = PhotoDrawingAddButton()
    private let modeView = PhotoDrawingModeView(titles: [L10n.telegram("Paint.Draw"), L10n.telegram("Paint.Text")])
    private let textAccessoryView = UIInputView(
        frame: CGRect(x: 0, y: 0, width: 320, height: 44),
        inputViewStyle: .keyboard,
    )
    private let accessorySettingsView = PhotoDrawingTextSettingsView()
    private let brushPreviewLayer = CAShapeLayer()
    private var toolState = PhotoDrawingToolState.load()
    private var navigationState = PhotoDrawingCanvasView.NavigationState()
    private var isActive = false
    private var areBarsHidden = false
    private var paintingTransform = CGAffineTransform.identity
    private var pendingMenu: UIMenu?
    private weak var eyedropperView: PhotoDrawingEyedropperView?
    private weak var entityPanGesture: UIPanGestureRecognizer?
    private weak var entityPinchGesture: UIPinchGestureRecognizer?
    private weak var entityRotationGesture: UIRotationGestureRecognizer?
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)

    /// Whether the painting adds anything to the photo.
    var hasDrawing: Bool {
        canvas.paintedStrokes != nil || !paintedEntities.isEmpty
    }

    /// Whether a stroke is being drawn, its arrowhead is still settling or an entity is moved.
    var isTracking: Bool {
        canvas.isDrawing || canvas.isTracking || entitiesView.isInteracting
    }

    /// The painting for the edit, or none when nothing is drawn. The size stays the one the painting was made at.
    var drawing: PhotoDrawing? {
        let result = PhotoDrawing(size: paintingSize, strokes: canvas.paintedStrokes, entities: paintedEntities)
        return result.isEmpty ? nil : result
    }

    /// The entities that draw something; a text being written stays out until it has letters.
    private var paintedEntities: [PhotoDrawingEntity] {
        entitiesView.entities.filter { entity in
            if case .text(let text) = entity.content {
                return !text.string.isEmpty
            }
            return true
        }
    }

    /// `currentColor`: the selected entity's color, or the brush's.
    private var currentColor: PhotoDrawingColor {
        if let selected = entitiesView.selectedEntity {
            return selected.color
        }
        if toolState.selectedTool.hasColor {
            return toolState.brush.color
        }
        return toolState.brushes[.pen]?.color ?? .white
    }

    /// `paintingSize` is the painting's own size when it is opened again, `PhotoDrawing.paintingSize(for:)` of the
    /// photo for a new one. `isVideo` leaves Blur out, as DrawingState's `forVideo`, and the entities' Flip, Move
    /// Forward and Duplicate.
    init(paintingSize: CGSize, drawing: PhotoDrawing?, isVideo: Bool = false) {
        self.paintingSize = paintingSize
        self.isVideo = isVideo
        self.canvas = PhotoDrawingCanvasView(size: paintingSize, strokes: drawing?.strokes)
        self.entitiesView = PhotoDrawingEntitiesView(paintingSize: paintingSize, entities: drawing?.entities ?? [])
        super.init(frame: .zero)
        if isVideo, toolState.selectedTool == .blur {
            toolState.selectedTool = .pen
        }
        toolsView.tools = isVideo ? PhotoDrawingTool.allCases.filter { $0 != .blur } : PhotoDrawingTool.allCases
        configurePainting()
        configureEntities()
        configureControls()
        addInteraction(editMenuInteraction)
        applyToolState(animated: false)
        canvasStateUpdated(canvas.internalState)
        setActive(false, animated: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    /// Touches outside the controls and the drawing area reach the editor underneath.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    // MARK: Gestures

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === entityPanGesture {
            return entitiesView.shouldBeginPan(
                at: gestureRecognizer.location(in: entitiesView),
                overlayPoint: gestureRecognizer.location(in: selectionOverlayView),
            )
        }
        if gestureRecognizer === entityPinchGesture || gestureRecognizer === entityRotationGesture {
            return entitiesView.hasSelection && !entitiesView.isEditingText
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// Lays the painting over the photo shown in `photoFrame`, taken there by `transform`, undo, redo and Clear All
    /// along `topRow`, the bottom controls on the editor's toolbar at `bottomEdge`, and Draw and Text in
    /// `modeRow` between its Cancel and Done. Strokes may start anywhere in `drawingArea`.
    func layout(
        photoFrame: CGRect,
        transform: CGAffineTransform,
        topRow: CGRect,
        drawingArea: CGRect,
        bottomEdge: CGFloat,
        modeRow: CGRect,
    ) {
        paintingOverlayView.frame = photoFrame
        editingBackgroundView.frame = bounds
        paintingView.bounds = CGRect(origin: .zero, size: paintingSize)
        paintingView.center = .zero
        paintingView.transform = transform
        paintingTransform = transform
        selectionOverlayView.frame = bounds
        gestureView.frame = drawingArea
        controlsView.frame = bounds
        let safeArea = safeAreaInsets
        let width = bounds.width
        // DrawingScreen's top row, and the selected entity's buttons under it.
        let side: CGFloat = 44
        let rowTop = topRow.midY - side / 2
        undoButton.frame = CGRect(x: safeArea.left + 16, y: rowTop, width: side, height: side)
        redoButton.frame = CGRect(x: safeArea.left + 16 + side + 2, y: rowTop, width: side, height: side)
        let clearWidth = ceil(clearButton.intrinsicContentSize.width)
        clearButton.frame = CGRect(
            x: width - safeArea.right - 13 - clearWidth,
            y: rowTop,
            width: clearWidth,
            height: side,
        )
        let cancelWidth = ceil(textCancelButton.intrinsicContentSize.width)
        textCancelButton.frame = CGRect(x: safeArea.left + 16, y: rowTop, width: cancelWidth, height: side)
        let doneWidth = ceil(textDoneButton.intrinsicContentSize.width)
        textDoneButton.frame = CGRect(
            x: width - safeArea.right - 13 - doneWidth,
            y: rowTop,
            width: doneWidth,
            height: side,
        )
        let entityRowTop = topRow.maxY
        fillButton.frame = CGRect(x: width / 2 - side / 2, y: entityRowTop, width: side, height: side)
        arrowButton.frame = fillButton.frame
        flipButton.frame = fillButton.frame.offsetBy(dx: side + 8, dy: 0)
        // TextSizeSliderComponent at the left edge, between the top row and the bottom controls' 145 pt.
        let topInset = topRow.midY
        let sliderSize = PhotoDrawingSizeSlider.size
        sizeSlider.frame = CGRect(
            x: 0,
            y: topInset + (bottomEdge - topInset - 145) / 2 - sliderSize.height / 2,
            width: sliderSize.width,
            height: sliderSize.height,
        )
        // The bottom controls stand on the editor's toolbar as DrawingScreen's do on its bottom row, 8 pt higher.
        let bottom = bottomEdge - 8
        let leftEdge = safeArea.left
        let rightEdge = width - safeArea.right
        swatchesView.frame = CGRect(x: leftEdge, y: bottom - 57 - 24, width: rightEdge - leftEdge, height: 24)
        toolsView.frame = CGRect(x: leftEdge, y: bottom - 78 - 120, width: rightEdge - leftEdge, height: 120)
        colorButton.frame = CGRect(x: leftEdge + 6, y: bottom - 89 - side, width: side, height: side)
        addButton.frame = CGRect(x: rightEdge - 6 - side, y: bottom - 89 - side, width: side, height: side)
        textSettingsView.frame = CGRect(
            x: colorButton.frame.maxX,
            y: colorButton.frame.minY,
            width: max(0, addButton.frame.minX - colorButton.frame.maxX),
            height: side,
        )
        modeView.frame = modeRow.insetBy(dx: modeRow.height + 8, dy: 0)
        let gradientHeight: CGFloat = 155
        bottomGradientLayer.frame = CGRect(x: 0, y: bottomEdge - gradientHeight, width: width, height: gradientHeight)
        eyedropperView?.frame = photoFrame
        entitiesView.updateSelection()
    }

    /// The paint tab is open: the controls show and strokes can be drawn.
    func setActive(_ active: Bool, animated: Bool) {
        isActive = active
        if !active {
            commitPendingStroke()
            entitiesView.select(nil)
            eyedropperView?.dismiss()
        }
        canvas.setGesturesEnabled(active)
        updateGestureAvailability()
        selectionOverlayView.isHidden = !active
        updateControlsVisibility(animated: animated)
    }

    /// The painting over the photo, shown in the paint and tools tabs.
    func setPaintingVisible(_ visible: Bool) {
        paintingOverlayView.alpha = visible ? 1 : 0
    }

    /// A stroke still drawing out its arrowhead and a text being written are committed before the edit is taken.
    func commitPendingStroke() {
        canvas.commitPendingStroke()
        entitiesView.endEditing()
    }

    /// DrawingScreen's `saveToolState`, on both Done and Cancel.
    func saveToolState() {
        toolState.save()
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }

    func editMenuInteraction(
        _: UIEditMenuInteraction,
        menuFor _: UIEditMenuConfiguration,
        suggestedActions _: [UIMenuElement],
    ) -> UIMenu? {
        pendingMenu
    }

    // MARK: Configuration

    private func configurePainting() {
        // While a text is written a tap beside the photo ends it, as on DrawingTextEntityView's fade.
        editingBackgroundView.isHidden = true
        editingBackgroundView.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(editingBackgroundTapped),
        ))
        addSubview(editingBackgroundView)
        paintingOverlayView.clipsToBounds = true
        paintingOverlayView.isUserInteractionEnabled = false
        paintingOverlayView.accessibilityIgnoresInvertColors = true
        addSubview(paintingOverlayView)
        paintingView.layer.anchorPoint = .zero
        paintingView.isUserInteractionEnabled = false
        paintingOverlayView.addSubview(paintingView)
        paintingView.addSubview(canvas)
        paintingView.addSubview(entitiesView)
        selectionOverlayView.isUserInteractionEnabled = false
        addSubview(selectionOverlayView)
        addSubview(gestureView)
        canvas.attachGestures(to: gestureView)
        canvas.getFullImage = { [weak self] in self?.getFullImage?() }
        canvas.stateUpdated = { [weak self] state in
            self?.canvasStateUpdated(state)
        }
        canvas.drawingBegan = { [weak self] in
            self?.eyedropperView?.dismiss()
        }
        // DrawingScreen's `shouldBegin`: an entity or a handle takes the touch, and a touch beside a selection
        // only deselects.
        canvas.shouldBegin = { [weak self] point in
            guard let self, !entitiesView.isEditingText else { return false }
            let paintingPoint = entitiesView.convert(point, from: gestureView)
            let overlayPoint = selectionOverlayView.convert(point, from: gestureView)
            if entitiesView.entity(at: paintingPoint) != nil || entitiesView.selectionHandle(at: overlayPoint) != nil {
                return false
            }
            if entitiesView.hasSelection {
                entitiesView.select(nil)
                return false
            }
            return true
        }
    }

    private func configureEntities() {
        canvas.hasEntities = { [weak self] in !(self?.entitiesView.entities.isEmpty ?? true) }
        canvas.removeEntity = { [weak self] id in self?.entitiesView.remove(id) }
        canvas.restoreEntity = { [weak self] entity, index in self?.entitiesView.restore(entity, at: index) }
        canvas.removeAllEntities = { [weak self] in self?.entitiesView.removeAll() }
        entitiesView.selectionOverlay = selectionOverlayView
        entitiesView.textAccessoryView = textAccessoryView
        entitiesView.centerPosition = { [weak self] in
            guard let self else { return .zero }
            let bounds = paintingOverlayView.bounds
            return entitiesView.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: paintingOverlayView)
        }
        entitiesView.initialRotation = { [weak self] in
            guard let self else { return 0 }
            return -atan2(paintingTransform.b, paintingTransform.a)
        }
        entitiesView.onEntityAdded = { [weak self] entity in
            self?.canvas.onEntityAdded(entity)
        }
        entitiesView.onEntityRemoved = { [weak self] entity, index in
            self?.canvas.onEntityRemoved(entity, index: index)
        }
        entitiesView.onSelectionChanged = { [weak self] _ in
            self?.selectionChanged()
        }
        entitiesView.onInteractionChanged = { [weak self] _ in
            self?.updateControlsVisibility(animated: true)
        }
        entitiesView.onEditingChanged = { [weak self] _ in
            self?.editingChanged()
        }
        entitiesView.onMenuRequested = { [weak self] entity, isTopmost in
            self?.presentMenu(for: entity, isTopmost: isTopmost)
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleEntityPan(_:)))
        pan.delegate = self
        gestureView.addGestureRecognizer(pan)
        entityPanGesture = pan
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleEntityPinch(_:)))
        pinch.delegate = self
        gestureView.addGestureRecognizer(pinch)
        entityPinchGesture = pinch
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleEntityRotation(_:)))
        rotation.delegate = self
        gestureView.addGestureRecognizer(rotation)
        entityRotationGesture = rotation
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleEntityTap(_:)))
        tap.delegate = self
        gestureView.addGestureRecognizer(tap)
        accessorySettingsView.frame = textAccessoryView.bounds
        accessorySettingsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textAccessoryView.addSubview(accessorySettingsView)
        for settingsView in [textSettingsView, accessorySettingsView] {
            settingsView.onStyle = { [weak self] in self?.updateSelectedText { $0.style = $0.style.next } }
            settingsView.onAlignment = { [weak self] in self?.updateSelectedText { $0.alignment = $0.alignment.next } }
            settingsView.onFont = { [weak self] font in self?.updateSelectedText { $0.font = font } }
        }
    }

    private func configureControls() {
        addSubview(controlsView)
        bottomGradientLayer.colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.5).cgColor]
        controlsView.layer.addSublayer(bottomGradientLayer)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let iconButtons: [(UIButton, String, String, () -> Void)] = [
            (
                undoButton,
                "arrow.uturn.backward",
                "Accessibility.PhotoEditor.Undo",
                { [weak self] in self?.undoPressed() },
            ),
            (
                redoButton,
                "arrow.uturn.forward",
                "Accessibility.PhotoEditor.Redo",
                { [weak self] in self?.redoPressed() },
            ),
            (fillButton, "square", "Accessibility.PhotoEditor.Fill", { [weak self] in self?.fillPressed() }),
            (
                arrowButton,
                "arrow.right",
                "Accessibility.PhotoEditor.ArrowType",
                { [weak self] in self?.arrowPressed() },
            ),
        ]
        for (button, symbol, label, action) in iconButtons {
            button.setImage(UIImage(systemName: symbol, withConfiguration: symbolConfiguration), for: .normal)
            button.accessibilityLabel = L10n.betterTG(label)
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        flipButton.setImage(
            UIImage(systemName: "flip.horizontal", withConfiguration: symbolConfiguration),
            for: .normal,
        )
        flipButton.accessibilityLabel = L10n.telegram("Paint.Flip")
        flipButton.addAction(UIAction { [weak self] _ in self?.flipSelectedBubble() }, for: .touchUpInside)
        let textButtons: [(UIButton, String, () -> Void)] = [
            (clearButton, L10n.telegram("Paint.Clear"), { [weak self] in self?.clearPressed() }),
            (
                textCancelButton,
                L10n.telegram("Common.Cancel"),
                { [weak self] in self?.entitiesView.endEditing(reset: true) },
            ),
            (textDoneButton, L10n.telegram("Common.Done"), { [weak self] in self?.entitiesView.endEditing() }),
        ]
        for (button, title, action) in textButtons {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        textDoneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        for button in [
            undoButton,
            redoButton,
            clearButton,
            textCancelButton,
            textDoneButton,
            fillButton,
            arrowButton,
            flipButton,
        ] {
            button.tintColor = .white
            controlsView.addSubview(button)
        }
        sizeSlider.accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Size")
        sizeSlider.onValueChanged = { [weak self] value in
            self?.sizeChanged(value)
        }
        sizeSlider.onReleased = { [weak self] in
            self?.setBrushPreview(nil)
        }
        controlsView.addSubview(sizeSlider)
        toolsView.onSelect = { [weak self] tool in
            self?.selectTool(tool)
        }
        controlsView.addSubview(toolsView)
        controlsView.addSubview(textSettingsView)
        swatchesView.onSelect = { [weak self] color in
            self?.applySwatchColor(color)
        }
        controlsView.addSubview(swatchesView)
        colorButton.addAction(UIAction { [weak self] _ in self?.presentColorPicker() }, for: .touchUpInside)
        controlsView.addSubview(colorButton)
        addButton.addAction(UIAction { [weak self] _ in self?.addPressed() }, for: .touchUpInside)
        controlsView.addSubview(addButton)
        modeView.onSelect = { [weak self] index in
            self?.modeSelected(index)
        }
        controlsView.addSubview(modeView)
        brushPreviewLayer.fillColor = UIColor.white.cgColor
        brushPreviewLayer.strokeColor = UIColor(white: 0, alpha: 0.4).cgColor
        brushPreviewLayer.lineWidth = 1
        brushPreviewLayer.opacity = 0
        layer.addSublayer(brushPreviewLayer)
    }

    // MARK: State

    /// The brush's tool, color and size, or the selected entity's, reach the canvas and the controls.
    private func applyToolState(animated: Bool) {
        let brush = toolState.brush
        canvas.tool = toolState.selectedTool
        canvas.toolColor = brush.color
        canvas.toolBrushSize = brush.size
        toolsView.update(state: toolState, animated: animated)
        updateEntityControls()
    }

    /// DrawingScreen's controls for the selected entity: Text in the mode, the text settings for the brushes, the
    /// slider on the font size or the line, its color among the swatches, and its fill, arrow or flip buttons.
    private func updateEntityControls() {
        let selected = entitiesView.selectedEntity
        var selectedText: PhotoDrawingTextEntity?
        var sliderValue = toolState.brush.size
        var isSliderVisible = true
        var showsFill = false
        var showsArrow = false
        var showsFlip = false
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        switch selected?.content {
        case .text(let text):
            selectedText = text
            sliderValue = text.fontSize
        case .shape(let shape):
            isSliderVisible = shape.drawType == .stroke
            sliderValue = shape.lineWidth
            showsFill = true
            showsFlip = shape.kind == .bubble && !isVideo
            let symbol = shape.drawType == .fill ? "square.fill" : "square"
            fillButton.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
        case .vector(let vector):
            sliderValue = vector.lineWidth
            showsArrow = true
            let symbol =
                switch vector.kind {
                case .oneSidedArrow: "arrow.right"
                case .twoSidedArrow: "arrow.left.and.right"
                case .line: "line.diagonal"
                }
            arrowButton.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
        case nil:
            break
        }
        let isEditing = entitiesView.isEditingText
        modeView.selectedIndex = selectedText == nil ? 0 : 1
        toolsView.isHidden = selectedText != nil
        textSettingsView.isHidden = selectedText == nil
        if let selectedText {
            textSettingsView.update(text: selectedText)
            accessorySettingsView.update(text: selectedText)
        }
        sizeSlider.isHidden = !isSliderVisible
        sizeSlider.setValue(sliderValue)
        fillButton.isHidden = !showsFill || isEditing
        arrowButton.isHidden = !showsArrow || isEditing
        flipButton.isHidden = !showsFlip || isEditing
        let color = currentColor
        let hasColor = selected != nil || toolState.selectedTool.hasColor
        swatchesView.selectedColor = hasColor ? color : nil
        colorButton.color = color
        colorButton.isColorHidden = !hasColor || PhotoDrawingSwatchesView.presetColors.contains(color)
    }

    private func canvasStateUpdated(_ state: PhotoDrawingCanvasView.NavigationState) {
        let wasDrawing = navigationState.isDrawing
        navigationState = state
        updateTopRow()
        if wasDrawing != state.isDrawing {
            updateControlsVisibility(animated: true)
        }
        onPaintingChanged?()
    }

    /// Undo, redo and Clear All, or Cancel and Done while a text is written.
    private func updateTopRow() {
        let isEditing = entitiesView.isEditingText
        undoButton.isHidden = isEditing
        undoButton.isEnabled = navigationState.canUndo
        undoButton.alpha = navigationState.canUndo ? 1 : 0.4
        redoButton.isHidden = isEditing || !navigationState.canRedo
        clearButton.isHidden = isEditing
        clearButton.isEnabled = navigationState.canClear
        clearButton.alpha = navigationState.canClear ? 1 : 0.4
        textCancelButton.isHidden = !isEditing
        textDoneButton.isHidden = !isEditing
    }

    private func selectionChanged() {
        eyedropperView?.dismiss()
        updateEntityControls()
    }

    /// A text being written takes the touches from the drawing.
    private func editingChanged() {
        let isEditing = entitiesView.isEditingText
        editingBackgroundView.isHidden = !isEditing
        paintingOverlayView.isUserInteractionEnabled = isEditing
        paintingView.isUserInteractionEnabled = isEditing
        updateGestureAvailability()
        updateTopRow()
        updateEntityControls()
        onPaintingChanged?()
    }

    private func updateGestureAvailability() {
        gestureView.isUserInteractionEnabled = isActive && !entitiesView.isEditingText
    }

    /// DrawingScreen's `controlsAreVisible`: everything fades while a stroke is drawn or an entity is moved.
    private func updateControlsVisibility(animated: Bool) {
        let isBusy = navigationState.isDrawing || entitiesView.isInteracting
        let hidden = !isActive || isBusy
        controlsView.isUserInteractionEnabled = !hidden
        let changes = {
            self.controlsView.alpha = hidden ? 0 : 1
        }
        if animated {
            UIView.animate(
                withDuration: Self.controlsAnimationDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes,
            )
        } else {
            changes()
        }
        let barsHidden = isActive && isBusy
        guard barsHidden != areBarsHidden else { return }
        areBarsHidden = barsHidden
        onControlsHiddenChanged?(barsHidden)
    }

    private func undoPressed() {
        eyedropperView?.dismiss()
        entitiesView.select(nil)
        canvas.undo()
    }

    private func redoPressed() {
        eyedropperView?.dismiss()
        entitiesView.select(nil)
        canvas.redo()
    }

    /// Clear All asks first with Clear Painting.
    private func clearPressed() {
        eyedropperView?.dismiss()
        let clear = TelegramContextMenuAction(title: L10n.telegram("Paint.ClearConfirm"), isDestructive: true) {
            [weak self] in
            self?.entitiesView.select(nil)
            self?.canvas.clear()
        }
        hostController?.presentTelegramContextMenu(
            sourceView: clearButton,
            actions: [clear],
            presentationStyle: .menuOnly,
        )
    }

    /// `updateSelectedTool`: a brush deselects the entity.
    private func selectTool(_ tool: PhotoDrawingTool) {
        eyedropperView?.dismiss()
        entitiesView.select(nil)
        guard tool != toolState.selectedTool else { return }
        toolState.selectedTool = tool
        applyToolState(animated: true)
    }

    /// `updateBrushSize` with `previewBrushSize`: the selected entity's font size or line, or the brush's size.
    private func sizeChanged(_ value: CGFloat) {
        eyedropperView?.dismiss()
        if let selected = entitiesView.selectedEntity {
            entitiesView.update(selected.id) { entity in
                switch entity.content {
                case .text(var text):
                    text.fontSize = value
                    entity.content = .text(text)
                case .shape(var shape):
                    shape.lineWidth = value
                    entity.content = .shape(shape)
                case .vector(var vector):
                    vector.lineWidth = value
                    entity.content = .vector(vector)
                }
            }
            return
        }
        toolState.brush.size = value
        canvas.toolBrushSize = value
        setBrushPreview(value)
    }

    /// `applySwatchColor`: Eraser and Blur give way to the pen.
    private func applySwatchColor(_ color: PhotoDrawingColor) {
        eyedropperView?.dismiss()
        applyColor(color)
    }

    /// `updateColor`: the selected entity's color, or the brush's.
    private func applyColor(_ color: PhotoDrawingColor) {
        if let selected = entitiesView.selectedEntity {
            entitiesView.update(selected.id) { $0.color = color }
            updateEntityControls()
            return
        }
        if !toolState.selectedTool.hasColor {
            toolState.selectedTool = .pen
        }
        toolState.brush.color = color
        applyToolState(animated: true)
    }

    /// The add button: the shapes' menu while drawing, a new text in the text mode.
    private func addPressed() {
        eyedropperView?.dismiss()
        if case .text = entitiesView.selectedEntity?.content {
            addText()
            return
        }
        let color = currentColor
        let shapes: [(String, String, PhotoDrawingEntity.Content)] = [
            ("Paint.Rectangle", "rectangle", .shape(PhotoDrawingShapeEntity(kind: .rectangle, size: .zero))),
            ("Paint.Ellipse", "circle", .shape(PhotoDrawingShapeEntity(kind: .ellipse, size: .zero))),
            ("Paint.Bubble", "bubble.left", .shape(PhotoDrawingShapeEntity(kind: .bubble, size: .zero))),
            ("Paint.Star", "star", .shape(PhotoDrawingShapeEntity(kind: .star, size: .zero))),
            ("Paint.Arrow", "arrow.up.right", .vector(PhotoDrawingVectorEntity(start: .zero, end: .zero))),
        ]
        let actions = shapes.map { key, symbol, content in
            TelegramContextMenuAction(title: L10n.telegram(key), image: UIImage(systemName: symbol)) { [weak self] in
                self?.entitiesView.insertNew(content, color: color)
            }
        }
        hostController?.presentTelegramContextMenu(
            sourceView: addButton,
            actions: actions,
            presentationStyle: .menuOnly,
        )
    }

    /// `addTextEntity`: white filled San Francisco, written at once.
    private func addText() {
        entitiesView.insertNew(.text(PhotoDrawingTextEntity(string: "", width: 0)), color: .white)
    }

    /// ModeComponent: Draw lets a selected text go, Text adds one.
    private func modeSelected(_ index: Int) {
        eyedropperView?.dismiss()
        if index == 1 {
            addText()
        } else if case .text = entitiesView.selectedEntity?.content {
            entitiesView.select(nil)
        }
        updateEntityControls()
    }

    private func updateSelectedText(_ change: @escaping (inout PhotoDrawingTextEntity) -> Void) {
        guard let selected = entitiesView.selectedEntity, case .text = selected.content else { return }
        entitiesView.update(selected.id) { entity in
            guard case .text(var text) = entity.content else { return }
            change(&text)
            entity.content = .text(text)
        }
    }

    /// The fill button between a filled and an outlined shape.
    private func fillPressed() {
        guard let selected = entitiesView.selectedEntity, case .shape = selected.content else { return }
        entitiesView.update(selected.id) { entity in
            guard case .shape(var shape) = entity.content else { return }
            shape.drawType = shape.drawType == .fill ? .stroke : .fill
            entity.content = .shape(shape)
        }
    }

    /// The arrow button through the arrow's kinds.
    private func arrowPressed() {
        guard let selected = entitiesView.selectedEntity, case .vector = selected.content else { return }
        entitiesView.update(selected.id) { entity in
            guard case .vector(var vector) = entity.content else { return }
            vector.kind = vector.kind.next
            entity.content = .vector(vector)
        }
    }

    /// `flipSelectedEntity`: the bubble's tail to the other side.
    private func flipSelectedBubble() {
        guard let selected = entitiesView.selectedEntity else { return }
        entitiesView.update(selected.id) { entity in
            guard case .shape(var shape) = entity.content, shape.kind == .bubble else { return }
            shape.tailPosition.x = 1 - shape.tailPosition.x
            entity.content = .shape(shape)
        }
    }

    /// `requestedMenuForEntityView`: Delete, Edit or Flip, Move Forward and Duplicate over the entity.
    private func presentMenu(for entity: PhotoDrawingEntity, isTopmost: Bool) {
        let id = entity.id
        var actions = [UIAction(title: L10n.telegram("Paint.Delete"), attributes: .destructive) { [weak self] _ in
            self?.entitiesView.delete(id)
        }]
        switch entity.content {
        case .text:
            actions.append(UIAction(title: L10n.telegram("Paint.Edit")) { [weak self] _ in
                self?.entitiesView.beginEditing(id)
            })
        case .shape(let shape) where shape.kind == .bubble && !isVideo:
            actions.append(UIAction(title: L10n.telegram("Paint.Flip")) { [weak self] _ in
                self?.flipSelectedBubble()
            })
        default:
            break
        }
        if !isTopmost, !isVideo {
            actions.append(UIAction(title: L10n.telegram("Paint.MoveForward")) { [weak self] _ in
                self?.entitiesView.bringToFront(id)
            })
        }
        if !isVideo {
            actions.append(UIAction(title: L10n.telegram("Paint.Duplicate")) { [weak self] _ in
                self?.entitiesView.duplicate(id)
            })
        }
        pendingMenu = UIMenu(children: actions)
        let point = entitiesView.selectionFrame(in: self).map { CGPoint(x: $0.midX, y: $0.minY) }
            ?? entitiesView.convert(entity.center, to: self)
        editMenuInteraction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }

    @objc private func handleEntityPan(_ recognizer: UIPanGestureRecognizer) {
        entitiesView.handlePan(recognizer, overlayPoint: recognizer.location(in: selectionOverlayView))
    }

    @objc private func handleEntityPinch(_ recognizer: UIPinchGestureRecognizer) {
        entitiesView.handlePinch(recognizer)
    }

    @objc private func handleEntityRotation(_ recognizer: UIRotationGestureRecognizer) {
        entitiesView.handleRotate(recognizer)
    }

    @objc private func handleEntityTap(_ recognizer: UITapGestureRecognizer) {
        entitiesView.handleTap(at: recognizer.location(in: entitiesView))
    }

    @objc private func editingBackgroundTapped() {
        entitiesView.endEditing()
    }

    /// The brush's width in the middle of the photo while the size is dragged.
    private func setBrushPreview(_ size: CGFloat?) {
        guard let size else {
            brushPreviewLayer.opacity = 0
            return
        }
        let transform = paintingTransform
        let scale = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
        let diameter = max(2, canvas.brushPreviewWidth(for: size) * scale)
        let center = CGPoint(x: paintingOverlayView.frame.midX, y: paintingOverlayView.frame.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        brushPreviewLayer.frame = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter,
        )
        brushPreviewLayer.path = CGPath(ellipseIn: brushPreviewLayer.bounds, transform: nil)
        brushPreviewLayer.opacity = 1
        CATransaction.commit()
    }

    // MARK: Colors

    /// ColorPickerScreen for the brush's or the selected entity's color.
    private func presentColorPicker() {
        eyedropperView?.dismiss()
        guard let hostController else { return }
        let picker = PhotoDrawingColorPickerViewController(color: currentColor, width: hostController.view.bounds.width)
        picker.onColorChanged = { [weak self] color in
            self?.applyColor(color)
        }
        picker.onEyedropper = { [weak self] in
            self?.presentEyedropper()
        }
        hostController.present(picker, animated: true)
    }

    /// EyedropperView over the photo with its painting, picking at one pixel a point.
    private func presentEyedropper() {
        guard eyedropperView == nil, let snapshot = makeSnapshot() else { return }
        let eyedropper = PhotoDrawingEyedropperView(
            frame: paintingOverlayView.frame,
            snapshot: snapshot.image,
            pixels: snapshot.pixels,
            bytesPerRow: snapshot.bytesPerRow,
        )
        eyedropper.onComplete = { [weak self] color in
            self?.applyColor(color)
        }
        addSubview(eyedropper)
        eyedropperView = eyedropper
    }

    /// The photo and its painting at the size they are shown.
    private func makeSnapshot() -> (image: CGImage, pixels: Data, bytesPerRow: Int)? {
        let size = paintingOverlayView.bounds.size
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard let context = PhotoDrawing.makeContext(width: width, height: height) else { return nil }
        UIGraphicsPushContext(context)
        getPreviewImage?()?.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        PhotoDrawing(size: paintingSize, strokes: canvas.strokes, entities: paintedEntities)
            .draw(in: context, transform: paintingTransform)
        guard let image = context.makeImage(), let data = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        return (image, Data(bytes: data, count: bytesPerRow * height), bytesPerRow)
    }
}

// MARK: - PhotoDrawingPassthroughView

/// A layer of controls that lets touches between them through to the views under it.
final class PhotoDrawingPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
