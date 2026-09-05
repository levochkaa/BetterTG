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
    var folderLoadTasks = [Int: Task<Void, Never>]()
    var folderConfigurationTask: Task<Void, Never>?
    var folderConfigurationGeneration = UUID()

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

    func getCustomChatForNavigation(from id: Int64, client: TDLibClient) async -> CustomChat? {
        await hydrateChat(id: id, list: nil, client: client, projection: nil)
    }

    private func getCustomChat(
        from chat: Chat,
        position: ChatPosition,
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
