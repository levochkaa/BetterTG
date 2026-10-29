// MessageEntityMenuProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks the long-press menus of a message's links, mentions and bot commands: which entity a press finds, what
    /// the card shows and Copy puts on the pasteboard, and the actions of each menu. The mention menu with its peer row
    /// and with an unknown username, and the command menu, render to Documents/entity-menus.png. Launch with
    /// `-ui-probe-entity-menus`; the result goes to the log and to Documents/entity-menus-probe.txt.
    @MainActor enum MessageEntityMenuProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        /// `-ui-probe-hashtag-search`: #telegram from the test group, on Public Posts. Add `-hashtag-chat-only` to
        /// check
        /// the single-chat layout without tabs.
        static func openHashtagSearchIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-hashtag-search") else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let client = TDLib.shared.activeClient
                guard let chat = await RootVM.shared.getCustomChatForNavigation(
                    from: -1_004_361_744_153,
                    client: client,
                )
                else { return log("Hashtag search probe: no test group") }
                NavigationStorage.shared.navigationController.pushViewController(
                    HashtagSearchViewController(
                        query: "#telegram", chat: chat,
                        chatOnly: ProcessInfo.processInfo.arguments.contains("-hashtag-chat-only"),
                        startsOnPublicPosts: true, client: client,
                    ),
                    animated: true,
                )
            }
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-entity-menus") else { return }
            Task { @MainActor in
                let result: String
                do {
                    try verifyTargets()
                    try verifyMenus()
                    try await render()
                    result = "Entity menu probe passed: targets/copy/menus/rendered=true"
                } catch {
                    result = "Entity menu probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("entity-menus-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        /// "a.io x a@b.io @name /go Ann +123 #tag hidden.io": every entity a press may land on.
        private static func verifyTargets() throws {
            let text = "a.io x a@b.io @name /go Ann +123 #tag hidden.io"
            func entity(_ word: String, _ type: TextEntityType) -> TextEntity {
                let range = (text as NSString).range(of: word)
                return TextEntity(length: range.length, offset: range.location, type: type)
            }
            let formatted = FormattedText(entities: [
                entity("a.io", .textEntityTypeUrl),
                entity("x", .textEntityTypeTextUrl(.init(url: "https://x.example"))),
                entity("a@b.io", .textEntityTypeEmailAddress),
                entity("@name", .textEntityTypeMention),
                entity("/go", .textEntityTypeBotCommand),
                entity("Ann", .textEntityTypeMentionName(.init(userId: 42))),
                entity("+123", .textEntityTypePhoneNumber),
                entity("#tag", .textEntityTypeHashtag),
                entity("hidden.io", .textEntityTypeUrl),
                entity("hidden.io", .textEntityTypeSpoiler),
            ], text: text)
            let presentation = MessageTextSpoilerPresentation(formatted)
            func target(at word: String, revealed: Bool = false) -> MessageTextLink.Target? {
                presentation.longPressTarget(at: (text as NSString).range(of: word).location, revealed: revealed)?
                    .target
            }
            try require(target(at: "a.io") == .url("a.io"), "url \(String(describing: target(at: "a.io")))")
            try require(target(at: "x") == .url("https://x.example"), "text url")
            try require(target(at: "a@b.io") == .url("mailto:a@b.io"), "email")
            try require(target(at: "@name") == .mention("@name"), "mention")
            try require(target(at: "/go") == .botCommand("/go"), "command")
            try require(target(at: "Ann") == .userMention(42, text: "Ann"), "text mention")
            try require(target(at: "+123") == nil, "phone has no menu yet")
            try require(target(at: "#tag") == .hashtag("#tag"), "hashtag")
            try require(
                presentation.action(at: (text as NSString).range(of: "#tag").location, revealed: false)
                == .hashtag("#tag"),
                "hashtag tap",
            )
            try require(target(at: "hidden.io") == nil, "url under a spoiler")
            try require(target(at: "hidden.io", revealed: true) == .url("hidden.io"), "revealed url")
            try require(
                MessageTextLink(target: .url("mailto:a@b.io"), rects: []).previewText == "a@b.io",
                "email card",
            )
            try require(MessageLinkMenu(url: "mailto:a@b.io").copiedText == "a@b.io", "copied email")
            try require(MessageLinkMenu(url: "https://a.io/x").copiedText == "https://a.io/x", "copied url")
        }

        private static func verifyMenus() throws {
            let link = MessageLinkMenu(url: "https://a.io").actions(open: {}, copied: { _ in }).map(\.title)
            try require(link == [
                L10n.telegram("Conversation.LinkDialogOpen"),
                L10n.telegram("Conversation.ContextMenuCopyLink"),
                L10n.telegram("Conversation.AddToReadingList"),
            ], "link actions \(link)")
            let email = MessageLinkMenu(url: "mailto:a@b.io").actions(open: {}, copied: { _ in }).map(\.title)
            try require(email == [
                L10n.telegram("Conversation.LinkDialogOpen"),
                L10n.telegram("Conversation.ContextMenuCopyEmail"),
            ], "email actions \(email)")
            let channel = mentionActions(kind: .channel)
            try require(channel.map(\.title) == [
                L10n.telegram("Chat.Context.Username.OpenChannel"),
                L10n.telegram("Chat.Context.Username.Copy"),
                "Probe Channel",
            ], "channel mention \(channel.map(\.title))")
            try require(channel[2].startsNewSection && channel[2].secondLine?.showsArrow == true, "peer row")
            try require(
                mentionActions(kind: .user).first?.title == L10n.telegram("Chat.Context.Username.SendMessage"),
                "user mention",
            )
            try require(
                mentionActions(kind: .group).first?.title == L10n.telegram("Chat.Context.Username.OpenGroup"),
                "group mention",
            )
            let unknown = MessageMentionMenu(text: "@nobody", peer: nil)
                .actions(open: { _ in }, openProfile: { _ in }, copied: { _ in })
            try require(unknown.map(\.title) == [
                L10n.telegram("Chat.Context.Username.Copy"),
                L10n.telegram("Chat.Context.Username.NotOnTelegram"),
            ] && unknown[1].isInformational, "unknown mention \(unknown.map(\.title))")
            let hashtag = MessageHashtagMenu.actions(hashtag: "#tag", search: {}, copied: { _ in }).map(\.title)
            try require(hashtag == [
                L10n.telegram("Chat.Context.Hashtag.Search"),
                L10n.telegram("Chat.Context.Hashtag.Copy"),
            ], "hashtag menu \(hashtag)")
            let command = MessageCommandMenu.actions(command: "/go", copied: { _ in }).map(\.title)
            try require(command == [L10n.telegram("Chat.Context.Command.Copy")], "command \(command)")
            try require(
                TelegramContextMenuLayout.height(of: channel[2], menuWidth: 250)
                    == TelegramContextMenuLayout.subtitledActionHeight,
                "peer row height",
            )
        }

        private static func mentionActions(kind: MessageMentionMenu.Peer.Kind) -> [TelegramContextMenuAction] {
            MessageMentionMenu(
                text: "@probe",
                peer: .init(kind: kind, name: "Probe Channel", avatar: nil, destination: .chat(1)),
            )
            .actions(open: { _ in }, openProfile: { _ in }, copied: { _ in })
        }

        /// The channel mention's menu, the unknown username's and the command's, one under another, 250 pt wide.
        private static func render() async throws {
            let unknown = MessageMentionMenu(text: "@nobody", peer: nil)
                .actions(open: { _ in }, openProfile: { _ in }, copied: { _ in })
            let actions = mentionActions(kind: .channel) + unknown
                + MessageCommandMenu.actions(command: "/go", copied: { _ in })
            let width = CGFloat(250)
            let rows = actions.map { TelegramContextMenuActionButton(action: $0) }
            let heights = actions.map { TelegramContextMenuLayout.height(of: $0, menuWidth: width) }
            let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: heights.reduce(0, +)))
            container.overrideUserInterfaceStyle = .dark
            container.backgroundColor = .secondarySystemBackground
            var y = CGFloat(0)
            for (row, height) in zip(rows, heights) {
                row.frame = CGRect(x: 0, y: y, width: width, height: height)
                container.addSubview(row)
                y += height
            }
            try await Task.sleep(for: .milliseconds(300))
            container.layoutIfNeeded()
            try require(
                rows[2].accessibilityValue == L10n.telegram("Chat.Context.Phone.ViewProfile"),
                "peer row value \(String(describing: rows[2].accessibilityValue))",
            )
            let image = UIGraphicsImageRenderer(bounds: container.bounds).image { context in
                container.layer.render(in: context.cgContext)
            }
            if let data = image.pngData(),
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            {
                try? data.write(to: directory.appendingPathComponent("entity-menus.png"), options: .atomic)
            }
        }
    }
#endif
