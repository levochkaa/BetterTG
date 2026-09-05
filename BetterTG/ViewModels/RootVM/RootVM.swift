// RootVM.swift

import Combine
import Foundation
import TDLibKit

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

    func getCustomChats(for chatList: ChatList) async -> [CustomChat]? {
        _ = try? await td.send(TDNativeRequests.loadChats(chatList: chatList, limit: 200))
        guard let ids = try? await td.getChats(chatList: chatList, limit: 200).chatIds
        else { return nil }
        return await ids.asyncCompactMap {
            await getCustomChat(from: $0, for: chatList)
        }
    }
}
