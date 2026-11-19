// ChatListScopedSearch.swift

import Foundation
import TDLibKit
import UIKit

// MARK: - ChatListSearchScope

/// Where a chat list search looks, as the token before the query sets it (ChatListSearchContainerNode's archive and
/// folder tokens). Removing the token searches the main list.
enum ChatListSearchScope: Equatable {
    case main
    case archive
    case folder(id: Int, title: String, icon: FolderIcon?)

    var chatList: ChatList {
        switch self {
        case .main: .chatListMain
        case .archive: .chatListArchive
        case .folder(let id, _, _): .chatListFolder(ChatListFolder(chatFolderId: id))
        }
    }

    /// Whether the search keeps to some chats: the account's chats outside them and the chats it doesn't have, such
    /// as public channels and popular apps, stay out of the results.
    var isRestricted: Bool { self != .main }

    /// The field's token: Telegram's archive glyph, or the folder's own icon, before the name.
    @MainActor var token: UISearchToken? {
        switch self {
        case .main:
            nil
        case .archive:
            UISearchToken(icon: UIImage(named: "ChatList/SearchArchiveIcon"), text: L10n.telegram("ChatList.Archive"))
        case .folder(_, let title, let icon):
            UISearchToken(icon: icon?.image, text: title)
        }
    }

    /// The search a page opens: its folder's, or the archive's.
    @MainActor init(folder: CustomFolder) {
        self =
            switch folder.type {
            case .main: .main
            case .archive: .archive
            case .folder(let info, _): .folder(id: Int(info.id), title: folder.name, icon: folder.icon)
            }
    }

    /// Whether a chat belongs where the search looks; the main list's search keeps every chat it finds, as Telegram's.
    @MainActor func admits(_ chatID: Int64) -> Bool {
        guard isRestricted else { return true }
        return TelegramChatListStore.shared.belongs(chatID: chatID, to: chatList)
    }
}

// MARK: - ChatListMessageSearch

/// The messages a chat list search finds, a load at a time, newest first. The main list and the archive are TDLib's
/// own lists for searchMessages. A folder is not: the server's messages.searchGlobal takes only those two, so TDLib
/// refuses `chatListFolder`. A folder's search reads every chat's messages and keeps the folder's. When few of them are
/// the folder's and the folder holds few chats, it searches each of the folder's chats instead and merges them by
/// date. TDLib waits out a FLOOD_WAIT of up to a minute without a word, and a round that slow or refused goes back to
/// reading every chat. Flood limits count per method, so the two ways don't hold each other up.
@MainActor final class ChatListMessageSearch {
    // MARK: Private

    private enum Mode {
        /// searchMessages over the scope's own list.
        case list
        /// searchMessages over all chats, keeping the folder's.
        case everyChat
        /// searchChatMessages in each of the folder's chats, merged by date.
        case eachChat
    }

    private struct Key: Hashable {
        let chatID: Int64
        let messageID: Int64

        init(_ message: Message) {
            self.chatID = message.chatId
            self.messageID = message.id
        }
    }

    /// One chat's search: its next request's start and what it found that the merge hasn't taken yet, newest first.
    private struct ChatCursor {
        var fromMessageID: Int64 = 0
        var buffer = [Message]()
        var isExhausted = false
    }

    /// TDLib returns at most this many messages a request.
    private static let everyChatPageLimit = 100
    /// Requests one load makes over all chats before it shows what it found.
    private static let everyChatRequestsPerLoad = 4
    /// The messages read over all chats before judging how many are the folder's.
    private static let probeCount = 200
    /// Below this share of the folder's messages, each chat is searched on its own.
    private static let sparseShare = 0.1
    /// A folder of more chats keeps reading all chats: a round of its own searches costs a request per chat.
    private static let eachChatMaxChats = 40
    private static let eachChatConcurrency = 4
    private static let eachChatPageLimit = 50
    /// A round of the chats' own searches slower than this goes back to reading all chats.
    private static let eachChatRoundTimeout = Duration.seconds(6)

    // MARK: Internal

    let scope: ChatListSearchScope
    private(set) var hasMore = true

    private let client: TDLibClient
    private let query: String
    private let filter: SearchMessagesFilter?
    private let chatTypeFilter: SearchMessagesChatTypeFilter?
    private var mode: Mode
    private var offset = ""
    private var scannedCount = 0
    private var keptCount = 0
    /// The chats' own searches failed once; the search keeps reading all chats.
    private var eachChatFailed = false
    /// The date of the oldest message read over all chats. Everything newer is found, so the chats' own searches
    /// give only what is older.
    private var boundaryDate: Int?
    private var seen = Set<Key>()
    private var cursors = [Int64: ChatCursor]()
    private lazy var folderChatIDs = searchableFolderChatIDs()

    init(
        client: TDLibClient,
        scope: ChatListSearchScope,
        query: String,
        filter: SearchMessagesFilter?,
        chatTypeFilter: SearchMessagesChatTypeFilter?,
    ) {
        self.client = client
        self.scope = scope
        self.query = query
        self.filter = filter
        self.chatTypeFilter = chatTypeFilter
        self.mode =
            if case .folder = scope {
                .everyChat
            } else {
                .list
            }
    }

    /// Whether `lhs` comes after `rhs` in searchMessages' order: by date, then chat, then message, newest first.
    private static func isOlder(_ lhs: Message, than rhs: Message) -> Bool {
        (lhs.date, lhs.chatId, lhs.id) < (rhs.date, rhs.chatId, rhs.id)
    }

    /// The tasks' values, or nil when they take longer than `timeout`; TDLib can't take back a request it sent, so
    /// the late answers are dropped.
    private static func values<T>(of tasks: [Task<T, Never>], within timeout: Duration) async -> [T]? {
        await withCheckedContinuation { (continuation: CheckedContinuation<[T]?, Never>) in
            let once = ResumeOnce(continuation)
            Task { @MainActor in
                var values = [T]()
                for task in tasks {
                    await values.append(task.value)
                }
                once.resume(values)
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(nil)
            }
        }
    }

    /// The next messages in date order, `limit` of them where there are so many, or nil when TDLib failed before
    /// finding any.
    func loadMore(limit: Int) async -> [Message]? {
        guard hasMore else { return [] }
        switch mode {
        case .list: return await loadFromList(limit: limit)
        case .eachChat,
             .everyChat: return await loadFromFolder(limit: limit)
        }
    }

    private func loadFromList(limit: Int) async -> [Message]? {
        guard let found = try? await client.searchMessages(
            chatList: scope.chatList,
            query: query,
            offset: offset,
            limit: limit,
            filter: filter,
            chatTypeFilter: chatTypeFilter,
            minDate: 0,
            maxDate: 0,
        ) else {
            hasMore = false
            return nil
        }
        offset = found.nextOffset
        hasMore = !offset.isEmpty
        return taking(found.messages)
    }

    private func loadFromFolder(limit: Int) async -> [Message]? {
        var result = [Message]()
        var requests = 0
        while result.count < limit, hasMore, !Task.isCancelled {
            if mode == .eachChat {
                // Fills the load, ends the search, or goes back to reading all chats.
                result += await loadFromEachChat(limit: limit - result.count)
                continue
            }
            guard requests < Self.everyChatRequestsPerLoad else { break }
            requests += 1
            guard let found = try? await client.searchMessages(
                chatList: nil,
                query: query,
                offset: offset,
                limit: Self.everyChatPageLimit,
                filter: filter,
                chatTypeFilter: chatTypeFilter,
                minDate: 0,
                maxDate: 0,
            ) else {
                hasMore = false
                return result.isEmpty ? nil : result
            }
            offset = found.nextOffset
            hasMore = !offset.isEmpty
            scannedCount += found.messages.count
            if let last = found.messages.last { boundaryDate = last.date }
            let kept = found.messages.filter { scope.admits($0.chatId) }
            keptCount += kept.count
            result += taking(kept)
            if searchesEachChat() { startEachChat() }
        }
        return result
    }

    /// Few of the messages read are the folder's, and its chats are few enough to search one by one.
    private func searchesEachChat() -> Bool {
        guard !eachChatFailed, hasMore, scannedCount >= Self.probeCount,
              Double(keptCount) < Double(scannedCount) * Self.sparseShare
        else { return false }
        return !folderChatIDs.isEmpty && folderChatIDs.count <= Self.eachChatMaxChats
    }

    private func startEachChat() {
        cursors = Dictionary(uniqueKeysWithValues: folderChatIDs.map { ($0, ChatCursor()) })
        mode = .eachChat
    }

    /// Takes the newest message among the chats' heads until the load is full, searching a chat again when it has
    /// none left.
    private func loadFromEachChat(limit: Int) async -> [Message] {
        var result = [Message]()
        while result.count < limit, !Task.isCancelled {
            let empty = cursors.filter { $0.value.buffer.isEmpty && !$0.value.isExhausted }.map(\.key)
            if !empty.isEmpty {
                guard await fill(empty) else {
                    eachChatFailed = true
                    mode = .everyChat
                    cursors = [:]
                    hasMore = !offset.isEmpty
                    return result
                }
                // A chat whose found messages were all shown already searches again.
                continue
            }
            guard let newest = cursors.filter({ !$0.value.buffer.isEmpty }).max(by: {
                Self.isOlder($0.value.buffer[0], than: $1.value.buffer[0])
            }) else {
                hasMore = false
                return result
            }
            let message = cursors[newest.key, default: ChatCursor()].buffer.removeFirst()
            if seen.insert(Key(message)).inserted { result.append(message) }
        }
        return result
    }

    /// Searches the chats a few at a time; false when a round is too slow or the server asks to wait.
    private func fill(_ chatIDs: [Int64]) async -> Bool {
        for start in stride(from: 0, to: chatIDs.count, by: Self.eachChatConcurrency) {
            let chunk = Array(chatIDs[start..<min(start + Self.eachChatConcurrency, chatIDs.count)])
            let client = client
            let query = query
            let filter = filter
            let tasks = chunk.map { chatID in
                let from = cursors[chatID]?.fromMessageID ?? 0
                return Task { () -> Result<TDNativeFoundChatMessages, Error> in
                    do {
                        return try await .success(client.searchChatMessages(
                            chatId: chatID,
                            filter: filter,
                            fromMessageId: from,
                            limit: Self.eachChatPageLimit,
                            offset: 0,
                            query: query,
                            senderId: nil,
                            topicId: nil,
                        ))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            guard let answers = await Self.values(of: tasks, within: Self.eachChatRoundTimeout), !Task.isCancelled
            else { return false }
            for (chatID, answer) in zip(chunk, answers) {
                var cursor = cursors[chatID, default: ChatCursor()]
                switch answer {
                case .success(let found):
                    cursor.buffer += found.messages.filter { message in
                        !seen.contains(Key(message)) && boundaryDate.map { message.date <= $0 } ?? true
                    }
                    cursor.fromMessageID = found.nextFromMessageId
                    cursor.isExhausted = found.nextFromMessageId == 0 || found.messages.isEmpty
                case .failure(let error):
                    // Too Many Requests, once TDLib gave up waiting; a chat that fails otherwise is left out.
                    if (error as? TDLibError)?.code == 429 { return false }
                    cursor.isExhausted = true
                }
                cursors[chatID] = cursor
            }
        }
        return true
    }

    /// The folder's chats searchMessages would search: no secret chats, and only the chat type asked for.
    private func searchableFolderChatIDs() -> [Int64] {
        let store = TelegramChatListStore.shared
        return store.chatIDs(belongingTo: scope.chatList).filter { chatID in
            switch store.chatType(chatID: chatID) {
            case .chatTypePrivate?:
                allowsType(private: true, group: false, channel: false)
            case .chatTypeBasicGroup?:
                allowsType(private: false, group: true, channel: false)
            case .chatTypeSupergroup(let supergroup)?:
                allowsType(private: false, group: !supergroup.isChannel, channel: supergroup.isChannel)
            case .chatTypeSecret?,
                 nil:
                false
            }
        }
    }

    private func allowsType(private isPrivate: Bool, group: Bool, channel: Bool) -> Bool {
        switch chatTypeFilter {
        case nil: true
        case .searchMessagesChatTypeFilterPrivate?: isPrivate
        case .searchMessagesChatTypeFilterGroup?: group
        case .searchMessagesChatTypeFilterChannel?: channel
        // A community's chats are the server's to know.
        case .searchMessagesChatTypeFilterCommunity?: false
        }
    }

    /// The messages not shown yet, which are now.
    private func taking(_ messages: [Message]) -> [Message] {
        messages.filter { seen.insert(Key($0)).inserted }
    }
}

// MARK: - ResumeOnce

/// A continuation that the first of several callers resumes.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
