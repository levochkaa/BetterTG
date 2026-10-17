// ReportContentViewController.swift

import TDLibKit
import UIKit

// MARK: - ReportContentViewController

/// Telegram's ContentReportScreen for messages and stories. TDLib's `reportChat` or `reportStory` leads through its
/// reason pages: the first request only asks for the reasons, a reason may open more reasons or a comment page, and the
/// report goes out when TDLib accepts a chosen reason or the comment's Send Report. Every request runs on the account
/// that opened the sheet.
final class ReportContentViewController: SettingsListViewController {
    /// ContentReportScreen's subjects BetterTG reports.
    enum Subject {
        case messages(chatID: Int64, messageIDs: [Int64])
        case story(chatID: Int64, storyID: Int)
    }

    enum Page {
        case options(title: String, options: [TDNativeReportOption])
        case comment(optionID: Data, isOptional: Bool)
    }

    /// What TDLib answers to a report request, for either subject.
    private enum Outcome {
        case reported
        case page(Page)
        /// TDLib asked for messages, which are already part of the report.
        case unexpected
    }

    private let subject: Subject
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

    private init(subject: Subject, page: Page, onReported: @escaping () -> Void) {
        self.subject = subject
        self.page = page
        self.onReported = onReported
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title =
            switch subject {
            case .messages: L10n.telegram("Report.Title.Message")
            case .story: L10n.telegram("Report.Title.Story")
            }
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
        guard !messageIDs.isEmpty else { return }
        present(.messages(chatID: chatID, messageIDs: messageIDs), from: presenter, onReported: onReported)
    }

    /// makeContentReportScreen with the `.stories` subject, as the story viewer's Report opens it.
    static func present(
        storyChatID: Int64,
        storyID: Int,
        from presenter: UIViewController,
        onReported: @escaping () -> Void,
    ) {
        present(.story(chatID: storyChatID, storyID: storyID), from: presenter, onReported: onReported)
    }

    private static func present(
        _ subject: Subject,
        from presenter: UIViewController,
        onReported: @escaping () -> Void,
    ) {
        guard let accountID = TDLib.shared.activeAccountID else { return }
        let client = TDLib.shared.activeClient
        Task { @MainActor [weak presenter] in
            let outcome = try? await send(subject, optionID: Data(), text: "", client: client)
            guard let presenter, TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id else { return }
            guard case .page(let page) = outcome, case .options = page else {
                presenter.presentChatListActionFailure()
                return
            }
            let controller = ReportContentViewController(subject: subject, page: page, onReported: onReported)
            presenter.chatListTopPresenter.present(
                TelegramNavigationController(rootViewController: controller),
                animated: true,
            )
        }
    }

    /// `reportChat` for messages and `reportStory` for a story, read as the same pages.
    private static func send(
        _ subject: Subject,
        optionID: Data,
        text: String,
        client: TDLibClient,
    ) async throws -> Outcome {
        switch subject {
        case .messages(let chatID, let messageIDs):
            let result = try await client.send(TDNativeRequests.reportChat(
                chatId: chatID,
                optionId: optionID,
                messageIds: messageIDs,
                text: text,
            ))
            switch result {
            case .reportChatResultOk:
                return .reported
            case .reportChatResultOptionRequired(let required):
                return .page(.options(title: required.title, options: required.options))
            case .reportChatResultTextRequired(let required):
                return .page(.comment(optionID: required.optionId, isOptional: required.isOptional))
            case .reportChatResultMessagesRequired:
                return .unexpected
            }
        case .story(let chatID, let storyID):
            let result = try await client.send(TDNativeRequests.reportStory(
                storyPosterChatId: chatID,
                storyId: storyID,
                optionId: optionID,
                text: text,
            ))
            switch result {
            case .reportStoryResultOk:
                return .reported
            case .reportStoryResultOptionRequired(let required):
                return .page(.options(title: required.title, options: required.options))
            case .reportStoryResultTextRequired(let required):
                return .page(.comment(optionID: required.optionId, isOptional: required.isOptional))
            }
        }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    /// The report with the chosen reason: TDLib accepts it or asks for the next page.
    private func report(optionID: Data, text: String) {
        guard !isSending, contextIsCurrent else { return }
        isSending = true
        reload()
        let client = client
        let subject = subject
        Task { [weak self] in
            do {
                let outcome = try await Self.send(subject, optionID: optionID, text: text, client: client)
                guard let self, contextIsCurrent else { return }
                isSending = false
                reload()
                handle(outcome)
            } catch {
                guard let self, contextIsCurrent else { return }
                isSending = false
                reload()
                presentChatListActionFailure()
            }
        }
    }

    private func handle(_ outcome: Outcome) {
        switch outcome {
        case .reported:
            let onReported = onReported
            let host: UIViewController = navigationController ?? self
            host.dismiss(animated: true) { onReported() }
        case .page(let page):
            show(page)
        case .unexpected:
            // The messages are already part of the report; TDLib asking again is unexpected.
            presentChatListActionFailure()
        }
    }

    private func show(_ page: Page) {
        navigationController?.pushViewController(
            ReportContentViewController(subject: subject, page: page, onReported: onReported),
            animated: true,
        )
    }
}
