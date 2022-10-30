// ChatViewVM.swift

import SwiftUI
import TDLibKit
import CollectionConcurrencyKit

class ChatViewVM: ObservableObject {
    let chat: Chat

    @Published var messages = [Message]()

    let tdApi = TdApi.shared
    let logger = Logger(label: "ChatVM")

    init(chat: Chat) {
        self.chat = chat

        Task {
            try await self.update()
        }

        self.tdApi.client.run { data in
            do {
                let update = try TdApi.shared.decoder.decode(Update.self, from: data)

                switch update {
                    case let .updateNewMessage(newMessage):
                        if newMessage.message.chatId != chat.id { break }
                        self.logger.log("Got a new message: \(newMessage.message)")
                        DispatchQueue.main.async {
                            self.messages.append(newMessage.message)
                        }
                    default:
                        break
                }
            } catch {
                guard let tdError = error as? TDLibKit.Error else { return }
                self.logger.log("\(tdError.code) - \(tdError.message)", level: .error)
            }
        }
    }

    func update() async throws {
        logger.log("Updating messages list for \(chat.id)")
        let msgs = try await getMessages()
        DispatchQueue.main.async {
            self.messages = msgs
            self.logger.log("Updated messages list for \(self.chat.id)")
        }
    }

    func getMessages() async throws -> [Message] {
        return try await self.tdApi.getChatHistory(
            chatId: self.chat.id,
            fromMessageId: 0,
            limit: 30,
            offset: 0,
            onlyLocal: false
        ).messages?.reversed() ?? []
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
                                text: text)
                        )
                    ),
            messageThreadId: 0,
            options: nil,
            replyMarkup: nil,
            replyToMessageId: 0
        )
    }
}
