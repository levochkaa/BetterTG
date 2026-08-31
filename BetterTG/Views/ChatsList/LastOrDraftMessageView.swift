// LastOrDraftMessageView.swift

import TDLibKit
import UIKit

@MainActor enum ChatSummary {
    static func attributedText(for chat: CustomChat) -> NSAttributedString? {
        if let draft = chat.draftMessage {
            let result = NSMutableAttributedString(
                string: L10n.telegram("DialogList.Draft") + ": ",
                attributes: [.foregroundColor: UIColor.systemRed],
            )
            if draft.replyTo != nil {
                result.append(NSAttributedString(
                    string: L10n.telegram("Conversation.InputTextPlaceholderReply") + " ",
                    attributes: [.foregroundColor: UIColor.label],
                ))
            }
            if case .draftMessageContentText(let text) = draft.content {
                let draftText = NSMutableAttributedString(getAttributedString(from: text.text))
                draftText.addAttribute(
                    .foregroundColor,
                    value: UIColor.secondaryLabel,
                    range: NSRange(location: 0, length: draftText.length),
                )
                result.append(draftText)
            }
            return result
        }
        guard let message = chat.lastMessage else { return nil }
        let prefix = message.forwardInfo == nil ? "" : "↗︎ "
        return NSAttributedString(string: prefix + summary(for: message), attributes: [
            .foregroundColor: UIColor.secondaryLabel,
        ])
    }

    static func summary(for message: Message) -> String {
        switch message.content {
        case .messagePhoto(let photo):
            photo.caption.text.isEmpty
                ? L10n.telegram("Message.Photo")
                : "\(L10n.telegram("Message.Photo")): \(photo.caption.text)"
        case .messageVoiceNote(let voice):
            voice.caption.text.isEmpty
                ? L10n.telegram("Message.Audio")
                : "\(L10n.telegram("Message.Audio")): \(voice.caption.text)"
        case .messageText(let text):
            text.text.text
        case .messageAnimation:
            L10n.telegram("Message.Animation")
        case .messageSticker:
            L10n.telegram("Message.Sticker")
        case .messageVideo:
            L10n.telegram("Message.Video")
        case .messageUnsupported:
            L10n.betterTG("Chat.UnsupportedTDLib")
        default:
            L10n.betterTG("Chat.UnsupportedBetterTG")
        }
    }
}
