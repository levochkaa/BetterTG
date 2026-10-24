// ChatStatusPanelView.swift

import UIKit

// MARK: - ChatStatusPanelView

/// Telegram's input panels that take the composer's place where the user can't write, 40 pt high:
/// ChatChannelSubscriberInputPanelNode in GlassControlPanelComponent's layout (a glass capsule with Join on the accent
/// fill, or Mute and Unmute, the search button on the right and a broadcast group's help on the left),
/// ChatUnblockInputPanelNode (Unblock in a glass capsule), ChatRestrictedInputPanelNode (the restriction in a glass
/// capsule) and DeleteChatInputPanelNode (a bare destructive button).
final class ChatStatusPanelView: UIView {
    struct Content: Equatable {
        enum Style: Equatable {
            case action(isAccent: Bool)
            case button
            case text
            case destructive
        }

        var title: String
        var style: Style
        var showsSearch = false
        var showsHelp = false

        var isAccent: Bool { style == .action(isAccent: true) }
    }

    #if DEBUG
        struct ProbeGeometry {
            let center: CGRect
            let label: CGRect
            let search: CGRect?
            let help: CGRect?
            let accentAlpha: CGFloat
            let hasGlass: Bool
            let title: String?
        }

        var probeGeometry: ProbeGeometry {
            ProbeGeometry(
                center: centerGlass.frame,
                label: centerLabel.frame,
                search: searchGlass.superview == nil ? nil : searchGlass.frame,
                help: helpGlass.superview == nil ? nil : helpGlass.frame,
                accentAlpha: accentFill.alpha,
                hasGlass: centerGlass.effect != nil,
                title: centerLabel.text,
            )
        }
    #endif

    static let contentHeight = CGFloat(40)

    var onAction: (() -> Void)?
    var onSearch: (() -> Void)?
    var onHelp: (() -> Void)?

    /// ChatUnblockInputPanelNode dims the title to 0.7 while the unblock is in flight.
    var isBusy = false {
        didSet {
            centerLabel.alpha = isBusy ? 0.7 : 1
            centerButton.isEnabled = !isBusy
        }
    }

    private(set) var content: Content?

    private let glassContainer = UIVisualEffectView(effect: UIGlassContainerEffect())
    private let centerGlass = ChatStatusPanelView.makeGlass()
    private let accentFill = UIView()
    private let centerLabel = UILabel()
    private let centerButton = UIControl()
    private let searchGlass = ChatStatusPanelView.makeGlass()
    private let searchButton = UIButton(type: .custom)
    private let helpGlass = ChatStatusPanelView.makeGlass()
    private let helpButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glassContainer)
        accentFill.isUserInteractionEnabled = false
        accentFill.layer.cornerCurve = .continuous
        centerGlass.contentView.addSubview(accentFill)
        centerLabel.textAlignment = .center
        centerLabel.lineBreakMode = .byTruncatingTail
        centerGlass.contentView.addSubview(centerLabel)
        centerButton.isAccessibilityElement = true
        centerButton.accessibilityTraits = .button
        centerButton.accessibilityIdentifier = "chat-status-action"
        centerButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        for event: UIControl.Event in [.touchDown, .touchDragEnter] {
            centerButton.addAction(UIAction { [weak self] _ in self?.setHighlighted(true) }, for: event)
        }
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit] {
            centerButton.addAction(UIAction { [weak self] _ in self?.setHighlighted(false) }, for: event)
        }
        centerGlass.contentView.addSubview(centerButton)

        let symbol = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        searchButton.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: symbol), for: .normal)
        searchButton.accessibilityLabel = L10n.telegram("Conversation.Search")
        searchButton.accessibilityIdentifier = "chat-status-search"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        searchGlass.contentView.addSubview(searchButton)

        helpButton.setImage(UIImage(systemName: "questionmark.circle", withConfiguration: symbol), for: .normal)
        helpButton.accessibilityIdentifier = "chat-status-help"
        helpButton.accessibilityLabel = L10n.telegram("Conversation.GigagroupDescription")
        helpButton.addAction(UIAction { [weak self] _ in self?.onHelp?() }, for: .touchUpInside)
        helpGlass.contentView.addSubview(helpButton)

        for glass in [centerGlass, searchGlass, helpGlass] {
            glass.clipsToBounds = true
            glass.layer.cornerCurve = .continuous
            glassContainer.contentView.addSubview(glass)
        }
        setSideItems(search: false, help: false)
        applyColors()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassContainer.frame = bounds
        let height = Self.contentHeight
        let side = CGSize(width: height, height: height)
        let searchFrame = CGRect(origin: CGPoint(x: bounds.width - height, y: 0), size: side)
        let helpFrame = CGRect(origin: .zero, size: side)
        place(searchGlass, frame: searchFrame)
        searchButton.frame = searchGlass.bounds
        place(helpGlass, frame: helpFrame)
        helpButton.frame = helpGlass.bounds

        let centerFrame: CGRect
        let labelFrame: CGRect
        switch content?.style ?? .action(isAccent: false) {
        case .action(let isAccent):
            // GlassControlPanelComponent: side items keep 8 pt from the centre one, whose insets even out up to 48 pt.
            let minSpacing = CGFloat(8)
            var rightInset = content?.showsSearch == true ? searchFrame.width + minSpacing : 0
            var leftInset = content?.showsHelp == true ? helpFrame.maxX + minSpacing : 0
            if leftInset <= 48, rightInset <= 48 {
                let inset = max(leftInset, rightInset)
                leftInset = inset
                rightInset = inset
            }
            let available = max(1, bounds.width - leftInset - rightInset)
            // ChatChannelSubscriberInputPanelNode: Join is at least 166 pt with 19 pt insets, Mute keeps 165 pt.
            let minWidth: CGFloat = isAccent ? 166 : 165
            let textInset: CGFloat = isAccent ? 19 : 10
            let titleWidth = ceil(centerLabel.intrinsicContentSize.width)
            let width = min(available, max(minWidth, titleWidth + textInset * 2))
            centerFrame = CGRect(x: leftInset + floor((available - width) / 2), y: 0, width: width, height: height)
            labelFrame = CGRect(origin: .zero, size: centerFrame.size).insetBy(dx: textInset, dy: 0)
        case .button:
            // ChatUnblockInputPanelNode: the title's width plus 16 pt a side.
            let titleWidth = min(bounds.width - 32, ceil(centerLabel.intrinsicContentSize.width))
            let width = titleWidth + 32
            centerFrame = CGRect(x: floor((bounds.width - width) / 2), y: 0, width: width, height: height)
            labelFrame = CGRect(origin: .zero, size: centerFrame.size).insetBy(dx: 16, dy: 0)
        case .text:
            // ChatRestrictedInputPanelNode: up to two lines 32 pt narrower than the panel, the glass 12 pt around them
            // and always 40 pt high.
            let textSize = centerLabel.sizeThatFits(CGSize(width: bounds.width - 32, height: height))
            let textWidth = min(bounds.width - 32, ceil(textSize.width))
            let width = textWidth + 24
            centerFrame = CGRect(x: floor((bounds.width - width) / 2), y: 0, width: width, height: height)
            labelFrame = CGRect(x: 12, y: 0, width: textWidth, height: height)
        case .destructive:
            // DeleteChatInputPanelNode: the title alone, centred, 10 pt narrower than the panel at most.
            let titleWidth = min(bounds.width - 10, ceil(centerLabel.intrinsicContentSize.width))
            centerFrame = CGRect(x: floor((bounds.width - titleWidth) / 2), y: 0, width: titleWidth, height: height)
            labelFrame = CGRect(origin: .zero, size: centerFrame.size)
        }
        place(centerGlass, frame: centerFrame)
        centerLabel.frame = labelFrame
        centerButton.frame = centerGlass.bounds
        // GlassBackgroundView's inner colour sits 3 pt inside the glass.
        let fillFrame = centerGlass.bounds.insetBy(dx: 3, dy: 3)
        accentFill.bounds = CGRect(origin: .zero, size: fillFrame.size)
        accentFill.center = CGPoint(x: fillFrame.midX, y: fillFrame.midY)
        accentFill.layer.cornerRadius = fillFrame.height / 2
    }

    /// Touches outside the panel's items reach the history.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self || result === glassContainer || result === glassContainer.contentView ? nil : result
    }

    private static func makeGlass() -> UIVisualEffectView {
        UIVisualEffectView(effect: makeGlassEffect())
    }

    private static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }

    /// GlassControlGroupComponent swaps a changed title by fading, and the capsule follows the new width on Telegram's
    /// 0.4 s spring; the accent fill of Join scales away when the action becomes Mute.
    func update(content: Content, animated: Bool) {
        guard content != self.content else { return }
        let previous = self.content
        self.content = content
        setSideItems(search: content.showsSearch, help: content.showsHelp)
        let animates = animated && previous != nil
        if previous?.title != content.title || previous?.style != content.style {
            if animates {
                UIView.transition(
                    with: centerLabel,
                    duration: 0.2,
                    options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
                ) { self.applyTitle() }
            } else {
                applyTitle()
            }
        }
        if (content.style == .destructive) != (centerGlass.effect == nil) {
            centerGlass.effect = content.style == .destructive ? nil : Self.makeGlassEffect()
        }
        centerButton.isUserInteractionEnabled = content.style != .text
        centerButton.accessibilityLabel = content.title
        centerButton.accessibilityTraits = content.style == .text ? .staticText : .button
        applyColors()
        guard animates else {
            accentFill.alpha = content.isAccent ? 1 : 0
            accentFill.transform = .identity
            setNeedsLayout()
            layoutIfNeeded()
            return
        }
        setNeedsLayout()
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
        ) {
            self.accentFill.alpha = content.isAccent ? 1 : 0
            self.accentFill.transform = content.isAccent ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
            self.layoutIfNeeded()
        } completion: { _ in
            if self.content?.isAccent == false { self.accentFill.transform = .identity }
        }
    }

    private func applyTitle() {
        guard let content else { return }
        centerLabel.text = content.title
        switch content.style {
        case .action:
            centerLabel.font = .systemFont(ofSize: 17, weight: .medium)
            centerLabel.numberOfLines = 1
        case .button,
             .destructive:
            centerLabel.font = .systemFont(ofSize: 17)
            centerLabel.numberOfLines = 1
        case .text:
            centerLabel.font = .systemFont(ofSize: 13)
            centerLabel.numberOfLines = 2
        }
    }

    /// The glass container keeps hidden glass in the accessibility tree, so an absent item leaves it.
    private func setSideItems(search: Bool, help: Bool) {
        for (glass, shown) in [(searchGlass, search), (helpGlass, help)] {
            if shown, glass.superview == nil {
                glassContainer.contentView.addSubview(glass)
            } else if !shown {
                glass.removeFromSuperview()
            }
        }
    }

    /// ChatUnblockInputPanelNode dims the glass content to 0.6 while pressed; the others dim the title.
    private func setHighlighted(_ highlighted: Bool) {
        let alpha: CGFloat = highlighted ? (content?.style == .button ? 0.6 : 0.5) : 1
        if highlighted {
            centerLabel.layer.removeAnimation(forKey: "opacity")
            centerLabel.alpha = alpha * (isBusy ? 0.7 : 1)
        } else {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.centerLabel.alpha = self.isBusy ? 0.7 : 1
            }
        }
    }

    private func place(_ glass: UIVisualEffectView, frame: CGRect) {
        glass.bounds = CGRect(origin: .zero, size: frame.size)
        glass.center = CGPoint(x: frame.midX, y: frame.midY)
        glass.layer.cornerRadius = frame.height / 2
    }

    private func applyColors() {
        accentFill.backgroundColor = tintColor
        centerLabel.textColor =
            switch content?.style {
            case .action(isAccent: true): .white
            case .text: .secondaryLabel
            case .destructive: .systemRed
            default: .label
            }
        searchButton.tintColor = .label
        helpButton.tintColor = .label
    }
}
