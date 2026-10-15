// MessagePeerNames.swift

import TDLibKit
import UIKit

/// Names that message content shows for senders and chats, as Telegram's EnginePeer titles. Users come from
/// ChatListSenderNames; chats are looked up on the content's client. A name TDLib hasn't returned yet arrives through
/// `completion`, and a lookup that finishes after the active client changed is dropped.
@MainActor enum MessagePeerNames {
    private struct Key: Hashable {
        let clientID: Int32
        let chatID: Int64
    }

    private static let capacity = 256
    private static var chats = [Key: Chat]()
    private static var chatWaiters = [Key: [(Chat) -> Void]]()

    /// The chat, once TDLib returned it on this client.
    static func chat(_ chatID: Int64, client: TDLibClient, completion: @escaping (Chat) -> Void) -> Chat? {
        let key = Key(clientID: client.id, chatID: chatID)
        if let chat = chats[key] { return chat }
        let isFirstWaiter = chatWaiters[key] == nil
        chatWaiters[key, default: []].append(completion)
        guard isFirstWaiter else { return nil }
        Task {
            let chat = try? await client.getChat(chatId: chatID)
            let completions = chatWaiters.removeValue(forKey: key) ?? []
            guard let chat, TDLib.shared.activeClient.id == client.id else { return }
            if chats.count >= capacity { chats.removeAll() }
            chats[key] = chat
            completions.forEach { $0(chat) }
        }
        return nil
    }

    /// A sender's displayTitle (the full name) or compactDisplayTitle (the first name); a chat reads as its title.
    static func name(
        of sender: MessageSender,
        compact: Bool,
        client: TDLibClient,
        completion: @escaping (String) -> Void,
    ) -> String? {
        switch sender {
        case .messageSenderUser(let value):
            let userID = value.userId
            let names = ChatListSenderNames.shared
            if let user = names.user(userID: userID, client: client) {
                return title(of: user, compact: compact)
            }
            names.resolve(userID: userID, client: client) {
                guard let user = names.user(userID: userID, client: client) else { return }
                completion(title(of: user, compact: compact))
            }
            return nil
        case .messageSenderChat(let value):
            return chat(value.chatId, client: client) { completion($0.title) }?.title
        }
    }

    /// A chat's compactDisplayTitle: a private chat reads as its user's first name, any other chat as its title.
    static func compactName(
        ofChat chatID: Int64,
        client: TDLibClient,
        completion: @escaping (String) -> Void,
    ) -> String? {
        let resolve: (Chat) -> String? = { chat in
            guard case .chatTypePrivate(let type) = chat.type else { return chat.title }
            return name(
                of: .messageSenderUser(MessageSenderUser(userId: type.userId)),
                compact: true,
                client: client,
                completion: completion,
            )
        }
        let cached = chat(chatID, client: client) { chat in
            if let name = resolve(chat) { completion(name) }
        }
        return cached.flatMap(resolve)
    }

    private static func title(of user: User, compact: Bool) -> String {
        compact ? ChatListSenderNames.compactName(user) : ServiceMessageText.displayTitle(user)
    }
}
