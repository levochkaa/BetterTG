// MessageShareButton.swift

import TDLibKit
import UIKit

// MARK: - MessageShareButton

/// ChatMessageShareButton: the 30 pt round button beside a bubble, sharing a channel post or, in Saved Messages,
/// going to the forwarded message's original.
final class MessageShareButton: UIControl {
    enum Kind: Equatable {
        case share
        case navigate(MessageMetadataNavigationTarget)
    }

    override var intrinsicContentSize: CGSize { CGSize(width: 30, height: 30) }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    private let iconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 15
        layer.borderColor = UIColor.separator.cgColor
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) { (self: Self, _) in
            self.updateBorder()
        }
        iconView.tintColor = .label
        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBorder()
    }

    /// ChatMessageBubbleItemNode's `needsShareButton`: an incoming broadcast post, a forward from a channel, a game or
    /// a link preview, unless its content is protected; in Saved Messages a forward that knows its source goes there
    /// instead. Sending, scheduled and service messages have none.
    static func kind(for message: CustomMessage, chat: CustomChat) -> Kind? {
        let source = message.message
        guard source.sendingState == nil, source.schedulingState == nil,
              !message.contentPresentation.isService else { return nil }
        if chat.isSavedMessages {
            guard let origin = source.forwardInfo?.source, origin.chatId != 0, origin.messageId != 0 else { return nil }
            return .navigate(.message(chatID: origin.chatId, messageID: origin.messageId, quote: nil))
        }
        guard !source.isOutgoing, source.canBeSaved else { return nil }
        if case .supergroup(let group) = chat.type, group.isChannel { return .share }
        if case .messageOriginChannel = source.forwardInfo?.origin { return .share }
        switch source.content {
        case .messageGame:
            return .share
        case .messageText(let text) where text.linkPreview != nil:
            return .share
        default:
            return nil
        }
    }

    func configure(kind: Kind) {
        let symbol: String
        switch kind {
        case .share:
            symbol = "arrowshape.turn.up.right.fill"
            accessibilityLabel = L10n.telegram("Conversation.ContextMenuForward")
        case .navigate:
            symbol = "arrow.right"
            accessibilityLabel = L10n.telegram("Conversation.ViewInChannel")
        }
        iconView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
        )
    }

    /// A hairline in the separator colour, as the scroll-to-latest button draws it.
    private func updateBorder() {
        layer.borderWidth = 1 / max(1, traitCollection.displayScale)
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}
