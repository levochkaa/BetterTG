// ChatUnreadDividerProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks where ChatTimelineProjection puts the Unread Messages divider (ChatHistoryEntriesForView's
    /// UnreadEntry): above the oldest loaded message past the read state the chat opened with, and nowhere when that
    /// state is outside the loaded messages.
    /// Launch with `-ui-probe-unread-divider`; the result goes to the log and to Documents/unread-divider-probe.txt.
    @MainActor enum ChatUnreadDividerProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-unread-divider") else { return }
            let result: String
            do {
                try verifyPlacement()
                result = "Unread divider probe passed: between-read-and-unread/above-loaded-none/all-read-none/"
                    + "no-state-none/album-newest-source=true"
            } catch {
                result = "Unread divider probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("unread-divider-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verifyPlacement() throws {
            // Newest first, as the timeline runs: 50 and 40 unread after 30.
            let messages = [50, 40, 30, 20].map { id in
                CustomMessage(
                    message: MessageDeliveryProbe.fixture(id: Int64(id), outgoing: false),
                    properties: .default,
                )
            }
            func dividerIndex(_ lastRead: Int64?, _ messages: [CustomMessage]) -> Int? {
                ChatTimelineProjection.items(
                    messages: messages,
                    includesTopicHeaders: false,
                    unreadAfterMessageID: lastRead,
                )
                    .firstIndex(of: .unreadDivider)
            }
            let items = ChatTimelineProjection.items(
                messages: messages,
                includesTopicHeaders: false,
                unreadAfterMessageID: 30,
            )
            guard let divider = items.firstIndex(of: .unreadDivider),
                  let firstUnread = items.firstIndex(of: .message(.message(40))),
                  let lastRead = items.firstIndex(of: .message(.message(30)))
            else { throw Failure(description: "divider missing \(items)") }
            try require(divider == firstUnread + 1 && divider < lastRead, "between \(items)")
            try require(dividerIndex(10, messages) == nil, "above loaded")
            try require(dividerIndex(50, messages) == nil, "all read")
            try require(dividerIndex(nil, messages) == nil, "no state")
            let album = CustomMessage(
                message: MessageDeliveryProbe.fixture(id: 45, album: 9, outgoing: false),
                album: [
                    MessageDeliveryProbe.fixture(id: 45, album: 9, outgoing: false),
                    MessageDeliveryProbe.fixture(id: 35, album: 9, outgoing: false),
                ],
                properties: .default,
            )
            let withAlbum = [messages[0], album, messages[3]]
            let albumItems = ChatTimelineProjection.items(
                messages: withAlbum,
                includesTopicHeaders: false,
                unreadAfterMessageID: 30,
            )
            try require(
                albumItems.firstIndex(of: .unreadDivider) == (albumItems.firstIndex(of: .message(.album(9))) ?? -9) + 1,
                "album \(albumItems)",
            )
        }
    }
#endif
