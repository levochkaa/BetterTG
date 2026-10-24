// StoryViewerViewList.swift

import Foundation
import TDLibKit

// MARK: - StoryViewList

/// StoryItemSetViewListComponent for the account's own story: who viewed it, reacted to it, forwarded or reposted it
/// (`getStoryInteractions`), with Telegram's list and sort modes, search, header and empty states. Channel stories,
/// the reposts-first order and the Premium upgrade are left out.
enum StoryViewList {
    /// The tabs: everyone, or only contacts (`only_contacts`).
    enum ListMode: Equatable {
        case everyone
        case contacts
    }

    /// The order a user's story offers: reactions first (`prefer_with_reaction`), Telegram's default, or recent first.
    enum SortMode: Equatable {
        case reactionsFirst
        case recentFirst
    }

    struct Query: Equatable {
        var listMode = ListMode.everyone
        var sortMode = SortMode.reactionsFirst
        var text = ""
    }

    enum Kind: Equatable {
        /// A view, with the reaction the viewer chose.
        case view(reaction: ReactionType?)
        /// A forward of the story as a message.
        case forward(chatID: Int64, messageID: Int64)
        /// A repost as a story; `hasCaption` adds Telegram's " • commented".
        case repost(posterChatID: Int64, storyID: Int, hasCaption: Bool)
    }

    struct Item: Equatable {
        let actor: MessageSender
        let date: Int
        let kind: Kind

        var actorID: Int64 {
            switch actor {
            case .messageSenderUser(let user): user.userId
            case .messageSenderChat(let chat): chat.chatId
            }
        }
    }

    struct Page: Equatable {
        let totalCount: Int
        let totalReactionCount: Int
        let items: [Item]
        let nextOffset: String
    }

    /// What the list's header shows: the title, or the tabs in its place, the search field and the sort button.
    struct Header: Equatable {
        let title: String
        let showsTabs: Bool
        let showsSearch: Bool
        let showsSort: Bool
    }

    /// EngineStoryViewListContext's page size.
    static let pageSize = 50

    static func page(_ interactions: StoryInteractions) -> Page {
        Page(
            totalCount: interactions.totalCount,
            totalReactionCount: interactions.totalReactionCount,
            items: interactions.interactions.map { interaction in
                let kind: Kind =
                    switch interaction.type {
                    case .storyInteractionTypeView(let view):
                        .view(reaction: view.chosenReactionType)
                    case .storyInteractionTypeForward(let forward):
                        .forward(chatID: forward.message.chatId, messageID: forward.message.id)
                    case .storyInteractionTypeRepost(let repost):
                        .repost(
                            posterChatID: repost.story.posterChatId,
                            storyID: repost.story.id,
                            hasCaption: !repost.story.caption.text.isEmpty,
                        )
                    }
                return Item(actor: interaction.actorId, date: interaction.interactionDate, kind: kind)
            },
            nextOffset: interactions.nextOffset,
        )
    }

    /// The header's rules: the tabs and search appear from 20 viewers, the tabs only for a story everyone can see,
    /// and the sort button from 10 reactions among 20 viewers. Once the viewers have expired there is no list to
    /// search or sort. The title counts the viewers while some of them didn't react.
    static func header(story: Story, totalCount: Int?) -> Header {
        let info = story.interactionInfo
        let total = totalCount ?? info?.viewCount ?? 0
        let reactions = info?.reactionCount ?? 0
        let title =
            if info == nil, totalCount == nil {
                L10n.telegram("Story.ViewList.TitleEmpty")
            } else if total > 0, total > reactions {
                L10n.telegramPlural("Story.ViewList.ViewerCount", count: total)
            } else {
                L10n.telegram("Story.ViewList.TitleViewers")
            }
        guard story.canGetInteractions, !story.hasExpiredViewers else {
            return Header(title: title, showsTabs: false, showsSearch: false, showsSort: false)
        }
        let isPublic =
            if case .storyPrivacySettingsEveryone = story.privacySettings {
                true
            } else {
                false
            }
        let showsSearch = total >= 20
        return Header(
            title: title,
            showsTabs: showsSearch && isPublic,
            showsSearch: showsSearch,
            showsSort: reactions >= 10 && total >= 20,
        )
    }

    /// The empty list's text. Telegram offers Premium where an expired story's viewers were recorded; here the story
    /// says that the list became unavailable, as it does where nobody viewed it.
    static func emptyText(query: Query, story: Story) -> String {
        if !query.text.isEmpty { return L10n.telegram("Story.ViewList.EmptyTextSearch") }
        if query.listMode == .contacts { return L10n.telegram("Story.ViewList.EmptyTextContacts") }
        if story.hasExpiredViewers { return L10n.telegram("Story.Views.ViewsExpired") }
        return L10n.telegram("Story.Views.NoViews")
    }

    /// humanReadableStringForTimestamp with the message-seen strings: today or yesterday at a time, or the date and
    /// time, and " • commented" after a repost with a caption.
    static func subtitle(for item: Item, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(item.date))
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        var text =
            if calendar.isDate(date, inSameDayAs: now) {
                L10n.telegram("Chat.MessageSeenTimestamp.TodayAt", time)
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                      calendar.isDate(date, inSameDayAs: yesterday)
            {
                L10n.telegram("Chat.MessageSeenTimestamp.YesterdayAt", time)
            } else {
                L10n.telegram("Chat.MessageSeenTimestamp.Date", date.formatted(date: .abbreviated, time: .shortened))
            }
        if case .repost(_, _, true) = item.kind { text += L10n.telegram("Story.Views.Commented") }
        return text
    }
}

// MARK: - StoryViewListLoader

/// One query's list of interactions, loaded a page at a time; a new query starts over and drops answers to the old.
@MainActor final class StoryViewListLoader {
    typealias Fetch = (_ query: StoryViewList.Query, _ offset: String) async -> StoryViewList.Page?

    private(set) var query = StoryViewList.Query()
    private(set) var items = [StoryViewList.Item]()
    /// TDLib's approximate total for the query; nil until its first page arrives.
    private(set) var totalCount: Int?
    private(set) var totalReactionCount: Int?
    private(set) var hasMore = true
    private(set) var isLoading = false
    /// Whether the first page has arrived, or failed, for the current query.
    private(set) var isLoaded = false
    var onChange: (() -> Void)?

    private let fetch: Fetch
    private var nextOffset = ""
    private var generation = 0

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func load(_ query: StoryViewList.Query) {
        self.query = query
        generation += 1
        items = []
        totalCount = nil
        totalReactionCount = nil
        nextOffset = ""
        hasMore = true
        isLoading = false
        isLoaded = false
        onChange?()
        loadMore()
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        let generation = generation
        let query = query
        let offset = nextOffset
        Task { @MainActor [weak self] in
            let page = await self?.fetch(query, offset)
            guard let self, generation == self.generation else { return }
            isLoading = false
            isLoaded = true
            guard let page else {
                hasMore = false
                onChange?()
                return
            }
            items.append(contentsOf: page.items)
            totalCount = page.totalCount
            totalReactionCount = page.totalReactionCount
            nextOffset = page.nextOffset
            hasMore = !page.nextOffset.isEmpty && !page.items.isEmpty
            onChange?()
        }
    }
}
