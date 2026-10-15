// MessageInteractionsViewController.swift

import TDLibKit
import UIKit

// MARK: - MessageInteractionsViewController

/// Telegram's read receipts and reactions lists from the message menu (ChatMessageContextMenu's "N Seen" and
/// "N reactions" items): who saw a message in a small group (`getMessageViewers`) with the time, or who reacted
/// (`getMessageAddedReactions`, in pages) with the reaction and the time.
final class MessageInteractionsViewController: SettingsListViewController {
    enum Kind {
        case viewers
        /// `count` is the message's reaction total, the title until TDLib returns its own.
        case reactions(isOutgoing: Bool, count: Int)
    }

    private struct Entry {
        let peer: SettingsPeer
        let detail: String
    }

    private static let pageSize = 50

    private let kind: Kind
    private let chatID: Int64
    private let messageID: Int64
    private var entries = [Entry]()
    private var totalCount: Int?
    private var nextOffset: String?
    private var isLoading = false

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(kind: Kind, chatID: Int64, messageID: Int64) {
        self.kind = kind
        self.chatID = chatID
        self.messageID = messageID
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Close"),
            style: .plain,
            target: self,
            action: #selector(close),
        )
        updateTitle()
        loadMore()
    }

    override func makeSections() -> [SettingsSection] {
        var rows = entries.map { entry in
            SettingsRow(title: entry.peer.title, detail: entry.detail, style: .peer(entry.peer))
        }
        if isLoading || totalCount == nil {
            rows.append(SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            ))
        } else if rows.isEmpty {
            rows.append(SettingsRow(
                title: L10n.telegram("Conversation.ContextMenuNoViews"),
                style: .status(.secondaryLabel),
            ))
        }
        return [SettingsSection(rows: rows)]
    }

    override func tableView(_ tableView: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= tableView.numberOfRows(inSection: indexPath.section) - 5 else { return }
        loadMore()
    }

    static func present(_ kind: Kind, chatID: Int64, messageID: Int64, from presenter: UIViewController) {
        let controller = MessageInteractionsViewController(kind: kind, chatID: chatID, messageID: messageID)
        let navigation = TelegramNavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.chatListTopPresenter.present(navigation, animated: true)
    }

    private static func emoji(of type: TDNativeReactionType) -> String {
        if case .reactionTypeEmoji(let value) = type { return value.emoji }
        return ""
    }

    /// Telegram's read time: today or yesterday at a time, or the date and time.
    private static func timeText(_ timestamp: Int) -> String {
        guard timestamp > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L10n.telegram("Time.TodayAt", time) }
        if calendar.isDateInYesterday(date) { return L10n.telegram("Time.YesterdayAt", time) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func updateTitle() {
        title =
            switch kind {
            case .viewers:
                totalCount.map { L10n.telegramPlural("Conversation.ContextMenuSeen", count: $0) }
                    ?? L10n.betterTG("Message.SeenBy")
            case .reactions(let isOutgoing, let count):
                L10n.telegramPlural(
                    isOutgoing ? "Chat.OutgoingContextReactionCount" : "Chat.ContextReactionCount",
                    count: totalCount ?? count,
                )
            }
    }

    private func loadMore() {
        guard !isLoading, contextIsCurrent else { return }
        switch kind {
        case .viewers:
            guard totalCount == nil else { return }
        case .reactions:
            guard totalCount == nil || nextOffset?.isEmpty == false else { return }
        }
        isLoading = true
        let client = client
        let chatID = chatID
        let messageID = messageID
        let kind = kind
        let offset = nextOffset ?? ""
        Task { [weak self] in
            var loaded = [Entry]()
            var count = 0
            var next: String?
            switch kind {
            case .viewers:
                let viewers = try? await client.send(TDNativeRequests.getMessageViewers(
                    chatId: chatID,
                    messageId: messageID,
                ))
                for viewer in viewers?.viewers ?? [] {
                    if let peer = await SettingsPeer.user(viewer.userId, client: client) {
                        loaded.append(Entry(peer: peer, detail: Self.timeText(viewer.viewDate)))
                    }
                }
                count = viewers?.viewers.count ?? 0
            case .reactions:
                let page = try? await client.send(TDNativeRequests.getMessageAddedReactions(
                    chatId: chatID,
                    messageId: messageID,
                    reactionType: nil,
                    offset: offset,
                    limit: Self.pageSize,
                ))
                for reaction in page?.reactions ?? [] {
                    if let peer = await SettingsPeer.resolve(reaction.senderId, client: client) {
                        let detail = [Self.emoji(of: reaction.type), Self.timeText(reaction.date)]
                            .filter { !$0.isEmpty }
                            .joined(separator: "  ")
                        loaded.append(Entry(peer: peer, detail: detail))
                    }
                }
                count = page?.totalCount ?? 0
                next = page?.nextOffset ?? ""
            }
            guard let self, contextIsCurrent else { return }
            isLoading = false
            entries += loaded
            totalCount = max(count, entries.count)
            nextOffset = next
            updateTitle()
            reload()
        }
    }
}
