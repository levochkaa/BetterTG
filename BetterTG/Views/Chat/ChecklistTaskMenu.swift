// ChecklistTaskMenu.swift

import TDLibKit
import UIKit

// MARK: - ChecklistTaskMenu

/// Telegram's checklist task menu (ChatControllerOpenTodoContextMenu): a long press on a task opens its own actions
/// under a Task tab, and the message's usual actions under a List tab.
struct ChecklistTaskMenu {
    struct Permissions {
        /// TDLib's `canMarkTasksAsDone` for a published checklist.
        var canMark: Bool
        var canReply: Bool
        var canCopy: Bool
        /// Telegram offers Copy Link in channels and supergroups, where TDLib's `canGetLink` holds.
        var canCopyLink: Bool
        var canEdit: Bool
    }

    struct Handlers {
        var toggle: () -> Void
        var reply: () -> Void
        var copy: () -> Void
        var copyLink: () -> Void
        var edit: () -> Void
        var delete: () -> Void
    }

    let task: ChecklistTask
    /// The task's state as the bubble shows it, a pending check included.
    let isDone: Bool
    let taskCount: Int
    let permissions: Permissions
    let handlers: Handlers

    /// The task's actions in Telegram's order: when it was completed, Check or Uncheck, Reply to Item, Copy, Copy Link,
    /// Edit Item and, after a separator, Delete Item while the checklist keeps another task.
    var actions: [TelegramContextMenuAction] {
        var actions = [TelegramContextMenuAction]()
        var startsSection = false
        func append(_ action: TelegramContextMenuAction) {
            var action = action
            if startsSection {
                action.startsNewSection = true
                startsSection = false
            }
            actions.append(action)
        }
        if task.completedBy != nil, task.completionDate > 0 {
            var date = TelegramContextMenuAction(title: Self.completionTitle(task.completionDate))
            date.isInformational = true
            append(date)
            startsSection = true
        }
        if permissions.canMark {
            append(TelegramContextMenuAction(
                title: L10n.telegram(isDone ? "Chat.Todo.ContextMenu.UncheckTask" : "Chat.Todo.ContextMenu.CheckTask"),
                image: UIImage(systemName: isDone ? "xmark.circle" : "checkmark.circle"),
                handler: handlers.toggle,
            ))
        }
        if permissions.canReply {
            append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.Todo.ReplyToItem"),
                image: UIImage(systemName: "arrowshape.turn.up.left"),
                handler: handlers.reply,
            ))
        }
        if permissions.canCopy {
            append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuCopy"),
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
                handler: handlers.copy,
            ))
        }
        if permissions.canCopyLink {
            append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuCopyLink"),
                image: UIImage(systemName: "link"),
                handler: handlers.copyLink,
            ))
        }
        if permissions.canEdit {
            append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.Todo.ContextMenu.EditTask"),
                image: UIImage(systemName: "square.and.pencil"),
                handler: handlers.edit,
            ))
            if taskCount > 1 {
                startsSection = true
                append(TelegramContextMenuAction(
                    title: L10n.telegram("Chat.Todo.ContextMenu.DeleteTask"),
                    image: UIImage(systemName: "trash"),
                    isDestructive: true,
                    handler: handlers.delete,
                ))
            }
        }
        return actions
    }

    /// Telegram's humanReadableStringForTimestamp with the completion strings: today or yesterday at a time, or the
    /// date and time.
    static func completionTitle(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return L10n.telegram("Chat.TodoItemCompletionTimestamp.TodayAt", time)
        }
        if Calendar.current.isDateInYesterday(date) {
            return L10n.telegram("Chat.TodoItemCompletionTimestamp.YesterdayAt", time)
        }
        return L10n.telegram(
            "Chat.TodoItemCompletionTimestamp.Date",
            date.formatted(date: .abbreviated, time: .shortened),
        )
    }

    /// The Task source with Telegram's footer, then the message's actions as the List source, which keeps the
    /// reactions.
    func sources(messageActions: [TelegramContextMenuAction]) -> [TelegramContextMenuSource] {
        [
            TelegramContextMenuSource(
                title: L10n.telegram("Chat.Todo.ContextMenu.SectionTask"),
                footer: L10n.telegram("Chat.Todo.ContextMenu.SectionsInfo"),
                actions: actions,
                showsReactions: false,
            ),
            TelegramContextMenuSource(
                title: L10n.telegram("Chat.Todo.ContextMenu.SectionList"),
                actions: messageActions,
            ),
        ]
    }
}
