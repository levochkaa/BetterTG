// ForumTopicsVM.swift

import Combine
import Foundation
import TDLibKitDynamic

// MARK: - ForumTopicsVM

@MainActor final class ForumTopicsVM: ObservableObject {
    private struct ReadStamp {
        let ordinal: UInt64
        let revision: UInt64
    }

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
    private let reads: ForumTopicsReadEnvironment
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var topicRefreshTasks = [Int: Task<Void, Never>]()
    private var topicRequestIDs = [Int: UUID]()
    // true is a semantic invalidation; a page can satisfy only a false/unknown echo.
    private var pendingTopicRefreshes = [Int: Bool]()
    private var liveRevision = UInt64.zero
    private var readOrdinal = UInt64.zero
    private var acceptedReadOrdinals = [Int: UInt64]()
    private var scalarUpdates = [Int: (revision: UInt64, value: UpdateForumTopic)]()
    private var infoUpdates = [Int: (revision: UInt64, value: ForumTopicInfo)]()
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
        usesTransport && !retired && reads.currentSource()?.matches(location) == true
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
        reads: ForumTopicsReadEnvironment? = nil,
    ) {
        self.customChat = customChat
        self.location = location
        self.client = client
        self.usesTransport = usesTransport
        self.reads = reads ?? .live(client: client)
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
        self.chatOpenLease = usesTransport && self.reads.opensChat
            ? ChatOpenLeaseCoordinator.shared.acquire(
                location: location,
                client: client,
            )
            : nil
        if usesTransport { observeUpdates() }
    }

    #if DEBUG
    static func controlled(
        customChat: CustomChat, location: ChatLocation, client: TDLibClient,
        reads: ForumTopicsReadEnvironment,
        restoration: ForumTopicsRestorationState? = nil,
    ) -> ForumTopicsVM {
        ForumTopicsVM(
            customChat: customChat,
            location: location,
            client: client,
            restoration: restoration,
            usesTransport: true,
            reads: reads,
        )
    }

    var probeReadTasks: [Task<Void, Never>] { Array(topicRefreshTasks.values) + [loadTask].compactMap(\.self) }
    var probePageTask: Task<Void, Never>? { loadTask }

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
        topicRequestIDs.removeAll()
        pendingTopicRefreshes.removeAll()
        scalarUpdates.removeAll()
        infoUpdates.removeAll()
        acceptedReadOrdinals.removeAll()
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
            topicRequestIDs.removeAll()
            topicRefreshTasks.values.forEach { $0.cancel() }
            topicRefreshTasks.removeAll()
            pendingTopicRefreshes.removeAll()
            scalarUpdates.removeAll()
            infoUpdates.removeAll()
            acceptedReadOrdinals.removeAll()
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
        let readPage = reads.page
        let location = location
        let read = beginRead()
        loadTask = Task { [weak self] in
            guard !Task.isCancelled, self?.contextIsCurrent == true else { return }
            do {
                let result = try await readPage(location, cursor, query)
                guard let self, !Task.isCancelled,
                      currentGeneration == generation,
                      query == self.query,
                      contextIsCurrent
                else { return }
                var removed = Set<Int>()
                let incoming = result.topics.compactMap { response -> ForumTopic? in
                    guard let topic = self.acceptFullTopic(response, read: read) else { return nil }
                    let renamed = self.infoUpdates[topic.info.forumTopicId].map {
                        $0.revision > read.revision && $0.value.name != response.info.name
                    } ?? false
                    // The server may match fuzzy/transliterated queries. Only a newer
                    // different name can invalidate that returned membership locally.
                    if topic.info.isHidden || (renamed && !self.topicMatchesQuery(topic.info)) {
                        removed.insert(topic.info.forumTopicId)
                    }
                    return topic
                }
                let retained = reset
                    ? topics.filter { (self.acceptedReadOrdinals[$0.info.forumTopicId] ?? 0) > read.ordinal }
                    : topics
                topics = ForumTopicPageState.merging(
                    existing: retained.filter { !removed.contains($0.info.forumTopicId) },
                    incoming: incoming.filter { !removed.contains($0.info.forumTopicId) },
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
                for topic in incoming where pendingTopicRefreshes[topic.info.forumTopicId] == false {
                    pendingTopicRefreshes[topic.info.forumTopicId] = nil
                }
                drainPendingTopicRefreshes()
            } catch is CancellationError {
                guard let self, currentGeneration == generation, contextIsCurrent else { return }
                requestedCursors.remove(cursor)
                loading = false
                loadTask = nil
                drainPendingTopicRefreshes()
            } catch {
                guard let self, currentGeneration == generation, contextIsCurrent else { return }
                requestedCursors.remove(cursor)
                loading = false
                loadTask = nil
                errorMessage = "Topics couldn't be loaded."
                drainPendingTopicRefreshes()
            }
        }
    }

    private func observeUpdates() {
        reads.sourceChanges
            .sink { [weak self] source in
                guard let self, !source.matches(location) else { return }
                retire()
            }
            .store(in: &cancellables)
        observeCurrentUpdate(.updateForumTopicInfo) { [weak self] update in
            guard let self,
                  contextIsCurrent,
                  update.info.chatId == location.chatID
            else { return }
            let previous = infoUpdates[update.info.forumTopicId]?.value
                ?? topics.first { $0.info.forumTopicId == update.info.forumTopicId }?.info
            liveRevision &+= 1
            infoUpdates[update.info.forumTopicId] = (liveRevision, update.info)
            guard let index = topics.firstIndex(where: {
                $0.info.forumTopicId == update.info.forumTopicId
            }) else {
                if previous != update.info, !update.info.isHidden, topicMatchesQuery(update.info) {
                    refreshTopic(id: update.info.forumTopicId, afterCurrent: false)
                }
                return
            }
            let retainedName = acceptedQuery == query ? topics[index].info.name : nil
            if update.info.isHidden || !topicMatchesQuery(update.info, retaining: retainedName) {
                topics.remove(at: index)
            } else if topics[index].info != update.info {
                topics[index] = topics[index].replacing(info: update.info)
            }
        }
        observeCurrentUpdate(.updateForumTopic) { [weak self] update in
            guard let self,
                  contextIsCurrent,
                  update.chatId == location.chatID
            else { return }
            acceptScalarUpdate(update)
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
            notification, center: reads.center, subscriptions: &cancellables, location: location,
            currentLocation: { [weak self] in self?.location },
            currentSource: { [weak self] in self?.reads.currentSource() },
            ownerIsCurrent: { [weak self] in self?.contextIsCurrent == true },
            perform: { value, _ in perform(value) },
        )
    }

    private func acceptScalarUpdate(_ update: UpdateForumTopic) {
        let id = update.forumTopicId
        guard id > 0 else { return }
        let current = topics.first { $0.info.forumTopicId == id }
        let previous = scalarUpdates[id]?.value ?? current?.updatePayload
        liveRevision &+= 1
        scalarUpdates[id] = (liveRevision, update)
        guard previous != update else { return }
        if let index = topics.firstIndex(where: { $0.info.forumTopicId == id }) {
            topics[index] = topics[index].applying(update: update)
        }
        let needsFull = previous.map {
            $0.lastReadInboxMessageId != update.lastReadInboxMessageId || $0.draftMessage != update.draftMessage
        } ?? false
        if current == nil || needsFull { refreshTopic(id: id, afterCurrent: needsFull) }
    }

    private func rebaseScalars(_ topic: ForumTopic, after revision: UInt64) -> ForumTopic {
        guard let update = scalarUpdates[topic.info.forumTopicId], update.revision > revision else { return topic }
        return topic.applying(update: update.value)
    }

    private func beginRead() -> ReadStamp {
        readOrdinal &+= 1
        return ReadStamp(ordinal: readOrdinal, revision: liveRevision)
    }

    /// Admission records removals too. A stale full result cannot revive a row
    /// or replace the payload used to recognize TDLib's response echoes.
    private func acceptFullTopic(_ response: ForumTopic, read: ReadStamp) -> ForumTopic? {
        let id = response.info.forumTopicId
        guard response.info.chatId == location.chatID, id > 0,
              acceptedReadOrdinals[id].map({ $0 <= read.ordinal }) ?? true else { return nil }
        var topic = rebaseScalars(response, after: read.revision)
        if let info = infoUpdates[id], info.revision > read.revision { topic = topic.replacing(info: info.value) }
        acceptedReadOrdinals[id] = read.ordinal
        if scalarUpdates[id].map({ $0.revision <= read.revision }) ?? true {
            scalarUpdates[id] = (read.revision, topic.updatePayload)
        }
        if infoUpdates[id].map({ $0.revision <= read.revision }) ?? true {
            infoUpdates[id] = (read.revision, topic.info)
        }
        return topic
    }

    private func drainPendingTopicRefreshes() {
        guard contextIsCurrent, !loading else { return }
        let pending = pendingTopicRefreshes
        pendingTopicRefreshes.removeAll()
        for (id, semantic) in pending {
            if topicRequestIDs[id] != nil { pendingTopicRefreshes[id] = semantic }
            else { refreshTopic(id: id, afterCurrent: semantic) }
        }
    }

    private func refreshTopic(id: Int, afterCurrent: Bool = true) {
        guard contextIsCurrent, id > 0 else { return }
        let retainedName = retainedTopicName(id: id)
        if let info = infoUpdates[id]?.value,
           info.isHidden || !topicMatchesQuery(info, retaining: retainedName) { return }
        if loading { pendingTopicRefreshes[id] = (pendingTopicRefreshes[id] ?? false) || afterCurrent
            return
        }
        if topicRequestIDs[id] != nil {
            if afterCurrent { pendingTopicRefreshes[id] = true }
            return
        }
        let requestID = UUID()
        topicRequestIDs[id] = requestID
        let currentGeneration = generation
        let query = query
        let location = location
        let readTopic = reads.topic
        let read = beginRead()
        topicRefreshTasks[id] = Task { [weak self] in
            defer {
                if let self, topicRequestIDs[id] == requestID {
                    topicRequestIDs[id] = nil
                    topicRefreshTasks[id] = nil
                    if let semantic = pendingTopicRefreshes.removeValue(forKey: id) {
                        refreshTopic(id: id, afterCurrent: semantic)
                    }
                }
            }
            guard !Task.isCancelled, self?.contextIsCurrent == true,
                  self?.topicRequestIDs[id] == requestID else { return }
            let response = try? await readTopic(location, id)
            guard let self, !Task.isCancelled, topicRequestIDs[id] == requestID,
                  currentGeneration == generation, query == self.query,
                  contextIsCurrent
            else { return }
            guard let response, response.info.forumTopicId == id,
                  let topic = acceptFullTopic(response, read: read) else { return }
            let currentName = retainedTopicName(id: id)
            let unchangedName = currentName == retainedName ? retainedName : nil
            if topic.info.isHidden || !topicMatchesQuery(topic.info, retaining: unchangedName) {
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

    private func retainedTopicName(id: Int) -> String? {
        guard acceptedQuery == query else { return nil }
        // Retain display membership already accepted for this query, including
        // restoration seeds. This does not make metadata or permissions fresh.
        return topics.first { $0.info.forumTopicId == id }?.info.name
    }

    private func topicMatchesQuery(_ info: ForumTopicInfo, retaining name: String? = nil) -> Bool {
        query.isEmpty || info.name.localizedCaseInsensitiveContains(query) || name == info.name
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
