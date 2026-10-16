// ChatBotInput.swift

import TDLibKit
import UIKit

// MARK: - ChatBotCommand

/// One command of the chat's bot or of a bot in the group (Telegram's ChatInputTextCommand).
struct ChatBotCommand: Equatable {
    let botUserID: Int64
    /// The bot's username; in a group the command goes as "/command@username" (sendBotCommand).
    let botUsername: String?
    let command: String
    let description: String

    /// The text Telegram sends for the command in this chat.
    func messageText(inGroup: Bool) -> String {
        guard inGroup, let botUsername, !botUsername.isEmpty else { return "/" + command }
        return "/" + command + "@" + botUsername
    }
}

// MARK: - ChatMentionSuggestion

/// One row of MentionChatInputContextPanelNode: a recently used inline bot or a member matching the "@" word.
struct ChatMentionSuggestion: Equatable {
    let userID: Int64
    /// Inserted as "@username"; without one the short name goes in as a text mention.
    let username: String?
    /// Telegram's compactDisplayTitle: the first name, else the last name.
    let compactTitle: String
    let peer: SettingsPeer

    init?(user: User) {
        if case .userTypeDeleted = user.type { return nil }
        let fullName = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        guard !fullName.isEmpty else { return nil }
        self.userID = user.id
        self.username = user.usernames?.activeUsernames.first
        self.compactTitle = user.firstName.isEmpty ? user.lastName : user.firstName
        self.peer = SettingsPeer(
            id: user.id,
            title: fullName,
            file: user.profilePhoto?.small,
            minithumbnail: user.profilePhoto?.minithumbnail,
            placeholder: user.telegramAvatarPlaceholder,
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.userID == rhs.userID && lhs.username == rhs.username && lhs.compactTitle == rhs.compactTitle
            && lhs.peer.title == rhs.peer.title && lhs.peer.file?.id == rhs.peer.file?.id
    }

    /// searchPeerMembers' match: a name word or the username starting with the query.
    func matches(_ normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        if username?.lowercased().hasPrefix(normalizedQuery) == true { return true }
        return peer.title
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .contains { $0.hasPrefix(normalizedQuery) }
    }
}

// MARK: - InlineBotResult

/// One inline result with the query it came from; each page of results has its own query ID.
struct InlineBotResult {
    let queryID: Int64
    let result: TDNativeInlineQueryResult

    var resultID: String {
        switch result {
        case .inlineQueryResultArticle(let value): value.id
        case .inlineQueryResultContact(let value): value.id
        case .inlineQueryResultLocation(let value): value.id
        case .inlineQueryResultVenue(let value): value.id
        case .inlineQueryResultGame(let value): value.id
        case .inlineQueryResultAnimation(let value): value.id
        case .inlineQueryResultAudio(let value): value.id
        case .inlineQueryResultDocument(let value): value.id
        case .inlineQueryResultPhoto(let value): value.id
        case .inlineQueryResultSticker(let value): value.id
        case .inlineQueryResultVideo(let value): value.id
        case .inlineQueryResultVoiceNote(let value): value.id
        }
    }
}

// MARK: - InlineBotQueryState

/// Telegram's contextRequestResult: the inline bot the input starts with ("@bot query") and its results.
struct InlineBotQueryState {
    let botUserID: Int64
    let username: String
    let placeholder: String
    var query: String
    var results = [InlineBotResult]()
    var nextOffset = ""
    var button: TDNativeInlineQueryResultsButton?
    var isLoading = true

    /// HorizontalListContextResultsChatInputContextPanelNode shows media results in a strip; anything else is a list.
    var isMediaGallery: Bool {
        !results.isEmpty && results.allSatisfy { item in
            switch item.result {
            case .inlineQueryResultAnimation, .inlineQueryResultPhoto, .inlineQueryResultSticker: true
            default: false
            }
        }
    }
}

// MARK: - ChatInputQuery

/// ChatContextQuery's textInputStateContextQueryRangeAndType for the queries BetterTG answers: an inline bot request
/// ("@bot query") and a "/" command the input consists of.
enum ChatInputQuery: Equatable {
    case command(String)
    case inlineBot(username: String, query: String)

    static func parse(_ text: String) -> ChatInputQuery? {
        let string = text as NSString
        if string.hasPrefix("@"), string.length > 1 {
            var index = 1
            while index < string.length {
                let character = string.character(at: index)
                if character == 0x20 {
                    guard index > 1 else { break }
                    return .inlineBot(
                        username: string.substring(with: NSRange(location: 1, length: index - 1)),
                        query: string.substring(from: index + 1),
                    )
                }
                guard isUsernameCharacter(character) else { break }
                index += 1
            }
        }
        if string.hasPrefix("/"), !text.contains(where: \.isWhitespace) {
            return .command(string.substring(from: 1))
        }
        return nil
    }

    /// The characters of a username: Latin letters, digits and the underscore.
    private static func isUsernameCharacter(_ character: unichar) -> Bool {
        (0x61...0x7A).contains(character) || (0x41...0x5A).contains(character) || (0x30...0x39).contains(character)
            || character == 0x5F
    }
}
