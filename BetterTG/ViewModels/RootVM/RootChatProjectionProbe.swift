// RootChatProjectionProbe.swift

#if DEBUG
    import Combine
    import Foundation
    import TDLibKitDynamic
    import UIKit

    @MainActor enum RootChatProjectionProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Gate {
            var continuation: CheckedContinuation<Void, Never>?

            func wait() async { await withCheckedContinuation { continuation = $0 } }
            func release() {
                let pending = continuation
                continuation = nil
                pending?.resume()
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-root-chat-projection") else { return }
            Task {
                let result: String
                do {
                    try verifyReadBoundaries()
                    try await verifyReadOutbox()
                    try await verifyRebuild()
                    try await verifyInsertionAdmission()
                    try await verifyInsertionRetirement()
                    try await verifyRefreshSupersession()
                    result = "Root chat projection probe passed: actual-reducer/insertion-helper=true; "
                        + "pre-read-freshness/raw-peer-boundaries/nil-fields=true; suspended-rebuild/new-folder/complete-partial-membership=true; "
                        + "late-insertion-unread/user/notification/title=true; coalesced-feed/terminal/supersession/epoch/refresh-retirement=true; "
                        + "scoped-outbox/live-folder-archive-patch/stale-hydration/native-cell-read-AX=true; "
                        + "RootVM/notification-RPC-wiring=source-reviewed; real-folder-rebuild=unverified; server-calls=0"
                } catch {
                    result = "Root chat projection probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("root-chat-projection-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ value: Bool, _ message: String) throws {
            if !value { throw Failure(description: message) }
        }

        private static func until(_ condition: () -> Bool, _ message: String) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                await Task.yield()
            }
            throw Failure(description: message)
        }

        private static func position(
            _ order: Int64,
            list: ChatList = .chatListMain,
            pinned: Bool = false,
        ) -> ChatPosition {
            .init(isPinned: pinned, list: list, order: .init(order), source: nil)
        }

        private static func unread(_ count: Int, id: Int64 = 7) -> Update {
            .updateChatReadInbox(.init(chatId: id, lastReadInboxMessageId: Int64(count), unreadCount: count))
        }

        private static func verifyReadBoundaries() throws {
            let projection = RootChatProjection()
            let read = projection.begin(chatID: 7)
            defer { projection.finish(read) }
            projection.record(.updateChatTitle(.init(chatId: 7, title: "before-read")))
            projection.record(unread(99))
            projection.record(.updateUser(.init(user: user("before-peer", bot: true))))
            try require(read.debugRetainedUserCount == 0, "unrequested user feed retained")
            let rawBoundary = projection.revision
            let fresh = RootChatInsertionProbe.chat(
                position(50),
                title: "fresh-read",
                user: user("fresh-peer"),
                unread: 2,
            )
            read.track(fresh, raw: rawBoundary, peer: rawBoundary)
            try require(
                fresh.chat.title == "fresh-read" && fresh.unreadCount == 2 && fresh.user?.firstName == "fresh-peer",
                "pre-read projection overwrote fresher server payload",
            )

            projection.record(.updateChatTitle(.init(chatId: 7, title: "during-raw")))
            projection.record(unread(3))
            projection.record(.updateUser(.init(user: user("before-new-peer", bot: true))))
            let peerBoundary = projection.revision
            read.watchUser(17)
            let second = RootChatInsertionProbe.chat(
                position(50),
                title: "stale-raw",
                user: user("new-peer-read"),
                unread: 2,
            )
            read.track(second, raw: rawBoundary, peer: peerBoundary)
            try require(
                second.chat.title == "during-raw" && second.unreadCount == 3 && second.user?
                    .firstName == "new-peer-read",
                "raw and peer boundaries conflated",
            )
            projection.record(.updateUser(.init(user: user("during-peer", bot: true))))
            read.project(second)
            try require(second.bot != nil && second.user?.firstName == "during-peer", "late user/bot metadata lost")

            let previous = populatedChat()
            let clear = projection.begin(chatID: 7)
            let clearBoundary = projection.revision
            defer { projection.finish(clear) }
            projection.record(.updateChatDraftMessage(.init(chatId: 7, draftMessage: nil, positions: [position(50)])))
            projection.record(.updateChatLastMessage(.init(chatId: 7, lastMessage: nil, positions: [position(50)])))
            projection.record(.updateChatPhoto(.init(chatId: 7, photo: nil)))
            projection.record(.updateChatAccentColors(.init(
                accentColorId: 9,
                backgroundCustomEmojiId: 42,
                chatId: 7,
                profileAccentColorId: 8,
                profileBackgroundCustomEmojiId: 43,
                upgradedGiftColors: nil,
            )))
            projection.record(.updateChatViewAsTopics(.init(chatId: 7, viewAsTopics: true)))
            projection.record(.updateChatIsMarkedAsUnread(.init(chatId: 7, isMarkedAsUnread: true)))
            projection.record(.updateChatNotificationSettings(.init(chatId: 7, notificationSettings: mutedSettings())))
            clear.track(previous, raw: clearBoundary, peer: clearBoundary)
            try require(
                previous.draftMessage == nil && previous.lastMessage == nil && previous.chat.photo == nil,
                "explicit nil restored stale media/draft/last",
            )
            try require(
                previous.chat.accentColorId == 9 && previous.chat.backgroundCustomEmojiId == 42
                && previous.chat.profileAccentColorId == 8 && previous.chat.profileBackgroundCustomEmojiId == 43
                && previous.chat.viewAsTopics && previous.chat.isMarkedAsUnread && previous.chat.notificationSettings
                    .muteFor == 60,
                "typed metadata patch lost fields",
            )
            let untouched = RootChatInsertionProbe.chat(position(1), id: 8)
            clear.track(untouched, raw: clearBoundary, peer: clearBoundary)
            try require(
                untouched.chat.accentColorId == -1 && !untouched.chat.viewAsTopics,
                "chat ID projection crossed",
            )

            for count in 0..<5000 {
                projection.record(unread(count))
            }
            clear.project(previous)
            try require(
                clear.debugRetainedChatCount == 1 && previous.unreadCount == 4999,
                "busy feed was not coalesced",
            )
            projection.finish(clear)
            try require(
                !clear.isValid && clear.debugRetainedChatCount == 0 && clear.debugRetainedUserCount == 0,
                "terminal projection retained feed",
            )
            let replacement = projection.begin(chatID: 7)
            projection.record(unread(4))
            projection.finish(clear)
            try require(replacement.isValid, "late old cleanup closed replacement")
            projection.invalidate()
            try require(
                projection.debugActiveReadCount == 0 && !read.isValid && !replacement.isValid,
                "epoch invalidation retained active reads",
            )
        }

        private static func verifyReadOutbox() async throws {
            let projection = RootChatProjection()
            let authority = RootListAuthority()
            let source = TdUpdateSource(accountID: UUID(), clientID: 1)
            let replacement = TdUpdateSource(accountID: source.accountID, clientID: 2)
            var current = source
            let center = NotificationCenter()
            var subscriptions = Set<AnyCancellable>()
            let message = populatedChat(isOutgoing: true).lastMessage
            let main = RootChatInsertionProbe.chat(position(50), user: user("receipt"), last: message, unread: 3)
            let archived = RootChatInsertionProbe.chat(position(40, list: .chatListArchive), last: message)
            let other = RootChatInsertionProbe.chat(position(30), id: 8)
            let folder = RootChatInsertionProbe.folder()
            folder.chats = [main]
            let folders = [
                CustomFolder(chats: [main, other], type: .main), folder,
                CustomFolder(chats: [archived], type: .archive),
            ]
            var published = 0
            main.objectWillChange.sink { published += 1 }.store(in: &subscriptions)
            center.scopedPublisher(&subscriptions, for: .updateChatReadOutbox) { event in
                guard authority.accepts(
                    event.source, ownerAccountID: source.accountID, activeSource: current,
                ) else { return }
                projection.record(.updateChatReadOutbox(event.value))
                RootChatProjection.applyReadOutbox(event.value, to: folders)
            }
            func post(_ value: Int64, from source: TdUpdateSource) {
                center.postTdUpdate(
                    name: .updateChatReadOutbox,
                    object: UpdateChatReadOutbox(chatId: 7, lastReadOutboxMessageId: value), source: source,
                )
            }
            func drain() async {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
            let cell = ChatListCell(style: .default, reuseIdentifier: ChatListCell.reuseIdentifier)
            let client = TDLib.shared.activeClient
            cell.configure(chat: main, isMuted: false, client: client)
            try require(cell.accessibilityLabel?.contains(", Delivered") == true, "receipt baseline was not delivered")
            post(1, from: source)
            await drain()
            try require(
                main.chat.lastReadOutboxMessageId == 1 && archived.chat.lastReadOutboxMessageId == 1
                && other.chat.lastReadOutboxMessageId == 0 && published == 1
                && main.unreadCount == 3 && main.lastMessage == message,
                "receipt did not patch all exact rows once or changed another field/chat",
            )
            cell.configure(chat: main, isMuted: false, client: client)
            try require(cell.accessibilityLabel?.contains(", Read") == true, "native list cell did not expose Read")
            post(1, from: source)
            await drain()
            try require(published == 1, "duplicate receipt republished unchanged live rows")

            let lease = projection.begin(chatID: 7)
            defer { projection.finish(lease) }
            let boundary = projection.revision
            let pendingRaw = main.chat
            post(9, from: source)
            current = replacement
            authority.invalidate()
            post(2, from: replacement)
            post(10, from: TdUpdateSource(accountID: UUID(), clientID: replacement.clientID))
            center.post(
                name: .updateChatReadOutbox,
                object: UpdateChatReadOutbox(chatId: 7, lastReadOutboxMessageId: 11),
            )
            await drain()
            try require(
                main.chat.lastReadOutboxMessageId == 2 && archived.chat.lastReadOutboxMessageId == 2
                && published == 2 && projection.revision == boundary + 1,
                "queued old-client/foreign-account/unscoped receipt crossed authority",
            )
            try require(
                lease.project(pendingRaw, after: boundary).lastReadOutboxMessageId == 2
                && lease.project(pendingRaw, after: projection.revision).lastReadOutboxMessageId == 1,
                "outbox projection lost delayed-read update or overwrote a newer read boundary",
            )
            let hydrated = RootChatInsertionProbe.chat(position(50), last: message)
            lease.track(hydrated, raw: boundary, peer: boundary)
            try require(hydrated.chat.lastReadOutboxMessageId == 2, "late insertion lost accepted read receipt")
            projection.record(.updateNewChat(.init(chat: pendingRaw)))
            try require(
                lease.project(pendingRaw, after: boundary).lastReadOutboxMessageId == 1,
                "older receipt overrode a newer complete chat snapshot",
            )
            projection.record(.updateChatReadOutbox(.init(chatId: 7, lastReadOutboxMessageId: 3)))
            lease.project(hydrated)
            try require(hydrated.chat.lastReadOutboxMessageId == 3, "receipt after complete snapshot was lost")
            projection.invalidate()
            try require(!lease.isValid && lease.debugRetainedChatCount == 0, "retired receipt lease retained data")
        }

        private static func verifyRebuild() async throws {
            let projection = RootChatProjection()
            let build = projection.begin()
            let gate = Gate()
            defer {
                gate.release()
                projection.invalidate()
            }
            let customList = ChatList.chatListFolder(.init(chatFolderId: 7))
            build.beginList(.chatListMain, revision: projection.revision)
            build.beginList(customList, revision: projection.revision)
            let removed = RootChatInsertionProbe.chat(position(10))
            let retained = RootChatInsertionProbe.chat(position(20), id: 8, user: user("old"), unread: 9)
            build.watchUser(17)
            build.track(removed, raw: projection.revision, peer: projection.revision)
            build.track(retained, raw: projection.revision, peer: projection.revision)
            var installed: [CustomFolder]?
            var replay = [(Int64, ChatPosition)]()
            let task = Task {
                // Simulates a later folder/archive RPC holding earlier hydrated rows.
                await gate.wait()
                guard build.isValid else { return }
                let main = CustomFolder(chats: [removed, retained], type: .main)
                let newFolder = RootChatInsertionProbe.folder()
                replay = build.reconcile([main, newFolder])
                installed = [main, newFolder]
                projection.finish(build)
            }
            try await until({ gate.continuation != nil }, "rebuild did not suspend")
            projection.record(.updateChatPosition(.init(chatId: 7, position: position(0))))
            projection.record(unread(0, id: 8))
            projection.record(.updateChatTitle(.init(chatId: 8, title: "latest-title")))
            projection.record(.updateUser(.init(user: user("latest-peer", bot: true))))
            projection.record(.updateChatPosition(.init(chatId: 8, position: position(80, pinned: true))))
            projection.record(.updateChatPosition(.init(chatId: 9, position: position(90, list: customList))))
            projection.record(.updateChatDraftMessage(.init(chatId: 9, draftMessage: nil, positions: [])))
            projection.record(.updateChatPosition(.init(
                chatId: 9,
                position: position(99, list: customList, pinned: true),
            )))
            gate.release()
            await task.value
            try require(
                installed?[0].chats.map(\.id) == [8] && retained.unreadCount == 0
                && retained.chat.title == "latest-title" && retained.user?.firstName == "latest-peer" && retained
                    .bot != nil
                && retained.position == position(80, pinned: true),
                "rebuild discarded accepted fields/membership",
            )
            try require(
                replay.count == 1 && replay[0].0 == 9 && replay[0].1 == position(99, list: customList, pinned: true),
                "new-folder latest positive replay missing or revoked intent revived",
            )
            try require(projection.debugActiveReadCount == 0, "successful rebuild retained lease")

            let overlap = projection.begin()
            projection.record(.updateChatPosition(.init(chatId: 7, position: position(10))))
            // A newer getChats response may legitimately omit an old accepted ID.
            overlap.beginList(.chatListMain, revision: projection.revision)
            try require(
                overlap.reconcile([CustomFolder(chats: [], type: .main)]).isEmpty,
                "pre-list-read membership overrode fresh list result",
            )
            projection.record(.updateChatLastMessage(.init(chatId: 7, lastMessage: nil, positions: [position(20)])))
            projection.record(.updateChatPosition(.init(chatId: 7, position: position(0))))
            try require(
                overlap.reconcile([CustomFolder(chats: [], type: .main)]).isEmpty,
                "partial removal lost to complete vector",
            )
            projection.record(.updateChatDraftMessage(.init(
                chatId: 7,
                draftMessage: nil,
                positions: [position(30, pinned: true)],
            )))
            let latest = overlap.reconcile([CustomFolder(chats: [], type: .main)])
            try require(
                latest.count == 1 && latest[0].1 == position(30, pinned: true),
                "later full vector failed legitimate re-add",
            )
            projection.finish(overlap)
        }

        private static func verifyInsertionAdmission() async throws {
            let projection = RootChatProjection()
            let insertion = RootChatInsertion()
            let folder = CustomFolder(chats: [], type: .main)
            let lease = projection.begin(chatID: 7)
            let row = RootChatInsertionProbe.chat(position(10), user: user("old"), unread: 9)
            lease.watchUser(17)
            lease.track(row, raw: projection.revision, peer: projection.revision)
            let gate = Gate()
            var finalizations = 0
            defer {
                gate.release()
                insertion.invalidate()
                projection.invalidate()
            }
            insertion.apply(
                source: .init(accountID: UUID(), clientID: 1), chatID: 7, position: position(10), folder: folder,
                accepts: { true }, hydrate: {
                    // The value is hydrated, but the async caller has not admitted it.
                    await gate.wait()
                    return row
                },
                prepare: {
                    // Actual admission seam: hydrate has returned to the helper,
                    // but no row is appended yet. The lease must still be live.
                    projection.record(.updateChatTitle(.init(chatId: 7, title: "late title")))
                    lease.project($0)
                },
                onFinish: {
                    finalizations += 1
                    projection.finish(lease)
                },
            )
            try await until({ gate.continuation != nil }, "insertion did not suspend")
            projection.record(unread(1))
            projection.record(.updateUser(.init(user: user("latest", bot: true))))
            projection.record(.updateChatNotificationSettings(.init(chatId: 7, notificationSettings: mutedSettings())))
            gate.release()
            try await until({ folder.chats.count == 1 }, "insertion admission missing")
            try require(
                row.unreadCount == 1 && row.user?.firstName == "latest" && row.bot != nil && row.chat.title == "late title"
                && row.chat.notificationSettings.muteFor == 60 && row.position == position(10),
                "hydration→admission delta lost",
            )
            try require(
                finalizations == 1 && projection.debugActiveReadCount == 0,
                "insertion lease did not finish exactly once",
            )
            insertion.invalidate()
            try require(finalizations == 1, "completed insertion cleanup repeated")
        }

        private static func verifyInsertionRetirement() async throws {
            let projection = RootChatProjection()
            let insertion = RootChatInsertion()
            let folder = CustomFolder(chats: [], type: .main)
            let source = TdUpdateSource(accountID: UUID(), clientID: 1)
            var gates = [Gate]()
            var leases = [RootChatProjection.Lease]()
            var finishes = 0
            defer {
                for gate in gates {
                    gate.release()
                }
                insertion.invalidate()
                projection.invalidate()
            }
            func apply(_ order: Int64) {
                var current: RootChatProjection.Lease?
                insertion.apply(
                    source: source,
                    chatID: 7,
                    position: position(order),
                    folder: folder,
                    accepts: { true },
                    hydrate: {
                        if let current { projection.finish(current) }
                        let lease = projection.begin(chatID: 7)
                        current = lease
                        leases.append(lease)
                        let row = RootChatInsertionProbe.chat(position(order), unread: 9)
                        lease.track(row, raw: projection.revision, peer: projection.revision)
                        let gate = Gate()
                        gates.append(gate)
                        await gate.wait()
                        return row
                    },
                    prepare: { current?.project($0) },
                    onFinish: {
                        if let current { projection.finish(current) }
                        current = nil
                        finishes += 1
                    },
                )
            }
            apply(10)
            try await until({ gates.count == 1 && gates[0].continuation != nil }, "first lease did not suspend")
            apply(20)
            gates[0].release()
            try await until({ gates.count == 2 && gates[1].continuation != nil }, "coalesced hydration did not restart")
            try require(
                !leases[0].isValid && leases[1].isValid && projection.debugActiveReadCount == 1,
                "coalesced hydration retained old lease or closed current",
            )
            apply(0)
            try require(finishes == 1 && projection.debugActiveReadCount == 0, "removal failed prompt lease cleanup")
            apply(30)
            try await until({ gates.count == 3 && gates[2].continuation != nil }, "re-add blocked by canceled old read")
            gates[1].release()
            for _ in 0..<12 {
                await Task.yield()
            }
            try require(
                leases[2].isValid && projection.debugActiveReadCount == 1 && finishes == 1,
                "late retired completion released new lease",
            )
            projection.record(unread(2))
            gates[2].release()
            try await until({ folder.chats.count == 1 }, "re-add admission missing")
            try require(
                folder.chats[0].position == position(30) && folder.chats[0].unreadCount == 2
                && finishes == 2 && projection.debugActiveReadCount == 0,
                "re-add field/order/terminal contract failed",
            )
        }

        private static func verifyRefreshSupersession() async throws {
            let projection = RootChatProjection()
            let first = projection.beginRefresh(chatID: 7)
            let gate = Gate()
            defer {
                gate.release()
                projection.invalidate()
            }
            let oldRPC = Task {
                defer { projection.finish(first) }
                await gate.wait()
            }
            try await until({ gate.continuation != nil }, "old refresh did not suspend")
            projection.record(unread(1))
            let second = projection.beginRefresh(chatID: 7)
            try require(
                !first.isValid && first.debugRetainedChatCount == 0 && projection.debugActiveReadCount == 1,
                "superseded refresh retained projection until RPC completion",
            )
            for count in 0..<5000 {
                projection.record(unread(count))
            }
            try require(
                first.debugRetainedChatCount == 0 && second.debugRetainedChatCount == 1,
                "retired refresh kept recording feed",
            )
            gate.release()
            await oldRPC.value
            try require(second.isValid && projection.debugActiveReadCount == 1, "old RPC cleanup closed replacement")
            let other = projection.beginRefresh(chatID: 8)
            try require(
                second.isValid && other.isValid && projection.debugActiveReadCount == 2,
                "refresh supersession crossed chat IDs",
            )
            projection.invalidate()
            try require(
                !second.isValid && !other.isValid && projection.debugActiveReadCount == 0,
                "epoch invalidation retained refresh owners",
            )
            let replacement = projection.beginRefresh(chatID: 7)
            projection.finish(second)
            try require(
                replacement.isValid && projection.debugActiveReadCount == 1,
                "old epoch cleanup retired new owner",
            )
        }

        private static func mutedSettings() -> ChatNotificationSettings {
            .init(
                disableMentionNotifications: false,
                disablePinnedMessageNotifications: false,
                muteFor: 60,
                muteStories: false,
                showPreview: true,
                showStoryPoster: true,
                soundId: 0,
                storySoundId: 0,
                useDefaultDisableMentionNotifications: true,
                useDefaultDisablePinnedMessageNotifications: true,
                useDefaultMuteFor: false,
                useDefaultMuteStories: true,
                useDefaultShowPreview: true,
                useDefaultShowStoryPoster: true,
                useDefaultSound: true,
                useDefaultStorySound: true,
            )
        }

        private static func user(_ name: String, bot: Bool = false) -> User {
            let type: UserType = bot
                ? .userTypeBot(.init(
                    activeUserCount: 0, allowsUsersToCreateTopics: false, canBeAddedToAttachmentMenu: false,
                    canBeEdited: false,
                    canConnectToBusiness: false, canJoinGroups: false, canManageBots: false,
                    canReadAllGroupMessages: false,
                    hasMainWebApp: false, hasTopics: false, inlineQueryPlaceholder: "", isGuard: false, isInline: false,
                    needLocation: false, supportsGuestQueries: false,
                ))
                : .userTypeRegular
            return User(
                accentColorId: -1,
                activeStoryState: nil,
                addedToAttachmentMenu: false,
                backgroundCustomEmojiId: 0,
                emojiStatus: nil,
                firstName: name,
                haveAccess: true,
                id: 17,
                isCloseFriend: false,
                isContact: false,
                isMutualContact: false,
                isPremium: false,
                isSupport: false,
                languageCode: "",
                lastName: "",
                paidMessageStarCount: 0,
                phoneNumber: "",
                profileAccentColorId: -1,
                profileBackgroundCustomEmojiId: 0,
                profilePhoto: nil,
                restrictionInfo: nil,
                restrictsNewChats: false,
                status: .userStatusEmpty,
                type: type,
                upgradedGiftColors: nil,
                usernames: nil,
                verificationStatus: nil,
            )
        }

        private static func populatedChat(isOutgoing: Bool = false) -> CustomChat {
            let text = FormattedText(entities: [], text: "old")
            let draft = DraftMessage(
                content: .draftMessageContentText(.init(linkPreviewOptions: nil, text: text)),
                date: 1,
                effectId: 0,
                replyTo: nil,
                suggestedPostInfo: nil,
            )
            let message = Message(
                authorSignature: "", autoDeleteIn: 0, canBeSaved: true, chatId: 7, containsUnreadMention: false,
                containsUnreadPollVotes: false,
                content: .messageText(.init(linkPreview: nil, linkPreviewOptions: nil, text: text)), date: 1,
                editDate: 0,
                effectId: 0, ephemeralMessageId: 0, factCheck: nil, forwardInfo: nil, guestBotCallerId: nil,
                hasTimestampedMedia: false,
                id: 1, importInfo: nil, interactionInfo: nil, isChannelPost: false, isFromOffline: false,
                isOutgoing: isOutgoing,
                isPaidGramSuggestedPost: false, isPaidStarSuggestedPost: false, isPinned: false, mediaAlbumId: 0,
                paidMessageStarCount: 0,
                receiverId: nil, replyMarkup: nil, replyTo: nil, restrictionInfo: nil, schedulingState: nil,
                selfDestructIn: 0,
                selfDestructType: nil, senderBoostCount: 0, senderBusinessBotUserId: 0,
                senderId: .messageSenderUser(.init(userId: 17)),
                senderTag: "", sendingState: nil, suggestedPostInfo: nil, summaryLanguageCode: "", topicId: nil,
                unreadReactions: [], viaBotUserId: 0,
            )
            let file = File(
                expectedSize: 0,
                id: 1,
                local: .init(
                    canBeDeleted: false,
                    canBeDownloaded: false,
                    downloadOffset: 0,
                    downloadedPrefixSize: 0,
                    downloadedSize: 0,
                    isDownloadingActive: false,
                    isDownloadingCompleted: false,
                    path: "",
                ),
                remote: .init(
                    id: "",
                    isUploadingActive: false,
                    isUploadingCompleted: false,
                    uniqueId: "",
                    uploadedSize: 0,
                ),
                size: 0,
            )
            let photo = ChatPhotoInfo(
                big: file,
                hasAnimation: false,
                isPersonal: false,
                minithumbnail: nil,
                small: file,
            )
            return RootChatInsertionProbe.chat(
                position(50),
                user: user("old"),
                last: message,
                draft: draft,
                photo: photo,
            )
        }
    }
#endif
