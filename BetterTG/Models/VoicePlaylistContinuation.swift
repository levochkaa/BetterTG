// VoicePlaylistContinuation.swift

import Combine
import Foundation
import TDLibKit

// MARK: - VoicePlaylistContinuation

/// Telegram's voice playlist keeps going after its chat closes (PeerMessagesMediaPlaylist reads the chat's history on
/// its own). An open full chat continues its own playlist from its loaded rows, including round videos; once no such
/// chat is open, this continues with the chat's next voice note from TDLib. Music always plays on through the chat's
/// tracks from here, in the order and looping MusicPlaybackSettings keeps.
@MainActor final class VoicePlaylistContinuation {
    // MARK: Internal

    struct ChatKey: Hashable {
        let accountID: UUID?
        let chatID: Int64
    }

    /// SharedMediaPlaylistControlAction's track steps.
    enum MusicControl {
        case next
        case previous
    }

    /// How a playlist step records its track on the played stack.
    private enum StackStep {
        case push
        /// The random order's previous returns to a track played before (PlaybackStack.resetToId).
        case returnTo
    }

    static let shared = VoicePlaylistContinuation()

    /// The track a playlist step is downloading, which the music player's list marks.
    @Published private(set) var loadingMusic: Media.NowPlaying?

    // MARK: Private

    private var openChats = [ChatKey: Int]()
    /// The header text of the note that just ended; Media clears its own copy when playback stops.
    private var lastDisplay: Media.NowPlayingDisplay?
    private var task: Task<Void, Never>?
    /// The chat's tracks in the order they played (PeerMessagesMediaPlaylist's playbackStack).
    private var musicStack = MusicPlaybackStack()
    private var musicStackChat: ChatKey?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Media.shared
            .$nowPlayingDisplay
            .compactMap(\.self)
            .sink { [weak self] display in self?.lastDisplay = display }
            .store(in: &cancellables)
        Media.shared
            .$nowPlaying
            .compactMap(\.self)
            .filter(\.isMusic)
            .sink { [weak self] item in self?.noteMusicStarted(item) }
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

    /// The track next to `item` (PeerMessagesMediaPlaylist's loadItem around a message): a window of ten tracks on
    /// either side of it, wrapped past the oldest track to the newest and past the newest to the oldest when looping
    /// all.
    private static func adjacentMusic(
        to item: Media.NowPlaying,
        position: MusicPlaylistNavigation.Position,
        reversed: Bool,
        loopsAll: Bool,
        client: TDLibClient,
    ) async -> Message? {
        guard let found = try? await client.searchChatMessages(
            chatId: item.chatID,
            filter: .searchMessagesFilterAudio,
            fromMessageId: item.messageID,
            limit: 21,
            offset: -10,
            query: "",
            senderId: nil,
            topicId: nil,
        ) else { return nil }
        let messages = found.messages.sorted { $0.id < $1.id }
        var entries = messages.map { MusicPlaylistNavigation.Entry(id: $0.id, albumID: $0.mediaAlbumId) }
        // A track TDLib left out of its own window still has neighbours by message order.
        if !entries.contains(where: { $0.id == item.messageID }) {
            let index = entries.firstIndex { $0.id > item.messageID } ?? entries.count
            entries.insert(MusicPlaylistNavigation.Entry(id: item.messageID, albumID: 0), at: index)
        }
        if let result = MusicPlaylistNavigation.navigate(
            entries,
            from: item.messageID,
            to: position,
            reversed: reversed,
        ), result.exact {
            return messages.first { $0.id == result.id }
        }
        guard loopsAll, !Task.isCancelled else { return nil }
        switch position {
        case .earlier: return await newestMusic(in: item.chatID, client: client)
        case .later: return await oldestMusic(in: item.chatID, client: client)
        }
    }

    private static func newestMusic(in chatID: Int64, client: TDLibClient) async -> Message? {
        try? await client.searchChatMessages(
            chatId: chatID,
            filter: .searchMessagesFilterAudio,
            fromMessageId: 0,
            limit: 1,
            offset: 0,
            query: "",
            senderId: nil,
            topicId: nil,
        )
        .messages
        .first
    }

    /// The chat's oldest track: the last of TDLib's sparse positions, then any older tracks the sparse ones skipped.
    private static func oldestMusic(in chatID: Int64, client: TDLibClient) async -> Message? {
        var oldestID: Int64 = 0
        if let positions = try? await client.getChatSparseMessagePositions(
            chatId: chatID,
            filter: .searchMessagesFilterAudio,
            fromMessageId: 0,
            limit: 2000,
            savedMessagesTopicId: 0,
        ) {
            oldestID = positions.positions.map(\.messageId).min() ?? 0
        }
        var oldest: Message?
        for _ in 0..<50 {
            guard !Task.isCancelled, let page = try? await client.searchChatMessages(
                chatId: chatID,
                filter: .searchMessagesFilterAudio,
                fromMessageId: oldestID,
                limit: 100,
                offset: 0,
                query: "",
                senderId: nil,
                topicId: nil,
            ), let last = page.messages.min(by: { $0.id < $1.id }), oldestID == 0 || last.id < oldestID
            else { break }
            oldest = last
            oldestID = last.id
        }
        if oldest == nil, oldestID != 0 {
            oldest = try? await client.getMessage(chatId: chatID, messageId: oldestID)
        }
        return oldest
    }

    /// A track outside `played`, as Postbox's findRandomMessage picks one. TDLib's sparse positions (every track up
    /// to 2,000 of them, evenly spread past that) stand in for Postbox's local tag index.
    private static func randomMusic(
        in chatID: Int64,
        excluding played: Set<Int64>,
        client: TDLibClient,
    ) async -> Message? {
        var ids = [Int64]()
        if let positions = try? await client.getChatSparseMessagePositions(
            chatId: chatID,
            filter: .searchMessagesFilterAudio,
            fromMessageId: 0,
            limit: 2000,
            savedMessagesTopicId: 0,
        ) {
            ids = positions.positions.map(\.messageId)
        } else if let page = try? await client.searchChatMessages(
            chatId: chatID,
            filter: .searchMessagesFilterAudio,
            fromMessageId: 0,
            limit: 100,
            offset: 0,
            query: "",
            senderId: nil,
            topicId: nil,
        ) {
            ids = page.messages.map(\.id)
        }
        guard let id = ids.filter({ !played.contains($0) }).randomElement() else { return nil }
        return try? await client.getMessage(chatId: chatID, messageId: id)
    }

    /// A full chat that continues its own playlist while it is alive.
    func register(_ key: ChatKey) {
        openChats[key, default: 0] += 1
    }

    func unregister(_ key: ChatKey) {
        guard let count = openChats[key] else { return }
        openChats[key] = count > 1 ? count - 1 : nil
    }

    /// SharedMediaPlayer.control(.next / .previous) for music, once the 5 s rule has passed: PeerMessagesMediaPlaylist
    /// goes to the older track for next in the regular order and to the newer one in the reversed order; the random
    /// order picks a track it hasn't played, and its previous goes back through the ones it has.
    func controlMusic(_ action: MusicControl) {
        guard let current = Media.shared.nowPlaying, current.isMusic else { return }
        navigateMusic(from: current, action: action, requiresIdle: false)
    }

    /// PeerMessagesMediaPlaylist.setOrder: the played stack starts over from the current track.
    func setMusicOrder(_ order: MusicPlaybackSettings.Order) {
        var settings = Media.shared.musicSettings
        guard settings.order != order else { return }
        settings.order = order
        Media.shared.updateMusicSettings(settings)
        musicStack.clear()
        if let current = Media.shared.nowPlaying, current.isMusic {
            musicStackChat = ChatKey(accountID: current.accountID, chatID: current.chatID)
            musicStack.push(current.messageID)
        }
    }

    func setMusicLooping(_ looping: MusicPlaybackSettings.Looping) {
        var settings = Media.shared.musicSettings
        guard settings.looping != looping else { return }
        settings.looping = looping
        Media.shared.updateMusicSettings(settings)
    }

    /// A track picked in the music player's list plays as its bubble would play it, starting the playlist over there.
    func playMusic(_ message: Message, accountID: UUID, client: TDLibClient) {
        guard TDLib.shared.activeAccountID == accountID else { return }
        task?.cancel()
        loadingMusic = nil
        task = Task { [weak self] in
            await self?.play(message, accountID: accountID, client: client, requiresIdle: false, stackStep: nil)
        }
    }

    /// A track started from its bubble or the player's list begins a new playlist (PeerMessagesMediaPlaylist's loadItem
    /// at a message clears the stack); one this playlist stepped to is already on top of it.
    private func noteMusicStarted(_ item: Media.NowPlaying) {
        let key = ChatKey(accountID: item.accountID, chatID: item.chatID)
        guard musicStackChat != key || musicStack.ids.last != item.messageID else { return }
        musicStackChat = key
        musicStack.clear()
        musicStack.push(item.messageID)
    }

    private func continuePlaylist(after finished: Media.NowPlaying) {
        // Music plays on through the chat's tracks whether the chat is open or not (SharedMediaPlayer's action at the
        // end); a track looping on itself started over in Media.
        if finished.isMusic {
            navigateMusic(from: finished, action: .next, requiresIdle: true)
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

    /// PeerMessagesMediaPlaylist.control in the saved order. After a track ends, nothing else may have started
    /// meanwhile.
    private func navigateMusic(from item: Media.NowPlaying, action: MusicControl, requiresIdle: Bool) {
        guard let accountID = item.accountID, TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        let settings = Media.shared.musicSettings
        let played = musicStackChat == ChatKey(accountID: accountID, chatID: item.chatID)
            ? musicStack
            : MusicPlaybackStack()
        task?.cancel()
        loadingMusic = nil
        task = Task { [weak self] in
            let target: Message?
            var stackStep = StackStep.push
            switch settings.order {
            case .regular, .reversed:
                // The regular order plays from newer tracks to older ones, the reversed order the other way.
                let toOlder = (settings.order == .regular) == (action == .next)
                target = await Self.adjacentMusic(
                    to: item,
                    position: toOlder ? .earlier : .later,
                    reversed: settings.order == .reversed,
                    loopsAll: settings.looping == .all,
                    client: client,
                )
            case .random:
                var unplayed = played
                var found: Message?
                if action == .previous {
                    stackStep = .returnTo
                    _ = unplayed.pop()
                    if let previousID = unplayed.pop() {
                        found = try? await client.getMessage(chatId: item.chatID, messageId: previousID)
                    }
                }
                if found == nil {
                    found = await Self.randomMusic(in: item.chatID, excluding: Set(unplayed.ids), client: client)
                }
                // With every track played, findRandomMessage's fallback is the current track.
                if found == nil {
                    found = try? await client.getMessage(chatId: item.chatID, messageId: item.messageID)
                }
                target = found
            }
            guard let target, !Task.isCancelled, let self else { return }
            await play(target, accountID: accountID, client: client, requiresIdle: requiresIdle, stackStep: stackStep)
        }
    }

    /// Downloads the message's track and plays it with its header text. `stackStep` records a playlist step on the
    /// played stack; a track picked outside the playlist leaves the stack to noteMusicStarted.
    private func play(
        _ message: Message,
        accountID: UUID,
        client: TDLibClient,
        requiresIdle: Bool,
        stackStep: StackStep?,
    ) async {
        guard case .messageAudio(let content) = message.content else { return }
        let item = Media.NowPlaying(accountID: accountID, chatID: message.chatId, messageID: message.id, isMusic: true)
        // The playlist landing on the loaded track again (a single track looping all, a random order that played every
        // track) plays it over.
        if Media.shared.nowPlaying == item, !Media.shared.savedMediaPath.isEmpty {
            if let stackStep { record(stackStep, item: item) }
            Media.shared.restartCurrentTrack()
            return
        }
        loadingMusic = item
        let file = try? await client.downloadFile(
            fileId: content.audio.audio.id,
            limit: 0,
            offset: 0,
            priority: 32,
            synchronous: true,
        )
        if loadingMusic == item { loadingMusic = nil }
        guard let file, file.local.isDownloadingCompleted, !file.local.path.isEmpty, !Task.isCancelled,
              TDLib.shared.activeAccountID == accountID, TDLib.shared.activeClient.id == client.id,
              !requiresIdle || Media.shared.savedMediaPath.isEmpty
        else { return }
        if let stackStep { record(stackStep, item: item) }
        Media.shared.toggle(with: file.local.path, duration: content.audio.duration, item: item)
        Media.shared.setDisplay(.music(content.audio, item: item))
    }

    private func record(_ step: StackStep, item: Media.NowPlaying) {
        let key = ChatKey(accountID: item.accountID, chatID: item.chatID)
        if musicStackChat != key {
            musicStackChat = key
            musicStack.clear()
        }
        switch step {
        case .push: musicStack.push(item.messageID)
        case .returnTo: musicStack.reset(to: item.messageID)
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
