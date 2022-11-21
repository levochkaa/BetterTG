// ChatViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class ChatViewVM: ObservableObject {
    let chat: Chat

    @Published var messages = [Message]()
    var offset = 0
    var retries = 0
    var loaded = 0
    let limit = 30

    private let tdApi = TdApi.shared
    private let logger = Logger(label: "ChatVM")
    private let nc = NotificationCenter.default
    private var cancellable = Set<AnyCancellable>()

    let maxNumberOfRetries = 10

    init(chat: Chat) {
        self.chat = chat

        Task {
            try await self.update()
        }
        
        self.setPublishers()
    }
    
    func setPublishers() {
        nc.publisher(for: .newMessage, in: &cancellable) { notification in
            if let newMessage = notification.object as? UpdateNewMessage {
                if newMessage.message.chatId != self.chat.id { return }
                DispatchQueue.main.async {
                    self.messages.append(newMessage.message)
                }
            }
        }
    }

    func update() async throws {
        retries = 0
        try await getMessages()
    }

    func getMessages() async throws {
        let chatHistory = try await self.tdApi.getChatHistory(
            chatId: self.chat.id,
            fromMessageId: 0,
            limit: limit,
            offset: -offset,
            onlyLocal: false
        )
        offset += chatHistory.totalCount

        let chatMessages = chatHistory.messages?.reversed() ?? []
        DispatchQueue.main.async {
            self.messages = chatMessages.compactMap { msg in
                if self.messages.first(where: { msg == $0 }) == nil {
                    return msg
                }
                return nil
            } + self.messages
        }

        if offset % limit != 0 {
            retries += 1
            if retries != maxNumberOfRetries {
                try await getMessages()
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
