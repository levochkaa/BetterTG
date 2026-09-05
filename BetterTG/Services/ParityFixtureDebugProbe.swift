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
        var phase: String?
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
        let previous = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: path))
        guard previous == nil || previous?.accountID == accountID else { return }
        if previous?.completed == true, (previous?.messageIDs.count ?? 0) >= 3 { return }
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
            var manifest = previous ?? Manifest(accountID: accountID, chatID: 0)
            manifest.error = nil
            manifest.phase = "resuming"
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
                save()
                try checkAccount()
                if manifest.chatID != 0, manifest.messageIDs.isEmpty {
                    let existing = try await client.getChat(chatId: manifest.chatID)
                    if existing.title == "BetterTG test", case .chatTypeSupergroup(let type) = existing.type {
                        let group = try await client
                            .send(TDNativeRequests.getSupergroup(supergroupId: type.supergroupId))
                        if group.isChannel, group.memberCount <= 1, group.usernames?.activeUsernames.isEmpty != false,
                           case .chatMemberStatusCreator = group.status
                        {
                            let history = try await client.getChatHistory(
                                chatId: existing.id,
                                fromMessageId: 0,
                                limit: 100,
                                offset: 0,
                                onlyLocal: false,
                            )
                            guard history.messages
                                .allSatisfy({
                                    if case .messageSupergroupChatCreate = $0.content {
                                        true
                                    } else {
                                        false
                                    }
                                }) else { return }
                            try checkAccount()
                            // Undo only the empty private fixture this probe created.
                            _ = try await client
                                .send(TDNativeRequests.deleteChat(chatId: existing.id))
                            manifest.chatID = 0
                            manifest.topicID = nil
                            save()
                        }
                    }
                }
                if manifest.chatID == 0 {
                    let created = try await client.send(TDNativeRequests.createNewSupergroupChat(
                        title: "BetterTG test", isForum: false, isChannel: false,
                        description: "Private BetterTG UI test fixtures. Created by Codex; no other members are invited.",
                        location: nil, messageAutoDeleteTime: 0, forImport: false,
                    ))
                    manifest.chatID = created.id
                    save()
                }
                try checkAccount()
                let fixtureChat = try await client.getChat(chatId: manifest.chatID)
                guard fixtureChat.title == "BetterTG test",
                      case .chatTypeSupergroup(let type) = fixtureChat.type else { return }
                let group = try await client.send(TDNativeRequests.getSupergroup(supergroupId: type.supergroupId))
                manifest.phase = "group: forum=\(group.isForum), channel=\(group.isChannel), members=\(group.memberCount), public=\(group.usernames?.activeUsernames.isEmpty == false)"
                save()
                guard case .chatMemberStatusCreator = group.status,
                      group.usernames?.activeUsernames.isEmpty != false,
                      !group.isChannel, group.memberCount <= 1 else { return }
                if !group.isForum {
                    try checkAccount()
                    manifest.phase = "enable forum"
                    save()
                    _ = try await client.send(TDNativeRequests.toggleSupergroupIsForum(
                        supergroupId: type.supergroupId, isForum: true, hasForumTabs: false,
                    ))
                }
                manifest.phase = "fetch icons"
                save()
                let icons = try? await client.send(TDNativeRequests.getForumTopicDefaultIcons())
                var emojiID: Int64 = 0
                if let first = icons?.stickers.first, case .stickerFullTypeCustomEmoji(let emoji) = first.fullType {
                    emojiID = emoji.customEmojiId
                }
                if manifest.topicID == nil {
                    manifest.phase = "create topic"
                    save()
                    let topic = try await client.send(TDNativeRequests.createForumTopic(
                        chatId: manifest.chatID,
                        name: "UI test",
                        isNameImplicit: false,
                        icon: ForumTopicIcon(
                            color: 0x6FB9F0,
                            customEmojiId: emojiID,
                        ),
                    ))
                    manifest.topicID = topic.forumTopicId
                    save()
                }
                manifest.phase = "send fixtures"
                save()
                let body = "BetterTG test: hidden spoiler and bold link. Tap to reveal the hidden text."
                let spoiler = (body as NSString).range(of: "hidden spoiler")
                let bold = (body as NSString).range(of: "bold link")
                if manifest.messageIDs.isEmpty { try await send(.inputMessageText(InputMessageText(
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
                ))) }
                if manifest.messageIDs.count < 2 { try await send(.inputMessageText(InputMessageText(
                    clearDraft: false,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: "BetterTG test link preview https://telegram.org/blog"),
                ))) }
                if manifest.messageIDs.count < 3 { try await send(richFixture()) }
                manifest.completed = true
                save()
            } catch {
                manifest.error = String(describing: error)
                save()
            }
        }
    }

    private static func richFixture() -> InputMessageContent {
        func plain(_ value: String) -> TDNativeRichText { .richTextPlain(TDNativeRichTextPlain(text: value)) }
        func paragraph(_ text: TDNativeRichText)
            -> TDNativeInputPageBlock { .inputPageBlockParagraph(TDNativeInputPageBlockParagraph(text: text)) }
        func cell(_ value: String, header: Bool = false) -> TDNativePageBlockTableCell {
            TDNativePageBlockTableCell(
                text: plain(value),
                isHeader: header,
                colspan: 1,
                rowspan: 1,
                align: .pageBlockHorizontalAlignmentLeft,
                valign: .pageBlockVerticalAlignmentTop,
            )
        }
        let blocks: [TDNativeInputPageBlock] = [
            .inputPageBlockSectionHeading(TDNativeInputPageBlockSectionHeading(
                text: plain("BetterTG test rich message"),
                size: 2,
            )),
            paragraph(.richTexts(TDNativeRichTexts(texts: [
                plain("Native blocks with "), .richTextBold(TDNativeRichTextBold(text: plain("bold"))), plain(", "),
                .richTextItalic(TDNativeRichTextItalic(text: plain("italic"))), plain(" and a "),
                .richTextSpoiler(TDNativeRichTextSpoiler(text: plain("hidden rich spoiler"))), plain("."),
            ]))),
            .inputPageBlockBlockQuote(TDNativeInputPageBlockBlockQuote(
                blocks: [paragraph(plain("A quote with its own layout."))],
                credit: nil,
            )),
            .inputPageBlockTable(TDNativeInputPageBlockTable(caption: plain(""), cells: [
                [cell("Feature", header: true), cell("Result", header: true)],
                [cell("Rich text"), cell("Visible")], [cell("Spoiler"), cell("Tap to reveal")],
            ], isBordered: true, isStriped: true, isCompact: false)),
            .inputPageBlockDetails(TDNativeInputPageBlockDetails(
                header: plain("Expand test details"),
                blocks: [paragraph(plain("Expanded content stays with this message when the cell is reused."))],
                isOpen: false,
            )),
        ]
        return .inputMessageRichMessage(TDNativeInputMessageRichMessage(
            message: TDNativeInputRichMessage(
                source: .richMessageSourceBlocks(TDNativeRichMessageSourceBlocks(blocks: blocks)),
                isRtl: false,
                detectAutomaticBlocks: false,
            ), clearDraft: false,
        ))
    }
}
#endif
