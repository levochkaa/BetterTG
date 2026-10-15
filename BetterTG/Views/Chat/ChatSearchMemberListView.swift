// ChatSearchMemberListView.swift

import TDLibKit
import UIKit

// MARK: - ChatSearchMemberListView

/// The members Telegram lists while a chat search picks a sender after "from:" (ChatSearchDomain.members, filled by
/// searchPeerMembers). Selecting one narrows the search to that member's messages.
@MainActor final class ChatSearchMemberListView: UIView, UITableViewDataSource, UITableViewDelegate {
    struct Member {
        let sender: MessageSender
        let title: String
        /// Telegram's token shows the compact title: a person's first name.
        let compactTitle: String
        let file: File?
        let minithumbnail: Minithumbnail?
        let placeholder: TelegramAvatarPlaceholder
    }

    private static let typingDelay = Duration.milliseconds(250)

    var onSelect: ((Member) -> Void)?

    private let client: TDLibClient
    private let chatID: Int64
    private let accountID: UUID?
    private let isCurrent: () -> Bool
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var members = [Member]()
    private var query: String?
    private var task: Task<Void, Never>?

    init(client: TDLibClient, chatID: Int64, accountID: UUID?, isCurrent: @escaping () -> Bool) {
        self.client = client
        self.chatID = chatID
        self.accountID = accountID
        self.isCurrent = isCurrent
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(ChatSearchMemberCell.self, forCellReuseIdentifier: ChatSearchMemberCell.reuseIdentifier)
        addSubview(tableView)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 32),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        task?.cancel()
    }

    private static func member(for sender: MessageSender, client: TDLibClient) async -> Member? {
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await client.getUser(userId: value.userId) else { return nil }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            let title = name.isEmpty ? L10n.telegram("User.DeletedAccount") : name
            return Member(
                sender: sender,
                title: title,
                compactTitle: user.firstName.isEmpty ? title : user.firstName,
                file: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                placeholder: user.telegramAvatarPlaceholder,
            )
        case .messageSenderChat(let value):
            guard let chat = try? await client.getChat(chatId: value.chatId) else { return nil }
            return Member(
                sender: sender,
                title: chat.title,
                compactTitle: chat.title,
                file: chat.photo?.small,
                minithumbnail: chat.photo?.minithumbnail,
                placeholder: TelegramAvatarPlaceholder(
                    peerID: chat.id,
                    accentColorID: chat.accentColorId,
                    upgradedGiftColors: chat.upgradedGiftColors,
                    letters: chat.title.telegramAvatarFirstLetter.map { [$0] } ?? [],
                    isDeleted: false,
                ),
            )
        }
    }

    func update(query rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != self.query else { return }
        let waitsForTyping = self.query != nil
        self.query = query
        task?.cancel()
        activityIndicator.startAnimating()
        let client = client
        let chatID = chatID
        task = Task { [weak self] in
            if waitsForTyping { try? await Task.sleep(for: Self.typingDelay) }
            guard !Task.isCancelled else { return }
            let found = try? await client.send(TDNativeRequests.searchChatMembers(
                chatId: chatID, query: query, limit: 50, filter: nil,
            ))
            var members = [Member]()
            for member in found?.members ?? [] {
                guard !Task.isCancelled else { return }
                if let resolved = await Self.member(for: member.memberId, client: client) {
                    members.append(resolved)
                }
            }
            guard let self, !Task.isCancelled, isCurrent() else { return }
            self.members = members
            activityIndicator.stopAnimating()
            tableView.reloadData()
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        query = nil
        members = []
        tableView.reloadData()
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        members.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatSearchMemberCell.reuseIdentifier, for: indexPath)
        (cell as? ChatSearchMemberCell)?.configure(member: members[indexPath.row], client: client, accountID: accountID)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard members.indices.contains(indexPath.row), isCurrent() else { return }
        onSelect?(members[indexPath.row])
    }
}

// MARK: - ChatSearchMemberCell

private final class ChatSearchMemberCell: UITableViewCell {
    static let reuseIdentifier = "ChatSearchMemberCell"

    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessibilityTraits = .button
        isAccessibilityElement = true
        for subview in [avatarView, nameLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 34),
            avatarView.heightAnchor.constraint(equalToConstant: 34),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(member: ChatSearchMemberListView.Member, client: TDLibClient, accountID: UUID?) {
        nameLabel.text = member.title
        accessibilityLabel = member.title
        avatarView.configure(
            file: member.file,
            minithumbnail: member.minithumbnail,
            placeholder: member.placeholder,
            accountID: accountID,
            accountUserID: 0,
            client: client,
        )
    }
}
