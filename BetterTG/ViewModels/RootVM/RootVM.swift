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
    let scopeSettingsLoading = RootScopeSettingsLoading()
    let chatProjection = RootChatProjection()
    var folderProjection: RootChatProjection.Lease?
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
        let loader = scopeSettingsLoading
        let reads = loader.reserveReads()
        Task { [weak self] in
            await loader.load(
                reads,
                accepts: { self?.acceptsListRequest(ticket) == true },
                fetch: { try await client.getScopeNotificationSettings(scope: $0) },
                publish: { [weak self] scope, settings in
                    guard let self else { return }
                    var updatedSettings = scopeNotificationSettings
                    updatedSettings[scope] = settings
                    scopeNotificationSettings = updatedSettings
                },
            )
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

    func getCustomChat(
        from id: Int64, for chatList: ChatList, client: TDLibClient,
        projection: RootChatProjection.Lease? = nil,
    ) async -> CustomChat? {
        await hydrateChat(id: id, list: chatList, client: client, projection: projection)
    }

    func getCustomChatForNavigation(from id: Int64, client: TDLibClient) async -> CustomChat? {
        await hydrateChat(id: id, list: nil, client: client, projection: nil)
    }

    func getCustomFolder(
        from info: ChatFolderInfo, client: TDLibClient, projection: RootChatProjection.Lease,
    ) async -> CustomFolder? {
        guard let folder = try? await client.getChatFolder(chatFolderId: info.id),
              projection.isValid,
              let chats = await getCustomChats(
                  for: .chatListFolder(.init(chatFolderId: info.id)),
                  client: client,
                  projection: projection,
              )
        else { return nil }
        return CustomFolder(chats: chats, type: .folder(info, folder))
    }

    func getCustomChats(
        for chatList: ChatList, client: TDLibClient, projection: RootChatProjection.Lease,
    ) async -> [CustomChat]? {
        guard projection.isValid else { return nil }
        projection.beginList(chatList, revision: chatProjection.revision)
        guard let ids = try? await client.getChats(chatList: chatList, limit: 200).chatIds,
              projection.isValid else { return nil }
        return await ids.asyncCompactMap { await getCustomChat(
            from: $0,
            for: chatList,
            client: client,
            projection: projection,
        ) }
    }

    private func hydrateChat(
        id: Int64,
        list: ChatList?,
        client: TDLibClient,
        projection: RootChatProjection.Lease?,
    ) async -> CustomChat? {
        guard let (ticket, _) = captureListRequest(), ticket.source.clientID == client.id else { return nil }
        let lease = projection ?? chatProjection.begin(chatID: id)
        defer { if projection == nil { chatProjection.finish(lease) } }
        guard lease.isValid else { return nil }
        let rawRevision = chatProjection.revision
        guard let chat = try? await client.getChat(chatId: id), lease.isValid,
              acceptsListRequest(ticket) else { return nil }
        let position = list.map { RootChatInsertion.position(in: chat.positions, for: $0) }
            ?? chat.positions.first ?? ChatPosition(isPinned: false, list: .chatListMain, order: 0, source: nil)
        let peerRevision = chatProjection.revision
        let type: CustomChat.CustomChatType
        switch chat.type {
        case .chatTypePrivate(let privateChat):
            lease.watchUser(privateChat.userId)
            guard let user = try? await client.getUser(userId: privateChat.userId) else { return nil }
            if case .userTypeBot = user.type { type = .bot(user) } else { type = .user(user) }
        case .chatTypeSupergroup(let peer):
            guard let group = try? await client.getSupergroup(supergroupId: peer.supergroupId) else { return nil }
            type = .supergroup(group)
        case .chatTypeBasicGroup(let peer):
            guard let group = try? await client.getBasicGroup(basicGroupId: peer.basicGroupId) else { return nil }
            type = .group(group)
        default:
            return nil
        }
        guard lease.isValid, acceptsListRequest(ticket) else { return nil }
        let result = CustomChat(
            chat: chat,
            position: position,
            unreadCount: chat.unreadCount,
            type: type,
            lastMessage: chat.lastMessage,
            draftMessage: chat.draftMessage,
        )
        lease.track(result, raw: rawRevision, peer: peerRevision)
        return list != nil && result.position.order == 0 ? nil : result
    }
}
