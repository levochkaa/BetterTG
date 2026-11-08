// ProfileMusicPlaylist.swift

import Combine
import Foundation
import TDLibKit

// MARK: - ProfileMusicPlaylist

/// Telegram's SavedMusicContext for the profile whose music plays: the user's profile audio files in their order
/// (getUserProfileAudios), paged in as the player's list or the playlist reaches their end.
@MainActor final class ProfileMusicPlaylist {
    struct Owner: Equatable {
        let accountID: UUID
        let userID: Int64
    }

    static let shared = ProfileMusicPlaylist()

    private static let pageSize = 50

    /// The list changed: its owner, a page or a reload.
    let changes = PassthroughSubject<Void, Never>()

    private(set) var owner: Owner?
    private(set) var audios = [Audio]()
    private(set) var totalCount = 0

    private var loadTask: Task<Void, Never>?
    private var generation = 0

    var canLoadMore: Bool {
        audios.count < totalCount
    }

    private init() {}

    /// The track item that plays `audio` from this user's profile.
    static func item(_ audio: Audio, owner: Owner) -> Media.NowPlaying {
        Media.NowPlaying(
            accountID: owner.accountID,
            chatID: owner.userID,
            messageID: Int64(audio.audio.id),
            isMusic: true,
            isProfileAudio: true,
        )
    }

    func audio(for item: Media.NowPlaying) -> Audio? {
        guard item.isProfileAudio, owner?.accountID == item.accountID, owner?.userID == item.chatID else { return nil }
        return audios.first { Int64($0.audio.id) == item.messageID }
    }

    /// The first page of the user's music, read again; it waits for the answer.
    func reload(_ owner: Owner, client: TDLibClient) async {
        loadTask?.cancel()
        loadTask = nil
        generation += 1
        let generation = generation
        let page = try? await client.getUserProfileAudios(limit: Self.pageSize, offset: 0, userId: owner.userID)
        guard generation == self.generation, let page else { return }
        self.owner = owner
        audios = page.audios
        totalCount = max(page.totalCount, page.audios.count)
        changes.send()
    }

    /// The next page, once; it waits for it.
    func loadMore(client: TDLibClient) async {
        guard let owner, canLoadMore else { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let generation = generation
        let offset = audios.count
        let task = Task { [weak self] in
            let page = try? await client.getUserProfileAudios(
                limit: Self.pageSize,
                offset: offset,
                userId: owner.userID,
            )
            guard let self, generation == self.generation, self.owner == owner else { return }
            loadTask = nil
            guard let page, !page.audios.isEmpty else {
                totalCount = audios.count
                changes.send()
                return
            }
            let known = Set(audios.map(\.audio.id))
            audios += page.audios.filter { !known.contains($0.audio.id) }
            totalCount = max(page.totalCount, audios.count)
            changes.send()
        }
        loadTask = task
        await task.value
    }
}
