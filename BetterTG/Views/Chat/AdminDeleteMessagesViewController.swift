// AdminDeleteMessagesViewController.swift

import TDLibKit
import UIKit

// MARK: - AdminDeleteMessagesViewController

/// Telegram's AdminUserActionsSheet for an admin deleting another member's messages in a group: the messages are
/// deleted for everyone, with Report Spam, Delete All from the sender and Ban the sender as extra choices. Nothing
/// happens until Proceed; then the choices run in Telegram's order (applyAdminUserActionsResult).
final class AdminDeleteMessagesViewController: SettingsListViewController {
    struct Request {
        let chatID: Int64
        let supergroupID: Int64
        let messageIDs: [Int64]
        let sender: MessageSender
        let canDeleteAll: Bool
        let canBan: Bool
    }

    private let request: Request
    /// The toast text Telegram shows after the actions.
    private let onFinished: (String) -> Void
    private var senderName = ""
    private var reportsSpam = false
    private var deletesAll = false
    private var bans = false
    private var isRunning = false

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(request: Request, onFinished: @escaping (String) -> Void) {
        self.request = request
        self.onFinished = onFinished
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegramPlural("Chat.AdminActionSheet.DeleteTitle", count: request.messageIDs.count)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancel),
        )
        loadSenderName()
    }

    override func makeSections() -> [SettingsSection] {
        var rows =
            [option(L10n.telegram("Chat.AdminActionSheet.ReportSpam"), isOn: reportsSpam) { $0.reportsSpam.toggle() }]
        if request.canDeleteAll {
            rows.append(option(
                L10n.telegram("Chat.AdminActionSheet.DeleteAllSingle", senderName),
                isOn: deletesAll,
            ) { $0.deletesAll.toggle() })
        }
        if request.canBan {
            rows.append(option(L10n.telegram("Chat.AdminActionSheet.BanSingle", senderName), isOn: bans) {
                $0.bans.toggle()
            })
        }
        return [
            SettingsSection(
                header: L10n.telegram("Chat.AdminActionSheet.RestrictSectionHeader"),
                footer: bans ? L10n.telegram("Chat.AdminActionSheet.BanFooterSingle") : nil,
                rows: rows,
            ),
            SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Chat.AdminActionSheet.ActionButton"),
                style: .action(destructive: true),
                accessory: isRunning ? .activity : .none,
                isEnabled: !isRunning,
            ) { [weak self] in self?.proceed() }]),
        ]
    }

    static func present(_ request: Request, from presenter: UIViewController, onFinished: @escaping (String) -> Void) {
        let navigation = TelegramNavigationController(
            rootViewController: AdminDeleteMessagesViewController(request: request, onFinished: onFinished),
        )
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.chatListTopPresenter.present(navigation, animated: true)
    }

    private func option(
        _ title: String,
        isOn: Bool,
        toggle: @escaping (AdminDeleteMessagesViewController) -> Void,
    ) -> SettingsRow {
        SettingsRow(title: title, accessory: isOn ? .checkmark : .none, isEnabled: !isRunning) { [weak self] in
            guard let self else { return }
            toggle(self)
            reload()
        }
    }

    /// Telegram names the sender by the short name: a person's first name or the chat's title.
    private func loadSenderName() {
        let client = client
        let sender = request.sender
        Task { [weak self] in
            var name: String?
            switch sender {
            case .messageSenderUser(let user):
                if let found = try? await client.getUser(userId: user.userId) {
                    name = found.firstName.isEmpty ? found.lastName : found.firstName
                }
            case .messageSenderChat(let chat):
                name = try? await client.getChat(chatId: chat.chatId).title
            }
            guard let self, contextIsCurrent, let name, !name.isEmpty else { return }
            senderName = name
            reload()
        }
    }

    @objc private func cancel() {
        guard !isRunning else { return }
        dismiss(animated: true)
    }

    /// applyAdminUserActionsResult: delete for everyone, then delete the sender's other messages, report spam and
    /// ban, as chosen. The toast lists what happened.
    private func proceed() {
        guard !isRunning, contextIsCurrent else { return }
        isRunning = true
        reload()
        let request = request
        let reportsSpam = reportsSpam
        let deletesAll = deletesAll
        let bans = bans
        let client = client
        Task { [weak self] in
            var deleted = await (try? client.deleteMessages(
                chatId: request.chatID,
                messageIds: request.messageIDs,
                revoke: true,
            )) != nil
            if deletesAll {
                let all = try? await client.send(TDNativeRequests.deleteChatMessagesBySender(
                    chatId: request.chatID,
                    senderId: request.sender,
                ))
                deleted = deleted || all != nil
            }
            var reported = false
            if reportsSpam {
                reported = await (try? client.send(TDNativeRequests.reportSupergroupSpam(
                    supergroupId: request.supergroupID,
                    messageIds: request.messageIDs,
                ))) != nil
            }
            var banned = false
            if bans {
                banned = await (try? client.send(TDNativeRequests.banChatMember(
                    chatId: request.chatID,
                    memberId: request.sender,
                    bannedUntilDate: 0,
                    revokeMessages: false,
                ))) != nil
            }
            guard let self, contextIsCurrent else { return }
            isRunning = false
            guard deleted || reported || banned else {
                reload()
                presentChatListActionFailure()
                return
            }
            var lines = [String]()
            if reported { lines.append(L10n.telegramPlural("Chat.AdminAction.ToastReportedSpamText", count: 1)) }
            if banned { lines.append(L10n.telegramPlural("Chat.AdminAction.ToastBannedText", count: 1)) }
            let isMultiple = request.messageIDs.count > 1 || deletesAll
            let text =
                if lines.isEmpty {
                    L10n.telegram(isMultiple
                        ? "Chat.AdminAction.ToastMessagesDeletedTextMultiple"
                        : "Chat.AdminAction.ToastMessagesDeletedTextSingle")
                } else {
                    ([L10n.telegram(isMultiple
                            ? "Chat.AdminAction.ToastMessagesDeletedTitleMultiple"
                            : "Chat.AdminAction.ToastMessagesDeletedTitleSingle")] + lines)
                        .joined(separator: "\n")
                }
            let onFinished = onFinished
            dismiss(animated: true) { onFinished(text.withoutTelegramMarkup) }
        }
    }
}
