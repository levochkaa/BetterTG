// ChatWelcomeMessagesViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatWelcomeMessagesViewController

/// Telegram's Welcome Message (WelcomeMessageSetupChatContents) as a BetterTG list: the messages new members see when
/// they join (loadChatWelcomeMessages, kept by updateChatWelcomeMessages), each deleted by its swipe
/// (deleteChatWelcomeMessage), and a field that adds a text message (addChatWelcomeMessage) up to
/// `welcome_message_count_max`. Telegram writes them in a chat whose bubbles and composer take any content; this list
/// shows each as its summary and adds text.
final class ChatWelcomeMessagesViewController: SettingsListViewController {
    private let chatID: Int64
    private var messages: [WelcomeMessage]?
    private var draft = ""
    private var limit = 5
    private var isAdding = false
    private var cancellables = Set<AnyCancellable>()

    /// `messages` is what the opening screen already read: TDLib reports the list again only when it changes.
    init(chatID: Int64, messages: [WelcomeMessage]? = nil) {
        self.chatID = chatID
        self.messages = messages
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("WelcomeMessages.Title")
        // ServiceHeader2's "touch and hold it to delete it".
        tableView.addGestureRecognizer(ContextMenuPressGestureRecognizer(target: self, action: #selector(pressed)))
        let source = TDLib.shared.activeUpdateSource
        nc.scopedPublisher(&cancellables, for: .updateChatWelcomeMessages) { [weak self] event in
            guard let self, event.source == source, event.value.chatId == chatID else { return }
            messages = event.value.messages
            reload()
        }
        let client = client
        let chatID = chatID
        Task { [weak self] in
            if case .optionValueInteger(let value)? = try? await client.send(
                TDNativeRequests.getOption(name: "welcome_message_count_max"),
            ), value.value > 0 {
                self?.limit = Int(value.value)
                self?.reload()
            }
            _ = try? await client.send(TDNativeRequests.loadChatWelcomeMessages(chatId: chatID))
            // A load that changes nothing sends no update: none read means none set.
            guard let self, messages == nil else { return }
            messages = []
            reload()
        }
    }

    override func makeSections() -> [SettingsSection] {
        guard let messages else { return [SettingsSection(rows: [ChatManagementRows.loading])] }
        var sections = [SettingsSection]()
        if messages.isEmpty {
            // ChatEmptyNode's `.welcomeMessages`.
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("WelcomeMessages.EmptyTitle"),
                detail: L10n.telegram("WelcomeMessages.EmptyText"),
                style: .subtitle,
            )]))
        } else {
            sections.append(SettingsSection(
                header: L10n.telegram("WelcomeMessages.ServiceHeader1"),
                footer: L10n.telegram("WelcomeMessages.ServiceHeader2"),
                rows: messages.map { message in
                    var row = SettingsRow(
                        title: MessageContentPresentation.make(message.content).summary,
                        style: .subtitle,
                    )
                    row.swipeAction = (L10n.telegram("Common.Delete"), { [weak self] in self?.delete(message.id) })
                    return row
                },
            ))
        }
        if messages.count >= limit {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegramPlural("WelcomeMessages.MessageLimitReachedText", count: limit),
                style: .status(.secondaryLabel),
            )]))
            return sections
        }
        sections.append(SettingsSection(rows: [
            SettingsRow(title: "", style: .input(SettingsTextInput(
                text: draft,
                placeholder: L10n.telegram("Conversation.InputTextPlaceholder"),
                maxLength: 4096,
            ) { [weak self] text in self?.draft = text })),
            SettingsRow(
                title: L10n.telegram("ShareMenu.Send"),
                style: .action(destructive: false),
                isEnabled: !isAdding,
            ) { [weak self] in self?.add() },
        ]))
        return sections
    }

    /// The first message's summary, as PeerInfoData's firstWelcomeMessageText labels the edit screen's row.
    static func label(_ messages: [WelcomeMessage]?) -> String {
        messages?.first.map { MessageContentPresentation.make($0.content).summary }
            ?? L10n.telegram("WelcomeMessages.Off")
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAdding, contextIsCurrent else { return }
        isAdding = true
        reload()
        let client = client
        let chatID = chatID
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.addChatWelcomeMessage(
                    chatId: chatID,
                    inputMessageContent: .inputMessageText(InputMessageText(
                        clearDraft: false,
                        linkPreviewOptions: nil,
                        text: FormattedText(entities: [], text: text),
                    )),
                ))
                guard let self else { return }
                isAdding = false
                draft = ""
                reload()
                _ = try? await client.send(TDNativeRequests.loadChatWelcomeMessages(chatId: chatID))
            } catch {
                guard let self else { return }
                isAdding = false
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    @objc private func pressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, contextIsCurrent, let messages, !messages.isEmpty,
              let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)),
              indexPath.section == 0, let message = messages[safe: indexPath.row],
              let cell = tableView.cellForRow(at: indexPath)
        else { return }
        presentTelegramContextMenu(
            sourceView: cell,
            actions: [TelegramContextMenuAction(
                title: L10n.telegram("Common.Delete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.delete(message.id) }],
            tracking: gesture,
        )
    }

    private func delete(_ id: Int) {
        guard contextIsCurrent else { return }
        let client = client
        let chatID = chatID
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.deleteChatWelcomeMessage(
                    chatId: chatID,
                    welcomeMessageId: id,
                ))
                _ = try? await client.send(TDNativeRequests.loadChatWelcomeMessages(chatId: chatID))
            } catch {
                guard let self, contextIsCurrent else { return }
                presentAlert(title: nil, message: ChatManagementRows.failureText(error))
            }
        }
    }
}
