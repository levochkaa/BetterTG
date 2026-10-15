// ChatListActivities.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatListActivities

/// Who is typing, recording or sending in each chat, from the active client's `updateChatAction`, for the chat list
/// rows (Telegram's `inputActivities` in `ChatListItem`). TDLib sends `chatActionCancel` when an action ends.
@MainActor final class ChatListActivities {
    static let shared = ChatListActivities()

    /// The chat whose activities changed.
    let changes = PassthroughSubject<Int64, Never>()

    private var clientID: Int32?
    private var activities = [Int64: [(sender: MessageSender, action: ChatAction)]]()

    /// The `ChatListTypingNode` wording for one chat's actions, oldest first. A sender TDLib has not named yet is
    /// looked up, and `named` runs once it is known so the caller can ask again.
    static func text(
        for list: [(sender: MessageSender, action: ChatAction)],
        privateUserID: Int64?,
        client: TDLibClient,
        named: @escaping () -> Void,
    ) -> String? {
        guard !list.isEmpty else { return nil }
        if list.count > 1 {
            let names = list.prefix(2).map { name(for: $0.sender, client: client, named: named) }
            return list.count == 2
                ? L10n.telegram("DialogList.MultipleTypingPair", names[0], names[1])
                : L10n.telegram(
                    "DialogList.MultipleTyping", names[0],
                    L10n.telegram("DialogList.MultipleTypingSuffix", list.count - 1),
                )
        }
        let (sender, action) = list[0]
        if case .messageSenderUser(let user) = sender, privateUserID == user.userId {
            return text(for: action)
        }
        guard let key = suffixKey(for: action) else { return text(for: action) }
        return L10n.telegram(key, name(for: sender, client: client, named: named))
    }

    private static func text(for action: ChatAction) -> String? {
        switch action {
        case .chatActionTyping: L10n.telegram("DialogList.Typing")
        case .chatActionRecordingVideoNote: L10n.telegram("Activity.RecordingVideoMessage")
        case .chatActionUploadingVideoNote: L10n.telegram("Activity.UploadingVideoMessage")
        case .chatActionRecordingVideo, .chatActionUploadingVideo: L10n.telegram("Activity.UploadingVideo")
        case .chatActionRecordingVoiceNote: L10n.telegram("Activity.RecordingAudio")
        case .chatActionUploadingDocument, .chatActionUploadingVoiceNote: L10n.telegram("Activity.UploadingDocument")
        case .chatActionUploadingPhoto: L10n.telegram("Activity.UploadingPhoto")
        case .chatActionChoosingSticker: L10n.telegram("Activity.ChoosingSticker")
        case .chatActionStartPlayingGame: L10n.telegram("Activity.PlayingGame")
        case .chatActionCancel, .chatActionChoosingContact, .chatActionChoosingLocation,
             .chatActionWatchingAnimations:
            nil
        }
    }

    private static func suffixKey(for action: ChatAction) -> String? {
        switch action {
        case .chatActionTyping: "DialogList.SingleTypingSuffix"
        case .chatActionRecordingVideoNote: "DialogList.SingleRecordingVideoMessageSuffix"
        case .chatActionRecordingVideo, .chatActionUploadingVideo, .chatActionUploadingVideoNote:
            "DialogList.SingleUploadingVideoSuffix"
        case .chatActionRecordingVoiceNote: "DialogList.SingleRecordingAudioSuffix"
        case .chatActionUploadingDocument, .chatActionUploadingVoiceNote: "DialogList.SingleUploadingFileSuffix"
        case .chatActionUploadingPhoto: "DialogList.SingleUploadingPhotoSuffix"
        case .chatActionChoosingSticker: "DialogList.SingleChoosingStickerSuffix"
        case .chatActionStartPlayingGame: "DialogList.SinglePlayingGameSuffix"
        case .chatActionCancel, .chatActionChoosingContact, .chatActionChoosingLocation,
             .chatActionWatchingAnimations:
            nil
        }
    }

    private static func name(for sender: MessageSender, client: TDLibClient, named: @escaping () -> Void) -> String {
        guard case .messageSenderUser(let value) = sender else { return "" }
        if let user = ChatListSenderNames.shared.user(userID: value.userId, client: client) {
            return ChatListSenderNames.compactName(user)
        }
        ChatListSenderNames.shared.resolve(userID: value.userId, client: client, completion: named)
        return ""
    }

    func receive(_ update: UpdateChatAction, clientID: Int32) {
        if self.clientID != clientID {
            self.clientID = clientID
            let chats = Array(activities.keys)
            activities = [:]
            chats.forEach(changes.send)
        }
        var list = activities[update.chatId] ?? []
        list.removeAll { $0.sender == update.senderId }
        if case .chatActionCancel = update.action {} else { list.append((update.senderId, update.action)) }
        activities[update.chatId] = list.isEmpty ? nil : list
        changes.send(update.chatId)
    }

    /// Telegram's `ChatListTypingNode` text: the bare action in a private chat, the sender's name and action in a
    /// group, or the typing count when several people act.
    func text(for chat: CustomChat, client: TDLibClient) -> String? {
        guard clientID == client.id, let list = activities[chat.id] else { return nil }
        let chatID = chat.id
        return Self.text(for: list, privateUserID: chat.user?.id, client: client) { [weak self] in
            self?.changes.send(chatID)
        }
    }
}
