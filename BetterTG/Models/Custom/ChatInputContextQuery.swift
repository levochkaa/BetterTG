// ChatInputContextQuery.swift

import Foundation

// MARK: - ChatInputContextQuery

/// ChatPresentationInputQuery's emoji, hashtag and emoji search queries; mentions, commands and inline bots have their
/// own paths.
enum ChatInputContextQuery: Equatable {
    /// A lone emoji as the whole input: stickers for it (InlineReactionSearchPanel).
    case stickers(emoji: String)
    /// The word after "#" at the caret (HashtagChatInputContextPanelNode).
    case hashtag(String)
    /// The word after ":" at the caret, in the keyboard's languages (EmojisChatInputContextPanelNode).
    case emojiSearch(String, languageCodes: [String])
}

// MARK: - ChatHashtagSuggestions

/// HashtagChatInputContextPanelNode's rows: the recently used hashtags that start with the query. A public chat adds
/// "Use #query" and "Use #query@username" once the query has four characters; rows naming the chat show its photo.
struct ChatHashtagSuggestions: Equatable {
    enum Row: Equatable {
        case useGeneric(String)
        case useLocal(String, isChannel: Bool)
        case recent(String)

        var hashtag: String {
            switch self {
            case .recent(let hashtag), .useGeneric(let hashtag), .useLocal(let hashtag, _): hashtag
            }
        }
    }

    let query: String
    let hashtags: [String]
    let publicUsername: String?
    let isChannel: Bool
    /// The chat, whose photo marks "#tag@username" rows.
    let chat: SettingsPeer?

    /// The rows in Telegram's order, without the query itself.
    var rows: [Row] {
        var rows = [Row]()
        if query.count >= 4, let publicUsername {
            rows.append(.useGeneric(query))
            rows.append(.useLocal(query + "@" + publicUsername, isChannel: isChannel))
        }
        for hashtag in hashtags where hashtag != query && hashtag.hasPrefix(query) {
            guard !rows.contains(where: { $0.hashtag == hashtag }) else { continue }
            rows.append(.recent(hashtag))
        }
        return rows
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query && lhs.hashtags == rhs.hashtags && lhs.publicUsername == rhs.publicUsername
            && lhs.isChannel == rhs.isChannel && lhs.chat?.id == rhs.chat?.id
    }
}

// MARK: - ChatEmojiSuggestion

/// One of EmojisChatInputContextPanelNode's emoji with the keyword that found it.
struct ChatEmojiSuggestion: Equatable {
    let emoji: String
    let keyword: String
}
