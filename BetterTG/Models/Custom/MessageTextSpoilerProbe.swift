// MessageTextSpoilerProbe.swift

#if DEBUG
    import Combine
    import TDLibKit
    import UIKit

    @MainActor enum MessageTextSpoilerProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-text-spoilers") else { return }
            Task { @MainActor in
                let result: String
                do {
                    try verify()
                    result = "Text spoiler probe passed: UTF16/overflow/overlap=true; text-layout/reveal-before-link-code=true; "
                        + "parent-AX/reply-quote/summary=true; account-client-chat-source-edit-reuse=true; "
                        + "emoji-admission/stale-generation=true; actual-emoji-decoder/live-UI=pending; URL/clipboard/server/account-stores=0"
                } catch { result = "Text spoiler probe failed: \(error)" }
                log(result)
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("text-spoiler-probe.txt"),
                        options: .atomic,
                    )
                }
            }
        }

        private static func require(_ value: Bool, _ reason: String) throws {
            guard value else { throw Failure(description: reason) }
        }

        private static func fixture() -> FormattedText {
            let text = "Public HIDDEN\n🙂 סוד"
            let secret = (text as NSString).range(of: "HIDDEN")
            let emoji = (text as NSString).range(of: "🙂")
            let hebrew = (text as NSString).range(of: "סוד")
            return FormattedText(entities: [
                .init(length: text.utf16.count, offset: 0, type: .textEntityTypeBold),
                .init(
                    length: secret.length,
                    offset: secret.location,
                    type: .textEntityTypeTextUrl(.init(url: "https://example.invalid/secret")),
                ),
                .init(length: secret.length, offset: secret.location, type: .textEntityTypeSpoiler),
                .init(
                    length: emoji.length,
                    offset: emoji.location,
                    type: .textEntityTypeCustomEmoji(.init(customEmojiId: 123)),
                ),
                .init(length: emoji.length, offset: emoji.location, type: .textEntityTypeSpoiler),
                .init(length: hebrew.length, offset: hebrew.location, type: .textEntityTypeSpoiler),
            ], text: text)
        }

        private static func verify() throws {
            let text = fixture()
            let source = TdUpdateSource(accountID: UUID(), clientID: 100)
            let store = MessageTextSpoilerStore()
            store.configure(source: source, chatID: 10, texts: [1: text, 2: text])
            guard let state = store.states[1],
                  let second = store.states[2] else { throw Failure(description: "missing states") }
            let secret = (text.text as NSString).range(of: "HIDDEN")
            let emoji = (text.text as NSString).range(of: "🙂")
            let projection = state.presentation
            try require(projection.text == text, "valid original entities changed")
            try require(
                !projection.accessibilityText().contains("HIDDEN") && !projection.accessibilityText().contains("סוד"),
                "redaction leaked",
            )
            try require(projection.action(at: secret.location, revealed: false) == .reveal, "link preceded concealment")
            try require(
                projection.action(at: -1, revealed: false) == .none && projection
                    .action(at: Int.max, revealed: false) == .none,
                "invalid hit index",
            )
            let malformed = FormattedText(entities: [
                .init(length: Int(Int32.max), offset: 1, type: .textEntityTypeSpoiler),
                .init(length: 1, offset: -1, type: .textEntityTypeBold),
            ], text: "secret")
            let unsafe = MessageTextSpoilerPresentation(malformed)
            try require(
                unsafe.text.entities.isEmpty && unsafe.accessibilityText() == "Spoiler",
                "malformed range did not fail closed",
            )
            _ = unsafe.attributedText()
            for offset in [0, 1] {
                let splitSurrogate = MessageTextSpoilerPresentation(.init(entities: [
                    .init(length: 1, offset: offset, type: .textEntityTypeSpoiler),
                    .init(length: 1, offset: offset, type: .textEntityTypeCode),
                ], text: "🙂"))
                try require(
                    splitSurrogate.text.entities.isEmpty && splitSurrogate.accessibilityText() == "Spoiler"
                        && splitSurrogate.action(at: offset, revealed: true) == .none,
                    "surrogate split start/end accepted",
                )
                _ = splitSurrogate.attributedText()
            }
            for (value, offset, length) in [("🙂", 0, 2), ("e\u{301}", 1, 1)] {
                let valid = FormattedText(entities: [
                    .init(length: length, offset: offset, type: .textEntityTypeSpoiler),
                ], text: value)
                let validProjection = MessageTextSpoilerPresentation(valid)
                try require(validProjection.text == valid, "valid scalar boundary rejected")
                _ = validProjection.attributedText()
            }
            let overlapping = MessageTextSpoilerPresentation(.init(entities: [
                .init(length: 4, offset: 0, type: .textEntityTypeSpoiler),
                .init(length: 4, offset: 2, type: .textEntityTypeSpoiler),
            ], text: "secret"))
            try require(
                overlapping.ranges.count == 1 && overlapping.accessibilityText() == "Spoiler",
                "overlapping redaction",
            )
            let code = MessageTextSpoilerPresentation(.init(entities: [
                .init(length: 11, offset: 0, type: .textEntityTypeCode),
                .init(length: 6, offset: 5, type: .textEntityTypeSpoiler),
            ], text: "show secret"))
            try require(
                code.action(at: 0, revealed: false) == .reveal && code
                    .action(at: 0, revealed: true) == .copy("show secret"),
                "partial code overlap copied secret",
            )

            let view = MessageTextContentView(frame: CGRect(x: 0, y: 0, width: 280, height: 180), textContainer: nil)
            view.configurePresentation(
                state: state,
                client: nil,
                statusText: "12:00",
                statusColor: .secondaryLabel,
                maximumWidth: 280,
            )
            view.layoutIfNeeded()
            let concealedHeight = view.intrinsicContentSize.height
            try require(view.accessibilityValue == "", "UITextView default AX value leaked")
            try require(
                view.attributedText.attribute(.link, at: secret.location, effectiveRange: nil) == nil,
                "concealed link attribute",
            )
            try require(
                (
                    view.attributedText.attribute(
                        .foregroundColor,
                        at: secret.location,
                        effectiveRange: nil,
                    ) as? UIColor
                ) ==
                    .clear,
                "concealed glyph visible",
            )
            let oldGeneration = view.debugCustomEmojiGeneration
            try require(!view.permitsCustomEmoji(range: emoji, generation: oldGeneration), "concealed emoji admitted")
            var actions = [MessageTextSpoilerPresentation.Action]()
            view.activateEntity(at: CGPoint(x: 275, y: 170)) { actions.append($0) }
            try require(actions.isEmpty && !state.revealed, "padding revealed or activated entity")
            let glyphs = view.layoutManager.glyphRange(
                forCharacterRange: NSRange(location: secret.location, length: 1),
                actualCharacterRange: nil,
            )
            let rect = view.layoutManager.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
            try require(!rect.isEmpty, "missing glyph layout")
            let point = CGPoint(x: rect.midX, y: rect.midY)
            view.activateEntity(at: point) { actions.append($0) }
            // The reveal is reported so the tap handler counts it as handled; nothing else is dispatched.
            try require(
                state.revealed && !second.revealed && actions == [.reveal],
                "first tap dispatched or revealed another album source",
            )
            try require(
                view.accessibilityLabel == text.text && view.intrinsicContentSize.height == concealedHeight,
                "reveal changed AX or geometry",
            )
            try require(
                view.permitsCustomEmoji(range: emoji, generation: view.debugCustomEmojiGeneration),
                "revealed emoji denied",
            )
            try require(
                !view.permitsCustomEmoji(range: emoji, generation: oldGeneration),
                "old emoji completion admitted",
            )
            actions.removeAll()
            view.activateEntity(at: point) { actions.append($0) }
            try require(
                actions == [.open(URL(string: "https://example.invalid/secret")!)],
                "second tap missed actionable entity after bold",
            )

            store.configure(source: source, chatID: 10, texts: [1: text, 2: text])
            try require(store.states[1] === state && state.revealed, "same-content configure reset reveal")
            let edited = FormattedText(entities: text.entities, text: text.text + "!")
            store.configure(source: source, chatID: 10, texts: [1: edited])
            try require(
                store.states[1] !== state && store.states[1]?.revealed == false && !second.reveal(),
                "edit or removed source retained authority",
            )
            for (nextSource, nextChat) in [
                (TdUpdateSource(accountID: source.accountID, clientID: 101), Int64(10)),
                (TdUpdateSource(accountID: UUID(), clientID: 101), Int64(10)),
                (source, Int64(11)),
            ] {
                let stale = store.states[1]
                store.configure(source: nextSource, chatID: nextChat, texts: [1: text])
                try require(
                    stale?.reveal() == false && store.states[1]?.revealed == false,
                    "source/chat replacement accepted stale reveal",
                )
            }
            let stale = store.states[1]
            store.reset()
            try require(stale?.reveal() == false, "reuse retained reveal authority")
            store.configure(source: nil, chatID: 10, texts: [1: text])
            try require(store.states[1]?.reveal() == false, "nil source revealed")
            view.prepareForReuse()
            try require(
                view.accessibilityLabel == nil && !view.permitsCustomEmoji(range: emoji, generation: oldGeneration),
                "view reuse leaked AX/emoji",
            )
            try require(view.accessibilityValue?.isEmpty != false, "view reuse retained raw AX value")
            view.configurePresentation(
                state: MessageTextSpoilerState(text: text, source: source), client: nil,
                statusText: "", statusColor: .secondaryLabel, maximumWidth: 280,
            )
            try require(
                view.accessibilityLabel?.contains("HIDDEN") == false && view.accessibilityValue == "",
                "standalone caption AX leaked",
            )
            try verifyParentAndPreviews(text: text, source: source)
        }

        private static func verifyParentAndPreviews(text: FormattedText, source: TdUpdateSource) throws {
            let state = MessageTextSpoilerState(text: text, source: source)
            let cell = MessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            var otherActionCount = 0
            let existing = UIAccessibilityCustomAction(name: "Reply") { _ in otherActionCount += 1
            return true
            }
            func refresh() {
                cell.updateSpoilerAccessibility(
                    content: state.presentation.accessibilityText(revealed: state.revealed), prefix: ["Sender"],
                    suffix: ["12:00"],
                    states: [state], actions: [existing],
                )
            }
            let subscription = state.changes.sink { refresh() }
            defer { subscription.cancel() }
            refresh()
            try require(cell.accessibilityLabel?.contains("HIDDEN") == false, "parent AX leaked")
            guard let reveal = cell.accessibilityCustomActions?.first(where: { $0.name == "Reveal spoilers" }) else {
                throw Failure(description: "parent reveal action missing")
            }
            try require(
                reveal.actionHandler?(reveal) == true && cell.accessibilityLabel?.contains("HIDDEN") == true,
                "parent action did not reveal/redeliver AX",
            )
            try require(
                cell.accessibilityCustomActions?.count == 1 && existing
                    .actionHandler?(existing) == true && otherActionCount == 1,
                "metadata AX action lost",
            )

            let reply = ReplySnippetView()
            var replyTaps = 0
            let quote = TextQuote(isManual: true, position: 0, text: text)
            let presentation = MessageReplyPresentation(
                availability: .inline, body: text, navigationTarget: .message(chatID: 10, messageID: 1, quote: nil),
                quote: quote, referencedChatID: nil, referencedUserID: nil, targetChatID: 10, targetMessageID: 1,
                thumbnail: nil, title: "Sender",
            )
            reply.configure(presentation: presentation, expanded: false, client: nil) { _ in replyTaps += 1 }
            try require(reply.accessibilityLabel?.contains("HIDDEN") == false, "reply AX leaked")
            reply.sendActions(for: .touchUpInside)
            try require(replyTaps == 1, "reply navigation consumed by reveal")
            reply.configure(title: "Quote", quote: .init(position: 0, text: text)) { replyTaps += 1 }
            try require(reply.accessibilityLabel?.contains("HIDDEN") == false, "composer quote AX leaked")
            let message = message(text: text)
            try require(ChatSummary.summary(for: message).contains("HIDDEN") == false, "summary fallback leaked")
            reply.configure(title: "Reply", message: message) { replyTaps += 1 }
            try require(reply.accessibilityLabel?.contains("HIDDEN") == false, "plain reply summary leaked")
        }

        private static func message(text: FormattedText) -> Message {
            Message(
                id: 1,
                senderId: .messageSenderUser(.init(userId: 1)),
                receiverId: nil,
                chatId: 10,
                sendingState: nil,
                schedulingState: nil,
                isOutgoing: false,
                isPinned: false,
                isFromOffline: false,
                canBeSaved: true,
                hasTimestampedMedia: false,
                isChannelPost: false,
                isPaidStarSuggestedPost: false,
                isPaidGramSuggestedPost: false,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                date: 1,
                editDate: 0,
                forwardInfo: nil,
                importInfo: nil,
                interactionInfo: nil,
                unreadReactions: [],
                factCheck: nil,
                suggestedPostInfo: nil,
                replyTo: nil,
                topicId: nil,
                selfDestructType: nil,
                selfDestructIn: 0,
                autoDeleteIn: 0,
                viaBotUserId: 0,
                guestBotCallerId: nil,
                senderBusinessBotUserId: 0,
                senderBoostCount: 0,
                senderTag: "",
                paidMessageStarCount: 0,
                authorSignature: "",
                mediaAlbumId: 0,
                effectId: 0,
                restrictionInfo: nil,
                summaryLanguageCode: "",
                content: .messageText(.init(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: text,
                )),
                ephemeralContent: nil,
                replyMarkup: nil,
                ephemeralMessageId: 0,
                chatInstance: 0,
            )
        }
    }
#endif
