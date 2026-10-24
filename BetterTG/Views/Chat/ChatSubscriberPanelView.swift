// ChatSubscriberPanelView.swift

import UIKit

// MARK: - ChatSubscriberPanelView

/// Telegram's ChatChannelSubscriberInputPanelNode in GlassControlPanelComponent's layout: in place of the composer, a
/// 40 pt glass capsule with the subscriber's action (Join on the accent fill, or Mute and Unmute), the help button of a
/// broadcast group on the left and the search button on the right.
final class ChatSubscriberPanelView: UIView {
    struct Content: Equatable {
        var title: String
        var isAccent: Bool
        var showsHelp: Bool
    }

    #if DEBUG
        struct ProbeGeometry {
            let center: CGRect
            let search: CGRect
            let help: CGRect?
            let accentAlpha: CGFloat
            let title: String?
        }

        var probeGeometry: ProbeGeometry {
            ProbeGeometry(
                center: centerGlass.frame,
                search: searchGlass.frame,
                help: helpGlass.isHidden ? nil : helpGlass.frame,
                accentAlpha: accentFill.alpha,
                title: centerButton.title(for: .normal),
            )
        }
    #endif

    static let contentHeight = CGFloat(40)

    var onAction: (() -> Void)?
    var onSearch: (() -> Void)?
    var onHelp: (() -> Void)?

    private(set) var content: Content?

    private let glassContainer = UIVisualEffectView(effect: UIGlassContainerEffect())
    private let centerGlass = ChatSubscriberPanelView.makeGlass()
    private let accentFill = UIView()
    private let centerButton = UIButton(type: .custom)
    private let searchGlass = ChatSubscriberPanelView.makeGlass()
    private let searchButton = UIButton(type: .custom)
    private let helpGlass = ChatSubscriberPanelView.makeGlass()
    private let helpButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glassContainer)
        accentFill.isUserInteractionEnabled = false
        accentFill.layer.cornerCurve = .continuous
        centerGlass.contentView.addSubview(accentFill)
        centerButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        centerButton.titleLabel?.lineBreakMode = .byTruncatingTail
        centerButton.accessibilityIdentifier = "chat-subscriber-action"
        centerButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        centerGlass.contentView.addSubview(centerButton)

        let symbol = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        searchButton.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: symbol), for: .normal)
        searchButton.accessibilityLabel = L10n.telegram("Conversation.Search")
        searchButton.accessibilityIdentifier = "chat-subscriber-search"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        searchGlass.contentView.addSubview(searchButton)

        helpButton.setImage(UIImage(systemName: "questionmark.circle", withConfiguration: symbol), for: .normal)
        helpButton.accessibilityIdentifier = "chat-subscriber-help"
        helpButton.accessibilityLabel = L10n.telegram("Conversation.GigagroupDescription")
        helpButton.addAction(UIAction { [weak self] _ in self?.onHelp?() }, for: .touchUpInside)
        helpGlass.contentView.addSubview(helpButton)

        for glass in [centerGlass, searchGlass, helpGlass] {
            glass.clipsToBounds = true
            glass.layer.cornerCurve = .continuous
            glassContainer.contentView.addSubview(glass)
        }
        setHelpHidden(true)
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

        // GlassControlPanelComponent: side items keep 8 pt from the centre one, whose insets even out up to 48 pt.
        let minSpacing = CGFloat(8)
        var rightInset = searchFrame.width + minSpacing
        var leftInset = content?.showsHelp == true ? helpFrame.maxX + minSpacing : 0
        if leftInset <= 48, rightInset <= 48 {
            let inset = max(leftInset, rightInset)
            leftInset = inset
            rightInset = inset
        }
        let available = max(1, bounds.width - leftInset - rightInset)
        let isAccent = content?.isAccent == true
        // ChatChannelSubscriberInputPanelNode: Join is at least 166 pt with 19 pt insets, Mute keeps wide at 165 pt.
        let minWidth: CGFloat = isAccent ? 166 : 165
        let textInset: CGFloat = isAccent ? 19 : 10
        let titleWidth = ceil(centerButton.titleLabel?.intrinsicContentSize.width ?? 0)
        let width = min(available, max(minWidth, titleWidth + textInset * 2))
        let centerFrame = CGRect(
            x: leftInset + floor((available - width) / 2),
            y: 0,
            width: width,
            height: height,
        )
        place(centerGlass, frame: centerFrame)
        centerButton.frame = centerGlass.bounds.insetBy(dx: textInset, dy: 0)
        // GlassBackgroundView's inner colour sits 3 pt inside the glass.
        let fillFrame = centerGlass.bounds.insetBy(dx: 3, dy: 3)
        accentFill.bounds = CGRect(origin: .zero, size: fillFrame.size)
        accentFill.center = CGPoint(x: fillFrame.midX, y: fillFrame.midY)
        accentFill.layer.cornerRadius = fillFrame.height / 2
    }

    /// GlassControlPanelComponent passes touches outside its items to the history.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self || result === glassContainer || result === glassContainer.contentView ? nil : result
    }

    private static func makeGlass() -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return UIVisualEffectView(effect: effect)
    }

    /// GlassControlGroupComponent swaps a changed title by fading, and the capsule follows the new width on Telegram's
    /// 0.4 s spring; the accent fill of Join scales away when the action becomes Mute.
    func update(content: Content, animated: Bool) {
        guard content != self.content else { return }
        let previous = self.content
        self.content = content
        setHelpHidden(!content.showsHelp)
        let titleChanged = previous?.title != content.title
        if titleChanged {
            if animated, previous != nil {
                UIView.transition(
                    with: centerButton,
                    duration: 0.2,
                    options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
                ) { self.centerButton.setTitle(content.title, for: .normal) }
            } else {
                centerButton.setTitle(content.title, for: .normal)
            }
        }
        centerButton.accessibilityLabel = content.title
        applyColors()
        guard animated, previous != nil else {
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

    /// The glass container keeps hidden glass in the accessibility tree, so the button goes too.
    private func setHelpHidden(_ hidden: Bool) {
        helpGlass.isHidden = hidden
        helpButton.isHidden = hidden
    }

    private func place(_ glass: UIVisualEffectView, frame: CGRect) {
        glass.bounds = CGRect(origin: .zero, size: frame.size)
        glass.center = CGPoint(x: frame.midX, y: frame.midY)
        glass.layer.cornerRadius = frame.height / 2
    }

    private func applyColors() {
        let isAccent = content?.isAccent == true
        accentFill.backgroundColor = tintColor
        centerButton.setTitleColor(isAccent ? .white : .label, for: .normal)
        centerButton.setTitleColor((isAccent ? UIColor.white : .label).withAlphaComponent(0.5), for: .highlighted)
        searchButton.tintColor = .label
        helpButton.tintColor = .label
    }
}
