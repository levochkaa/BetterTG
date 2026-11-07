// ChatListForumRowProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Lays out the account's forum rows as the chat list does: the last message's topic, the other recent topics
    /// after it (topForumTopicItems) and, for an unread first topic, the compound highlight with its arrow. Each row
    /// is rendered to Documents/forum-row-N.png. Launch with `-ui-probe-forum-row`; the result goes to the log and
    /// to Documents/forum-row-probe.txt.
    @MainActor enum ChatListForumRowProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-forum-row") else { return }
            Task {
                let result: String
                do {
                    result = try await run()
                } catch {
                    result = "Forum row probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("forum-row-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func run() async throws -> String {
            try await ProbeFixtures.waitForActiveAccount()
            let client = TDLib.shared.activeClient
            var forums = [CustomChat]()
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while forums.isEmpty, ContinuousClock.now < deadline {
                var seen = Set<Int64>()
                forums = RootVM.shared.allFolders.flatMap(\.chats).filter { chat in
                    chat.supergroup?.isForum == true && chat.lastMessage != nil && seen.insert(chat.id).inserted
                }
                if forums.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
            }
            guard !forums.isEmpty else { throw Failure(description: "no forum in the chat list") }
            guard let window = UIApplication.shared
                .connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first
            else { throw Failure(description: "window") }
            var lines = [String]()
            for (index, chat) in forums.prefix(4).enumerated() {
                let cell = ChatListCell(style: .default, reuseIdentifier: ChatListCell.reuseIdentifier)
                let width = window.bounds.width
                cell.frame = CGRect(x: 0, y: 0, width: width, height: ChatListCell.cardRowHeight)
                let host = UIView(frame: CGRect(x: 0, y: -400, width: width, height: ChatListCell.cardRowHeight))
                host.backgroundColor = .systemBackground
                host.addSubview(cell)
                window.addSubview(host)
                defer { host.removeFromSuperview() }
                var opened = [Int]()
                cell.onOpenTopic = { opened.append($0) }
                cell.configure(chat: chat, isMuted: false, client: client)
                // The recent topics and their icons arrive from TDLib.
                try await Task.sleep(for: .seconds(3))
                cell.layoutIfNeeded()
                let summary = cell.probeTopicSummary
                lines.append("row \(index): \(summary.description)")
                try require(!summary.selectable || summary.highlightBounds != nil, "row \(index): no highlight")
                try require(summary.shownTopics >= 1, "row \(index): no topic on the line")
                let image = UIGraphicsImageRenderer(bounds: cell.bounds).image { _ in
                    cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
                }
                if let data = image.pngData(),
                   let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                {
                    try? data.write(to: directory.appendingPathComponent("forum-row-\(index).png"), options: .atomic)
                }
                // An unread first topic: TDLib reports the test forums' topics read, so the row is told to treat its
                // first one as unread to lay out the compound highlight.
                cell.probeTreatsFirstTopicAsUnread = true
                cell.configure(chat: chat, isMuted: false, client: client)
                cell.layoutIfNeeded()
                let unread = cell.probeTopicSummary
                lines.append("row \(index) unread: \(unread.description)")
                try require(unread.selectable, "row \(index): an unread first topic isn't selectable")
                try require(unread.highlightBounds != nil, "row \(index): no highlight")
                cell.probeTapTopic()
                try require(opened.count == 1, "row \(index): the topic button didn't open the topic")
                let unreadImage = UIGraphicsImageRenderer(bounds: cell.bounds).image { _ in
                    cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
                }
                if let data = unreadImage.pngData(),
                   let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                {
                    try? data.write(
                        to: directory.appendingPathComponent("forum-row-\(index)-unread.png"),
                        options: .atomic,
                    )
                }
                withExtendedLifetime(chat) {}
            }
            return "Forum row probe passed: " + lines.joined(separator: "; ")
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }
    }
#endif
