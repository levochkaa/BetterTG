// TelegramChatListStore.swift

import Combine
import Foundation
import TDLibKit

// MARK: - TelegramChatListStore

/// Consumes TDLib's ordered update stream before UI notifications are dispatched.
/// No list membership is inferred from getChats or from a later getChat response.
@MainActor final class TelegramChatListStore {
    enum Change {
        case reset
        case folders
        case chats(Set<Int64>)
    }

    /// A person, basic group or supergroup whose chats a peer update redraws.
    private enum PeerKey: Hashable {
        case user(Int64)
        case basicGroup(Int64)
        case supergroup(Int64)
    }

    static let shared = TelegramChatListStore()

    let changes = PassthroughSubject<Change, Never>()
    /// A chat's online member count changed (`updateChatOnlineMemberCount`, sent while the chat is open).
    let onlineMemberCountChanges = PassthroughSubject<Int64, Never>()
    private(set) var accountID: UUID?
    private(set) var clientID: Int32?
    private(set) var folderConfiguration: UpdateChatFolders?

    private var records = [Int64: ChatListRecord]()
    /// The chats of each peer, so a peer update finds them without going through every chat. A chat's type never
    /// changes, so the index is set once per chat.
    private var chatIDsByPeer = [PeerKey: Set<Int64>]()
    private var users = [Int64: User]()
    private var groups = [Int64: BasicGroup]()
    private var supergroups = [Int64: Supergroup]()
    /// TDLib names communities only by updateCommunity; service messages about them need the name.
    private var communityNames = [Int64: String]()
    private var onlineMemberCounts = [Int64: Int]()

    /// A person's update redraws their private chat (not a secret one); a group's, its chat.
    private static func peerKey(of record: ChatListRecord) -> PeerKey? {
        switch record.type {
        case .chatTypePrivate(let peer): .user(peer.userId)
        case .chatTypeBasicGroup(let peer): .basicGroup(peer.basicGroupId)
        case .chatTypeSupergroup(let peer): .supergroup(peer.supergroupId)
        case .chatTypeSecret: nil
        }
    }

    /// The chat's online members as TDLib last reported them for this client; 0 when unknown.
    func onlineMemberCount(chatID: Int64, clientID: Int32) -> Int {
        self.clientID == clientID ? onlineMemberCounts[chatID] ?? 0 : 0
    }

    func consume(_ update: Update, accountID: UUID, clientID: Int32) {
        if self.accountID != accountID || self.clientID != clientID {
            self.accountID = accountID
            self.clientID = clientID
            records = [:]
            chatIDsByPeer = [:]
            users = [:]
            groups = [:]
            supergroups = [:]
            communityNames = [:]
            onlineMemberCounts = [:]
            folderConfiguration = nil
            changes.send(.reset)
        }
        switch update {
        case .updateChatFolders(let value):
            folderConfiguration = value
            changes.send(.folders)
        case .updateNewChat(let value):
            let record = ChatListRecord(value.chat)
            records[value.chat.id] = record
            if let key = Self.peerKey(of: record) { chatIDsByPeer[key, default: []].insert(value.chat.id) }
            changes.send(.chats([value.chat.id]))
        case .updateUser(let value):
            users[value.user.id] = value.user
            ChatListSenderNames.shared.receive(value.user, clientID: clientID)
            changedPeers(.user(value.user.id))
        case .updateUserStatus(let value):
            // ChatListItem's online marker follows the person's presence.
            guard let user = users[value.userId] else { break }
            users[value.userId] = user.replacingStatus(value.status)
            changedPeers(.user(value.userId))
        case .updateBasicGroup(let value):
            groups[value.basicGroup.id] = value.basicGroup
            changedPeers(.basicGroup(value.basicGroup.id))
        case .updateSupergroup(let value):
            supergroups[value.supergroup.id] = value.supergroup
            changedPeers(.supergroup(value.supergroup.id))
        case .updateCommunity(let value):
            communityNames[value.community.id] = value.community.name
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
        case .updateChatAction(let value):
            ChatListActivities.shared.receive(value, clientID: clientID)
        case .updateChatOnlineMemberCount(let value):
            onlineMemberCounts[value.chatId] = value.onlineMemberCount
            onlineMemberCountChanges.send(value.chatId)
        case .updateDefaultReactionType(let value):
            DefaultReactionType.shared.receive(value.reactionType, clientID: clientID)
        case .updateActiveEmojiReactions(let value):
            DefaultReactionType.shared.receive(activeEmojis: value.emojis, clientID: clientID)
        case .updateReactionNotificationSettings(let value):
            ReactionNotificationSettingsStore.shared.receive(value.notificationSettings, clientID: clientID)
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

    /// MediaAutoDownloadPeerType for a message in the chat: a contact's or another private chat, a group (a contact
    /// writing there counts as a contact, as shouldDownloadMediaAutomatically does) or a channel. A chat TDLib hasn't
    /// sent counts as another private chat.
    func autoDownloadPeerType(chatID: Int64, sender: MessageSender?, clientID: Int32) -> MediaAutoDownload.PeerType {
        guard self.clientID == clientID, let record = records[chatID] else { return .otherPrivate }
        func isContact(_ sender: MessageSender?) -> Bool {
            guard case .messageSenderUser(let user) = sender else { return false }
            return users[user.userId]?.isContact == true
        }
        switch record.type {
        case .chatTypePrivate(let value):
            return users[value.userId]?.isContact == true ? .contact : .otherPrivate
        case .chatTypeSecret(let value):
            return users[value.userId]?.isContact == true ? .contact : .otherPrivate
        case .chatTypeBasicGroup:
            return isContact(sender) ? .contact : .group
        case .chatTypeSupergroup(let value):
            if value.isChannel { return .channel }
            return isContact(sender) ? .contact : .group
        }
    }

    /// The community's name for this client, nil until TDLib has sent it.
    func communityName(_ id: Int64, clientID: Int32) -> String? {
        guard self.clientID == clientID else { return nil }
        return communityNames[id]
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

    /// The list's pinned chats in TDLib's order, including chats the list cannot show, such as secret chats.
    func pinnedChatIDs(in list: ChatList) -> [Int64] {
        records.values
            .compactMap { record -> (id: Int64, order: Int64)? in
                guard let position = record.positions.first(where: { $0.list == list && $0.order != 0 }),
                      position.isPinned
                else { return nil }
                return (record.id, position.order)
            }
            .sorted { $0.order == $1.order ? $0.id > $1.id : $0.order > $1.order }
            .map(\.id)
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
        case .chatTypeSecret(let peer):
            // Telegram lists a secret chat as a row for its user, marked with a lock (`ChatListItem`).
            return users[peer.userId].map(CustomChat.CustomChatType.user)
        }
    }

    private func mutate(_ id: Int64, _ body: (inout ChatListRecord) -> Void) {
        guard var record = records[id] else { return }
        body(&record)
        records[id] = record
        changes.send(.chats([id]))
    }

    private func changedPeers(_ key: PeerKey) {
        guard let ids = chatIDsByPeer[key], !ids.isEmpty else { return }
        changes.send(.chats(ids))
    }
}

// MARK: - ReactionNotificationSettingsStore

/// TDLib's `updateReactionNotificationSettings`, which has no getter: who may notify the user about reactions to
/// their messages and stories.
@MainActor final class ReactionNotificationSettingsStore {
    static let shared = ReactionNotificationSettingsStore()

    let changes = PassthroughSubject<Void, Never>()

    private var clientID: Int32?
    private var value: TDNativeReactionNotificationSettings?

    func receive(_ settings: TDNativeReactionNotificationSettings, clientID: Int32) {
        self.clientID = clientID
        value = settings
        changes.send()
    }

    func settings(for client: TDLibClient) -> TDNativeReactionNotificationSettings? {
        clientID == client.id ? value : nil
    }
}

// MARK: - DefaultReactionType

/// The account's quick reaction (TDLib's `updateDefaultReactionType`, Telegram's reactionSettings.quickReaction),
/// which a double tap on a message toggles.
@MainActor final class DefaultReactionType {
    static let shared = DefaultReactionType()

    /// The quick reaction or the active reactions changed.
    let changes = PassthroughSubject<Void, Never>()

    private var clientID: Int32?
    private var value: ReactionType?
    private var activeEmojisClientID: Int32?
    private var activeEmojis = [String]()

    func receive(_ type: ReactionType, clientID: Int32) {
        self.clientID = clientID
        value = type
        changes.send()
    }

    /// `updateActiveEmojiReactions`: the emoji reactions anyone can choose, which a quick reaction is chosen from.
    func receive(activeEmojis: [String], clientID: Int32) {
        activeEmojisClientID = clientID
        self.activeEmojis = activeEmojis
        changes.send()
    }

    func activeEmojis(for client: TDLibClient) -> [String] {
        activeEmojisClientID == client.id ? activeEmojis : []
    }

    /// The client's quick reaction, or 👍 as Telegram's default until TDLib names one.
    func type(for client: TDLibClient) -> ReactionType {
        guard clientID == client.id, let value else { return .reactionTypeEmoji(.init(emoji: "👍")) }
        return value
    }
}

extension User {
    /// The same person with another presence, as `updateUserStatus` reports it.
    func replacingStatus(_ status: UserStatus) -> User {
        User(
            accentColorId: accentColorId, activeStoryState: activeStoryState,
            addedToAttachmentMenu: addedToAttachmentMenu, backgroundCustomEmojiId: backgroundCustomEmojiId,
            emojiStatus: emojiStatus, firstName: firstName, haveAccess: haveAccess, id: id,
            isCloseFriend: isCloseFriend, isContact: isContact, isMutualContact: isMutualContact, isPremium: isPremium,
            isSupport: isSupport, languageCode: languageCode, lastName: lastName,
            paidMessageStarCount: paidMessageStarCount, phoneNumber: phoneNumber,
            profileAccentColorId: profileAccentColorId, profileBackgroundCustomEmojiId: profileBackgroundCustomEmojiId,
            profilePhoto: profilePhoto, restrictionInfo: restrictionInfo, restrictsNewChats: restrictsNewChats,
            status: status, type: type, upgradedGiftColors: upgradedGiftColors, usernames: usernames,
            verificationStatus: verificationStatus,
        )
    }

    /// PeerUtils' isServicePeer: Telegram's notifications, Replies and Verification Codes accounts.
    var isServicePeer: Bool {
        [777_000, 333_000, 708_513, 1_271_266_957, 489_000].contains(id)
    }

    /// ChatListItem's online marker: a person (not a service account, support or a bot) whose presence is online
    /// right now.
    var showsOnlineMarker: Bool {
        guard canShowOnlineMarker, case .userStatusOnline(let online) = status else { return false }
        return TimeInterval(online.expires) > Date().timeIntervalSince1970
    }

    var canShowOnlineMarker: Bool {
        guard !isSupport, !isServicePeer, case .userTypeRegular = type else { return false }
        return true
    }
}
