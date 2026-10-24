// PollResultsViewController.swift

import TDLibKit
import UIKit

// MARK: - PollResultsViewController

/// Telegram's pollResultsController: a public poll's voters by answer, read with `getPollVoters` on the chat's
/// client. An answer shows its first ten voters; Show More reveals the rest and loads further pages, and Collapse
/// folds them back. Pages that arrive after the account or client changed are dropped.
@MainActor final class PollResultsViewController: UITableViewController {
    private struct OptionVoters {
        var voters = [PollVoter]()
        var totalCount: Int
        var nextOffset = 0
        var canLoadMore = true
        var hasLoadedOnce = false
        var isLoading = false
        var isExpanded = false
        var loadError: String?
    }

    private struct VoterPeer {
        let title: String
        let file: File?
        let minithumbnail: Minithumbnail?
        let placeholder: TelegramAvatarPlaceholder
    }

    private enum Row {
        case question
        case voter(PollVoter)
        case loading
        case failed(String)
        case showMore(remaining: Int, isLoading: Bool)
    }

    /// PollResultsController's collapsed count, which is also PollResultsOptionContext's first page; later pages
    /// take 50, TDLib's maximum.
    private static let collapsedCount = 10
    private static let pageSize = 50
    private static let textCellID = "PollResultsTextCell"
    private static let questionCellID = "PollResultsQuestionCell"

    private let chatID: Int64
    private let messageID: Int64
    private let poll: Poll
    private let client: TDLibClient
    private let accountID: UUID
    private var focusedOptionID: Int?
    private var options: [Int: OptionVoters]
    private var sectionOptionIDs = [Int]()
    private var users = [Int64: User]()
    private var chats = [Int64: Chat]()
    private var loadTasks = [Int: Task<Void, Never>]()
    private var profileTask: Task<Void, Never>?

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(
        chatID: Int64,
        messageID: Int64,
        poll: Poll,
        focusedOptionID: Int?,
        client: TDLibClient,
        accountID: UUID,
    ) {
        self.chatID = chatID
        self.messageID = messageID
        self.poll = poll
        self.focusedOptionID = focusedOptionID
        self.client = client
        self.accountID = accountID
        var options = [Int: OptionVoters]()
        for index in poll.options.indices where poll.options[index].voterCount > 0 {
            options[index] = OptionVoters(totalCount: poll.options[index].voterCount)
        }
        self.options = options
        super.init(style: .insetGrouped)
        let title = L10n.telegram("PollResults.Title")
        self.title = title
        navigationItem.backButtonTitle = title
        navigationItem.titleView = PollResultsTitleView(
            title: title,
            subtitle: L10n.telegramPlural("MessagePoll.VotedCount", count: poll.totalVoterCount),
        )
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for task in loadTasks.values {
            task.cancel()
        }
        profileTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.textCellID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.questionCellID)
        tableView.register(PollResultsVoterCell.self, forCellReuseIdentifier: PollResultsVoterCell.reuseIdentifier)
        tableView.register(PollResultsLoadingCell.self, forCellReuseIdentifier: PollResultsLoadingCell.reuseIdentifier)
        tableView.register(
            PollResultsOptionHeaderView.self,
            forHeaderFooterViewReuseIdentifier: PollResultsOptionHeaderView.reuseIdentifier,
        )
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 32
        reloadSections()
        for optionID in options.keys.sorted() {
            load(optionID: optionID)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scrollToFocusedOption()
    }

    // MARK: Table

    override func numberOfSections(in _: UITableView) -> Int {
        1 + sectionOptionIDs.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows(in: section).count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch row(at: indexPath) {
        case .voter(let voter):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: PollResultsVoterCell.reuseIdentifier,
                for: indexPath,
            ) as? PollResultsVoterCell else { return UITableViewCell() }
            let peer = voterPeer(for: voter.voterId)
            cell.configure(
                title: peer.title,
                date: Self.voteDate(voter.date),
                file: peer.file,
                minithumbnail: peer.minithumbnail,
                placeholder: peer.placeholder,
                client: client,
                accountID: accountID,
            )
            return cell
        case .loading:
            return tableView.dequeueReusableCell(withIdentifier: PollResultsLoadingCell.reuseIdentifier, for: indexPath)
        case .question:
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.questionCellID, for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = poll.question.text
            content.textProperties.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .systemFont(ofSize: 17, weight: .semibold),
            )
            content.textProperties.numberOfLines = 0
            cell.contentConfiguration = content
            cell.backgroundConfiguration = .clear()
            cell.selectionStyle = .none
            cell.accessibilityTraits = .header
            return cell
        case .failed(let message):
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.textCellID, for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = L10n.betterTG("PollResults.LoadFailed", message)
            content.textProperties.color = .secondaryLabel
            content.textProperties.numberOfLines = 0
            cell.contentConfiguration = content
            cell.selectionStyle = .default
            cell.accessoryView = nil
            cell.accessibilityTraits = .button
            return cell
        case .showMore(let remaining, let isLoading):
            // ItemListPeerActionItem with the down arrow.
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.textCellID, for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.image = UIImage(systemName: "chevron.down")
            content.imageProperties.tintColor = .systemBlue
            content.text = L10n.telegramPlural("PollResults.ShowMore", count: remaining)
            content.textProperties.color = .systemBlue
            cell.contentConfiguration = content
            cell.selectionStyle = isLoading ? .none : .default
            if isLoading {
                let indicator = UIActivityIndicatorView(style: .medium)
                indicator.startAnimating()
                cell.accessoryView = indicator
            } else {
                cell.accessoryView = nil
            }
            cell.accessibilityTraits = isLoading ? [.button, .notEnabled] : .button
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let optionID = optionID(in: section), let state = options[optionID],
              let header = tableView.dequeueReusableHeaderFooterView(
                  withIdentifier: PollResultsOptionHeaderView.reuseIdentifier,
              ) as? PollResultsOptionHeaderView
        else { return nil }
        let option = poll.options[optionID]
        let collapseAction: (() -> Void)? = state.isExpanded
            ? { [weak self] in self?.collapse(optionID: optionID) }
            : nil
        // ItemListPeerItemHeader: the answer in capitals with its share, then its vote count or Collapse.
        header.configure(
            title: option.text.text.uppercased() + " — \(option.votePercentage)%",
            actionTitle: state.isExpanded
                ? L10n.telegram("PollResults.Collapse")
                : L10n.telegramPlural("MessagePoll.VotedCount", count: state.totalCount),
            action: collapseAction,
        )
        return header
    }

    override func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch row(at: indexPath) {
        case .failed,
             .showMore(_, false),
             .voter: true
        case .loading,
             .question,
             .showMore: false
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let optionID = optionID(in: indexPath.section) else { return }
        switch row(at: indexPath) {
        case .voter(let voter):
            openProfile(of: voter.voterId)
        case .failed:
            load(optionID: optionID)
        case .showMore(_, false):
            showMore(optionID: optionID)
        case .loading,
             .question,
             .showMore:
            break
        }
    }

    // MARK: Voters

    /// User ids are positive and chat ids negative, so one id names either.
    private static func peerID(of sender: MessageSender) -> Int64 {
        switch sender {
        case .messageSenderUser(let user): user.userId
        case .messageSenderChat(let chat): chat.chatId
        }
    }

    /// PollResultsController.formatTimeAndDate: the vote's time, below its day unless that is today.
    private static func voteDate(_ timestamp: Int) -> NSAttributedString? {
        guard timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = Calendar.current
        let day: String? =
            if calendar.isDateInToday(date) {
                nil
            } else if calendar.isDateInYesterday(date) {
                L10n.telegram("Weekday.Yesterday").lowercased()
            } else {
                date.formatted(date: .numeric, time: .omitted)
            }
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let result = NSMutableAttributedString()
        if let day {
            result.append(NSAttributedString(
                string: day + "\n",
                attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel],
            ))
        }
        result.append(NSAttributedString(
            string: date.formatted(date: .omitted, time: .shortened),
            attributes: [.font: font, .foregroundColor: UIColor.label],
        ))
        return result
    }

    private static func profileChatID(of sender: MessageSender, client: TDLibClient) async -> Int64? {
        switch sender {
        case .messageSenderUser(let user):
            try? await client.createPrivateChat(force: false, userId: user.userId).id
        case .messageSenderChat(let chat):
            chat.chatId
        }
    }

    // MARK: Rows

    private func optionID(in section: Int) -> Int? {
        sectionOptionIDs.indices.contains(section - 1) ? sectionOptionIDs[section - 1] : nil
    }

    private func row(at indexPath: IndexPath) -> Row {
        let sectionRows = rows(in: indexPath.section)
        return sectionRows.indices.contains(indexPath.row) ? sectionRows[indexPath.row] : .loading
    }

    /// PollResultsController's entries for one section: the question, or an answer's voters with Show More.
    private func rows(in section: Int) -> [Row] {
        guard section > 0 else { return [.question] }
        guard let optionID = optionID(in: section), let state = options[optionID] else { return [] }
        guard state.hasLoadedOnce else {
            return [state.loadError.map(Row.failed) ?? .loading]
        }
        let shown = state.isExpanded ? state.voters.count : min(state.voters.count, Self.collapsedCount)
        var rows = state.voters.prefix(shown).map(Row.voter)
        let remaining = state.totalCount - shown
        if let loadError = state.loadError {
            rows.append(.failed(loadError))
        } else if remaining > 0, shown < state.voters.count || state.canLoadMore {
            rows.append(.showMore(remaining: remaining, isLoading: state.isLoading))
        }
        return rows
    }

    /// Telegram lists an answer while its first page loads, and afterwards only if it has voters.
    private func reloadSections() {
        sectionOptionIDs = options.keys.sorted().filter { optionID in
            guard let state = options[optionID] else { return false }
            return !state.hasLoadedOnce || !state.voters.isEmpty
        }
        tableView.reloadData()
    }

    /// Opens the list at the tapped answer unless it comes first (initialScrollToItem).
    private func scrollToFocusedOption() {
        guard let focusedOptionID else { return }
        self.focusedOptionID = nil
        guard let index = sectionOptionIDs.firstIndex(of: focusedOptionID), index > 0 else { return }
        tableView.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: 0, section: index + 1), at: .top, animated: false)
    }

    // MARK: Loading

    /// PollResultsController.expandOption: shows every loaded voter and loads the next page.
    private func showMore(optionID: Int) {
        guard var state = options[optionID] else { return }
        state.isExpanded = true
        options[optionID] = state
        reloadSections()
        load(optionID: optionID)
    }

    private func collapse(optionID: Int) {
        guard var state = options[optionID], state.isExpanded else { return }
        state.isExpanded = false
        options[optionID] = state
        reloadSections()
    }

    private func load(optionID: Int) {
        guard loadTasks[optionID] == nil, var state = options[optionID], state.canLoadMore, contextIsCurrent
        else { return }
        let offset = state.nextOffset
        let limit = state.hasLoadedOnce ? Self.pageSize : Self.collapsedCount
        state.isLoading = true
        state.loadError = nil
        options[optionID] = state
        reloadSections()
        let client = client
        let chatID = chatID
        let messageID = messageID
        loadTasks[optionID] = Task { [weak self] in
            let result: Result<PollVoters, any Error>
            do {
                let page = try await client.getPollVoters(
                    chatId: chatID,
                    limit: limit,
                    messageId: messageID,
                    offset: offset,
                    optionId: optionID,
                )
                result = .success(page)
            } catch {
                result = .failure(error)
            }
            var resolvedUsers = [Int64: User]()
            var resolvedChats = [Int64: Chat]()
            if case .success(let page) = result {
                for voter in page.voters {
                    switch voter.voterId {
                    case .messageSenderUser(let sender):
                        if resolvedUsers[sender.userId] == nil,
                           let user = try? await client.getUser(userId: sender.userId)
                        {
                            resolvedUsers[sender.userId] = user
                        }
                    case .messageSenderChat(let sender):
                        if resolvedChats[sender.chatId] == nil,
                           let chat = try? await client.getChat(chatId: sender.chatId)
                        {
                            resolvedChats[sender.chatId] = chat
                        }
                    }
                }
            }
            guard let self else { return }
            loadTasks[optionID] = nil
            guard !Task.isCancelled, contextIsCurrent else { return }
            apply(result, optionID: optionID, offset: offset, users: resolvedUsers, chats: resolvedChats)
        }
    }

    private func apply(
        _ result: Result<PollVoters, any Error>,
        optionID: Int,
        offset: Int,
        users resolvedUsers: [Int64: User],
        chats resolvedChats: [Int64: Chat],
    ) {
        guard var state = options[optionID], state.nextOffset == offset else { return }
        state.isLoading = false
        switch result {
        case .success(let page):
            users.merge(resolvedUsers) { _, new in new }
            chats.merge(resolvedChats) { _, new in new }
            var known = Set(state.voters.map { Self.peerID(of: $0.voterId) })
            for voter in page.voters where known.insert(Self.peerID(of: voter.voterId)).inserted {
                state.voters.append(voter)
            }
            state.nextOffset = offset + page.voters.count
            state.totalCount = max(page.totalCount, state.voters.count)
            state.canLoadMore = !page.voters.isEmpty && state.nextOffset < page.totalCount
            state.hasLoadedOnce = true
        case .failure(let error):
            state.loadError = (error as? TDLibError)?.message ?? error.localizedDescription
        }
        options[optionID] = state
        reloadSections()
    }

    private func voterPeer(for sender: MessageSender) -> VoterPeer {
        switch sender {
        case .messageSenderUser(let userSender):
            guard let user = users[userSender.userId] else {
                return VoterPeer(
                    title: L10n.telegram("User.DeletedAccount"),
                    file: nil,
                    minithumbnail: nil,
                    placeholder: TelegramAvatarPlaceholder(
                        peerID: userSender.userId,
                        accentColorID: 0,
                        upgradedGiftColors: nil,
                        letters: [],
                        isDeleted: true,
                    ),
                )
            }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            return VoterPeer(
                title: name.isEmpty ? L10n.telegram("User.DeletedAccount") : name,
                file: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                placeholder: user.telegramAvatarPlaceholder,
            )
        case .messageSenderChat(let chatSender):
            let chat = chats[chatSender.chatId]
            let title = chat?.title ?? L10n.betterTG("Chat.FallbackChatTitle")
            let firstLetter = title.trimmingCharacters(in: .whitespacesAndNewlines)
                .first
                .map { String($0).uppercased() }
            return VoterPeer(
                title: title,
                file: chat?.photo?.small,
                minithumbnail: chat?.photo?.minithumbnail,
                placeholder: TelegramAvatarPlaceholder(
                    peerID: chatSender.chatId,
                    accentColorID: chat?.accentColorId ?? 0,
                    upgradedGiftColors: chat?.upgradedGiftColors,
                    letters: firstLetter.map { [$0] } ?? [],
                    isDeleted: false,
                ),
            )
        }
    }

    /// PollResultsController.openPeer: the voter's profile, opened as the members list opens a member.
    private func openProfile(of sender: MessageSender) {
        guard profileTask == nil, contextIsCurrent else { return }
        let client = client
        let accountID = accountID
        profileTask = Task { [weak self] in
            var chat: CustomChat?
            if let chatID = await Self.profileChatID(of: sender, client: client), self?.contextIsCurrent == true {
                chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
            }
            guard let self else { return }
            profileTask = nil
            guard !Task.isCancelled, let chat, contextIsCurrent, let navigation = navigationController,
                  navigation.topViewController === self else { return }
            let profile = PeerProfileViewController(customChat: chat, topic: nil, client: client, accountID: accountID)
            profile.configureOpensChatItself()
            navigation.pushViewController(profile, animated: true)
        }
    }
}

// MARK: - PollResultsTitleView

/// Telegram's title with subtitle: Poll Results over the poll's vote count.
private final class PollResultsTitleView: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(
            width: max(titleLabel.intrinsicContentSize.width, subtitleLabel.intrinsicContentSize.width),
            height: 44,
        )
    }

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        subtitleLabel.text = subtitle
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(subtitle)"
        accessibilityTraits = .header
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleHeight = ceil(titleLabel.font.lineHeight)
        let subtitleHeight = ceil(subtitleLabel.font.lineHeight)
        let top = max(0, floor((bounds.height - titleHeight - subtitleHeight) / 2))
        titleLabel.frame = CGRect(x: 0, y: top, width: bounds.width, height: titleHeight)
        subtitleLabel.frame = CGRect(x: 0, y: top + titleHeight, width: bounds.width, height: subtitleHeight)
    }
}

// MARK: - PollResultsOptionHeaderView

/// ItemListPeerItemHeader: a caption with a trailing count, or Collapse while the answer is expanded.
private final class PollResultsOptionHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "PollResultsOptionHeaderView"

    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var action: (() -> Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        for subview in [titleLabel, actionButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.textColor = .secondaryLabel
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.setTitleColor(.systemBlue, for: .normal)
        actionButton.setTitleColor(.secondaryLabel, for: .disabled)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),
            actionButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        action = nil
    }

    func configure(title: String, actionTitle: String, action: (() -> Void)?) {
        titleLabel.text = title
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isEnabled = action != nil
        self.action = action
    }

    @objc private func actionPressed() {
        action?()
    }
}

// MARK: - PollResultsVoterCell

/// ItemListPeerItem in the poll results: the voter's avatar and name with the time of the vote.
private final class PollResultsVoterCell: UITableViewCell {
    static let reuseIdentifier = "PollResultsVoterCell"

    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = L10n.betterTG("Accessibility.OpenVoterProfileHint")
        for subview in [avatarView, nameLabel, dateLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.textColor = .label
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail
        dateLabel.numberOfLines = 2
        dateLabel.textAlignment = .right
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dateLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 6),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(
        title: String,
        date: NSAttributedString?,
        file: File?,
        minithumbnail: Minithumbnail?,
        placeholder: TelegramAvatarPlaceholder,
        client: TDLibClient,
        accountID: UUID,
    ) {
        nameLabel.text = title
        dateLabel.attributedText = date
        dateLabel.isHidden = date == nil
        // The account's own vote shows its avatar, never the Saved Messages icon.
        avatarView.configure(
            file: file,
            minithumbnail: minithumbnail,
            placeholder: placeholder,
            accountID: accountID,
            accountUserID: 0,
            client: client,
        )
        accessibilityLabel = [title, date?.string.replacing("\n", with: " ")]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

// MARK: - PollResultsLoadingCell

/// Stands in for Telegram's shimmering voter rows while an answer's first page loads.
private final class PollResultsLoadingCell: UITableViewCell {
    static let reuseIdentifier = "PollResultsLoadingCell"

    private let indicator = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        isAccessibilityElement = true
        accessibilityLabel = L10n.betterTG("Accessibility.Loading")
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        contentView.addSubview(indicator)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            indicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        indicator.startAnimating()
    }
}
