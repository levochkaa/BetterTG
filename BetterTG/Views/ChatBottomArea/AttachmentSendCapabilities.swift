// AttachmentSendCapabilities.swift

import UIKit

// MARK: - AttachmentSendTiming

enum AttachmentSendTiming {
    case now
    case silently
    case whenOnline
    case schedule
}

// MARK: - AttachmentSendCapabilities

/// AttachmentController's send menu follows the destination: Saved Messages offers reminders, secret chats
/// cannot schedule, and Send When Online requires a known last-seen status. Gallery also excludes media timers.
struct AttachmentSendCapabilities {
    var isReminders = false
    var canSchedule = false
    var canSendWhenOnline = false

    func menuActions(send: @escaping (AttachmentSendTiming) -> Void) -> [TelegramContextMenuAction] {
        var actions = [TelegramContextMenuAction]()
        if !isReminders {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.SendMessage.SendSilently"),
                image: UIImage(systemName: "bell.slash"),
            ) { send(.silently) })
            if canSchedule, canSendWhenOnline {
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.SendMessage.SendWhenOnline"),
                    image: UIImage(systemName: "person.crop.circle.badge.clock"),
                ) { send(.whenOnline) })
            }
        }
        if canSchedule {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isReminders
                    ? "Conversation.SendMessage.SetReminder"
                    : "Conversation.SendMessage.ScheduleMessage"),
                image: UIImage(systemName: "calendar.badge.clock"),
            ) { send(.schedule) })
        }
        return actions
    }
}
