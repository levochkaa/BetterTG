// ForumMessageSearch.swift

import Foundation
import TDLibKit

// MARK: - ForumMessageSearch

/// Telegram's forum search lists the forum's messages below its topics (ChatListSearchListPaneNode, a `.forum`
/// location searching `.peer(forumID)`). Each found message shows in its topic's row and opens in that topic.
/// One search belongs to one client binding of the topic list; `isCurrent` gates every result.
@MainActor final class ForumMessageSearch {
    struct Result {
        let message: Message
        let topic: ForumTopic
    }

    /// Remote requests wait for typing to pause, as the chat list search does.
    private static let typingDelay = Duration.milliseconds(400)
    private static let firstPageLimit = 50
    private static let pageLimit = 80

    private(set) var results = [Result]()
    private(set) var isLoading = false
    var onChange: (() -> Void)?

    private let client: TDLibClient
    private let chatID: Int64
    private let isCurrent: () -> Bool
    private var query = ""
    private var generation = UInt64.zero
    private var task: Task<Void, Never>?
    private var nextFromMessageID = Int64.zero
    private var knownTopics = [Int: ForumTopic]()

    init(client: TDLibClient, chatID: Int64, isCurrent: @escaping () -> Bool) {
        self.client = client
        self.chatID = chatID
        self.isCurrent = isCurrent
    }

    deinit {
        task?.cancel()
    }

    /// Topics the list already read name found messages without another getForumTopic.
    func noteTopics(_ topics: [ForumTopic]) {
        for topic in topics where topic.info.chatId == chatID {
            knownTopics[topic.info.forumTopicId] = topic
        }
    }

    func update(query rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != self.query else { return }
        self.query = query
        restart()
        guard !query.isEmpty else { return }
        isLoading = true
        onChange?()
        load(fromMessageID: 0, limit: Self.firstPageLimit, waitsForTyping: true)
    }

    func loadMore() {
        guard task == nil, nextFromMessageID != 0, !query.isEmpty, isCurrent() else { return }
        isLoading = true
        onChange?()
        load(fromMessageID: nextFromMessageID, limit: Self.pageLimit, waitsForTyping: false)
    }

    func retire() {
        query = ""
        restart()
        onChange = nil
    }

    private func restart() {
        generation &+= 1
        task?.cancel()
        task = nil
        nextFromMessageID = 0
        let hadContent = !results.isEmpty || isLoading
        results = []
        isLoading = false
        if hadContent { onChange?() }
    }

    private func load(fromMessageID: Int64, limit: Int, waitsForTyping: Bool) {
        let requestGeneration = generation
        let query = query
        let client = client
        let chatID = chatID
        task = Task { [weak self] in
            if waitsForTyping { try? await Task.sleep(for: Self.typingDelay) }
            guard let self, owns(requestGeneration) else { return }
            let found = try? await client.searchChatMessages(
                chatId: chatID,
                filter: nil,
                fromMessageId: fromMessageID,
                limit: limit,
                offset: 0,
                query: query,
                senderId: nil,
                topicId: nil,
            )
            guard owns(requestGeneration) else { return }
            var added = [Result]()
            var seen = Set(results.map(\.message.id))
            for message in found?.messages ?? [] where message.chatId == chatID {
                guard seen.insert(message.id).inserted,
                      case .messageTopicForum(let reference) = message.topicId else { continue }
                let topic = await topic(id: reference.forumTopicId)
                guard owns(requestGeneration) else { return }
                if let topic { added.append(Result(message: message, topic: topic)) }
            }
            results += added
            let next = found?.nextFromMessageId ?? 0
            nextFromMessageID = found?.messages.isEmpty == false ? next : 0
            isLoading = false
            task = nil
            onChange?()
        }
    }

    /// A request of a replaced query is dropped. One the binding no longer owns also leaves no spinner, and the same
    /// query can run again once the binding is current.
    private func owns(_ requestGeneration: UInt64) -> Bool {
        guard !Task.isCancelled, requestGeneration == generation else { return false }
        guard isCurrent() else {
            query = ""
            restart()
            return false
        }
        return true
    }

    private func topic(id: Int) async -> ForumTopic? {
        if let topic = knownTopics[id] { return topic }
        guard let topic = try? await client.getForumTopic(chatId: chatID, forumTopicId: id),
              topic.info.chatId == chatID, topic.info.forumTopicId == id else { return nil }
        knownTopics[id] = topic
        return topic
    }
}

extension ForumTopic {
    /// The topic's row showing a found message: the topic's icon and name, without its unread state, pin or draft.
    func showing(foundMessage message: Message) -> ForumTopic {
        ForumTopic(
            draftMessage: nil,
            info: info,
            isPinned: false,
            lastMessage: message,
            lastReadInboxMessageId: lastReadInboxMessageId,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            notificationSettings: notificationSettings,
            order: order,
            unreadCount: 0,
            unreadMentionCount: 0,
            unreadPollVoteCount: 0,
            unreadReactionCount: 0,
        )
    }
}
