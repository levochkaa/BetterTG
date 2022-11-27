// ChatViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class ChatViewVM: ObservableObject {

    let chat: Chat

    @Published var messages = [Message]()
    var offset = 0

    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "ChatVM")
    private let nc: NotificationCenter = .default

//    var retries = 0
//    let maxNumberOfRetries = 5

    init(chat: Chat) {
        self.chat = chat
        self.setPublishers()
        Task {
            try await self.update()
        }
    }


    func setPublishers() {
        nc.publisher(for: .newMessage) { notification in
            guard let newMessage = notification.object as? UpdateNewMessage else {
                return
            }
            if newMessage.message.chatId != self.chat.id {
                return
            }
            DispatchQueue.main.async {
                self.messages.append(newMessage.message)
            }
        }

    }

    func update() async throws {
//        retries = 0
        try await getMessages()
    }

    func getMessages() async throws {
        let chatHistory = try await self.tdApi.getChatHistory(
            chatId: self.chat.id,
            fromMessageId: self.messages.first?.id ?? 0,
            limit: 30,
            offset: self.messages.first == nil ? -offset : 0,
            onlyLocal: false
        )

        let chatMessages = chatHistory.messages?.reversed() ?? []

        DispatchQueue.main.async {
            self.messages = chatMessages.compactMap { msg in
                if self.messages.first(where: { msg == $0 }) == nil {
                    return msg
                }
                return nil
            } + self.messages
        }

        offset = messages.count

//        did preloading, so, retries aren't needed
//        if retries != maxNumberOfRetries {
//            retries += 1
//            try await getMessages()
//        }
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
