// TelegramChatListStore.swift

import Combine
import Foundation
import TDLibKit

/// Consumes TDLib's ordered update stream before UI notifications are dispatched.
/// No list membership is inferred from getChats or from a later getChat response.
@MainActor final class TelegramChatListStore {
    enum Change {
        case reset
        case folders
        case chats(Set<Int64>)
    }

    static let shared = TelegramChatListStore()

    let changes = PassthroughSubject<Change, Never>()
    private(set) var accountID: UUID?
    private(set) var clientID: Int32?
    private(set) var folderConfiguration: UpdateChatFolders?

    private var records = [Int64: ChatListRecord]()
    private var users = [Int64: User]()
    private var groups = [Int64: BasicGroup]()
    private var supergroups = [Int64: Supergroup]()

    func consume(_ update: Update, accountID: UUID, clientID: Int32) {
        if self.accountID != accountID || self.clientID != clientID {
            self.accountID = accountID
            self.clientID = clientID
            records = [:]
            users = [:]
            groups = [:]
            supergroups = [:]
            folderConfiguration = nil
            changes.send(.reset)
        }
        switch update {
        case .updateChatFolders(let value):
            folderConfiguration = value
            changes.send(.folders)
        case .updateNewChat(let value):
            records[value.chat.id] = ChatListRecord(value.chat)
            changes.send(.chats([value.chat.id]))
        case .updateUser(let value):
            users[value.user.id] = value.user
            changedPeers { record in
                if case .chatTypePrivate(let peer) = record.type { peer.userId == value.user.id } else { false }
            }
        case .updateBasicGroup(let value):
            groups[value.basicGroup.id] = value.basicGroup
            changedPeers { record in
                if case .chatTypeBasicGroup(let peer) = record.type { peer.basicGroupId == value.basicGroup.id }
                else { false }
            }
        case .updateSupergroup(let value):
            supergroups[value.supergroup.id] = value.supergroup
            changedPeers { record in
                if case .chatTypeSupergroup(let peer) = record.type { peer.supergroupId == value.supergroup.id }
                else { false }
            }
        case .updateChatPosition(let value):
            mutate(value.chatId) { $0.setPosition(value.position) }
        case .updateChatLastMessage(let value):
            mutate(value.chatId) { $0.lastMessage = value.lastMessage
                $0.positions = value.positions
            }
        case .updateChatDraftMessage(let value):
            mutate(value.chatId) { $0.draftMessage = value.draftMessage
                $0.positions = value.positions
            }
        case .updateChatTitle(let value):
            mutate(value.chatId) { $0.title = value.title }
        case .updateChatPhoto(let value):
            mutate(value.chatId) { $0.photo = value.photo }
        case .updateChatReadInbox(let value):
            mutate(value.chatId) { $0.unreadCount = value.unreadCount
                $0.lastReadInboxMessageId = value.lastReadInboxMessageId
            }
        case .updateChatReadOutbox(let value):
            mutate(value.chatId) { $0.lastReadOutboxMessageId = value.lastReadOutboxMessageId }
        case .updateChatNotificationSettings(let value):
            mutate(value.chatId) { $0.notificationSettings = value.notificationSettings }
        case .updateChatIsMarkedAsUnread(let value):
            mutate(value.chatId) { $0.isMarkedAsUnread = value.isMarkedAsUnread }
        case .updateChatViewAsTopics(let value):
            mutate(value.chatId) { $0.viewAsTopics = value.viewAsTopics }
        case .updateChatPermissions(let value):
            mutate(value.chatId) { $0.permissions = value.permissions }
        case .updateChatAccentColors(let value):
            mutate(value.chatId) {
                $0.accentColorId = value.accentColorId
                $0.backgroundCustomEmojiId = value.backgroundCustomEmojiId
                $0.profileAccentColorId = value.profileAccentColorId
                $0.profileBackgroundCustomEmojiId = value.profileBackgroundCustomEmojiId
                $0.upgradedGiftColors = value.upgradedGiftColors
            }
        case .updateChatAddedToList(let value):
            mutate(value.chatId) {
                if !$0.chatLists.contains(value.chatList) { $0.chatLists.append(value.chatList) }
            }
        case .updateChatRemovedFromList(let value):
            mutate(value.chatId) {
                $0.chatLists.removeAll { $0 == value.chatList }
                $0.positions.removeAll { $0.list == value.chatList }
            }
        case .updateChatUnreadMentionCount(let value):
            mutate(value.chatId) { $0.unreadMentionCount = value.unreadMentionCount }
        case .updateChatUnreadReactionCount(let value):
            mutate(value.chatId) { $0.unreadReactionCount = value.unreadReactionCount }
        case .updateChatUnreadPollVoteCount(let value):
            mutate(value.chatId) { $0.unreadPollVoteCount = value.unreadPollVoteCount }
        case .updateChatHasProtectedContent(let value):
            mutate(value.chatId) { $0.hasProtectedContent = value.hasProtectedContent }
        case .updateChatAvailableReactions(let value):
            mutate(value.chatId) { $0.availableReactions = value.availableReactions }
        case .updateChatMessageSender(let value):
            mutate(value.chatId) { $0.messageSenderId = value.messageSenderId }
        case .updateChatDefaultDisableNotification(let value):
            mutate(value.chatId) { $0.defaultDisableNotification = value.defaultDisableNotification }
        case .updateChatHasWelcomeMessages(let value):
            mutate(value.chatId) { $0.hasWelcomeMessages = value.hasWelcomeMessages }
        case .updateChatIsTranslatable(let value):
            mutate(value.chatId) { $0.isTranslatable = value.isTranslatable }
        case .updateChatHasScheduledMessages(let value):
            mutate(value.chatId) { $0.hasScheduledMessages = value.hasScheduledMessages }
        case .updateChatMessageAutoDeleteTime(let value):
            mutate(value.chatId) { $0.messageAutoDeleteTime = value.messageAutoDeleteTime }
        case .updateChatActionBar(let value):
            mutate(value.chatId) { $0.actionBar = value.actionBar }
        case .updateChatReplyMarkup(let value):
            mutate(value.chatId) { $0.replyMarkupMessageId = value.replyMarkupMessage?.id ?? 0 }
        case .updateChatVideoChat(let value):
            mutate(value.chatId) { $0.videoChat = value.videoChat }
        case .updateChatPendingJoinRequests(let value):
            mutate(value.chatId) { $0.pendingJoinRequests = value.pendingJoinRequests }
        case .updateChatTheme(let value):
            mutate(value.chatId) { $0.theme = value.theme }
        case .updateChatBackground(let value):
            mutate(value.chatId) { $0.background = value.background }
        case .updateChatEmojiStatus(let value):
            mutate(value.chatId) { $0.emojiStatus = value.emojiStatus }
        case .updateChatBlockList(let value):
            mutate(value.chatId) { $0.blockList = value.blockList }
        case .updateChatBusinessBotManageBar(let value):
            mutate(value.chatId) { $0.businessBotManageBar = value.businessBotManageBar }
        default:
            break
        }
    }

    func chatIDs(in list: ChatList) -> [Int64] {
        records.values
            .compactMap { record -> (id: Int64, order: Int64)? in
                guard let position = record.positions.first(where: { $0.list == list && $0.order != 0 })
                else { return nil }
                return (record.id, position.order)
            }
            .sorted { $0.order == $1.order ? $0.id > $1.id : $0.order > $1.order }
            .map(\.id)
    }

    func customChat(id: Int64, in list: ChatList) -> CustomChat? {
        guard let record = records[id],
              let position = record.positions.first(where: { $0.list == list && $0.order != 0 }),
              let type = peerType(for: record)
        else { return nil }
        return CustomChat(
            chat: record.snapshot,
            position: position,
            unreadCount: record.unreadCount,
            type: type,
            lastMessage: record.lastMessage,
            draftMessage: record.draftMessage,
        )
    }

    /// Whether `customChat(id:in:)` would return the chat, without building it.
    func listsChat(id: Int64, in list: ChatList) -> Bool {
        guard let record = records[id], record.positions.contains(where: { $0.list == list && $0.order != 0 })
        else { return false }
        return peerType(for: record) != nil
    }

    private func peerType(for record: ChatListRecord) -> CustomChat.CustomChatType? {
        switch record.type {
        case .chatTypePrivate(let peer):
            guard let user = users[peer.userId] else { return nil }
            if case .userTypeBot = user.type { return .bot(user) }
            return .user(user)
        case .chatTypeBasicGroup(let peer):
            return groups[peer.basicGroupId].map(CustomChat.CustomChatType.group)
        case .chatTypeSupergroup(let peer):
            return supergroups[peer.supergroupId].map(CustomChat.CustomChatType.supergroup)
        case .chatTypeSecret:
            return nil
        }
    }

    private func mutate(_ id: Int64, _ body: (inout ChatListRecord) -> Void) {
        guard var record = records[id] else { return }
        body(&record)
        records[id] = record
        changes.send(.chats([id]))
    }

    private func changedPeers(where matches: (ChatListRecord) -> Bool) {
        let ids = Set(records.values.filter(matches).map(\.id))
        if !ids.isEmpty { changes.send(.chats(ids)) }
    }
}
