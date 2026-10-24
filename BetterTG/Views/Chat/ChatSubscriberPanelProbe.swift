// ChatSubscriberPanelProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks the subscriber panel offline (no TDLib): `ChatVM.subscriberPanelAction`'s rules for every member status
    /// of channels and groups, and the panel's GlassControlPanelComponent geometry.
    /// Launch with `-ui-probe-subscriber-panel`; the result goes to the log and to
    /// Documents/subscriber-panel-probe.txt.
    @MainActor enum ChatSubscriberPanelProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-subscriber-panel") else { return }
            let result: String
            do {
                try verifyActions()
                try verifyGeometry()
                result = "Subscriber panel probe passed: channel-member-mute/unmute/left-join/joining-mute/"
                    + "creator-left-join/admin-mute/banned-none/direct-messages-none=true; "
                    + "group-left-join-group/request-apply/forum-join/member-none/restricted-member-none/"
                    + "restricted-left-join/broadcast-mute=true; "
                    + "geometry-mute-165-centred/search-right/join-166-accent/long-title/help-left=true"
            } catch {
                result = "Subscriber panel probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("subscriber-panel-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verifyActions() throws {
            typealias Action = ChatVM.SubscriberPanelAction
            let member = ChatMemberStatus.chatMemberStatusMember(.init(memberUntilDate: 0))
            let left = ChatMemberStatus.chatMemberStatusLeft
            let cases: [(String, Supergroup, Bool, Bool, Action?)] = [
                ("channel member", supergroup(member), false, false, .mute),
                ("muted channel member", supergroup(member), false, true, .unmute),
                ("left channel", supergroup(left), false, false, .join),
                ("joining channel", supergroup(left), true, true, .unmute),
                (
                    "creator who left",
                    supergroup(.chatMemberStatusCreator(.init(isAnonymous: false, isMember: false))),
                    false,
                    false,
                    .join,
                ),
                ("admin", supergroup(administrator()), false, false, .mute),
                ("banned", supergroup(.chatMemberStatusBanned(.init(bannedUntilDate: 0))), false, false, nil),
                ("direct messages", supergroup(left, isChannel: false, directMessages: true), false, false, nil),
                ("left group", supergroup(left, isChannel: false), false, false, .joinGroup),
                ("join request", supergroup(left, isChannel: false, joinByRequest: true), false, false, .applyToJoin),
                ("left forum", supergroup(left, isChannel: false, forum: true), false, false, .join),
                ("group member", supergroup(member, isChannel: false), false, false, nil),
                ("restricted member", supergroup(restricted(isMember: true), isChannel: false), false, false, nil),
                (
                    "restricted non-member",
                    supergroup(restricted(isMember: false), isChannel: false),
                    false,
                    false,
                    .joinGroup,
                ),
                ("broadcast group", supergroup(member, isChannel: false, broadcast: true), false, true, .unmute),
            ]
            for (name, group, isJoining, isMuted, expected) in cases {
                let action = ChatVM.subscriberPanelAction(for: group, isJoining: isJoining, isMuted: isMuted)
                try require(action == expected, "\(name): \(String(describing: action))")
            }
        }

        private static func verifyGeometry() throws {
            let panel = ChatSubscriberPanelView(frame: CGRect(x: 0, y: 0, width: 386, height: 40))
            panel.update(content: .init(title: "Mute", isAccent: false, showsHelp: false), animated: false)
            panel.layoutIfNeeded()
            var geometry = panel.probeGeometry
            try require(geometry.center == CGRect(x: 110, y: 0, width: 165, height: 40), "mute \(geometry.center)")
            try require(geometry.search == CGRect(x: 346, y: 0, width: 40, height: 40), "search \(geometry.search)")
            try require(geometry.help == nil && geometry.accentAlpha == 0, "mute extras")

            panel.update(content: .init(title: "Join", isAccent: true, showsHelp: false), animated: false)
            panel.layoutIfNeeded()
            geometry = panel.probeGeometry
            try require(geometry.center.width == 166 && geometry.accentAlpha == 1, "join \(geometry.center)")

            let long = "Apply to Join Group"
            panel.update(content: .init(title: long, isAccent: true, showsHelp: false), animated: false)
            panel.layoutIfNeeded()
            geometry = panel.probeGeometry
            let titleWidth = ceil((long as NSString)
.size(withAttributes: [
    .font: UIFont.systemFont(ofSize: 17, weight: .medium),
])
.width)
            try require(
                abs(geometry.center.width - min(290, titleWidth + 38)) <= 1 && geometry.title == long,
                "long title \(geometry.center) text \(titleWidth)",
            )

            panel.update(content: .init(title: "Unmute", isAccent: false, showsHelp: true), animated: false)
            panel.layoutIfNeeded()
            geometry = panel.probeGeometry
            try require(
                geometry.help == CGRect(x: 0, y: 0, width: 40, height: 40),
                "help \(String(describing: geometry.help))",
            )
            try require(geometry.center.minX == 110, "help centre \(geometry.center)")
        }

        private static func supergroup(
            _ status: ChatMemberStatus,
            isChannel: Bool = true,
            broadcast: Bool = false,
            forum: Bool = false,
            joinByRequest: Bool = false,
            directMessages: Bool = false,
        ) -> Supergroup {
            .init(
                id: 1,
                usernames: nil,
                date: 0,
                status: status,
                memberCount: 0,
                boostLevel: 0,
                hasAutomaticTranslation: false,
                hasLinkedChat: false,
                hasLocation: false,
                signMessages: false,
                showMessageSender: false,
                joinToSendMessages: false,
                joinByRequest: joinByRequest,
                isSlowModeEnabled: false,
                isChannel: isChannel,
                isBroadcastGroup: broadcast,
                isForum: forum,
                isDirectMessagesGroup: directMessages,
                isAdministeredDirectMessagesGroup: false,
                verificationStatus: nil,
                hasDirectMessagesGroup: false,
                hasForumTabs: false,
                restrictionInfo: nil,
                paidMessageStarCount: 0,
                activeStoryState: nil,
            )
        }

        private static func restricted(isMember: Bool) -> ChatMemberStatus {
            .chatMemberStatusRestricted(.init(
                isMember: isMember,
                restrictedUntilDate: 0,
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
            ))
        }

        private static func administrator() -> ChatMemberStatus {
            .chatMemberStatusAdministrator(.init(canBeEdited: false, rights: .init(
                canManageChat: false,
                canChangeInfo: false,
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
