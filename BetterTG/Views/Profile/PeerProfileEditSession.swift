// PeerProfileEditSession.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - PeerProfileEditSession

@MainActor final class PeerProfileEditSession {
    enum Mutation: Equatable {
        case name(String, String)
        case bio(String)
        case title(Int64, String)
        case description(Int64, String)
    }

    enum State { case waiting, ready, saving, uncertain, revoked }

    struct Endpoint {
        let source: TdUpdateSource
        let write: (Mutation, @escaping () throws -> Void) async throws -> Void
    }

    private final class Attempt {
        let endpoint: Endpoint
        weak var owner: UIViewController?
        var dispatched = false

        init(endpoint: Endpoint, owner: UIViewController) {
            self.endpoint = endpoint
            self.owner = owner
        }
    }

    let accountID: UUID

    private let actorID: Int64?
    private let currentSource: () -> TdUpdateSource?
    private let currentActor: () -> Int64?
    private let resolve: (TdUpdateSource) -> Endpoint?
    private let changes = CurrentValueSubject<State, Never>(.waiting)
    private var readySource: TdUpdateSource?
    private var attempt: Attempt?
    private var task: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    var state: State { changes.value }
    var publisher: AnyPublisher<State, Never> { changes.eraseToAnyPublisher() }

    init(
        accountID: UUID,
        actorID: Int64?,
        currentSource: @escaping () -> TdUpdateSource?,
        currentActor: @escaping () -> Int64?,
        readiness: AnyPublisher<TdUpdateSource?, Never>,
        clientChanges: AnyPublisher<TdUpdateSource, Never>,
        accountChanges: AnyPublisher<Void, Never>,
        resolve: @escaping (TdUpdateSource) -> Endpoint?,
    ) {
        self.accountID = accountID
        self.actorID = actorID
        self.currentSource = currentSource
        self.currentActor = currentActor
        self.resolve = resolve
        clientChanges.sink { [weak self] source in
            guard let self else { return }
            refresh(departed: source.accountID != accountID)
        }
        .store(in: &subscriptions)
        readiness.sink { [weak self] source in
            self?.readySource = source
            self?.refresh()
        }
        .store(in: &subscriptions)
        accountChanges.sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
    }

    static func live(accountID: UUID, actorID: Int64?) -> PeerProfileEditSession {
        PeerProfileEditSession(
            accountID: accountID,
            actorID: actorID,
            currentSource: { TDLib.shared.activeUpdateSource },
            currentActor: { TDLib.shared.activeAccount?.userID },
            readiness: TDLib.shared.readyClientChanges,
            clientChanges: TDLib.shared.activeClientChanges,
            accountChanges: nc.publisher(for: .telegramAccountsChanged)
                .map { _ in () }
                .eraseToAnyPublisher(),
            resolve: { source in
                guard TDLib.shared.activeUpdateSource == source, let actorID,
                      TDLib.shared.activeAccount?.userID == actorID else { return nil }
                let client = TDLib.shared.activeClient
                return Endpoint(source: source) { mutation, dispatch in
                    switch mutation {
                    case .name(let first, let last):
                        try dispatch()
                        _ = try await client.setName(firstName: first, lastName: last)
                    case .bio(let value):
                        try dispatch()
                        _ = try await client.setBio(bio: value)
                    case .description(let chatID, let value), .title(let chatID, let value):
                        let authorization = PeerProfileInfoEditAuthorization.live(
                            accountID: accountID, actorUserID: actorID, chatID: chatID,
                            client: client,
                        )
                        _ = try await authorization.perform {
                            try dispatch()
                            if case .title = mutation {
                                return try await client.setChatTitle(chatId: chatID, title: value)
                            }
                            return try await client.setChatDescription(
                                chatId: chatID,
                                description: value,
                            )
                        }
                    }
                }
            },
        )
    }

    static func isAttached(_ owner: UIViewController?) -> Bool {
        owner?.chatListActionOwnerIsAttached == true
    }

    func representsActor(_ userID: Int64) -> Bool { actorID == userID }

    func save(
        _ mutations: [Mutation],
        owner: UIViewController,
        accepted: @escaping (Mutation) -> Void,
        completion: @escaping (Result<Void, any Swift.Error>, Int) -> Void,
    ) {
        guard state == .ready, attempt == nil, Self.isAttached(owner), let source = readySource,
              accepts(source), let endpoint = resolve(source), endpoint.source == source else { return }
        let pending = Attempt(endpoint: endpoint, owner: owner)
        attempt = pending
        changes.send(.saving)
        guard (try? check(pending)) != nil else {
            if attempt === pending {
                attempt = nil
                refresh()
            }
            return
        }
        task = Task { [weak self] in
            var completed = 0
            let result: Result<Void, any Swift.Error>
            do {
                for mutation in mutations {
                    try self?.check(pending)
                    guard self != nil else { return }
                    try await endpoint.write(mutation) { [weak self] in
                        guard let self else { throw CancellationError() }
                        try check(pending)
                        pending.dispatched = true
                    }
                    guard let self else { return }
                    try check(pending)
                    accepted(mutation)
                    completed += 1
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            guard let self, attempt === pending else { return }
            let deliver = (try? check(pending)) != nil
            attempt = nil
            task = nil
            if !deliver, pending.dispatched { changes.send(.uncertain) }
            refresh()
            guard deliver, state == .ready, accepts(source), Self.isAttached(pending.owner) else { return }
            completion(result, completed)
        }
    }

    private func check(_ pending: Attempt) throws {
        guard !Task.isCancelled, attempt === pending, state == .saving,
              accepts(pending.endpoint.source), Self.isAttached(pending.owner) else { throw CancellationError() }
    }

    private func accepts(_ source: TdUpdateSource) -> Bool {
        source.accountID == accountID && source == currentSource() && source == readySource
            && actorID != nil && actorID == currentActor()
    }

    private func refresh(departed: Bool = false) {
        guard state != .revoked else { return }
        let departed = departed || currentSource()?.accountID != accountID
            || (currentActor() != nil && actorID != currentActor())
        let accepted = readySource.map(accepts) == true
        if departed || !accepted || attempt.map({ !accepts($0.endpoint.source) }) == true {
            let uncertain = attempt?.dispatched == true || state == .uncertain
            if attempt?.dispatched == false { task?.cancel() }
            attempt = nil
            task = nil
            changes.send(departed ? .revoked : uncertain ? .uncertain : .waiting)
        } else if state != .uncertain {
            changes.send(attempt == nil ? .ready : .saving)
        }
    }
}

// MARK: - PeerProfileEditorRetention

/// Only this parent's exact editor may delay retiring a stale profile route.
@MainActor final class PeerProfileEditorRetention {
    weak var editor: PeerProfileEditViewController?

    func shouldRetain(parent: UIViewController, accountID: UUID, currentAccountID: UUID?) -> Bool {
        guard currentAccountID == accountID, let editor, editor.editAccountID == accountID,
              editor.canRetainStaleProfile,
              PeerProfileEditSession.isAttached(editor), let navigation = parent.navigationController,
              editor.navigationController === navigation,
              let index = navigation.viewControllers.firstIndex(where: { $0 === parent }),
              navigation.viewControllers.indices.contains(index + 1) else { return false }
        return navigation.viewControllers[index + 1] === editor
    }
}
