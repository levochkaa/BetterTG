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
    var onRetired: (() -> Void)?

    private(set) var isRetired = false
    #if DEBUG
        /// The UI probe's session: it answers from seeded stories, chats and story lists, and nothing reaches TDLib.
        private(set) var isOffline = false
        private var offlineActiveStories = [Int64: ChatActiveStories]()
        /// The probe's interactions with the account's stories, by story, newest first, and its contacts.
        private var offlineInteractions = [Int: [StoryInteraction]]()
        private var offlineContactIDs = Set<Int64>()
    #else
        let isOffline = false
    #endif

    private var stories = [StoryKey: Story]()
    private var storyRequests = [StoryKey: Task<Story?, Never>]()
    private var activeStoryRequests = [Int64: Task<ChatActiveStories?, Never>]()
    private var chats = [Int64: Chat]()
    private var chatRequests = [Int64: Task<Chat?, Never>]()
    private var openedStory: StoryKey?
    /// openStory and closeStory reach TDLib in the order the viewer shows and leaves stories.
    private var visibilityRequests: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var isCurrent: Bool {
        !isRetired && TDLib.shared.activeUpdateSource == source
    }

    init?(client: TDLibClient) {
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id else { return nil }
        self.source = source
        self.client = client
        self.vodRanges = TDLib.shared.vodRanges
        self.accountUserID = TDLib.shared.activeAccount?.userID
        observeUpdates()
    }

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

    /// getStoryInteractions for one of the account's stories, a page of `query` from `offset`.
    func storyInteractions(storyID: Int, query: StoryViewList.Query, offset: String) async -> StoryViewList.Page? {
        #if DEBUG
            if isOffline { return offlineInteractionPage(storyID: storyID, query: query, offset: offset) }
        #endif
        guard isCurrent,
              let interactions = try? await client.getStoryInteractions(
                  limit: StoryViewList.pageSize,
                  offset: offset,
                  onlyContacts: query.listMode == .contacts,
                  preferForwards: false,
                  preferWithReaction: query.sortMode == .reactionsFirst,
                  query: query.text,
                  storyId: storyID,
              ),
              isCurrent
        else { return nil }
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

    #if DEBUG
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
            if query.sortMode == .reactionsFirst {
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

    private func enqueueVisibility(_ request: @escaping (TDLibClient) async -> Void) {
        let previous = visibilityRequests
        let client = client
        visibilityRequests = Task {
            await previous?.value
            await request(client)
        }
    }

    private func observeUpdates() {
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
}

// MARK: - StoryMedia

enum StoryMedia {
    /// A story photo's largest size; stories are shown full screen.
    static func photoFile(_ photo: Photo) -> File? {
        photo.sizes.max { $0.width * $0.height < $1.width * $1.height }?.photo
    }
}
