// StickerPeekView.swift

import TDLibKit
import UIKit

// MARK: - StickerPeekView

/// PeekControllerNode presenting StickerPreviewPeekContent (`.freeform`, menu on `.press`). The screen dims and the
/// sticker springs out of its cell to a third of the way down, its emoji above it. When the menu opens the background
/// blurs and the menu springs out 64 points under the sticker, beside it in landscape. Lifting the finger before then,
/// or tapping the background, puts the sticker back into its cell.
final class StickerPeekView: UIView {
    // MARK: Private

    private enum LayoutTransition {
        case immediate
        case spring(TimeInterval)
        case easeInOut(TimeInterval)
    }

    // MARK: Internal

    private(set) weak static var current: StickerPeekView?

    #if DEBUG
        /// The sticker peek probe's record of what the preview does.
        static var probeObserver: ((String) -> Void)?
    #endif

    private(set) var content: StickerPeekContent

    private let isDark: Bool
    private let dimView = UIView()
    private let blurView = UIVisualEffectView(effect: nil)
    private let darkDimView = UIView()
    private let containerView = UIView()
    private var contentView: StickerPeekContentView
    private var contentHasValidLayout = false
    private let menuView = StickerPeekMenuView()
    private var isMenuActivated = false
    /// The actions stack's alpha is no longer zero.
    private var isMenuShown = false
    private var isDismissing = false
    private var initialContinueGesturePoint: CGPoint?
    private var didMoveFromInitialGesturePoint = false
    private var laidOutSize = CGSize.zero
    private let tapFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    #if DEBUG
        /// The probe's view of the open preview: where the sticker and the menu are, and what the menu offers.
        var probeSummary: String {
            let titles = content.actions.map(\.title).joined(separator: ", ")
            return "sticker \(content.sticker.emoji) at \(containerView.frame.integral), "
                + "menu \(isMenuShown ? "open" : "closed") at \(menuView.frame.integral): [\(titles)]"
        }
    #endif

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(content: StickerPeekContent, isDark: Bool) {
        self.content = content
        self.isDark = isDark
        self.contentView = StickerPeekContentView(sticker: content.sticker, client: content.client)
        super.init(frame: .zero)
        accessibilityViewIsModal = true

        // PeekControllerNode's dim for `.press` activation, and its blur and context dim for the open menu.
        dimView.backgroundColor = UIColor(white: isDark ? 0 : 1, alpha: 0.5)
        dimView.isAccessibilityElement = true
        dimView.accessibilityTraits = .button
        dimView.accessibilityLabel = L10n.telegram("Common.Close")
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped(_:))))
        addSubview(dimView)
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)
        darkDimView.backgroundColor = isDark
            ? UIColor(white: 0, alpha: 0.6)
            : UIColor(rgb: 0x000A26).withAlphaComponent(0.2)
        darkDimView.alpha = 0
        darkDimView.isUserInteractionEnabled = false
        addSubview(darkDimView)

        menuView.alpha = 0
        menuView.configure(actions: content.actions)
        menuView.onPerform = { [weak self] action in self?.perform(action) }
        addSubview(menuView)

        // A freeform preview takes no touches; a tap on it closes the preview like one on the background.
        containerView.isUserInteractionEnabled = false
        containerView.addSubview(contentView)
        addSubview(containerView)

        tapFeedback.prepare()
        impactFeedback.prepare()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil,
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isDismissing, bounds.size != laidOutSize else { return }
        updateLayout()
    }

    override func accessibilityPerformEscape() -> Bool {
        dismiss()
        return true
    }

    /// Opens the preview over the window holding the source, or over the keyboard when it is up, as Telegram's
    /// global overlay covers it.
    @discardableResult static func present(_ content: StickerPeekContent) -> StickerPeekView? {
        guard let sourceWindow = content.sourceView.window else { return nil }
        current?.dismiss()
        let host = TelegramContextMenuKeyboardHost.visibleKeyboardWindow(
            for: sourceWindow,
            sourceView: content.sourceView,
        ) ?? sourceWindow
        let style = content.sourceView.traitCollection.userInterfaceStyle
        let peek = StickerPeekView(content: content, isDark: style == .dark)
        peek.overrideUserInterfaceStyle = style
        peek.frame = host.bounds
        peek.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(peek)
        current = peek
        peek.updateLayout()
        peek.animateIn(from: peek.sourceRect())
        UIAccessibility.post(notification: .screenChanged, argument: peek.contentView)
        #if DEBUG
            probeObserver?("opened \(content.sticker.emoji) (\(content.sticker.sticker.id))")
        #endif
        return peek
    }

    /// PeekControllerNode.updateContent: the finger reached another sticker. The old one shrinks away while the new
    /// one springs up from a third of its size, and the menu takes the new sticker's items.
    func updateContent(_ newContent: StickerPeekContent) {
        guard !isDismissing else { return }
        let oldView = contentView
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            oldView.stopPlayback()
            oldView.removeFromSuperview()
        }
        oldView.layer.addPeekAnimation(keyPath: "opacity", from: 1, to: 0, duration: 0.15, isRemovedOnCompletion: false)
        oldView.layer.addPeekAnimation(
            keyPath: "transform.scale",
            from: 1,
            to: 0.2,
            duration: 0.15,
            isRemovedOnCompletion: false,
        )
        CATransaction.commit()

        content = newContent
        contentView = StickerPeekContentView(sticker: newContent.sticker, client: newContent.client)
        contentHasValidLayout = false
        containerView.addSubview(contentView)
        menuView.configure(actions: newContent.actions)

        contentView.layer.addPeekAnimation(keyPath: "opacity", from: 0, to: 1, duration: 0.1)
        contentView.layer.addPeekSpring(keyPath: "transform.scale", from: 0.35, to: 1, duration: 0.5, damping: 88)
        updateLayout(.easeInOut(0.15))
        tapFeedback.selectionChanged()
        #if DEBUG
            Self.probeObserver?("moved to \(newContent.sticker.emoji) (\(newContent.sticker.sticker.id))")
        #endif
    }

    /// PeekControllerNode.activateMenu: a medium impact, the blur and the context dim, then the menu springs out of
    /// the sticker. A sticker without items keeps the plain preview.
    func activateMenu(immediately: Bool) {
        guard !isDismissing, !isMenuActivated, !content.actions.isEmpty else { return }
        isMenuActivated = true
        impactFeedback.impactOccurred()
        let blurStyle: UIBlurEffect.Style = isDark ? .dark : .light
        UIView.animate(withDuration: 0.25) { self.blurView.effect = UIBlurEffect(style: blurStyle) }
        UIView.animate(withDuration: 0.3) { self.darkDimView.alpha = 1 }
        updateLayout(.spring(0.42))
        if immediately {
            showMenu()
        } else {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(20))
                self?.showMenu()
            }
        }
        #if DEBUG
            Self.probeObserver?("menu opened for \(content.sticker.emoji)")
        #endif
    }

    /// PeekControllerNode.applyDraggingOffset: once the menu is open, a finger that has moved 12 points up or down
    /// highlights the item under it.
    func applyDraggingOffset(_ point: CGPoint) {
        let initialPoint = initialContinueGesturePoint ?? point
        if initialContinueGesturePoint == nil {
            initialContinueGesturePoint = point
        }
        guard isMenuShown else { return }
        if !didMoveFromInitialGesturePoint, abs(point.y - initialPoint.y) > 12 {
            didMoveFromInitialGesturePoint = true
        }
        if didMoveFromInitialGesturePoint {
            menuView.highlightItem(at: convert(point, to: menuView))
        }
    }

    /// PeekControllerNode.endDragging: a finger that moved performs the highlighted item; one lifted before the menu
    /// opened closes the preview; otherwise the open menu waits for a tap.
    func endDragging(at _: CGPoint) {
        if didMoveFromInitialGesturePoint {
            menuView.finishHighlight(performs: true)
        } else if !isMenuShown {
            dismiss()
        }
    }

    /// PeekControllerNode.animateOut: the sticker springs back into its cell as everything else fades.
    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        isUserInteractionEnabled = false
        if Self.current === self {
            Self.current = nil
        }
        let targetRect = sourceRect()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.finishDismissal() }
        dimView.layer.addPeekAnimation(keyPath: "opacity", from: 1, to: 0, duration: 0.2, isRemovedOnCompletion: false)
        darkDimView.layer.addPeekAnimation(
            keyPath: "opacity",
            from: darkDimView.alpha,
            to: 0,
            duration: 0.2,
            isRemovedOnCompletion: false,
        )
        let containerOffset = CGPoint(
            x: targetRect.midX - containerView.layer.position.x,
            y: targetRect.midY - containerView.layer.position.y,
        )
        containerView.layer.addPeekSpring(
            keyPath: "position",
            from: NSValue(cgPoint: .zero),
            to: NSValue(cgPoint: containerOffset),
            duration: 0.42,
            damping: 104,
            isAdditive: true,
            isRemovedOnCompletion: false,
        )
        containerView.layer.addPeekAnimation(
            keyPath: "transform.scale",
            from: 1,
            to: 0.1,
            duration: 0.25,
            isRemovedOnCompletion: false,
        )
        containerView.layer.addPeekAnimation(
            keyPath: "opacity",
            from: 1,
            to: 0,
            duration: 0.2,
            isRemovedOnCompletion: false,
        )
        if isMenuShown {
            let menuOffset = CGPoint(
                x: targetRect.midX - menuView.layer.position.x,
                y: targetRect.midY - menuView.layer.position.y,
            )
            menuView.layer.addPeekAnimation(
                keyPath: "opacity",
                from: 1,
                to: 0,
                duration: 0.2,
                isRemovedOnCompletion: false,
            )
            menuView.layer.addPeekSpring(
                keyPath: "transform.scale",
                from: 1,
                to: 0,
                duration: 0.42,
                damping: 104,
                isRemovedOnCompletion: false,
            )
            menuView.layer.addPeekSpring(
                keyPath: "position",
                from: NSValue(cgPoint: .zero),
                to: NSValue(cgPoint: menuOffset),
                duration: 0.42,
                damping: 104,
                isAdditive: true,
                isRemovedOnCompletion: false,
            )
        }
        CATransaction.commit()
        UIView.animate(withDuration: 0.25) { self.blurView.effect = nil }
        #if DEBUG
            Self.probeObserver?("closed")
        #endif
    }

    @objc private func dimTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        dismiss()
    }

    @objc private func applicationDidEnterBackground() {
        dismiss()
    }

    /// The source cell in this view's space, where the sticker comes from and returns to.
    private func sourceRect() -> CGRect {
        let sourceView = content.sourceView
        guard sourceView.window != nil else {
            return CGRect(origin: containerView.center, size: .zero)
        }
        return sourceView.convert(sourceView.bounds, to: self)
    }

    /// PeekControllerNode.containerLayoutUpdated: the sticker fits the screen less 14 points a side and 90 points of
    /// height. In portrait it sits a third of the way down with the menu 64 points under it; in landscape the menu
    /// is 32 points to its right.
    private func updateLayout(_ transition: LayoutTransition = .immediate) {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        laidOutSize = size
        for view in [dimView, blurView, darkDimView] {
            view.frame = bounds
        }
        // The preview fills its window, whose insets are current before this view's first layout pass.
        let windowInsets = window?.safeAreaInsets ?? safeAreaInsets
        var insets = windowInsets
        if insets.bottom != 0 {
            insets.bottom -= 12
        }
        let maxContainerSize = CGSize(
            width: size.width - 14 * 2,
            height: size.height - insets.top - insets.bottom - 90,
        )
        let contentSize = contentView.layoutContent(in: maxContainerSize)
        let actionsSideInset = windowInsets.left + 11
        let menuSize = menuView.preferredSize(maxWidth: size.width - actionsSideInset * 2)
        let containerFrame: CGRect
        let menuFrame: CGRect
        if size.width > size.height {
            let x = isMenuShown
                ? floor((size.width - contentSize.width) / 3)
                : floor((size.width - contentSize.width) / 2)
            containerFrame = CGRect(
                origin: CGPoint(x: x, y: floor((size.height - contentSize.height) / 2)),
                size: contentSize,
            )
            menuFrame = CGRect(
                origin: CGPoint(x: containerFrame.maxX + 32, y: floor((size.height - menuSize.height) / 2)),
                size: menuSize,
            )
        } else {
            containerFrame = CGRect(
                origin: CGPoint(
                    x: floor((size.width - contentSize.width) / 2),
                    y: floor((size.height - contentSize.height) / 3),
                ),
                size: contentSize,
            )
            menuFrame = CGRect(
                origin: CGPoint(x: floor((size.width - menuSize.width) / 2), y: containerFrame.maxY + 64),
                size: menuSize,
            )
        }
        let contentFrame = CGRect(origin: .zero, size: contentSize)
        if !contentHasValidLayout {
            contentView.frame = contentFrame
            contentHasValidLayout = true
        }
        let apply = {
            self.containerView.frame = containerFrame
            self.contentView.frame = contentFrame
            self.menuView.frame = menuFrame
        }
        switch transition {
        case .immediate:
            apply()
        case .spring(let duration):
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: apply,
            )
        case .easeInOut(let duration):
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                animations: apply,
            )
        }
    }

    /// PeekControllerNode.animateIn: the background fades in while the sticker springs from its cell, growing from a
    /// tenth of its size, with a tap.
    private func animateIn(from sourceRect: CGRect) {
        dimView.layer.addPeekAnimation(keyPath: "opacity", from: 0, to: 1, duration: 0.3)
        let offset = CGPoint(
            x: sourceRect.midX - containerView.layer.position.x,
            y: sourceRect.midY - containerView.layer.position.y,
        )
        containerView.layer.addPeekSpring(
            keyPath: "position",
            from: NSValue(cgPoint: offset),
            to: NSValue(cgPoint: .zero),
            duration: 0.4,
            damping: 110,
            isAdditive: true,
        )
        containerView.layer.addPeekSpring(keyPath: "transform.scale", from: 0.1, to: 1, duration: 0.4, damping: 110)
        containerView.layer.addPeekAnimation(keyPath: "opacity", from: 0, to: 1, duration: 0.15)
        tapFeedback.selectionChanged()
    }

    /// The menu's half of activateMenu, 0.02 s after the layout spring starts: it fades in and springs out of the
    /// sticker's centre from a tenth of its size.
    private func showMenu() {
        guard !isDismissing, !isMenuShown else { return }
        isMenuShown = true
        menuView.alpha = 1
        menuView.layer.addPeekAnimation(keyPath: "opacity", from: 0, to: 1, duration: 0.2)
        menuView.layer.addPeekSpring(keyPath: "transform.scale", from: 0.1, to: 1, duration: 0.42, damping: 104)
        let sourceCenter = containerView.layer.position
        let offset = CGPoint(
            x: sourceCenter.x - menuView.layer.position.x,
            y: sourceCenter.y - menuView.layer.position.y,
        )
        menuView.layer.addPeekSpring(
            keyPath: "position",
            from: NSValue(cgPoint: offset),
            to: NSValue(cgPoint: .zero),
            duration: 0.42,
            damping: 104,
            isAdditive: true,
        )
        UIAccessibility.post(notification: .layoutChanged, argument: menuView)
    }

    private func perform(_ action: TelegramContextMenuAction) {
        guard !isDismissing else { return }
        #if DEBUG
            Self.probeObserver?("chose \(action.title)")
        #endif
        dismiss()
        action.handler()
    }

    private func finishDismissal() {
        contentView.stopPlayback()
        removeFromSuperview()
    }
}

// MARK: - StickerPeekContentView

/// StickerPreviewPeekContentNode: the sticker fitted into a 180-point box, 120 for a custom emoji, with its emoji in
/// 32-point type 50 points above it.
private final class StickerPeekContentView: UIView {
    // MARK: Internal

    private let sticker: Sticker
    private let emojiLabel = UILabel()
    private let stickerView = CustomEmojiInlineView()

    init(sticker: Sticker, client: TDLibClient) {
        self.sticker = sticker
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        emojiLabel.font = .systemFont(ofSize: 32)
        emojiLabel.textColor = .black
        emojiLabel.textAlignment = .center
        emojiLabel.text = sticker.emoji.isEmpty ? nil : sticker.emoji
        emojiLabel.isAccessibilityElement = false
        addSubview(emojiLabel)
        addSubview(stickerView)
        stickerView.configure(sticker: sticker, client: client)
        stickerView.setPlaybackVisible(true)
        isAccessibilityElement = true
        accessibilityLabel = sticker.emoji.isEmpty
            ? L10n.telegram("Message.Sticker")
            : L10n.telegram("Message.StickerText", sticker.emoji)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// StickerPreviewPeekContentNode.updateLayout. Returns the content's size; a custom emoji's height leaves out its
    /// text, as in Telegram.
    func layoutContent(in size: CGSize) -> CGSize {
        let isCustomEmoji =
            if case .stickerFullTypeCustomEmoji = sticker.fullType {
                true
            } else {
                false
            }
        let boundingSize = isCustomEmoji
            ? CGSize(width: 120, height: 120)
            : CGSize(width: 180, height: 180).peekFitted(size)
        let dimensions = sticker.width > 0 && sticker.height > 0
            ? CGSize(width: sticker.width, height: sticker.height)
            : CGSize(width: 512, height: 512)
        var topOffset: CGFloat = 0
        var textSpacing: CGFloat = 50
        // Telegram lifts the preview on the 320- and 375-point-wide phones.
        if size.width == 292 || (size.width == 347 && size.height == 577) {
            topOffset = 60
            textSpacing -= 10
        }
        var textSize = CGSize.zero
        if emojiLabel.text != nil {
            let fitting = emojiLabel.sizeThatFits(CGSize(width: 100, height: 100))
            textSize = CGSize(width: min(ceil(fitting.width), 100), height: min(ceil(fitting.height), 100))
        }
        if textSize.height == 0 {
            topOffset = 0
            textSpacing = 0
        }
        let imageSize = dimensions.peekAspectFitted(boundingSize)
        let imageFrame = CGRect(
            origin: CGPoint(
                x: floor((boundingSize.width - imageSize.width) / 2),
                y: textSize.height + textSpacing - topOffset,
            ),
            size: imageSize,
        )
        stickerView.frame = imageFrame
        emojiLabel.frame = CGRect(
            origin: CGPoint(
                x: imageFrame.minX + floor((imageFrame.width - textSize.width) / 2),
                y: imageFrame.minY - textSize.height - textSpacing,
            ),
            size: textSize,
        )
        if isCustomEmoji || textSize.height == 0 {
            return CGSize(width: boundingSize.width, height: imageFrame.height)
        }
        return CGSize(width: boundingSize.width, height: imageFrame.height + textSize.height + textSpacing)
    }

    func stopPlayback() {
        stickerView.prepareForReuse()
    }
}

// MARK: - StickerPeekMenuView

/// ContextControllerActionsStackNode inline under the preview, drawn as BetterTG's context menu: the same glass, rows
/// and shared highlight. A finger dragged over it highlights an item, and lifting it there performs the item.
private final class StickerPeekMenuView: UIView {
    // MARK: Internal

    var onPerform: ((TelegramContextMenuAction) -> Void)?

    // MARK: Private

    private let glassView = UIVisualEffectView(effect: nil)
    private let contentView = UIView()
    private let highlightView = UIView()
    private var buttons = [TelegramContextMenuActionButton]()
    private var highlightedIndex: Int?
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let highlightFrameBehavior = ContextMenuNativeAnimation.makeBehavior(dampingRatio: 1, response: 0.12)
    private let highlightAlphaBehavior = ContextMenuNativeAnimation.makeBehavior(dampingRatio: 1, response: 0.3)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let radius = TelegramContextMenuLayout.menuCornerRadius
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        // The public interactive glass of BetterTG's menu; the private flexible material would add a pan to the
        // window while the peek's finger is still down.
        let glass = UIGlassEffect(style: .regular)
        glass.isInteractive = true
        glassView.effect = glass
        glassView.cornerConfiguration = .corners(radius: .fixed(Double(radius)))
        glassView.isUserInteractionEnabled = false
        glassView.frame = bounds
        glassView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(glassView)
        contentView.frame = bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.layer.cornerRadius = radius
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        addSubview(contentView)
        highlightView.backgroundColor = .contextMenuSelectionHighlight
        highlightView.layer.cornerCurve = .continuous
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        contentView.addSubview(highlightView)
        // ContextControllerActionsStackNode's pan selection once the finger has lifted.
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressChanged(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        addGestureRecognizer(press)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(
                x: 0,
                y: TelegramContextMenuLayout.contentVerticalInset
                    + CGFloat(index) * TelegramContextMenuLayout.actionHeight,
                width: bounds.width,
                height: TelegramContextMenuLayout.actionHeight,
            )
        }
    }

    func configure(actions: [TelegramContextMenuAction]) {
        setHighlight(nil)
        for button in buttons {
            button.removeFromSuperview()
        }
        buttons = actions.map { action in
            let button = TelegramContextMenuActionButton(action: action)
            // The menu's own recognizer tracks the finger; VoiceOver activates a row directly.
            button.isUserInteractionEnabled = false
            button.onActivate = { [weak self] in self?.onPerform?(action) }
            contentView.addSubview(button)
            return button
        }
        setNeedsLayout()
    }

    /// The width of BetterTG's context menu for these titles, 220 to 240 points.
    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let font = UIFont.systemFont(ofSize: TelegramContextMenuLayout.actionFontSize)
        let naturalWidth = buttons.reduce(CGFloat.zero) { width, button in
            let action = button.menuAction
            let titleWidth = ceil((action.title as NSString).size(withAttributes: [.font: font]).width)
            guard action.image != nil else {
                return max(width, titleWidth + TelegramContextMenuLayout.contentSideInset * 2)
            }
            return max(
                width,
                titleWidth
                    + TelegramContextMenuLayout.contentSideInset
                    + TelegramContextMenuLayout.iconSlotWidth
                    + TelegramContextMenuLayout.iconSideInset
                    + TelegramContextMenuLayout.iconSpacing,
            )
        }
        let width = min(
            max(naturalWidth, TelegramContextMenuLayout.minimumMenuWidth),
            min(TelegramContextMenuLayout.maximumMenuWidth, maxWidth),
        )
        let height = TelegramContextMenuLayout.contentVerticalInset * 2
            + CGFloat(buttons.count) * TelegramContextMenuLayout.actionHeight
        return CGSize(width: width, height: height)
    }

    /// highlightGestureMoved: the item under a point in this view, or none outside the items.
    func highlightItem(at point: CGPoint) {
        layoutIfNeeded()
        let index = bounds.contains(point)
            ? buttons.firstIndex { $0.acceptsSelection && $0.frame.contains(point) }
            : nil
        setHighlight(index)
    }

    /// highlightGestureFinished: performs the highlighted item, if any.
    func finishHighlight(performs: Bool) {
        let index = highlightedIndex
        setHighlight(nil)
        guard performs, let index, buttons.indices.contains(index) else { return }
        onPerform?(buttons[index].menuAction)
    }

    @objc private func pressChanged(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began,
             .changed:
            highlightItem(at: gesture.location(in: self))
        case .ended:
            highlightItem(at: gesture.location(in: self))
            finishHighlight(performs: true)
        default:
            setHighlight(nil)
        }
    }

    private func setHighlight(_ index: Int?) {
        guard index != highlightedIndex else { return }
        highlightedIndex = index
        let highlight = highlightView
        guard let index, buttons.indices.contains(index) else {
            ContextMenuNativeAnimation.animate(
                behavior: highlightAlphaBehavior,
                tracking: false,
                fallbackDampingRatio: 1,
                fallbackResponse: 0.3,
            ) { highlight.alpha = 0 }
            return
        }
        let rect = buttons[index].frame.insetBy(dx: TelegramContextMenuLayout.highlightInset, dy: 0)
        let radius = min(
            TelegramContextMenuLayout.menuCornerRadius - TelegramContextMenuLayout.highlightInset,
            rect.height / 2,
        )
        let place = {
            highlight.frame = rect
            highlight.layer.cornerRadius = radius
        }
        if (highlight.layer.presentation() ?? highlight.layer).opacity < 0.05 {
            UIView.performWithoutAnimation(place)
        } else {
            ContextMenuNativeAnimation.animate(
                behavior: highlightFrameBehavior,
                tracking: false,
                fallbackDampingRatio: 1,
                fallbackResponse: 0.12,
                place,
            )
        }
        ContextMenuNativeAnimation.animate(
            behavior: highlightAlphaBehavior,
            tracking: false,
            fallbackDampingRatio: 1,
            fallbackResponse: 0.3,
        ) { highlight.alpha = 1 }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }
}

// MARK: - Telegram layer animations

private extension CALayer {
    /// Telegram's `animateSpring`: a mass-5, stiffness-900 spring sped up to settle within `duration`.
    func addPeekSpring(
        keyPath: String,
        from: Any,
        to: Any,
        duration: CFTimeInterval,
        damping: CGFloat,
        isAdditive: Bool = false,
        isRemovedOnCompletion: Bool = true,
    ) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 5
        animation.stiffness = 900
        animation.damping = damping
        animation.duration = animation.settlingDuration
        animation.speed = Float(animation.duration / duration)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fromValue = from
        animation.toValue = to
        animation.isAdditive = isAdditive
        animation.isRemovedOnCompletion = isRemovedOnCompletion
        animation.fillMode = .forwards
        add(animation, forKey: isAdditive ? nil : keyPath)
    }

    /// Telegram's `animateAlpha` and `animateScale` curve.
    func addPeekAnimation(
        keyPath: String,
        from: CGFloat,
        to: CGFloat,
        duration: CFTimeInterval,
        isRemovedOnCompletion: Bool = true,
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fromValue = NSNumber(value: Float(from))
        animation.toValue = NSNumber(value: Float(to))
        animation.isRemovedOnCompletion = isRemovedOnCompletion
        animation.fillMode = .forwards
        add(animation, forKey: keyPath)
    }
}

// MARK: - CGSize

private extension CGSize {
    /// Telegram's `fitted`: scaled down to fit, never up.
    func peekFitted(_ size: CGSize) -> CGSize {
        var fitted = self
        if fitted.width > size.width {
            fitted = CGSize(width: size.width, height: floor(fitted.height * size.width / max(fitted.width, 1)))
        }
        if fitted.height > size.height {
            fitted = CGSize(width: floor(fitted.width * size.height / max(fitted.height, 1)), height: size.height)
        }
        return fitted
    }

    /// Telegram's `aspectFitted`.
    func peekAspectFitted(_ size: CGSize) -> CGSize {
        let scale = min(size.width / max(1, width), size.height / max(1, height))
        return CGSize(width: floor(width * scale), height: floor(height * scale))
    }
}
