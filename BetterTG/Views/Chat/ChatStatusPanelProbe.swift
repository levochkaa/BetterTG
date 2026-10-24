// ChatStatusPanelProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks the status panel offline (no TDLib): `ChatVM.statusPanel(for:)` and `subscriberPanelAction`'s rules
    /// for every member status of channels and groups, the restriction texts, and the panel's geometry for each style.
    /// Launch with `-ui-probe-status-panel`; the result goes to the log and to Documents/status-panel-probe.txt.
    @MainActor enum ChatStatusPanelProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-status-panel") else { return }
            let result: String
            do {
                try verifyActions()
                try verifyPanels()
                try verifyRestrictionTexts()
                try verifyGeometry()
                result = "Status panel probe passed: channel-member-mute/unmute/left-join/joining-mute/"
                    + "creator-left-join/admin-mute/banned-none/direct-messages-none=true; "
                    + "group-left-join-group/request-apply/forum-join/member-none/restricted-member-none/"
                    + "restricted-left-join/broadcast-mute=true; "
                    + "panel-writable-none/banned-delete/restricted-text/channel-subscriber/basic-left-delete/"
                    + "basic-creator-left-delete/basic-read-only-restricted/user-none=true; "
                    + "restricted-default/personal/timed=true; "
                    + "geometry-mute-centred/search-right/join-spans/help-left/unblock-centred/"
                    + "restricted-text/delete=true"
            } catch {
                result = "Status panel probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("status-panel-probe.txt"),
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

        private static func verifyPanels() throws {
            typealias Panel = ChatVM.StatusPanel
            let member = ChatMemberStatus.chatMemberStatusMember(.init(memberUntilDate: 0))
            let banned = ChatMemberStatus.chatMemberStatusBanned(.init(bannedUntilDate: 0))
            let defaultText = L10n.telegram("Conversation.DefaultRestrictedText")
            let personalText = L10n.telegram("Conversation.RestrictedText")
            let cases: [(String, CustomChat.CustomChatType, Bool, Panel?)] = [
                ("writable group", .supergroup(supergroup(member, isChannel: false)), true, nil),
                ("banned channel", .supergroup(supergroup(banned)), false, .deleteChat),
                ("banned writable", .supergroup(supergroup(banned, isChannel: false)), true, .deleteChat),
                (
                    "restricted group",
                    .supergroup(supergroup(restricted(isMember: true), isChannel: false)),
                    false,
                    .restricted(personalText),
                ),
                ("read-only group", .supergroup(supergroup(member, isChannel: false)), false, .restricted(defaultText)),
                ("channel", .supergroup(supergroup(member)), false, .subscriber(.mute)),
                ("left basic group", .group(basicGroup(.chatMemberStatusLeft)), false, .deleteChat),
                ("removed basic group", .group(basicGroup(banned)), false, .deleteChat),
                (
                    "creator left basic group",
                    .group(basicGroup(.chatMemberStatusCreator(.init(isAnonymous: false, isMember: false)))),
                    false,
                    .deleteChat,
                ),
                ("read-only basic group", .group(basicGroup(member)), false, .restricted(defaultText)),
                ("writable basic group", .group(basicGroup(member)), true, nil),
            ]
            for (name, type, canWrite, expected) in cases {
                let panel = ChatVM.statusPanel(for: type, canWrite: canWrite, isJoining: false, isMuted: false)
                try require(panel == expected, "\(name): \(String(describing: panel))")
            }
        }

        private static func verifyRestrictionTexts() throws {
            let member = ChatMemberStatus.chatMemberStatusMember(.init(memberUntilDate: 0))
            try require(
                ChatVM.restrictionText(status: member) == L10n.telegram("Conversation.DefaultRestrictedText"),
                "default text",
            )
            try require(
                ChatVM.restrictionText(status: restricted(isMember: true)) == L10n
                    .telegram("Conversation.RestrictedText"),
                "personal text",
            )
            let until = 1_900_000_000
            let timed = ChatVM.restrictionText(status: restricted(isMember: true, until: until))
            let expected = L10n.telegram(
                "Conversation.RestrictedTextTimed",
                ChatVM.fullDateString(Date(timeIntervalSince1970: TimeInterval(until))),
            )
            try require(timed == expected && timed.contains("2030"), "timed text \(timed)")
        }

        private static func verifyGeometry() throws {
            let panel = ChatStatusPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 84))
            let regular = UIFont.systemFont(ofSize: 17)
            func width(_ title: String) -> CGFloat {
                ceil((title as NSString).size(withAttributes: [.font: regular]).width)
            }

            panel.update(
                content: .init(title: "Mute", style: .action(spansWidth: false), showsSearch: true),
                animated: false,
            )
            var geometry = panel.probeGeometry
            let muteFrame = geometry.action ?? .zero
            try require(
                abs(muteFrame.width - (width("Mute") + 24)) <= 1 && abs(muteFrame.midX - 201) <= 1
                    && muteFrame.minY == 0 && muteFrame.height == 50,
                "mute \(muteFrame)",
            )
            try require(
                geometry.search == CGRect(x: 358, y: 0, width: 44, height: 50) && geometry.help == nil,
                "search \(String(describing: geometry.search))",
            )

            panel.update(
                content: .init(title: "Join", style: .action(spansWidth: true), showsSearch: true),
                animated: false,
            )
            geometry = panel.probeGeometry
            try require(
                geometry.action == CGRect(x: 44, y: 0, width: 314, height: 50),
                "join \(String(describing: geometry.action))",
            )

            panel.update(
                content: .init(title: "Unmute", style: .action(spansWidth: false), showsSearch: true, showsHelp: true),
                animated: false,
            )
            geometry = panel.probeGeometry
            try require(
                geometry.help == CGRect(x: 0, y: 0, width: 44, height: 50)
                    && abs((geometry.action?.midX ?? 0) - 201) <= 1,
                "help \(String(describing: geometry.help))",
            )

            panel.update(content: .init(title: "Unblock", style: .button), animated: false)
            geometry = panel.probeGeometry
            try require(
                abs((geometry.action?.width ?? 0) - (width("Unblock") + 24)) <= 1 && geometry.search == nil,
                "unblock \(String(describing: geometry.action))",
            )

            let text = L10n.telegram("Conversation.RestrictedTextTimed", "January 1, 2030 at 10:00")
            panel.update(content: .init(title: text, style: .text), animated: false)
            geometry = panel.probeGeometry
            try require(
                geometry.action == nil && geometry.text == CGRect(x: 16, y: 0, width: 370, height: 50),
                "restricted \(String(describing: geometry.text))",
            )

            panel.update(content: .init(title: "Delete and Exit", style: .destructive), animated: false)
            geometry = panel.probeGeometry
            try require(
                abs((geometry.action?.width ?? 0) - (width("Delete and Exit") + 24)) <= 1 && geometry.text == nil,
                "delete \(String(describing: geometry.action))",
            )
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

        private static func basicGroup(_ status: ChatMemberStatus) -> BasicGroup {
            .init(id: 7, memberCount: 2, status: status, isActive: true, upgradedToSupergroupId: 0)
        }

        private static func restricted(isMember: Bool, until: Int = 0) -> ChatMemberStatus {
            .chatMemberStatusRestricted(.init(
                isMember: isMember,
                restrictedUntilDate: until,
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
