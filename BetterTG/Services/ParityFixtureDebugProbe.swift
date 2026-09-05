// ParityFixtureDebugProbe.swift

#if DEBUG
import Combine
import Foundation
import TDLibKit

/// Explicit launch-only fixture creation. The manifest owns every created ID;
/// no cleanup path ever accepts an arbitrary pre-existing message or chat.
@MainActor enum ParityFixtureDebugProbe {
    private struct Manifest: Codable {
        let accountID: UUID
        var chatID: Int64
        var topicID: Int?
        var messageIDs = [Int64]()
        var completed = false
        var error: String?
    }

    private static var started = false
    private static var sendObserver: AnyCancellable?
    private static var acceptedIDs = [Int64: Int64]()

    static func runIfRequested(chat: CustomChat) {
        guard !started, chat.isSavedMessages,
              ProcessInfo.processInfo.arguments.contains("-create-parity-test-fixtures"),
              let accountID = TDLib.shared.activeAccountID,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        started = true
        let client = TDLib.shared.activeClient
        let path = documents.appendingPathComponent("parity-test-fixtures.json")
        if let previous = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: path)),
           previous.accountID == accountID { return }
        sendObserver = nc.publisher(for: .updateMessageSendSucceeded)
            .receive(on: DispatchQueue.main)
            .sink { update in
                guard TDLib.shared.activeAccountID == accountID else { return }
                acceptedIDs[update.oldMessageId] = update.message.id
                guard var saved = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: path)),
                      saved.accountID == accountID, saved.chatID == update.message.chatId,
                      let index = saved.messageIDs.firstIndex(of: update.oldMessageId) else { return }
                saved.messageIDs[index] = update.message.id
                if let data = try? JSONEncoder().encode(saved) { try? data.write(to: path, options: .atomic) }
            }
        Task {
            var manifest = Manifest(accountID: accountID, chatID: 0)
            @MainActor func save() {
                manifest.messageIDs = manifest.messageIDs.map { acceptedIDs[$0] ?? $0 }
                if let data = try? JSONEncoder().encode(manifest) { try? data.write(to: path, options: .atomic) }
            }
            @MainActor func checkAccount() throws {
                guard TDLib.shared.activeAccountID == accountID, TDLib.shared.activeClient.id == client.id else {
                    throw ChatSendContextError.accountUnavailable
                }
            }
            @MainActor func send(_ content: InputMessageContent) async throws {
                try checkAccount()
                guard manifest.chatID != 0, let topicID = manifest.topicID else { return }
                let message = try await client.sendMessage(
                    chatId: manifest.chatID,
                    inputMessageContent: content,
                    options: nil,
                    replyMarkup: nil,
                    replyTo: nil,
                    topicId: .messageTopicForum(MessageTopicForum(forumTopicId: topicID)),
                )
                manifest.messageIDs.append(acceptedIDs[message.id] ?? message.id)
                save()
            }
            do {
                try checkAccount()
                let created = try await client.send(TDNativeRequests.createNewSupergroupChat(
                    title: "BetterTG test", isForum: true, isChannel: false,
                    description: "Private BetterTG UI test fixtures. Created by Codex; no other members are invited.",
                    location: nil, messageAutoDeleteTime: 0, forImport: false,
                ))
                manifest.chatID = created.id
                save()
                try checkAccount()
                let icons = try? await client.send(TDNativeRequests.getForumTopicDefaultIcons())
                var emojiID: Int64 = 0
                if let first = icons?.stickers.first, case .stickerFullTypeCustomEmoji(let emoji) = first.fullType {
                    emojiID = emoji.customEmojiId
                }
                let topic = try await client.send(TDNativeRequests.createForumTopic(
                    chatId: created.id,
                    name: "UI test",
                    isNameImplicit: false,
                    icon: ForumTopicIcon(
                        color: 0x6FB9F0,
                        customEmojiId: emojiID,
                    ),
                ))
                manifest.topicID = topic.forumTopicId
                save()
                let body = "BetterTG test: hidden spoiler and bold link. Tap to reveal the hidden text."
                let spoiler = (body as NSString).range(of: "hidden spoiler")
                let bold = (body as NSString).range(of: "bold link")
                try await send(.inputMessageText(InputMessageText(
                    clearDraft: false, linkPreviewOptions: nil,
                    text: FormattedText(entities: [
                        TextEntity(length: spoiler.length, offset: spoiler.location, type: .textEntityTypeSpoiler),
                        TextEntity(length: bold.length, offset: bold.location, type: .textEntityTypeBold),
                        TextEntity(
                            length: bold.length,
                            offset: bold.location,
                            type: .textEntityTypeTextUrl(TextEntityTypeTextUrl(url: "https://telegram.org")),
                        ),
                    ], text: body),
                )))
                try await send(.inputMessageText(InputMessageText(
                    clearDraft: false,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: "BetterTG test link preview https://telegram.org/blog"),
                )))
                manifest.completed = true
                save()
            } catch {
                manifest.error = String(describing: error)
                save()
            }
        }
    }
}
#endif
