// RootChatProjection.swift

import Foundation
import TDLibKitDynamic

/// A current-value projection, retained only by active reads. Repeated updates
/// replace fields; they never append to a feed journal.
@MainActor final class RootChatProjection {
    struct Stamp<Value> {
        let revision: UInt64
        let value: Value

        func replacing(_ original: Value, after boundary: UInt64) -> Value {
            revision > boundary ? value : original
        }
    }

    struct Delta {
        var snapshot: Stamp<Chat>?
        var title: Stamp<String>?
        var photo: Stamp<ChatPhotoInfo?>?
        var accent: Stamp<UpdateChatAccentColors>?
        var topics: Stamp<Bool>?
        var notifications: Stamp<ChatNotificationSettings>?
        var marked: Stamp<Bool>?
        var unread: Stamp<UpdateChatReadInbox>?
        var last: Stamp<Message?>?
        var draft: Stamp<DraftMessage?>?
        var positions: Stamp<[ChatPosition]>?
        var partialPositions = [ChatList: Stamp<ChatPosition>]()

        mutating func replacePositions(_ value: [ChatPosition], revision: UInt64) {
            positions = Stamp(revision: revision, value: value)
            partialPositions.removeAll()
        }

        func positions(over original: [ChatPosition], after boundary: UInt64) -> [ChatPosition] {
            var result = positions?.replacing(original, after: boundary) ?? original
            for stamp in partialPositions.values.sorted(by: { $0.revision < $1.revision })
                where stamp.revision > boundary
            {
                result.removeAll { $0.list == stamp.value.list }
                if stamp.value.order != 0 { result.append(stamp.value) }
            }
            return result.filter { $0.order != 0 }
        }

        func applying(to original: Chat, after boundary: UInt64) -> Chat {
            let base = snapshot?.replacing(original, after: boundary) ?? original
            let boundary = max(boundary, snapshot?.revision ?? 0)
            let colors = accent.flatMap { $0.revision > boundary ? $0.value : nil }
            let read = unread.flatMap { $0.revision > boundary ? $0.value : nil }
            return Chat(
                accentColorId: colors?.accentColorId ?? base.accentColorId,
                actionBar: base.actionBar, availableReactions: base.availableReactions, background: base.background,
                backgroundCustomEmojiId: colors?.backgroundCustomEmojiId ?? base.backgroundCustomEmojiId,
                blockList: base.blockList, businessBotManageBar: base.businessBotManageBar,
                canBeDeletedForAllUsers: base.canBeDeletedForAllUsers,
                canBeDeletedOnlyForSelf: base.canBeDeletedOnlyForSelf,
                canBeReported: base.canBeReported, chatLists: base.chatLists, clientData: base.clientData,
                defaultDisableNotification: base.defaultDisableNotification,
                draftMessage: draft.map { $0.replacing(base.draftMessage, after: boundary) } ?? base.draftMessage,
                emojiStatus: base.emojiStatus, hasProtectedContent: base.hasProtectedContent,
                hasScheduledMessages: base.hasScheduledMessages,
                id: base.id,
                isMarkedAsUnread: marked?.replacing(base.isMarkedAsUnread, after: boundary) ?? base.isMarkedAsUnread,
                isTranslatable: base.isTranslatable,
                lastMessage: last.map { $0.replacing(base.lastMessage, after: boundary) } ?? base.lastMessage,
                lastReadInboxMessageId: read?.lastReadInboxMessageId ?? base.lastReadInboxMessageId,
                lastReadOutboxMessageId: base.lastReadOutboxMessageId,
                messageAutoDeleteTime: base.messageAutoDeleteTime,
                messageSenderId: base.messageSenderId,
                notificationSettings: notifications?.replacing(base.notificationSettings, after: boundary) ?? base
                    .notificationSettings,
                pendingJoinRequests: base.pendingJoinRequests, permissions: base.permissions,
                photo: photo.map { $0.replacing(base.photo, after: boundary) } ?? base.photo,
                positions: positions(over: base.positions, after: boundary),
                profileAccentColorId: colors?.profileAccentColorId ?? base.profileAccentColorId,
                profileBackgroundCustomEmojiId: colors?.profileBackgroundCustomEmojiId ?? base
                    .profileBackgroundCustomEmojiId,
                replyMarkupMessageId: base.replyMarkupMessageId, theme: base.theme,
                title: title?.replacing(base.title, after: boundary) ?? base.title, type: base.type,
                unreadCount: read?.unreadCount ?? base.unreadCount, unreadMentionCount: base.unreadMentionCount,
                unreadPollVoteCount: base.unreadPollVoteCount, unreadReactionCount: base.unreadReactionCount,
                upgradedGiftColors: colors.map(\.upgradedGiftColors) ?? base.upgradedGiftColors,
                videoChat: base.videoChat,
                viewAsTopics: topics?.replacing(base.viewAsTopics, after: boundary) ?? base.viewAsTopics,
            )
        }
    }

    @MainActor final class Lease {
        private(set) var isValid = true

        fileprivate let id = UUID()
        fileprivate let chatID: Int64?

        private var deltas = [Int64: Delta]()
        private var users = [Int64: Stamp<User>]()
        private var userIDs = Set<Int64>()
        private var rows = [ObjectIdentifier: (raw: UInt64, peer: UInt64)]()
        private var lists = [ChatList: UInt64]()

        #if DEBUG
            var debugRetainedChatCount: Int { deltas.count }
            var debugRetainedUserCount: Int { users.count }
        #endif

        fileprivate init(chatID: Int64?) { self.chatID = chatID }

        /// Registered immediately before getUser. Earlier user deltas precede
        /// that read and must not override its response.
        func watchUser(_ id: Int64) {
            guard isValid else { return }
            userIDs.insert(id)
        }

        func beginList(_ list: ChatList, revision: UInt64) {
            guard isValid else { return }
            lists[list] = revision
        }

        func track(_ chat: CustomChat, raw: UInt64, peer: UInt64) {
            guard isValid else { return }
            rows[ObjectIdentifier(chat)] = (raw, peer)
            project(chat)
        }

        func project(_ chat: Chat, after revision: UInt64) -> Chat {
            deltas[chat.id]?.applying(to: chat, after: revision) ?? chat
        }

        func project(_ chat: CustomChat) {
            guard isValid, let baseline = rows[ObjectIdentifier(chat)] else { return }
            chat.chat = project(chat.chat, after: baseline.raw)
            chat.unreadCount = chat.chat.unreadCount
            chat.lastMessage = chat.chat.lastMessage
            chat.draftMessage = chat.chat.draftMessage
            chat.position = RootChatInsertion.position(in: chat.chat.positions, for: chat.position.list)
            if case .chatTypePrivate(let peer) = chat.chat.type,
               let user = users[peer.userId], user.revision > baseline.peer
            {
                chat.updatePrivateUser(user.value)
            }
        }

        /// Missing positive intents are hydrated after atomic installation, using
        /// the new exact folder owner. No extra await can reopen the commit gap.
        func reconcile(_ folders: [CustomFolder]) -> [(Int64, ChatPosition)] {
            guard isValid else { return [] }
            var insertions = [(Int64, ChatPosition)]()
            for folder in folders {
                for chat in folder.chats {
                    project(chat)
                }
                folder.chats.removeAll { $0.position.order == 0 }
                guard let boundary = lists[folder.chatList] else { continue }
                for (id, delta) in deltas {
                    guard !folder.chats.contains(where: { $0.id == id }),
                          let position = delta.positions(over: [], after: boundary)
                              .first(where: { $0.list == folder.chatList })
                    else { continue }
                    insertions.append((id, position))
                }
            }
            return insertions
        }

        fileprivate func record(_ update: Update, revision: UInt64) {
            func stamp<T>(_ value: T) -> Stamp<T> { Stamp(revision: revision, value: value) }
            switch update {
            case .updateNewChat(let value):
                modify(value.chat.id) {
                    $0.snapshot = stamp(value.chat)
                    $0.replacePositions(value.chat.positions, revision: revision)
                }
            case .updateChatPosition(let value):
                modify(value.chatId) { $0.partialPositions[value.position.list] = stamp(value.position) }
            case .updateChatLastMessage(let value):
                modify(value.chatId) {
                    $0.last = stamp(value.lastMessage)
                    $0.replacePositions(value.positions, revision: revision)
                }
            case .updateChatDraftMessage(let value):
                modify(value.chatId) {
                    $0.draft = stamp(value.draftMessage)
                    $0.replacePositions(value.positions, revision: revision)
                }
            case .updateChatReadInbox(let value):
                modify(value.chatId) { $0.unread = stamp(value) }
            case .updateChatTitle(let value):
                modify(value.chatId) { $0.title = stamp(value.title) }
            case .updateChatPhoto(let value):
                modify(value.chatId) { $0.photo = stamp(value.photo) }
            case .updateChatAccentColors(let value):
                modify(value.chatId) { $0.accent = stamp(value) }
            case .updateChatViewAsTopics(let value):
                modify(value.chatId) { $0.topics = stamp(value.viewAsTopics) }
            case .updateChatNotificationSettings(let value):
                modify(value.chatId) {
                    $0.notifications = stamp(value.notificationSettings)
                }
            case .updateChatIsMarkedAsUnread(let value):
                modify(value.chatId) {
                    $0.marked = stamp(value.isMarkedAsUnread)
                }
            case .updateUser(let value):
                if userIDs.contains(value.user.id) { users[value.user.id] = stamp(value.user) }
            default: break
            }
        }

        fileprivate func close() {
            isValid = false
            deltas.removeAll()
            users.removeAll()
            userIDs.removeAll()
            rows.removeAll()
            lists.removeAll()
        }

        private func modify(_ id: Int64, _ body: (inout Delta) -> Void) {
            guard chatID == nil || chatID == id else { return }
            body(&deltas[id, default: Delta()])
        }
    }

    private(set) var revision: UInt64 = 0

    private var leases = [UUID: Lease]()

    #if DEBUG
        var debugActiveReadCount: Int { leases.count }
    #endif

    func begin(chatID: Int64? = nil) -> Lease {
        let lease = Lease(chatID: chatID)
        leases[lease.id] = lease
        return lease
    }

    func finish(_ lease: Lease) {
        leases[lease.id] = nil
        lease.close()
    }

    func invalidate() {
        for lease in leases.values {
            lease.close()
        }
        leases.removeAll()
    }

    func record(_ update: Update) {
        revision &+= 1
        for lease in leases.values {
            lease.record(update, revision: revision)
        }
    }
}
