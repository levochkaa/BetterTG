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

    // MARK: Private

    private static let springDuration: TimeInterval = 0.4
    /// The least time the lens stays lifted after a tap, so that it crosses the bar as a lens.
    private static let liftDuration: TimeInterval = 0.3
    private static let selectionTint = UIColor.label.withAlphaComponent(0.08)

    var onSelect: ((Int) -> Void)?
    var onReselect: ((Int) -> Void)?
    /// A hold on one of `holdableIndices`, with the tab's view for a menu to come out of and the press to track.
    var onHold: ((Int, UIView, UIGestureRecognizer) -> Void)?
    var holdableIndices = Set<Int>()

    private(set) var axis = Axis.horizontal
    private(set) var isCompact = false
    private(set) var selectedIndex = 0

    private var items = [Item]()
    /// Where the lifted lens is drawn: it holds the capsule and does not clip.
    private let liftedContainer = UIView()
    private let glassView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        return view
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
        liftedContainer.frame = bounds
        glassView.frame = bounds
        let inset = Metrics.innerInset
        stripView.frame = glassView.contentView.bounds.insetBy(dx: inset, dy: inset)
        selectedLayer.frame = stripView.bounds
        normalLayer.frame = stripView.bounds
        restingTintView.frame = selectedLayer.bounds
        itemFrames = Self.itemFrames(axis: axis, isCompact: isCompact, count: items.count, size: bounds.size)
        for (index, frame) in itemFrames.enumerated() where normalViews.indices.contains(index) {
            normalViews[index].frame = frame
            selectedViews[index].frame = frame
        }
        layoutSelection(animated: false)
    }

    /// The bar's size for `count` tabs with `availableLength` along its axis.
    static func size(axis: Axis, isCompact: Bool, count: Int, availableLength: CGFloat) -> CGSize {
        let inset = Metrics.innerInset
        switch axis {
        case .vertical:
            let length = CGFloat(count) * Metrics.verticalItemLength + (inset + Metrics.verticalExtraEndInset) * 2
            return CGSize(width: Metrics.compactThickness + inset * 2, height: length)
        case .horizontal:
            let thickness = (isCompact ? Metrics.compactThickness : Metrics.itemLength) + inset * 2
            guard isCompact else { return CGSize(width: availableLength, height: thickness) }
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
            view.showsTitle = !isCompact
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
            view.showsTitle = !isCompact
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
            lens.place(frame, isLifted: isLifted, springDuration: animated ? Self.springDuration : nil)
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

    @objc private func stripTouched(_ gesture: LiquidLensTabRecognizer) {
        guard !itemFrames.isEmpty else { return }
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
            if axis == .horizontal {
                let maxX = max(0, stripView.bounds.width - frame.width)
                frame.origin.x = min(max(frame.minX + translation.x, 0), maxX)
            } else {
                let minY = -Metrics.verticalExtraEndInset - 2
                let maxY = stripView.bounds.height - frame.height - minY
                frame.origin.y = min(max(frame.minY + translation.y, minY), maxY)
            }
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
                onSelect?(index)
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
        guard gesture.state == .began else { return }
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

// MARK: UIGestureRecognizerDelegate

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
