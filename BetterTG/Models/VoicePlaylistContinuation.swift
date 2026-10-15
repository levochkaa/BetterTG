// VoicePlaylistContinuation.swift

import Combine
import Foundation
import TDLibKit

/// Telegram's voice playlist keeps going after its chat closes (PeerMessagesMediaPlaylist reads the chat's history on
/// its own). An open full chat continues its own playlist from its loaded rows, including round videos; once no such
/// chat is open, this continues with the chat's next voice note from TDLib.
@MainActor final class VoicePlaylistContinuation {
    // MARK: Internal

    struct ChatKey: Hashable {
        let accountID: UUID?
        let chatID: Int64
    }

    static let shared = VoicePlaylistContinuation()

    // MARK: Private

    private var openChats = [ChatKey: Int]()
    /// The header text of the note that just ended; Media clears its own copy when playback stops.
    private var lastDisplay: Media.NowPlayingDisplay?
    private var task: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Media.shared
            .$nowPlayingDisplay
            .compactMap(\.self)
            .sink { [weak self] display in self?.lastDisplay = display }
            .store(in: &cancellables)
        Media.shared
            .playbackFinished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] finished in self?.continuePlaylist(after: finished) }
            .store(in: &cancellables)
    }

    private static func senderTitle(of message: Message, client: TDLibClient) async -> String {
        switch message.senderId {
        case .messageSenderUser(let sender):
            if let user = try? await client.getUser(userId: sender.userId) {
                return ServiceMessageText.displayTitle(user)
            }
        case .messageSenderChat(let sender):
            if let chat = try? await client.getChat(chatId: sender.chatId) { return chat.title }
        }
        return L10n.telegram("MusicPlayer.VoiceNote")
    }

    /// A full chat that continues its own playlist while it is alive.
    func register(_ key: ChatKey) {
        openChats[key, default: 0] += 1
    }

    func unregister(_ key: ChatKey) {
        guard let count = openChats[key] else { return }
        openChats[key] = count > 1 ? count - 1 : nil
    }

    private func continuePlaylist(after finished: Media.NowPlaying) {
        guard openChats[ChatKey(accountID: finished.accountID, chatID: finished.chatID)] == nil,
              let accountID = finished.accountID, TDLib.shared.activeAccountID == accountID
        else { return }
        let client = TDLib.shared.activeClient
        let subtitle = lastDisplay?.item == finished ? lastDisplay?.subtitle : nil
        task?.cancel()
        task = Task { [weak self] in
            guard let found = try? await client.searchChatMessages(
                chatId: finished.chatID,
                filter: .searchMessagesFilterVoiceNote,
                fromMessageId: finished.messageID,
                limit: 10,
                offset: -9,
                query: "",
                senderId: nil,
                topicId: nil,
            ),
                let next = found.messages
                    .filter({ $0.id > finished.messageID && $0.selfDestructType == nil })
                    .min(by: { $0.id < $1.id }),
                    case .messageVoiceNote(let content) = next.content
            else { return }
            guard let file = try? await client.downloadFile(
                fileId: content.voiceNote.voice.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            ), file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }
            let title = await Self.senderTitle(of: next, client: client)
            guard !Task.isCancelled, let self,
                  TDLib.shared.activeAccountID == accountID, TDLib.shared.activeClient.id == client.id,
                  openChats[ChatKey(accountID: accountID, chatID: finished.chatID)] == nil,
                  Media.shared.savedMediaPath.isEmpty
            else { return }
            let item = Media.NowPlaying(accountID: accountID, chatID: next.chatId, messageID: next.id)
            Media.shared.toggle(with: file.local.path, duration: content.voiceNote.duration, item: item)
            Media.shared.setDisplay(Media.NowPlayingDisplay(
                item: item,
                title: title,
                subtitle: subtitle ?? L10n.telegram("MusicPlayer.VoiceNote"),
            ))
            if !next.isOutgoing, !content.isListened {
                _ = try? await client.openMessageContent(chatId: next.chatId, messageId: next.id)
            }
        }
    }
}
