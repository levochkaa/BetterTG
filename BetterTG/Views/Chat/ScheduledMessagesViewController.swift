// ScheduledMessagesViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ScheduledMessagesViewController

/// Telegram's scheduled messages chat (ChatControllerSubject.scheduledMessages) as a BetterTG list: the chat's or
/// topic's scheduled messages grouped by the day they go out, or "until online". A message's menu sends it now,
/// reschedules it (editMessageSchedulingState), copies its text or deletes it. Saved Messages calls them reminders.
final class ScheduledMessagesViewController: SettingsListViewController {
    private let location: ChatLocation
    private let isReminders: Bool
    private let canSendWhenOnline: Bool
    private var messages: [Message]?
    private var updateCancellables = Set<AnyCancellable>()
    private var reloadTask: Task<Void, Never>?
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter
    }()

    init(location: ChatLocation, isReminders: Bool, canSendWhenOnline: Bool) {
        self.location = location
        self.isReminders = isReminders
        self.canSendWhenOnline = canSendWhenOnline
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { reloadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(isReminders ? "ScheduledMessages.RemindersTitle" : "ScheduledMessages.Title")
        observeUpdates()
        loadMessages()
    }

    override func makeSections() -> [SettingsSection] {
        guard let messages else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )])]
        }
        guard !messages.isEmpty else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("ScheduledMessages.EmptyPlaceholder"),
                style: .status(.secondaryLabel),
            )])]
        }
        var sections = [SettingsSection]()
        var currentHeader: String?
        for message in messages {
            let header = Self.header(for: message, dayFormatter: dayFormatter)
            let content = MessageContentPresentation.make(message)
            let row = SettingsRow(
                title: content.summary,
                detail: Self.time(for: message),
                style: .subtitle,
                action: {},
            )
            if header == currentHeader, !sections.isEmpty {
                sections[sections.count - 1].rows.append(row)
            } else {
                sections.append(SettingsSection(header: header, rows: [row]))
                currentHeader = header
            }
        }
        return sections
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let message = scheduledMessage(at: indexPath),
              let cell = tableView.cellForRow(at: indexPath) else { return }
        presentMenu(for: message, from: cell)
    }

    // MARK: Content

    /// The day Telegram's scheduled chat heads a message with: today, a date, or until online.
    private static func header(for message: Message, dayFormatter: DateFormatter) -> String {
        switch message.schedulingState {
        case .messageSchedulingStateSendAtDate(let state):
            let date = Date(timeIntervalSince1970: TimeInterval(state.sendDate))
            return Calendar.current.isDateInToday(date)
                ? L10n.telegram("ScheduledMessages.ScheduledToday")
                : L10n.telegram("ScheduledMessages.ScheduledDate", dayFormatter.string(from: date))
        case .messageSchedulingStateSendWhenOnline:
            return L10n.telegram("ScheduledMessages.ScheduledOnline")
        default:
            return L10n.telegram("ScheduledMessages.Title")
        }
    }

    private static func time(for message: Message) -> String? {
        guard case .messageSchedulingStateSendAtDate(let state) = message.schedulingState else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(state.sendDate)).formatted(date: .omitted, time: .shortened)
    }

    private static func sendDate(of message: Message) -> Int {
        if case .messageSchedulingStateSendAtDate(let state) = message.schedulingState { return state.sendDate }
        return Int.max
    }

    private func scheduledMessage(at indexPath: IndexPath) -> Message? {
        guard let messages else { return nil }
        var offset = 0
        for section in 0..<indexPath.section {
            offset += sections[safe: section]?.rows.count ?? 0
        }
        return messages[safe: offset + indexPath.row]
    }

    private func loadMessages() {
        guard contextIsCurrent else { return }
        let client = client
        let location = location
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let loaded = try? await client.send(TDNativeRequests.getChatScheduledMessages(chatId: location.chatID))
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            messages = (loaded?.messages ?? [])
                .filter { $0.schedulingState != nil && location.matches(message: $0) }
                .sorted { Self.sendDate(of: $0) < Self.sendDate(of: $1) }
            reload()
        }
    }

    /// TDLib announces scheduled messages with the ordinary message updates; any of them for this chat reloads it.
    private func observeUpdates() {
        nc.publisher(
            &updateCancellables,
            for: TdNotification<UpdateNewMessage>.updateNewMessage.name,
        ) { [weak self] notification in
            guard let update = TdScopedUpdate<UpdateNewMessage>(notification: notification),
                  update.value.message.schedulingState != nil else { return }
            self?.reloadAfterUpdate(from: update.source, chatID: update.value.message.chatId)
        }
        nc.publisher(
            &updateCancellables,
            for: TdNotification<UpdateDeleteMessages>.updateDeleteMessages.name,
        ) { [weak self] notification in
            guard let update = TdScopedUpdate<UpdateDeleteMessages>(notification: notification),
                  update.value.isPermanent else { return }
            self?.reloadAfterUpdate(from: update.source, chatID: update.value.chatId)
        }
        nc.publisher(
            &updateCancellables,
            for: TdNotification<UpdateMessageSendSucceeded>.updateMessageSendSucceeded.name,
        ) { [weak self] notification in
            guard let update = TdScopedUpdate<UpdateMessageSendSucceeded>(notification: notification),
                  update.value.message.schedulingState != nil else { return }
            self?.reloadAfterUpdate(from: update.source, chatID: update.value.message.chatId)
        }
    }

    private func reloadAfterUpdate(from source: TdUpdateSource, chatID: Int64) {
        guard let accountID, source == TdUpdateSource(accountID: accountID, clientID: client.id),
              chatID == location.chatID else { return }
        loadMessages()
    }

    /// Telegram's scheduled message menu: Send Now, Reschedule, Copy and Delete.
    private func presentMenu(for message: Message, from cell: UITableViewCell) {
        var actions = [
            TelegramContextMenuAction(
                title: L10n.telegram("ScheduledMessages.SendNow"),
                image: UIImage(systemName: "paperplane"),
            ) { [weak self] in self?.setSchedulingState(nil, of: message) },
            TelegramContextMenuAction(
                title: L10n.telegram("ScheduledMessages.EditTime"),
                image: UIImage(systemName: "calendar.badge.clock"),
            ) { [weak self] in self?.reschedule(message) },
        ]
        if let text = MessageContentPresentation.make(message).formattedText, !text.text.isEmpty {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuCopy"),
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            ) { UIPasteboard.setFormattedText(text) })
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("Common.Delete"),
            image: UIImage(systemName: "trash"),
            isDestructive: true,
            children: [TelegramContextMenuAction(
                title: L10n.telegram("ScheduledMessages.Delete"),
                isDestructive: true,
            ) { [weak self] in self?.delete(message) }],
        ))
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    private func reschedule(_ message: Message) {
        let current: Date? =
            if case .messageSchedulingStateSendAtDate(let state) = message.schedulingState {
                Date(timeIntervalSince1970: TimeInterval(state.sendDate))
            } else {
                nil
            }
        ScheduleMessagePickerViewController.present(
            from: self,
            isReminder: isReminders,
            showsSendWhenOnline: canSendWhenOnline,
            initialDate: current,
        ) { [weak self] state in
            self?.setSchedulingState(state, of: message)
        }
    }

    /// editMessageSchedulingState: nil sends the message now.
    private func setSchedulingState(_ state: TDNativeMessageSchedulingState?, of message: Message) {
        perform { client in
            _ = try await client.send(TDNativeRequests.editMessageSchedulingState(
                chatId: message.chatId,
                messageId: message.id,
                schedulingState: state,
            ))
        } completion: { [weak self] in
            self?.loadMessages()
        }
    }

    private func delete(_ message: Message) {
        perform { client in
            _ = try await client.deleteMessages(chatId: message.chatId, messageIds: [message.id], revoke: true)
        } completion: { [weak self] in
            self?.loadMessages()
        }
    }
}
