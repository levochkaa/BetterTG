// RootChatInsertionProbe.swift

#if DEBUG
    import Foundation
    import TDLibKitDynamic

    @MainActor enum RootChatInsertionProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Fixture {
            let insertion = RootChatInsertion()
            let authority = RootListAuthority()
            var source = TdUpdateSource(accountID: UUID(), clientID: 1)
            var folders = [CustomFolder(chats: [], type: .main)]
            var reads = [Int: CheckedContinuation<CustomChat?, Never>]()
            var readCount = 0

            func apply(_ position: ChatPosition, to folder: CustomFolder? = nil, chatID: Int64 = 7) {
                let folder = folder ?? folders[0]
                let source = source
                guard let ticket = authority.capture(ownerAccountID: source.accountID, activeSource: source)
                    else { return }
                insertion.apply(
                    source: source, chatID: chatID, position: position, folder: folder,
                    accepts: { [weak self, weak folder] in
                        guard let self, let folder else { return false }
                        return authority.accepts(
                            ticket,
                            ownerAccountID: self.source.accountID,
                            activeSource: self.source,
                        )
                            && folders.contains(where: { $0 === folder })
                    },
                    hydrate: { [weak self] in
                        guard let self else { return nil }
                        readCount += 1
                        let request = readCount
                        return await withCheckedContinuation { self.reads[request] = $0 }
                    },
                )
            }

            func complete(_ request: Int, _ value: CustomChat?) throws {
                guard let continuation = reads.removeValue(forKey: request) else {
                    throw Failure(description: "missing suspended read \(request)")
                }
                continuation.resume(returning: value)
            }

            func finish() {
                insertion.invalidate()
                let suspended = reads.values
                reads.removeAll()
                for continuation in suspended {
                    continuation.resume(returning: nil)
                }
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-root-chat-insertion") else { return }
            Task {
                let result: String
                do {
                    try await verify()
                    result = "Root chat insertion probe passed: actual-helper/folders=true; remove-late-reply/readd/late-error=true; "
                        + "coalesced-position/draft-last-membership/pinned=true; semantic-lists/client-epoch/exact-folder=fenced; "
                        + "canceled-owner/duplicate/nil/rejected-admission=true; RootVM/RPC=source-reviewed; server-calls=0"
                } catch {
                    result = "Root chat insertion probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("root-chat-insertion-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ value: Bool, _ description: String) throws {
            if !value { throw Failure(description: description) }
        }

        private static func settle() async {
            for _ in 0..<12 {
                await Task.yield()
            }
        }

        private static func until(_ condition: () -> Bool, _ description: String) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                await Task.yield()
            }
            throw Failure(description: description)
        }

        private static func position(
            _ order: Int64,
            list: ChatList = .chatListMain,
            pinned: Bool = false,
        ) -> ChatPosition {
            ChatPosition(isPinned: pinned, list: list, order: .init(order), source: nil)
        }

        private static func verify() async throws {
            let f = Fixture()
            defer { f.finish() }
            let main = f.folders[0]
            f.apply(position(9))
            f.apply(position(0))
            await settle()
            try require(f.readCount == 0, "removed-before-dispatch intent started hydration")
            f.apply(position(10))
            try await until({ f.readCount == 1 }, "initial hydration missing")
            f.apply(position(0))
            try f.complete(1, chat(position(10)))
            await settle()
            try require(main.chats.isEmpty && f.readCount == 1, "remove resurrected late insertion")

            f.apply(position(20))
            try await until({ f.readCount == 2 }, "re-add hydration missing")
            // These are the complete-vector policies used by last-message/draft.
            f.apply(RootChatInsertion.position(in: [position(30)], for: .chatListMain))
            f.apply(RootChatInsertion.position(in: [position(40, pinned: true)], for: .chatListMain))
            try require(f.readCount == 2, "position updates started parallel hydration")
            try f.complete(2, chat(position(20)))
            try await until({ f.readCount == 3 }, "updated intent did not rehydrate")
            try require(main.chats.isEmpty, "stale snapshot became visible")
            let latest = chat(position(999), title: "latest-hydration")
            try f.complete(3, latest)
            try await until({ main.chats.count == 1 }, "current insertion missing")
            try require(
                main.chats[0] === latest && latest.position == position(40, pinned: true),
                "new order/pin overwritten",
            )
            f.apply(position(50))
            try require(
                main.chats.count == 1 && latest.position == position(50) && f.readCount == 3,
                "existing row regressed",
            )

            f.apply(RootChatInsertion.position(in: [], for: .chatListMain))
            try require(main.chats.isEmpty, "omitted list retained row")
            f.apply(position(60))
            try await until({ f.readCount == 4 }, "second pending read missing")
            f.apply(RootChatInsertion.position(in: [position(90, list: .chatListArchive)], for: .chatListMain))
            f.apply(position(70, pinned: true))
            try await until({ f.readCount == 5 }, "re-add waited for canceled old RPC")
            try f.complete(4, nil)
            await settle()
            try f.complete(5, chat(position(1)))
            try await until({ main.chats.count == 1 }, "late old error released new owner")
            try require(main.chats[0].position == position(70, pinned: true), "re-add position incorrect")

            f.apply(position(0))
            f.apply(position(80))
            try await until({ f.readCount == 6 }, "epoch read missing")
            f.source = TdUpdateSource(accountID: f.source.accountID, clientID: 2)
            f.authority.invalidate()
            f.insertion.invalidate()
            f.apply(position(90))
            try await until({ f.readCount == 7 }, "replacement client read missing")
            try f.complete(6, chat(position(80)))
            await settle()
            try require(main.chats.isEmpty, "old client published")
            try f.complete(7, chat(position(90)))
            try await until({ main.chats.count == 1 }, "replacement client insertion missing")

            f.apply(position(0))
            f.apply(position(100))
            try await until({ f.readCount == 8 }, "old folder read missing")
            let replacement = CustomFolder(chats: [], type: .main)
            f.folders = [replacement]
            f.apply(position(110))
            try await until({ f.readCount == 9 }, "replacement folder read missing")
            try f.complete(8, chat(position(100)))
            await settle()
            try require(main.chats.isEmpty && replacement.chats.isEmpty, "retired folder received insertion")
            try f.complete(9, chat(position(110)))
            try await until({ replacement.chats.count == 1 }, "replacement folder insertion missing")

            let archive = CustomFolder(chats: [], type: .archive)
            let custom = folder()
            f.folders += [archive, custom]
            f.apply(position(120, list: .chatListArchive), to: archive)
            f.apply(position(130, list: custom.chatList, pinned: true), to: custom)
            try await until({ f.readCount == 11 }, "semantic list reads missing")
            // Map completion by request order without relying on Task scheduling.
            try f.complete(10, chat(position(1)))
            try f.complete(11, chat(position(1)))
            try await until({ archive.chats.count == 1 && custom.chats.count == 1 }, "semantic list collision")
            try require(
                archive.chats[0].position == position(120, list: .chatListArchive)
                && custom.chats[0].position == position(130, list: custom.chatList, pinned: true),
                "semantic positions crossed",
            )
            f.apply(position(0, list: .chatListArchive), to: archive)
            try require(
                archive.chats.isEmpty && custom.chats.count == 1 && replacement.chats.count == 1,
                "removal crossed lists",
            )

            f.apply(position(140, list: .chatListArchive), to: archive)
            try await until({ f.readCount == 12 }, "nil read missing")
            try f.complete(12, nil)
            await settle()
            try require(archive.chats.isEmpty && f.readCount == 12, "nil result retried automatically")
            f.apply(position(150, list: .chatListArchive), to: archive)
            try await until({ f.readCount == 13 }, "failed intent blocked legitimate retry")
            f.apply(position(0, list: .chatListArchive), to: archive)
            try f.complete(13, chat(position(150)))
            await settle()
            try require(archive.chats.isEmpty, "canceled owner appended")
            f.apply(position(160, list: .chatListArchive), to: replacement)
            f.apply(position(160), to: main)
            await settle()
            try require(f.readCount == 13, "wrong list/retired folder admitted")

            // The root epoch guard also rejects a callback without eager cancel.
            f.apply(position(170, list: .chatListArchive), to: archive)
            try await until({ f.readCount == 14 }, "guard-only read missing")
            f.authority.invalidate()
            try f.complete(14, chat(position(170)))
            await settle()
            try require(archive.chats.isEmpty, "invalid root ticket admitted")

            f.apply(position(180, list: .chatListArchive), to: archive)
            try await until({ f.readCount == 15 }, "old account read missing")
            f.source = TdUpdateSource(accountID: UUID(), clientID: f.source.clientID)
            f.authority.invalidate()
            f.insertion.invalidate()
            f.apply(position(190, list: .chatListArchive), to: archive)
            try await until({ f.readCount == 16 }, "new account read missing")
            try f.complete(15, chat(position(180)))
            await settle()
            try require(archive.chats.isEmpty, "numeric-client collision crossed accounts")
            try f.complete(16, chat(position(190)))
            try await until({ archive.chats.count == 1 }, "new account insertion missing")
            try require(
                archive.chats[0].position == position(190, list: .chatListArchive),
                "new account order overwritten",
            )
        }

        private static func folder() -> CustomFolder {
            let name = ChatFolderName(animateCustomEmoji: false, text: .init(entities: [], text: "probe"))
            let icon = ChatFolderIcon(name: "All")
            let info = ChatFolderInfo(
                colorId: -1,
                hasMyInviteLinks: false,
                icon: icon,
                id: 7,
                isShareable: false,
                name: name,
            )
            let folder = ChatFolder(
                colorId: -1, excludeArchived: false, excludeMuted: false, excludeRead: false, excludedChatIds: [],
                icon: icon, includeBots: false, includeChannels: false, includeContacts: false, includeGroups: true,
                includeNonContacts: false, includedChatIds: [], isShareable: false, name: name, pinnedChatIds: [],
            )
            return CustomFolder(chats: [], type: .folder(info, folder))
        }

        private static func chat(_ position: ChatPosition, title: String = "probe") -> CustomChat {
            let raw = Chat(
                accentColorId: -1, actionBar: nil,
                availableReactions: .chatAvailableReactionsAll(.init(maxReactionCount: 1)),
                background: nil, backgroundCustomEmojiId: 0, blockList: nil, businessBotManageBar: nil,
                canBeDeletedForAllUsers: false, canBeDeletedOnlyForSelf: false, canBeReported: false,
                chatLists: [position.list], clientData: "", defaultDisableNotification: false, draftMessage: nil,
                emojiStatus: nil, hasProtectedContent: false, hasScheduledMessages: false, id: 7,
                isMarkedAsUnread: false, isTranslatable: false, lastMessage: nil, lastReadInboxMessageId: 0,
                lastReadOutboxMessageId: 0, messageAutoDeleteTime: 0, messageSenderId: nil,
                notificationSettings: .init(
                    disableMentionNotifications: false, disablePinnedMessageNotifications: false, muteFor: 0,
                    muteStories: false, showPreview: true, showStoryPoster: true, soundId: 0, storySoundId: 0,
                    useDefaultDisableMentionNotifications: true, useDefaultDisablePinnedMessageNotifications: true,
                    useDefaultMuteFor: true, useDefaultMuteStories: true, useDefaultShowPreview: true,
                    useDefaultShowStoryPoster: true, useDefaultSound: true, useDefaultStorySound: true,
                ),
                pendingJoinRequests: nil, permissions: .init(
                    canAddLinkPreviews: false, canChangeInfo: false, canCreateTopics: false, canEditTag: false,
                    canInviteUsers: false, canPinMessages: false, canReactToMessages: false, canSendAudios: false,
                    canSendBasicMessages: false, canSendDocuments: false, canSendOtherMessages: false,
                    canSendPhotos: false, canSendPolls: false, canSendVideoNotes: false, canSendVideos: false,
                    canSendVoiceNotes: false,
                ),
                photo: nil, positions: [position], profileAccentColorId: -1, profileBackgroundCustomEmojiId: 0,
                replyMarkupMessageId: 0, theme: nil, title: title, type: .chatTypeBasicGroup(.init(basicGroupId: 7)),
                unreadCount: 0, unreadMentionCount: 0, unreadPollVoteCount: 0, unreadReactionCount: 0,
                upgradedGiftColors: nil, videoChat: .init(
                    defaultParticipantId: nil,
                    groupCallId: 0,
                    hasParticipants: false,
                ), viewAsTopics: false,
            )
            return CustomChat(
                chat: raw, position: position, unreadCount: 0,
                type: .group(.init(
                    id: 7,
                    isActive: true,
                    memberCount: 2,
                    status: .chatMemberStatusMember(.init(memberUntilDate: 0)),
                    upgradedToSupergroupId: 0,
                )),
            )
        }
    }
#endif
