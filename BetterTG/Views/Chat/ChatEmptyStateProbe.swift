// ChatEmptyStateProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks the empty chat state offline: ChatEmptyStateView.kind's content choice for each kind of chat, the
    /// texts each content shows and the card staying inside the history.
    /// Launch with `-ui-probe-empty-chat`; the result goes to the log and to Documents/empty-chat-probe.txt.
    @MainActor enum ChatEmptyStateProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-empty-chat") else { return }
            Task {
                let result: String
                do {
                    try await ProbeFixtures.waitForActiveAccount()
                    try verifyKinds()
                    try verifyContent()
                    result = "Empty chat probe passed: person-greeting/blocked-regular/deleted-regular/support-regular/"
                        + "thread-regular/group-member-regular/group-creator-group=true; "
                        + "regular/greeting/cloud/secret/group-texts/card-inside=true"
                } catch {
                    result = "Empty chat probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("empty-chat-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verifyKinds() throws {
            typealias Kind = ChatEmptyStateView.Kind
            let position = ChatPosition(list: .chatListMain, order: 1, isPinned: false, source: nil)
            let person = ProbeFixtures.chat(
                position,
                title: "Alice",
                id: 11,
                user: user(.userTypeRegular, support: false),
            )
            let deleted = ProbeFixtures.chat(
                position,
                title: "Gone",
                id: 12,
                user: user(.userTypeDeleted, support: false),
            )
            let support = ProbeFixtures.chat(
                position,
                title: "Help",
                id: 13,
                user: user(.userTypeRegular, support: true),
            )
            let group = ProbeFixtures.chat(position, title: "Group", id: 14)
            let created = ProbeFixtures.chat(position, title: "Mine", id: 15)
            created.type = .group(.init(
                id: 7,
                memberCount: 1,
                status: .chatMemberStatusCreator(.init(isAnonymous: false, isMember: true)),
                isActive: true,
                upgradedToSupergroupId: 0,
            ))
            let cases: [(String, CustomChat, Bool, Bool, Kind)] = [
                ("person", person, false, false, .greeting),
                ("blocked person", person, true, false, .regular),
                ("deleted", deleted, false, false, .regular),
                ("support", support, false, false, .regular),
                ("thread", person, false, true, .regular),
                ("group member", group, false, false, .regular),
                ("group creator", created, false, false, .group),
            ]
            for (name, chat, isBlocked, isThread, expected) in cases {
                let kind = ChatEmptyStateView.kind(for: chat, isBlocked: isBlocked, isThread: isThread)
                try require(kind == expected, "\(name): \(kind)")
            }
        }

        private static func verifyContent() throws {
            let client = TDLib.shared.activeClient
            let expectations: [(ChatEmptyStateView.Kind, [String])] = [
                (.regular, [L10n.telegram("Conversation.EmptyPlaceholder")]),
                (
                    .greeting,
                    [L10n.telegram("Conversation.EmptyPlaceholder"), L10n.telegram("Conversation.GreetingText")],
                ),
                (
                    .cloud,
                    [L10n.telegram("Conversation.CloudStorageInfo.Title")]
                    + (1...4).map { L10n.telegram("Conversation.ClousStorageInfo.Description\($0)") },
                ),
                (.secret(name: "Alice", secretChatID: 0), [
                    L10n.telegram("Conversation.EncryptedPlaceholderTitleOutgoing", "Alice"),
                    L10n.telegram("Conversation.EncryptedDescriptionTitle"),
                ] + (1...4).map { L10n.telegram("Conversation.EncryptedDescription\($0)") }),
                (
                    .group,
                    [L10n.telegram("EmptyGroupInfo.Title"), L10n.telegram("EmptyGroupInfo.Subtitle")]
                    + [L10n.telegram("EmptyGroupInfo.Line1", AppLocalization.formattedNumber(200_000))]
                    + (2...4).map { L10n.telegram("EmptyGroupInfo.Line\($0)") },
                ),
            ]
            for (kind, texts) in expectations {
                let view = ChatEmptyStateView(kind: kind, client: client)
                view.frame = CGRect(x: 0, y: 0, width: 402, height: 600)
                view.layoutIfNeeded()
                try require(view.probeTexts == texts, "\(kind) texts \(view.probeTexts)")
                saveSnapshot(of: view, kind: kind)
                let card = view.probeCardFrame
                try require(
                    card.minX >= 0 && card.maxX <= 402 && card.minY >= 0 && card.maxY <= 600 && card.width > 0,
                    "\(kind) card \(card)",
                )
            }
        }

        /// Documents/empty-chat-<kind>.png in the dark appearance, for a look at each card.
        private static func saveSnapshot(of view: ChatEmptyStateView, kind: ChatEmptyStateView.Kind) {
            view.overrideUserInterfaceStyle = .dark
            view.backgroundColor = .black
            view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
                view.layer.render(in: context.cgContext)
            }
            let name =
                switch kind {
                case .regular: "regular"
                case .greeting: "greeting"
                case .cloud: "cloud"
                case .secret: "secret"
                case .group: "group"
                }
            guard let data = image.pngData(),
                  let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            try? data.write(to: directory.appendingPathComponent("empty-chat-\(name).png"), options: .atomic)
        }

        private static func user(_ type: UserType, support: Bool) -> User {
            User(
                accentColorId: -1, activeStoryState: nil, addedToAttachmentMenu: false, backgroundCustomEmojiId: 0,
                emojiStatus: nil, firstName: "Alice", haveAccess: true, id: 11, isCloseFriend: false,
                isContact: false, isMutualContact: false, isPremium: false, isSupport: support, languageCode: "",
                lastName: "", paidMessageStarCount: 0, phoneNumber: "", profileAccentColorId: -1,
                profileBackgroundCustomEmojiId: 0, profilePhoto: nil, restrictionInfo: nil, restrictsNewChats: false,
                status: .userStatusEmpty, type: type, upgradedGiftColors: nil, usernames: nil, verificationStatus: nil,
            )
        }
    }
#endif
