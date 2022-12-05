// ChatViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class ChatViewVM: ObservableObject {

    let chat: Chat
    
    @Published var text = ""
    
    @Published var scrollViewProxy: ScrollViewProxy?
    @Published var isScrollToBottomButtonShown = false
    
    var initSavedFirstMessage: CustomMessage?
    @Published var savedFirstMessage: CustomMessage?
    @Published var messages = [CustomMessage]()
    @Published var loadingMessages = false
    @Published var initLoadingMessages = false
    var offset = 0
    
    @Published var replyMessage: CustomMessage? {
        didSet {
            Task {
                try await updateDraft()
            }
        }
    }
    
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "ChatVM")
    private let nc: NotificationCenter = .default
    
    init(chat: Chat) {
        self.chat = chat
        
        setPublishers()
        Task {
            try await self.loadMessages(isInit: true)
            
            guard let draftMessage = chat.draftMessage else { return }
            try await self.setDraft(draftMessage)
        }
    }
    
    func setPublishers() {
        nc.publisher(for: .chatDraftMessage) { notification in
            guard let chatDraftMessage = notification.object as? UpdateChatDraftMessage,
                  let draftMessage = chatDraftMessage.draftMessage,
                  chatDraftMessage.chatId == self.chat.id
            else { return }
            
            Task {
                try await self.setDraft(draftMessage)
            }
        }
        
        nc.publisher(for: .newMessage) { notification in
            guard let newMessage = notification.object as? UpdateNewMessage,
                  newMessage.message.chatId == self.chat.id
            else { return }
            
            Task {
                let customMessage = try await self.getCustomMessage(from: newMessage.message)
                await MainActor.run {
                    withAnimation {
                        self.messages.append(customMessage)
                    }
                }
            }
        }
        
        nc.publisher(for: .deleteMessages) { notification in
            guard let deleteMessages = notification.object as? UpdateDeleteMessages else { return }
            if deleteMessages.chatId != self.chat.id
                || deleteMessages.fromCache
                || !deleteMessages.isPermanent { return }
            
            withAnimation {
                self.messages.removeAll(where: { customMessage in
                    deleteMessages.messageIds.contains(customMessage.message.id)
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
        var customMessage = CustomMessage(message: message)
        
        switch message.senderId {
            case let .messageSenderUser(messageSenderUser):
                let senderUser = try await tdApi.getUser(userId: messageSenderUser.userId)
                customMessage.senderUser = senderUser
            case .messageSenderChat:
                break
        }
        
        if let reply = replyToMessage {
            switch reply.senderId {
                case let .messageSenderUser(messageSenderUser):
                    let replyUser = try await tdApi.getUser(userId: messageSenderUser.userId)
                    customMessage.replyToMessage = replyToMessage
                    customMessage.replyUser = replyUser
                    return customMessage
                default:
                    customMessage.replyToMessage = replyToMessage
                    return customMessage
            }
        } else {
            return customMessage
        }
    }
    
    func setDraft(_ draftMessage: DraftMessage) async throws {
        switch draftMessage.inputMessageText {
            case let .inputMessageText(inputMessageText):
                await MainActor.run {
                    text = inputMessageText.text.text
                }
            default:
                break
        }
        let message = try await tdApi.getMessage(chatId: chat.id, messageId: draftMessage.replyToMessageId)
        let customMessage = try await getCustomMessage(from: message)
        await MainActor.run {
            replyMessage = customMessage
        }
    }
    
    func updateDraft() async throws {
        let draftMessage = DraftMessage(
            date: Int(Date.now.timeIntervalSince1970),
            inputMessageText: .inputMessageText(
                .init(
                    clearDraft: true,
                    disableWebPagePreview: true,
                    text: FormattedText(
                        entities: [],
                        text: text
                    )
                )
            ),
            replyToMessageId: replyMessage?.message.id ?? 0
        )
        _ = try await tdApi.setChatDraftMessage(
            chatId: chat.id,
            draftMessage: draftMessage,
            messageThreadId: 0
        )
    }

    func loadMessages(isInit: Bool = false) async throws {
        await MainActor.run {
            self.loadingMessages = true
            
            if isInit {
                self.initLoadingMessages = true
            }
        }
        
        let chatHistory = try await self.tdApi.getChatHistory(
            chatId: chat.id,
            fromMessageId: self.messages.first?.message.id ?? 0,
            limit: 30,
            offset: messages.first == nil ? -offset : 0,
            onlyLocal: false
        )
        
        let chatMessages = chatHistory.messages?.reversed() ?? []
        let messages = try await chatMessages.asyncMap { chatMessage in
            try await self.getCustomMessage(from: chatMessage)
        }
        
        if isInit {
            initSavedFirstMessage = messages.first
        }
        
        await MainActor.run {
            self.savedFirstMessage = self.messages.first
            self.messages = messages + self.messages
            self.offset = self.messages.count
            self.loadingMessages = false
            
            if isInit {
                self.initLoadingMessages = false
            }
        }
    }
    
    func sendMessage() async throws {
        if text.isEmpty { return }
        
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
            replyToMessageId: replyMessage?.message.id ?? 0
        )
        
        replyMessage = nil
        text = ""
    }
}
