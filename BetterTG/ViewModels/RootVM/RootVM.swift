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
        messageThread: MessageThreadInfo? = nil,
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
    var folderLoadTasks = [Int: Task<Void, Never>]()
    var folderConfigurationTask: Task<Void, Never>?
    var folderConfigurationGeneration = UUID()
    /// Lists a same-account client renewal has not reloaded yet. Their rows stay until the new client lists them.
    var renewalHeldFolderIDs = Set<Int>()
    /// Folders whose removal waits behind its Undo toast (ChatFolderLinkPreviewScreen's addHiddenChatListFilterIds).
    private(set) var hiddenFolderIDs = Set<Int>()
    var renewalHoldTask: Task<Void, Never>?
    let listAuthority = RootListAuthority()
    let scopeSettingsLoading = RootScopeSettingsLoading()

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
        restoreChatListContext()
        if loggedIn {
            loadScopeNotificationSettings()
        }
    }

    /// Hides a folder's tab and page while its removal waits, or brings them back after Undo or the removal.
    func setFolderHidden(_ id: Int, _ hidden: Bool) {
        let changed = hidden ? hiddenFolderIDs.insert(id).inserted : hiddenFolderIDs.remove(id) != nil
        guard changed else { return }
        loadFolderConfiguration()
    }

    /// A new account or client starts with every folder it lists.
    func resetHiddenFolders() {
        hiddenFolderIDs.removeAll()
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

    func getCustomChatForNavigation(from id: Int64, client: TDLibClient) async -> CustomChat? {
        // Navigation hydrates only through the client that owns this root. A result that
        // completes after an account or client switch is discarded.
        guard let (ticket, _) = captureListRequest(), ticket.source.clientID == client.id,
              let chat = try? await client.getChat(chatId: id), acceptsListRequest(ticket)
        else { return nil }
        let position = chat.positions.first ?? ChatPosition(
            isPinned: false,
            list: .chatListMain,
            order: 0,
            source: nil,
        )
        guard let result = await getCustomChat(from: chat, position: position, client: client),
              acceptsListRequest(ticket)
        else { return nil }
        return result
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
        case .chatTypeSecret(let type):
            guard let user = try? await client.getUser(userId: type.userId) else { return nil }
            return CustomChat(
                chat: chat,
                position: position,
                unreadCount: chat.unreadCount,
                type: .user(user),
                lastMessage: chat.lastMessage,
                draftMessage: chat.draftMessage,
            )
        }
    }
}
