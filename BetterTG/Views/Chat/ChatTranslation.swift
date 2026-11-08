// ChatTranslation.swift

import Foundation
import NaturalLanguage
import TDLibKit

// MARK: - ChatTranslationState

/// Telegram's ChatTranslationState for a chat or topic: the language its incoming messages are in, the one they are
/// translated to (the app language until another is chosen), and whether translation is on.
struct ChatTranslationState: Codable, Equatable {
    var baseLang: String
    var fromLang: String
    /// When `fromLang` was detected; chatTranslationState trusts it for an hour.
    var timestamp: Int
    var toLang: String?
    var isEnabled: Bool

    var effectiveToLang: String {
        toLang ?? baseLang
    }
}

// MARK: - ChatTranslation

/// Telegram's chat translation (TranslateUI/ChatTranslation.swift): Translate Entire Chat in the language settings,
/// the language a chat is written in, recognised from its latest incoming texts, and each chat's state, kept per
/// account as Telegram keeps it in its item cache.
enum ChatTranslation {
    private static let translateChatsKey = "BetterTG.translateChats"
    private static let statesKey = "BetterTG.chatTranslationStates"
    /// chatTranslationState's cache lifetime for a detected language.
    private static let detectionLifetime = 60 * 60

    /// TranslationSettings.translateChats, on by default; it takes effect with Premium.
    static var translatesChats: Bool {
        get { UserDefaults.standard.object(forKey: translateChatsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: translateChatsKey) }
    }

    static func key(accountID: UUID, chatID: Int64, topicKey: String?) -> String {
        [accountID.uuidString, String(chatID), topicKey].compactMap(\.self).joined(separator: ":")
    }

    static func state(for key: String) -> ChatTranslationState? {
        guard let data = (UserDefaults.standard.dictionary(forKey: statesKey) as? [String: Data])?[key] else {
            return nil
        }
        return try? JSONDecoder().decode(ChatTranslationState.self, from: data)
    }

    static func setState(_ state: ChatTranslationState?, for key: String) {
        var states = UserDefaults.standard.dictionary(forKey: statesKey) as? [String: Data] ?? [:]
        states[key] = state.flatMap { try? JSONEncoder().encode($0) }
        UserDefaults.standard.set(states, forKey: statesKey)
    }

    /// The cached state while its detection is fresh and made for the same app language.
    static func freshState(for key: String, baseLang: String, now: Int) -> ChatTranslationState? {
        guard let cached = state(for: key), cached.baseLang == baseLang, now - cached.timestamp < detectionLifetime
        else { return nil }
        return cached
    }

    /// chatTranslationState's recognition: up to 16 incoming texts of 10 characters or more, their code, links,
    /// mentions, hashtags and commands removed, each counted by its length for the language it is in; the language
    /// with the most characters wins.
    static func detectLanguage(of messages: [Message]) -> String {
        var counts = [String: Int]()
        var recognised = 0
        let recognizer = NLLanguageRecognizer()
        for message in messages where !message.isOutgoing {
            guard let text = MessageContentPresentation.make(message).formattedText, text.text.count >= 10 else {
                continue
            }
            let cleaned = Self.textForRecognition(text)
            recognizer.processString(cleaned)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 4)
            recognizer.reset()
            guard let language = hypotheses
                .map({ (MessageTranslation.normalizedLanguage($0.key.rawValue), $0.value) })
                .filter({ MessageTranslation.isSupportedLanguage($0.0) })
                .max(by: { $0.1 < $1.1 })?
                .0
            else { continue }
            counts[language, default: 0] += text.text.count
            recognised += 1
            if recognised >= 16 { break }
        }
        return counts.max { $0.value < $1.value }?.key ?? ""
    }

    /// The text's first 256 characters without its pre, code, URL, email, mention, hashtag and command entities.
    private static func textForRecognition(_ text: FormattedText) -> String {
        let prefix = String(text.text.prefix(256))
        var utf16 = Array(prefix.utf16)
        let removed = text.entities
            .filter { entity in
                switch entity.type {
                case .textEntityTypeBotCommand,
                     .textEntityTypeCode,
                     .textEntityTypeEmailAddress,
                     .textEntityTypeHashtag,
                     .textEntityTypeMention,
                     .textEntityTypePre,
                     .textEntityTypePreCode,
                     .textEntityTypeUrl: true
                default: false
                }
            }
            .sorted { $0.offset > $1.offset }
        for entity in removed where entity.offset + entity.length <= utf16.count {
            utf16.removeSubrange(entity.offset..<(entity.offset + entity.length))
        }
        return String(decoding: utf16, as: UTF16.self)
    }
}
