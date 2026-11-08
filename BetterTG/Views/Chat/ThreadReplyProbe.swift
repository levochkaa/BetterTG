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

        /// `-ui-probe-community`: puts the account's own BetterTG thread test in a community of its own once, to try
        /// the
        /// profile's community row and screen; `-ui-probe-community-delete` deletes that community again.
        static func setUpCommunityIfRequested() {
            let arguments = ProcessInfo.processInfo.arguments
            let deletes = arguments.contains("-ui-probe-community-delete")
            guard arguments.contains("-ui-probe-community") || deletes else { return }
            Task {
                var result: String
                do {
                    try await ProbeFixtures.waitForActiveAccount()
                    let client = TDLib.shared.activeClient
                    let found = try await client.send(TDNativeRequests.searchChats(
                        query: title,
                        typeFilter: nil,
                        limit: 10,
                    ))
                    var chat: Chat?
                    for id in found.chatIds {
                        let candidate = try await client.send(TDNativeRequests.getChat(chatId: id))
                        if candidate.title == title { chat = candidate }
                    }
                    guard let chat, case .chatTypeSupergroup(let type) = chat.type else {
                        throw NSError(domain: "probe", code: 1)
                    }
                    let info = try await client
                        .send(TDNativeRequests.getSupergroupFullInfo(supergroupId: type.supergroupId))
                    if deletes {
                        if info.communityId != 0 {
                            _ = try await client.send(TDNativeRequests.deleteCommunity(communityId: info.communityId))
                        }
                        result = "Community probe deleted \(info.communityId)"
                    } else if info.communityId != 0 {
                        result = "Community probe: already in \(info.communityId)"
                    } else {
                        let id = try await client.send(TDNativeRequests.createCommunity(
                            name: "BetterTG test community",
                            chatId: chat.id,
                            isChatHidden: false,
                        ))
                        result = "Community probe created \(id.id)"
                    }
                } catch {
                    result = "Community probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("community-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        /// `-ui-probe-message-effect`: sends "BetterTG effect test" to Saved Messages with the first free reaction
        /// effect, to try the status icon and the effect's animation.
        static func sendMessageEffectIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-message-effect") else { return }
            Task {
                var result: String
                do {
                    try await ProbeFixtures.waitForActiveAccount()
                    let client = TDLib.shared.activeClient
                    try await Task.sleep(for: .seconds(2))
                    var effectID: Int64?
                    for id in MessageEffectStore.shared.availableReactionEffectIDs {
                        let effect = try await client.send(TDNativeRequests.getMessageEffect(effectId: id))
                        if !effect.isPremium {
                            effectID = id
                            break
                        }
                    }
                    guard let effectID, let me = TDLib.shared.activeAccount?.userID else {
                        throw NSError(domain: "probe", code: 1)
                    }
                    let sent = try await client.send(TDNativeRequests.sendMessage(
                        chatId: me,
                        topicId: nil,
                        replyTo: nil,
                        options: TDNativeMessageSendOptions(
                            suggestedPostInfo: nil,
                            disableNotification: false,
                            fromBackground: false,
                            protectContent: false,
                            allowPaidBroadcast: false,
                            paidMessageStarCount: 0,
                            updateOrderOfInstalledStickerSets: false,
                            schedulingState: nil,
                            effectId: effectID,
                            sendingId: 0,
                            onlyPreview: false,
                        ),
                        replyMarkup: nil,
                        inputMessageContent: .inputMessageText(InputMessageText(
                            clearDraft: false,
                            linkPreviewOptions: nil,
                            text: FormattedText(entities: [], text: "BetterTG effect test"),
                        )),
                    ))
                    result = "Message effect probe sent \(sent.id) with effect \(effectID)"
                } catch {
                    result = "Message effect probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("message-effect-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        /// `-ui-probe-emoji-sounds`: which animated emoji TDLib gives a sound (getAnimatedEmoji), to try the tap's
        /// sound.
        static func listEmojiSoundsIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-emoji-sounds") else { return }
            Task {
                try? await ProbeFixtures.waitForActiveAccount()
                let client = TDLib.shared.activeClient
                let candidates = [
                    "🎃",
                    "🍆",
                    "🎉",
                    "👻",
                    "🥳",
                    "🎆",
                    "🎇",
                    "🔥",
                    "💋",
                    "😘",
                    "🤡",
                    "💩",
                    "👍",
                    "❤️",
                    "🍑",
                    "😂",
                    "🎄",
                    "☃️",
                    "🦃",
                    "🐔",
                    "🐶",
                    "🐱",
                    "🐷",
                    "🐸",
                    "🐮",
                    "🦆",
                ]
                var withSound = [String]()
                for emoji in candidates {
                    if let animated = try? await client.send(TDNativeRequests.getAnimatedEmoji(emoji: emoji)),
                       animated.sound != nil
                    {
                        withSound.append(emoji)
                    }
                }
                let result = "Emoji sounds: " + withSound.joined(separator: " ")
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("emoji-sounds.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

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
