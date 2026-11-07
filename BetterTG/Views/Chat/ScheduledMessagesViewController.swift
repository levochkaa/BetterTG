// ScheduledMessagesViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ScheduledMessagesViewController

/// Telegram's scheduled messages chat (ChatControllerSubject.scheduledMessages) as a BetterTG list: the chat's or
/// topic's scheduled messages grouped by the day they go out, or "until online". A message's menu sends it now,
/// reschedules it (editMessageSchedulingState), copies its text or deletes it. Saved Messages calls them reminders.
/// A video still being converted goes out on its date once processed: its row says so, and Send Now asks first.
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
        case .messageSchedulingStateSendAtDate,
             .messageSchedulingStateSendWhenVideoProcessed:
            let date = Date(timeIntervalSince1970: TimeInterval(sendDate(of: message)))
            return Calendar.current.isDateInToday(date)
                ? L10n.telegram("ScheduledMessages.ScheduledToday")
                : L10n.telegram("ScheduledMessages.ScheduledDate", dayFormatter.string(from: date))
        case .messageSchedulingStateSendWhenOnline:
            return L10n.telegram("ScheduledMessages.ScheduledOnline")
        default:
            return L10n.telegram("ScheduledMessages.Title")
        }
    }

    /// The time it goes out; a video still processing adds Chat.VideoProcessingInfo, as Telegram's scheduled chat puts
    /// "This video will be published once converted and optimized" over it.
    private static func time(for message: Message) -> String? {
        let date = sendDate(of: message)
        guard date != Int.max else { return nil }
        let time = Date(timeIntervalSince1970: TimeInterval(date)).formatted(date: .omitted, time: .shortened)
        guard isProcessingVideo(message) else { return time }
        return "\(time) · \(L10n.telegram("Chat.VideoProcessingInfo"))"
    }

    private static func sendDate(of message: Message) -> Int {
        switch message.schedulingState {
        case .messageSchedulingStateSendAtDate(let state): state.sendDate
        case .messageSchedulingStateSendWhenVideoProcessed(let state): state.sendDate
        default: Int.max
        }
    }

    private static func isProcessingVideo(_ message: Message) -> Bool {
        if case .messageSchedulingStateSendWhenVideoProcessed = message.schedulingState { return true }
        return false
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
            ) { [weak self] in self?.sendNow(message) },
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

    /// Send Now; a video still being converted first gets "Wait!" with Send Anyway, as Telegram asks.
    private func sendNow(_ message: Message) {
        guard Self.isProcessingVideo(message) else {
            setSchedulingState(nil, of: message)
            return
        }
        let alert = UIAlertController(
            title: L10n.telegram("Chat.ScheduledForceSendProcessingVideo.Title"),
            message: L10n.telegram("Chat.ScheduledForceSendProcessingVideo.Text"),
            preferredStyle: .alert,
        )
        let send = UIAlertAction(
            title: L10n.telegram("Chat.ScheduledForceSendProcessingVideo.Action"), style: .default,
        ) { [weak self] _ in self?.setSchedulingState(nil, of: message) }
        alert.addAction(send)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.preferredAction = send
        present(alert, animated: true)
    }

    private func reschedule(_ message: Message) {
        let date = Self.sendDate(of: message)
        let current: Date? = date == Int.max ? nil : Date(timeIntervalSince1970: TimeInterval(date))
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
