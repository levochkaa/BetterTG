// MessageStatusLineProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks ChatMessageDateAndStatusNode's replies count and pin in a bubble's status: a group's history shows the
    /// count, a pinned message without replies the pin, a thread neither, a channel no count. The lines render to
    /// Documents/status-line.png. Launch with `-ui-probe-status-line`; the result goes to the log and to
    /// Documents/status-line-probe.txt.
    @MainActor enum MessageStatusLineProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-status-line") else { return }
            let result: String
            do {
                try verify()
                result = "Status line probe passed: group-replies/pinned/thread-hidden/channel-no-replies/rendered=true"
            } catch {
                result = "Status line probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("status-line-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verify() throws {
            let withReplies = MessageDeliveryProbe.fixture(
                id: 1,
                outgoing: false,
                interactionInfo: MessageInteractionInfo(
                    forwardCount: 0,
                    reactions: nil,
                    replyInfo: MessageReplyInfo(
                        lastMessageId: 9,
                        lastReadInboxMessageId: 0,
                        lastReadOutboxMessageId: 0,
                        recentReplierIds: [],
                        replyCount: 12,
                    ),
                    viewCount: 0,
                ),
            )
            let plain = MessageDeliveryProbe.fixture(id: 2, outgoing: false)
            let group = MessageStatusLine.make(
                withReplies, isChannel: false, isGroup: true, isPinned: true, time: "12:00",
            )
            try require(group.replyCount == "12" && !group.isPinned, "group \(group)")
            let pinned = MessageStatusLine.make(
                plain, isChannel: false, isGroup: true, isPinned: true, time: "12:01",
            )
            try require(pinned.replyCount == nil && pinned.isPinned, "pinned \(pinned)")
            let thread = MessageStatusLine.make(
                withReplies,
                isChannel: false,
                isGroup: true,
                showsThreadInfo: false,
                isPinned: true,
                time: "12:02",
            )
            try require(thread.replyCount == nil && !thread.isPinned, "thread \(thread)")
            let channel = MessageStatusLine.make(
                withReplies, isChannel: true, isGroup: false, isPinned: false, time: "12:03",
            )
            try require(channel.replyCount == nil, "channel \(channel)")
            let font = UIFont.preferredFont(forTextStyle: .caption2)
            let lines = [group, pinned, thread].map { $0.attributedText(font: font, color: .secondaryLabel) }
            let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 66)).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 160, height: 66))
                for (index, line) in lines.enumerated() {
                    line.draw(at: CGPoint(x: 8, y: 4 + CGFloat(index) * 20))
                }
            }
            if let data = image.pngData(),
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            {
                try? data.write(to: directory.appendingPathComponent("status-line.png"), options: .atomic)
            }
        }
    }
#endif
