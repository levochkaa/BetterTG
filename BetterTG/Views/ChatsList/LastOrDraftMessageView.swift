// LastOrDraftMessageView.swift

import TDLibKitDynamic
import UIKit

@MainActor enum ChatSummary {
    static func attributedText(for chat: CustomChat) -> NSAttributedString? {
        if let draft = chat.draftMessage {
            let result = NSMutableAttributedString(
                string: "Draft: ",
                attributes: [.foregroundColor: UIColor.systemRed],
            )
            if draft.replyTo != nil {
                result.append(NSAttributedString(string: "reply ", attributes: [.foregroundColor: UIColor.label]))
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
            photo.caption.text.isEmpty ? "Photo" : "Photo: \(photo.caption.text)"
        case .messageVoiceNote(let voice):
            voice.caption.text.isEmpty ? "Voice" : "Voice: \(voice.caption.text)"
        case .messageText(let text):
            text.text.text
        case .messageAnimation:
            "Animation"
        case .messageSticker:
            "Sticker"
        case .messageVideo:
            "Video"
        case .messageUnsupported:
            "TDLib not supported"
        default:
            "BTG not supported"
        }
    }
}
