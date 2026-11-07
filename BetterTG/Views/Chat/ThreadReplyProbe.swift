// ThreadReplyProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Sets up a reply thread in the account's own test supergroup, "BetterTG thread test" (created once): a root
    /// message and a reply to it, so the reply carries TDLib's `messageTopicThread` as a supergroup's replies do.
    /// The whole chat's reply to that message is then tried by hand. Launch with `-ui-probe-thread-reply`; the
    /// result goes to the log and to Documents/thread-reply-probe.txt.
    @MainActor enum ThreadReplyProbe {
        private static let title = "BetterTG thread test"

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-thread-reply") else { return }
            Task {
                let result: String
                do {
                    result = try await run()
                } catch {
                    result = "Thread reply probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("thread-reply-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func run() async throws -> String {
            try await ProbeFixtures.waitForActiveAccount()
            let client = TDLib.shared.activeClient
            let found = try await client.send(TDNativeRequests.searchChats(query: title, typeFilter: nil, limit: 10))
            var chatID: Int64?
            for id in found.chatIds {
                let chat = try await client.send(TDNativeRequests.getChat(chatId: id))
                if chat.title == title { chatID = id }
            }
            if chatID == nil {
                chatID = try await client.send(TDNativeRequests.createNewSupergroupChat(
                    title: title,
                    isForum: false,
                    isChannel: false,
                    description: "BetterTG's own test group for replies in threads; no one else is in it.",
                    location: nil,
                    messageAutoDeleteTime: 0,
                    forImport: false,
                ))
.id
            }
            guard let chatID else { return "Thread reply probe failed: no chat" }
            let root = try await send("thread root", to: chatID, replyTo: nil, client: client)
            try await Task.sleep(for: .seconds(2))
            let reply = try await send("thread reply", to: chatID, replyTo: root.id, client: client)
            try await Task.sleep(for: .seconds(2))
            let sent = try await client.send(TDNativeRequests.getMessage(chatId: chatID, messageId: reply.id))
            return "Thread reply probe passed: chat=\(title) reply topic=\(String(describing: sent.topicId))"
        }

        private static func send(
            _ text: String,
            to chatID: Int64,
            replyTo: Int64?,
            client: TDLibClient,
        ) async throws -> Message {
            let pending = try await client.send(TDNativeRequests.sendMessage(
                chatId: chatID,
                topicId: nil,
                replyTo: replyTo.map {
                    .inputMessageReplyToMessage(InputMessageReplyToMessage(
                        checklistTaskId: 0,
                        messageId: $0,
                        pollOptionId: "",
                        quote: nil,
                    ))
                },
                options: nil,
                replyMarkup: nil,
                inputMessageContent: .inputMessageText(InputMessageText(
                    clearDraft: false,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: text),
                )),
            ))
            // The sent message takes its final ID once the server accepts it.
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(250))
                let history = try await client.send(TDNativeRequests.getChatHistory(
                    chatId: chatID, fromMessageId: 0, offset: 0, limit: 5, onlyLocal: false,
                ))
                if let message = history.messages
                    .first(where: { $0.isOutgoing && $0.sendingState == nil && $0.date >= pending.date }),
                    message.content.textValue == text
                {
                    return message
                }
            }
            return pending
        }
    }

    private extension MessageContent {
        var textValue: String? {
            if case .messageText(let text) = self {
                text.text.text
            } else {
                nil
            }
        }
    }
#endif
