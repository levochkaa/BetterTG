// MessageStatusLine.swift

import TDLibKit
import UIKit

// MARK: - MessageStatusLine

/// Telegram's date and status line of a bubble (`ChatMessageDateAndStatusNode` with
/// `stringForMessageTimestampStatus`): an eye icon with the compact view count, "edited", the author signature, the
/// time and the delivery checks, as in "1.2K edited Anna, 12:00".
struct MessageStatusLine: Equatable {
    /// The view count after the eye icon (`compactNumericCountString`), or nil when the message has no views.
    let viewCount: String?
    /// "edited", the signature, the time and the delivery symbol.
    let text: String

    init(viewCount: String? = nil, text: String) {
        self.viewCount = viewCount
        self.text = text
    }

    /// `isChannel` is true when the message belongs to a broadcast channel.
    static func make(
        _ message: Message,
        isChannel: Bool,
        time: String,
        deliverySymbol: String,
    ) -> MessageStatusLine {
        var date = time
        if let signature = authorSignature(of: message, isChannel: isChannel) {
            date = "\(signature), \(date)"
        }
        // Telegram prefixes "edited" unless the edit is hidden (`EditedMessageAttribute.isHidden`, as for a bot's
        // keyboard-only edit); TDLib reports such edits with an edit date of 0.
        if message.editDate != 0 {
            date = "\(L10n.telegram("Conversation.MessageEditedLabel")) \(date)"
        }
        // ViewCountMessageAttribute: TDLib reports views only for posts that have them.
        let views = message.interactionInfo?.viewCount ?? 0
        return MessageStatusLine(
            viewCount: views > 0 ? compactNumericCountString(views) : nil,
            text: [date, deliverySymbol].filter { !$0.isEmpty }.joined(separator: " "),
        )
    }

    /// `stringForMessageTimestampStatus`'s author title: a channel post's signature, the signature of a channel post
    /// shown in its discussion group, or that of a channel post forwarded by a user to another chat.
    private static func authorSignature(of message: Message, isChannel: Bool) -> String? {
        let signature: String
        switch message.senderId {
        case .messageSenderChat(let sender):
            if isChannel, sender.chatId == message.chatId {
                signature = message.authorSignature
            } else if case .messageOriginChannel(let origin) = message.forwardInfo?.origin,
                      origin.chatId == sender.chatId
            {
                signature = origin.authorSignature
            } else {
                return nil
            }
        case .messageSenderUser:
            // A channel that shows its authors' profiles names them above the post instead.
            guard !isChannel, case .messageOriginChannel(let origin) = message.forwardInfo?.origin else {
                return nil
            }
            signature = origin.authorSignature
        }
        return signature.isEmpty ? nil : signature
    }

    func attributedText(font: UIFont, color: UIColor) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let result = NSMutableAttributedString()
        if let viewCount {
            let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)
            if let icon = UIImage(systemName: "eye.fill", withConfiguration: configuration)?
                .withTintColor(color, renderingMode: .alwaysOriginal)
            {
                let attachment = NSTextAttachment()
                attachment.image = icon
                attachment.bounds = CGRect(
                    x: 0,
                    y: round((font.capHeight - icon.size.height) / 2),
                    width: icon.size.width,
                    height: icon.size.height,
                )
                let iconText = NSMutableAttributedString(attachment: attachment)
                // Telegram leaves 3 pt between the impression icon and the count.
                iconText.addAttributes(
                    attributes.merging([.kern: 3]) { current, _ in current },
                    range: NSRange(location: 0, length: iconText.length),
                )
                result.append(iconText)
            }
            result.append(NSAttributedString(
                string: text.isEmpty ? viewCount : viewCount + " ",
                attributes: attributes,
            ))
        }
        result.append(NSAttributedString(string: text, attributes: attributes))
        return result
    }
}

extension CustomChat {
    /// A broadcast channel, where Telegram shows view counts, signatures and the comments bar.
    var isBroadcastChannel: Bool {
        if case .chatTypeSupergroup(let type) = chat.type {
            type.isChannel
        } else {
            false
        }
    }
}
