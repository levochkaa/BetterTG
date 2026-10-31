// MessageStatusLine.swift

import TDLibKit
import UIKit

// MARK: - MessageStatusLine

/// Telegram's date and status line of a bubble (`ChatMessageDateAndStatusNode` with
/// `stringForMessageTimestampStatus`): an eye icon with the compact view count, "edited", the author signature, the
/// time and the delivery checks, as in "1.2K edited Anna, 12:00".
struct MessageStatusLine: Equatable {
    /// Telegram's `outgoingCheckColor` on a dark bubble and on a light one with dark text.
    static let checkColor = UIColor { $0.userInterfaceStyle == .dark ? .white : .systemBlue }

    /// The view count after the eye icon (`compactNumericCountString`), or nil when the message has no views.
    let viewCount: String?
    /// "edited", the signature and the time.
    let text: String
    /// The checks after the time, or the clock while sending.
    var delivery = MessageDeliveryState.none
    /// ChatMessageDateAndStatusNode's replies icon with the thread's reply count, first in the line.
    var replyCount: String?
    /// The pin icon there for a pinned message without replies.
    var isPinned = false

    init(
        viewCount: String? = nil,
        text: String,
        delivery: MessageDeliveryState = .none,
        replyCount: String? = nil,
        isPinned: Bool = false,
    ) {
        self.viewCount = viewCount
        self.text = text
        self.delivery = delivery
        self.replyCount = replyCount
        self.isPinned = isPinned
    }

    /// `isChannel` is true when the message belongs to a broadcast channel. `showsThreadInfo` is
    /// ChatMessageBubbleItemNode's
    /// `.peer` chat location: a group's own history shows reply counts and pins, a thread or topic neither.
    static func make(
        _ message: Message,
        isChannel: Bool,
        isGroup: Bool = false,
        showsThreadInfo: Bool = true,
        isPinned: Bool = false,
        time: String,
        delivery: MessageDeliveryState = .none,
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
        // ReplyThreadMessageAttribute's count in a group's history (dateReplies), else the pin.
        let replies = isGroup && showsThreadInfo ? message.interactionInfo?.replyInfo?.replyCount ?? 0 : 0
        return MessageStatusLine(
            viewCount: views > 0 ? compactNumericCountString(views) : nil,
            text: delivery == .failed ? "\(date) !" : date,
            delivery: delivery,
            replyCount: replies > 0 ? compactNumericCountString(replies) : nil,
            isPinned: replies == 0 && isPinned && showsThreadInfo,
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

    /// `checkColor` is on a bubble; over media the checks take the status's own colour.
    func attributedText(font: UIFont, color: UIColor, checkColor: UIColor? = nil) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let result = NSMutableAttributedString()
        func icon(_ name: String, kern: CGFloat) -> NSAttributedString? {
            let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)
            guard let image = UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(
                x: 0,
                y: round((font.capHeight - image.size.height) / 2),
                width: image.size.width,
                height: image.size.height,
            )
            let text = NSMutableAttributedString(attachment: attachment)
            text.addAttributes(
                attributes.merging([.kern: kern]) { current, _ in current },
                range: NSRange(location: 0, length: text.length),
            )
            return text
        }
        if let replyCount {
            // Telegram leaves 3 pt after the replies icon and 4 pt after the count.
            if let replies = icon("arrowshape.turn.up.left.fill", kern: 3) { result.append(replies) }
            result.append(NSAttributedString(string: replyCount + " ", attributes: attributes))
        } else if isPinned, let pin = icon("pin.fill", kern: 4) {
            result.append(pin)
        }
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
        result.append(timeText(attributes: attributes, font: font))
        if let checks = checksAttachment(font: font, color: checkColor ?? color) { result.append(checks) }
        return result
    }

    /// The time, with Telegram's point before the checks' image.
    private func timeText(attributes: [NSAttributedString.Key: Any], font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        if checkImage(width: floor(font.pointSize)) != nil, result.length > 0 {
            result.addAttribute(
                .kern,
                value: font.pointSize / 11,
                range: NSRange(location: result.length - 1, length: 1),
            )
        }
        return result
    }

    private func checkImage(width: CGFloat) -> UIImage? {
        switch delivery {
        case .delivered: TelegramDeliveryCheck.bubbleImage(isRead: false, width: width)
        case .read: TelegramDeliveryCheck.bubbleImage(isRead: true, width: width)
        case .sending: TelegramDeliveryCheck.bubbleClockImage(width: width)
        case .failed,
             .none: nil
        }
    }

    /// ChatMessageDateAndStatusNode stands the checks 3 pt below the date's top and the clock's centre 7.5 pt.
    private func checksAttachment(font: UIFont, color: UIColor) -> NSAttributedString? {
        guard let image = checkImage(width: floor(font.pointSize)) else { return nil }
        let scale = font.pointSize / 11
        let top = delivery == .sending ? 7.5 * scale - image.size.height / 2 : 3 * scale
        let attachment = NSTextAttachment()
        attachment.image = image.withTintColor(color, renderingMode: .alwaysOriginal)
        attachment.bounds = CGRect(
            x: 0,
            y: font.ascender - top - image.size.height,
            width: image.size.width,
            height: image.size.height,
        )
        return NSAttributedString(attachment: attachment)
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
