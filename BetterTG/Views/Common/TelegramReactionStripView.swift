// TelegramReactionStripView.swift

import TDLibKit
import UIKit

// MARK: - TelegramContextMenuReaction

struct TelegramContextMenuReaction {
    let type: ReactionType
    let isChosen: Bool
    let sticker: Sticker?
    /// The client that resolved `sticker`; its file ids belong to that client's account.
    let client: TDLibClient
    let handler: () -> Void
}

typealias TelegramContextReactionsProvider = @MainActor () async -> [TelegramContextMenuReaction]

// MARK: - TelegramReactionStripView

/// The collapsed reaction row from Telegram's ReactionContextNode: 46-point
/// cloud, 36-point items, 8-point spacing. The user's recent items come first.
final class TelegramReactionStripView: UIView {
    private static let rowHeight = CGFloat(46)
    private static let titleHeight = CGFloat(22)

    var onSelect: ((TelegramContextMenuReaction) -> Void)?

    /// ReactionContextNode's title: a line above the reactions, such as the story viewer's Send Reaction as a
    /// Private Message.
    var title: String? {
        didSet {
            titleLabel.text = title
            titleLabel.isHidden = title == nil
            setNeedsLayout()
        }
    }

    private let effect = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private var buttons = [TelegramReactionStripButton]()
    private weak var trackedButton: TelegramReactionStripButton?

    var preferredWidth: CGFloat {
        let rowWidth = buttons.isEmpty ? 180 : min(320, CGFloat(buttons.count) * 44 + 4)
        guard title != nil else { return rowWidth }
        return min(320, max(rowWidth, ceil(titleLabel.intrinsicContentSize.width) + 32))
    }

    var preferredHeight: CGFloat {
        title == nil ? Self.rowHeight : Self.rowHeight + Self.titleHeight
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        effect.clipsToBounds = true
        effect.layer.cornerRadius = 23
        effect.isUserInteractionEnabled = true
        addSubview(effect)
        effect.contentView.addSubview(scroll)
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        effect.contentView.addSubview(spinner)
        spinner.startAnimating()
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.isHidden = true
        effect.contentView.addSubview(titleLabel)
        accessibilityIdentifier = "message-context-reactions"
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        effect.frame = bounds
        let top = title == nil ? 0 : Self.titleHeight
        titleLabel.frame = CGRect(x: 12, y: 8, width: max(0, bounds.width - 24), height: 16)
        scroll.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        spinner.center = CGPoint(x: scroll.frame.midX, y: scroll.frame.midY)
    }

    func configure(_ reactions: [TelegramContextMenuReaction]) {
        prepareForReuse()
        spinner.setLoading(false)
        for reaction in reactions {
            let button = TelegramReactionStripButton(reaction: reaction)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let button else { return }
                self?.onSelect?(button.reaction)
            }, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    func prepareForReuse() {
        trackedButton = nil
        for button in buttons {
            button.prepareForReuse()
            button.removeFromSuperview()
        }
        buttons.removeAll()
    }

    func updateTracking(at point: CGPoint?) {
        let button = point.flatMap { point in
            bounds.contains(point) ? buttons.first { $0.convert($0.bounds, to: self).contains(point) } : nil
        }
        guard trackedButton !== button else { return }
        trackedButton?.isHighlighted = false
        trackedButton = button
        button?.isHighlighted = true
        if button != nil { UISelectionFeedbackGenerator().selectionChanged() }
    }

    @discardableResult func selectTrackedReaction() -> Bool {
        guard let button = trackedButton else { return false }
        onSelect?(button.reaction)
        return true
    }
}

// MARK: - TelegramReactionStripButton

private final class TelegramReactionStripButton: UIControl {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 1.22, y: 1.22) : .identity
            }
        }
    }

    let reaction: TelegramContextMenuReaction

    private let emoji = UILabel()
    private var animation: CustomEmojiInlineView?

    init(reaction: TelegramContextMenuReaction) {
        self.reaction = reaction
        super.init(frame: .zero)
        layer.cornerRadius = 18
        backgroundColor = reaction.isChosen ? UIColor.systemBlue.withAlphaComponent(0.2) : .clear
        emoji.text = reaction.type.standardEmoji ?? reaction.sticker?.emoji ?? "◇"
        emoji.font = .systemFont(ofSize: 28)
        emoji.textAlignment = .center
        emoji.isUserInteractionEnabled = false
        addSubview(emoji)
        if let sticker = reaction.sticker {
            let animation = CustomEmojiInlineView()
            animation.energySaving = EnergySavingRole(item: .loopEmoji, whenOff: .still)
            // ReactionContextNode's `.primary` tint mode for a template reaction.
            animation.templateColor = .label
            animation.isUserInteractionEnabled = false
            animation.onFirstFrameReady = { [weak self] in self?.emoji.isHidden = true }
            animation.configure(sticker: sticker, client: reaction.client)
            addSubview(animation)
            self.animation = animation
        }
        isAccessibilityElement = true
        accessibilityLabel = reaction.type.standardEmoji ?? reaction.sticker?.emoji ?? reaction.type.accessibilityName
        accessibilityIdentifier = "context-reaction-\(reaction.type.accessibilityIdentifierComponent)"
        accessibilityTraits = reaction.isChosen ? [.button, .selected] : .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        emoji.frame = bounds
        animation?.frame = bounds.insetBy(dx: 2, dy: 2)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        animation?.setPlaybackVisible(window != nil)
    }

    func prepareForReuse() { animation?.prepareForReuse() }
}
