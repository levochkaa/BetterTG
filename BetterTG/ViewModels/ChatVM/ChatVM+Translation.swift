// ChatVM+Translation.swift

import Foundation
import TDLibKit

// MARK: - ChatVM + Translation

extension ChatVM {
    /// Telegram's service notifications are never translated.
    private static let serviceNotificationsChatID: Int64 = 777_000

    private var translationKey: String? {
        guard let accountID else { return nil }
        let topicKey = location.forumTopicID.map { "f\($0)" }
            ?? location.messageThreadID.map { "t\($0)" }
            ?? location.savedMessagesTopicID.map { "s\($0)" }
        return ChatTranslation.key(accountID: accountID, chatID: chatID, topicKey: topicKey)
    }

    /// chatTranslationState: once the chat shows more than one message, with Premium and Translate Entire Chat on (or
    /// a channel that translates itself), and while the translation bar isn't hidden, the language its latest
    /// incoming texts are in. A language on the Do Not Translate list leaves the chat alone.
    func refreshTranslationStateIfNeeded() {
        guard !translationDetectionStarted, messages.count > 1, let key = translationKey,
              chatID != Self.serviceNotificationsChatID, !customChat.isSavedMessages
        else { return }
        translationDetectionStarted = true
        let client = client
        let sample = messages
            .map(\.message)
            .sorted { $0.id > $1.id }
            .prefix(32)
        let autoTranslates = customChat.supergroup?.hasAutomaticTranslation == true
        Task { [weak self] in
            let isPremium = await (try? client.getMe())?.isPremium ?? false
            guard let self, locationContextIsCurrent,
                  (isPremium && ChatTranslation.translatesChats) || autoTranslates,
                  customChat.chat.isTranslatable || autoTranslates
            else { return }
            let baseLang = MessageTranslation.appLanguageCode
            let now = Int(Date().timeIntervalSince1970)
            let state: ChatTranslationState
            if let fresh = ChatTranslation.freshState(for: key, baseLang: baseLang, now: now) {
                state = fresh
            } else {
                let cached = ChatTranslation.state(for: key)
                state = ChatTranslationState(
                    baseLang: baseLang,
                    fromLang: ChatTranslation.detectLanguage(of: Array(sample)),
                    timestamp: now,
                    toLang: cached?.toLang,
                    isEnabled: cached?.isEnabled ?? autoTranslates,
                )
                ChatTranslation.setState(state, for: key)
            }
            guard !state.fromLang.isEmpty, !MessageTranslation.ignoredLanguages.contains(state.fromLang) else { return }
            translationState = state
            applyTranslations()
        }
    }

    /// toggleTranslation: Translate to … or Show Original.
    func setTranslationEnabled(_ isEnabled: Bool) {
        updateTranslationState { $0.isEnabled = isEnabled }
    }

    /// changeTranslationLanguage: the chat translates to the chosen language from now on.
    func setTranslationLanguage(_ code: String) {
        let code = MessageTranslation.normalizedLanguage(code)
        updateTranslationState {
            $0.toLang = code
            $0.isEnabled = true
        }
    }

    /// addDoNotTranslateLanguage: the chat's language joins the Do Not Translate list, and the chat forgets its state.
    func doNotTranslate(_ code: String) {
        MessageTranslation.setIgnored(code, true)
        if let translationKey { ChatTranslation.setState(nil, for: translationKey) }
        translationState = nil
        applyTranslations()
    }

    /// hideTranslationPanel (togglePeerMessagesTranslationHidden): the chat's bar goes away, or comes back on Undo.
    func setTranslationHidden(_ isHidden: Bool) {
        let client = client
        let chatID = chatID
        Task {
            _ = try? await client.send(TDNativeRequests.toggleChatIsTranslatable(
                chatId: chatID,
                isTranslatable: !isHidden,
            ))
        }
        if isHidden {
            translationState = nil
            applyTranslations()
        } else {
            translationDetectionStarted = false
            refreshTranslationStateIfNeeded()
        }
    }

    /// ChatHistoryListNode's translation of what it shows: a translated chat asks TDLib for a message's text in its
    /// language the first time the message comes into view. The account's own messages stay as they are.
    func translateIfNeeded(_ message: CustomMessage) {
        guard let state = translationState, state.isEnabled, !message.message.isOutgoing,
              let text = message.formattedText, !text.text.isEmpty
        else { return }
        let language = state.effectiveToLang
        if let known = translatedTexts[message.id]?[language] {
            if message.translatedText != known { message.translatedText = known }
            return
        }
        let requestKey = "\(message.id):\(language)"
        guard translationRequests.insert(requestKey).inserted else { return }
        // An album's text belongs to the message whose caption it is.
        let sourceID = message.sourceMessages
            .first { MessageContentPresentation.make($0).formattedText == text }?
            .id ?? message.id
        let client = client
        let chatID = chatID
        let messageID = message.id
        Task { [weak self, weak message] in
            let result = try? await client.send(TDNativeRequests.translateMessageText(
                chatId: chatID,
                messageId: sourceID,
                toLanguageCode: language,
                tone: "",
            ))
            guard let self, locationContextIsCurrent else { return }
            translationRequests.remove(requestKey)
            guard let result else { return }
            translatedTexts[messageID, default: [:]][language] = result
            guard let message, let current = translationState, current.isEnabled,
                  current.effectiveToLang == language else { return }
            message.translatedText = result
        }
    }

    /// The loaded messages show their translations in the current language, or their originals.
    func applyTranslations() {
        let language = translationState.flatMap { $0.isEnabled ? $0.effectiveToLang : nil }
        for message in messages {
            let translated = language.flatMap { translatedTexts[message.id]?[$0] }
            if message.translatedText != translated { message.translatedText = translated }
        }
    }

    private func updateTranslationState(_ change: (inout ChatTranslationState) -> Void) {
        guard var state = translationState else { return }
        change(&state)
        translationState = state
        if let translationKey { ChatTranslation.setState(state, for: translationKey) }
        applyTranslations()
    }
}
