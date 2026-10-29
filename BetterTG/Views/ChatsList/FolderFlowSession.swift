// FolderFlowSession.swift

import Combine
import TDLibKit
import UIKit

/// Local editor state outlives a native client, but an issued action scope never does.
@MainActor final class FolderFlowSession {
    enum Mutation {
        case create(ChatFolder)
        case edit(Int, ChatFolder)
        case reorder([Int], Int)
        /// Telegram removes a shared folder together with the chats the user chose to quit.
        case delete(Int, leaveChatIDs: [Int64] = [])
    }

    enum State { case waiting, ready, saving, uncertain, revoked }

    struct Endpoint {
        let source: TdUpdateSource
        /// Writes the mutation and returns the ID of a folder it created.
        let write: (Mutation) async throws -> Int?
    }

    /// TDLib reads the folder screens make beyond the loaded chat lists. Callers check that the session is still
    /// current when a read returns. Probe sessions have none.
    struct Reader {
        /// `chat_folder_chosen_chat_count_max`: how many non-secret chats a folder may pin and include, or exclude,
        /// and as many secret chats again.
        let chosenChatLimit: () async -> Int?
        /// TDLib's count of the chats a folder definition covers (`getChatFolderChatCount`).
        let chatCount: (ChatFolder) async -> Int?
        /// Loads the main chat list's next page, which reaches the pickers through the session's folders.
        let loadMoreMainChats: () -> Void
        /// Chats for a picker query beyond the loaded lists: TDLib's chat search, its server search and contacts.
        let searchChats: (String) async -> [CustomChat]
        /// TDLib's recommended folders (`getRecommendedChatFolders`).
        let recommendedFolders: () async -> [TDNativeRecommendedChatFolder]
        /// The client a folder's invite links are read and changed on; the screens check the session's scope around
        /// each request.
        let inviteLinkClient: () -> TDLibClient
    }

    private(set) var state = State.waiting
    let reader: Reader?

    let accountID: UUID?

    private let currentSource: () -> TdUpdateSource?
    private let ownerAccount: () -> UUID?
    private let resolve: (TdUpdateSource) -> Endpoint?
    private let readFolders: () -> [CustomFolder]
    private let readAllFolders: () -> [CustomFolder]
    private let changes = CurrentValueSubject<State, Never>(.waiting)
    private var subscriptions = Set<AnyCancellable>()
    private var readySource: TdUpdateSource?
    private var endpoint: Endpoint?
    private var generation = UUID()
    private var pending: (id: UUID, dispatched: Bool)?

    var folders: [CustomFolder] { ownsModel ? readFolders() : [] }
    var allFolders: [CustomFolder] { ownsModel ? readAllFolders() : [] }
    var isCurrent: Bool {
        state == .ready && endpoint?.source == currentSource()
            && accountID != nil && ownerAccount() == accountID
    }

    private var ownsModel: Bool {
        state != .revoked && accountID != nil && ownerAccount() == accountID
            && currentSource()?.accountID == accountID
    }

    init(
        initialSource: TdUpdateSource?, currentSource: @escaping () -> TdUpdateSource?,
        ownerAccount: @escaping () -> UUID?, readiness: AnyPublisher<TdUpdateSource?, Never>,
        clientChanges: AnyPublisher<TdUpdateSource, Never>, modelChanges: AnyPublisher<Void, Never>,
        folders: @escaping () -> [CustomFolder], allFolders: @escaping () -> [CustomFolder],
        resolve: @escaping (TdUpdateSource) -> Endpoint?,
        reader: Reader? = nil,
    ) {
        self.accountID = initialSource?.accountID
        self.currentSource = currentSource
        self.ownerAccount = ownerAccount
        self.resolve = resolve
        self.reader = reader
        self.readFolders = folders
        self.readAllFolders = allFolders
        clientChanges.sink { [weak self] source in
            guard let self else { return }
            if source.accountID != accountID { revoke() } else { refresh() }
        }
        .store(in: &subscriptions)
        readiness.sink { [weak self] source in
            guard let self else { return }
            self.readySource = source
            refresh()
        }
        .store(in: &subscriptions)
        modelChanges.sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }

    static func live(rootVM: RootVM, authority: ChatListActionAuthority?) -> FolderFlowSession {
        let authority = authority ?? ChatListActionAuthority()
        return FolderFlowSession(
            initialSource: authority.source,
            currentSource: { TDLib.shared.activeUpdateSource },
            ownerAccount: { rootVM.activeAccountID },
            readiness: TDLib.shared.readyClientChanges,
            clientChanges: TDLib.shared.activeClientChanges,
            modelChanges: rootVM.objectWillChange.receive(on: DispatchQueue.main).eraseToAnyPublisher(),
            folders: { rootVM.folders }, allFolders: { rootVM.allFolders },
            resolve: { source in
                let authority = ChatListActionAuthority()
                guard authority.source == source, authority.isCurrent else { return nil }
                let client = authority.client
                return Endpoint(source: source) { mutation in
                    switch mutation {
                    case .create(let folder):
                        return try await client.createChatFolder(folder: folder).id
                    case .edit(let id, let folder):
                        _ = try await client.editChatFolder(chatFolderId: id, folder: folder)
                        return nil
                    case .reorder(let ids, let mainPosition):
                        _ = try await client.reorderChatFolders(chatFolderIds: ids, mainChatListPosition: mainPosition)
                        return nil
                    case .delete(let id, let leaveChatIDs):
                        _ = try await client.deleteChatFolder(chatFolderId: id, leaveChatIds: leaveChatIDs)
                        return nil
                    }
                }
            },
            reader: Reader(
                chosenChatLimit: {
                    let client = ChatListActionAuthority().client
                    guard case .optionValueInteger(let value) = try? await client.getOption(
                        name: "chat_folder_chosen_chat_count_max",
                    ) else { return nil }
                    return max(1, Int(clamping: value.value))
                },
                chatCount: { folder in
                    let client = ChatListActionAuthority().client
                    return try? await client.getChatFolderChatCount(folder: folder).count
                },
                loadMoreMainChats: {
                    guard let main = rootVM.folders.first(where: { $0.id == 0 }) else { return }
                    rootVM.loadMoreChats(in: main)
                },
                searchChats: { query in
                    let client = ChatListActionAuthority().client
                    var ids = [Int64]()
                    if let local = try? await client.searchChats(limit: 50, query: query, typeFilter: nil) {
                        ids += local.chatIds
                    }
                    if let server = try? await client.searchChatsOnServer(limit: 50, query: query, typeFilter: nil) {
                        ids += server.chatIds
                    }
                    if let contacts = try? await client.searchContacts(query: query, limit: 50) {
                        // A contact without a chat yet gets its private chat, whose ID is the user's.
                        for userID in contacts.userIds where !ids.contains(userID) {
                            guard !Task.isCancelled else { return [] }
                            if let chat = try? await client.createPrivateChat(force: false, userId: userID) {
                                ids.append(chat.id)
                            }
                        }
                    }
                    var seen = Set<Int64>()
                    var chats = [CustomChat]()
                    for id in ids where seen.insert(id).inserted {
                        guard !Task.isCancelled else { return [] }
                        if let chat = await rootVM.getCustomChatForNavigation(from: id, client: client) {
                            chats.append(chat)
                        }
                    }
                    return chats
                },
                recommendedFolders: {
                    let client = ChatListActionAuthority().client
                    return await (try? client.send(TDNativeRequests.getRecommendedChatFolders()))?.chatFolders ?? []
                },
                inviteLinkClient: { ChatListActionAuthority().client },
            ),
        )
    }

    func scope(owner: UIViewController) -> ChatListActionScope {
        let expected = generation
        return ChatListActionScope(
            source: endpoint?.source,
            currentSource: { [weak self] in
                guard let self, generation == expected, isCurrent else { return nil }
                return endpoint?.source
            },
            ownerIsAttached: { [weak owner] in owner?.chatListActionOwnerIsAttached == true },
        )
    }

    func bind(_ owner: UIViewController, onReady: @escaping () -> Void = {}) -> AnyCancellable {
        changes.sink { [weak owner] state in
            guard let owner else { return }
            owner.navigationItem.rightBarButtonItem?.isEnabled = state == .ready
            switch state {
            case .ready:
                owner.navigationItem.prompt = nil
                onReady()
            case .waiting: owner.navigationItem.prompt = L10n.betterTG("Session.ReconnectingKeepsChanges")
            case .saving: owner.navigationItem.prompt = L10n.betterTG("Session.Saving")
            case .uncertain:
                owner.navigationItem.prompt = L10n.betterTG("Folders.ResultUnknown")
            case .revoked:
                owner.navigationItem.prompt = L10n.betterTG("Session.AccountInactive")
                owner.view.isUserInteractionEnabled = false
                guard let navigation = owner.navigationController,
                      let index = navigation.viewControllers.firstIndex(where: { $0 === owner }) else { return }
                if index > 0 {
                    navigation.setViewControllers(Array(navigation.viewControllers.prefix(index)), animated: false)
                } else if navigation.presentingViewController != nil {
                    navigation.dismiss(animated: false)
                }
            }
        }
    }

    /// Writes the mutation; a successful creation completes with the new folder's ID.
    func mutate(
        _ mutation: Mutation,
        owner: UIViewController,
        completion: @escaping (Result<Int?, any Swift.Error>) -> Void,
    ) {
        let scope = scope(owner: owner)
        guard scope.isCurrent, let endpoint, pending == nil else { return }
        let id = UUID()
        let expectedGeneration = generation
        pending = (id, false)
        // The dispatch gate runs in the task, not when a button first schedules it.
        Task { [weak self] in
            guard let self, pending?.id == id else { return }
            guard scope.isCurrent else {
                pending = nil
                refresh()
                return
            }
            publish(.saving)
            guard generation == expectedGeneration, state == .saving,
                  readySource == endpoint.source, currentSource() == endpoint.source,
                  ownerAccount() == accountID, scope.ownerIsAttached()
            else {
                pending = nil
                refresh()
                return
            }
            pending = (id, true)
            let result: Result<Int?, any Swift.Error>
            do {
                result = try await .success(endpoint.write(mutation))
            } catch {
                result = .failure(error)
            }
            guard pending?.id == id else { return }
            pending = nil
            // An ACK from a retired client cannot resolve an uncertain operation.
            guard state == .saving, readySource == endpoint.source,
                  currentSource() == endpoint.source, ownerAccount() == accountID
            else {
                if state != .revoked { publish(.uncertain) }
                return
            }
            publish(.ready)
            guard scope.isCurrent else { return }
            completion(result)
        }
    }

    private func refresh() {
        guard state != .revoked else { return }
        guard let accountID, let current = currentSource(), current.accountID == accountID else {
            revoke()
            return
        }
        let accepted = readySource == current && ownerAccount() == accountID
        if !accepted || (endpoint != nil && endpoint?.source != current) {
            generation = UUID()
            endpoint = nil
            if pending?.dispatched == true { publish(.uncertain) }
        }
        guard state != .uncertain else { return }
        guard accepted else {
            publish(.waiting)
            return
        }
        if endpoint == nil { endpoint = resolve(current) }
        guard endpoint?.source == current else {
            publish(.waiting)
            return
        }
        publish(pending?.dispatched == true ? .saving : .ready)
    }

    private func revoke() {
        generation = UUID()
        endpoint = nil
        publish(.revoked)
    }

    private func publish(_ value: State) {
        state = value
        changes.send(value)
    }
}
