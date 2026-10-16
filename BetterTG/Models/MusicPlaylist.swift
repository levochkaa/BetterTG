// MusicPlaylist.swift

import Foundation

// MARK: - MusicPlaybackSettings

/// Telegram's MusicPlaybackSettings: the order a chat's music plays in and how it loops, kept across launches the way
/// BetterTG keeps its voice playback rate.
struct MusicPlaybackSettings: Equatable {
    /// MusicPlaybackSettingsOrder, with Telegram's raw values.
    enum Order: Int {
        case regular = 0
        case reversed = 1
        case random = 2

        /// OverlayAudioPlayerControlsNode.orderPressed: regular → reversed → random → regular.
        var following: Order {
            switch self {
            case .regular: .reversed
            case .reversed: .random
            case .random: .regular
            }
        }
    }

    /// MusicPlaybackSettingsLooping, with Telegram's raw values (none, item, all).
    enum Looping: Int {
        case off = 0
        case item = 1
        case all = 2

        /// OverlayAudioPlayerControlsNode.loopingPressed: none → item → all → none.
        var following: Looping {
            switch self {
            case .off: .item
            case .item: .all
            case .all: .off
            }
        }
    }

    private static let orderKey = "BetterTG.musicPlaybackOrder"
    private static let loopingKey = "BetterTG.musicPlaybackLooping"

    var order: Order
    var looping: Looping

    /// The saved settings; MusicPlaybackSettings.defaultSettings (regular order, no looping) before any change.
    static func load() -> Self {
        let defaults = UserDefaults.standard
        return Self(
            order: Order(rawValue: defaults.integer(forKey: orderKey)) ?? .regular,
            looping: Looping(rawValue: defaults.integer(forKey: loopingKey)) ?? .off,
        )
    }

    func save() {
        UserDefaults.standard.set(order.rawValue, forKey: Self.orderKey)
        UserDefaults.standard.set(looping.rawValue, forKey: Self.loopingKey)
    }
}

// MARK: - MusicPlaylistNavigation

/// PeerMessagesMediaPlaylist's navigatedMessageFromView over a window of a chat's music, oldest first. Outside the
/// reversed order an album plays from its first track to its last, while the playlist itself goes from newer tracks
/// to older ones; the reversed order goes track by track.
enum MusicPlaylistNavigation {
    struct Entry: Equatable {
        let id: Int64
        /// The message's media album, 0 outside one (Telegram's groupingKey).
        let albumID: Int64
    }

    enum Position {
        case earlier
        case later
    }

    /// The track at `position` from `anchor`. `exact` is false when `anchor` has no such neighbour in `entries`
    /// and the result is only the window's edge, which the playlist doesn't play.
    static func navigate(
        _ entries: [Entry],
        from anchor: Int64,
        to position: Position,
        reversed: Bool,
    ) -> (id: Int64, exact: Bool)? {
        guard let index = entries.firstIndex(where: { $0.id == anchor }) else {
            return edge(of: entries, position)
        }
        let album = entries[index].albumID
        switch position {
        case .later:
            if !reversed, album != 0 {
                if index - 1 > 0, entries[index - 1].albumID == album {
                    return (entries[index - 1].id, true)
                }
                if let newer = entries[index...].first(where: { $0.albumID != album }) {
                    return (newer.id, true)
                }
            } else if index + 1 < entries.count {
                return (entries[index + 1].id, true)
            } else {
                return nil
            }
        case .earlier:
            if !reversed, album != 0 {
                if index + 1 < entries.count, entries[index + 1].albumID == album {
                    return (entries[index + 1].id, true)
                }
                // The older album, if one comes next, starts from its first track.
                var olderAlbum: Int64?
                for i in (0..<index).reversed() {
                    if let olderAlbum {
                        if entries[i].albumID != olderAlbum {
                            return (entries[i + 1].id, true)
                        } else if i == 0 {
                            return (entries[i].id, true)
                        }
                    } else if entries[i].albumID != album {
                        if entries[i].albumID != 0 {
                            olderAlbum = entries[i].albumID
                        } else {
                            return (entries[i].id, true)
                        }
                    }
                }
            } else if index != 0 {
                let older = entries[index - 1]
                if !reversed, older.albumID != 0 {
                    for i in (0..<index).reversed() {
                        if entries[i].albumID != older.albumID {
                            return (entries[i + 1].id, true)
                        } else if i == 0 {
                            return (entries[i].id, true)
                        }
                    }
                }
                return (older.id, true)
            } else {
                return nil
            }
        }
        return edge(of: entries, position)
    }

    private static func edge(of entries: [Entry], _ position: Position) -> (id: Int64, exact: Bool)? {
        guard let first = entries.first, let last = entries.last else { return nil }
        switch position {
        case .later: return (last.id, false)
        case .earlier: return (first.id, false)
        }
    }
}

// MARK: - MusicPlaybackStack

/// PeerMessagesMediaPlaylist's PlaybackStack: the chat's tracks in the order they played, which the random order
/// steps back through and doesn't repeat.
struct MusicPlaybackStack {
    private(set) var ids = [Int64]()

    mutating func clear() {
        ids.removeAll()
    }

    mutating func push(_ id: Int64) {
        ids.removeAll { $0 == id }
        ids.append(id)
    }

    mutating func pop() -> Int64? {
        ids.popLast()
    }

    /// Drops the tracks played after `id`, or pushes it when it never played.
    mutating func reset(to id: Int64) {
        if let index = ids.firstIndex(of: id) {
            ids.removeSubrange((index + 1)...)
        } else {
            push(id)
        }
    }
}
