// MessageLinkMenu.swift

import SafariServices
import UIKit

// MARK: - MessageTextLink

/// A link of a message's text under a long press.
struct MessageTextLink: Equatable {
    /// The link as Telegram's `TelegramTextAttributes.URL` holds it: the address, a text link's URL, or `mailto:` and
    /// the email address.
    let url: String
    /// The link's line rects in its text view.
    let rects: [CGRect]
}

// MARK: - MessageLinkMenu

/// Telegram's menu for a link in a message (ChatControllerOpenLinkContextMenu): Open, Copy Link or Copy Email, and
/// Add to Reading List for anything but an email address. BetterTG opens web links in Safari, so the in-app browser's
/// Open in Browser and Open in App have nothing to switch to.
struct MessageLinkMenu {
    let url: String

    var isEmail: Bool { url.hasPrefix("mailto:") }

    /// The link as the menu's preview shows it.
    var previewText: String { url.replacing("mailto:", with: "") }

    /// parseUrl's display string, which Copy puts on the pasteboard: an email address without `mailto:`, and a link
    /// whose host has non-Latin letters percent-encoded.
    var copiedText: String {
        if isEmail { return String(url.dropFirst("mailto:".count)) }
        let parsed = url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://")
            ? URL(string: url)
            : URL(string: "https://" + url)
        let host = parsed?.host ?? url
        let rawHost = host.removingPercentEncoding ?? host
        let latin = CharacterSet(charactersIn: "A"..."Z")
            .union(CharacterSet(charactersIn: "a"..."z"))
            .union(CharacterSet(charactersIn: "0"..."9"))
        let punctuation = CharacterSet(charactersIn: ".-/+_?=")
        let hasNonLatin = rawHost.unicodeScalars.contains { !latin.contains($0) && !punctuation.contains($0) }
        return hasNonLatin ? url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url : url
    }

    func actions(open: @escaping () -> Void, copied: @escaping (String) -> Void) -> [TelegramContextMenuAction] {
        var actions = [
            TelegramContextMenuAction(
                title: L10n.telegram("Conversation.LinkDialogOpen"),
                image: UIImage(systemName: "globe"),
                handler: open,
            ),
            TelegramContextMenuAction(
                title: L10n
                    .telegram(isEmail ? "Conversation.ContextMenuCopyEmail" : "Conversation.ContextMenuCopyLink"),
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
                handler: { [copiedText, isEmail] in
                    UIPasteboard.general.string = copiedText
                    copied(L10n.telegram(isEmail ? "Conversation.EmailCopied" : "Conversation.LinkCopied"))
                },
            ),
        ]
        if !isEmail {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.AddToReadingList"),
                image: UIImage(systemName: "eyeglasses"),
                handler: { [url] in
                    guard let link = getUrl(from: url) else { return }
                    try? SSReadingList.default()?.addItem(with: link, title: nil, previewText: nil)
                },
            ))
        }
        return actions
    }
}

// MARK: - MessageLinkContextChipView

/// ChatMessageBubbleItemNode.contextContentNodeForLink: the link on a bubble-colored card with 10 pt corners, at
/// most two lines, that the menu lifts in place of the message.
final class MessageLinkContextChipView: TelegramContextMenuExtractableView {
    init(text: String, maximumTextWidth: CGFloat) {
        super.init(frame: .zero)
        let label = UILabel()
        label.text = text
        label.font = .body
        label.textColor = .systemBlue
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        let fitting = label.sizeThatFits(CGSize(width: maximumTextWidth, height: .greatestFiniteMagnitude))
        let textSize = CGSize(width: ceil(min(fitting.width, maximumTextWidth)), height: ceil(fitting.height))
        let insets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        bounds.size = CGSize(
            width: textSize.width + insets.left + insets.right,
            height: textSize.height + insets.top + insets.bottom,
        )
        extractedContentView.backgroundColor = .secondarySystemBackground
        extractedContentView.layer.cornerRadius = 10
        extractedContentView.clipsToBounds = true
        label.frame = CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: textSize)
        extractedContentView.addSubview(label)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MessageLinkHighlightView

/// LinkHighlightingNode: the link's rects grown by 2 pt with 4 pt corners.
final class MessageLinkHighlightView: UIView {
    init(rects: [CGRect], color: UIColor) {
        let grown = rects.map { $0.insetBy(dx: -2, dy: -2) }
        let bounds = grown.dropFirst().reduce(grown.first ?? .zero) { $0.union($1) }
        super.init(frame: bounds)
        isUserInteractionEnabled = false
        let path = UIBezierPath()
        for rect in grown {
            path.append(UIBezierPath(
                roundedRect: rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY),
                cornerRadius: 4,
            ))
        }
        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.fillColor = color.cgColor
        layer.addSublayer(shape)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
