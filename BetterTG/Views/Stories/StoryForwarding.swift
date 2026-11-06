// StoryForwarding.swift

import TDLibKit
import UIKit

// MARK: - StoryForwarding

/// Telegram's story Forward (ShareController with `.story`): the chat picker, then the story sent there as an
/// inputMessageStory with Telegram's forwarded tooltip. The viewer's share button and the profile's story grid use it.
@MainActor enum StoryForwarding {
    /// The account's chat picker in a full-screen navigation; nil when the client is no longer the account's.
    static func picker(
        client: TDLibClient,
        onChosen: @escaping (CustomChat, ForumTopic?) -> Void,
    ) -> UIViewController? {
        guard let accountID = TDLib.shared.activeAccountID, TDLib.shared.activeClient.id == client.id else {
            return nil
        }
        var seen = Set<Int64>()
        let seedChats = RootVM.shared
            .allFolders
            .flatMap(\.chats)
            .map(\.chat)
            .filter { seen.insert($0.id).inserted }
        guard let picker = ForwardMessagesViewController(
            choosingChatFor: .shareStory,
            client: client,
            accountID: accountID,
            seedChats: seedChats,
        ) else { return nil }
        picker.onChosenChat = { chat, topic in
            guard TDLib.shared.activeAccountID == accountID, TDLib.shared.activeClient.id == client.id else { return }
            onChosen(chat, topic)
        }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .fullScreen
        return navigation
    }

    /// Sends the story and reports the tooltip to show, or the failure.
    static func send(
        storyChatID: Int64,
        storyID: Int,
        to chat: Chat,
        topic: ForumTopic?,
        client: TDLibClient,
        completion: @escaping (Result<String, Error>) -> Void,
    ) {
        let chatID = chat.id
        let topicID = topic
            .map { MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId)) }
        let content = TDNativeInputMessageStory(storyPosterChatId: storyChatID, storyId: storyID)
        let tooltip = chatID == TDLib.shared.activeAccount?.userID
            ? L10n.telegram("Conversation.StoryForwardTooltip.SavedMessages.One")
            : L10n.telegram("Conversation.StoryForwardTooltip.Chat.One", chat.title)
        Task { @MainActor in
            do {
                _ = try await client.send(TDNativeRequests.sendMessage(
                    chatId: chatID,
                    topicId: topicID,
                    replyTo: nil,
                    options: nil,
                    replyMarkup: nil,
                    inputMessageContent: .inputMessageStory(content),
                ))
                completion(.success(tooltip.withoutTelegramMarkup))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
