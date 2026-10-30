// StoryViewerSession.swift

import Combine
import Foundation
import TDLibKit

// MARK: - StoryViewerSession

/// The TDLib side of one story viewer: the account and client it opened with. Requests answer only while that client
/// is active, updates from any other client are dropped, and a client change retires the session, so a viewer never
/// follows a replacement client.
@MainActor final class StoryViewerSession {
    struct StoryKey: Hashable {
        let chatID: Int64
        let storyID: Int
    }

    let source: TdUpdateSource
    let client: TDLibClient
    let vodRanges: TDLibVODRangeCoordinator
    /// The account's user, whose stories get Telegram's footer and own menu.
    private(set) var accountUserID: Int64?

    var onStoryChanged: ((Story) -> Void)?
    var onStoryDeleted: ((StoryKey) -> Void)?
    var onActiveStoriesChanged: ((ChatActiveStories) -> Void)?
    var onViewListAccessChanged: ((Int64) -> Void)?
    var onRetired: (() -> Void)?

    private(set) var isRetired = false
    #if DEBUG
        /// The UI probe's session: it answers from seeded stories, chats and story lists, and nothing reaches TDLib.
        private(set) var isOffline = false
        private var offlineActiveStories = [Int64: ChatActiveStories]()
        /// The probe's interactions with the account's stories, by story, newest first, and its contacts.
        private var offlineInteractions = [Int: [StoryInteraction]]()
        private var offlineContactIDs = Set<Int64>()
        private var offlineChatAccess = [Int64: Bool]()
        private var offlineFailedOffsets = Set<String>()
        private(set) var interactionRequests = [StoryViewList.Request]()
    #else
        let isOffline = false
    #endif

    private var stories = [StoryKey: Story]()
    private var storyRequests = [StoryKey: Task<Story?, Never>]()
    private var activeStoryRequests = [Int64: Task<ChatActiveStories?, Never>]()
    private var chats = [Int64: Chat]()
    private var chatRequests = [Int64: Task<Chat?, Never>]()
    private var statisticsAccess = [Int64: Bool]()
    private var viewListMemberStatuses = [Int64: ChatMemberStatus]()
    private var viewListAccessGenerations = [Int64: Int]()
    private var openedStory: StoryKey?
    /// openStory and closeStory reach TDLib in the order the viewer shows and leaves stories.
    private var visibilityRequests: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var isCurrent: Bool {
        !isRetired && (isOffline || TDLib.shared.activeUpdateSource == source)
    }

    init?(client: TDLibClient) {
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id else { return nil }
        self.source = source
        self.client = client
        self.vodRanges = TDLib.shared.vodRanges
        self.accountUserID = TDLib.shared.activeAccount?.userID
        observeUpdates()
    }

    #if DEBUG
        /// An isolated fixture has no active-account dependency and never subscribes to real account updates.
        init(offlineClient client: TDLibClient) {
            self.client = client
            self.source = TdUpdateSource(accountID: UUID(), clientID: client.id)
            self.vodRanges = TDLib.shared.vodRanges
            self.isOffline = true
        }

        /// Turns the session into the UI probe's: the viewer shows only these, without TDLib requests. With
        /// `accountUserID` set, that poster's stories are the account's own.
        func seedOffline(
            stories: [Story],
            chats: [Chat],
            activeStories: [ChatActiveStories],
            accountUserID: Int64? = nil,
        ) {
            isOffline = true
            if let accountUserID { self.accountUserID = accountUserID }
            for story in stories {
                self.stories[StoryKey(chatID: story.posterChatId, storyID: story.id)] = story
            }
            for chat in chats {
                self.chats[chat.id] = chat
            }
            for list in activeStories {
                offlineActiveStories[list.chatId] = list
            }
        }

        /// The probe's viewers of the account's stories; `contactIDs` answers the Contacts tab.
        func seedOfflineInteractions(_ interactions: [Int: [StoryInteraction]], contactIDs: Set<Int64>) {
            offlineInteractions = interactions
            offlineContactIDs = contactIDs
        }

        func setOfflineChatAccess(chatID: Int64, allowed: Bool) {
            offlineChatAccess[chatID] = allowed
            onViewListAccessChanged?(chatID)
        }

        func failOfflineInteractionPage(offset: String) { offlineFailedOffsets.insert(offset) }

        /// getStoryInteractions over the seeded list, ten at a time so the probe pages: the search matches the
        /// seeded chats' titles, and reactions come first in their date order when asked.
        private func offlineInteractionPage(
            storyID: Int,
            query: StoryViewList.Query,
            offset: String,
        ) -> StoryViewList.Page {
            var all = offlineInteractions[storyID] ?? []
            if query.listMode == .contacts {
                all = all.filter { offlineContactIDs.contains(Self.actorID($0.actorId)) }
            }
            if !query.text.isEmpty {
                all = all.filter { interaction in
                    chats[Self.actorID(interaction.actorId)]?.title.localizedCaseInsensitiveContains(query.text) == true
                }
            }
            if query.sortMode == .repostsFirst {
                let shared = all.filter { interaction in
                    switch interaction.type {
                    case .storyInteractionTypeForward,
                         .storyInteractionTypeRepost: true
                    case .storyInteractionTypeView: false
                    }
                }
                all = shared + all.filter { interaction in
                    if case .storyInteractionTypeView = interaction.type { return true }
                    return false
                }
            } else if query.sortMode == .reactionsFirst {
                let reacted = all.filter(Self.hasReaction)
                all = reacted + all.filter { !Self.hasReaction($0) }
            }
            let start = Int(offset) ?? 0
            let end = min(all.count, start + 10)
            let slice = start < end ? Array(all[start..<end]) : []
            let reactions = offlineInteractions[storyID]?.count(where: Self.hasReaction) ?? 0
            return StoryViewList.page(StoryInteractions(
                totalCount: all.count,
                totalForwardCount: 0,
                totalReactionCount: reactions,
                interactions: slice,
                nextOffset: end < all.count ? String(end) : "",
            ))
        }

        private static func actorID(_ sender: MessageSender) -> Int64 {
            switch sender {
            case .messageSenderUser(let user): user.userId
            case .messageSenderChat(let chat): chat.chatId
            }
        }

        private static func hasReaction(_ interaction: StoryInteraction) -> Bool {
            if case .storyInteractionTypeView(let view) = interaction.type { return view.chosenReactionType != nil }
            return false
        }
    #endif

    func cachedStory(_ key: StoryKey) -> Story? {
        stories[key]
    }

    func cachedChat(_ chatID: Int64) -> Chat? {
        chats[chatID]
    }

    func story(_ key: StoryKey) async -> Story? {
        if let story = stories[key] { return story }
        guard !isOffline else { return nil }
        let task = storyRequests[key] ?? Task { [client] in
            try? await client.getStory(onlyLocal: false, storyId: key.storyID, storyPosterChatId: key.chatID)
        }
        storyRequests[key] = task
        let story = await task.value
        storyRequests[key] = nil
        guard isCurrent, let story else { return nil }
        // An update that arrived meanwhile is newer than the answer.
        if let updated = stories[key] { return updated }
        stories[key] = story
        return story
    }

    func activeStories(chatID: Int64) async -> ChatActiveStories? {
        #if DEBUG
            if isOffline { return offlineActiveStories[chatID] }
        #endif
        let task = activeStoryRequests[chatID] ?? Task { [client] in
            try? await client.getChatActiveStories(chatId: chatID)
        }
        activeStoryRequests[chatID] = task
        let stories = await task.value
        activeStoryRequests[chatID] = nil
        return isCurrent ? stories : nil
    }

    /// Creator/statistics access follows StoryItemSetContainerComponent; own-viewer availability is a separate flag.
    func viewListScope(for story: Story) async -> StoryViewList.Scope? {
        guard isCurrent else { return nil }
        let generation = viewListAccessGenerations[story.posterChatId, default: 0]
        if case .storyContentLive = story.content { return nil }
        if story.posterChatId == accountUserID { return .own }
        #if DEBUG
            if isOffline { return (offlineChatAccess[story.posterChatId] ?? story.canGetStatistics) ? .chat : nil }
        #endif
        guard let chat = await chat(story.posterChatId), case .chatTypeSupergroup(let info) = chat.type,
              let group = try? await client.send(TDNativeRequests.getSupergroup(supergroupId: info.supergroupId)),
              isCurrent, generation == viewListAccessGenerations[story.posterChatId, default: 0] else { return nil }
        viewListMemberStatuses[info.supergroupId] = group.status
        if StoryViewList.canReadChat(status: group.status, canViewStatistics: false) { return .chat }
        guard case .chatMemberStatusAdministrator = group.status,
              let full = try? await client
                .send(TDNativeRequests.getSupergroupFullInfo(supergroupId: info.supergroupId)),
              isCurrent, generation == viewListAccessGenerations[story.posterChatId, default: 0] else { return nil }
        statisticsAccess[info.supergroupId] = full.canGetStatistics
        return StoryViewList.canReadChat(status: group.status, canViewStatistics: full.canGetStatistics) ? .chat : nil
    }

    /// Keep the poster with its story ID, revalidate access, then dispatch to TDLib's matching method.
    func storyInteractions(
        key: StoryKey,
        scope: StoryViewList.Scope,
        query: StoryViewList.Query,
        offset: String,
    ) async -> StoryViewList.Page? {
        guard isCurrent, let story = stories[key], await viewListScope(for: story) == scope,
              isCurrent else { return nil }
        let request = StoryViewList.request(key: key, scope: scope, query: query, offset: offset)
        let generation = viewListAccessGenerations[key.chatID, default: 0]
        #if DEBUG
            interactionRequests.append(request)
            if isOffline {
                if offlineFailedOffsets.remove(offset) != nil { return nil }
                return offlineInteractionPage(storyID: key.storyID, query: query, offset: offset)
            }
        #endif
        let interactions: StoryInteractions? =
            switch request {
            case .own(let storyID, let query, let offset):
                try? await client.getStoryInteractions(
                    limit: StoryViewList.pageSize, offset: offset, onlyContacts: query.listMode == .contacts,
                    preferForwards: query.sortMode == .repostsFirst,
                    preferWithReaction: query.sortMode == .reactionsFirst,
                    query: query.text, storyId: storyID,
                )
            case .chat(let chatID, let storyID, let forwards, let offset):
                try? await client.send(TDNativeRequests.getChatStoryInteractions(
                    storyPosterChatId: chatID, storyId: storyID, reactionType: nil, preferForwards: forwards,
                    offset: offset, limit: StoryViewList.pageSize,
                ))
            }
        guard isCurrent, generation == viewListAccessGenerations[key.chatID, default: 0],
              stories[key] != nil, let interactions else { return nil }
        return StoryViewList.page(interactions)
    }

    func chat(_ chatID: Int64) async -> Chat? {
        if let chat = chats[chatID] { return chat }
        guard !isOffline else { return nil }
        let task = chatRequests[chatID] ?? Task { [client] in
            try? await client.getChat(chatId: chatID)
        }
        chatRequests[chatID] = task
        let chat = await task.value
        chatRequests[chatID] = nil
        guard isCurrent, let chat else { return nil }
        chats[chatID] = chat
        return chat
    }

    /// Telegram marks a story seen while it shows (StoryContentContext.markAsSeen); TDLib's openStory views and
    /// reads it, and closeStory ends the view.
    func open(_ key: StoryKey) {
        guard isCurrent, !isOffline, openedStory != key else { return }
        closeOpenedStory()
        openedStory = key
        enqueueVisibility { client in
            _ = try? await client.openStory(storyId: key.storyID, storyPosterChatId: key.chatID)
        }
    }

    func closeOpenedStory() {
        guard let key = openedStory else { return }
        openedStory = nil
        guard TDLib.shared.activeUpdateSource == source else { return }
        enqueueVisibility { client in
            _ = try? await client.closeStory(storyId: key.storyID, storyPosterChatId: key.chatID)
        }
    }

    /// Starts the file a story shows first, so the next story opens without waiting: a photo whole, a video its
    /// preload prefix (StoryContentContextImpl preloads the following items).
    func preloadMedia(of story: Story) {
        guard isCurrent, !isOffline else { return }
        let client = client
        switch story.content {
        case .storyContentPhoto(let content):
            guard let file = StoryMedia.photoFile(content.photo), !file.local.isDownloadingCompleted else { return }
            Task { _ = try? await client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            ) }
        case .storyContentVideo(let content):
            let video = content.video
            guard !video.video.local.isDownloadingCompleted, video.preloadPrefixSize > 0 else { return }
            Task {
                _ = try? await client.downloadFile(
                    fileId: video.video.id, limit: Int64(video.preloadPrefixSize), offset: 0, priority: 1,
                    synchronous: false,
                )
            }
        case .storyContentLive,
             .storyContentUnsupported:
            break
        }
    }

    /// The shown story's file goes before preloads.
    func prioritizeDownload(of file: File) {
        guard isCurrent, !isOffline, !file.local.isDownloadingCompleted else { return }
        let client = client
        Task {
            _ = try? await client.downloadFile(fileId: file.id, limit: 0, offset: 0, priority: 32, synchronous: false)
        }
    }

    func invalidate() {
        closeOpenedStory()
        storyRequests.values.forEach { $0.cancel() }
        activeStoryRequests.values.forEach { $0.cancel() }
        chatRequests.values.forEach { $0.cancel() }
        storyRequests.removeAll()
        activeStoryRequests.removeAll()
        chatRequests.removeAll()
        cancellables.removeAll()
        isRetired = true
    }

    private func enqueueVisibility(_ request: @escaping (TDLibClient) async -> Void) {
        let previous = visibilityRequests
        let client = client
        visibilityRequests = Task {
            await previous?.value
            await request(client)
        }
    }

    private func observeUpdates() {
        nc.scopedPublisher(&cancellables, for: .updateSupergroup) { [weak self] event in
            guard let self, event.source == source, isCurrent else { return }
            let group = event.value.supergroup
            let previous = viewListMemberStatuses.updateValue(group.status, forKey: group.id)
            if let previous, previous != group.status { viewListAccessChanged(supergroupID: group.id) }
        }
        nc.scopedPublisher(&cancellables, for: .updateSupergroupFullInfo) { [weak self] event in
            guard let self, event.source == source, isCurrent else { return }
            let id = event.value.supergroupId
            let allowed = event.value.supergroupFullInfo.canGetStatistics
            let previous = statisticsAccess.updateValue(allowed, forKey: id)
            if let previous, previous != allowed { viewListAccessChanged(supergroupID: id) }
        }
        nc.scopedPublisher(&cancellables, for: .updateStory) { [weak self] event in
            guard let self, event.source == source, isCurrent else { return }
            let story = event.value.story
            let key = StoryKey(chatID: story.posterChatId, storyID: story.id)
            guard stories[key] != nil else { return }
            stories[key] = story
            onStoryChanged?(story)
        }
        nc.scopedPublisher(&cancellables, for: .updateStoryDeleted) { [weak self] event in
            guard let self, event.source == source, isCurrent else { return }
            let key = StoryKey(chatID: event.value.storyPosterChatId, storyID: event.value.storyId)
            stories[key] = nil
            if openedStory == key { openedStory = nil }
            onStoryDeleted?(key)
        }
        nc.scopedPublisher(&cancellables, for: .updateChatActiveStories) { [weak self] event in
            guard let self, event.source == source, isCurrent else { return }
            onActiveStoriesChanged?(event.value.activeStories)
        }
        TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, source != self.source, !isRetired else { return }
                isRetired = true
                openedStory = nil
                onRetired?()
            }
            .store(in: &cancellables)
    }

    private func viewListAccessChanged(supergroupID: Int64) {
        for chat in chats.values {
            if case .chatTypeSupergroup(let info) = chat.type, info.supergroupId == supergroupID {
                viewListAccessGenerations[chat.id, default: 0] += 1
                onViewListAccessChanged?(chat.id)
            }
        }
    }
}

// MARK: - StoryMedia

enum StoryMedia {
    /// A story photo's largest size; stories are shown full screen.
    static func photoFile(_ photo: Photo) -> File? {
        photo.sizes.max { $0.width * $0.height < $1.width * $1.height }?.photo
    }
}
