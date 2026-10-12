// ProbeFixtures.swift

#if DEBUG
    import Foundation
    import TDLibKit

    /// Chat-list fixtures shared by DEBUG probes. Never used by production paths.
    @MainActor enum ProbeFixtures {
        struct AccountNotReady: Error, CustomStringConvertible {
            var description: String { "account did not become ready" }
        }

        /// TDLibKit 2 creates the active client asynchronously after launch. Probes that borrow the active client
        /// object or its VOD ranges wait for it instead of tripping the bootstrap precondition.
        static func waitForActiveAccount(timeout: Duration = .seconds(30)) async throws {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while !TDLib.shared.isActiveAccountReady, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard TDLib.shared.isActiveAccountReady else { throw AccountNotReady() }
        }

        static func folder() -> CustomFolder {
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

        static func chat(
            _ position: ChatPosition, title: String = "probe", id: Int64 = 7, user: User? = nil,
            last: Message? = nil, draft: DraftMessage? = nil, photo: ChatPhotoInfo? = nil, unread: Int = 0,
            viewAsTopics: Bool = false,
        ) -> CustomChat {
            let raw = Chat(
                id: id,
                type: user
                .map { .chatTypePrivate(.init(userId: $0.id)) } ?? .chatTypeBasicGroup(.init(basicGroupId: 7)),
                title: title,
                photo: photo,
                accentColorId: -1,
                backgroundCustomEmojiId: 0,
                upgradedGiftColors: nil,
                profileAccentColorId: -1,
                profileBackgroundCustomEmojiId: 0,
                permissions: .init(
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
                    canChangeInfo: false,
                    canInviteUsers: false,
                    canPinMessages: false,
                    canCreateTopics: false,
                ),
                lastMessage: last,
                positions: [position],
                chatLists: [position.list],
                messageSenderId: nil,
                blockList: nil,
                hasProtectedContent: false,
                isTranslatable: false,
                isMarkedAsUnread: false,
                viewAsTopics: viewAsTopics,
                hasScheduledMessages: false,
                hasWelcomeMessages: false,
                canBeDeletedOnlyForSelf: false,
                canBeDeletedForAllUsers: false,
                canBeReported: false,
                defaultDisableNotification: false,
                unreadCount: unread,
                lastReadInboxMessageId: 0,
                lastReadOutboxMessageId: 0,
                unreadMentionCount: 0,
                unreadReactionCount: 0,
                unreadPollVoteCount: 0,
                notificationSettings: .init(
                    disableMentionNotifications: false, disablePinnedMessageNotifications: false, muteFor: 0,
                    muteStories: false, showPreview: true, showStoryPoster: true, soundId: 0, storySoundId: 0,
                    useDefaultDisableMentionNotifications: true, useDefaultDisablePinnedMessageNotifications: true,
                    useDefaultMuteFor: true, useDefaultMuteStories: true, useDefaultShowPreview: true,
                    useDefaultShowStoryPoster: true, useDefaultSound: true, useDefaultStorySound: true,
                ),
                availableReactions: .chatAvailableReactionsAll(.init(maxReactionCount: 1)),
                messageAutoDeleteTime: 0,
                emojiStatus: nil,
                background: nil,
                theme: nil,
                actionBar: nil,
                businessBotManageBar: nil,
                videoChat: .init(
                    groupCallId: 0,
                    hasParticipants: false,
                    defaultParticipantId: nil,
                ),
                pendingJoinRequests: nil,
                replyMarkupMessageId: 0,
                draftMessage: draft,
                clientData: "",
            )
            return CustomChat(
                chat: raw, position: position, unreadCount: unread,
                type: user.map { user in
                    if case .userTypeBot = user.type { return .bot(user) }
                    return .user(user)
                } ?? .group(.init(
                    id: 7,
                    memberCount: 2,
                    status: .chatMemberStatusMember(.init(memberUntilDate: 0)),
                    isActive: true,
                    upgradedToSupergroupId: 0,
                )), lastMessage: last, draftMessage: draft,
            )
        }
    }
#endif
