// MediaDraftCodingProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    enum MediaDraftCodingProbe {
        private static var resultURL: URL {
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("media-draft-coding-probe.txt")
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-draft-coding") else { return }
            do {
                try verifyLegacyDrafts()
                try verifyNativeTextEntities()
                log("Media draft coding probe passed")
                try Data("passed".utf8).write(to: resultURL, options: .atomic)
            } catch {
                log("Media draft coding probe failed: \(error)")
                try? Data("failed: \(error)".utf8).write(to: resultURL, options: .atomic)
                assertionFailure("Media draft coding probe failed: \(error)")
            }
        }

        private static func verifyLegacyDrafts() throws {
            let legacy = #"""
            {
                "id": "D04FCF41-BEDF-4053-9933-1051BD488834",
                "chatID": 123,
                "caption": {
                    "text": "Bold link emoji",
                    "entities": [
                        {"offset": 0, "length": 4, "type": {"@type": "textEntityTypeBold"}},
                        {"offset": 5, "length": 4, "type": {"@type": "textEntityTypeTextUrl", "url": "https://telegram.org"}},
                        {"offset": 10, "length": 5, "type": {"@type": "textEntityTypeCustomEmoji", "customEmojiId": "9223372036854775806"}}
                    ]
                },
                "createdAt": 100,
                "duration": 2,
                "fileURL": "file:///tmp/legacy-voice.ogg",
                "isEncoded": true,
                "replyMessageID": 456,
                "replyTo": {
                    "@type": "inputMessageReplyToMessage",
                    "checklistTaskId": 7,
                    "messageId": 456,
                    "pollOptionId": "option",
                    "quote": {"position": 1, "text": {"text": "quote", "entities": []}}
                },
                "waveform": "AQID"
            }
            """#
            let decoder = JSONDecoder()
            let draft = try decoder.decode(VoiceNoteSendDraft.self, from: Data(legacy.utf8))
            let restored = try decoder.decode(VoiceNoteSendDraft.self, from: JSONEncoder().encode(draft))
            precondition(restored.id == draft.id && restored.fileURL == draft.fileURL)
            precondition(restored.caption == draft.caption && restored.replyTo == draft.replyTo)
            precondition(restored.waveform == Data([1, 2, 3]))
            precondition(MediaDraftFormattedText(restored.caption.native) == draft.caption)
            precondition(restored.replyTo.map { MediaDraftInputMessageReplyTo($0.native) } == draft.replyTo)

            let replies = [
                #"{"@type":"inputMessageReplyToExternalMessage","chatId":-100123,"checklistTaskId":2,"messageId":789,"pollOptionId":"x","quote":null}"#,
                #"{"@type":"inputMessageReplyToStory","storyId":9,"storyPosterChatId":123}"#,
                #"{"@type":"inputMessageReplyToEphemeralMessage","ephemeralMessageId":8}"#,
            ]
            for json in replies {
                let reply = try decoder.decode(MediaDraftInputMessageReplyTo.self, from: Data(json.utf8))
                try roundTrip(reply)
                precondition(MediaDraftInputMessageReplyTo(reply.native) == reply)
            }
        }

        private static func verifyNativeTextEntities() throws {
            let types: [TDNativeTextEntityType] = [
                .textEntityTypeMention, .textEntityTypeHashtag, .textEntityTypeCashtag,
                .textEntityTypeBotCommand, .textEntityTypeUrl, .textEntityTypeEmailAddress,
                .textEntityTypePhoneNumber, .textEntityTypeBankCardNumber, .textEntityTypeBold,
                .textEntityTypeItalic, .textEntityTypeUnderline, .textEntityTypeStrikethrough,
                .textEntityTypeSpoiler, .textEntityTypeCode, .textEntityTypePre,
                .textEntityTypePreCode(.init(language: "swift")), .textEntityTypeBlockQuote,
                .textEntityTypeExpandableBlockQuote, .textEntityTypeTextUrl(.init(url: "https://telegram.org")),
                .textEntityTypeMentionName(.init(userId: Int64.max - 1)),
                .textEntityTypeCustomEmoji(.init(customEmojiId: Int64.max - 1)),
                .textEntityTypeMediaTimestamp(.init(mediaTimestamp: 42)),
                .textEntityTypeDateTime(.init(unixTime: 123, formattingType: nil)),
                .textEntityTypeDateTime(.init(unixTime: 123, formattingType: .dateTimeFormattingTypeRelative)),
                .textEntityTypeDateTime(.init(unixTime: 123, formattingType: .dateTimeFormattingTypeAbsolute(.init(
                    timePrecision: .dateTimePartPrecisionShort,
                    datePrecision: .dateTimePartPrecisionLong,
                    showDayOfWeek: true,
                )))),
            ]
            for type in types {
                let text = TDNativeFormattedText(text: "test", entities: [.init(offset: 0, length: 4, type: type)])
                let snapshot = MediaDraftFormattedText(text)
                try roundTrip(snapshot)
                precondition(MediaDraftFormattedText(snapshot.native) == snapshot)
            }
        }

        private static func roundTrip(_ value: some Codable & Equatable) throws {
            let decoded = try JSONDecoder().decode(type(of: value), from: JSONEncoder().encode(value))
            precondition(decoded == value)
        }
    }
#endif
