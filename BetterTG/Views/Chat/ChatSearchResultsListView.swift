// ChatSearchResultsListView.swift

import TDLibKit
import UIKit

// MARK: - ChatSearchResultsListView

/// Telegram's chat search results as a list (ChatInlineSearchResultsListComponent behind the search panel's Show as
/// List): every found message, newest first, with its author, text and date. Selecting one returns the search to the
/// chat at that message, as ChatControllerNode's messageSelected turns displayHistoryFilterAsList off.
@MainActor final class ChatSearchResultsListView: UIView, UITableViewDataSource, UITableViewDelegate {
    /// Telegram names a forward's original author (effectiveAuthor), else the message's sender.
    private enum Author {
        case sender(MessageSender)
        case name(String)
    }

    var onSelect: ((Int64) -> Void)?
    var onNeedsMore: (() -> Void)?

    private let client: TDLibClient
    private let accountID: UUID?
    private let isCurrent: () -> Bool
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let loadingFooter = UIActivityIndicatorView(style: .medium)
    private var messages = [Message]()
    private var authors = [MessageSender: ChatSearchMemberListView.Member]()
    private var resolvingAuthors = Set<MessageSender>()

    init(client: TDLibClient, accountID: UUID?, isCurrent: @escaping () -> Bool) {
        self.client = client
        self.accountID = accountID
        self.isCurrent = isCurrent
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(ChatSearchResultCell.self, forCellReuseIdentifier: ChatSearchResultCell.reuseIdentifier)
        addSubview(tableView)
        loadingFooter.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        loadingFooter.hidesWhenStopped = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func author(of message: Message) -> Author {
        switch message.forwardInfo?.origin {
        case .messageOriginUser(let origin):
            .sender(.messageSenderUser(MessageSenderUser(userId: origin.senderUserId)))
        case .messageOriginChat(let origin):
            .sender(.messageSenderChat(MessageSenderChat(chatId: origin.senderChatId)))
        case .messageOriginChannel(let origin):
            .sender(.messageSenderChat(MessageSenderChat(chatId: origin.chatId)))
        case .messageOriginHiddenUser(let origin):
            .name(origin.senderName)
        case nil:
            .sender(message.senderId)
        }
    }

    /// A hidden forward author has no peer; Telegram colours it from its name.
    private static func namedAuthor(_ name: String, sender: MessageSender) -> ChatSearchMemberListView.Member {
        let colorIndex = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 7
        return ChatSearchMemberListView.Member(
            sender: sender,
            title: name,
            compactTitle: name,
            file: nil,
            minithumbnail: nil,
            placeholder: TelegramAvatarPlaceholder(
                peerID: 0,
                accentColorID: colorIndex,
                upgradedGiftColors: nil,
                letters: name.telegramAvatarFirstLetter.map { [$0] } ?? [],
                isDeleted: false,
            ),
        )
    }

    /// `messages` follow the search's order, newest first; `isLoading` shows the next page loading at the end.
    func update(messages: [Message], isLoading: Bool) {
        let changed = messages.map(\.id) != self.messages.map(\.id)
        self.messages = messages
        if changed { tableView.reloadData() }
        if isLoading, !messages.isEmpty {
            loadingFooter.startAnimating()
            tableView.tableFooterView = loadingFooter
        } else {
            loadingFooter.stopAnimating()
            tableView.tableFooterView = nil
        }
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatSearchResultCell.reuseIdentifier, for: indexPath)
        let message = messages[indexPath.row]
        (cell as? ChatSearchResultCell)?.configure(
            author: author(for: message),
            text: ChatSummary.summary(for: message),
            date: ChatListCell.dateText(timestamp: message.date),
            client: client,
            accountID: accountID,
        )
        return cell
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= messages.count - 5 else { return }
        onNeedsMore?()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard messages.indices.contains(indexPath.row), isCurrent() else { return }
        onSelect?(messages[indexPath.row].id)
    }

    private func author(for message: Message) -> ChatSearchMemberListView.Member? {
        switch Self.author(of: message) {
        case .name(let name):
            return Self.namedAuthor(name, sender: message.senderId)
        case .sender(let sender):
            if let author = authors[sender] { return author }
            resolve(sender)
            return nil
        }
    }

    private func resolve(_ sender: MessageSender) {
        guard resolvingAuthors.insert(sender).inserted else { return }
        let client = client
        Task { [weak self] in
            let author = await ChatSearchMemberListView.member(for: sender, client: client)
            guard let self, isCurrent(), let author else { return }
            authors[sender] = author
            let rows = tableView.indexPathsForVisibleRows?.filter { indexPath in
                guard messages.indices.contains(indexPath.row),
                      case .sender(let rowSender) = Self.author(of: messages[indexPath.row]) else { return false }
                return rowSender == sender
            } ?? []
            if !rows.isEmpty { tableView.reconfigureRows(at: rows) }
        }
    }
}

// MARK: - ChatSearchResultCell

/// ChatListItem showing a found message (displayAsMessage): the author's avatar and name, the date and the text.
private final class ChatSearchResultCell: UITableViewCell {
    static let reuseIdentifier = "ChatSearchResultCell"

    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()
    private let messageLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessibilityTraits = .button
        isAccessibilityElement = true
        for subview in [avatarView, nameLabel, dateLabel, messageLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dateLabel.font = .preferredFont(forTextStyle: .footnote)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = .secondaryLabel
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 2
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 52),
            avatarView.heightAnchor.constraint(equalToConstant: 52),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            dateLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
        ])
        separatorInset.left = 80
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(
        author: ChatSearchMemberListView.Member?,
        text: String,
        date: String,
        client: TDLibClient,
        accountID: UUID?,
    ) {
        nameLabel.text = author?.title
        dateLabel.text = date
        messageLabel.text = text
        accessibilityLabel = [author?.title, text, date].compactMap(\.self).joined(separator: ", ")
        guard let author else { return }
        // The account's own messages show its avatar, not Saved Messages.
        avatarView.configure(
            file: author.file,
            minithumbnail: author.minithumbnail,
            placeholder: author.placeholder,
            accountID: accountID,
            accountUserID: 0,
            client: client,
        )
    }
}
