// ChatViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class ChatViewVM: ObservableObject, Hashable {
    static func == (lhs: ChatViewVM, rhs: ChatViewVM) -> Bool {
        lhs.chat.id == rhs.chat.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(chat.id)
    }
    
    let chat: Chat
    
    var scrollViewProxy: ScrollViewProxy?
    @Published var isScrollToBottomButtonShown = false
    
    @Published var messages = [CustomMessage]()
    var offset = 0
    var loadingMessages = false
    
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "ChatVM")
    private let nc: NotificationCenter = .default
    
    init(chat: Chat) {
        self.chat = chat
        setPublishers()
        Task {
            try await self.loadMessages(true)
        }
    }
    
    func setPublishers() {
        nc.publisher(for: .newMessage) { notification in
            guard let newMessage = notification.object as? UpdateNewMessage else { return }
            if newMessage.message.chatId != self.chat.id { return }
            
            Task {
                let customMessage = try await self.getCustomMessage(from: newMessage.message)
                await MainActor.run {
                    withAnimation {
                        self.messages.insert(customMessage, at: 0)
                    }
                }
            }
        }
        
        nc.publisher(for: .deleteMessages) { notification in
            guard let deleteMessages = notification.object as? UpdateDeleteMessages else { return }
            if deleteMessages.chatId != self.chat.id { return }
            if deleteMessages.fromCache { return }
            if !deleteMessages.isPermanent { return }
            
            withAnimation {
                self.messages.removeAll(where: {
                    deleteMessages.messageIds.contains($0.message.id)
                })
            }
        }
    }
    
    func deleteMessages(ids: [Int64], deleteForBoth: Bool) async throws {
        _ = try await tdApi.deleteMessages(chatId: self.chat.id, messageIds: ids, revoke: deleteForBoth)
    }
    
    func getMessage(id: Int64) async throws -> Message {
        try await tdApi.getMessage(chatId: chat.id, messageId: id)
    }
    
    func getReplyToMessage(id: Int64) async throws -> Message? {
        id != 0 ? try await getMessage(id: id) : nil
    }
    
    func getCustomMessage(from message: Message) async throws -> CustomMessage {
        let replyToMessage = try await getReplyToMessage(id: message.replyToMessageId)
        if let reply = replyToMessage {
            switch reply.senderId {
                case let .messageSenderUser(messageSenderUser):
                    let replyUser = try await tdApi.getUser(userId: messageSenderUser.userId)
                    return CustomMessage(
                        message: message,
                        replyToMessage: replyToMessage,
                        replyUser: replyUser
                    )
                default:
                    return CustomMessage(
                        message: message,
                        replyToMessage: replyToMessage
                    )
            }
        } else {
            return CustomMessage(
                message: message
            )
        }
    }
    
    func loadMessages(_ isInit: Bool = false) async throws {
        loadingMessages = true
        let chatHistory = try await self.tdApi.getChatHistory(
            chatId: chat.id,
            fromMessageId: self.messages.last?.message.id ?? 0,
            limit: 30,
            offset: messages.last == nil ? -offset : 0,
            onlyLocal: false
        )
        
        let chatMessages = chatHistory.messages ?? []
        let messages = try await chatMessages.asyncMap { chatMessage in
            try await self.getCustomMessage(from: chatMessage)
        }
        
        await MainActor.run {
            self.messages += messages
            self.offset = self.messages.count
            self.loadingMessages = false
            
            if isInit {
                self.scrollViewProxy?.scrollTo(self.messages.last?.message.id)
            }
        }
    }
    
    func sendMessage(text: String) async throws {
        _ = try await tdApi.sendMessage(
            chatId: chat.id,
            inputMessageContent:
                    .inputMessageText(
                        .init(
                            clearDraft: true,
                            disableWebPagePreview: true,
                            text: FormattedText(
                                entities: [],
                                text: text
                            )
                        )
                    ),
            messageThreadId: 0,
            options: nil,
            replyMarkup: nil,
            replyToMessageId: 0
        )
    }
}
