// ReportContentViewController.swift

import TDLibKit
import UIKit

// MARK: - ReportContentViewController

/// Telegram's ContentReportScreen for messages. TDLib's `reportChat` leads through its reason pages: the first request
/// only asks for the reasons, a reason may open more reasons or a comment page, and the report goes out when TDLib
/// accepts a chosen reason or the comment's Send Report. Every request runs on the account that opened the sheet.
final class ReportContentViewController: SettingsListViewController {
    enum Page {
        case options(title: String, options: [TDNativeReportOption])
        case comment(optionID: Data, isOptional: Bool)
    }

    private let chatID: Int64
    private let messageIDs: [Int64]
    private let page: Page
    private let onReported: () -> Void
    private var comment = ""
    private var isSending = false

    private var canSendComment: Bool {
        guard case .comment(_, let isOptional) = page else { return false }
        return !isSending && (isOptional || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(chatID: Int64, messageIDs: [Int64], page: Page, onReported: @escaping () -> Void) {
        self.chatID = chatID
        self.messageIDs = messageIDs
        self.page = page
        self.onReported = onReported
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Report.Title.Message")
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: L10n.telegram("Common.Cancel"),
                style: .plain,
                target: self,
                action: #selector(cancel),
            )
        }
    }

    override func makeSections() -> [SettingsSection] {
        switch page {
        case .options(let title, let options):
            return [SettingsSection(header: title, rows: options.map { option in
                SettingsRow(
                    title: option.text,
                    accessory: .disclosure,
                    isEnabled: !isSending,
                ) { [weak self] in
                    self?.report(optionID: option.id, text: "")
                }
            })]
        case .comment(let optionID, let isOptional):
            let input = SettingsTextInput(
                text: comment,
                placeholder: L10n.telegram(isOptional
                    ? "Report.Comment.Placeholder.Optional"
                    : "Report.Comment.Placeholder"),
                isMultiline: true,
            ) { [weak self] text in
                guard let self else { return }
                let couldSend = canSendComment
                comment = text
                if couldSend != canSendComment { reload(sections: IndexSet(integer: 1)) }
            }
            return [
                SettingsSection(
                    footer: L10n.telegram("Report.Comment.Info"),
                    rows: [SettingsRow(title: "", style: .input(input))],
                ),
                SettingsSection(rows: [SettingsRow(
                    title: L10n.telegram("Report.Send"),
                    style: .action(destructive: false),
                    isEnabled: canSendComment,
                ) { [weak self] in
                    guard let self, canSendComment else { return }
                    report(optionID: optionID, text: comment.trimmingCharacters(in: .whitespacesAndNewlines))
                }]),
            ]
        }
    }

    /// makeContentReportScreen: asks TDLib for the reasons and shows the sheet only when it returns them.
    static func present(
        chatID: Int64,
        messageIDs: [Int64],
        from presenter: UIViewController,
        onReported: @escaping () -> Void,
    ) {
        guard let accountID = TDLib.shared.activeAccountID, !messageIDs.isEmpty else { return }
        let client = TDLib.shared.activeClient
        Task { @MainActor [weak presenter] in
            let result = try? await client.send(TDNativeRequests.reportChat(
                chatId: chatID,
                optionId: Data(),
                messageIds: messageIDs,
                text: "",
            ))
            guard let presenter, TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id else { return }
            guard case .reportChatResultOptionRequired(let required) = result else {
                presenter.presentChatListActionFailure()
                return
            }
            let controller = ReportContentViewController(
                chatID: chatID,
                messageIDs: messageIDs,
                page: .options(title: required.title, options: required.options),
                onReported: onReported,
            )
            presenter.chatListTopPresenter.present(
                TelegramNavigationController(rootViewController: controller),
                animated: true,
            )
        }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    /// `reportChat` with the chosen reason: TDLib accepts the report or asks for the next page.
    private func report(optionID: Data, text: String) {
        guard !isSending, contextIsCurrent else { return }
        isSending = true
        reload()
        let client = client
        let chatID = chatID
        let messageIDs = messageIDs
        Task { [weak self] in
            do {
                let result = try await client.send(TDNativeRequests.reportChat(
                    chatId: chatID,
                    optionId: optionID,
                    messageIds: messageIDs,
                    text: text,
                ))
                guard let self, contextIsCurrent else { return }
                isSending = false
                reload()
                handle(result)
            } catch {
                guard let self, contextIsCurrent else { return }
                isSending = false
                reload()
                presentChatListActionFailure()
            }
        }
    }

    private func handle(_ result: TDNativeReportChatResult) {
        switch result {
        case .reportChatResultOk:
            let onReported = onReported
            let host: UIViewController = navigationController ?? self
            host.dismiss(animated: true) { onReported() }
        case .reportChatResultOptionRequired(let required):
            show(.options(title: required.title, options: required.options))
        case .reportChatResultTextRequired(let required):
            show(.comment(optionID: required.optionId, isOptional: required.isOptional))
        case .reportChatResultMessagesRequired:
            // The messages are already part of the report; TDLib asking again is unexpected.
            presentChatListActionFailure()
        }
    }

    private func show(_ page: Page) {
        navigationController?.pushViewController(
            ReportContentViewController(chatID: chatID, messageIDs: messageIDs, page: page, onReported: onReported),
            animated: true,
        )
    }
}
