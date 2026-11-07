// MessageForwardDelivery.swift

import TDLibKit
import UIKit

// MARK: - MessageForwardDelivery

/// The forwards Telegram sends without opening a chat: peerSelected's Saved Messages and multiplePeersSelected's
/// several chats, each with its toast. The chat's and the profile's forward pickers share them.
@MainActor enum MessageForwardDelivery {
    /// The forward goes out now, with UndoOverlayController's `.forward(savedMessages: true)` at the top, which opens
    /// Saved Messages, and a success haptic after 0.88 s.
    static func toSavedMessages(
        _ draft: PendingMessageForward,
        chat: CustomChat,
        client: TDLibClient,
        accountID: UUID,
        host: UIView,
        topInset: CGFloat,
        open: @escaping () -> Void,
        onError: @escaping (Error) -> Void,
    ) {
        let key = draft.prepared.request.messageIDs.count == 1
            ? "Conversation.ForwardTooltip.SavedMessages.One"
            : "Conversation.ForwardTooltip.SavedMessages.Many"
        TelegramUndoToast.showSavedMessagesForward(L10n.telegram(key), in: host, topInset: topInset) {
            guard TDLib.shared.activeAccountID == accountID else { return }
            open()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.88) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        Task {
            do {
                try await MessageForwardingService.send(
                    draft.prepared,
                    to: MessageForwardDestination(chatID: chat.id, topic: nil),
                    mode: draft.mode,
                    client: client,
                    accountID: accountID,
                )
            } catch {
                onError(error)
            }
        }
    }

    /// multiplePeersSelected: the comment and then the forward go to each chosen chat, and the toast names them: Saved
    /// Messages alone at the top with its link, otherwise one chat, two chats, or the first and how many others.
    static func toChats(
        _ draft: PendingMessageForward,
        chats: [CustomChat],
        comment: String,
        client: TDLibClient,
        accountID: UUID,
        host: UIView,
        topInset: CGFloat,
        openSavedMessages: @escaping (CustomChat) -> Void,
        showToast: (String) -> Void,
        onError: @escaping (Error) -> Void,
    ) {
        let many = draft.prepared.request.messageIDs.count > 1
        if chats.count == 1, let chat = chats.first, chat.isSavedMessages {
            TelegramUndoToast.showSavedMessagesForward(
                L10n.telegram(many
                    ? "Conversation.ForwardTooltip.SavedMessages.Many"
                    : "Conversation.ForwardTooltip.SavedMessages.One"),
                in: host,
                topInset: topInset,
            ) {
                guard TDLib.shared.activeAccountID == accountID else { return }
                openSavedMessages(chat)
            }
        } else {
            let names = chats.map { chat in
                (chat.isSavedMessages ? L10n.telegram("DialogList.SavedMessages") : chat.displayTitle)
                    .replacing("**", with: "")
            }
            let suffix = many ? "Many" : "One"
            let text =
                switch names.count {
                case 1: L10n.telegram("Conversation.ForwardTooltip.Chat.\(suffix)", names[0])
                case 2: L10n.telegram("Conversation.ForwardTooltip.TwoChats.\(suffix)", names[0], names[1])
                default: L10n.telegram(
                        "Conversation.ForwardTooltip.ManyChats.\(suffix)",
                        names[0],
                        "\(names.count - 1)",
                    )
                }
            showToast(text)
        }
        Task {
            var failure: Error?
            for chat in chats {
                do {
                    if !comment.isEmpty {
                        _ = try await client.send(TDNativeRequests.sendMessage(
                            chatId: chat.id,
                            topicId: nil,
                            replyTo: nil,
                            options: nil,
                            replyMarkup: nil,
                            inputMessageContent: .inputMessageText(TDNativeInputMessageText(
                                clearDraft: false,
                                linkPreviewOptions: nil,
                                text: FormattedText(entities: [], text: comment),
                            )),
                        ))
                    }
                    try await MessageForwardingService.send(
                        draft.prepared,
                        to: MessageForwardDestination(chatID: chat.id, topic: nil),
                        mode: draft.mode,
                        client: client,
                        accountID: accountID,
                    )
                } catch {
                    failure = failure ?? error
                }
            }
            if let failure { onError(failure) }
        }
    }
}
