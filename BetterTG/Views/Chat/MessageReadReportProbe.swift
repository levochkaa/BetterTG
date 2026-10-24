// MessageReadReportProbe.swift

import Combine
import TDLibKit
import UIKit

#if DEBUG
    /// Checks ChatReadReportContextItem's group row: the text for viewers, listens, watches and reactions, when the row
    /// opens the list, and which avatars it shows. A loading, a seen and a nobody-listened row render to
    /// Documents/read-report.png. Launch with `-ui-probe-read-report`; the result goes to the log and to
    /// Documents/read-report-probe.txt.
    @MainActor enum MessageReadReportProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-read-report") else { return }
            Task { @MainActor in
                let result: String
                do {
                    try verify()
                    try await ProbeFixtures.waitForActiveAccount()
                    try await render()
                    result = "Read report probe passed: loading/nobody/seen/listened/watched/reactions/mixed/"
                        + "enabled/avatars/rendered=true"
                } catch {
                    result = "Read report probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("read-report-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func user(_ id: Int64) -> MessageSender {
            .messageSenderUser(MessageSenderUser(userId: id))
        }

        private static func report(
            reactions: Int,
            media: MessageReadReport.Media = .other,
            viewers: [Int64]?,
            reactors: [MessageSender] = [],
        ) -> MessageReadReport {
            var report = MessageReadReport(reactionCount: reactions, media: media, canListViewers: true)
            report.viewerIDs = viewers
            report.recentReactors = reactors
            return report
        }

        private static func verify() throws {
            let loading = report(reactions: 0, viewers: nil)
            try require(loading.title == nil && !loading.isEnabled, "loading \(String(describing: loading.title))")
            let reactingWhileLoading = report(reactions: 2, viewers: nil)
            try require(reactingWhileLoading.isEnabled, "reactions enable the row before the viewers load")
            let unlisted = MessageReadReport(reactionCount: 0, media: .other, canListViewers: false)
            try require(unlisted.viewerIDs == [], "unlisted viewers \(String(describing: unlisted.viewerIDs))")

            let cases: [(MessageReadReport, String, Bool)] = [
                (report(reactions: 0, viewers: []), L10n.telegram("Conversation.ContextMenuNoViews"), false),
                (
                    report(reactions: 0, media: .voice, viewers: []),
                    L10n.telegram("Conversation.ContextMenuNobodyListened"),
                    false,
                ),
                (
                    report(reactions: 0, media: .round, viewers: []),
                    L10n.telegram("Conversation.ContextMenuNobodyWatched"),
                    false,
                ),
                (
                    report(reactions: 0, viewers: [1, 2, 3]),
                    L10n.telegramPlural("Conversation.ContextMenuSeen", count: 3),
                    true,
                ),
                (
                    report(reactions: 0, media: .voice, viewers: [1, 2]),
                    L10n.telegramPlural("Conversation.ContextMenuListened", count: 2),
                    true,
                ),
                (
                    report(reactions: 0, media: .round, viewers: [1]),
                    L10n.telegramPlural("Conversation.ContextMenuWatched", count: 1),
                    true,
                ),
                (
                    report(reactions: 4, viewers: []),
                    L10n.telegramPlural("Chat.ContextReactionCount", count: 4),
                    true,
                ),
                (
                    report(reactions: 2, viewers: [1, 2]),
                    L10n.telegramPlural("Chat.OutgoingContextReactionCount", count: 2),
                    true,
                ),
                (
                    report(reactions: 1, media: .voice, viewers: [1, 2, 3]),
                    L10n.telegram("Chat.OutgoingContextMixedReactionCount", "1", "3"),
                    true,
                ),
            ]
            for (index, (report, title, enabled)) in cases.enumerated() {
                try require(
                    report.title == title && report.isEnabled == enabled,
                    "case \(index): \(String(describing: report.title)) \(report.isEnabled), expected \(title) \(enabled)",
                )
            }
            try require(
                L10n.telegram("Chat.OutgoingContextMixedReactionCount", "1", "3").contains("1/3"),
                "mixed wording \(L10n.telegram("Chat.OutgoingContextMixedReactionCount", "1", "3"))",
            )

            let reactors = report(reactions: 5, viewers: [9], reactors: [user(1), user(2), user(1), user(3), user(4)])
            try require(reactors.avatarSenders == [user(1), user(2), user(3)], "reactors \(reactors.avatarSenders)")
            let viewers = report(reactions: 0, viewers: [5, 6, 7, 8])
            try require(viewers.avatarSenders == [user(5), user(6), user(7)], "viewers \(viewers.avatarSenders)")
            try require(loading.avatarSenders.isEmpty, "loading avatars \(loading.avatarSenders)")
        }

        private static func peer(_ id: Int64, _ letter: String) -> SettingsPeer {
            SettingsPeer(
                id: id,
                title: letter,
                file: nil,
                minithumbnail: nil,
                placeholder: TelegramAvatarPlaceholder(
                    peerID: id,
                    accentColorID: Int(id % 7),
                    upgradedGiftColors: nil,
                    letters: [letter],
                    isDeleted: false,
                ),
            )
        }

        /// The rows as the menu lays them out 240 pt wide: still loading, three viewers, nobody listened.
        private static func render() async throws {
            let client = TDLib.shared.activeClient
            func row(
                image: String,
                title: String?,
                selectable: Bool,
                avatars: [SettingsPeer]?,
            ) -> TelegramContextMenuActionButton {
                var action = TelegramContextMenuAction(title: "", image: UIImage(systemName: image))
                action.titleUpdates = title.map { Just($0).eraseToAnyPublisher() } ?? Empty().eraseToAnyPublisher()
                action.selectableUpdates = Just(selectable).eraseToAnyPublisher()
                action.avatarUpdates = avatars.map {
                    Just(TelegramContextMenuAvatars(peers: $0, client: client)).eraseToAnyPublisher()
                } ?? Empty().eraseToAnyPublisher()
                return TelegramContextMenuActionButton(action: action)
            }
            let rows = [
                row(image: "eye", title: nil, selectable: false, avatars: nil),
                row(
                    image: "eye",
                    title: L10n.telegramPlural("Conversation.ContextMenuSeen", count: 3),
                    selectable: true,
                    avatars: [peer(1, "A"), peer(2, "B"), peer(3, "C")],
                ),
                row(
                    image: "eye",
                    title: L10n.telegram("Conversation.ContextMenuNobodyListened"),
                    selectable: false,
                    avatars: [],
                ),
            ]
            let height = TelegramContextMenuLayout.actionHeight
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: height * CGFloat(rows.count)))
            container.overrideUserInterfaceStyle = .dark
            container.backgroundColor = .secondarySystemBackground
            for (index, row) in rows.enumerated() {
                row.frame = CGRect(x: 0, y: height * CGFloat(index), width: 240, height: height)
                container.addSubview(row)
            }
            try await Task.sleep(for: .milliseconds(600))
            container.layoutIfNeeded()
            let labels = rows.map { $0.accessibilityLabel ?? "" }
            try require(
                labels[0].isEmpty && labels[1] == L10n.telegramPlural("Conversation.ContextMenuSeen", count: 3),
                "row labels \(labels)",
            )
            try require(!rows[0].acceptsSelection && rows[1].acceptsSelection, "row selection")
            let image = UIGraphicsImageRenderer(bounds: container.bounds).image { context in
                container.layer.render(in: context.cgContext)
            }
            if let data = image.pngData(),
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            {
                try? data.write(to: directory.appendingPathComponent("read-report.png"), options: .atomic)
            }
        }
    }
#endif
