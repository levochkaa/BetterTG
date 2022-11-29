// ChatViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class ChatViewVM: ObservableObject {

    let chat: Chat

    var scrollViewProxy: ScrollViewProxy?

    @Published var messages = [Message]()
    var offset = 0
    var loadingMessages = false

    @Published var isScrollToBottomButtonShown = false

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
            guard let newMessage = notification.object as? UpdateNewMessage else {
                return
            }
            if newMessage.message.chatId != self.chat.id {
                return
            }
            Task { @MainActor in
                self.messages.insert(newMessage.message, at: 0)
            }
        }
    }

    func loadMessages(_ isInit: Bool = false) async throws {
        loadingMessages = true
        let chatHistory = try await self.tdApi.getChatHistory(
            chatId: chat.id,
            fromMessageId: self.messages.last?.id ?? 0,
            limit: 30,
            offset: messages.last == nil ? -offset : 0,
            onlyLocal: false
        )

        let chatMessages = chatHistory.messages ?? []

        await MainActor.run {
            self.messages += chatMessages
            self.offset = self.messages.count
            self.loadingMessages = false

            if isInit {
                self.scrollViewProxy?.scrollTo(self.messages.last?.id)
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
