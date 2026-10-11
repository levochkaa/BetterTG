// RichNotificationTarget.swift

import Foundation
import TDLibKit

/// The relay identifies an ordinary cloud message, not a local or scheduled ID.
/// Account and peer validation precede any use of a notification's content.
struct RichNotificationTarget: Equatable {
    let accountID: Int64
    let peer: RichNotificationPeerReference
    let messageID: Int64

    /// Pinned TDLib DialogId.cpp: cloud peer IDs have disjoint chat-ID mappings.
    /// Keep monoforum IDs valid; only arithmetic overflow is rejected here.
    var expectedChatID: Int64? {
        switch peer.kind {
        case .privateChat: return peer.id
        case .basicGroup: return -peer.id
        case .supergroup:
            let result = Int64(-1_000_000_000_000).subtractingReportingOverflow(peer.id)
            return result.overflow ? nil : result.partialValue
        }
    }

    init?(accountID: Int64?, peer: RichNotificationPeerReference, serverMessageID: Int64?) {
        guard let accountID, accountID > 0, peer.id > 0,
              let serverMessageID, serverMessageID > 0, serverMessageID <= Int64(Int32.max)
        else { return nil }
        self.accountID = accountID
        self.peer = peer
        // TDLib MessageId.h: ordinary server IDs occupy the high bits; the
        // low20 bits also encode local/scheduled variants and must be zero.
        self.messageID = serverMessageID << 20
    }

    func matches(accountUserID: Int64?) -> Bool {
        accountUserID == accountID
    }

    func matches(chat: Chat, requestedChatID: Int64) -> Bool {
        matches(chatID: chat.id, type: chat.type, requestedChatID: requestedChatID)
    }

    func matches(chatID: Int64, type: ChatType, requestedChatID: Int64) -> Bool {
        guard chatID != 0, chatID == requestedChatID else { return false }
        switch type {
        case .chatTypePrivate(let value):
            return peer.kind == .privateChat && peer.id == value.userId
        case .chatTypeBasicGroup(let value):
            return peer.kind == .basicGroup && peer.id == value.basicGroupId
        case .chatTypeSupergroup(let value):
            return peer.kind == .supergroup && peer.id == value.supergroupId
        case .chatTypeSecret:
            return false
        }
    }

    func matches(message: Message, chatID: Int64) -> Bool {
        matches(messageID: message.id, messageChatID: message.chatId, chatID: chatID)
    }

    func matches(messageID: Int64, messageChatID: Int64, chatID: Int64) -> Bool {
        chatID != 0 && messageChatID == chatID && messageID == self.messageID
    }

    func matches(notification: TDNativeNotification, groupChatID: Int64) -> Bool {
        guard groupChatID != 0, groupChatID == expectedChatID else { return false }
        switch notification.type {
        case .notificationTypeNewPushMessage(let value):
            return value.messageId == messageID
        case .notificationTypeNewMessage(let value):
            return matches(message: value.message, chatID: groupChatID)
        default:
            return false
        }
    }

    func notification(in notifications: [TDNativeNotification], groupChatID: Int64)
    -> TDNativeNotification? {
        notifications.last { matches(notification: $0, groupChatID: groupChatID) }
    }
}
