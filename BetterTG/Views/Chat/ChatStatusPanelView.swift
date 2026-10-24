// ChatStatusPanelView.swift

import UIKit

// MARK: - ChatStatusPanelView

/// Telegram's input panels that take the composer's place where the user can't write, in the classic chrome BetterTG
/// keeps: a bar of the composer's docked glass, as high as the resting composer, with
/// ChatChannelSubscriberInputPanelNode's accent Join, Mute or Unmute (and the search button release 13 adds, with a
/// broadcast group's help opposite), ChatUnblockInputPanelNode's Unblock, ChatRestrictedInputPanelNode's restriction
/// and DeleteChatInputPanelNode's destructive Delete and Exit.
final class ChatStatusPanelView: UIView {
    struct Content: Equatable {
        enum Style: Equatable {
            /// Join spans the bar; Mute and Unmute keep their title's width.
            case action(spansWidth: Bool)
            case button
            case text
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

        var probeGeometry: ProbeGeometry {
            ProbeGeometry(
                action: actionButton.isHidden ? nil : actionButton.frame,
                text: textLabel.isHidden ? nil : textLabel.frame,
                search: searchButton.isHidden ? nil : searchButton.frame,
                help: helpButton.isHidden ? nil : helpButton.frame,
                title: content?.title,
            )
        }
    #endif

    /// The resting composer's height above the safe area (7 pt, the 36 pt row, 7 pt), as Telegram's subscriber panel
    /// matches its text input panel.
    static let contentHeight = CGFloat(50)

    private static let sideButtonWidth = CGFloat(44)

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

    private let glassView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        let view = UIVisualEffectView(effect: effect)
        view.isUserInteractionEnabled = false
        return view
    }()

    private let actionButton = UIButton(type: .system)
    private let textLabel = UILabel()
    private let searchButton = UIButton(type: .system)
    private let helpButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glassView)
        actionButton.titleLabel?.font = .systemFont(ofSize: 17)
        actionButton.titleLabel?.lineBreakMode = .byTruncatingTail
        actionButton.accessibilityIdentifier = "chat-status-action"
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        addSubview(actionButton)
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 2
        textLabel.accessibilityIdentifier = "chat-status-text"
        addSubview(textLabel)

        let symbol = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        searchButton.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: symbol), for: .normal)
        searchButton.accessibilityLabel = L10n.telegram("Conversation.Search")
        searchButton.accessibilityIdentifier = "chat-status-search"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        helpButton.setImage(UIImage(systemName: "questionmark.circle", withConfiguration: symbol), for: .normal)
        helpButton.accessibilityIdentifier = "chat-status-help"
        helpButton.accessibilityLabel = L10n.telegram("Conversation.GigagroupDescription")
        helpButton.addAction(UIAction { [weak self] _ in self?.onHelp?() }, for: .touchUpInside)
        for button in [searchButton, helpButton] {
            button.isHidden = true
            addSubview(button)
        }
        applyColors()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The composer's docked glass: its rim goes past the screen edges, only the top edge shows.
        glassView.frame = bounds.inset(by: UIEdgeInsets(top: 0, left: -16, bottom: -16, right: -16))
        let content = CGRect(
            x: safeAreaInsets.left,
            y: 0,
            width: bounds.width - safeAreaInsets.left - safeAreaInsets.right,
            height: Self.contentHeight,
        )
        let side = Self.sideButtonWidth
        searchButton.frame = CGRect(x: content.maxX - side, y: content.minY, width: side, height: content.height)
        helpButton.frame = CGRect(x: content.minX, y: content.minY, width: side, height: content.height)
        // Side items take the same room on both ends, so the title stays centred.
        let sideInset = self.content?.showsSearch == true || self.content?.showsHelp == true ? side : 0
        let available = content.insetBy(dx: sideInset, dy: 0)
        switch self.content?.style ?? .button {
        case .action(spansWidth: true):
            actionButton.frame = available
        case .action(spansWidth: false),
             .button,
             .destructive:
            // ChatChannelSubscriberInputPanelNode's Mute is its title plus 24 pt, centred.
            let font = actionButton.titleLabel?.font ?? .systemFont(ofSize: 17)
            let titleWidth = ceil(((self.content?.title ?? "") as NSString).size(withAttributes: [.font: font]).width)
            let width = min(available.width, titleWidth + 24)
            actionButton.frame = CGRect(
                x: available.minX + floor((available.width - width) / 2),
                y: available.minY,
                width: width,
                height: available.height,
            )
        case .text:
            break
        }
        // ChatRestrictedInputPanelNode: up to two lines, 16 pt in from each side.
        textLabel.frame = content.insetBy(dx: 16, dy: 0)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
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

    func update(content: Content, animated: Bool) {
        guard content != self.content else { return }
        let previous = self.content
        self.content = content
        searchButton.isHidden = !content.showsSearch
        helpButton.isHidden = !content.showsHelp
        let isText = content.style == .text
        actionButton.isHidden = isText
        textLabel.isHidden = !isText
        textLabel.text = isText ? content.title : nil
        actionButton.accessibilityLabel = content.title
        applyColors()
        let offset = Self.titleSlideOffset(from: previous, to: content)
        let snapshot = animated && offset != nil ? actionButton.snapshotView(afterScreenUpdates: false) : nil
        if !isText { actionButton.setTitle(content.title, for: .normal) }
        setNeedsLayout()
        layoutIfNeeded()
        guard let snapshot, let offset else { return }
        // ChatChannelSubscriberInputPanelNode: the old title leaves 30 pt one way while the new one arrives from the
        // other, both fading over 0.2 s.
        snapshot.center = actionButton.center
        addSubview(snapshot)
        actionButton.alpha = 0
        actionButton.transform = CGAffineTransform(translationX: 0, y: -offset)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            snapshot.alpha = 0
            snapshot.transform = CGAffineTransform(translationX: 0, y: offset)
            self.actionButton.alpha = self.isBusy ? 0.7 : 1
            self.actionButton.transform = .identity
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }

    private func applyColors() {
        let color: UIColor = content?.style == .destructive ? .systemRed : tintColor
        actionButton.setTitleColor(color, for: .normal)
        actionButton.setTitleColor(color.withAlphaComponent(0.4), for: .highlighted)
        searchButton.tintColor = tintColor
        helpButton.tintColor = tintColor
    }
}
