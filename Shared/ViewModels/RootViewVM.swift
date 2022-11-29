// RootViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class RootViewVM: ObservableObject {

    @Published var loggedIn: Bool?
    @Published var mainChats = [Chat]()

    var loadedUsers = 0
    var limit = 10
    var loadingUsers = false

    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "RootVM")
    private let nc: NotificationCenter = .default

    init() {
        setPublishers()
    }

    func setPublishers() {
        setAuthPublishers()
        setChatPublishers()
    }

    func setChatPublishers() {
        nc.publisher(for: .chatLastMessage) { notification in
            guard let updateChatLastMessage = notification.object as? UpdateChatLastMessage,
                  let index = self.mainChats.firstIndex(where: { $0.id == updateChatLastMessage.chatId })
            else {
                return
            }
            let newChat = self.getChat(from: self.mainChats[index], lastMessage: updateChatLastMessage.lastMessage)
            Task { @MainActor in
                self.mainChats[index] = newChat
            }
        }

        nc.publisher(for: .chatDraftMessage) { notification in
            guard let updateChatDraftMessage = notification.object as? UpdateChatDraftMessage,
                  let index = self.mainChats.firstIndex(where: { $0.id == updateChatDraftMessage.chatId })
            else {
                return
            }
            let newChat = self.getChat(
                from: self.mainChats[index],
                draftMessage: updateChatDraftMessage.draftMessage,
                updatedChatDraftMessage: true
            )
            Task { @MainActor in
                self.mainChats[index] = newChat
            }
        }
    }

    func setAuthPublishers() {
        nc.mergeMany([
            nc.publisher(for: .closed),
            nc.publisher(for: .closing),
            nc.publisher(for: .loggingOut),
            nc.publisher(for: .waitPhoneNumber),
            nc.publisher(for: .waitCode),
            nc.publisher(for: .waitPassword)
        ]) { _ in
            Task { @MainActor in
                self.loggedIn = false
            }
        }

        nc.publisher(for: .ready) { _ in
            Task {
                try await self.loadMainChats()

                await MainActor.run {
                    self.loggedIn = true
                }
            }
        }
    }

    func fetchChatsHistory() async throws {
        try await mainChats.asyncForEach { chat in
            _ = try await tdApi.getChatHistory(
                chatId: chat.id,
                fromMessageId: 0,
                limit: 30,
                offset: 0,
                onlyLocal: false
            )
        }
    }

    func loadMainChats() async throws {
        // don't know why, but some times loadChats() gives Error: 404
        do {
            _ = try await tdApi.loadChats(chatList: .chatListMain, limit: limit)
        } catch {
            // tired of this error in logs.
//            guard let tdError = error as? TDLibKit.Error else {
//                return
//            }
//            logger.log(tdError)
        }

        loadingUsers = true
        let chats = try await tdApi.getChats(chatList: .chatListMain, limit: limit)
        let mainChats = try await chats.chatIds.asyncCompactMap { id in
            let chat = try await tdApi.getChat(chatId: id)
            switch chat.type {
                case .chatTypePrivate:
                    let user = try await tdApi.getUser(userId: chat.id)
                    switch user.type {
                        case .userTypeRegular:
                            return chat
                        default:
                            return nil
                    }
                default:
                    return nil
            }
        }
        loadedUsers = mainChats.count
        limit += 10
        await MainActor.run {
            self.mainChats += mainChats[self.mainChats.count...]
            self.loadingUsers = false
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
                 videoChat: VideoChat? = nil,
                 updatedChatDraftMessage: Bool = false
    ) -> Chat {
        Chat(
            actionBar: actionBar ?? chat.actionBar,
            availableReactions: availableReactions ?? chat.availableReactions,
            canBeDeletedForAllUsers: canBeDeletedForAllUsers ?? chat.canBeDeletedForAllUsers,
            canBeDeletedOnlyForSelf: canBeDeletedOnlyForSelf ?? chat.canBeDeletedOnlyForSelf,
            canBeReported: canBeReported ?? chat.canBeReported,
            clientData: clientData ?? chat.clientData,
            defaultDisableNotification: defaultDisableNotification ?? chat.defaultDisableNotification,
            draftMessage: updatedChatDraftMessage ? draftMessage : chat.draftMessage,
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
