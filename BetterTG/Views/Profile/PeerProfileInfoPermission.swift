// PeerProfileInfoPermission.swift

import Foundation
import TDLibKitDynamic

func peerProfileCanChangeInfo(
    chatType: ChatType,
    permissions: ChatPermissions,
    status: ChatMemberStatus?,
) -> Bool {
    let isBasicGroup: Bool
    let isChannel: Bool
    switch chatType {
    case .chatTypeBasicGroup:
        isBasicGroup = true
        isChannel = false
    case .chatTypeSupergroup(let group):
        isBasicGroup = false
        isChannel = group.isChannel
    case .chatTypePrivate, .chatTypeSecret:
        return false
    }

    switch status {
    case .chatMemberStatusCreator:
        return true
    case .chatMemberStatusAdministrator(let administrator):
        // Basic-group administrators have all applicable rights. In a
        // supergroup an administrator also retains ordinary member permissions.
        return isBasicGroup || administrator.rights.canChangeInfo || !isChannel && permissions.canChangeInfo
    case .chatMemberStatusMember:
        return !isChannel && permissions.canChangeInfo
    case .chatMemberStatusRestricted(let restricted):
        return !isBasicGroup && !isChannel && restricted.isMember
            && permissions.canChangeInfo && restricted.permissions.canChangeInfo
    case .chatMemberStatusBanned, .chatMemberStatusLeft, nil:
        return false
    }
}

// MARK: - PeerProfileInfoPermissionState

/// Keep capability updates separate from shared mutable profile metadata.
struct PeerProfileInfoPermissionState {
    let source: TdUpdateSource
    let chatID: Int64
    private(set) var chatType: ChatType
    private(set) var permissions: ChatPermissions
    private(set) var status: ChatMemberStatus?
    private(set) var revision = UInt64.zero

    var canChangeInfo: Bool {
        peerProfileCanChangeInfo(chatType: chatType, permissions: permissions, status: status)
    }

    mutating func updatePermissions(_ update: UpdateChatPermissions, source: TdUpdateSource) -> Bool {
        guard source == self.source, update.chatId == chatID else { return false }
        permissions = update.permissions
        revision &+= 1
        return true
    }

    mutating func updateStatus(_ status: ChatMemberStatus, chatType: ChatType, source: TdUpdateSource) -> Bool {
        guard source == self.source, chatType == self.chatType else { return false }
        self.status = status
        revision &+= 1
        return true
    }

    mutating func refresh(
        chatID: Int64,
        chatType: ChatType,
        permissions: ChatPermissions,
        status: ChatMemberStatus,
        ifRevision revision: UInt64,
    ) {
        guard chatID == self.chatID, self.revision == revision else { return }
        self.chatType = chatType
        self.permissions = permissions
        self.status = status
        self.revision &+= 1
    }
}

// MARK: - PeerProfileInfoEditAuthorization

/// Re-read both effective default rights and actor status before each write.
@MainActor struct PeerProfileInfoEditAuthorization {
    struct Snapshot {
        let chatID: Int64
        let chatType: ChatType
        let permissions: ChatPermissions
        let memberID: MessageSender
        let status: ChatMemberStatus
    }

    let chatID: Int64
    let actorUserID: Int64
    let source: TdUpdateSource
    let currentSource: () -> TdUpdateSource?
    let currentActorUserID: () -> Int64?
    let fetchSnapshot: @MainActor () async throws -> Snapshot

    var contextIsCurrent: Bool {
        source == currentSource() && actorUserID == currentActorUserID()
    }

    static func live(
        accountID: UUID,
        actorUserID: Int64,
        chatID: Int64,
        client: TDLibClient,
    ) -> Self {
        Self(
            chatID: chatID,
            actorUserID: actorUserID,
            source: TdUpdateSource(accountID: accountID, clientID: client.id),
            currentSource: {
                TDLib.shared.activeAccountID.map {
                    TdUpdateSource(accountID: $0, clientID: TDLib.shared.activeClient.id)
                }
            },
            currentActorUserID: { TDLib.shared.activeAccount?.userID },
            fetchSnapshot: {
                async let chatRequest = client.getChat(chatId: chatID)
                async let memberRequest = client.getChatMember(
                    chatId: chatID,
                    memberId: .messageSenderUser(.init(userId: actorUserID)),
                )
                let (chat, member) = try await (chatRequest, memberRequest)
                return Snapshot(
                    chatID: chat.id, chatType: chat.type, permissions: chat.permissions,
                    memberID: member.memberId, status: member.status,
                )
            },
        )
    }

    func loadSnapshot() async throws -> Snapshot {
        try checkContext()
        do {
            let snapshot = try await fetchSnapshot()
            try checkContext()
            guard snapshot.chatID == chatID,
                  snapshot.memberID == .messageSenderUser(.init(userId: actorUserID))
            else { throw PeerProfileEditError.permissionChanged }
            return snapshot
        } catch {
            try checkContext()
            throw error
        }
    }

    func perform<Value>(_ write: @MainActor () async throws -> Value) async throws -> Value {
        let snapshot = try await loadSnapshot()
        try checkContext()
        guard peerProfileCanChangeInfo(
            chatType: snapshot.chatType, permissions: snapshot.permissions, status: snapshot.status,
        ) else { throw PeerProfileEditError.permissionChanged }
        do {
            let result = try await write()
            try checkContext()
            return result
        } catch {
            try checkContext()
            throw error
        }
    }

    private func checkContext() throws {
        try Task.checkCancellation()
        guard contextIsCurrent else { throw PeerProfileEditError.permissionChanged }
    }
}
