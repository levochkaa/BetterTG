// RootVM.swift

import Combine
import SwiftUI
import TDLibKit

// MARK: - Route

enum Route: Hashable {
    case customChat(CustomChat)
    case archive(CustomFolder)
}

// MARK: - RootVM

@Observable final class RootVM {
    // MARK: Lifecycle

    init() {
        setPublishers()
    }
    
    // MARK: Internal

    @ObservationIgnored static let shared = RootVM()
    
    var path = [Route]()
    var confirmChatDelete = ConfirmChatDelete(chat: nil, show: false, forAll: false)
    var folders = [CustomFolder]()
    var archive: CustomFolder?
    var currentFolder: Int?
    var scrollPosition = ScrollPosition(x: 0)
    var query = ""
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    
    var loggedIn: Bool {
        get {
            access(keyPath: \.loggedIn)
            return UserDefaults.standard.bool(forKey: "loggedIn")
        }
        set {
            withMutation(keyPath: \.loggedIn) {
                UserDefaults.standard.set(newValue, forKey: "loggedIn")
            }
        }
    }
    
    var mainFolder: CustomFolder? { folders.first(where: { $0.type == .main }) }
    var allChats: [CustomChat] {
        var chats = [CustomChat]()
        if let archive { chats.append(contentsOf: archive.chats) }
        if let mainFolder { chats.append(contentsOf: mainFolder.chats) }
        return chats
    }
    
    func scrollToTop(folderID: Int) {
        guard let scrollViewProxy = folders.first(where: { $0.id == folderID })?.scrollViewProxy else { return }
        scrollViewProxy.scrollTo("top", anchor: .top)
    }
    
    func getCustomChat(from id: Int64, for chatList: ChatList) async -> CustomChat? {
        guard let chat = try? await td.getChat(chatId: id),
              let position = chat.positions.first(chatList) else { return nil }
        switch chat.type {
        case .chatTypePrivate(let chatTypePrivate):
            guard let user = try? await td.getUser(userId: chatTypePrivate.userId) else { return nil }
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
            case .userTypeBot(let userTypeBot):
                return CustomChat(
                    chat: chat,
                    position: position,
                    unreadCount: chat.unreadCount,
                    type: .bot(userTypeBot),
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage,
                )
            case .userTypeDeleted, .userTypeUnknown:
                return nil
            }
        case .chatTypeSupergroup(let chatTypeSupergroup):
            guard let supergroup = try? await td.getSupergroup(supergroupId: chatTypeSupergroup.supergroupId)
            else { return nil }
            return CustomChat(
                chat: chat,
                position: position,
                unreadCount: chat.unreadCount,
                type: .supergroup(supergroup),
                lastMessage: chat.lastMessage,
                draftMessage: chat.draftMessage,
            )
        case .chatTypeBasicGroup(let chatTypeBasicGroup):
            guard let group = try? await td.getBasicGroup(basicGroupId: chatTypeBasicGroup.basicGroupId)
            else { return nil }
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
              let customChats = await getCustomChats(for: .chatListFolder(.init(chatFolderId: info.id)))
        else { return nil }
        return CustomFolder(
            chats: customChats,
            type: .folder(info, folder),
        )
    }
    
    func getCustomChats(for chatList: ChatList) async -> [CustomChat]? {
        guard let chatIds = try? await td.getChats(chatList: chatList, limit: 200).chatIds else { return nil }
        return await chatIds.asyncCompactMap { await getCustomChat(from: $0, for: chatList) }
    }
}
