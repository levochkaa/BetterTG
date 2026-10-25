// MessageDeleteRowProbe.swift

import Combine
import UIKit

#if DEBUG
    /// Checks ChatDeleteMessageContextItem's status: stringForRemainingTime's minutes, hours and rounded days, and the
    /// taller row that holds it under the title. A Delete row with the status and a plain one render to
    /// Documents/delete-row.png. Launch with `-ui-probe-delete-row`; the result goes to the log and to
    /// Documents/delete-row-probe.txt.
    @MainActor enum MessageDeleteRowProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-delete-row") else { return }
            Task { @MainActor in
                let result: String
                do {
                    try verify()
                    try await render()
                    result = "Delete row probe passed: minutes/hours/days/height/timer/rendered=true"
                } catch {
                    result = "Delete row probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("delete-row-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verify() throws {
            let cases: [(Int, String)] = [
                (0, L10n.telegram("Conversation.AutoremoveRemainingTime", "0:00")),
                (65, L10n.telegram("Conversation.AutoremoveRemainingTime", "1:05")),
                (3723, L10n.telegram("Conversation.AutoremoveRemainingTime", "1:02:03")),
                (86399, L10n.telegram("Conversation.AutoremoveRemainingTime", "23:59:59")),
                (86400, L10n.telegramPlural("Conversation.AutoremoveRemainingDays", count: 1)),
                (86400 * 3 / 2, L10n.telegramPlural("Conversation.AutoremoveRemainingDays", count: 2)),
                (86400 * 7 - 1, L10n.telegramPlural("Conversation.AutoremoveRemainingDays", count: 7)),
            ]
            for (timeLeft, expected) in cases {
                let text = ChatViewController.autoDeleteText(timeLeft: timeLeft)
                try require(text == expected, "\(timeLeft) s: \(text), expected \(expected)")
            }
            // The input's timer and its tooltip: shortTimeIntervalString and timeIntervalString.
            let shortCases: [(Int, String)] = [
                (30, "30s"), (300, "5m"), (3600, "1h"), (86400, "1d"), (86400 * 7, "1w"), (86400 * 31, "1mo"),
                (86400 * 365, "1y"),
            ]
            for (seconds, expected) in shortCases {
                let text = ChatComposerView.shortTimeInterval(seconds)
                try require(text.lowercased() == expected, "short \(seconds) s: \(text), expected \(expected)")
            }
            try require(
                ChatViewController.timeIntervalText(86400 * 7) == L10n.telegramPlural("MessageTimer.Weeks", count: 1),
                "week interval \(ChatViewController.timeIntervalText(86400 * 7))",
            )
            try require(
                L10n.telegramPlural("Conversation.AutoremoveRemainingDays", count: 2).contains("2"),
                "days wording \(L10n.telegramPlural("Conversation.AutoremoveRemainingDays", count: 2))",
            )
            var row = deleteRow()
            try require(
                TelegramContextMenuLayout.height(of: row, menuWidth: 240)
                    > TelegramContextMenuLayout.actionHeight + 10,
                "status row height \(TelegramContextMenuLayout.height(of: row, menuWidth: 240))",
            )
            row.subtitleUpdates = nil
            try require(
                TelegramContextMenuLayout.height(of: row, menuWidth: 240) == TelegramContextMenuLayout.actionHeight,
                "plain row height",
            )
        }

        private static func deleteRow() -> TelegramContextMenuAction {
            var action = TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuDelete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
                children: [TelegramContextMenuAction(title: "")],
            )
            action.subtitleUpdates = Just(ChatViewController.autoDeleteText(timeLeft: 3723)).eraseToAnyPublisher()
            return action
        }

        /// The Delete row with its status above a plain Delete row, 240 pt wide.
        private static func render() async throws {
            var plain = deleteRow()
            plain.subtitleUpdates = nil
            let actions = [deleteRow(), plain]
            let rows = actions.map { TelegramContextMenuActionButton(action: $0) }
            let container = UIView(frame: CGRect(
                x: 0,
                y: 0,
                width: 240,
                height: actions.reduce(0) { $0 + TelegramContextMenuLayout.height(of: $1, menuWidth: 240) },
            ))
            container.overrideUserInterfaceStyle = .dark
            container.backgroundColor = .secondarySystemBackground
            var y = CGFloat(0)
            for (action, row) in zip(actions, rows) {
                let height = TelegramContextMenuLayout.height(of: action, menuWidth: 240)
                row.frame = CGRect(x: 0, y: y, width: 240, height: height)
                container.addSubview(row)
                y += height
            }
            try await Task.sleep(for: .milliseconds(300))
            container.layoutIfNeeded()
            try require(
                rows[0].accessibilityValue == ChatViewController.autoDeleteText(timeLeft: 3723),
                "status \(String(describing: rows[0].accessibilityValue))",
            )
            let image = UIGraphicsImageRenderer(bounds: container.bounds).image { context in
                container.layer.render(in: context.cgContext)
            }
            if let data = image.pngData(),
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            {
                try? data.write(to: directory.appendingPathComponent("delete-row.png"), options: .atomic)
            }
        }
    }
#endif
