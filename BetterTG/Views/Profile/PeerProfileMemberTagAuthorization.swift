// PeerProfileMemberTagAuthorization.swift

import TDLibKitDynamic
import UIKit

// MARK: - PeerProfileMemberTagAuthorization

/// Fresh actor, target and chat authority for one immutable tag mutation.
@MainActor struct PeerProfileMemberTagAuthorization {
    struct Snapshot {
        let chatID: Int64
        let chatType: ChatType
        let permissions: ChatPermissions
        let actor: ChatMember
        let target: ChatMember
    }

    let chatID: Int64
    let actorID: Int64
    let targetID: Int64
    let source: TdUpdateSource
    let currentSource: () -> TdUpdateSource?
    let currentActor: () -> Int64?
    let fetch: @MainActor () async throws -> Snapshot

    static func live(accountID: UUID, actorID: Int64, chatID: Int64, targetID: Int64, client: TDLibClient) -> Self {
        Self(
            chatID: chatID,
            actorID: actorID,
            targetID: targetID,
            source: .init(accountID: accountID, clientID: client.id),
            currentSource: { TDLib.shared.activeUpdateSource },
            currentActor: { TDLib.shared.activeAccount?.userID },
            fetch: {
                async let chat = client.getChat(chatId: chatID)
                async let actor = client.getChatMember(
                    chatId: chatID,
                    memberId: .messageSenderUser(.init(userId: actorID)),
                )
                async let target = client.getChatMember(
                    chatId: chatID,
                    memberId: .messageSenderUser(.init(userId: targetID)),
                )
                let values = try await (chat, actor, target)
                return Snapshot(
                    chatID: values.0.id,
                    chatType: values.0.type,
                    permissions: values.0.permissions,
                    actor: values.1,
                    target: values.2,
                )
            },
        )
    }

    func load() async throws -> PeerProfileMemberTagAuthority {
        try check()
        let snapshot = try await fetch()
        try check()
        guard snapshot.chatID == chatID,
              snapshot.actor.memberId == .messageSenderUser(.init(userId: actorID)),
              snapshot.target.memberId == .messageSenderUser(.init(userId: targetID))
        else {
            throw PeerProfileMemberTagError.accountChanged
        }
        return try PeerProfileMemberTagAuthority.validate(snapshot, actorID: actorID, targetID: targetID)
    }

    func perform(baseline: String, write: @MainActor () async throws -> Void) async throws {
        let authority = try await load()
        guard authority.baselineTag == baseline else { throw PeerProfileMemberTagError.staleTag }
        try check()
        try await write()
        try check()
    }

    private func check() throws {
        try Task.checkCancellation()
        guard currentSource() == source,
              currentActor() == actorID else { throw PeerProfileMemberTagError.accountChanged }
    }
}

// MARK: - PeerProfileMemberTagRetention

/// A typed editor hold is separate from quiescent Members replacement. Neither
/// stale parent becomes authoritative while the exact tag editor owns its draft.
@MainActor final class PeerProfileMemberTagRetention {
    weak var editor: PeerProfileMemberTagViewController?

    func shouldRetain(
        parent: UIViewController,
        members: UIViewController,
        accountID: UUID,
        actorID: Int64?,
        chatID: Int64,
        currentAccountID: UUID?,
        currentActorID: Int64?,
    ) -> Bool {
        guard let actorID, currentAccountID == accountID, currentActorID == actorID,
              let editor, editor.represents(accountID: accountID, actorID: actorID, chatID: chatID),
              editor.canRetainStaleParents, PeerProfileEditSession.isAttached(parent),
              PeerProfileEditSession.isAttached(members), PeerProfileEditSession.isAttached(editor),
              let navigation = parent.navigationController,
              members.navigationController === navigation, editor.navigationController === navigation,
              navigation.topViewController === editor,
              let index = navigation.viewControllers.firstIndex(where: { $0 === parent }),
              navigation.viewControllers.indices.contains(index + 2) else { return false }
        return navigation.viewControllers[index + 1] === members && navigation.viewControllers[index + 2] === editor
    }
}
