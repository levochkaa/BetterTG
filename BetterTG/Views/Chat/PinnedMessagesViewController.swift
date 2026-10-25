// PinnedMessagesViewController.swift

import TDLibKit
import UIKit

// MARK: - PinnedMessagesViewController

/// Telegram's pinned messages chat (ChatControllerSubject.pinnedMessages) as a BetterTG list, opened from the pinned
/// banner's list button: the pins newest first, titled "N Pinned Messages", with ChatChannelSubscriberInputPanelNode's
/// Unpin All Messages for whoever may manage pins, else Don't Show Pinned Messages. A row returns to the chat at its
/// message; the bottom button returns and lets the chat unpin or hide, as Telegram's requestedUnpinAllMessages and
/// updatedClosedPinnedMessageId do.
final class PinnedMessagesViewController: UIViewController {
    enum Outcome {
        case open(messageID: Int64)
        case unpinAll
        case hide
    }

    private let messages: [Message]
    private let totalCount: Int
    private let canUnpinAll: Bool
    private let client: TDLibClient
    private let accountID: UUID?
    private let onOutcome: (Outcome) -> Void
    /// The banner's long-press preview leaves the actions to its menu (ChatController's `.previewing` mode).
    private let isPreview: Bool
    private let statusPanel = ChatStatusPanelView()
    private lazy var listView = ChatSearchResultsListView(client: client, accountID: accountID) { [weak self] in
        self?.view.window != nil
    }

    init(
        messages: [Message],
        totalCount: Int,
        canUnpinAll: Bool,
        client: TDLibClient,
        accountID: UUID?,
        isPreview: Bool = false,
        onOutcome: @escaping (Outcome) -> Void,
    ) {
        self.isPreview = isPreview
        self.messages = messages
        self.totalCount = totalCount
        self.canUnpinAll = canUnpinAll
        self.client = client
        self.accountID = accountID
        self.onOutcome = onOutcome
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.telegramPlural("Chat.TitlePinnedMessages", count: totalCount)
        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.onSelect = { [weak self] messageID in self?.finish(.open(messageID: messageID)) }
        view.addSubview(listView)
        statusPanel.translatesAutoresizingMaskIntoConstraints = false
        statusPanel.update(
            content: .init(
                title: L10n.telegram(canUnpinAll ? "Chat.PanelUnpinAllMessages" : "Chat.PanelHidePinnedMessages"),
                style: .action(spansWidth: true),
            ),
            animated: false,
        )
        statusPanel.onAction = { [weak self] in
            guard let self else { return }
            finish(canUnpinAll ? .unpinAll : .hide)
        }
        view.addSubview(statusPanel)
        statusPanel.isHidden = isPreview
        NSLayoutConstraint.activate([
            listView.topAnchor.constraint(equalTo: view.topAnchor),
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: statusPanel.topAnchor),
            statusPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusPanel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: isPreview ? 0 : -ChatStatusPanelView.contentHeight,
            ),
        ])
        listView.update(messages: messages, isLoading: false)
    }

    private func finish(_ outcome: Outcome) {
        let onOutcome = onOutcome
        if let navigationController, navigationController.topViewController === self {
            navigationController.popViewController(animated: true)
        }
        onOutcome(outcome)
    }
}
