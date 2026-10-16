// VoicePlaylistContinuation.swift

import Combine
import Foundation
import TDLibKit

// MARK: - VoicePlaylistContinuation

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

    /// The header's swipe between tracks. PeerMessagesMediaPlaylist plays music in its regular order, so the next
    /// track is the chat's older one and the previous track the newer one.
    func skipMusic(toOlder: Bool) {
        guard let current = Media.shared.nowPlaying, current.isMusic else { return }
        playMusic(adjacentTo: current, older: toOlder, requiresIdle: false)
    }

    private func continuePlaylist(after finished: Media.NowPlaying) {
        // Music plays on through the chat's tracks whether the chat is open or not; TDLib finds the next one.
        if finished.isMusic {
            playMusic(adjacentTo: finished, older: true, requiresIdle: true)
            return
        }
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

    /// The chat's music track next to `item` (searchChatMessages with the audio filter), downloaded and played with
    /// its header text. After a track ends, nothing else may have started meanwhile.
    private func playMusic(adjacentTo item: Media.NowPlaying, older: Bool, requiresIdle: Bool) {
        guard let accountID = item.accountID, TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        task?.cancel()
        task = Task { [weak self] in
            guard let found = try? await client.searchChatMessages(
                chatId: item.chatID,
                filter: .searchMessagesFilterAudio,
                fromMessageId: item.messageID,
                limit: older ? 3 : 10,
                offset: older ? 0 : -9,
                query: "",
                senderId: nil,
                topicId: nil,
            ) else { return }
            let next =
                if older {
                    found.messages.filter { $0.id < item.messageID }.max { $0.id < $1.id }
                } else {
                    found.messages.filter { $0.id > item.messageID }.min { $0.id < $1.id }
                }
            guard let next, case .messageAudio(let content) = next.content,
                  let file = try? await client.downloadFile(
                      fileId: content.audio.audio.id,
                      limit: 0,
                      offset: 0,
                      priority: 32,
                      synchronous: true,
                  ), file.local.isDownloadingCompleted, !file.local.path.isEmpty
            else { return }
            guard !Task.isCancelled, self != nil,
                  TDLib.shared.activeAccountID == accountID, TDLib.shared.activeClient.id == client.id,
                  !requiresIdle || Media.shared.savedMediaPath.isEmpty
            else { return }
            let nextItem = Media.NowPlaying(
                accountID: accountID,
                chatID: next.chatId,
                messageID: next.id,
                isMusic: true,
            )
            Media.shared.toggle(with: file.local.path, duration: content.audio.duration, item: nextItem)
            Media.shared.setDisplay(.music(content.audio, item: nextItem))
        }
    }
}

// MARK: - Media.NowPlayingDisplay

extension Media.NowPlaying {
    /// A chat's music track in the active account.
    @MainActor static func music(chatID: Int64, messageID: Int64) -> Self {
        Self(accountID: TDLib.shared.activeAccountID, chatID: chatID, messageID: messageID, isMusic: true)
    }
}

extension Media.NowPlayingDisplay {
    /// MediaNavigationAccessoryHeaderNode's music text: the track's title over its performer, the file name when both
    /// tags are missing (PeerMessagesMediaPlaylist), Unknown Track and Unknown Artist otherwise; the rate button only
    /// for tracks over ten minutes. The album art is none for an .ogg file, as PeerMessagesMediaPlaylist has it.
    static func music(_ audio: Audio, item: Media.NowPlaying) -> Self {
        let title = audio.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let performer = audio.performer.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = audio.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let shownTitle =
            if !title.isEmpty {
                title
            } else if performer.isEmpty, !fileName.isEmpty {
                fileName
            } else {
                L10n.telegram("MediaPlayer.UnknownTrack")
            }
        // playerAlbumArt falls back from the file's own cover to the external covers, largest first, then the
        // sender's thumbnail.
        var covers: [Thumbnail] = audio.externalAlbumCovers.sorted { $0.width * $0.height > $1.width * $1.height }
        if let thumbnail = audio.albumCoverThumbnail { covers.append(thumbnail) }
        let artwork: Media.Artwork? = fileName.lowercased().hasSuffix(".ogg")
            ? nil
            : Media.Artwork(mimeType: audio.mimeType, coverFileIDs: covers.map(\.file.id))
        return Self(
            item: item,
            title: shownTitle,
            subtitle: performer.isEmpty ? L10n.telegram("MediaPlayer.UnknownArtist") : performer,
            showsRate: audio.duration > 10 * 60,
            artwork: artwork,
        )
    }
}
