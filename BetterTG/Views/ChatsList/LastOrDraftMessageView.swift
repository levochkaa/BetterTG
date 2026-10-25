// LastOrDraftMessageView.swift

import TDLibKit
import UIKit

@MainActor enum ChatSummary {
    /// With a type icon or a media thumbnail the text starts after their gap and names the media as Telegram does.
    static func attributedText(
        for chat: CustomChat,
        icon: ChatListMessageTypeIcon? = nil,
        previews: ChatListMediaPreviews? = nil,
        font: UIFont,
    ) -> NSAttributedString? {
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
            // Telegram's row names a voice, video or rich draft by its kind (`ChatListItem` draft content).
            let draftText =
                switch draft.content {
                case .draftMessageContentText(let text):
                    NSMutableAttributedString(getAttributedString(from: text.text))
                case .draftMessageContentVoiceNote:
                    NSMutableAttributedString(string: L10n.telegram("Message.Audio"))
                case .draftMessageContentVideoNote:
                    NSMutableAttributedString(string: L10n.telegram("Message.VideoMessage"))
                case .draftMessageContentInputRichMessage,
                     .draftMessageContentRichMessage:
                    NSMutableAttributedString(string: L10n.betterTG("Message.Rich"))
                }
            draftText.addAttribute(
                .foregroundColor,
                value: UIColor.secondaryLabel,
                range: NSRange(location: 0, length: draftText.length),
            )
            result.append(draftText)
            return result
        }
        guard let message = chat.lastMessage else { return nil }
        // ChatListItem: a person's chat shows an unseen reaction to the last message in its place.
        if case .chatTypePrivate = chat.chat.type, let reaction = message.unreadReactions.first,
           case .reactionTypeEmoji(let value) = reaction.type
        {
            return ChatListPreviewText.attributed(
                FormattedText(entities: [], text: L10n.telegram("ChatList.UserReacted", value.emoji)),
                font: font,
                color: .secondaryLabel,
            )
        }
        let result = NSMutableAttributedString()
        if icon != nil || previews != nil {
            result.append(ChatListMessageTypeIcon.gap(icon: icon, previews: previews))
        }
        let text = previews?.text
            ?? ChatListMessageTypeIcon.text(for: message)
            ?? formattedText(of: message)
            ?? ChatListMediaPreview.plain(summary(for: message))
        result.append(ChatListPreviewText.attributed(text, font: font, color: .secondaryLabel))
        return result
    }

    static func summary(for message: Message) -> String {
        MessageTextSpoilerPresentation.summary(for: message)
    }

    /// chatListItemStrings' message text with its entities: a text message's, or a file's caption alone, which
    /// Telegram shows without the file's name.
    private static func formattedText(of message: Message) -> FormattedText? {
        switch message.content {
        case .messageText(let content):
            content.text
        case .messageDocument(let content):
            content.caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : content.caption
        default:
            nil
        }
    }
}
