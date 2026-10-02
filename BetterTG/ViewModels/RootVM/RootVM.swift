// RootVM.swift

import Combine
import Foundation
import TDLibKitDynamic

// MARK: - Route

enum Route {
    case customChat(
        CustomChat,
        location: ChatLocation? = nil,
        forumTopic: ForumTopic? = nil,
        targetMessageID: Int64? = nil,
        targetQuote: MessageQuoteHighlight? = nil,
    )
    case archive(CustomFolder)
}

// MARK: - RootVM

@MainActor final class RootVM: ObservableObject {
    // MARK: Internal

    static let shared = RootVM()

    @Published var folders = [CustomFolder]()
    @Published var archive: CustomFolder?
    @Published var activeAccountID: UUID?
    @Published var scopeNotificationSettings = [NotificationSettingsScope: ScopeNotificationSettings]()
    var cancellables = Set<AnyCancellable>()
    let listAuthority = RootListAuthority()
    let chatInsertions = RootChatInsertion()
    var folderLoadID: UUID?
    var chatRefreshIDs = [Int64: UUID]()

    @Published var loggedIn = false

    @Published var currentFolder = UserDefaults.standard.object(forKey: "currentFolder") as? Int {
        didSet {
            if let currentFolder {
                UserDefaults.standard.set(currentFolder, forKey: "currentFolder")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentFolder")
            }
        }
    }

    var allFolders: [CustomFolder] {
        folders + [archive].compactMap(\.self)
    }

    private init() {
        self.activeAccountID = TDLib.shared.activeAccountID
        self.loggedIn = TDLib.shared.isActiveAccountReady
        setPublishers()
        if loggedIn {
            loadScopeNotificationSettings()
        }
    }

    func isMuted(_ chat: CustomChat) -> Bool {
        let settings = chat.chat.notificationSettings
        if settings.useDefaultMuteFor,
           let scopeSettings = scopeNotificationSettings[chat.notificationSettingsScope]
        {
            return scopeSettings.muteFor > 0
        }
        return settings.muteFor > 0
    }

    func loadScopeNotificationSettings() {
        guard let (ticket, client) = captureListRequest() else { return }
        Task { [weak self] in
            guard let self else { return }
            let scopes: [NotificationSettingsScope] = [
                .notificationSettingsScopePrivateChats,
                .notificationSettingsScopeGroupChats,
                .notificationSettingsScopeChannelChats,
            ]
            var loadedSettings = [NotificationSettingsScope: ScopeNotificationSettings]()
            for scope in scopes {
                guard acceptsListRequest(ticket) else { return }
                if let settings = try? await client.getScopeNotificationSettings(scope: scope) {
                    loadedSettings[scope] = settings
                }
            }
            guard acceptsListRequest(ticket) else { return }
            var mergedSettings = scopeNotificationSettings
            mergedSettings.merge(loadedSettings, uniquingKeysWith: { _, loaded in loaded })
            scopeNotificationSettings = mergedSettings
        }
    }

    func captureListRequest() -> (RootListAuthority.Ticket, TDLibClient)? {
        guard let ticket = listAuthority.capture(
            ownerAccountID: activeAccountID, activeSource: TDLib.shared.activeUpdateSource,
        ) else { return nil }
        let client = td
        guard client.id == ticket.source.clientID else { return nil }
        return (ticket, client)
    }

    func acceptsListRequest(_ ticket: RootListAuthority.Ticket) -> Bool {
        !Task.isCancelled && listAuthority.accepts(
            ticket, ownerAccountID: activeAccountID, activeSource: TDLib.shared.activeUpdateSource,
        )
    }

    func getCustomChat(from id: Int64, for chatList: ChatList, client: TDLibClient) async -> CustomChat? {
        guard let chat = try? await client.getChat(chatId: id),
              let position = chat.positions.first(chatList) else { return nil }
        return await getCustomChat(from: chat, position: position, client: client)
    }

    func getCustomChatForNavigation(from id: Int64, client: TDLibClient) async -> CustomChat? {
        guard let chat = try? await client.getChat(chatId: id) else { return nil }
        let position = chat.positions.first ?? ChatPosition(
            isPinned: false,
            list: .chatListMain,
            order: 0,
            source: nil,
        )
        return await getCustomChat(from: chat, position: position, client: client)
    }

    func getCustomFolder(from info: ChatFolderInfo, client: TDLibClient) async -> CustomFolder? {
        guard let folder = try? await client.getChatFolder(chatFolderId: info.id),
              let chats = await getCustomChats(for: .chatListFolder(.init(chatFolderId: info.id)), client: client)
        else { return nil }
        return CustomFolder(chats: chats, type: .folder(info, folder))
    }

    func getCustomChats(for chatList: ChatList, client: TDLibClient) async -> [CustomChat]? {
        guard let ids = try? await client.getChats(chatList: chatList, limit: 200).chatIds else { return nil }
        return await ids.asyncCompactMap { await getCustomChat(from: $0, for: chatList, client: client) }
    }

    private func getCustomChat(
        from chat: Chat,
        position: ChatPosition,
        client: TDLibClient,
    ) async -> CustomChat? {
        switch chat.type {
        case .chatTypePrivate(let privateChat):
            guard let user = try? await client.getUser(userId: privateChat.userId) else { return nil }
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
            case .userTypeBot:
                return CustomChat(
                    chat: chat,
                    position: position,
                    unreadCount: chat.unreadCount,
                    type: .bot(user),
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage,
                )
            case .userTypeDeleted, .userTypeUnknown:
                return CustomChat(
                    chat: chat,
                    position: position,
                    unreadCount: chat.unreadCount,
                    type: .user(user),
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage,
                )
            }
        case .chatTypeSupergroup(let type):
            guard let group = try? await client.getSupergroup(supergroupId: type.supergroupId) else { return nil }
            return CustomChat(
                chat: chat,
                position: position,
                unreadCount: chat.unreadCount,
                type: .supergroup(group),
                lastMessage: chat.lastMessage,
                draftMessage: chat.draftMessage,
            )
        case .chatTypeBasicGroup(let type):
            guard let group = try? await client.getBasicGroup(basicGroupId: type.basicGroupId) else { return nil }
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
}
