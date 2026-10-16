// PhotoCropView.swift

import UIKit

// MARK: - PhotoCropGridMode

/// TGPhotoCropViewGridMode: thirds while the crop moves, ninths while the photo straightens.
enum PhotoCropGridMode {
    case none
    case major
    case minor
}

// MARK: - PhotoCropView

/// TGPhotoCropView with its TGPhotoCropScrollView: the photo under the crop area, panned and pinched inside it, the
/// area resized by its handles, turned a quarter, mirrored, and straightened with the dial under it. The photo and the
/// area are laid out in a frame that turns with the crop's quarter turns, and the photo's place follows from the
/// area's frame and the crop rectangle. A second after the area changes it evenly fills the view again; at rest the
/// photo outside it is blurred. A video's crop (`hasArbitraryRotation` off) has no dial and can show the playing
/// video over the still frame.
final class PhotoCropView: UIView, UIGestureRecognizerDelegate {
    // MARK: Private

    /// `TGPhotoCropViewOverscreenSize`: the dimming reaches past the screen's edges.
    private static let overscreen: CGFloat = 1000
    private static let rotationViewHeight: CGFloat = 100
    /// POPSpringAnimation at speed 7 and bounciness 1, which TGPhotoCropView uses throughout.
    private static let springDuration: TimeInterval = 0.45

    // MARK: Internal

    /// TGPhotoCropView's `croppingChanged`.
    var onCroppingChanged: (() -> Void)?
    /// TGPhotoCropView's `interactionBegan`: the photo or the area starts moving.
    var onInteractionBegan: (() -> Void)?
    /// TGPhotoCropView's `interactionEnded`: the crop settled after the movement.
    var onInteractionEnded: (() -> Void)?

    /// TGPhotoAvatarCropView's `tapped`: a tap on the picture, which a video's crop uses to play and pause.
    var onTap: (() -> Void)? {
        didSet { tapRecognizer.isEnabled = onTap != nil }
    }

    private(set) var adjustments: PhotoCropAdjustments

    private var image: UIImage
    private var imagePixelSize: CGSize
    /// TGPhotoCropView's `hasArbitraryRotation`: the straightening dial, which a video's crop doesn't have.
    private let hasArbitraryRotation: Bool
    private let orientedView = PhotoCropOrientedView()
    private let imageView = UIImageView()
    private let blurView = UIVisualEffectView(effect: nil)
    private let areaClipView = UIView()
    private let areaImageView = UIImageView()
    private let overlayViews = (0..<4).map { _ in UIView() }
    private let areaView = PhotoCropAreaView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    private let rotationView = PhotoCropRotationView()
    private lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
    /// The views over the still frame, under the area and in it, such as player layers sharing one player.
    private var contentViews = [UIView]()

    /// The crop area in the turned frame.
    private var areaFrame = CGRect.zero
    private var laidOutSize = CGSize.zero
    private var contentGestureCount = 0
    private var animationCount = 0
    private var pinchLargestWidth: CGFloat = 0
    private var pinchStartZoom: CGFloat = 1
    /// TGPhotoCropScrollView's rotation start values: the crop's size and the photo point at its center.
    private var rotationStart: (size: CGSize, point: CGPoint)?
    private var confirmGeneration = 0
    private var isConfirmPending = false
    private var cropAreaChanged = false
    private var isInteracting = false

    var isTracking: Bool {
        contentGestureCount > 0 || areaView.isTracking || rotationView.isTracking
    }

    var isAnimating: Bool {
        animationCount > 0
    }

    var isAspectRatioLocked: Bool {
        adjustments.lockedAspectRatio > .ulpOfOne
    }

    /// `hasArbitraryRotation` off is TGPhotoCropController's `forVideo`: the crop turns only by quarters.
    init(image: UIImage, adjustments: PhotoCropAdjustments, hasArbitraryRotation: Bool = true) {
        self.image = image
        self.imagePixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        self.adjustments = adjustments
        self.hasArbitraryRotation = hasArbitraryRotation
        super.init(frame: .zero)
        for imageView in [imageView, areaImageView] {
            imageView.image = image
            imageView.isUserInteractionEnabled = false
        }
        blurView.isUserInteractionEnabled = false
        areaClipView.clipsToBounds = true
        areaClipView.isUserInteractionEnabled = false
        areaClipView.addSubview(areaImageView)
        for overlayView in overlayViews {
            overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            overlayView.isUserInteractionEnabled = false
        }
        orientedView.addSubview(imageView)
        orientedView.addSubview(blurView)
        orientedView.addSubview(areaClipView)
        for overlayView in overlayViews {
            orientedView.addSubview(overlayView)
        }
        orientedView.addSubview(areaView)
        orientedView.areaView = areaView
        addSubview(orientedView)
        addSubview(rotationView)
        // Without the dial the view stays in place for the quarter turn's snapshot and takes no touches.
        rotationView.isHidden = !hasArbitraryRotation
        rotationView.isUserInteractionEnabled = hasArbitraryRotation
        configureArea()
        configureRotationView()
        panRecognizer.delegate = self
        pinchRecognizer.delegate = self
        tapRecognizer.delegate = self
        tapRecognizer.isEnabled = false
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(tapRecognizer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0 else { return }
        laidOutSize = bounds.size
        guard !areaView.isTracking, !isAnimating else { return }
        if isConfirmPending {
            UIView.performWithoutAnimation { performConfirm(animated: false) }
        }
        areaFrame = fittedAreaFrame()
        UIView.performWithoutAnimation { applyLayout() }
        showBackdrop(animated: false)
    }

    /// Touches under and beside the area belong to the photo (`hitTestEdgeInsets`), and the handles reach past it.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        if hasArbitraryRotation, !rotationView.isHidden, rotationView.alpha > 0.01,
           let hit = rotationView.hitTest(convert(point, to: rotationView), with: event)
        {
            return hit
        }
        if !orientedView.isHidden, let hit = orientedView.hitTest(convert(point, to: orientedView), with: event) {
            return hit
        }
        let reach = bounds.inset(by: UIEdgeInsets(top: -16, left: -100, bottom: -100, right: -100))
        return reach.contains(point) ? self : nil
    }

    // MARK: Gestures

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panRecognizer || gestureRecognizer === pinchRecognizer
            || gestureRecognizer === tapRecognizer
        {
            return !isAnimating && !areaView.isTracking && !rotationView.isTracking
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    private static func setHidden(_ view: UIView, _ hidden: Bool, animated: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        guard animated else {
            view.isHidden = hidden
            view.alpha = alpha
            return
        }
        view.isHidden = false
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            view.alpha = alpha
        } completion: { _ in
            if view.alpha == alpha { view.isHidden = hidden }
        }
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        return !view.isDescendant(of: rotationView) && !(view is PhotoCropHandleView)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        let pair: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer]
        return pair.contains { $0 === gestureRecognizer } && pair.contains { $0 === otherGestureRecognizer }
    }

    /// TGPhotoCropView's `setImage:`: another picture of the same frame, such as a video's current frame for the
    /// quarter turn's snapshot.
    func setImage(_ newImage: UIImage) {
        image = newImage
        imagePixelSize = CGSize(
            width: newImage.size.width * newImage.scale,
            height: newImage.size.height * newImage.scale,
        )
        imageView.image = newImage
        areaImageView.image = newImage
    }

    /// The video crop's picture: two views from `makeView`, under the area and in it, over the still frame, which
    /// stays for the quarter turn's snapshot. Each fills a frame of `originalSize` and turns and mirrors with it.
    func setContentViews(_ makeView: () -> UIView) {
        contentViews.forEach { $0.removeFromSuperview() }
        contentViews = [imageView, areaImageView].map { holder in
            let view = makeView()
            view.isUserInteractionEnabled = false
            view.frame = holder.bounds
            holder.addSubview(view)
            return view
        }
    }

    /// `rotate90DegreesCCWAnimated`: a picture of the crop turns into place, then the area fills the view in the new
    /// orientation.
    func rotate90DegreesCounterclockwise() {
        guard !isAnimating, !isTracking, areaFrame.width > 0 else { return }
        cancelConfirmCountdown()
        rotationStart = nil
        var upright = adjustments
        upright.orientation = .up
        let displayScale = max(1, traitCollection.displayScale)
        let snapshot = UIImageView(image: upright.render(
            image,
            sourcePixelSize: imagePixelSize,
            maximumSide: max(areaFrame.width, areaFrame.height) * displayScale,
        ))
        snapshot.bounds = CGRect(origin: .zero, size: areaFrame.size)
        snapshot.center = .zero
        snapshot.transform = CGAffineTransform(rotationAngle: adjustments.orientation.angle)
        // The turn is animated on a container from no rotation, so it always goes a quarter counterclockwise.
        let pivot = UIView()
        pivot.isUserInteractionEnabled = false
        pivot.bounds = .zero
        pivot.center = orientedView.convert(CGPoint(x: areaFrame.midX, y: areaFrame.midY), to: self)
        pivot.addSubview(snapshot)
        insertSubview(pivot, belowSubview: rotationView)
        orientedView.isHidden = true
        resetBackdrop(animated: false)
        setInterfaceHidden(true, animated: false)
        setCropAreaHidden(true, animated: false)
        adjustments.orientation = adjustments.orientation.nextCounterclockwise
        areaFrame = fittedAreaFrame()
        let targetSize = areaFrame.size
        animationCount += 1
        UIView.animate(springDuration: Self.springDuration, bounce: 0) {
            pivot.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            pivot.transform = CGAffineTransform(rotationAngle: -.pi / 2)
            snapshot.bounds = CGRect(origin: .zero, size: targetSize)
        } completion: { _ in
            pivot.removeFromSuperview()
            self.animationCount -= 1
            UIView.performWithoutAnimation { self.applyLayout() }
            self.orientedView.isHidden = false
            self.setInterfaceHidden(false, animated: true)
            self.setCropAreaHidden(false, animated: true)
            self.showBackdrop(animated: true)
            self.endInteraction()
        }
        onCroppingChanged?()
    }

    /// `mirror`: the photo flips inside the same crop.
    func mirror() {
        guard !isAnimating, !isTracking else { return }
        cancelConfirmCountdown()
        adjustments.isMirrored.toggle()
        resetBackdrop(animated: false)
        areaFrame = fittedAreaFrame()
        UIView.performWithoutAnimation { applyLayout() }
        showBackdrop(animated: false)
        onCroppingChanged?()
        endInteraction()
    }

    /// `setLockedAspectRatio:performResize:`: the crop takes the ratio about its center, inside the photo, or inside
    /// itself once the photo is straightened.
    func setLockedAspectRatio(_ ratio: CGFloat, animated: Bool) {
        guard ratio > 0 else { return unlockAspectRatio() }
        adjustments.lockedAspectRatio = ratio
        areaView.lockedAspectRatio = ratio
        let crop = adjustments.cropRect
        let available = abs(adjustments.rotation) <= .ulpOfOne
            ? CGRect(origin: .zero, size: adjustments.originalSize)
            : crop
        var resized = crop
        resized.size.height = resized.width * ratio
        if resized.height > available.height {
            resized.size.height = available.height
            resized.size.width = resized.height / ratio
        }
        resized.origin = CGPoint(x: crop.midX - resized.width / 2, y: crop.midY - resized.height / 2)
        if resized.minX < available.minX { resized.origin.x = available.minX }
        if resized.minY < available.minY { resized.origin.y = available.minY }
        if resized.maxX > available.maxX { resized.origin.x = available.maxX - resized.width }
        if resized.maxY > available.maxY { resized.origin.y = available.maxY - resized.height }
        let epsilon = max(adjustments.originalSize.width, adjustments.originalSize.height) * 0.005
        if abs(resized.minX - crop.minX) >= epsilon || abs(resized.minY - crop.minY) >= epsilon
            || abs(resized.width - crop.width) >= epsilon * 2 || abs(resized.height - crop.height) >= epsilon * 2
        {
            resetBackdrop(animated: false)
        }
        cancelConfirmCountdown()
        adjustments.cropRect = adjustments.fitted(resized, allowsScale: true)
        evenlyFillArea(animated: animated) { [weak self] in
            self?.endInteraction()
        }
        onCroppingChanged?()
    }

    func unlockAspectRatio() {
        adjustments.lockedAspectRatio = 0
        areaView.lockedAspectRatio = 0
        onCroppingChanged?()
    }

    /// `resetAnimated`: the whole photo, upright, straight and unmirrored, without a locked ratio.
    func reset(animated requestedAnimation: Bool) {
        guard !isAnimating else { return }
        let full = CGRect(origin: .zero, size: adjustments.originalSize)
        let turnsBack = adjustments.orientation != .up
            && (adjustments.isMirrored || abs(adjustments.rotation) > .ulpOfOne || adjustments.cropRect != full)
        let animated = requestedAnimation && !turnsBack
        cropAreaChanged = false
        cancelConfirmCountdown()
        rotationStart = nil
        areaView.lockedAspectRatio = 0
        resetBackdrop(animated: false)
        if adjustments.isMirrored {
            // Telegram unmirrors at once; only the crop and the angle animate back.
            adjustments.isMirrored = false
            UIView.performWithoutAnimation { layoutContent() }
        }
        adjustments = PhotoCropAdjustments(originalSize: adjustments.originalSize)
        rotationView.setAngle(0, animated: animated)
        areaView.setGridMode(.none, animated: animated)
        evenlyFillArea(animated: animated) { [weak self] in
            self?.setInterfaceHidden(false, animated: true)
            self?.setCropAreaHidden(false, animated: true)
            self?.endInteraction()
        }
        onCroppingChanged?()
    }

    /// `performConfirmAnimated`: the crop no smaller than the photo over the maximum zoom, and a resized area evenly
    /// filling the view again.
    func performConfirm(animated: Bool) {
        guard !areaView.isTracking, !isAnimating else { return }
        cancelConfirmCountdown()
        let constrained = adjustments.constrainedToMinimumSize(adjustments.cropRect)
        areaView.setGridMode(.none, animated: animated)
        setInterfaceHidden(false, animated: animated)
        guard cropAreaChanged else {
            if constrained != adjustments.cropRect {
                adjustments.cropRect = adjustments.fitted(constrained, allowsScale: true)
                animateContent(animated: animated)
            }
            showBackdrop(animated: animated)
            onCroppingChanged?()
            endInteraction()
            return
        }
        cropAreaChanged = false
        adjustments.cropRect = adjustments.fitted(constrained, allowsScale: true)
        evenlyFillArea(animated: animated) { [weak self] in
            self?.endInteraction()
        }
        onCroppingChanged?()
    }

    /// TGPhotoCropController settles a waiting area change before it closes.
    func commitPendingChanges() {
        guard isConfirmPending else { return }
        UIView.performWithoutAnimation { performConfirm(animated: false) }
    }

    // MARK: Layout

    /// The view's size in the turned frame.
    private func orientedSize(for orientation: PhotoCropOrientation) -> CGSize {
        orientation.isSideward ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
    }

    /// `_areaSizeForCropRect`: the crop fitted into the view, centered.
    private func fittedAreaFrame() -> CGRect {
        let available = orientedSize(for: adjustments.orientation)
        let size = PhotoCropAdjustments.scaleToSize(adjustments.cropRect.size, available)
        return CGRect(
            x: (available.width - size.width) / 2,
            y: (available.height - size.height) / 2,
            width: size.width,
            height: size.height,
        )
    }

    private func applyLayout() {
        orientedView.bounds = CGRect(origin: .zero, size: orientedSize(for: adjustments.orientation))
        orientedView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        orientedView.transform = CGAffineTransform(rotationAngle: adjustments.orientation.angle)
        layoutContent()
        layoutRotationView()
    }

    /// The photo placed so that the crop rectangle fills the area: mirrored, straightened, then scaled.
    private func layoutContent() {
        let crop = adjustments.cropRect
        guard crop.width > 0, areaFrame.width > 0 else { return }
        let scale = areaFrame.width / crop.width
        let content = adjustments.rotatedContentSize
        var transform = adjustments.isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        transform = transform
            .concatenating(CGAffineTransform(rotationAngle: adjustments.rotation))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let center = CGPoint(
            x: areaFrame.minX + (content.width / 2 - crop.minX) * scale,
            y: areaFrame.minY + (content.height / 2 - crop.minY) * scale,
        )
        let imageBounds = CGRect(origin: .zero, size: adjustments.originalSize)
        imageView.bounds = imageBounds
        imageView.center = center
        imageView.transform = transform
        areaClipView.frame = areaFrame
        areaImageView.bounds = imageBounds
        areaImageView.center = CGPoint(x: center.x - areaFrame.minX, y: center.y - areaFrame.minY)
        areaImageView.transform = transform
        areaView.frame = areaFrame
        blurView.frame = orientedView.bounds.insetBy(dx: -Self.overscreen, dy: -Self.overscreen)
        for contentView in contentViews {
            contentView.frame = imageBounds
        }
        layoutOverlays()
    }

    /// `_layoutOverlayViewsWithFrame`: the dimming above, beside and below the area.
    private func layoutOverlays() {
        let area = areaFrame
        let reach = Self.overscreen
        overlayViews[0].frame = CGRect(x: area.minX, y: area.minY - reach, width: area.width, height: reach)
        overlayViews[1].frame = CGRect(
            x: area.minX - reach,
            y: area.minY - reach,
            width: reach,
            height: area.height + 2 * reach,
        )
        overlayViews[2].frame = CGRect(
            x: area.maxX,
            y: area.minY - reach,
            width: reach,
            height: area.height + 2 * reach,
        )
        overlayViews[3].frame = CGRect(x: area.minX, y: area.maxY, width: area.width, height: reach)
    }

    /// `_layoutRotationViewWithWrapperFrame`: the dial right under the area.
    private func layoutRotationView() {
        let area = orientedView.convert(areaFrame, to: self)
        rotationView.frame = CGRect(
            x: area.midX - bounds.width / 2,
            y: area.maxY,
            width: bounds.width,
            height: Self.rotationViewHeight,
        )
    }

    private func animateContent(animated: Bool) {
        guard animated else {
            UIView.performWithoutAnimation { layoutContent() }
            return
        }
        animationCount += 1
        UIView.animate(springDuration: Self.springDuration, bounce: 0) {
            self.layoutContent()
        } completion: { _ in
            self.animationCount -= 1
        }
    }

    /// `evenlyFillAreaViewAnimated`: the area fills the view at the crop's ratio, and the photo zooms with it.
    private func evenlyFillArea(animated: Bool, completion: (() -> Void)? = nil) {
        areaFrame = fittedAreaFrame()
        guard animated else {
            UIView.performWithoutAnimation { applyLayout() }
            showBackdrop(animated: true)
            completion?()
            return
        }
        animationCount += 1
        UIView.animate(springDuration: Self.springDuration, bounce: 0) {
            self.applyLayout()
        } completion: { _ in
            self.animationCount -= 1
            self.showBackdrop(animated: true)
            completion?()
        }
    }

    /// `showBackdropViewAnimated`: at rest the photo outside the area is blurred.
    private func showBackdrop(animated: Bool) {
        let effect = UIBlurEffect(style: .dark)
        guard animated else {
            blurView.effect = effect
            return
        }
        UIView.animate(withDuration: 0.16, delay: 0, options: .curveEaseOut) {
            self.blurView.effect = effect
        }
    }

    /// `resetBackdropViewsAnimated`.
    private func resetBackdrop(animated: Bool) {
        guard animated, blurView.effect != nil else {
            blurView.effect = nil
            return
        }
        UIView.animate(withDuration: 0.16, delay: 0, options: .curveEaseInOut) {
            self.blurView.effect = nil
        }
    }

    /// `setIntefaceHidden`: the dial hides while the area is resized or turned.
    private func setInterfaceHidden(_ hidden: Bool, animated: Bool) {
        guard hasArbitraryRotation else { return }
        Self.setHidden(rotationView, hidden, animated: animated)
    }

    private func setCropAreaHidden(_ hidden: Bool, animated: Bool) {
        Self.setHidden(areaView, hidden, animated: animated)
    }

    private func beginInteraction() {
        guard !isInteracting else { return }
        isInteracting = true
        onInteractionBegan?()
    }

    /// The interaction ends once the crop settles, or when a button changes it before that.
    private func endInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        onInteractionEnded?()
    }

    // MARK: Confirmation

    /// `startConfirmCountdown`: a second after the last change the area settles.
    private func startConfirmCountdown() {
        guard !areaView.isTracking else { return }
        confirmGeneration += 1
        let generation = confirmGeneration
        isConfirmPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, isConfirmPending, confirmGeneration == generation else { return }
            performConfirm(animated: true)
        }
    }

    private func cancelConfirmCountdown() {
        confirmGeneration += 1
        isConfirmPending = false
    }

    // MARK: Photo gestures

    private func contentGestureBegan() {
        contentGestureCount += 1
        guard contentGestureCount == 1 else { return }
        beginInteraction()
        resetBackdrop(animated: true)
        cancelConfirmCountdown()
        areaView.setGridMode(.major, animated: true)
        rotationStart = nil
    }

    /// TGPhotoCropScrollView fits the photo back over the area when the fingers lift.
    private func contentGestureEnded() {
        contentGestureCount = max(0, contentGestureCount - 1)
        guard contentGestureCount == 0 else { return }
        adjustments.cropRect = adjustments.fitted(adjustments.cropRect, allowsScale: true)
        animateContent(animated: true)
        startConfirmCountdown()
        onCroppingChanged?()
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            contentGestureBegan()
        case .changed:
            let translation = recognizer.translation(in: orientedView)
            recognizer.setTranslation(.zero, in: orientedView)
            let crop = adjustments.cropRect
            guard crop.width > 0, areaFrame.width > 0 else { return }
            let scale = areaFrame.width / crop.width
            adjustments.cropRect.origin.x -= translation.x / scale
            adjustments.cropRect.origin.y -= translation.y / scale
            layoutContent()
        case .cancelled, .ended:
            contentGestureEnded()
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            contentGestureBegan()
            let crop = adjustments.cropRect
            guard crop.width > 0 else { return }
            pinchLargestWidth = crop.width * adjustments.coverFactor(for: crop.size)
            pinchStartZoom = pinchLargestWidth / crop.width
            updatePinch(recognizer)
        case .changed:
            updatePinch(recognizer)
        case .cancelled, .ended:
            contentGestureEnded()
        default:
            break
        }
    }

    /// `handlePinch`: the zoom about the fingers, at most ten times the fitted zoom, and rubber banded below it.
    private func updatePinch(_ recognizer: UIPinchGestureRecognizer) {
        let crop = adjustments.cropRect
        guard crop.width > 0, pinchLargestWidth > 0, areaFrame.width > 0 else { return }
        let maximum = PhotoCropAdjustments.maximumZoomScale
        let zoom = min(pinchStartZoom * recognizer.scale, maximum)
        let constrained = max(1, zoom)
        let banded = max(
            0.25,
            constrained + PhotoCropAdjustments.rubberBandDistance(zoom - constrained, dimension: maximum - 1),
        )
        let width = pinchLargestWidth / banded
        let height = width * crop.height / crop.width
        let location = recognizer.location(in: orientedView)
        let offset = CGPoint(x: location.x - areaFrame.minX, y: location.y - areaFrame.minY)
        let oldScale = areaFrame.width / crop.width
        let newScale = areaFrame.width / width
        let anchor = CGPoint(x: crop.minX + offset.x / oldScale, y: crop.minY + offset.y / oldScale)
        adjustments.cropRect = CGRect(
            x: anchor.x - offset.x / newScale,
            y: anchor.y - offset.y / newScale,
            width: width,
            height: height,
        )
        layoutContent()
    }

    // MARK: Area

    private func configureArea() {
        areaView.lockedAspectRatio = adjustments.lockedAspectRatio
        areaView.shouldBeginResizing = { [weak self] in
            guard let self else { return true }
            return !isAnimating && contentGestureCount == 0 && !rotationView.isTracking
        }
        areaView.didBeginResizing = { [weak self] in
            guard let self else { return }
            beginInteraction()
            resetBackdrop(animated: false)
            cancelConfirmCountdown()
            areaView.setGridMode(.major, animated: true)
            setInterfaceHidden(true, animated: true)
            rotationStart = nil
        }
        areaView.didResize = { [weak self] handle, translation in
            self?.resizeArea(handle, translation: translation)
        }
        areaView.didEndResizing = { [weak self] in
            self?.startConfirmCountdown()
        }
    }

    /// `handleCropAreaChanged`: the photo stays put under the resized area and zooms in where it no longer covers it.
    private func resizeArea(_ handle: PhotoCropAreaView.Handle, translation: CGPoint) {
        let previous = areaFrame
        let crop = adjustments.cropRect
        guard crop.width > 0, previous.width > 0 else { return }
        let frame = cappedAreaFrame(PhotoCropAreaView.resizedFrame(
            previous,
            handle: handle,
            translation: translation,
            aspectRatio: adjustments.lockedAspectRatio,
        ))
        cropAreaChanged = true
        let scale = previous.width / crop.width
        let resized = CGRect(
            x: crop.minX + (frame.minX - previous.minX) / scale,
            y: crop.minY + (frame.minY - previous.minY) / scale,
            width: frame.width / scale,
            height: frame.height / scale,
        )
        adjustments.cropRect = adjustments.fitted(resized, allowsScale: true)
        areaFrame = frame
        layoutContent()
        layoutRotationView()
    }

    /// `_cappedAreaViewRectWithRect`: the area kept inside the view, at the locked ratio.
    private func cappedAreaFrame(_ rect: CGRect) -> CGRect {
        let limits = orientedView.bounds.size
        let minimum = PhotoCropAreaView.minimumSide
        let ratio = adjustments.lockedAspectRatio
        var capped = rect
        if capped.maxX > limits.width {
            capped.origin.x = min(limits.width - minimum, capped.origin.x)
            capped.size.width = max(minimum, limits.width - capped.origin.x)
            if ratio > 0 { capped.size.height = capped.size.width * ratio }
        } else if capped.minX < 0 {
            capped.size.width = capped.maxX
            if ratio > 0 { capped.size.height = capped.size.width * ratio }
            capped.origin.x = 0
        }
        if capped.maxY > limits.height {
            capped.origin.y = min(limits.height - minimum, capped.origin.y)
            capped.size.height = max(minimum, limits.height - capped.origin.y)
            if ratio > 0 { capped.size.width = capped.size.height / ratio }
        } else if capped.minY < 0 {
            capped.size.height = capped.maxY
            if ratio > 0 { capped.size.width = capped.size.height / ratio }
            capped.origin.y = 0
        }
        return capped
    }

    // MARK: Straightening

    private func configureRotationView() {
        rotationView.setAngle(adjustments.rotation, animated: false)
        rotationView.shouldBeginChanging = { [weak self] in
            guard let self else { return true }
            return !isAnimating && contentGestureCount == 0 && !areaView.isTracking
        }
        rotationView.didBeginChanging = { [weak self] in
            guard let self else { return }
            beginInteraction()
            resetBackdrop(animated: true)
            cancelConfirmCountdown()
            areaView.setGridMode(.minor, animated: true)
            storeRotationStart()
        }
        rotationView.angleChanged = { [weak self] angle in
            self?.setRotation(angle)
        }
        rotationView.didEndChanging = { [weak self] in
            guard let self else { return }
            startConfirmCountdown()
            areaView.setGridMode(.none, animated: true)
            onCroppingChanged?()
        }
    }

    private func storeRotationStart() {
        let crop = adjustments.cropRect
        let content = adjustments.rotatedContentSize
        let point = CGPoint(x: crop.midX - content.width / 2, y: crop.midY - content.height / 2)
            .applying(CGAffineTransform(rotationAngle: -adjustments.rotation))
        rotationStart = (crop.size, point)
    }

    /// `setContentRotation:maximize:`: the photo turns about the crop's center and zooms in only as far as it must
    /// to cover the crop, never below the zoom it started from.
    private func setRotation(_ angle: CGFloat) {
        if rotationStart == nil { storeRotationStart() }
        guard let start = rotationStart else { return }
        adjustments.rotation = angle
        let content = adjustments.rotatedContentSize
        let offset = start.point.applying(CGAffineTransform(rotationAngle: angle))
        let rect = CGRect(
            x: content.width / 2 + offset.x - start.size.width / 2,
            y: content.height / 2 + offset.y - start.size.height / 2,
            width: start.size.width,
            height: start.size.height,
        )
        adjustments.cropRect = adjustments.fitted(rect, allowsScale: true)
        layoutContent()
    }
}

// MARK: - PhotoCropOrientedView

/// TGPhotoCropView's area wrapper, turned with the crop. Only the area's handles take touches here.
private final class PhotoCropOrientedView: UIView {
    weak var areaView: PhotoCropAreaView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let areaView, !areaView.isHidden, areaView.alpha > 0.01 else { return nil }
        return areaView.hitTest(convert(point, to: areaView), with: event)
    }
}

// MARK: - PhotoCropAreaView

/// TGPhotoCropAreaView: the crop frame with its corner brackets, the grid, and a handle on each corner and edge.
/// Edges show a bold line while dragged, and all of them while a ratio is locked.
final class PhotoCropAreaView: UIView, UIGestureRecognizerDelegate {
    // MARK: Internal

    enum Handle {
        case top
        case left
        case bottom
        case right
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    /// `TGPhotoCropCornerControlSize`: the smallest area.
    static let minimumSide: CGFloat = 44

    var shouldBeginResizing: (() -> Bool)?
    var didBeginResizing: (() -> Void)?
    var didResize: ((Handle, CGPoint) -> Void)?
    var didEndResizing: (() -> Void)?

    private(set) var isTracking = false

    /// The locked ratio, height over width; zero when unlocked.
    var lockedAspectRatio: CGFloat = 0 {
        didSet { updateEdgeHighlights() }
    }

    // MARK: Private

    private let majorGridView = PhotoCropGridView(mode: .major)
    private let minorGridView = PhotoCropGridView(mode: .minor)
    private var handleViews = [PhotoCropHandleView]()
    private var edgeHighlights = [Handle: UIView]()
    private var activeEdge: Handle?
    private var gridMode = PhotoCropGridMode.none

    override init(frame: CGRect) {
        super.init(frame: frame)
        let width = frame.width
        let height = frame.height
        let line: CGFloat = 1
        addLine(CGRect(x: 0, y: 0, width: width, height: line), [.flexibleWidth])
        addLine(CGRect(x: 0, y: height - line, width: width, height: line), [.flexibleWidth, .flexibleTopMargin])
        addLine(CGRect(x: 0, y: 0, width: line, height: height), [.flexibleHeight])
        addLine(CGRect(x: width - line, y: 0, width: line, height: height), [.flexibleHeight, .flexibleLeftMargin])
        // PhotoEditorCropCorners: 20 pt brackets, 2 pt outside the frame and 1 pt inside.
        let length: CGFloat = 20
        let thickness: CGFloat = 3
        let near: CGFloat = -2
        let farX = width + 2 - length
        let farY = height + 2 - length
        addLine(CGRect(x: near, y: near, width: length, height: thickness), [])
        addLine(CGRect(x: near, y: near, width: thickness, height: length), [])
        addLine(CGRect(x: farX, y: near, width: length, height: thickness), [.flexibleLeftMargin])
        addLine(CGRect(x: width - 1, y: near, width: thickness, height: length), [.flexibleLeftMargin])
        addLine(CGRect(x: near, y: height - 1, width: length, height: thickness), [.flexibleTopMargin])
        addLine(CGRect(x: near, y: farY, width: thickness, height: length), [.flexibleTopMargin])
        addLine(
            CGRect(x: farX, y: height - 1, width: length, height: thickness),
            [.flexibleLeftMargin, .flexibleTopMargin],
        )
        addLine(
            CGRect(x: width - 1, y: farY, width: thickness, height: length),
            [.flexibleLeftMargin, .flexibleTopMargin],
        )
        addHighlight(.top, CGRect(x: 0, y: -1, width: width, height: 2), [.flexibleWidth])
        addHighlight(.left, CGRect(x: -1, y: 0, width: 2, height: height), [.flexibleHeight])
        addHighlight(
            .right,
            CGRect(x: width - 1, y: 0, width: 2, height: height),
            [.flexibleLeftMargin, .flexibleHeight],
        )
        addHighlight(
            .bottom,
            CGRect(x: 0, y: height - 1, width: width, height: 2),
            [.flexibleTopMargin, .flexibleWidth],
        )
        for grid in [majorGridView, minorGridView] {
            grid.frame = bounds
            grid.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            grid.isHidden = true
            grid.alpha = 0
            addSubview(grid)
        }
        addHandles(width: width, height: height)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    /// Only the handles take touches; the rest goes to the photo.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        for handleView in handleViews.reversed() where handleView.point(
            inside: convert(point, to: handleView),
            with: event,
        ) {
            return handleView
        }
        return nil
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view is PhotoCropHandleView {
            return shouldBeginResizing?() ?? true
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// `handleResizeWithSender`: the frame after a handle moved by `translation`, at the locked ratio and no smaller
    /// than the handles.
    static func resizedFrame(
        _ frame: CGRect,
        handle: Handle,
        translation: CGPoint,
        aspectRatio: CGFloat,
    ) -> CGRect {
        let isLocked = aspectRatio > 0
        func withWidth(_ rect: CGRect) -> CGRect {
            var result = rect
            result.size.height = rect.size.width * aspectRatio
            return result
        }
        func withHeight(_ rect: CGRect) -> CGRect {
            var result = rect
            result.size.width = rect.size.height / aspectRatio
            return result
        }
        let byHeight = abs(translation.x) < abs(translation.y)
        var rect: CGRect
        switch handle {
        case .topLeft:
            rect = CGRect(
                x: frame.origin.x + translation.x,
                y: frame.origin.y + translation.y,
                width: frame.size.width - translation.x,
                height: frame.size.height - translation.y,
            )
            if isLocked {
                var constrained = byHeight ? withHeight(rect) : withWidth(rect)
                constrained.origin.x -= constrained.size.width - rect.size.width
                constrained.origin.y -= constrained.size.height - rect.size.height
                rect = constrained
            }
        case .topRight:
            rect = CGRect(
                x: frame.origin.x,
                y: frame.origin.y + translation.y,
                width: frame.size.width + translation.x,
                height: frame.size.height - translation.y,
            )
            if isLocked {
                var constrained = byHeight ? withHeight(rect) : withWidth(rect)
                constrained.origin.y -= constrained.size.height - rect.size.height
                rect = constrained
            }
        case .bottomLeft:
            rect = CGRect(
                x: frame.origin.x + translation.x,
                y: frame.origin.y,
                width: frame.size.width - translation.x,
                height: frame.size.height + translation.y,
            )
            if isLocked {
                var constrained = byHeight ? withHeight(rect) : withWidth(rect)
                constrained.origin.x -= constrained.size.width - rect.size.width
                rect = constrained
            }
        case .bottomRight:
            rect = CGRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width + translation.x,
                height: frame.size.height + translation.y,
            )
            if isLocked { rect = byHeight ? withHeight(rect) : withWidth(rect) }
        case .top:
            rect = CGRect(
                x: frame.origin.x,
                y: frame.origin.y + translation.y,
                width: frame.size.width,
                height: frame.size.height - translation.y,
            )
            if isLocked { rect = withHeight(rect) }
        case .left:
            rect = CGRect(
                x: frame.origin.x + translation.x,
                y: frame.origin.y,
                width: frame.size.width - translation.x,
                height: frame.size.height,
            )
            if isLocked { rect = withWidth(rect) }
        case .bottom:
            rect = CGRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height + translation.y,
            )
            if isLocked { rect = withHeight(rect) }
        case .right:
            rect = CGRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width + translation.x,
                height: frame.size.height,
            )
            if isLocked { rect = withWidth(rect) }
        }
        let minimum = minimumSide
        if rect.size.width < minimum { rect.size.width = minimum }
        if rect.size.height < minimum { rect.size.height = minimum }
        if isLocked {
            if aspectRatio > 1 {
                if rect.size.width <= minimum {
                    rect.size.width = minimum
                    rect.size.height = minimum * aspectRatio
                }
            } else if rect.size.height <= minimum {
                rect.size.height = minimum
                rect.size.width = minimum / aspectRatio
            }
        }
        return rect
    }

    private static func setGrid(_ grid: PhotoCropGridView, hidden: Bool, animated: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        grid.setNeedsDisplay()
        guard animated else {
            grid.isHidden = hidden
            grid.alpha = alpha
            return
        }
        grid.isHidden = false
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            grid.alpha = alpha
        } completion: { _ in
            if grid.alpha == alpha { grid.isHidden = hidden }
        }
    }

    func setGridMode(_ mode: PhotoCropGridMode, animated: Bool) {
        guard mode != gridMode else { return }
        gridMode = mode
        Self.setGrid(majorGridView, hidden: mode != .major, animated: animated)
        Self.setGrid(minorGridView, hidden: mode != .minor, animated: animated)
    }

    private func addLine(_ rect: CGRect, _ mask: UIView.AutoresizingMask) {
        let line = UIView(frame: rect)
        line.backgroundColor = .white
        line.isUserInteractionEnabled = false
        line.autoresizingMask = mask
        addSubview(line)
    }

    private func addHighlight(_ edge: Handle, _ rect: CGRect, _ mask: UIView.AutoresizingMask) {
        let highlight = UIView(frame: rect)
        highlight.backgroundColor = .white
        highlight.isUserInteractionEnabled = false
        highlight.autoresizingMask = mask
        highlight.isHidden = true
        addSubview(highlight)
        edgeHighlights[edge] = highlight
    }

    /// TGPhotoCropControl: 44 pt handles centered on the frame, reaching 16 pt further for touches.
    private func addHandles(width: CGFloat, height: CGFloat) {
        let side = Self.minimumSide
        let half = side / 2
        let reach: CGFloat = -16
        let handles: [(Handle, CGRect, UIView.AutoresizingMask, UIEdgeInsets)] = [
            (
                .top,
                CGRect(x: half, y: -half, width: width - side, height: side),
                [.flexibleWidth],
                UIEdgeInsets(top: reach, left: 0, bottom: reach, right: 0),
            ),
            (
                .left,
                CGRect(x: -half, y: half, width: side, height: height - side),
                [.flexibleHeight],
                UIEdgeInsets(top: 0, left: reach, bottom: 0, right: reach),
            ),
            (
                .bottom,
                CGRect(x: half, y: height - half, width: width - side, height: side),
                [.flexibleWidth, .flexibleTopMargin],
                UIEdgeInsets(top: reach, left: 0, bottom: reach, right: 0),
            ),
            (
                .right,
                CGRect(x: width - half, y: half, width: side, height: height - side),
                [.flexibleLeftMargin, .flexibleHeight],
                UIEdgeInsets(top: 0, left: reach, bottom: 0, right: reach),
            ),
            (
                .topLeft,
                CGRect(x: -half, y: -half, width: side, height: side),
                [],
                UIEdgeInsets(top: reach, left: reach, bottom: reach, right: reach),
            ),
            (
                .topRight,
                CGRect(x: width - half, y: -half, width: side, height: side),
                [.flexibleLeftMargin],
                UIEdgeInsets(top: reach, left: reach, bottom: reach, right: reach),
            ),
            (
                .bottomLeft,
                CGRect(x: -half, y: height - half, width: side, height: side),
                [.flexibleTopMargin],
                UIEdgeInsets(top: reach, left: reach, bottom: reach, right: reach),
            ),
            (
                .bottomRight,
                CGRect(x: width - half, y: height - half, width: side, height: side),
                [.flexibleLeftMargin, .flexibleTopMargin],
                UIEdgeInsets(
                    top: reach,
                    left: reach,
                    bottom: reach,
                    right: reach,
                ),
            ),
        ]
        for (handle, handleFrame, mask, insets) in handles {
            let handleView = PhotoCropHandleView(handle: handle, hitInsets: insets)
            handleView.frame = handleFrame
            handleView.autoresizingMask = mask
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.delegate = self
            handleView.addGestureRecognizer(recognizer)
            addSubview(handleView)
            handleViews.append(handleView)
        }
    }

    private func updateEdgeHighlights() {
        let isLocked = lockedAspectRatio > 0
        for (edge, highlight) in edgeHighlights {
            highlight.isHidden = !(isLocked || edge == activeEdge)
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let handleView = recognizer.view as? PhotoCropHandleView, let container = superview else { return }
        switch recognizer.state {
        case .began:
            isTracking = true
            didBeginResizing?()
            switch handleView.handle {
            case .bottom, .left, .right, .top:
                activeEdge = handleView.handle
            default:
                activeEdge = nil
            }
            updateEdgeHighlights()
        case .changed:
            let translation = recognizer.translation(in: container)
            recognizer.setTranslation(.zero, in: container)
            didResize?(handleView.handle, translation)
        case .cancelled, .ended:
            isTracking = false
            activeEdge = nil
            updateEdgeHighlights()
            didEndResizing?()
        default:
            break
        }
    }
}

// MARK: - PhotoCropHandleView

/// TGPhotoCropControl: an invisible handle with a wider touch area.
final class PhotoCropHandleView: UIView {
    // MARK: Internal

    let handle: PhotoCropAreaView.Handle

    // MARK: Private

    private let hitInsets: UIEdgeInsets

    init(handle: PhotoCropAreaView.Handle, hitInsets: UIEdgeInsets) {
        self.handle = handle
        self.hitInsets = hitInsets
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        bounds.inset(by: hitInsets).contains(point)
    }
}

// MARK: - PhotoCropGridView

/// TGPhotoCropGridView: white thirds, or light ninths at 70 percent.
final class PhotoCropGridView: UIView {
    // MARK: Private

    private let mode: PhotoCropGridMode

    init(mode: PhotoCropGridMode) {
        self.mode = mode
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    // MARK: Internal

    override func draw(_: CGRect) {
        let width = bounds.width
        let height = bounds.height
        let thickness: CGFloat = traitCollection.displayScale >= 2 ? 0.5 : 1
        for third in 0..<3 {
            let thirdOffset = CGFloat(third)
            if mode == .minor {
                UIColor(white: 0xEE / 255, alpha: 0.7).setFill()
                for ninth in 1..<4 {
                    let step = CGFloat(ninth)
                    UIRectFill(CGRect(
                        x: (width / 9 * step + width / 3 * thirdOffset).rounded(),
                        y: 0,
                        width: thickness,
                        height: height.rounded(),
                    ))
                    UIRectFill(CGRect(
                        x: 0,
                        y: (height / 9 * step + height / 3 * thirdOffset).rounded(),
                        width: width.rounded(),
                        height: thickness,
                    ))
                }
            }
            if mode == .major, third > 0 {
                UIColor.white.setFill()
                UIRectFill(CGRect(
                    x: (width / 3 * thirdOffset).rounded(),
                    y: 0,
                    width: thickness,
                    height: height.rounded(),
                ))
                UIRectFill(CGRect(
                    x: 0,
                    y: (height / 3 * thirdOffset).rounded(),
                    width: width.rounded(),
                    height: thickness,
                ))
            }
        }
    }
}

// MARK: - PhotoCropRotationView

/// TGPhotoCropRotationView: a dial of degrees under the crop that straightens the photo up to 45 degrees either way.
/// Dragging it sideways turns it, and a touch shows the fine grid.
final class PhotoCropRotationView: UIView, UIGestureRecognizerDelegate {
    // MARK: Private

    private static let wheelSide: CGFloat = 400
    private static let maximumDegrees: CGFloat = 45

    /// PhotoEditorRotationWheel: dots every 2 degrees, larger every 10 with the degrees beside them.
    private static let wheelImage: UIImage = {
        let side = wheelSide
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let canvas = context.cgContext
            let center = CGPoint(x: side / 2, y: side / 2)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.white,
            ]
            UIColor.white.setFill()
            for degrees in stride(from: -90, through: 90, by: 2) {
                let radians = CGFloat(degrees) * .pi / 180
                let isMajor = degrees % 10 == 0
                let dotRadius: CGFloat = isMajor ? 2 : 0.75
                let dot = CGPoint(x: center.x + 190 * sin(radians), y: center.y + 190 * cos(radians))
                canvas.fillEllipse(in: CGRect(
                    x: dot.x - dotRadius,
                    y: dot.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2,
                ))
                guard isMajor else { continue }
                let label = NSAttributedString(string: String(degrees), attributes: attributes)
                let labelSize = label.size()
                canvas.saveGState()
                canvas.translateBy(x: center.x + 177 * sin(radians), y: center.y + 177 * cos(radians))
                canvas.rotate(by: -radians)
                label.draw(at: CGPoint(x: -labelSize.width / 2, y: -labelSize.height / 2))
                canvas.restoreGState()
            }
        }
    }()

    /// PhotoEditorRotationNeedle.
    private static let needleImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 9)).image { _ in
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 5, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 9))
        path.addLine(to: CGPoint(x: 0, y: 9))
        path.close()
        UIColor.white.setFill()
        path.fill()
    }

    // MARK: Internal

    var shouldBeginChanging: (() -> Bool)?
    var didBeginChanging: (() -> Void)?
    var angleChanged: ((CGFloat) -> Void)?
    var didEndChanging: (() -> Void)?

    private(set) var angle: CGFloat = 0
    private(set) var isTracking = false

    private let wheelView = UIImageView(image: PhotoCropRotationView.wheelImage)
    private let needleView = UIImageView(image: PhotoCropRotationView.needleImage)
    private var beganInteraction = false
    private var endedInteraction = false
    private var isAnimating = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        wheelView.bounds = CGRect(x: 0, y: 0, width: Self.wheelSide, height: Self.wheelSide)
        wheelView.alpha = 0.9
        needleView.alpha = 0.9
        needleView.contentMode = .center
        addSubview(wheelView)
        addSubview(needleView)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.1
        press.delegate = self
        addGestureRecognizer(press)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        isAccessibilityElement = true
        accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Straighten")
        accessibilityTraits = .adjustable
        updateAccessibilityValue()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        wheelView.center = CGPoint(x: bounds.width / 2, y: -152)
        needleView.frame = CGRect(x: (bounds.width - 10) / 2, y: 47, width: 10, height: 10)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer.view === self else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        return !isAnimating && (shouldBeginChanging?() ?? true)
    }

    override func accessibilityIncrement() {
        step(by: 1)
    }

    override func accessibilityDecrement() {
        step(by: -1)
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }

    /// `setAngle:` and `resetAnimated:`: the dial alone, without reporting the change.
    func setAngle(_ newAngle: CGFloat, animated: Bool) {
        angle = newAngle
        updateAccessibilityValue()
        let transform = CGAffineTransform(rotationAngle: newAngle)
        guard animated else {
            wheelView.transform = transform
            return
        }
        isAnimating = true
        UIView.animate(springDuration: 0.45, bounce: 0.1) {
            self.wheelView.transform = transform
        } completion: { _ in
            self.isAnimating = false
        }
    }

    private func beginInteraction() {
        guard !beganInteraction else { return }
        isTracking = true
        didBeginChanging?()
        endedInteraction = false
        beganInteraction = true
    }

    private func endInteraction() {
        beganInteraction = false
        guard !endedInteraction else { return }
        isTracking = false
        didEndChanging?()
        endedInteraction = true
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            beginInteraction()
        case .cancelled, .ended:
            endInteraction()
        default:
            break
        }
    }

    /// `handlePan`: a sideways drag of π × 1.15 points turns the dial a degree.
    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            beginInteraction()
        case .changed:
            let translation = recognizer.translation(in: self).x
            recognizer.setTranslation(.zero, in: self)
            let degrees = angle * 180 / .pi
            let newDegrees = min(Self.maximumDegrees, max(-Self.maximumDegrees, degrees - translation / .pi / 1.15))
            guard abs(newDegrees - degrees) > .ulpOfOne else { return }
            setAngle(newDegrees * .pi / 180, animated: false)
            angleChanged?(angle)
        case .cancelled, .ended:
            endInteraction()
        default:
            break
        }
    }

    private func step(by degrees: CGFloat) {
        guard !isAnimating, shouldBeginChanging?() ?? true else { return }
        let current = (angle * 180 / .pi).rounded()
        let newDegrees = min(Self.maximumDegrees, max(-Self.maximumDegrees, current + degrees))
        beginInteraction()
        setAngle(newDegrees * .pi / 180, animated: false)
        angleChanged?(angle)
        endInteraction()
    }

    private func updateAccessibilityValue() {
        accessibilityValue = "\(Int((angle * 180 / .pi).rounded()))°"
    }
}
