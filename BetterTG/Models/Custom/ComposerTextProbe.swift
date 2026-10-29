// ComposerTextProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    @MainActor enum ComposerTextProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        private static var fixtureContact: InputMessageContent {
            DeviceContactMessage.content(
                phoneNumber: "155501000", firstName: "Fixture", lastName: "", organization: "", vcard: "", userID: 0,
            )
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-composer-entities") else { return }
            Task { @MainActor in
                let result: String
                do {
                    try verify()
                    let undoVerified = try verifyUndo()
                    result = "Composer entities probe passed: manual-payload/UTF16/scoped-bridge/fallback=true; "
                        + "UITextView-callback/edit-attempt/draft/snapshot=true; overlapping-toggles/range-edits/caret=true; "
                        + "RTF-whitelist/automatic-types/identity-isolation=true; marked-model-feedback=true; "
                        + "UIKit-undo-redo=\(undoVerified); attachment-comments/order/reply/split=true; "
                        + "clipboard/URL/server/account-stores=0; live-IME/keyboard-undo=pending"
                } catch {
                    result = "Composer entities probe failed: \(error)"
                }
                log(result)
                if let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: root.appendingPathComponent("composer-entities-probe.txt"),
                        options: .atomic,
                    )
                }
            }
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw Failure(description: detail) }
        }

        private static func same(_ actual: FormattedText, _ expected: FormattedText, _ detail: String) throws {
            try require(actual.text == expected.text && Set(actual.entities) == Set(expected.entities), detail)
        }

        private static func verify() throws {
            let types: [TextEntityType] = [
                .textEntityTypeBold, .textEntityTypeItalic, .textEntityTypeUnderline, .textEntityTypeStrikethrough,
                .textEntityTypeSpoiler, .textEntityTypeCode, .textEntityTypePre,
                .textEntityTypePreCode(.init(language: "swift")), .textEntityTypeBlockQuote,
                .textEntityTypeExpandableBlockQuote, .textEntityTypeTextUrl(.init(url: "tg://user?id=42")),
                .textEntityTypeMentionName(.init(userId: 42)), .textEntityTypeCustomEmoji(.init(customEmojiId: 123)),
                .textEntityTypeDateTime(.init(
                    unixTime: 1_800_000_000,
                    formattingType: .dateTimeFormattingTypeRelative,
                )),
            ]
            for type in types {
                let formatted = FormattedText(entities: [.init(length: 2, offset: 1, type: type)], text: "a🙂b")
                let value = ComposerText.attributed(formatted)
                try same(ComposerText.formatted(value), formatted, "manual round trip \(type)")
                try verifyAttachmentComment(value, expected: formatted)
                try same(
                    ComposerText.formatted(ComposerText.value(ComposerText.uiKit(value))),
                    formatted,
                    "scoped bridge \(type)",
                )
                try same(
                    ComposerText.formatted(ComposerText.semanticValue(ComposerText.uiKit(value))),
                    formatted,
                    "Swift fallback \(type)",
                )
                try same(ComposerText.formatted(ComposerText.semanticUIKit(value)), formatted, "UIKit fallback \(type)")
            }
            try verifyRanges()
            try verifyFieldAndOwnership()
            try verifyFormatting()
            try verifyTyping()
            try verifyExternalText()
            try verifyMarkedTextFeedback()
            try verifyLongAttachmentComment()
        }

        private static func verifyAttachmentComment(_ comment: AttributedString, expected: FormattedText) throws {
            let items = AttachmentMessageSequence.items(contents: [fixtureContact, fixtureContact], comment: comment)
            try require(items.count == 3, "comment before two cards")
            guard case .inputMessageText(let input) = items[0].content else {
                throw Failure(description: "comment is not first")
            }
            try same(input.text, expected, "contact comment entities")
            try require(!input.clearDraft && !items[0].repliesToComposer, "comment changed draft or reply")
            for item in items.dropFirst() {
                guard case .inputMessageContact = item.content else { throw Failure(description: "card order") }
                try require(item.repliesToComposer, "card lost reply")
            }
        }

        private static func verifyLongAttachmentComment() throws {
            let text = String(repeating: "a", count: 4095) + "🙂tail"
            let comment = ComposerText.attributed(FormattedText(entities: [
                .init(length: 6, offset: 4095, type: .textEntityTypeBold),
            ], text: text))
            let items = AttachmentMessageSequence.items(contents: [fixtureContact], comment: comment)
            try require(items.count == 3, "long comment split count")
            let parts = items.compactMap { item -> FormattedText? in
                guard case .inputMessageText(let value) = item.content else { return nil }
                return value.text
            }
            try require(parts.map(\.text).joined() == text, "UTF16 split lost text")
            try require(parts.allSatisfy { $0.text.utf16.count <= 4096 }, "comment exceeds message limit")
            try same(parts[1], FormattedText(entities: [
                .init(length: 6, offset: 0, type: .textEntityTypeBold),
            ], text: "🙂tail"), "entity across comment split")
            try require(AttachmentMessageSequence.items(contents: [], comment: comment).isEmpty, "orphan comment")
            let noComment = AttachmentMessageSequence.items(
                contents: [fixtureContact],
                comment: AttributedString(" \n "),
            )
            try require(noComment.count == 1 && noComment[0].repliesToComposer, "blank comment sent")
        }

        private static func verifyMarkedTextFeedback() throws {
            let field = FormattedTextView(placeholder: "")
            field.onTextChange = { [weak field] value in field?.setAttributedText(value) }
            field.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
            try require(field.text == "ni" && field.markedTextRange != nil, "model feedback ended marked text")
            try require(!field.permitsClientRestoration, "marked composition allowed route replacement")
            field.setMarkedText("你", selectedRange: NSRange(location: 1, length: 0))
            try require(
                field.text == "你" && field.markedTextRange != nil,
                "second marked candidate lost composition: text=\(field.text ?? "nil") marked=\(field.markedTextRange != nil)",
            )
            field.unmarkText()
            try require(field.text == "你" && field.markedTextRange == nil, "marked commit lost text")
        }

        private static func verifyUndo() throws -> Bool {
            let field = FormattedTextView(placeholder: "")
            let original = FormattedText(entities: [
                .init(length: 4, offset: 0, type: .textEntityTypeItalic),
            ], text: "word")
            field.setAttributedText(ComposerText.attributed(original))
            guard let manager = field.undoManager else { return false }
            manager.removeAllActions()
            field.selectedRange = NSRange(location: 0, length: 4)
            manager.beginUndoGrouping()
            field.toggleFormatting(.textEntityTypeBold)
            manager.endUndoGrouping()
            let formatted = ComposerText.formatted(field.attributedText)
            try require(manager.canUndo, "formatting undo not registered")
            manager.undo()
            try same(ComposerText.formatted(field.attributedText), original, "formatting undo changed semantics")
            try require(manager.canRedo, "formatting redo not registered")
            manager.redo()
            try same(ComposerText.formatted(field.attributedText), formatted, "formatting redo changed semantics")
            field.selectedRange = NSRange(location: 4, length: 0)
            manager.beginUndoGrouping()
            field.receivePastedText(NSAttributedString(string: "!"))
            manager.endUndoGrouping()
            let pasted = ComposerText.formatted(field.attributedText)
            try require(pasted.text == "word!" && manager.canUndo, "paste undo not registered")
            manager.undo()
            try same(ComposerText.formatted(field.attributedText), formatted, "paste undo changed semantics")
            try require(manager.canRedo, "paste redo not registered")
            manager.redo()
            try same(ComposerText.formatted(field.attributedText), pasted, "paste redo changed semantics")
            return true
        }

        private static func verifyRanges() throws {
            for range in [
                NSRange(location: 1, length: 1),
                NSRange(location: 0, length: 1),
                NSRange(location: -1, length: 1),
                // TDLibKit 2 entities hold Int32 offsets and lengths; the largest one is still out of range.
                NSRange(location: 1, length: Int(Int32.max)),
            ] {
                let text = FormattedText(
                    entities: [.init(length: range.length, offset: range.location, type: .textEntityTypeBold)],
                    text: "🙂",
                )
                try require(
                    ComposerText.formatted(ComposerText.attributed(text)).entities.isEmpty,
                    "invalid UTF16 range \(range)",
                )
            }
            for string in ["e\u{301}", "👩‍💻", "אבג"] {
                let range = string == "e\u{301}"
                    ? NSRange(location: 1, length: 1)
                    : NSRange(location: 0, length: string.utf16.count)
                let text = FormattedText(
                    entities: [.init(length: range.length, offset: range.location, type: .textEntityTypeItalic)],
                    text: string,
                )
                let value = ComposerText.attributed(text)
                try same(ComposerText.formatted(value), text, "valid scalar range")
                try same(
                    ComposerText.formatted(ComposerText.semanticValue(ComposerText.uiKit(value))),
                    text,
                    "scalar fallback",
                )
            }
            let emoji = TextEntityType.textEntityTypeCustomEmoji(.init(customEmojiId: 123))
            let pair = FormattedText(entities: [
                .init(length: 2, offset: 0, type: emoji), .init(length: 2, offset: 2, type: emoji),
            ], text: "🙂🙂")
            let field = FormattedTextView(placeholder: "")
            field.setAttributedText(ComposerText.attributed(pair))
            field.selectedRange = NSRange(location: 0, length: 0)
            field.insertText("x")
            try same(ComposerText.formatted(field.attributedText), .init(entities: [
                .init(length: 2, offset: 1, type: emoji), .init(length: 2, offset: 3, type: emoji),
            ], text: "x🙂🙂"), "emoji shift or adjacent identity merged")
            field.selectedRange = NSRange(location: 1, length: 2)
            field.insertText("A")
            try same(ComposerText.formatted(field.attributedText), .init(entities: [
                .init(length: 2, offset: 2, type: emoji),
            ], text: "xA🙂"), "emoji identity copied into replacement")
        }

        private static func verifyFieldAndOwnership() throws {
            let formatted = FormattedText(entities: [
                .init(length: 4, offset: 0, type: .textEntityTypeBold),
                .init(length: 4, offset: 0, type: .textEntityTypeItalic),
                .init(length: 4, offset: 5, type: .textEntityTypeTextUrl(.init(url: "https://example.invalid/a?x=1"))),
                .init(length: 4, offset: 5, type: .textEntityTypeSpoiler),
            ], text: "bold link")
            let field = FormattedTextView(placeholder: "")
            field.frame = CGRect(x: 0, y: 0, width: 300, height: 120)
            field.setAttributedText(ComposerText.attributed(formatted))
            var callback: AttributedString?
            field.onTextChange = { callback = $0 }
            field.selectedRange = NSRange(location: field.text.utf16.count, length: 0)
            field.insertText("!")
            guard let callback
                else { throw Failure(description: "UITextView insert did not deliver production callback") }
            let expected = FormattedText(entities: formatted.entities, text: "bold link!")
            try same(ComposerText.formatted(callback), expected, "callback semantics")
            let state = ChatComposerEditState()
            let message = fixture(expected)
            guard case .edit(let attempt) = state.prepare(message: message, text: callback) else {
                throw Failure(description: "real edit preparation")
            }
            try same(attempt.text, expected, "edit attempt payload")
            let draft = DraftMessage(content: .draftMessageContentText(.init(
                linkPreviewOptions: nil, text: .init(entities: getEntities(from: callback), text: callback.string),
            )), date: 1, effectId: 0, replyTo: nil, suggestedPostInfo: nil)
            // TDLibKit 2 sends this native object without a JSON transport step.
            let restored = draft
            guard case .draftMessageContentText(let content) = restored.content else {
                throw Failure(description: "draft schema")
            }
            try same(content.text, expected, "draft serialized payload")
            let accountID = UUID()
            let location = ChatLocation(accountID: accountID, chatID: 100, clientID: 1, topic: nil)
            let target = ChatComposerRestorationState.MessageValue(CustomMessage(
                message: message,
                properties: .default,
            ))
            let snapshot = ChatComposerRestorationState(
                location: location, revision: 1, text: callback, edit: .init(target: target, text: callback),
                replyMessage: nil, replyTo: nil, images: [], documents: [], sendError: nil, draftError: nil,
            )
            let transfer = ChatComposerRestorationTransfer(snapshot: snapshot, retireOwner: { true })
            let destination = ChatLocation(accountID: accountID, chatID: 100, clientID: 2, topic: nil)
            let replacement = transfer.commit(to: destination, currentSource: .init(
                accountID: accountID,
                clientID: 2,
            )) { seed in
                let field = FormattedTextView(placeholder: "")
                field.setAttributedText(seed.edit?.text ?? seed.text)
                return field
            }
            guard let replacement else { throw Failure(description: "snapshot transfer") }
            try same(ComposerText.formatted(replacement.attributedText), expected, "snapshot semantic bridge")
            replacement.selectedRange = NSRange(location: 0, length: 4)
            replacement.toggleFormatting(.textEntityTypeBold)
            try same(attempt.text, expected, "captured attempt mutated")
            try same(ComposerText.formatted(snapshot.text), expected, "captured snapshot mutated")
        }

        private static func verifyFormatting() throws {
            let field = FormattedTextView(placeholder: "")
            field.setAttributedText(ComposerText.attributed(.init(entities: [], text: "abcdef")))
            field.selectedRange = NSRange(location: 0, length: 4)
            field.toggleFormatting(.textEntityTypeBold)
            field.selectedRange = NSRange(location: 2, length: 4)
            field.toggleFormatting(.textEntityTypeItalic)
            var value = ComposerText.formatted(field.attributedText)
            try require(covered(.textEntityTypeBold, in: value) == Set(0..<4), "bold overwritten")
            try require(covered(.textEntityTypeItalic, in: value) == Set(2..<6), "italic missing")
            try require(!hasCrossingEntities(value), "mutually intersecting TD ranges")
            let font = field.attributedText.attribute(.font, at: 2, effectiveRange: nil) as? UIFont
            try require(
                font?.fontDescriptor.symbolicTraits.contains([.traitBold, .traitItalic]) == true,
                "overlap visual font",
            )
            field.selectedRange = NSRange(location: 0, length: 4)
            field.toggleFormatting(.textEntityTypeBold)
            value = ComposerText.formatted(field.attributedText)
            try require(
                covered(.textEntityTypeBold, in: value)
                    .isEmpty && covered(.textEntityTypeItalic, in: value) == Set(2..<6),
                "independent toggle",
            )
            field.selectedRange = NSRange(location: 2, length: 2)
            field.toggleFormatting(.textEntityTypeUnderline)
            field.toggleFormatting(.textEntityTypeUnderline)
            try same(ComposerText.formatted(field.attributedText), value, "toggle idempotence")
            field.toggleFormatting(.textEntityTypeCode)
            value = ComposerText.formatted(field.attributedText)
            try require(
                covered(.textEntityTypeCode, in: value) == Set(2..<4) && covered(.textEntityTypeItalic, in: value) ==
                    Set(4..<6),
                "code exclusivity",
            )
            field.toggleFormatting(.textEntityTypeBold)
            try same(ComposerText.formatted(field.attributedText), value, "style nested into exclusive code")
        }

        private static func verifyTyping() throws {
            for offset in [0, 2, 4] {
                let original = FormattedText(entities: [
                    .init(length: 4, offset: 0, type: .textEntityTypeBold),
                    .init(length: 4, offset: 0, type: .textEntityTypeItalic),
                    .init(length: 4, offset: 0, type: .textEntityTypeUnderline),
                    .init(length: 4, offset: 0, type: .textEntityTypeStrikethrough),
                    .init(length: 4, offset: 0, type: .textEntityTypeSpoiler),
                ], text: "word")
                let field = FormattedTextView(placeholder: "")
                field.setAttributedText(ComposerText.attributed(original))
                field.selectedRange = NSRange(location: offset, length: 0)
                field.insertText("x")
                let value = ComposerText.formatted(field.attributedText)
                try require(covered(.textEntityTypeBold, in: value) == Set(0..<5), "caret bold inheritance \(offset)")
                try require(
                    covered(.textEntityTypeItalic, in: value) == Set(0..<5),
                    "caret italic inheritance \(offset)",
                )
                for type: TextEntityType in [
                    .textEntityTypeUnderline,
                    .textEntityTypeStrikethrough,
                    .textEntityTypeSpoiler,
                ] {
                    try require(
                        !covered(type, in: value).contains(offset),
                        "caret copied non-typing attribute \(type), offset \(offset)",
                    )
                }
                field.selectedRange = NSRange(location: offset, length: 1)
                field.deleteBackward()
                try same(ComposerText.formatted(field.attributedText), original, "delete/rejoin spans \(offset)")
            }
            let type = TextEntityType.textEntityTypePreCode(.init(language: "swift"))
            let field = FormattedTextView(placeholder: "")
            field.setAttributedText(ComposerText.attributed(.init(
                entities: [.init(length: 4, offset: 0, type: type)],
                text: "code",
            )))
            field.selectedRange = NSRange(location: 2, length: 0)
            field.insertText("X")
            try same(
                ComposerText.formatted(field.attributedText),
                .init(entities: [.init(length: 5, offset: 0, type: type)], text: "coXde"),
                "inner block language",
            )
        }

        private static func verifyExternalText() throws {
            let descriptor = UIFont.systemFont(ofSize: 23).fontDescriptor.withSymbolicTraits([
                .traitBold,
                .traitItalic,
            ])!
            let external = NSAttributedString(string: "link", attributes: [
                .font: UIFont(descriptor: descriptor, size: 23), .backgroundColor: UIColor.red,
                .underlineStyle: 0, .strikethroughStyle: 1, .link: URL(string: "https://example.invalid/rtf")!,
            ])
            let rtf = try external.data(
                from: NSRange(location: 0, length: 4),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
            )
            let decoded = try NSAttributedString(
                data: rtf,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil,
            )
            let field = FormattedTextView(placeholder: "")
            field.receivePastedText(decoded)
            let imported = ComposerText.formatted(field.attributedText)
            try require(
                covered(.textEntityTypeBold, in: imported) == Set(0..<4) && covered(
                    .textEntityTypeItalic,
                    in: imported,
                ) == Set(0..<4),
                "RTF font traits",
            )
            try require(
                covered(.textEntityTypeSpoiler, in: imported).isEmpty && covered(.textEntityTypeUnderline, in: imported)
                    .isEmpty,
                "RTF color/zero style became entities",
            )
            try require(
                imported.entities.contains {
                    if case .textEntityTypeTextUrl = $0.type {
                        true
                    } else {
                        false
                    }
                },
                "RTF explicit link",
            )
            let forged = ComposerText.uiKit(ComposerText.attributed(.init(entities: [
                .init(length: 2, offset: 0, type: .textEntityTypeCustomEmoji(.init(customEmojiId: 123))),
                .init(length: 2, offset: 0, type: .textEntityTypeSpoiler),
            ], text: "🙂")))
            field.setAttributedText("")
            field.receivePastedText(forged)
            try require(
                ComposerText.formatted(field.attributedText).entities.isEmpty,
                "external private identity trusted",
            )
            field.setAttributedText("")
            field.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
            var admittedMidMutation = false
            field.onTextChange = { [weak field] _ in admittedMidMutation = field?.permitsClientRestoration == true }
            field.receivePastedText(NSAttributedString(string: "!"))
            try require(field.text == "ni!" && field.markedTextRange == nil, "paste discarded marked text")
            try require(!admittedMidMutation && field.permitsClientRestoration, "paste restoration barrier")
            let malformed = NSAttributedString(
                string: "plain",
                attributes: [.font: "not a font", .link: NSNull(), .backgroundColor: NSObject()],
            )
            try require(
                ComposerText.formatted(ComposerText.value(malformed)).entities.isEmpty,
                "untrusted attributes leaked",
            )
            let automatic: [TextEntityType] = [
                .textEntityTypeUrl,
                .textEntityTypeEmailAddress,
                .textEntityTypePhoneNumber,
                .textEntityTypeMention,
                .textEntityTypeHashtag,
                .textEntityTypeCashtag,
                .textEntityTypeBotCommand,
                .textEntityTypeBankCardNumber,
                .textEntityTypeMediaTimestamp(.init(mediaTimestamp: 42)),
            ]
            for type in automatic {
                let text = FormattedText(entities: [.init(length: 4, offset: 0, type: type)], text: "text")
                try same(
                    ComposerText.formatted(ComposerText.attributed(text)),
                    .init(entities: [], text: "text"),
                    "automatic type manually emitted \(type)",
                )
            }
        }

        private static func covered(_ type: TextEntityType, in value: FormattedText) -> Set<Int> {
            Set(value.entities.filter { $0.type == type }.flatMap { $0.offset..<($0.offset + $0.length) })
        }

        private static func hasCrossingEntities(_ value: FormattedText) -> Bool {
            value.entities.contains { a in value.entities.contains { b in
                a.offset < b.offset && b.offset < a.offset + a.length && a.offset + a.length < b.offset + b.length
            } }
        }

        private static func fixture(_ text: FormattedText) -> Message {
            Message(
                id: 42,
                senderId: .messageSenderUser(.init(userId: 1)),
                receiverId: nil,
                chatId: 100,
                sendingState: nil,
                schedulingState: nil,
                isOutgoing: true,
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
                content: .messageText(.init(linkPreview: nil, linkPreviewOptions: nil, text: text)),
                ephemeralContent: nil,
                replyMarkup: nil,
                ephemeralMessageId: 0,
                chatInstance: 0,
            )
        }
    }
#endif
