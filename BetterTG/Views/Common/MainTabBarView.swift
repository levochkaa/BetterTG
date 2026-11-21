// MainTabBarView.swift

import UIKit

// MARK: - MainTabBarView

/// Telegram 12's floating tab bar (TabBarComponent): one capsule of interactive glass whose tabs share it, with UIKit's
/// liquid lens over the selected tab. A finger lifts the lens onto the touched tab and carries it; letting go selects
/// the tab under it. Along the bottom the tabs show their names; standing in iPhone Duo's strip and in a split's list
/// pane they show only their icons, as Telegram's compact bar does.
final class MainTabBarView: UIView {
    // MARK: Internal

    struct Item: Equatable {
        let title: String
        let image: UIImage?
    }

    enum Axis {
        case horizontal
        case vertical
    }

    /// Telegram's TabBarItemsLayout, and Swiftgram's vertical bar with the system's iPhone Duo metrics.
    enum Metrics {
        /// The gap between the capsule's edge and its tabs, on every side.
        static let innerInset: CGFloat = 4
        /// A tab's length in a compact bar along the bottom, and a tab with its name across the bar.
        static let itemLength: CGFloat = 56
        /// A compact tab across the bar.
        static let compactThickness: CGFloat = 40
        /// A tab of the vertical bar, and the bar's extra end inset: the system's bar is 50n + 12 long.
        static let verticalItemLength: CGFloat = 50
        static let verticalExtraEndInset: CGFloat = 2
        /// The bar's side and bottom margins along the bottom edge (TabBarControllerNode).
        static let sideMargin: CGFloat = 20
        /// A horizontal compact bar hugging its tabs within this much of its room takes the whole room.
        static let compactFillThreshold: CGFloat = 60

        static func bottomMargin(safeBottom: CGFloat) -> CGFloat {
            safeBottom > 0 ? 20 : 8
        }
    }

    /// A finger holding the standing bar; positions are along the bar, in its coordinates.
    private struct Hold {
        let startIndex: Int
        let touchStart: CGFloat
        var touch: CGFloat
        let time: CFTimeInterval
        var lastTime: CFTimeInterval
        var press: TabBarHoldSpring
        var expand: TabBarHoldSpring
        /// The lens's centre along the bar, in the resting capsule's coordinates.
        var lens: TabBarHoldSpring
    }

    // MARK: Private

    private static let springDuration: TimeInterval = 0.4
    /// The least time the lens stays lifted after a tap, so that it crosses the bar as a lens.
    private static let liftDuration: TimeInterval = 0.3
    private static let selectionTint = UIColor.label.withAlphaComponent(0.08)

    /// A held standing bar widens after this long, or as soon as the finger moves this far.
    private static let holdExpandDelay: TimeInterval = 0.2
    private static let holdExpandDistance: CGFloat = 4
    private static let holdTitleFont = UIFont.systemFont(ofSize: 10, weight: .medium)
    /// Keeps a held title off the widened capsule's sides.
    private static let holdTitleInset: CGFloat = 6
    /// The titles fade out this fast on release, before the narrowing capsule passes them.
    private static let holdTitleFadeDuration: TimeInterval = 0.15

    var onSelect: ((Int) -> Void)?
    var onReselect: ((Int) -> Void)?
    /// A hold on one of `holdableIndices`, with the tab's view for a menu to come out of and the press to track.
    var onHold: ((Int, UIView, UIGestureRecognizer) -> Void)?
    var holdableIndices = Set<Int>()

    private(set) var axis = Axis.horizontal
    private(set) var isCompact = false
    /// Swiftgram's Show Tab Names.
    var showsTitles = true {
        didSet {
            guard showsTitles != oldValue else { return }
            rebuildItems()
            setNeedsLayout()
        }
    }

    private(set) var selectedIndex = 0

    private var items = [Item]()
    /// Where the lifted lens is drawn: it holds the capsule and does not clip.
    private let liftedContainer = UIView()
    private let glassView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        // No `cornerConfiguration`: the shape is the layer's corner radius, as in Telegram's GlassBackgroundView.
        // `.capsule()` resolves from the final bounds, so a release spring narrowing the capsule showed it square.
        return UIVisualEffectView(effect: effect)
    }()

    /// The tabs' box inside the capsule, `innerInset` from its edges.
    private let stripView = UIView()
    /// The copies the lens shows, in the accent colour, and the ones it cuts away.
    private let selectedLayer = UIView()
    private let normalLayer = UIView()
    private let restingTintView = UIView()
    private let fallbackSelection = UIView()
    private var normalViews = [MainTabBarItemView]()
    private var selectedViews = [MainTabBarItemView]()
    private var itemFrames = [CGRect]()
    private var lens: LiquidLens?
    private var isLifted = false
    private var lowering: DispatchWorkItem?
    private lazy var tabGesture = LiquidLensTabRecognizer(target: self, action: #selector(stripTouched(_:)))
    private lazy var holdGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        gesture.minimumPressDuration = ContextMenuMotion.phoneHoldDuration
        gesture.delegate = self
        return gesture
    }()

    private var hold: Hold?
    private var holdLink: CADisplayLink?
    /// The names a hold shows under the icons: over the tabs, and under the lens in the accent colour.
    private var titleLabels = [UILabel]()
    private var selectedTitleLabels = [UILabel]()

    /// The touched tab's frame and when the touch began, while a finger carries the lens.
    private var drag: (frame: CGRect, time: CFTimeInterval)?
    private var heldFrame: CGRect?
    private var heldIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCapsule()
        layoutSelection(animated: false)
    }

    /// The bar's size for `count` tabs with `availableLength` along its axis. `showsTitles` and `isWide` are
    /// Swiftgram's Show Tab Names and Wide Tab Bar.
    static func size(
        axis: Axis,
        isCompact: Bool,
        count: Int,
        availableLength: CGFloat,
        showsTitles: Bool = true,
        isWide: Bool = false,
    ) -> CGSize {
        let inset = Metrics.innerInset
        switch axis {
        case .vertical:
            let length = CGFloat(count) * Metrics.verticalItemLength + (inset + Metrics.verticalExtraEndInset) * 2
            return CGSize(width: Metrics.compactThickness + inset * 2, height: length)
        case .horizontal:
            let thickness = (isCompact || !showsTitles ? Metrics.compactThickness : Metrics.itemLength) + inset * 2
            guard isCompact else {
                if isWide { return CGSize(width: min(500, availableLength), height: thickness) }
                // TabBarComponent's 500-point cap, then Swiftgram's default narrow bar (its Wide Tab Bar setting
                // off): the room divided by 1.75, 1.5 or 1.25 for one to three tabs, less the 48-point search button's
                // room and its insets, as the bar carries no search.
                let reducer: CGFloat =
                    switch count {
                    case 1: 1.75
                    case 2: 1.5
                    case 3: 1.25
                    default: 1
                    }
                let width = min(500, availableLength) / reducer - 48 - inset * 2
                return CGSize(width: width, height: thickness)
            }
            let hugging = CGFloat(count) * Metrics.itemLength + inset * 2
            let width = availableLength - hugging < Metrics.compactFillThreshold ? availableLength : hugging
            return CGSize(width: width, height: thickness)
        }
    }

    /// The tabs' frames in the strip, `innerInset` inside a bar of `size`.
    private static func itemFrames(axis: Axis, isCompact _: Bool, count: Int, size: CGSize) -> [CGRect] {
        guard count > 0 else { return [] }
        let inset = Metrics.innerInset
        let strip = CGSize(width: max(0, size.width - inset * 2), height: max(0, size.height - inset * 2))
        switch axis {
        case .vertical:
            let extra = Metrics.verticalExtraEndInset
            return (0..<count).map {
                CGRect(
                    x: 0,
                    y: extra + CGFloat($0) * Metrics.verticalItemLength,
                    width: strip.width,
                    height: Metrics.verticalItemLength,
                )
            }
        case .horizontal:
            let length = floor(strip.width / CGFloat(count))
            return (0..<count).map {
                CGRect(x: CGFloat($0) * length, y: 0, width: length, height: strip.height)
            }
        }
    }

    private static func makeTitleLabel(_ title: String?, color: UIColor, in container: UIView) -> UILabel {
        let label = UILabel()
        label.text = title
        label.textColor = color
        label.font = holdTitleFont
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        // On iOS 27 a label's `alpha` reaches the screen only on the next layout pass, so a release left the names
        // standing through their fade; they fade by the layer's opacity instead. `alpha` is set after the opacity, or
        // the text draws clear.
        label.layer.opacity = 0
        label.alpha = 1
        label.isAccessibilityElement = false
        label.accessibilityElementsHidden = true
        label.bounds = CGRect(
            x: 0,
            y: 0,
            width: TabBarHold.expandedWidth(forItems: 3) - 2 * holdTitleInset,
            height: ceil(holdTitleFont.lineHeight),
        )
        container.addSubview(label)
        return label
    }

    func configure(items: [Item], selectedIndex: Int) {
        let changed = items != self.items
        self.items = items
        self.selectedIndex = min(max(0, selectedIndex), max(0, items.count - 1))
        if changed { rebuildItems() }
        setNeedsLayout()
    }

    func setAxis(_ axis: Axis, isCompact: Bool) {
        guard axis != self.axis || isCompact != self.isCompact else { return }
        self.axis = axis
        self.isCompact = isCompact
        for view in normalViews + selectedViews {
            view.showsTitle = !isCompact && showsTitles
        }
        setNeedsLayout()
    }

    func select(_ index: Int, animated: Bool) {
        guard items.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        updateAccessibility()
        layoutSelection(animated: animated)
    }

    /// The tab's view, for a menu that comes out of it.
    func itemView(at index: Int) -> UIView? {
        normalViews.indices.contains(index) ? normalViews[index] : nil
    }

    /// Steps the springs on real time, so a slow frame does not slow the motion down, and lays the bar out from them.
    fileprivate func stepHold() {
        guard var hold, let rest = holdRest() else {
            holdLink?.invalidate()
            holdLink = nil
            return
        }
        let now = CACurrentMediaTime()
        let time = CGFloat(min(now - hold.lastTime, 1.0 / 15.0))
        hold.lastTime = now
        if now - hold.time >= Self.holdExpandDelay { hold.expand.target = 1 }
        hold.press.advance(by: time)
        hold.expand.advance(by: time)
        let held = TabBarHold(press: hold.press.value, expand: hold.expand.value, rest: rest)
        if let first = held.itemCenters.first, let last = held.itemCenters.last {
            // The capsule's growth carries the lens with the pressed tab; from there it follows the finger.
            let start = held.itemCenters[min(hold.startIndex, held.itemCenters.count - 1)]
            hold.lens.target = held.capsuleFrame.minY + min(max(start + hold.touch - hold.touchStart, first), last)
        }
        hold.lens.advance(by: time)
        self.hold = hold
        layoutCapsule()
        layoutSelection(animated: false)
    }

    /// Lays out the capsule and its tabs: at rest, or as the hold has them (ArtWorkout's `layoutCapsule`).
    private func layoutCapsule() {
        liftedContainer.frame = bounds
        let held = heldStrip()
        glassView.frame = held?.capsuleFrame ?? bounds
        // The radius animates on the same spring as the frame.
        glassView.layer.cornerRadius = min(glassView.frame.width, glassView.frame.height) / 2
        stripView.frame = glassView.contentView.bounds
        selectedLayer.frame = stripView.bounds
        normalLayer.frame = stripView.bounds
        restingTintView.frame = selectedLayer.bounds
        let inset = Metrics.innerInset
        itemFrames = Self.itemFrames(axis: axis, isCompact: isCompact, count: items.count, size: bounds.size)
            .map { $0.offsetBy(dx: inset, dy: inset) }
        let itemScale = hold.map { 1 + (TabBarHold.liftedItemScale - 1) * $0.press.value } ?? 1
        let titleAlpha = hold.map { min(1, max(0, $0.expand.value * 2.5)) } ?? 0
        for (index, frame) in itemFrames.enumerated() where normalViews.indices.contains(index) {
            var center = CGPoint(x: frame.midX, y: frame.midY)
            var transform = CGAffineTransform.identity
            if let held, held.itemCenters.indices.contains(index) {
                center = CGPoint(x: held.capsuleFrame.width / 2, y: held.itemCenters[index])
                // The icon grows on top of the tab's scale and rises; the name keeps its place under the tab's centre,
                // so the two rise together as the system's do.
                let scale = itemScale * held.iconScale
                transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: held.iconOffset * itemScale)
            }
            for view in [normalViews[index], selectedViews[index]] {
                view.bounds = CGRect(origin: .zero, size: frame.size)
                view.center = center
                view.transform = transform
            }
            guard titleLabels.indices.contains(index), selectedTitleLabels.indices.contains(index) else { continue }
            for label in [titleLabels[index], selectedTitleLabels[index]] {
                label.center = CGPoint(x: center.x, y: center.y + TabBarHold.titleOffset * itemScale)
                label.transform = CGAffineTransform(scaleX: itemScale, y: itemScale)
                // The release's fade stays the opacity's only animation.
                if label.layer.opacity != Float(titleAlpha) { label.layer.opacity = Float(titleAlpha) }
            }
        }
    }

    /// The resting bar a hold widens; nil along the bottom, which keeps its tabs as they are.
    private func holdRest() -> TabBarHold.Rest? {
        guard axis == .vertical, let first = itemFrames.first else { return nil }
        return TabBarHold.Rest(
            size: bounds.size,
            itemCenters: itemFrames.map(\.midY),
            lensSize: lensFrame(for: first).size,
            hasAccessoryBelow: false,
        )
    }

    private func heldStrip() -> TabBarHold? {
        guard let hold, let rest = holdRest() else { return nil }
        return TabBarHold(press: hold.press.value, expand: hold.expand.value, rest: rest)
    }

    private func holdLensFrame() -> CGRect? {
        guard let hold, let held = heldStrip() else { return nil }
        return held.lensFrame(
            center: hold.lens.value - held.capsuleFrame.minY,
            liftedOutset: lens == nil ? 0 : LiquidLens.liftedOutset,
        )
    }

    private func configureViews() {
        liftedContainer.clipsToBounds = false
        addSubview(liftedContainer)
        liftedContainer.addSubview(glassView)
        glassView.contentView.addSubview(stripView)
        stripView.addSubview(selectedLayer)
        stripView.addSubview(normalLayer)
        selectedLayer.isUserInteractionEnabled = false
        selectedLayer.accessibilityElementsHidden = true
        normalLayer.isUserInteractionEnabled = false
        restingTintView.backgroundColor = Self.selectionTint
        selectedLayer.addSubview(restingTintView)
        glassView.contentView.addGestureRecognizer(tabGesture)
        glassView.contentView.addGestureRecognizer(holdGesture)

        lens = LiquidLens(liftedContainer: liftedContainer, liftedContent: selectedLayer, punchout: normalLayer)
        if lens == nil {
            selectedLayer.removeFromSuperview()
            fallbackSelection.backgroundColor = Self.selectionTint
            fallbackSelection.isUserInteractionEnabled = false
            fallbackSelection.layer.cornerCurve = .continuous
            stripView.insertSubview(fallbackSelection, belowSubview: normalLayer)
        }
        isAccessibilityElement = false
        accessibilityTraits = .tabBar
    }

    private func rebuildItems() {
        for view in normalViews + selectedViews {
            view.removeFromSuperview()
        }
        normalViews = items.map { MainTabBarItemView(item: $0, tint: .label) }
        selectedViews = items.map { MainTabBarItemView(item: $0, tint: .tintColor) }
        for view in normalViews {
            normalLayer.addSubview(view)
        }
        for view in selectedViews {
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
            selectedLayer.addSubview(view)
        }
        for view in normalViews + selectedViews {
            view.showsTitle = !isCompact && showsTitles
        }
        for label in titleLabels + selectedTitleLabels {
            label.removeFromSuperview()
        }
        titleLabels = items.map { Self.makeTitleLabel(showsTitles ? $0.title : nil, color: .label, in: normalLayer) }
        selectedTitleLabels = items.map {
            Self.makeTitleLabel(lens == nil || !showsTitles ? nil : $0.title, color: .tintColor, in: selectedLayer)
        }
        // A fallback without the lens shows the selection by colour.
        if lens == nil {
            for view in selectedViews {
                view.isHidden = true
            }
        }
        updateAccessibility()
    }

    private func updateAccessibility() {
        for (index, view) in normalViews.enumerated() {
            view.accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
            if lens == nil { view.tint = index == selectedIndex ? .tintColor : .label }
        }
    }

    /// The lens over the selected tab, or under the finger while it carries the lens. Standing, the lens is the
    /// system's 44 x 58: the tab grown by the bar's ends.
    private func selectionFrame() -> CGRect? {
        if let frame = holdLensFrame() { return frame }
        if let heldFrame { return heldFrame }
        guard itemFrames.indices.contains(selectedIndex) else { return nil }
        return lensFrame(for: itemFrames[selectedIndex])
    }

    private func lensFrame(for itemFrame: CGRect) -> CGRect {
        switch axis {
        case .vertical: itemFrame.insetBy(dx: -2, dy: -Metrics.verticalExtraEndInset - 2)
        case .horizontal: itemFrame
        }
    }

    private func layoutSelection(animated: Bool) {
        let frame = selectionFrame()
        if let lens {
            let restingAlpha: CGFloat = isLifted ? 0 : 1
            if restingTintView.alpha != restingAlpha {
                UIView.animate(withDuration: animated ? 0.2 : 0, delay: 0, options: [.beginFromCurrentState]) {
                    self.restingTintView.alpha = restingAlpha
                }
            }
            if hold != nil, !animated, let frame {
                lens.follow(frame)
            } else {
                lens.place(frame, isLifted: isLifted, springDuration: animated ? Self.springDuration : nil)
            }
            return
        }
        guard let frame else { return }
        let changes = {
            self.fallbackSelection.frame = frame
            self.fallbackSelection.layer.cornerRadius = min(frame.width, frame.height) / 2
        }
        if animated {
            UIView.animate(
                springDuration: Self.springDuration,
                bounce: 0.15,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes,
            )
        } else {
            changes()
        }
    }

    private func index(at point: CGPoint) -> Int {
        let position = axis == .horizontal ? point.x : point.y
        for (index, frame) in itemFrames.enumerated() {
            let maxPosition = axis == .horizontal ? frame.maxX : frame.maxY
            if position < maxPosition { return index }
        }
        return max(0, itemFrames.count - 1)
    }

    // MARK: Holding

    /// The standing bar held as the system's on iPhone Duo (ArtWorkout's `GlassSegmentedPicker.held`): the touch lifts
    /// the lens and grows the capsule, after 0.2 s or once the finger moves the capsule widens and shows the names,
    /// and letting go selects the tab under the lens.
    private func held(by gesture: LiquidLensTabRecognizer) {
        let position = gesture.location(in: self).y
        switch gesture.state {
        case .began:
            guard let rest = holdRest() else { return }
            let index = rest.itemCenters.indices.min {
                abs(rest.itemCenters[$0] - position) < abs(rest.itemCenters[$1] - position)
            } ?? 0
            let now = CACurrentMediaTime()
            var press = TabBarHoldSpring.press()
            press.target = 1
            let lensStart = rest.itemCenters.indices.contains(selectedIndex)
                ? rest.itemCenters[selectedIndex]
                : rest.itemCenters[index]
            hold = Hold(
                startIndex: index,
                touchStart: position,
                touch: position,
                time: now,
                lastTime: now,
                press: press,
                expand: .expand(),
                lens: .lens(at: lensStart),
            )
            // The hold drives the capsule from what is on screen; a release still running would add to it.
            for view in [glassView, stripView] + normalViews + selectedViews + titleLabels + selectedTitleLabels {
                view.layer.removeAllAnimations()
            }
            lowering?.cancel()
            lowering = nil
            isLifted = lens != nil
            layoutCapsule()
            layoutSelection(animated: true)
            startHoldLink()
        case .changed:
            guard var hold else { return }
            hold.touch = position
            if abs(position - hold.touchStart) > Self.holdExpandDistance { hold.expand.target = 1 }
            self.hold = hold
        case .ended:
            guard let hold, let rest = holdRest() else { return cancelHold() }
            let index = TabBarHold.expanded(rest)
                .itemIndex(startIndex: hold.startIndex, translation: hold.touch - hold.touchStart)
            endHold()
            isLifted = false
            if index != selectedIndex {
                UISelectionFeedbackGenerator().selectionChanged()
                selectedIndex = index
                updateAccessibility()
                layoutSelection(animated: true)
                deliverSelection(index)
            } else {
                layoutSelection(animated: true)
                onReselect?(index)
            }
        default:
            cancelHold()
        }
    }

    /// Switching the tab builds its screen on the main thread, about 150 ms the first time; the release's springs go to
    /// the render server first, or the bar stands still through that work and then jumps.
    private func deliverSelection(_ index: Int) {
        DispatchQueue.main.async { [weak self] in
            CATransaction.flush()
            self?.onSelect?(index)
        }
    }

    private func cancelHold() {
        guard hold != nil else { return }
        endHold()
        isLifted = false
        layoutSelection(animated: true)
    }

    private func startHoldLink() {
        guard holdLink == nil else { return }
        let link = CADisplayLink(
            target: MainTabBarHoldLinkTarget(bar: self),
            selector: #selector(MainTabBarHoldLinkTarget.step(_:)),
        )
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        holdLink = link
    }

    /// Lets the bar spring back to rest in Core Animation; the caller lowers and places the lens.
    private func endHold() {
        holdLink?.invalidate()
        holdLink = nil
        hold = nil
        // The names fade first, on their own curve, as the system's do; the spring below leaves their opacity alone.
        for label in titleLabels + selectedTitleLabels {
            let layer = label.layer
            let opacity = layer.presentation()?.opacity ?? layer.opacity
            layer.removeAnimation(forKey: "opacity")
            layer.opacity = 0
            guard opacity > 0 else { continue }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opacity
            fade.toValue = 0
            fade.duration = Self.holdTitleFadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "opacity")
        }
        UIView.animate(
            springDuration: Self.springDuration,
            bounce: 0,
            initialSpringVelocity: 0,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: layoutCapsule,
        )
    }

    @objc private func stripTouched(_ gesture: LiquidLensTabRecognizer) {
        guard !itemFrames.isEmpty else { return }
        if axis == .vertical { return held(by: gesture) }
        switch gesture.state {
        case .began:
            let index = index(at: gesture.location(in: stripView))
            let frame = lensFrame(for: itemFrames[index])
            drag = (frame, CACurrentMediaTime())
            heldFrame = frame
            heldIndex = index
            lift()
            layoutSelection(animated: true)
        case .changed:
            guard let drag else { return }
            let translation = gesture.translation
            var frame = drag.frame
            let inset = Metrics.innerInset
            let maxX = max(inset, stripView.bounds.width - inset - frame.width)
            frame.origin.x = min(max(frame.minX + translation.x, inset), maxX)
            heldFrame = frame
            let index = index(at: CGPoint(x: frame.midX, y: frame.midY))
            if index != heldIndex {
                UISelectionFeedbackGenerator().selectionChanged()
                heldIndex = index
            }
            layoutSelection(animated: false)
        case .ended:
            guard let drag else { return }
            let index = heldIndex
            self.drag = nil
            heldFrame = nil
            heldIndex = nil
            if let index, index != selectedIndex {
                selectedIndex = index
                updateAccessibility()
                layoutSelection(animated: true)
                deliverSelection(index)
            } else {
                layoutSelection(animated: true)
                if let index { onReselect?(index) }
            }
            lower(after: max(0, Self.liftDuration - (CACurrentMediaTime() - drag.time)))
        default:
            drag = nil
            heldFrame = nil
            heldIndex = nil
            layoutSelection(animated: true)
            lower(after: 0)
        }
    }

    /// A hold opens the tab's menu, as Settings' account switcher in Telegram, and the lens goes back to the selected
    /// tab.
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        // Standing, a hold widens the bar with the names instead, as the system's does.
        guard gesture.state == .began, axis == .horizontal else { return }
        let index = index(at: gesture.location(in: stripView))
        guard holdableIndices.contains(index), normalViews.indices.contains(index) else { return }
        tabGesture.isEnabled = false
        tabGesture.isEnabled = true
        drag = nil
        heldFrame = nil
        heldIndex = nil
        layoutSelection(animated: true)
        lower(after: 0)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onHold?(index, normalViews[index], gesture)
    }

    private func lift() {
        lowering?.cancel()
        lowering = nil
        isLifted = lens != nil
    }

    private func lower(after delay: TimeInterval) {
        lowering?.cancel()
        let lowering = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lowering = nil
            isLifted = false
            layoutSelection(animated: true)
        }
        self.lowering = lowering
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: lowering)
    }
}

// MARK: - MainTabBarHoldLinkTarget

/// Holds the bar weakly: a display link keeps its target alive until it is invalidated.
@MainActor private final class MainTabBarHoldLinkTarget: NSObject {
    private weak var bar: MainTabBarView?

    init(bar: MainTabBarView) {
        self.bar = bar
    }

    @objc func step(_ link: CADisplayLink) {
        guard let bar else {
            link.invalidate()
            return
        }
        bar.stepHold()
    }
}

// MARK: - MainTabBarView + UIGestureRecognizerDelegate

extension MainTabBarView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }
}

// MARK: - MainTabBarItemView

/// One tab: its icon, and its name under it along the bottom (TabBarComponent's ItemComponent).
private final class MainTabBarItemView: UIView {
    // MARK: Internal

    var showsTitle = true {
        didSet {
            titleLabel.isHidden = !showsTitle
            setNeedsLayout()
        }
    }

    var tint: UIColor {
        didSet { applyTint() }
    }

    // MARK: Private

    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init(item: MainTabBarView.Item, tint: UIColor) {
        self.tint = tint
        super.init(frame: .zero)
        iconView.image = item.image
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        iconView.isAccessibilityElement = false
        titleLabel.isAccessibilityElement = false
        addSubview(iconView)
        addSubview(titleLabel)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = item.title
        applyTint()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if showsTitle {
            iconView.frame = CGRect(x: 0, y: 6, width: bounds.width, height: 28)
            titleLabel.frame = CGRect(x: 2, y: 35, width: max(0, bounds.width - 4), height: 14)
        } else {
            iconView.frame = bounds
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyTint()
    }

    private func applyTint() {
        iconView.tintColor = tint
        titleLabel.textColor = tint
    }
}
