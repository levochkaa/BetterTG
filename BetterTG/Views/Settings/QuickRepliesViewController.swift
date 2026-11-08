// QuickRepliesViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - QuickReplyStore

/// The account's quick reply shortcuts and their messages, kept from updateQuickReplyShortcut(s),
/// updateQuickReplyShortcutDeleted and updateQuickReplyShortcutMessages, as Telegram's shortcut message list view.
@MainActor final class QuickReplyStore {
    struct Account {
        var clientID: Int32
        var order = [Int]()
        var shortcuts = [Int: TDNativeQuickReplyShortcut]()
        var messages = [Int: [TDNativeQuickReplyMessage]]()
    }

    static let shared = QuickReplyStore()

    let changes = PassthroughSubject<Void, Never>()

    private var accounts = [UUID: Account]()

    /// A message's line in the list: its text, or what it is with its caption.
    static func preview(_ content: MessageContent) -> String {
        if case .messageText(let text) = content { return text.text.text }
        let summary = MessageContentPresentation.make(content).summary
        let caption: String? =
            switch content {
            case .messagePhoto(let photo): photo.caption.text
            case .messageVideo(let video): video.caption.text
            case .messageDocument(let document): document.caption.text
            case .messageAudio(let audio): audio.caption.text
            case .messageAnimation(let animation): animation.caption.text
            default: nil
            }
        guard let caption, !caption.isEmpty else { return summary }
        return "\(summary), \(caption)"
    }

    func receive(_ update: TDNativeUpdateQuickReplyShortcut, source: TdUpdateSource) {
        modify(source) { account in
            account.shortcuts[update.shortcut.id] = update.shortcut
            if !account.order.contains(update.shortcut.id) { account.order.append(update.shortcut.id) }
        }
    }

    func receive(_ update: TDNativeUpdateQuickReplyShortcutDeleted, source: TdUpdateSource) {
        modify(source) { account in
            account.shortcuts[update.shortcutId] = nil
            account.messages[update.shortcutId] = nil
            account.order.removeAll { $0 == update.shortcutId }
        }
    }

    func receive(_ update: TDNativeUpdateQuickReplyShortcuts, source: TdUpdateSource) {
        modify(source) { account in account.order = update.shortcutIds }
    }

    func receive(_ update: TDNativeUpdateQuickReplyShortcutMessages, source: TdUpdateSource) {
        modify(source) { account in account.messages[update.shortcutId] = update.messages }
    }

    /// The shortcuts in the account's order.
    func shortcuts(for source: TdUpdateSource?) -> [TDNativeQuickReplyShortcut] {
        guard let account = account(source) else { return [] }
        return account.order.compactMap { account.shortcuts[$0] }
    }

    func messages(shortcutID: Int, source: TdUpdateSource?) -> [TDNativeQuickReplyMessage]? {
        account(source)?.messages[shortcutID]
    }

    private func account(_ source: TdUpdateSource?) -> Account? {
        guard let source, let account = accounts[source.accountID], account.clientID == source.clientID else {
            return nil
        }
        return account
    }

    private func modify(_ source: TdUpdateSource, _ change: (inout Account) -> Void) {
        var account = accounts[source.accountID]
        if account?.clientID != source.clientID { account = Account(clientID: source.clientID) }
        guard var account else { return }
        change(&account)
        accounts[source.accountID] = account
        changes.send()
    }
}

// MARK: - QuickRepliesViewController

/// QuickReplySetupScreen: New Quick Reply, which asks for a shortcut and opens it, then each shortcut as /name with
/// its first message and how many follow. A shortcut opens its messages; holding it offers Edit Shortcut and Delete,
/// and swiping deletes it after Delete Quick Reply.
final class QuickRepliesViewController: SettingsListViewController {
    private var cancellable: AnyCancellable?

    private var shortcuts: [TDNativeQuickReplyShortcut] {
        QuickReplyStore.shared.shortcuts(for: TDLib.shared.activeUpdateSource)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("QuickReply.Title")
        cancellable = QuickReplyStore.shared
            .changes
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
        let client = client
        Task { _ = try? await client.send(TDNativeRequests.loadQuickReplyShortcuts()) }
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("QuickReply.InlineCreateAction"),
            style: .action(destructive: false),
            symbol: "plus.bubble",
        ) { [weak self] in self?.create() }])]
        let shortcuts = shortcuts
        guard !shortcuts.isEmpty else { return sections }
        sections.append(SettingsSection(rows: shortcuts.map { shortcut in
            let more = shortcut.messageCount > 1 ? " · +\(shortcut.messageCount - 1)" : ""
            return SettingsRow(
                title: "/" + shortcut.name,
                detail: QuickReplyStore.preview(shortcut.firstMessage.content) + more,
                style: .subtitle,
                accessory: .disclosure,
                action: { [weak self] in self?.open(name: shortcut.name, id: shortcut.id) },
                swipeAction: (L10n.telegram("Common.Delete"), { [weak self] in self?.confirmDelete(shortcut) }),
            )
        }))
        return sections
    }

    /// The shortcut's holding menu: Edit Shortcut and Delete.
    override func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == 1, let shortcut = shortcuts[safe: indexPath.row] else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: L10n.telegram("QuickReply.EditShortcutTitle"),
                    image: UIImage(systemName: "pencil"),
                ) { _ in self?.rename(shortcut) },
                UIAction(
                    title: L10n.telegram("Common.Delete"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive,
                ) { _ in self?.confirmDelete(shortcut) },
            ])
        })
    }

    private func open(name: String, id: Int?) {
        navigationController?.pushViewController(
            QuickReplyEditViewController(name: name, shortcutID: id),
            animated: true,
        )
    }

    private func create() {
        askName(
            title: L10n.telegram("QuickReply.CreateShortcutTitle"),
            message: L10n.telegram("QuickReply.CreateShortcutText"),
            value: "",
        ) { [weak self] name in self?.open(name: name, id: nil) }
    }

    private func rename(_ shortcut: TDNativeQuickReplyShortcut) {
        askName(
            title: L10n.telegram("QuickReply.EditShortcutTitle"),
            message: L10n.telegram("QuickReply.EditShortcutText"),
            value: shortcut.name,
        ) { [weak self] name in
            guard name != shortcut.name else { return }
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.setQuickReplyShortcutName(
                    shortcutId: shortcut.id,
                    name: name,
                ))
            } completion: {}
        }
    }

    /// quickReplyNameAlertController: the shortcut, up to 32 characters, unique among the account's shortcuts and
    /// valid for TDLib (checkQuickReplyShortcutName).
    private func askName(title: String, message: String, value: String, apply: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = value
            field.placeholder = L10n.telegram("QuickReply.ShortcutPlaceholder")
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Done"), style: .default) { [
            weak self,
            weak alert,
        ] _ in
            guard let self else { return }
            let name = String((alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces).prefix(32))
            guard !name.isEmpty else { return }
            if name.lowercased() != value.lowercased(),
               shortcuts.contains(where: { $0.name.lowercased() == name.lowercased() })
            {
                TelegramUndoToast.show(
                    text: L10n.telegram("QuickReply.ShortcutExistsInlineError"),
                    in: view,
                    bottomInset: 12,
                    undo: nil,
                )
                return
            }
            let client = client
            Task { [weak self] in
                do {
                    _ = try await client.send(TDNativeRequests.checkQuickReplyShortcutName(name: name))
                    apply(name)
                } catch {
                    guard let self else { return }
                    TelegramUndoToast.show(text: "\(error)", in: view, bottomInset: 12, undo: nil)
                }
            }
        })
        present(alert, animated: true)
    }

    /// openDeleteShortcuts: Delete Quick Reply over Cancel.
    private func confirmDelete(_ shortcut: TDNativeQuickReplyShortcut) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: L10n.telegram("QuickReply.DeleteConfirmationSingle"),
            style: .destructive,
        ) { [weak self] _ in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.deleteQuickReplyShortcut(shortcutId: shortcut.id))
            } completion: {}
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        let row = shortcuts.firstIndex { $0.id == shortcut.id }
        sheet.popoverPresentationController?.sourceView =
            row.flatMap { tableView.cellForRow(at: IndexPath(row: $0, section: 1)) } ?? view
        present(sheet, animated: true)
    }
}

// MARK: - QuickReplyEditViewController

/// A shortcut's messages, in place of Telegram's chat-style editor: New Quick Reply's two hints while it is empty,
/// then each message, which a tap edits (editQuickReplyMessage, for text) and a swipe deletes
/// (deleteQuickReplyShortcutMessages), and a field whose Add sends a text message to the shortcut
/// (addQuickReplyShortcutMessage), creating it with the first one.
final class QuickReplyEditViewController: SettingsListViewController {
    private let name: String
    private let displayTitle: String?
    private var shortcutID: Int?
    private var draft = ""
    private var cancellable: AnyCancellable?

    private var messages: [TDNativeQuickReplyMessage] {
        shortcutID.flatMap { QuickReplyStore.shared.messages(shortcutID: $0, source: TDLib.shared.activeUpdateSource) }
            ?? []
    }

    /// `displayTitle` names the greeting and away messages, which live in the hello and away shortcuts.
    init(name: String, shortcutID: Int?, displayTitle: String? = nil) {
        self.name = name
        self.shortcutID = shortcutID
        self.displayTitle = displayTitle
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = displayTitle ?? "/" + name
        cancellable = QuickReplyStore.shared
            .changes
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.storeChanged() }
        loadMessages()
    }

    override func makeSections() -> [SettingsSection] {
        let messages = messages
        let hints = [
            L10n.telegram("Chat.EmptyState.QuickReply.Text1", name),
            L10n.telegram("Chat.EmptyState.QuickReply.Text2"),
        ]
            .map(\.withoutTelegramMarkup)
            .joined(separator: "\n")
        return [
            SettingsSection(
                header: messages.isEmpty ? L10n.telegram("Chat.EmptyState.QuickReply.Title").uppercased() : nil,
                footer: messages.isEmpty ? hints : L10n.telegram("Chat.QuickReply.ServiceHeader2"),
                rows: messages.map { message in
                    let isText =
                        if case .messageText = message.content {
                            true
                        } else {
                            false
                        }
                    return SettingsRow(
                        title: QuickReplyStore.preview(message.content),
                        action: isText && message.canBeEdited ? { [weak self] in self?.edit(message) } : nil,
                        swipeAction: (L10n.telegram("Common.Delete"), { [weak self] in self?.delete(message) }),
                    )
                },
            ),
            SettingsSection(rows: [
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: draft,
                    placeholder: L10n.telegram("Conversation.InputTextPlaceholder"),
                    maxLength: 4096,
                    isMultiline: true,
                ) { [weak self] text in self?.draft = text })),
                SettingsRow(
                    title: L10n.telegram("ShareMenu.Send"),
                    style: .action(destructive: false),
                    symbol: "arrow.up.circle.fill",
                ) { [weak self] in self?.add() },
            ]),
        ]
    }

    private func loadMessages() {
        guard let shortcutID else { return }
        let client = client
        Task { _ = try? await client.send(TDNativeRequests.loadQuickReplyShortcutMessages(shortcutId: shortcutID)) }
    }

    /// A new shortcut gets its identifier once its first message lands, and TDLib swaps its temporary one for the
    /// server's when that is saved; the name finds it either way.
    private func storeChanged() {
        let shortcuts = QuickReplyStore.shared.shortcuts(for: TDLib.shared.activeUpdateSource)
        if !shortcuts.contains(where: { $0.id == shortcutID }),
           let shortcut = shortcuts.first(where: { $0.name == name })
        {
            shortcutID = shortcut.id
            loadMessages()
        }
        reload(sections: IndexSet(integer: 0))
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        view.endEditing(true)
        reload()
        let name = name
        perform { client in
            _ = try await client.send(TDNativeRequests.addQuickReplyShortcutMessage(
                shortcutName: name,
                replyToMessageId: 0,
                inputMessageContent: .inputMessageText(InputMessageText(
                    clearDraft: false,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: text),
                )),
            ))
        } completion: {}
    }

    private func edit(_ message: TDNativeQuickReplyMessage) {
        guard let shortcutID, case .messageText(let current) = message.content else { return }
        let alert = UIAlertController(title: L10n.telegram("Common.Edit"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = current.text.text }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Done"), style: .default) { [
            weak self,
            weak alert,
        ] _ in
            let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != current.text.text else { return }
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.editQuickReplyMessage(
                    shortcutId: shortcutID,
                    messageId: message.id,
                    inputMessageContent: .inputMessageText(InputMessageText(
                        clearDraft: false,
                        linkPreviewOptions: nil,
                        text: FormattedText(entities: [], text: text),
                    )),
                ))
            } completion: {}
        })
        present(alert, animated: true)
    }

    private func delete(_ message: TDNativeQuickReplyMessage) {
        guard let shortcutID else { return }
        perform { client in
            _ = try await client.send(TDNativeRequests.deleteQuickReplyShortcutMessages(
                shortcutId: shortcutID,
                messageIds: [message.id],
            ))
        } completion: {}
    }
}
