// RootVM.swift

import SwiftUI
import TDLibKit
import Combine

@Observable final class RootVM {
    @ObservationIgnored static let shared = RootVM()
    
    init() {
        setPublishers()
    }
    
    var confirmChatDelete = ConfirmChatDelete(chat: nil, show: false, forAll: false)
    
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
    var folders = [CustomFolder]()
    var mainFolder: CustomFolder? { folders.first(where: { $0.type == .main }) }
    var archive: CustomFolder?
    var showArchive = false
    var currentFolder = 0
    var query = ""
    
    var allChats: [CustomChat] {
        var chats = [CustomChat]()
        if let archive { chats.append(contentsOf: archive.chats) }
        if let mainFolder { chats.append(contentsOf: mainFolder.chats) }
        return chats
    }
    
    func getCustomChat(from id: Int64, for chatList: ChatList) async -> CustomChat? {
        guard let chat = try? await td.getChat(chatId: id) else { return nil }
        
        if case .chatTypePrivate(let chatTypePrivate) = chat.type {
            guard let user = try? await td.getUser(userId: chatTypePrivate.userId) else { return nil }
            
            if case .userTypeRegular = user.type, let position = chat.positions.first(chatList) {
                return CustomChat(
                    chat: chat,
                    position: position,
                    unreadCount: chat.unreadCount,
                    user: user,
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage
                )
            }
        }
        
        return nil
    }
    
    func getCustomFolder(from info: ChatFolderInfo) async -> CustomFolder? {
        guard let folder = try? await td.getChatFolder(chatFolderId: info.id),
              let customChats = await getCustomChats(for: .chatListFolder(.init(chatFolderId: info.id)))
        else { return nil }
        let customFolder = CustomFolder(
            chats: customChats,
            type: .folder(info, folder)
        )
        return customFolder
    }
    
    func getCustomChats(for chatList: ChatList) async -> [CustomChat]? {
        guard let chatIds = try? await td.getChats(chatList: chatList, limit: 200).chatIds else { return nil }
        return await chatIds.asyncCompactMap { await getCustomChat(from: $0, for: chatList) }
    }
}
