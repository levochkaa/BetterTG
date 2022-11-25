// RootViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class RootViewVM: ObservableObject {
    
    @Published var loggedIn: Bool?
    @Published var mainChats = [Chat]()
    
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "RootVM")
    private let nc: NotificationCenter = .default
    
    init() {
        self.setPublishers()
    }
    
    func setPublishers() {
        self.setAuthPublishers()
        self.setChatPublishers()
    }

    func setChatPublishers() {
        nc.publisher(for: .chatLastMessage) { notification in
            if let updateChatLastMessage = notification.object as? UpdateChatLastMessage,
               let index = self.mainChats.firstIndex(where: { $0.id == updateChatLastMessage.chatId }) {
                let newChat = self.getChat(from: self.mainChats[index], lastMessage: updateChatLastMessage.lastMessage)
                DispatchQueue.main.async {
                    self.mainChats[index] = newChat
                }
            }
        }

        nc.publisher(for: .chatDraftMessage) { notification in
            if let updateChatDraftMessage = notification.object as? UpdateChatDraftMessage,
               let index = self.mainChats.firstIndex(where: { $0.id == updateChatDraftMessage.chatId }) {
                let newChat = self.getChat(
                        from: self.mainChats[index],
                        draftMessage: updateChatDraftMessage.draftMessage

                )
                DispatchQueue.main.async {
                    self.mainChats[index] = newChat
                }
            }
        }
    }
    
    func setAuthPublishers() {
        nc.mergeMany([
            nc.publisher(for: .closed),
            nc.publisher(for: .closing),
            nc.publisher(for: .loggingOut),
            nc.publisher(for: .waitPhoneNumber)
        ]) { _ in
            DispatchQueue.main.async {
                self.loggedIn = false
            }
        }
        
        nc.publisher(for: .ready) { _ in
            Task {
                try await self.loadMainChats()
            }
            DispatchQueue.main.async {
                self.loggedIn = true
            }
        }
    }
    
    func loadMainChats() async throws {
        _ = try await tdApi.loadChats(chatList: .chatListMain, limit: 50)
        let chats = try await tdApi.getChats(chatList: .chatListMain, limit: 50)
        let mainChats = try await chats.chatIds.asyncCompactMap { id in
            let chat = try await tdApi.getChat(chatId: id)
            switch chat.type {
                case .chatTypePrivate:
                    return try await tdApi.getUser(userId: chat.id).type == .userTypeRegular ? chat : nil
                default:
                    return nil
            }
        }
        DispatchQueue.main.async {
            self.mainChats = mainChats
        }
    }

    func getChat(from chat: Chat,
                 actionBar: ChatActionBar? = nil,
                 availableReactions: ChatAvailableReactions? = nil,
                 canBeDeletedForAllUsers: Bool? = nil,
                 canBeDeletedOnlyForSelf: Bool? = nil,
                 canBeReported: Bool? = nil,
                 clientData: String? = nil,
                 defaultDisableNotification: Bool? = nil,
                 draftMessage: DraftMessage? = nil,
                 hasProtectedContent: Bool? = nil,
                 hasScheduledMessages: Bool? = nil,
                 id: Int64? = nil,
                 isBlocked: Bool? = nil,
                 isMarkedAsUnread: Bool? = nil,
                 lastMessage: Message? = nil,
                 lastReadInboxMessageId: Int64? = nil,
                 lastReadOutboxMessageId: Int64? = nil,
                 messageSenderId: MessageSender? = nil,
                 messageTtl: Int? = nil,
                 notificationSettings: ChatNotificationSettings? = nil,
                 pendingJoinRequests: ChatJoinRequestsInfo? = nil,
                 permissions: ChatPermissions? = nil,
                 photo: ChatPhotoInfo? = nil,
                 positions: [ChatPosition]? = nil,
                 replyMarkupMessageId: Int64? = nil,
                 themeName: String? = nil,
                 title: String? = nil,
                 type: ChatType? = nil,
                 unreadCount: Int? = nil,
                 unreadMentionCount: Int? = nil,
                 unreadReactionCount: Int? = nil,
                 videoChat: VideoChat? = nil
    ) -> Chat {
        return Chat(
                actionBar: actionBar ?? chat.actionBar,
                availableReactions:  availableReactions ?? chat.availableReactions,
                canBeDeletedForAllUsers: canBeDeletedForAllUsers ?? chat.canBeDeletedForAllUsers,
                canBeDeletedOnlyForSelf: canBeDeletedOnlyForSelf ?? chat.canBeDeletedOnlyForSelf,
                canBeReported: canBeReported ?? chat.canBeReported,
                clientData: clientData ?? chat.clientData,
                defaultDisableNotification: defaultDisableNotification ?? chat.defaultDisableNotification,
                draftMessage: draftMessage ?? chat.draftMessage,
                hasProtectedContent: hasProtectedContent ?? chat.hasProtectedContent,
                hasScheduledMessages: hasScheduledMessages ?? chat.hasScheduledMessages,
                id: id ?? chat.id,
                isBlocked: isBlocked ?? chat.isBlocked,
                isMarkedAsUnread: isMarkedAsUnread ?? chat.isMarkedAsUnread,
                lastMessage: lastMessage ?? chat.lastMessage,
                lastReadInboxMessageId: lastReadInboxMessageId ?? chat.lastReadInboxMessageId,
                lastReadOutboxMessageId: lastReadOutboxMessageId ?? chat.lastReadOutboxMessageId,
                messageSenderId: messageSenderId ?? chat.messageSenderId,
                messageTtl: messageTtl ?? chat.messageTtl,
                notificationSettings: notificationSettings ?? chat.notificationSettings,
                pendingJoinRequests: pendingJoinRequests ?? chat.pendingJoinRequests,
                permissions: permissions ?? chat.permissions,
                photo: photo ?? chat.photo,
                positions: positions ?? chat.positions,
                replyMarkupMessageId: replyMarkupMessageId ?? chat.replyMarkupMessageId,
                themeName: themeName ?? chat.themeName,
                title: title ?? chat.title,
                type: type ?? chat.type,
                unreadCount: unreadCount ?? chat.unreadCount,
                unreadMentionCount: unreadMentionCount ?? chat.unreadMentionCount,
                unreadReactionCount: unreadReactionCount ?? chat.unreadReactionCount,
                videoChat: videoChat ?? chat.videoChat
        )
    }
}
