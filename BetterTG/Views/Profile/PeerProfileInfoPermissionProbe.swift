// PeerProfileInfoPermissionProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    @MainActor enum PeerProfileInfoPermissionProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private final class Gate {
            private var entered = false
            private var continuation: CheckedContinuation<Void, Never>?
            private var observer: CheckedContinuation<Void, Never>?

            func wait() async {
                entered = true
                observer?.resume()
                observer = nil
                await withCheckedContinuation { continuation = $0 }
            }

            func waitUntilEntered() async {
                guard !entered else { return }
                await withCheckedContinuation { observer = $0 }
            }

            func open() {
                continuation?.resume()
                continuation = nil
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-info-permissions") else { return }
            Task {
                let result: String
                do {
                    try verifyPolicyAndUpdates()
                    try await verifyAuthorization()
                    result = "Profile info permission probe passed: production-policy/authorization=true; "
                        + "basic/supergroup-member-allow/deny; restricted-default-intersection; "
                        + "creator/admin-rights; broadcast-member-denied; private/secret-denied; "
                        + "scoped-live-updates; stale-refresh-fenced; fresh-check-before-each-write; "
                        + "revoked-second-write=0; wrong-account/client/actor/chat-writes=0; "
                        + "cancelled-writes=0; late-success/error-fenced; server-writes=0; UIKit-runtime=unverified"
                } catch {
                    result = "Profile info permission probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("profile-info-permissions-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(description: message) }
        }

        private static func verifyPolicyAndUpdates() throws {
            let basic = ChatType.chatTypeBasicGroup(.init(basicGroupId: 7))
            let group = ChatType.chatTypeSupergroup(.init(supergroupId: 7, isChannel: false))
            let channel = ChatType.chatTypeSupergroup(.init(supergroupId: 7, isChannel: true))
            let member = ChatMemberStatus.chatMemberStatusMember(.init(memberUntilDate: 0))
            let creator = ChatMemberStatus.chatMemberStatusCreator(.init(isAnonymous: false, isMember: true))
            let cases: [(String, ChatType, Bool, ChatMemberStatus?, Bool)] = [
                ("basic member allowed", basic, true, member, true),
                ("basic member denied", basic, false, member, false),
                ("basic admin full rights", basic, false, administrator(false), true),
                ("basic creator", basic, false, creator, true),
                ("basic restricted unsupported", basic, true, restricted(true), false),
                ("group member allowed", group, true, member, true),
                ("group member denied", group, false, member, false),
                ("group admin explicit", group, false, administrator(true), true),
                ("group admin member fallback", group, true, administrator(false), true),
                ("group admin denied", group, false, administrator(false), false),
                ("group creator", group, false, creator, true),
                ("restricted allowed", group, true, restricted(true), true),
                ("restricted denied", group, true, restricted(false), false),
                ("restricted default denied", group, false, restricted(true), false),
                ("restricted nonmember", group, true, restricted(true, isMember: false), false),
                ("broadcast member denied", channel, true, member, false),
                ("broadcast admin allowed", channel, false, administrator(true), true),
                ("broadcast admin no fallback", channel, true, administrator(false), false),
                ("broadcast creator", channel, false, creator, true),
                ("broadcast restricted unsupported", channel, true, restricted(true), false),
                ("left denied", group, true, .chatMemberStatusLeft, false),
                ("banned denied", group, true, .chatMemberStatusBanned(.init(bannedUntilDate: 0)), false),
                ("unknown denied", group, true, nil, false),
                ("private denied", .chatTypePrivate(.init(userId: 7)), true, creator, false),
                ("secret denied", .chatTypeSecret(.init(secretChatId: 7, userId: 7)), true, creator, false),
            ]
            for (label, type, allowed, status, expected) in cases {
                try require(peerProfileCanChangeInfo(
                    chatType: type, permissions: permissions(allowed), status: status,
                ) == expected, label)
            }

            let source = TdUpdateSource(accountID: UUID(), clientID: 73)
            let wrongAccount = TdUpdateSource(accountID: UUID(), clientID: source.clientID)
            let wrongClient = TdUpdateSource(accountID: source.accountID, clientID: 74)
            var state = PeerProfileInfoPermissionState(
                source: source, chatID: 17, chatType: group, permissions: permissions(false), status: member,
            )
            let oldRevision = state.revision
            try require(
                state.updatePermissions(.init(chatId: 17, permissions: permissions(true)), source: source),
                "current permission update rejected",
            )
            try require(state.canChangeInfo, "permission update did not enable Edit")
            for obsolete in [wrongAccount, wrongClient] {
                try require(
                    !state.updatePermissions(.init(chatId: 17, permissions: permissions(false)), source: obsolete),
                    "wrong source default update accepted",
                )
                try require(
                    !state.updateStatus(.chatMemberStatusLeft, chatType: group, source: obsolete),
                    "wrong source actor update accepted",
                )
            }
            try require(
                !state.updatePermissions(.init(chatId: 18, permissions: permissions(false)), source: source),
                "wrong chat permission update accepted",
            )
            try require(
                !state.updateStatus(.chatMemberStatusLeft, chatType: channel, source: source),
                "wrong chat kind status accepted",
            )
            state.refresh(
                chatID: 17, chatType: group, permissions: permissions(false), status: member, ifRevision: oldRevision,
            )
            try require(state.canChangeInfo, "older getChat overwrote live permission")
            try require(
                state.updateStatus(restricted(false), chatType: group, source: source),
                "status update rejected",
            )
            try require(!state.canChangeInfo, "live restriction did not disable Edit")
            try require(
                state.updateStatus(administrator(true), chatType: group, source: source),
                "admin update rejected",
            )
            try require(state.canChangeInfo, "live admin promotion did not enable Edit")
            state.refresh(
                chatID: 17, chatType: group, permissions: permissions(false), status: member,
                ifRevision: state.revision,
            )
            try require(!state.canChangeInfo, "fresh appearance snapshot retained old admin permission")
        }

        private static func verifyAuthorization() async throws {
            let source = TdUpdateSource(accountID: UUID(), clientID: 81)
            let otherAccount = TdUpdateSource(accountID: UUID(), clientID: source.clientID)
            let replacement = TdUpdateSource(accountID: source.accountID, clientID: 82)
            let actorID: Int64 = 11
            let member = ChatMemberStatus.chatMemberStatusMember(.init(memberUntilDate: 0))
            let group = ChatType.chatTypeSupergroup(.init(supergroupId: 7, isChannel: false))
            func snapshot(
                allowed: Bool = true, chatID: Int64 = 17, userID: Int64? = nil,
            ) -> PeerProfileInfoEditAuthorization.Snapshot {
                .init(
                    chatID: chatID,
                    chatType: group,
                    permissions: permissions(allowed),
                    memberID: .messageSenderUser(.init(userId: userID ?? actorID)),
                    status: member,
                )
            }
            var current: TdUpdateSource? = source
            var currentActorID = actorID
            var freshSnapshot = snapshot()
            var reads = 0
            var writes = 0
            let authorization = PeerProfileInfoEditAuthorization(
                chatID: 17, actorUserID: actorID, source: source, currentSource: { current },
                currentActorUserID: { currentActorID },
                fetchSnapshot: {
                    reads += 1
                    return freshSnapshot
                },
            )
            let appearance = try await authorization.loadSnapshot()
            try require(
                appearance.status == member && appearance.permissions.canChangeInfo,
                "fresh entry capability missing",
            )
            _ = try await authorization.perform { writes += 1 }
            freshSnapshot = snapshot(allowed: false)
            do {
                _ = try await authorization.perform { writes += 1 }
                throw Failure(description: "revoked second write accepted")
            } catch PeerProfileEditError.permissionChanged {}
            try require(reads == 3 && writes == 1, "fresh permission not read before each write")

            for invalid in [snapshot(chatID: 18), snapshot(userID: 12)] {
                freshSnapshot = invalid
                do {
                    _ = try await authorization.perform { writes += 1 }
                    throw Failure(description: "wrong chat/actor response accepted")
                } catch PeerProfileEditError.permissionChanged {}
            }
            try require(writes == 1, "identity mismatch wrote")

            for invalidation in 0..<5 {
                for requestThrows in [false, true] {
                    current = source
                    currentActorID = actorID
                    let gate = Gate()
                    let pending = PeerProfileInfoEditAuthorization(
                        chatID: 17, actorUserID: actorID, source: source, currentSource: { current },
                        currentActorUserID: { currentActorID },
                        fetchSnapshot: {
                            await gate.wait()
                            if requestThrows { throw Failure(description: "old read error") }
                            return snapshot()
                        },
                    )
                    let task = Task {
                        do {
                            _ = try await pending.perform { writes += 1 }
                            return false
                        } catch {
                            return true
                        }
                    }
                    await gate.waitUntilEntered()
                    switch invalidation {
                    case 0: current = otherAccount
                    case 1: current = replacement
                    case 2: currentActorID = 12
                    case 3: current = nil
                    default: task.cancel()
                    }
                    gate.open()
                    let rejected = await task.value
                    try require(rejected && writes == 1, "stale or cancelled authorization wrote")
                }
            }

            for requestThrows in [false, true] {
                current = source
                currentActorID = actorID
                freshSnapshot = snapshot()
                let gate = Gate()
                var completions = 0
                let task = Task {
                    do {
                        _ = try await authorization.perform {
                            await gate.wait()
                            if requestThrows { throw Failure(description: "old write error") }
                        }
                        completions += 1
                        return false
                    } catch {
                        return true
                    }
                }
                await gate.waitUntilEntered()
                current = replacement
                gate.open()
                let rejected = await task.value
                try require(rejected && completions == 0, "stale write completion delivered")
            }
        }

        private static func restricted(_ allowed: Bool, isMember: Bool = true) -> ChatMemberStatus {
            .chatMemberStatusRestricted(.init(
                isMember: isMember,
                restrictedUntilDate: 0,
                permissions: permissions(allowed),
            ))
        }

        private static func permissions(_ allowed: Bool) -> ChatPermissions {
            .init(
                canSendBasicMessages: false,
                canSendAudios: false,
                canSendDocuments: false,
                canSendPhotos: false,
                canSendVideos: false,
                canSendVideoNotes: false,
                canSendVoiceNotes: false,
                canSendPolls: false,
                canSendOtherMessages: false,
                canAddLinkPreviews: false,
                canReactToMessages: false,
                canEditTag: false,
                canChangeInfo: allowed,
                canInviteUsers: false,
                canPinMessages: false,
                canCreateTopics: false,
            )
        }

        private static func administrator(_ allowed: Bool) -> ChatMemberStatus {
            .chatMemberStatusAdministrator(.init(canBeEdited: false, rights: .init(
                canManageChat: false,
                canChangeInfo: allowed,
                canPostMessages: false,
                canEditMessages: false,
                canDeleteMessages: false,
                canInviteUsers: false,
                canRestrictMembers: false,
                canPinMessages: false,
                canManageTopics: false,
                canPromoteMembers: false,
                canManageVideoChats: false,
                canPostStories: false,
                canEditStories: false,
                canDeleteStories: false,
                canManageDirectMessages: false,
                canManageTags: false,
                canSendWelcomeMessages: false,
                isAnonymous: false,
            )))
        }
    }
#endif
