// ChatMessageSearch.swift

import Foundation
import TDLibKit

// MARK: - ChatMessageSearch

/// Telegram's in-chat search results (ChatSearchResultsState): the found messages of one chat location, newest first,
/// the current one and the pages still to load. The chat starts on the newest result and steps with the panel's arrows
/// (ChatControllerLoadDisplayNode.navigateMessageSearch). `isCurrent` gates every request and result.
@MainActor final class ChatMessageSearch {
    private static let typingDelay = Duration.milliseconds(250)
    private static let pageLimit = 50
    /// Pages whose messages all belong to another topic are skipped, up to this many in a row.
    private static let maximumSkippedPages = 4

    /// Called with a found message the chat should show.
    var onNavigate: ((Int64) -> Void)?
    var onChange: (() -> Void)?

    private(set) var query = ""
    private(set) var sender: MessageSender?
    /// Newest first.
    private(set) var messageIDs = [Int64]()
    private(set) var currentIndex: Int?
    private(set) var isLoading = false

    private let client: TDLibClient
    private let location: ChatLocation
    private let isCurrent: () -> Bool
    private var totalCount = 0
    private var nextFromMessageID = Int64.zero
    private var generation = UInt64.zero
    private var task: Task<Void, Never>?

    var isActive: Bool {
        !query.isEmpty || sender != nil
    }

    var status: ChatSearchPanel.Status {
        guard isActive else { return .idle }
        guard let currentIndex else { return isLoading ? .loading : .noResults }
        let total = nextFromMessageID == 0 ? messageIDs.count : max(totalCount, messageIDs.count)
        return .results(
            position: currentIndex + 1,
            total: total,
            canGoOlder: currentIndex + 1 < messageIDs.count || nextFromMessageID != 0,
            canGoNewer: currentIndex > 0,
        )
    }

    init(client: TDLibClient, location: ChatLocation, isCurrent: @escaping () -> Bool) {
        self.client = client
        self.location = location
        self.isCurrent = isCurrent
    }

    deinit {
        task?.cancel()
    }

    /// Telegram's searchMessageIdByTimestamp (getHistory with an offset date and add_offset -1): the first message of
    /// the location sent at `date` or later. TDLib finds the last message before the date, and the location's
    /// history from there gives the next one.
    static func firstMessageID(sentSince date: Int, in location: ChatLocation, client: TDLibClient) async -> Int64? {
        let before = try? await client.send(TDNativeRequests.getChatMessageByDate(
            chatId: location.chatID, date: max(1, date - 1),
        ))
        // Without an earlier message the history starts at the location's first server message.
        let anchorID: Int64 = before?.id ?? 1 << 20
        let isNewer: (Message) -> Bool = { message in
            before == nil ? message.id >= anchorID : message.id > anchorID
        }
        for _ in 0..<3 {
            let messages: [Message] =
                if location.topic == nil {
                    await (try? client.getChatHistory(
                        chatId: location.chatID, fromMessageId: anchorID, limit: 6, offset: -5, onlyLocal: false,
                    )
                    .messages) ?? []
                } else {
                    await (try? client.searchChatMessages(
                        chatId: location.chatID, filter: nil, fromMessageId: anchorID, limit: 6, offset: -5,
                        query: "", senderId: nil, topicId: location.topic,
                    )
                    .messages) ?? []
                }
            if let next = messages.filter({ location.matches(message: $0) && isNewer($0) }).min(by: { $0.id < $1.id }) {
                return next.id
            }
            // A thread search reads the server; TDLib may first answer a chat history from its cache only.
            if location.topic != nil || Task.isCancelled { break }
        }
        return nil
    }

    func update(query rawQuery: String, sender: MessageSender?) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != self.query || sender != self.sender else { return }
        self.query = query
        self.sender = sender
        restart()
        guard isActive else {
            onChange?()
            return
        }
        isLoading = true
        onChange?()
        load(waitsForTyping: true) { [weak self] in
            guard let self, let first = messageIDs.first else { return }
            currentIndex = 0
            onNavigate?(first)
        }
    }

    /// Telegram's up arrow: the next older result, loading the next page when the loaded ones run out.
    func showOlder() {
        guard let currentIndex, !isLoading, isCurrent() else { return }
        if currentIndex + 1 < messageIDs.count {
            show(index: currentIndex + 1)
            return
        }
        guard nextFromMessageID != 0 else { return }
        isLoading = true
        onChange?()
        load(waitsForTyping: false) { [weak self] in
            guard let self, let currentIndex, currentIndex + 1 < messageIDs.count else { return }
            show(index: currentIndex + 1)
        }
    }

    func showNewer() {
        guard let currentIndex, currentIndex > 0, isCurrent() else { return }
        show(index: currentIndex - 1)
    }

    func reset() {
        query = ""
        sender = nil
        restart()
    }

    private func show(index: Int) {
        currentIndex = index
        onChange?()
        onNavigate?(messageIDs[index])
    }

    private func restart() {
        generation &+= 1
        task?.cancel()
        task = nil
        messageIDs = []
        currentIndex = nil
        totalCount = 0
        nextFromMessageID = 0
        isLoading = false
    }

    private func load(waitsForTyping: Bool, completion: @escaping () -> Void) {
        let requestGeneration = generation
        let query = query
        let sender = sender
        let client = client
        let location = location
        task = Task { [weak self] in
            if waitsForTyping { try? await Task.sleep(for: Self.typingDelay) }
            guard let self, owns(requestGeneration) else { return }
            var skippedPages = 0
            var fromMessageID = nextFromMessageID
            var seen = Set(messageIDs)
            while true {
                let found = try? await client.searchChatMessages(
                    chatId: location.chatID,
                    filter: nil,
                    fromMessageId: fromMessageID,
                    limit: Self.pageLimit,
                    offset: 0,
                    query: query,
                    senderId: sender,
                    topicId: location.topic,
                )
                guard owns(requestGeneration) else { return }
                let added = (found?.messages ?? [])
                    .filter { location.matches(message: $0) && seen.insert($0.id).inserted }
                    .map(\.id)
                messageIDs += added
                totalCount = max(totalCount, found?.totalCount ?? 0)
                fromMessageID = found?.messages.isEmpty == false ? found?.nextFromMessageId ?? 0 : 0
                skippedPages += 1
                if !added.isEmpty || fromMessageID == 0 || skippedPages > Self.maximumSkippedPages { break }
            }
            nextFromMessageID = fromMessageID
            isLoading = false
            task = nil
            completion()
            onChange?()
        }
    }

    private func owns(_ requestGeneration: UInt64) -> Bool {
        guard !Task.isCancelled, requestGeneration == generation else { return false }
        guard isCurrent() else {
            reset()
            onChange?()
            return false
        }
        return true
    }
}
