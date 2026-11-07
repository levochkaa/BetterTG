// ChatStatusPanelView.swift

import UIKit

// MARK: - ChatStatusPanelView

/// Telegram's input panels that take the composer's place where the user can't write, in its glass chrome: on the
/// bars' blur, GlassControlPanelComponent's 40 pt glass shapes. ChatChannelSubscriberInputPanelNode's Mute or Unmute
/// is a glass capsule of at least 165 pt in the middle, its Join one filled with the accent, the search a glass circle
/// at the right edge and a broadcast group's help one at the left; ChatUnblockInputPanelNode's Unblock and
/// DeleteChatInputPanelNode's destructive Delete and Exit are capsules too. ChatRestrictedInputPanelNode's restriction
/// and the secret chat's status stay text on the blur.
final class ChatStatusPanelView: UIView {
    struct Content: Equatable {
        enum Style: Equatable {
            /// Join is filled with the accent; Mute and Unmute are plain glass.
            case action(spansWidth: Bool)
            case button
            /// ChatRestrictedInputPanelNode's 13 pt secondary text.
            case text
            /// SecretChatHandshakeStatusInputPanelNode's 15 pt primary text.
            case status
            case destructive
        }

        var title: String
        var style: Style
        var showsSearch = false
        var showsHelp = false
    }

    #if DEBUG
        struct ProbeGeometry {
            let action: CGRect?
            let text: CGRect?
            let search: CGRect?
            let help: CGRect?
            let title: String?
        }

        private static func restingFrame(_ view: UIView) -> CGRect {
            CGRect(
                x: view.center.x - view.bounds.width / 2,
                y: view.center.y - view.bounds.height / 2,
                width: view.bounds.width,
                height: view.bounds.height,
            )
        }

        var probeGeometry: ProbeGeometry {
            ProbeGeometry(
                action: actionCapsule.isUserInteractionEnabled ? Self.restingFrame(actionCapsule) : nil,
                text: textLabel.isHidden ? nil : textLabel.frame,
                search: searchCircle.isUserInteractionEnabled ? Self.restingFrame(searchCircle) : nil,
                help: helpCircle.isUserInteractionEnabled ? Self.restingFrame(helpCircle) : nil,
                title: content?.title,
            )
        }
    #endif

    /// GlassControlPanelComponent's 40 pt shapes with 8 pt above and below, over the safe area.
    static let contentHeight = shapeHeight + verticalInset * 2

    private static let shapeHeight = CGFloat(40)
    private static let verticalInset = CGFloat(8)
    /// ChatChannelSubscriberInputPanelNode's 8 pt from the sides.
    private static let sideInset = CGFloat(8)
    /// GlassControlPanelComponent's least gap between the middle capsule and the side shapes.
    private static let minSpacing = CGFloat(8)
    private static let hiddenTransform = CGAffineTransform(scaleX: 0.001, y: 0.001)

    var onAction: (() -> Void)?
    var onSearch: (() -> Void)?
    var onHelp: (() -> Void)?

    /// ChatUnblockInputPanelNode dims the title to 0.7 while the unblock is in flight.
    var isBusy = false {
        didSet {
            actionButton.alpha = isBusy ? 0.7 : 1
            actionButton.isEnabled = !isBusy
        }
    }

    private(set) var content: Content?

    private let blurView = TelegramBarBackgroundView(edge: .bottom)
    private let actionCapsule = ChatStatusPanelView.makeGlass()
    private let actionButton = UIButton(type: .system)
    private let textLabel = UILabel()
    private let searchCircle = ChatStatusPanelView.makeGlass()
    private let searchButton = UIButton(type: .system)
    private let helpCircle = ChatStatusPanelView.makeGlass()
    private let helpButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(blurView)
        actionButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        actionButton.titleLabel?.lineBreakMode = .byTruncatingTail
        actionButton.accessibilityIdentifier = "chat-status-action"
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        actionCapsule.contentView.addSubview(actionButton)
        addSubview(actionCapsule)
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 2
        textLabel.accessibilityIdentifier = "chat-status-text"
        addSubview(textLabel)

        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.accessibilityLabel = L10n.telegram("Conversation.Search")
        searchButton.accessibilityIdentifier = "chat-status-search"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        helpButton.setImage(UIImage(systemName: "questionmark"), for: .normal)
        helpButton.accessibilityIdentifier = "chat-status-help"
        helpButton.accessibilityLabel = L10n.telegram("Conversation.GigagroupDescription")
        helpButton.addAction(UIAction { [weak self] _ in self?.onHelp?() }, for: .touchUpInside)
        for (circle, button) in [(searchCircle, searchButton), (helpCircle, helpButton)] {
            button.setPreferredSymbolConfiguration(UIButton.telegramGlassIconConfiguration, forImageIn: .normal)
            button.tintColor = .label
            circle.contentView.addSubview(button)
            circle.transform = Self.hiddenTransform
            circle.isUserInteractionEnabled = false
            addSubview(circle)
        }
        applyColors()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        let content = CGRect(
            x: safeAreaInsets.left + Self.sideInset,
            y: Self.verticalInset,
            width: bounds.width - safeAreaInsets.left - safeAreaInsets.right - Self.sideInset * 2,
            height: Self.shapeHeight,
        )
        let side = Self.shapeHeight
        // Bounds and centre, as the shapes may be shrunk away by a transform.
        let searchFrame = CGRect(x: content.maxX - side, y: content.minY, width: side, height: side)
        let helpFrame = CGRect(x: content.minX, y: content.minY, width: side, height: side)
        Self.place(searchCircle, in: searchFrame)
        Self.place(helpCircle, in: helpFrame)
        searchButton.frame = searchCircle.bounds
        helpButton.frame = helpCircle.bounds
        // GlassControlPanelComponent: the capsule fits between the side shapes, centred on the panel when it can.
        let leftLimit = self.content?.showsHelp == true ? helpFrame.maxX + Self.minSpacing : content.minX
        let rightLimit = self.content?.showsSearch == true ? searchFrame.minX - Self.minSpacing : content.maxX
        let isAccent = self.content?.style == .action(spansWidth: true)
        let font = actionButton.titleLabel?.font ?? .systemFont(ofSize: 17, weight: .medium)
        let titleWidth = ceil(((self.content?.title ?? "") as NSString).size(withAttributes: [.font: font]).width)
        // Join: 19 pt on each side and at least 166 pt; the others 10 pt and at least 165 pt.
        let width = min(
            rightLimit - leftLimit,
            max(isAccent ? 166 : 165, titleWidth + (isAccent ? 19 : 10) * 2),
        )
        let maxInset = max(leftLimit - content.minX, content.maxX - rightLimit)
        let centred = content.width - maxInset * 2 >= width
            ? content.minX + maxInset + floor((content.width - maxInset * 2 - width) / 2)
            : leftLimit + floor((rightLimit - leftLimit - width) / 2)
        Self.place(actionCapsule, in: CGRect(x: centred, y: content.minY, width: width, height: side))
        actionButton.frame = actionCapsule.bounds
        // ChatRestrictedInputPanelNode: up to two lines, 16 pt in from each side.
        textLabel.frame = CGRect(
            x: safeAreaInsets.left + 16,
            y: 0,
            width: bounds.width - safeAreaInsets.left - safeAreaInsets.right - 32,
            height: Self.contentHeight,
        )
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
    }

    /// Interactive glass, its content inside it, as Telegram's GlassBackgroundView with `isInteractive`.
    private static func makeGlass() -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        return view
    }

    /// Join or Mute becoming Unmute moves up; Join or Unmute becoming Mute moves down. Other changes swap at once.
    private static func titleSlideOffset(from previous: Content?, to content: Content) -> CGFloat? {
        guard let previous, previous.title != content.title,
              case .action = previous.style, case .action = content.style else { return nil }
        switch content.title {
        case L10n.telegram("Conversation.Unmute"): return -30
        case L10n.telegram("Conversation.Mute"): return 30
        default: return nil
        }
    }

    private static func place(_ view: UIView, in frame: CGRect) {
        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
    }

    func update(content: Content, animated: Bool) {
        guard content != self.content else { return }
        let previous = self.content
        self.content = content
        let isText = content.style == .text || content.style == .status
        textLabel.isHidden = !isText
        textLabel.text = isText ? content.title : nil
        textLabel.font = .systemFont(ofSize: content.style == .status ? 15 : 13)
        textLabel.textColor = content.style == .status ? .label : .secondaryLabel
        actionButton.accessibilityLabel = content.title
        applyColors()
        let offset = Self.titleSlideOffset(from: previous, to: content)
        // The old title, a real label in the glass, leaves while the new one arrives.
        let leaving: UILabel? = animated && offset != nil
            ? actionButton.titleLabel.map { label in
                let copy = UILabel()
                copy.text = label.text
                copy.font = label.font
                copy.textColor = label.textColor
                copy.sizeToFit()
                copy.center = actionButton.convert(label.center, to: actionCapsule.contentView)
                return copy
            }
            : nil
        if !isText { actionButton.setTitle(content.title, for: .normal) }
        let shapes = {
            self.setShape(self.actionCapsule, shown: !isText)
            self.setShape(self.searchCircle, shown: content.showsSearch)
            self.setShape(self.helpCircle, shown: content.showsHelp)
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        if animated, previous != nil {
            UIView.animate(
                springDuration: 0.4,
                bounce: 0,
                initialSpringVelocity: 0,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: shapes,
            )
        } else {
            UIView.performWithoutAnimation(shapes)
        }
        guard let leaving, let offset else { return }
        // ChatChannelSubscriberInputPanelNode: the old title leaves 30 pt one way while the new one arrives from the
        // other, both fading over 0.2 s.
        actionCapsule.contentView.addSubview(leaving)
        actionButton.alpha = 0
        actionButton.transform = CGAffineTransform(translationX: 0, y: -offset)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            leaving.alpha = 0
            leaving.transform = CGAffineTransform(translationX: 0, y: offset)
            self.actionButton.alpha = self.isBusy ? 0.7 : 1
            self.actionButton.transform = .identity
        } completion: { _ in
            leaving.removeFromSuperview()
        }
    }

    /// Glass grows in and shrinks away, as a glass view's opacity must not animate.
    private func setShape(_ shape: UIVisualEffectView, shown: Bool) {
        // A shrunk shape stays in place, out of reach: hiding it would cut its shrinking short.
        shape.transform = shown ? .identity : Self.hiddenTransform
        shape.isUserInteractionEnabled = shown
        shape.accessibilityElementsHidden = !shown
    }

    private func applyColors() {
        let isAccent = content?.style == .action(spansWidth: true)
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        // GlassControlGroupComponent's activeTint: the accent fills Join's glass, with white text.
        if isAccent { effect.tintColor = tintColor }
        actionCapsule.effect = effect
        let color: UIColor =
            switch content?.style {
            case .destructive: .systemRed
            case .action(spansWidth: true): .white
            default: .label
            }
        actionButton.setTitleColor(color, for: .normal)
        actionButton.setTitleColor(color.withAlphaComponent(0.4), for: .highlighted)
    }
}
