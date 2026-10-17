// PollOptionMenu.swift

import TDLibKit
import UIKit

// MARK: - PollOptionMenu

/// Telegram's poll answer menu (ChatControllerOpenPollContextMenu): a long press on an answer opens its own actions
/// under an Option tab, and the message's usual actions under a Poll tab.
struct PollOptionMenu {
    struct Permissions {
        /// An open, sent poll the user can vote in now: no vote yet, or a vote that can be changed.
        var canVote: Bool
        /// TDLib's pollOptionProperties.
        var canReply: Bool
        var canCopyLink: Bool
        var canRemove: Bool
    }

    /// Who added the answer after the poll was sent.
    struct Author {
        let name: String
        let isCurrentUser: Bool
        let avatar: UIImage?
    }

    struct Handlers {
        var vote: () -> Void
        var retractVote: () -> Void
        var reply: () -> Void
        var copy: () -> Void
        var copyLink: () -> Void
        var remove: () -> Void
        var openAuthor: () -> Void
    }

    let option: PollOption
    let author: Author?
    let permissions: Permissions
    let handlers: Handlers

    /// The answer's actions in Telegram's order: Vote or Retract Vote, Reply to Option, Copy, Copy Link, Remove and,
    /// after a separator, who added the answer and when.
    var actions: [TelegramContextMenuAction] {
        var actions = [TelegramContextMenuAction]()
        if permissions.canVote {
            actions.append(option.isChosen
                ? TelegramContextMenuAction(
                    title: L10n.telegram("Chat.Poll.RetractOptionVote"),
                    image: UIImage(systemName: "arrow.uturn.backward.circle"),
                    handler: handlers.retractVote,
                )
                : TelegramContextMenuAction(
                    title: L10n.telegram("Chat.Poll.VoteOption"),
                    image: UIImage(systemName: "checkmark.circle"),
                    handler: handlers.vote,
                ))
        }
        if permissions.canReply {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.Poll.ReplyToOption"),
                image: UIImage(systemName: "arrowshape.turn.up.left"),
                handler: handlers.reply,
            ))
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("Conversation.ContextMenuCopy"),
            image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            handler: handlers.copy,
        ))
        if permissions.canCopyLink {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuCopyLink"),
                image: UIImage(systemName: "link"),
                handler: handlers.copyLink,
            ))
        }
        if let author, option.additionDate > 0 {
            if permissions.canRemove {
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("Chat.Poll.RemoveOption"),
                    image: UIImage(systemName: "trash"),
                    isDestructive: true,
                    handler: handlers.remove,
                ))
            }
            var addedBy = TelegramContextMenuAction(
                title: Self.additionTitle(option.additionDate, author: author),
                image: author.avatar ?? UIImage(systemName: "person.crop.circle"),
                startsNewSection: true,
                handler: handlers.openAuthor,
            )
            addedBy.usesSmallText = true
            actions.append(addedBy)
        }
        return actions
    }

    /// humanReadableStringForTimestamp with Telegram's Added by strings: today or yesterday at a time, or the date
    /// and time. A name longer than 20 characters is cut.
    static func additionTitle(_ timestamp: Int, author: Author) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let time = date.formatted(date: .omitted, time: .shortened)
        let name = author.name.count > 20 ? String(author.name.prefix(20)) + "..." : author.name
        let you = author.isCurrentUser ? "You" : ""
        func title(_ form: String, _ value: String) -> String {
            let key = "Chat.PollOptionAddedTimestamp\(you).\(form)"
            return author.isCurrentUser ? L10n.telegram(key, value) : L10n.telegram(key, name, value)
        }
        if Calendar.current.isDateInToday(date) { return title("TodayAt", time) }
        if Calendar.current.isDateInYesterday(date) { return title("YesterdayAt", time) }
        return title("Date", date.formatted(date: .abbreviated, time: .shortened))
    }

    /// ContextMenuActionItem's 24 pt avatar from a downloaded profile photo.
    static func avatar(path: String) -> UIImage? {
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size)
            .image { _ in
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            .withRenderingMode(.alwaysOriginal)
    }

    /// The Option source with Telegram's footer, then the message's actions as the Poll source, which keeps the
    /// reactions.
    func sources(messageActions: [TelegramContextMenuAction]) -> [TelegramContextMenuSource] {
        [
            TelegramContextMenuSource(
                title: L10n.telegram("Chat.Poll.ContextMenu.SectionOption"),
                footer: L10n.telegram("Chat.Poll.ContextMenu.SectionsInfo"),
                actions: actions,
                showsReactions: false,
            ),
            TelegramContextMenuSource(
                title: L10n.telegram("Chat.Poll.ContextMenu.SectionPoll"),
                actions: messageActions,
            ),
        ]
    }
}
