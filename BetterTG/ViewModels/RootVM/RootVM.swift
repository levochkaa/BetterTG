// RootVM.swift

import Combine
import Foundation
import TDLibKit

// MARK: - Route

enum Route {
    case customChat(CustomChat, targetMessageID: Int64? = nil)
    case archive(CustomFolder)
}

// MARK: - RootVM

@MainActor final class RootVM: ObservableObject {
    // MARK: Lifecycle

    private init() {
        setPublishers()
    }

    // MARK: Internal

    static let shared = RootVM()

    @Published var folders = [CustomFolder]()
    @Published var archive: CustomFolder?
    var cancellables = Set<AnyCancellable>()

    @Published var currentFolder = UserDefaults.standard.object(forKey: "currentFolder") as? Int {
        didSet {
            if let currentFolder {
                UserDefaults.standard.set(currentFolder, forKey: "currentFolder")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentFolder")
            }
        }
    }

    @Published var loggedIn = UserDefaults.standard.bool(forKey: "loggedIn") {
        didSet { UserDefaults.standard.set(loggedIn, forKey: "loggedIn") }
    }

    var allFolders: [CustomFolder] {
        folders + [archive].compactMap(\.self)
    }

    func getCustomChat(from id: Int64, for chatList: ChatList) async -> CustomChat? {
        guard let chat = try? await td.getChat(chatId: id),
              let position = chat.positions.first(chatList) else { return nil }
        return await getCustomChat(from: chat, position: position)
    }

    func getCustomChat(from chat: Chat, position: ChatPosition) async -> CustomChat? {
        switch chat.type {
        case .chatTypePrivate(let privateChat):
            guard let user = try? await td.getUser(userId: privateChat.userId) else { return nil }
            switch user.type {
            case .userTypeRegular:
                return CustomChat(
                    chat: chat,
                    position: position,
                    unreadCount: chat.unreadCount,
                    type: .user(user),
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage,
                )
            case .userTypeBot(let bot):
                return CustomChat(
                    chat: chat,
                    position: position,
                    unreadCount: chat.unreadCount,
                    type: .bot(bot),
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage,
                )
            case .userTypeDeleted, .userTypeUnknown:
                return nil
            }
        case .chatTypeSupergroup(let type):
            guard let group = try? await td.getSupergroup(supergroupId: type.supergroupId) else { return nil }
            return CustomChat(
                chat: chat,
                position: position,
                unreadCount: chat.unreadCount,
                type: .supergroup(group),
                lastMessage: chat.lastMessage,
                draftMessage: chat.draftMessage,
            )
        case .chatTypeBasicGroup(let type):
            guard let group = try? await td.getBasicGroup(basicGroupId: type.basicGroupId) else { return nil }
            return CustomChat(
                chat: chat,
                position: position,
                unreadCount: chat.unreadCount,
                type: .group(group),
                lastMessage: chat.lastMessage,
                draftMessage: chat.draftMessage,
            )
        default:
            return nil
        }
    }

    func getCustomFolder(from info: ChatFolderInfo) async -> CustomFolder? {
        guard let folder = try? await td.getChatFolder(chatFolderId: info.id),
              let chats = await getCustomChats(for: .chatListFolder(.init(chatFolderId: info.id)))
        else { return nil }
        return CustomFolder(chats: chats, type: .folder(info, folder))
    }

    func getCustomChats(for chatList: ChatList) async -> [CustomChat]? {
        guard let ids = try? await td.getChats(chatList: chatList, limit: 200).chatIds else { return nil }
        return await ids.asyncCompactMap { await getCustomChat(from: $0, for: chatList) }
    }
}
