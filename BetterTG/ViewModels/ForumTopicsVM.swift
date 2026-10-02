// ForumTopicsVM.swift

import Combine
import Foundation
import TDLibKitDynamic

// MARK: - ForumTopicsVM

@MainActor final class ForumTopicsVM: ObservableObject {
    let customChat: CustomChat
    let location: ChatLocation
    let client: TDLibClient
    @Published private(set) var topics = [ForumTopic]()
    @Published private(set) var loading = false
    @Published private(set) var hasMore = true
    @Published private(set) var errorMessage: String?

    #if DEBUG
    private(set) var probeQueries = [String]()
    private(set) var probeStarts = 0
    #endif

    private let chatOpenLease: ChatOpenLease?
    private let usesTransport: Bool
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var topicRefreshTasks = [Int: Task<Void, Never>]()
    private var generation = UInt64.zero
    private var nextOffsetDate = 0
    private var nextOffsetForumTopicID = 0
    private var nextOffsetMessageID = Int64.zero
    private var requestedCursors = Set<ForumTopicPageCursor>()
    private var query = ""
    private var acceptedQuery = ""
    private var pendingPageRequest: ForumTopicPageRequest?
    private var restoringPages = false
    private var restorationReset: Bool?
    private var retired = false

    private var contextIsCurrent: Bool {
        usesTransport && !retired && TDLib.shared.activeAccountID == location.accountID
            && TDLib.shared.activeClient.id == location.clientID
            && client.id == location.clientID
    }

    convenience init(
        customChat: CustomChat,
        location: ChatLocation,
        client: TDLibClient,
        restoration: ForumTopicsRestorationState? = nil,
    ) {
        self.init(
            customChat: customChat,
            location: location,
            client: client,
            restoration: restoration,
            usesTransport: true,
        )
    }

    deinit {
        loadTask?.cancel()
        topicRefreshTasks.values.forEach { $0.cancel() }
        chatOpenLease?.invalidate()
    }

    private init(
        customChat: CustomChat,
        location: ChatLocation,
        client: TDLibClient,
        restoration: ForumTopicsRestorationState?,
        usesTransport: Bool,
    ) {
        self.customChat = customChat
        self.location = location
        self.client = client
        self.usesTransport = usesTransport
        if let restoration, restoration.accepts(location) {
            self.topics = restoration.topics
            self.query = restoration.query
            self.acceptedQuery = restoration.query
            self.nextOffsetDate = restoration.cursor.date
            self.nextOffsetForumTopicID = restoration.cursor.forumTopicID
            self.nextOffsetMessageID = restoration.cursor.messageID
            self.requestedCursors = restoration.completedCursors
            self.hasMore = restoration.hasMore
            self.restoringPages = true
            self.restorationReset = restoration.pendingReset
            self.pendingPageRequest = restoration.pendingReset.map {
                ForumTopicPageRequest(cursor: restoration.cursor, resets: $0)
            }
        }
        self.chatOpenLease = usesTransport
            ? ChatOpenLeaseCoordinator.shared.acquire(
                location: location,
                client: client,
            )
            : nil
        if usesTransport { observeUpdates() }
    }

    #if DEBUG
    static func isolated(
        customChat: CustomChat,
        location: ChatLocation,
        client: TDLibClient,
        restoration: ForumTopicsRestorationState?,
    ) -> ForumTopicsVM {
        ForumTopicsVM(
            customChat: customChat,
            location: location,
            client: client,
            restoration: restoration,
            usesTransport: false,
        )
    }

    func publishProbe(topics: [ForumTopic], loading: Bool = false, error: String? = nil) {
        guard !usesTransport else { return }
        self.topics = topics
        self.loading = loading
        errorMessage = error
    }
    #endif

    func loadInitial() {
        load(reset: true, query: query)
    }

    func start() {
        #if DEBUG
        if !usesTransport { probeStarts += 1 }
        #endif
        guard restoringPages else { loadInitial()
            return
        }
        restoringPages = false
        // The saved rows/cursor are a display seed, not a fresh server head.
        if let restorationReset { load(reset: restorationReset, query: query) }
    }

    func restorationState(rawQuery: String) -> ForumTopicsRestorationState {
        ForumTopicsRestorationState(
            location: location, rawQuery: rawQuery, modelQuery: query, acceptedQuery: acceptedQuery,
            topics: topics,
            cursor: ForumTopicPageCursor(
                date: nextOffsetDate,
                forumTopicID: nextOffsetForumTopicID,
                messageID: nextOffsetMessageID,
            ),
            requestedCursors: requestedCursors, hasMore: hasMore, request: pendingPageRequest,
        )
    }

    func retire() {
        retired = true
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        topicRefreshTasks.values.forEach { $0.cancel() }
        topicRefreshTasks.removeAll()
        cancellables.removeAll()
        chatOpenLease?.invalidate()
    }

    func search(_ query: String) {
        #if DEBUG
        if !usesTransport { probeQueries.append(query) }
        #endif
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != self.query else { return }
        load(reset: true, query: normalized)
    }

    func loadMore() {
        load(reset: false, query: query)
    }

    func topicForOpening(id: Int, rawQuery: String) -> ForumTopic? {
        let normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard contextIsCurrent, normalized == query, normalized == acceptedQuery else { return nil }
        return topics.first { $0.info.forumTopicId == id }
    }

    private func load(reset: Bool, query: String) {
        guard contextIsCurrent, !loading || reset else { return }
        if reset {
            generation &+= 1
            loadTask?.cancel()
            self.query = query
            nextOffsetDate = 0
            nextOffsetForumTopicID = 0
            nextOffsetMessageID = 0
            requestedCursors.removeAll()
            hasMore = true
        } else {
            guard hasMore else { return }
        }
        let currentGeneration = generation
        let offsetDate = nextOffsetDate
        let offsetForumTopicID = nextOffsetForumTopicID
        let offsetMessageID = nextOffsetMessageID
        let cursor = ForumTopicPageCursor(
            date: offsetDate,
            forumTopicID: offsetForumTopicID,
            messageID: offsetMessageID,
        )
        guard requestedCursors.insert(cursor).inserted else {
            hasMore = false
            return
        }
        loading = true
        errorMessage = nil
        pendingPageRequest = ForumTopicPageRequest(cursor: cursor, resets: reset)
        loadTask = Task { [weak self] in
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            do {
                let result = try await client.getForumTopics(
                    chatId: location.chatID,
                    limit: 50,
                    offsetDate: offsetDate,
                    offsetForumTopicId: offsetForumTopicID,
                    offsetMessageId: offsetMessageID,
                    query: query,
                )
                guard !Task.isCancelled,
                      currentGeneration == generation,
                      query == self.query,
                      contextIsCurrent
                else { return }
                topics = ForumTopicPageState.merging(
                    existing: reset ? [] : topics,
                    incoming: result.topics,
                )
                acceptedQuery = query
                nextOffsetDate = result.nextOffsetDate
                nextOffsetForumTopicID = result.nextOffsetForumTopicId
                nextOffsetMessageID = result.nextOffsetMessageId
                hasMore = ForumTopicPageState.hasMore(
                    response: result,
                    requestedCursor: cursor,
                )
                loading = false
                loadTask = nil
                pendingPageRequest = nil
            } catch is CancellationError {
                guard currentGeneration == generation else { return }
                requestedCursors.remove(cursor)
                loading = false
                loadTask = nil
            } catch {
                guard currentGeneration == generation, contextIsCurrent else { return }
                requestedCursors.remove(cursor)
                loading = false
                loadTask = nil
                errorMessage = "Topics couldn't be loaded."
            }
        }
    }

    private func observeUpdates() {
        observeCurrentUpdate(.updateForumTopicInfo) { [weak self] update in
            guard let self,
                  contextIsCurrent,
                  update.info.chatId == location.chatID
            else { return }
            guard let index = topics.firstIndex(where: {
                $0.info.forumTopicId == update.info.forumTopicId
            }) else {
                if !update.info.isHidden, topicMatchesQuery(update.info) {
                    refreshTopic(id: update.info.forumTopicId)
                }
                return
            }
            if update.info.isHidden || !topicMatchesQuery(update.info) {
                topics.remove(at: index)
            } else {
                topics[index] = topics[index].replacing(info: update.info)
            }
        }
        observeCurrentUpdate(.updateForumTopic) { [weak self] update in
            guard let self,
                  contextIsCurrent,
                  update.chatId == location.chatID
            else { return }
            refreshTopic(id: update.forumTopicId)
        }
        observeCurrentUpdate(.updateNewMessage) { [weak self] update in
            guard let self,
                  contextIsCurrent,
                  update.message.chatId == location.chatID,
                  case .messageTopicForum(let topic) = update.message.topicId
            else { return }
            refreshTopic(id: topic.forumTopicId)
        }
        observeCurrentUpdate(.updateDeleteMessages) { [weak self] update in
            guard let self,
                  contextIsCurrent,
                  update.chatId == location.chatID,
                  !update.fromCache,
                  update.isPermanent,
                  topics.contains(where: { topic in
                      topic.lastMessage.map { update.messageIds.contains($0.id) } == true
                  })
            else { return }
            load(reset: true, query: query)
        }
        observeCurrentUpdate(.updateMessageContent) { [weak self] update in
            self?.refreshTopicContainingLastMessage(
                chatID: update.chatId,
                messageID: update.messageId,
            )
        }
        observeCurrentUpdate(.updateMessageEdited) { [weak self] update in
            self?.refreshTopicContainingLastMessage(
                chatID: update.chatId,
                messageID: update.messageId,
            )
        }
        observeCurrentUpdate(.updateMessageSendSucceeded) { [weak self] update in
            self?.refreshTopic(for: update.message)
        }
        observeCurrentUpdate(.updateMessageSendFailed) { [weak self] update in
            self?.refreshTopic(for: update.message)
        }
    }

    private func observeCurrentUpdate<Value>(
        _ notification: TdNotification<Value>,
        perform: @escaping (Value) -> Void,
    ) {
        ChatUpdateDeliveryAuthority.observe(
            notification, center: nc, subscriptions: &cancellables, location: location,
            currentLocation: { [weak self] in self?.location },
            currentSource: { TDLib.shared.activeUpdateSource },
            ownerIsCurrent: { [weak self] in self?.contextIsCurrent == true },
            perform: { value, _ in perform(value) },
        )
    }

    private func refreshTopic(id: Int) {
        guard contextIsCurrent else { return }
        topicRefreshTasks[id]?.cancel()
        let currentGeneration = generation
        topicRefreshTasks[id] = Task { [weak self] in
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            let topic = try? await client.getForumTopic(
                chatId: location.chatID,
                forumTopicId: id,
            )
            guard !Task.isCancelled,
                  currentGeneration == generation,
                  contextIsCurrent
            else { return }
            topicRefreshTasks[id] = nil
            guard let topic else { return }
            if topic.info.isHidden || !topicMatchesQuery(topic.info) {
                topics.removeAll { $0.info.forumTopicId == id }
                return
            }
            if let index = topics.firstIndex(where: { $0.info.forumTopicId == id }) {
                topics[index] = topic
            } else {
                topics.append(topic)
            }
            sortTopics()
        }
    }

    private func topicMatchesQuery(_ info: ForumTopicInfo) -> Bool {
        query.isEmpty || info.name.localizedCaseInsensitiveContains(query)
    }

    private func refreshTopicContainingLastMessage(chatID: Int64, messageID: Int64) {
        guard contextIsCurrent, chatID == location.chatID,
              let topic = topics.first(where: { $0.lastMessage?.id == messageID })
        else { return }
        refreshTopic(id: topic.info.forumTopicId)
    }

    private func refreshTopic(for message: Message) {
        guard contextIsCurrent,
              message.chatId == location.chatID,
              case .messageTopicForum(let topic) = message.topicId
        else { return }
        refreshTopic(id: topic.forumTopicId)
    }

    private func sortTopics() {
        topics.sort { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order > rhs.order
            }
            return lhs.info.forumTopicId < rhs.info.forumTopicId
        }
    }
}

extension ForumTopic {
    func replacing(info: ForumTopicInfo) -> ForumTopic {
        ForumTopic(
            draftMessage: draftMessage,
            info: info,
            isPinned: isPinned,
            lastMessage: lastMessage,
            lastReadInboxMessageId: lastReadInboxMessageId,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            notificationSettings: notificationSettings,
            order: order,
            unreadCount: unreadCount,
            unreadMentionCount: unreadMentionCount,
            unreadPollVoteCount: unreadPollVoteCount,
            unreadReactionCount: unreadReactionCount,
        )
    }
}
