// ChatActionBarProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks the action bar offline (no TDLib): `ChatVM.actionBarContent(_:user:)` for every TDLib action bar and
    /// the kind of chat, the button titles, and ChatActionBarView's classic layout.
    /// Launch with `-ui-probe-action-bar`; the result goes to the log and to Documents/action-bar-probe.txt.
    /// `-ui-probe-action-bar-fixture KIND` (report-spam, report-add-block, add-contact, share-phone, invite-members,
    /// join-request) gives every chat that action bar instead of TDLib's, and its close button sends nothing.
    @MainActor enum ChatActionBarProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static let fixture: TDNativeChatActionBar? = {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-ui-probe-action-bar-fixture"), index + 1 < arguments.count
            else { return nil }
            return switch arguments[index + 1] {
            case "report-spam": .chatActionBarReportSpam(.init(canUnarchive: false))
            case "report-add-block": .chatActionBarReportAddBlock(.init(canUnarchive: false, accountInfo: nil))
            case "add-contact": .chatActionBarAddContact
            case "share-phone": .chatActionBarSharePhoneNumber
            case "invite-members": .chatActionBarInviteMembers
            case "join-request": .chatActionBarJoinRequest(.init(
                title: "Probe Group",
                isChannel: false,
                requestDate: Int(Date().timeIntervalSince1970) - 3600,
            ))
            default: nil
            }
        }()

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-action-bar") else { return }
            let result: String
            do {
                try verifyContent()
                try verifyTitles()
                try verifyLayout()
                result = "Action bar probe passed: report-spam-user-block/deleted-report/group-leave/archived-unarchive="
                    + "true; invite-members/report-add-block/archived-block-unarchive/add-contact-name/no-phone-long/"
                    + "share-phone/join-request=true; titles=true; one-button-338/two-buttons-inside/close-right=true"
            } catch {
                result = "Action bar probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("action-bar-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verifyContent() throws {
            typealias Content = ChatVM.ActionBarContent
            let alice = user(phone: "15550000000", deleted: false)
            let noPhone = user(phone: "", deleted: false)
            let deleted = user(phone: "", deleted: true)
            let spam = TDNativeChatActionBar.chatActionBarReportSpam(.init(canUnarchive: false))
            let archivedSpam = TDNativeChatActionBar.chatActionBarReportSpam(.init(canUnarchive: true))
            let addBlock = TDNativeChatActionBar.chatActionBarReportAddBlock(.init(
                canUnarchive: false,
                accountInfo: nil,
            ))
            let archivedAddBlock = TDNativeChatActionBar.chatActionBarReportAddBlock(.init(
                canUnarchive: true,
                accountInfo: nil,
            ))
            let request = TDNativeChatActionBar.chatActionBarJoinRequest(.init(
                title: "Group",
                isChannel: true,
                requestDate: 5,
            ))
            let cases: [(String, TDNativeChatActionBar, User?, Content?)] = [
                ("user spam", spam, alice, .buttons([.block])),
                ("deleted spam", spam, deleted, .buttons([.reportUserSpam])),
                ("group spam", spam, nil, .buttons([.reportSpam])),
                ("archived group", archivedSpam, nil, .buttons([.reportUserSpam, .unarchive])),
                ("archived user", archivedSpam, alice, .buttons([.block, .unarchive])),
                ("invite members", .chatActionBarInviteMembers, nil, .buttons([.addMembers])),
                ("add block", addBlock, alice, .buttons([.block, .addContact(name: nil, long: false)])),
                ("archived add block", archivedAddBlock, deleted, .buttons([.reportUserSpam, .unarchive])),
                (
                    "add contact",
                    .chatActionBarAddContact,
                    alice,
                    .buttons([.addContact(name: alice.compactDisplayTitle, long: true)]),
                ),
                (
                    "add contact no phone",
                    .chatActionBarAddContact,
                    noPhone,
                    .buttons([.addContact(name: nil, long: true)]),
                ),
                ("share phone", .chatActionBarSharePhoneNumber, alice, .buttons([.shareMyPhoneNumber])),
                ("join request", request, alice, .joinRequest(title: "Group", isChannel: true, date: 5)),
            ]
            for (name, bar, user, expected) in cases {
                let content = ChatVM.actionBarContent(bar, user: user)
                try require(content == expected, "\(name): \(String(describing: content))")
            }
        }

        private static func verifyTitles() throws {
            try require(
                ChatVM.ActionBarButton.addContact(name: "Alice", long: true).title
                    == L10n.telegram("Conversation.AddNameToContacts", "Alice"),
                "add name title",
            )
            try require(
                ChatVM.ActionBarButton.reportSpam.title == L10n.telegram("Conversation.ReportSpamAndLeave")
                    && ChatVM.ActionBarButton.block.isDestructive && !ChatVM.ActionBarButton.unarchive.isDestructive,
                "report titles",
            )
        }

        private static func verifyLayout() throws {
            let bar = ChatActionBarView(frame: CGRect(x: 0, y: 0, width: 402, height: 40))
            bar.update(content: .buttons([.addContact(name: "Alice", long: true)]))
            bar.layoutIfNeeded()
            let single = bar.probeButtonFrames
            try require(single == [CGRect(x: 32, y: 0, width: 338, height: 40)], "one button \(single)")
            let close = bar.probeCloseFrame
            try require(abs(close.maxX - (402 - 14)) <= 0.5 && abs(close.midY - 20) <= 1, "close \(close)")

            bar.update(content: .buttons([.block, .addContact(name: nil, long: false)]))
            bar.layoutIfNeeded()
            let pair = bar.probeButtonFrames
            try require(
                pair.count == 2 && pair[0].minX >= 0 && pair[1].maxX <= 402 - 20 + 16 && pair[0].maxX <= pair[1].minX,
                "two buttons \(pair)",
            )
        }

        private static func user(phone: String, deleted: Bool) -> User {
            User(
                accentColorId: -1, activeStoryState: nil, addedToAttachmentMenu: false, backgroundCustomEmojiId: 0,
                emojiStatus: nil, firstName: "Alice", haveAccess: true, id: 7, isCloseFriend: false,
                isContact: false, isMutualContact: false, isPremium: false, isSupport: false, languageCode: "",
                lastName: "Probe", paidMessageStarCount: 0, phoneNumber: phone, profileAccentColorId: -1,
                profileBackgroundCustomEmojiId: 0, profilePhoto: nil, restrictionInfo: nil, restrictsNewChats: false,
                status: .userStatusEmpty, type: deleted ? .userTypeDeleted : .userTypeRegular, upgradedGiftColors: nil,
                usernames: nil, verificationStatus: nil,
            )
        }
    }
#endif
