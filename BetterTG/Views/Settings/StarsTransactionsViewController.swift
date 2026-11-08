// StarsTransactionsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - StarsBalanceStore

/// updateOwnedStarCount for each account's client: the Stars the account owns, which Settings shows beside Your Stars.
@MainActor final class StarsBalanceStore {
    static let shared = StarsBalanceStore()

    let changes = PassthroughSubject<Void, Never>()

    private var balances = [UUID: (clientID: Int32, amount: StarAmount)]()

    /// formatStarsAmountText: whole Stars grouped, with up to two decimals of nanostars.
    static func text(_ amount: StarAmount) -> String {
        let value = Double(amount.starCount) + Double(amount.nanostarCount) / 1_000_000_000
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    func receive(_ update: UpdateOwnedStarCount, source: TdUpdateSource) {
        balances[source.accountID] = (source.clientID, update.starAmount)
        changes.send()
    }

    func balance(for source: TdUpdateSource?) -> StarAmount? {
        guard let source, let entry = balances[source.accountID], entry.clientID == source.clientID else { return nil }
        return entry.amount
    }
}

// MARK: - StarsTransactionsViewController

/// Telegram's StarsTransactionsScreen for the account: the star over Telegram Stars and the balance, then All
/// Transactions, Incoming and Outgoing (getStarTransactions), each row the peer or the service it was with, what it
/// was for and when, and the amount in green for Stars received or in red for Stars spent. BetterTG sells
/// no Stars, so the screen has no Buy or Gift buttons.
final class StarsTransactionsViewController: SettingsListViewController {
    struct Row {
        let id: String
        let title: String
        let subtitle: String?
        let date: String
        let timestamp: Int
        let amount: StarAmount
        let isRefund: Bool
        let peer: SettingsPeer?
        /// The peer the Stars went to or came from, which the details name.
        let counterpart: SettingsPeer?
        let symbol: String?

        var isIncome: Bool {
            amount.starCount > 0 || (amount.starCount == 0 && amount.nanostarCount > 0)
        }
    }

    private enum PeerID {
        case user(Int64)
        case chat(Int64)
    }

    private static let pageSize = 50

    private var balance: StarAmount?
    private var direction: TDNativeTransactionDirection?
    private var rows = [Row]()
    private var nextOffset: String?
    private var isLoading = false
    private var generation = 0
    private var peers = [Int64: SettingsPeer]()
    private let segments = UISegmentedControl(items: [
        L10n.telegram("Stars.Intro.AllTransactions"),
        L10n.telegram("Stars.Intro.Incoming"),
        L10n.telegram("Stars.Intro.Outgoing"),
    ])
    private let balanceLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Stars.Intro.Title")
        tableView.tableHeaderView = makeHeader()
        load(reset: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        guard abs(header.frame.height - size.height) > 0.5 || abs(header.frame.width - tableView.bounds.width) > 0.5
        else { return }
        header.frame.size = CGSize(width: tableView.bounds.width, height: size.height)
        tableView.tableHeaderView = header
    }

    override func makeSections() -> [SettingsSection] {
        guard !rows.isEmpty else {
            return isLoading ? [SettingsSection(rows: [ChatManagementRows.loading])] : []
        }
        return [SettingsSection(rows: rows.map { row in
            SettingsRow(
                title: row.title,
                detail: [row.subtitle, row.date].compactMap(\.self).joined(separator: "\n"),
                style: row.peer.map { .peer($0) } ?? .subtitle,
                symbol: row.peer == nil ? row.symbol : nil,
                action: { [weak self] in self?.openDetails(row) },
                trailingView: Self.amountView(row.amount, isRefund: row.isRefund),
            )
        })]
    }

    /// The list pages in more transactions near its end.
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard nextOffset?.isEmpty == false, !isLoading,
              scrollView.contentOffset.y > scrollView.contentSize.height - scrollView.bounds.height * 2
        else { return }
        load(reset: false)
    }

    /// The amount with its sign and a star: green for Stars received, red for Stars spent.
    static func amountView(_ amount: StarAmount, isRefund _: Bool) -> SettingsTrailingView {
        SettingsTrailingView {
            let isIncome = amount.starCount > 0 || (amount.starCount == 0 && amount.nanostarCount > 0)
            let label = UILabel()
            let sign = isIncome ? "+" : "−"
            let magnitude = StarAmount(
                nanostarCount: abs(amount.nanostarCount),
                starCount: abs(amount.starCount),
            )
            let text = NSMutableAttributedString(
                string: sign + StarsBalanceStore.text(magnitude) + " ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 17, weight: .medium),
                    .foregroundColor: isIncome ? UIColor.systemGreen : UIColor.systemRed,
                ],
            )
            let star = NSTextAttachment(image: UIImage(systemName: "star.fill")?
                .withTintColor(.systemOrange, renderingMode: .alwaysOriginal) ?? UIImage())
            text.append(NSAttributedString(attachment: star))
            label.attributedText = text
            return label
        }
    }

    /// The transaction's peer and wording: a title for the services, otherwise the peer's name over the subtitle.
    private static func describe(
        _ type: TDNativeStarTransactionType,
    ) -> (peer: PeerID?, title: String?, subtitle: String?, symbol: String?) {
        let gift = L10n.telegram("Stars.Intro.Transaction.Gift")
        func sender(_ id: TDNativeMessageSender) -> PeerID {
            switch id {
            case .messageSenderUser(let user): .user(user.userId)
            case .messageSenderChat(let chat): .chat(chat.chatId)
            }
        }
        switch type {
        case .starTransactionTypePremiumBotDeposit:
            return (
                nil,
                L10n.telegram("Stars.Intro.Transaction.PremiumBotTopUp.Title"),
                L10n.telegram("Stars.Intro.Transaction.PremiumBotTopUp.Subtitle"),
                "star.circle.fill",
            )
        case .starTransactionTypeAppStoreDeposit:
            return (
                nil,
                L10n.telegram("Stars.Intro.Transaction.AppleTopUp.Title"),
                L10n.telegram("Stars.Intro.Transaction.AppleTopUp.Subtitle"),
                "applelogo",
            )
        case .starTransactionTypeGooglePlayDeposit:
            return (
                nil,
                L10n.telegram("Stars.Intro.Transaction.GoogleTopUp.Title"),
                L10n.telegram("Stars.Intro.Transaction.GoogleTopUp.Subtitle"),
                "play.circle.fill",
            )
        case .starTransactionTypeFragmentDeposit:
            return (
                nil,
                L10n.telegram("Stars.Intro.Transaction.FragmentTopUp.Title"),
                L10n.telegram("Stars.Intro.Transaction.FragmentTopUp.Subtitle"),
                "diamond.fill",
            )
        case .starTransactionTypeFragmentWithdrawal:
            return (
                nil,
                L10n.telegram("Stars.Intro.Transaction.FragmentWithdrawal.Title"),
                L10n.telegram("Stars.Intro.Transaction.FragmentWithdrawal.Subtitle"),
                "diamond.fill",
            )
        case .starTransactionTypeTelegramAdsWithdrawal:
            return (
                nil,
                L10n.telegram("Stars.Intro.Transaction.TelegramAds.Title"),
                L10n.telegram("Stars.Intro.Transaction.TelegramAds.Subtitle"),
                "megaphone.fill",
            )
        case .starTransactionTypeTelegramApiUsage:
            return (nil, L10n.telegram("Stars.Intro.Transaction.TelegramBotApi.Title"), nil, "paperplane.fill")
        case .starTransactionTypePublicPostSearch:
            return (nil, L10n.telegram("Stars.Intro.Transaction.SearchFee"), nil, "magnifyingglass")
        case .starTransactionTypeUnsupported:
            return (nil, L10n.telegram("Stars.Intro.Transaction.Unsupported.Title"), nil, "questionmark.circle")
        case .starTransactionTypeUserDeposit(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.Gift.Title"), nil)
        case .starTransactionTypeGiveawayDeposit(let value):
            return (.chat(value.chatId), nil, L10n.telegram("Stars.Intro.Transaction.GiveawayPrize"), nil)
        case .starTransactionTypeBotPaidMediaPurchase(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.MediaPurchase"), nil)
        case .starTransactionTypeBotPaidMediaSale(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.MediaPurchase"), nil)
        case .starTransactionTypeChannelPaidMediaPurchase(let value):
            return (.chat(value.chatId), nil, L10n.telegram("Stars.Intro.Transaction.MediaPurchase"), nil)
        case .starTransactionTypeChannelPaidMediaSale(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.MediaPurchase"), nil)
        case .starTransactionTypeBotInvoicePurchase(let value):
            return (.user(value.userId), nil, value.productInfo.title, nil)
        case .starTransactionTypeBotInvoiceSale(let value):
            return (.user(value.userId), nil, value.productInfo.title, nil)
        case .starTransactionTypeBotSubscriptionPurchase(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.SubscriptionFee.Title"), nil)
        case .starTransactionTypeBotSubscriptionSale(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.SubscriptionFee.Title"), nil)
        case .starTransactionTypeChannelSubscriptionPurchase(let value):
            return (.chat(value.chatId), nil, L10n.telegram("Stars.Intro.Transaction.SubscriptionFee.Title"), nil)
        case .starTransactionTypeChannelSubscriptionSale(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.SubscriptionFee.Title"), nil)
        case .starTransactionTypeGiftAuctionBid(let value):
            return (sender(value.ownerId), nil, L10n.telegram("Stars.Intro.Transaction.GiftAuctionBid"), nil)
        case .starTransactionTypeGiftPurchase(let value):
            return (sender(value.ownerId), nil, gift, nil)
        case .starTransactionTypeGiftPurchaseOffer:
            return (nil, gift, nil, "gift.fill")
        case .starTransactionTypeGiftTransfer(let value):
            return (sender(value.ownerId), nil, L10n.telegram("Stars.Intro.Transaction.GiftTransfer"), nil)
        case .starTransactionTypeGiftOriginalDetailsDrop(let value):
            return (sender(value.ownerId), nil, L10n.telegram("Stars.Intro.Transaction.GiftDropOriginalDetails"), nil)
        case .starTransactionTypeGiftSale(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.ConvertedGift"), nil)
        case .starTransactionTypeGiftUpgrade(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.GiftUpgrade"), nil)
        case .starTransactionTypeGiftUpgradePurchase(let value):
            return (sender(value.ownerId), nil, L10n.telegram("Stars.Intro.Transaction.PrepaidGiftUpgrade"), nil)
        case .starTransactionTypeUpgradedGiftPurchase(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.GiftPurchase"), nil)
        case .starTransactionTypeUpgradedGiftSale(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.GiftSale"), nil)
        case .starTransactionTypeChannelPaidReactionSend(let value):
            return (.chat(value.chatId), nil, L10n.telegram("Stars.Intro.Transaction.Reaction.Title"), nil)
        case .starTransactionTypeChannelPaidReactionReceive(let value):
            return (.user(value.userId), nil, L10n.telegram("Stars.Intro.Transaction.Reaction.Title"), nil)
        case .starTransactionTypeAffiliateProgramCommission(let value):
            return (.chat(value.chatId), nil, L10n.telegram(
                "Stars.Intro.Transaction.Commission.Title",
                (Double(value.commissionPerMille) / 10).formatted() + "%",
            ), nil)
        case .starTransactionTypePaidMessageSend(let value):
            return (
                .chat(value.chatId),
                nil,
                L10n.telegramPlural("Stars.Intro.Transaction.PaidMessage", count: value.messageCount),
                nil,
            )
        case .starTransactionTypePaidMessageReceive(let value):
            return (
                sender(value.senderId),
                nil,
                L10n.telegramPlural("Stars.Intro.Transaction.PaidMessage", count: value.messageCount),
                nil,
            )
        case .starTransactionTypePaidGroupCallMessageSend(let value):
            return (
                .chat(value.chatId),
                nil,
                L10n.telegramPlural("Stars.Intro.Transaction.LiveStreamPaidMessage", count: 1),
                nil,
            )
        case .starTransactionTypePaidGroupCallMessageReceive(let value):
            return (
                sender(value.senderId),
                nil,
                L10n.telegramPlural("Stars.Intro.Transaction.LiveStreamPaidMessage", count: 1),
                nil,
            )
        case .starTransactionTypePaidGroupCallReactionSend(let value):
            return (.chat(value.chatId), nil, L10n.telegram("Stars.Intro.Transaction.LiveStreamReaction"), nil)
        case .starTransactionTypePaidGroupCallReactionReceive(let value):
            return (sender(value.senderId), nil, L10n.telegram("Stars.Intro.Transaction.LiveStreamReaction"), nil)
        case .starTransactionTypeSuggestedPostPaymentSend(let value):
            return (.chat(value.chatId), nil, nil, nil)
        case .starTransactionTypeSuggestedPostPaymentReceive(let value):
            return (.user(value.userId), nil, nil, nil)
        case .starTransactionTypePremiumPurchase(let value):
            return (
                .user(value.userId),
                nil,
                L10n.telegramPlural("Stars.Intro.Transaction.TelegramPremium", count: value.monthCount),
                nil,
            )
        case .starTransactionTypeBusinessBotTransferSend(let value):
            return (.user(value.userId), nil, nil, nil)
        case .starTransactionTypeBusinessBotTransferReceive(let value):
            return (.user(value.userId), nil, nil, nil)
        }
    }

    /// StarsTransactionScreen as a sheet.
    private func openDetails(_ row: Row) {
        let navigation = UINavigationController(rootViewController: StarsTransactionDetailViewController(row: row))
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    /// StarsBalanceComponent: the star, Telegram Stars, the balance in 48 pt and "your balance", then the tabs.
    private func makeHeader() -> UIView {
        let star = UIImageView(image: UIImage(
            systemName: "star.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 64, weight: .regular),
        ))
        star.tintColor = .systemOrange
        let titleLabel = UILabel()
        titleLabel.text = L10n.telegram("Stars.Intro.Title")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        balanceLabel.font = .systemFont(ofSize: 48, weight: .semibold)
        balanceLabel.text = " "
        let caption = UILabel()
        caption.text = L10n.telegram("Stars.Intro.YourBalance")
        caption.font = .preferredFont(forTextStyle: .subheadline)
        caption.textColor = .secondaryLabel
        segments.selectedSegmentIndex = 0
        segments.addAction(UIAction { [weak self] _ in self?.segmentChanged() }, for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [star, titleLabel, balanceLabel, caption, segments])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(16, after: star)
        stack.setCustomSpacing(24, after: caption)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            segments.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    private func segmentChanged() {
        direction =
            switch segments.selectedSegmentIndex {
            case 1: .transactionDirectionIncoming
            case 2: .transactionDirectionOutgoing
            default: nil
            }
        load(reset: true)
    }

    private func load(reset: Bool) {
        guard contextIsCurrent, let me = TDLib.shared.activeAccount?.userID else { return }
        if reset {
            generation += 1
            rows = []
            nextOffset = nil
        }
        isLoading = true
        if reset { reload() }
        let generation = generation
        let client = client
        let direction = direction
        let offset = nextOffset ?? ""
        Task { [weak self] in
            let page = try? await client.send(TDNativeRequests.getStarTransactions(
                ownerId: .messageSenderUser(TDNativeMessageSenderUser(userId: me)),
                subscriptionId: "",
                direction: direction,
                offset: offset,
                limit: Self.pageSize,
            ))
            guard let self, generation == self.generation, contextIsCurrent else { return }
            var loaded = [Row]()
            for transaction in page?.transactions ?? [] {
                await loaded.append(row(for: transaction, client: client))
            }
            guard generation == self.generation else { return }
            isLoading = false
            if let page {
                balance = page.starAmount
                balanceLabel.text = StarsBalanceStore.text(page.starAmount)
                nextOffset = page.nextOffset
            } else {
                nextOffset = ""
            }
            rows += loaded
            reload()
        }
    }

    /// StarsTransactionsListPanelComponent's item: the peer with what the Stars were for, or the service.
    private func row(for transaction: TDNativeStarTransaction, client: TDLibClient) async -> Row {
        let described = Self.describe(transaction.type)
        var peer: SettingsPeer?
        if let peerID = described.peer {
            peer = await settingsPeer(peerID, client: client)
        }
        var date = Date(timeIntervalSince1970: TimeInterval(transaction.date))
            .formatted(date: .abbreviated, time: .shortened)
        if transaction.isRefund { date += " – " + L10n.telegram("Stars.Intro.Transaction.Refund") }
        return Row(
            id: transaction.id,
            title: described.title ?? peer?.title ?? L10n.telegram("Stars.Intro.Transaction.Unsupported.Title"),
            subtitle: described.title == nil ? described.subtitle : described.subtitle ?? peer?.title,
            date: date,
            timestamp: transaction.date,
            amount: transaction.starAmount,
            isRefund: transaction.isRefund,
            peer: described.title == nil ? peer : nil,
            counterpart: peer,
            symbol: described.symbol,
        )
    }

    private func settingsPeer(_ id: PeerID, client: TDLibClient) async -> SettingsPeer? {
        switch id {
        case .user(let userID):
            if let known = peers[userID] { return known }
            let peer = await SettingsPeer.user(userID, client: client)
            peers[userID] = peer
            return peer
        case .chat(let chatID):
            if let known = peers[chatID] { return known }
            guard let chat = try? await client.getChat(chatId: chatID) else { return nil }
            let peer = SettingsPeer(chat: chat)
            peers[chatID] = peer
            return peer
        }
    }
}

// MARK: - StarsTransactionDetailViewController

/// StarsTransactionScreen for one transaction: what it was with the amount, then From or To with the peer (Via for a
/// service), the transaction ID, which a tap copies, the date, and Refund for a refund, over Review the Terms of
/// Service for Stars.
final class StarsTransactionDetailViewController: SettingsListViewController {
    private let row: StarsTransactionsViewController.Row

    init(row: StarsTransactionsViewController.Row) {
        self.row = row
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
    }

    override func makeSections() -> [SettingsSection] {
        var details = [SettingsRow]()
        if let peer = row.counterpart {
            details.append(SettingsRow(
                title: L10n.telegram(row.isIncome ? "Stars.Transaction.From" : "Stars.Transaction.To"),
                detail: peer.title,
            ))
        } else if let subtitle = row.subtitle {
            details.append(SettingsRow(title: L10n.telegram("Stars.Transaction.Via"), detail: subtitle))
        }
        let id = row.id
        details.append(SettingsRow(
            title: L10n.telegram("Stars.Transaction.Id"),
            detail: id,
        ) { [weak self] in self?.copyID(id) })
        details.append(SettingsRow(
            title: L10n.telegram("Stars.Transaction.Date"),
            detail: Date(timeIntervalSince1970: TimeInterval(row.timestamp))
                .formatted(date: .abbreviated, time: .shortened),
        ))
        if row.isRefund {
            details.append(SettingsRow(title: L10n.telegram("Stars.Transaction.Refund")))
        }
        return [
            SettingsSection(rows: [SettingsRow(
                title: row.title,
                detail: row.subtitle,
                style: row.peer.map { .peer($0) } ?? .subtitle,
                symbol: row.peer == nil ? row.symbol : nil,
                trailingView: StarsTransactionsViewController.amountView(row.amount, isRefund: row.isRefund),
            )]),
            SettingsSection(
                footer: L10n.telegram("Stars.Transaction.Terms"),
                rows: details,
                footerLinks: ["default": {
                    if let url = URL(string: "https://telegram.org/tos") { UIApplication.shared.open(url) }
                }],
            ),
        ]
    }

    private func copyID(_ id: String) {
        UIPasteboard.general.string = id
        TelegramUndoToast.show(
            text: L10n.telegram("Stars.Transaction.CopiedId"),
            in: view,
            bottomInset: 12,
            undo: nil,
        )
    }
}
