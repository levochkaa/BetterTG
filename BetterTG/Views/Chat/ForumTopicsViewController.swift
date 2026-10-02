// ForumTopicsViewController.swift

import Combine
import Foundation
import TDLibKitDynamic
import UIKit

// MARK: - ForumTopicsViewController

@MainActor final class ForumTopicsViewController: UIViewController, UITableViewDelegate,
    UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate, ClientRestorableNavigationEntry
{
    struct ClientRestorationState {
        let pages: ForumTopicsRestorationState
        let rawQuery: String
        let targetConsumed: Bool
        let viewport: ChatListViewportSnapshot
    }

    private enum Section {
        case topics
    }

    private let viewModel: ForumTopicsVM
    private let targetMessageID: Int64?
    private let targetQuote: MessageQuoteHighlight?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private let refreshControl = UIRefreshControl()
    private var dataSource: UITableViewDiffableDataSource<Section, Int>!
    private var cancellables = Set<AnyCancellable>()
    private var targetResolutionTask: Task<Void, Never>?
    private var targetIntent: ForumTopicTargetIntent
    private let initialQuery: String
    private var previousSearchQuery: String
    private var viewportRestoration: ChatListViewportRestoration
    private var didPresentLoadError = false
    private var retired = false
    private var preparationTask: Task<Void, Never>?
    private var preparationSource: TdUpdateSource?
    private var preparedClient: (source: TdUpdateSource, client: TDLibClient, chat: CustomChat)?
    private var retryScheduled = false

    var navigationClientSource: TdUpdateSource? {
        viewModel.location.accountID.map { TdUpdateSource(accountID: $0, clientID: viewModel.client.id) }
    }

    private var routeIsRetained: Bool {
        !retired && navigationController?.viewControllers.contains(where: { $0 === self }) == true
    }

    private var contextIsCurrent: Bool {
        guard let source = navigationClientSource else { return false }
        return routeIsRetained && source == TDLib.shared.activeUpdateSource
            && RootVM.shared.activeAccountID == viewModel.location.accountID
    }

    init(
        customChat: CustomChat,
        location: ChatLocation,
        client: TDLibClient,
        targetMessageID: Int64? = nil,
        targetQuote: MessageQuoteHighlight? = nil,
        restoration: ClientRestorationState? = nil,
    ) {
        self.viewModel = ForumTopicsVM(
            customChat: customChat,
            location: location,
            client: client,
            restoration: restoration?.pages,
        )
        self.targetMessageID = targetMessageID
        self.targetQuote = targetQuote
        self.targetIntent = ForumTopicTargetIntent(consumed: restoration?.targetConsumed ?? false)
        self.initialQuery = restoration?.rawQuery ?? ""
        self.previousSearchQuery = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.viewportRestoration = ChatListViewportRestoration(restoration?.viewport)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        targetResolutionTask?.cancel()
        preparationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.customChat.displayTitle
        view.backgroundColor = .systemBackground
        configureTable()
        configureSearch()
        configureDataSource()
        observeState()
        viewModel.start()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        resolveTargetIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveTargetIfNeeded()
        retryClientRestoration()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        restoreViewportIfNeeded()
    }

    func updateSearchResults(for searchController: UISearchController) {
        guard !retired else { return }
        let query = searchController.searchBar.text ?? ""
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized != previousSearchQuery {
            viewportRestoration.cancel()
            previousSearchQuery = normalized
        }
        viewModel.search(query)
        retryClientRestoration()
    }

    func didDismissSearchController(_: UISearchController) { retryClientRestoration() }
    func searchBarTextDidEndEditing(_: UISearchBar) { retryClientRestoration() }
    func scrollViewWillBeginDragging(_: UIScrollView) { viewportRestoration.cancel() }
    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { retryClientRestoration() }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) { retryClientRestoration() }

    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard canRestoreClient(source) else { return nil }
        guard let preparedClient, preparedClient.source == source else {
            prepareClientMetadata(source)
            return nil
        }
        let query = isViewLoaded ? searchController.searchBar.text ?? "" : initialQuery
        let pages = viewModel.restorationState(rawQuery: query)
        let viewport = viewportRestoration.pending ?? (isViewLoaded
            ? ChatListViewportSnapshot.capture(
                tableView: tableView, chatID: { dataSource.itemIdentifier(for: $0).map(Int64.init) },
            )
            : .init(chatID: nil, rowMinYRelativeToViewport: 0, offsetFromTop: 0))
        let state = ClientRestorationState(
            pages: pages, rawQuery: query,
            targetConsumed: targetIntent.consumed,
            viewport: pages.topics.isEmpty
                ? .init(chatID: nil, rowMinYRelativeToViewport: 0, offsetFromTop: 0)
                : viewport,
        )
        return PreparedClientNavigationReplacement(
            preflight: { [weak self] in self?.canRestoreClient(source) == true },
            commit: { [self] in
                guard canRestoreClient(source) else { return nil }
                let location = ChatLocation(
                    accountID: source.accountID,
                    chatID: viewModel.location.chatID,
                    clientID: source.clientID,
                    topic: viewModel.location.topic,
                )
                let replacement = ForumTopicsViewController(
                    customChat: preparedClient.chat, location: location, client: preparedClient.client,
                    targetMessageID: targetMessageID, targetQuote: targetQuote, restoration: state,
                )
                retired = true
                targetIntent.cancel()
                targetResolutionTask?.cancel()
                preparationTask?.cancel()
                cancellables.removeAll()
                viewModel.retire()
                return replacement
            },
        )
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicID = dataSource.itemIdentifier(for: indexPath),
              let topic = viewModel.topics.first(where: { $0.info.forumTopicId == topicID })
        else { return }
        open(topic: topic, targetMessageID: nil, quote: nil)
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= max(0, viewModel.topics.count - 5) {
            viewModel.loadMore()
        }
    }

    private func canRestoreClient(_ source: TdUpdateSource) -> Bool {
        routeIsRetained && source == TDLib.shared.activeUpdateSource
            && source.accountID == viewModel.location.accountID && source.clientID != viewModel.client.id
            && RootVM.shared.activeAccountID == source.accountID && !isBeingDismissed && !isMovingFromParent
            && presentedViewController == nil && transitionCoordinator == nil && !searchController.isActive
            && !tableView.isDragging && !tableView.isDecelerating
            && searchController.searchBar.searchTextField.markedTextRange == nil
    }

    private func prepareClientMetadata(_ source: TdUpdateSource) {
        guard preparationSource != source else { return }
        preparationTask?.cancel()
        let client = TDLib.shared.activeClient
        guard client.id == source.clientID else { return }
        preparationSource = source
        preparationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if preparationSource == source {
                    preparationTask = nil
                    preparationSource = nil
                }
            }
            let chat = await RootVM.shared.getCustomChatForNavigation(from: viewModel.location.chatID, client: client)
            guard !Task.isCancelled, routeIsRetained, preparationSource == source,
                  TDLib.shared.activeUpdateSource == source, RootVM.shared.activeAccountID == source.accountID,
                  let chat, chat.chat.id == viewModel.location.chatID, chat.chat.viewAsTopics else { return }
            preparedClient = (source, client, chat)
            retryClientRestoration()
        }
    }

    private func retryClientRestoration() {
        guard !retired, !retryScheduled, TDLib.shared.activeAccountID == viewModel.location.accountID,
              TDLib.shared.activeClient.id != viewModel.client.id else { return }
        retryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            retryScheduled = false
            guard routeIsRetained else { return }
            NavigationStorage.shared.retryClientRestoration()
        }
    }

    private func restoreViewportIfNeeded() {
        guard !retired, let viewport = viewportRestoration.takeForLayout(
            usable: tableView.bounds.height > 0 && !tableView.isDragging && !tableView.isDecelerating,
        ) else { return }
        viewport.restore(tableView: tableView, indexPath: { id in
            Int(exactly: id).flatMap { dataSource.indexPath(for: $0) }
        })
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 70
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
        tableView.register(ForumTopicCell.self, forCellReuseIdentifier: ForumTopicCell.reuseID)
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureSearch() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.text = initialQuery
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        searchController.searchBar.delegate = self
        searchController.searchBar.placeholder = "Search Topics"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Int>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, topicID in
            guard let self,
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: ForumTopicCell.reuseID,
                      for: indexPath,
                  ) as? ForumTopicCell,
                  let topic = viewModel.topics.first(where: { $0.info.forumTopicId == topicID })
            else { return UITableViewCell() }
            cell.configure(topic: topic, client: viewModel.client)
            return cell
        }
    }

    private func observeState() {
        viewModel.$topics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] topics in
                self?.applySnapshot(topics)
            }
            .store(in: &cancellables)
        viewModel.$loading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                guard let self, !retired else { return }
                if !loading {
                    refreshControl.endRefreshing()
                }
                updateBackgroundView()
            }
            .store(in: &cancellables)
        viewModel.$errorMessage
            .compactMap(\.self)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.presentLoadError(message)
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(_ topics: [ForumTopic]) {
        guard !retired else { return }
        let previousIDs = Set(dataSource.snapshot().itemIdentifiers)
        let topicIDs = topics.map(\.info.forumTopicId)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
        snapshot.appendSections([.topics])
        snapshot.appendItems(topicIDs)
        let retainedIDs = topicIDs.filter(previousIDs.contains)
        if !retainedIDs.isEmpty {
            snapshot.reconfigureItems(retainedIDs)
        }
        let token = viewportRestoration.beginApply()
        dataSource.apply(snapshot, animatingDifferences: viewportRestoration.pending == nil) { [weak self] in
            guard let self, !retired else { return }
            viewportRestoration.completeApply(token)
            restoreViewportIfNeeded()
        }
        updateBackgroundView()
    }

    private func updateBackgroundView() {
        guard viewModel.topics.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        if viewModel.loading {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            tableView.backgroundView = spinner
        } else {
            let label = UILabel()
            label.text = searchController.searchBar.text?.isEmpty == false
                ? "No topics found"
                : "No topics"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        }
    }

    private func resolveTargetIfNeeded() {
        guard contextIsCurrent, let targetMessageID, targetResolutionTask == nil,
              navigationController?.topViewController === self, let attempt = targetIntent.begin()
        else { return }
        let client = viewModel.client
        let location = viewModel.location
        targetResolutionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if targetIntent.owns(attempt) {
                    targetIntent.finish(attempt)
                    targetResolutionTask = nil
                }
            }
            guard contextIsCurrent, targetIntent.owns(attempt), !Task.isCancelled else { return }
            let message = try? await client.getMessage(
                chatId: location.chatID,
                messageId: targetMessageID,
            )
            guard !Task.isCancelled, contextIsCurrent, targetIntent.owns(attempt) else { return }
            guard let message, message.chatId == location.chatID, message.id == targetMessageID,
                  case .messageTopicForum(let forumTopic) = message.topicId
            else {
                presentLoadError("The message topic couldn't be opened.")
                return
            }
            let topic = try? await client.getForumTopic(chatId: location.chatID, forumTopicId: forumTopic.forumTopicId)
            guard !Task.isCancelled, contextIsCurrent, targetIntent.owns(attempt) else { return }
            guard let topic, topic.info.chatId == location.chatID,
                  topic.info.forumTopicId == forumTopic.forumTopicId
            else {
                presentLoadError("The message topic couldn't be opened.")
                return
            }
            let opened = open(topic: topic, targetMessageID: targetMessageID, quote: targetQuote)
            targetIntent.finish(attempt, opened: opened)
            targetResolutionTask = nil
        }
    }

    @discardableResult private func open(
        topic: ForumTopic,
        targetMessageID: Int64?,
        quote: MessageQuoteHighlight?,
    ) -> Bool {
        guard contextIsCurrent, navigationController?.topViewController === self else { return false }
        let location = viewModel.location.withForumTopic(id: topic.info.forumTopicId)
        NavigationStorage.shared.push(.customChat(
            viewModel.customChat,
            location: location,
            forumTopic: topic,
            targetMessageID: targetMessageID,
            targetQuote: quote,
        ))
        return true
    }

    private func presentLoadError(_ message: String) {
        guard contextIsCurrent, navigationController?.topViewController === self,
              !didPresentLoadError, presentedViewController == nil else { return }
        didPresentLoadError = true
        let alert = UIAlertController(title: "Topics", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.didPresentLoadError = false
            self?.viewModel.loadInitial()
            self?.resolveTargetIfNeeded()
            self?.dismiss(animated: true) { self?.retryClientRestoration() }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.didPresentLoadError = false
            self?.dismiss(animated: true) { self?.retryClientRestoration() }
        })
        present(alert, animated: true)
    }

    @objc private func refreshPulled() {
        viewModel.loadInitial()
        retryClientRestoration()
    }
}

// MARK: - ForumTopicCell

final class ForumTopicCell: UITableViewCell {
    static let reuseID = "ForumTopicCell"

    private let iconView = ForumTopicIconView()
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let dateLabel = UILabel()
    private let unreadBadge = TelegramUnreadBadgeLabel(minimumDiameter: 20, horizontalPadding: 8)
    private let pinView = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let closedView = UIImageView(image: UIImage(systemName: "lock.fill"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        isAccessibilityElement = true
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.prepareForReuse()
    }

    private static func draftPreview(_ content: DraftMessageContent) -> String {
        switch content {
        case .draftMessageContentText(let text):
            "Draft: \(text.text.text)"
        case .draftMessageContentRichMessage:
            "Draft: Rich message"
        case .draftMessageContentVideoNote:
            "Draft: Video message"
        case .draftMessageContentVoiceNote:
            "Draft: Voice message"
        }
    }

    private static func dateText(timestamp: Int) -> String {
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    func configure(topic: ForumTopic, client: TDLibClient) {
        iconView.configure(info: topic.info, client: client)
        titleLabel.text = topic.info.name
        previewLabel.text =
            if let draft = topic.draftMessage {
                Self.draftPreview(draft.content)
            } else if let message = topic.lastMessage {
                ChatSummary.summary(for: message)
            } else {
                "Message preview unavailable"
            }
        previewLabel.textColor = topic.draftMessage == nil ? .secondaryLabel : .systemRed
        dateLabel.text = topic.lastMessage.map { Self.dateText(timestamp: $0.date) }
        let hasUnreadIndicator = topic.unreadCount > 0
            || topic.unreadMentionCount > 0
            || topic.unreadReactionCount > 0
            || topic.unreadPollVoteCount > 0
        pinView.isHidden = !topic.isPinned || hasUnreadIndicator
        closedView.isHidden = !topic.info.isClosed
        unreadBadge.text =
            if topic.unreadCount > 0 {
                compactNumericCountString(topic.unreadCount)
            } else if topic.unreadMentionCount > 0 {
                "@"
            } else if topic.unreadReactionCount > 0 {
                "●"
            } else if topic.unreadPollVoteCount > 0 {
                "!"
            } else {
                nil
            }
        unreadBadge.isHidden = !hasUnreadIndicator
        backgroundColor = topic.isPinned ? .secondarySystemBackground : .systemBackground
        contentView.backgroundColor = backgroundColor
        accessibilityLabel = [
            topic.info.name,
            topic.info.isClosed ? "Closed" : nil,
            topic.isPinned ? "Pinned" : nil,
            topic.unreadCount > 0 ? "\(topic.unreadCount) unread" : nil,
            topic.unreadMentionCount > 0 ? "\(topic.unreadMentionCount) unread mentions" : nil,
            topic.unreadReactionCount > 0 ? "\(topic.unreadReactionCount) unread reactions" : nil,
            topic.unreadPollVoteCount > 0 ? "\(topic.unreadPollVoteCount) unread poll votes" : nil,
            previewLabel.text,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        accessibilityIdentifier = "forum-topic-\(topic.info.forumTopicId)"
        accessibilityTraits = [.button]
    }

    private func configureViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16, weight: .medium),
            maximumPointSize: 17,
        )
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 2
        titleLabel.isAccessibilityElement = false
        contentView.addSubview(titleLabel)

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .regular),
            maximumPointSize: 17,
        )
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.isAccessibilityElement = false
        contentView.addSubview(previewLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 14, weight: .regular),
            maximumPointSize: 17,
        )
        dateLabel.textColor = .secondaryLabel
        dateLabel.isAccessibilityElement = false
        contentView.addSubview(dateLabel)

        for imageView in [pinView, closedView] {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.tintColor = .secondaryLabel
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            imageView.isAccessibilityElement = false
            contentView.addSubview(imageView)
        }

        unreadBadge.translatesAutoresizingMaskIntoConstraints = false
        unreadBadge.backgroundColor = .systemBlue
        unreadBadge.textColor = .white
        unreadBadge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        unreadBadge.isAccessibilityElement = false
        contentView.addSubview(unreadBadge)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 80),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinView.leadingAnchor, constant: -4),
            pinView.trailingAnchor.constraint(equalTo: closedView.leadingAnchor, constant: -5),
            pinView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            pinView.widthAnchor.constraint(equalToConstant: 12),
            pinView.heightAnchor.constraint(equalToConstant: 12),
            closedView.trailingAnchor.constraint(equalTo: dateLabel.leadingAnchor, constant: -6),
            closedView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closedView.widthAnchor.constraint(equalToConstant: 12),
            closedView.heightAnchor.constraint(equalToConstant: 12),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            dateLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            previewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadBadge.leadingAnchor, constant: -8),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            unreadBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            unreadBadge.centerYAnchor.constraint(equalTo: previewLabel.centerYAnchor),
            unreadBadge.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
}

// MARK: - ForumTopicIconView

private final class ForumTopicIconView: UIView {
    private let backgroundView = UIView()
    private let fallbackLabel = UILabel()
    private let fallbackImageView = UIImageView()
    private var customEmojiView: CustomEmojiInlineView?
    private var loadTask: Task<Void, Never>?
    private var generation = UInt64.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = 16
        backgroundView.layer.cornerCurve = .continuous
        addSubview(backgroundView)
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        fallbackLabel.textColor = .white
        fallbackLabel.textAlignment = .center
        addSubview(fallbackLabel)
        fallbackImageView.translatesAutoresizingMaskIntoConstraints = false
        fallbackImageView.contentMode = .center
        fallbackImageView.tintColor = .white
        addSubview(fallbackImageView)
        NSLayoutConstraint.activate([
            backgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: centerYAnchor),
            backgroundView.widthAnchor.constraint(equalToConstant: 32),
            backgroundView.heightAnchor.constraint(equalToConstant: 32),
            fallbackLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            fallbackLabel.widthAnchor.constraint(equalToConstant: 32),
            fallbackLabel.heightAnchor.constraint(equalToConstant: 32),
            fallbackImageView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            fallbackImageView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            fallbackImageView.widthAnchor.constraint(equalToConstant: 32),
            fallbackImageView.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        customEmojiView?.setPlaybackVisible(window != nil)
    }

    func configure(info: ForumTopicInfo, client: TDLibClient) {
        prepareForReuse()
        backgroundView.backgroundColor = UIColor(rgb: info.icon.color)
        if info.isGeneral {
            fallbackImageView.image = UIImage(
                systemName: "bubble.left.and.bubble.right.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
            )
            fallbackImageView.isHidden = false
            fallbackLabel.isHidden = true
        } else {
            fallbackLabel.text = info.name.first.map { String($0).uppercased() }
        }
        guard info.icon.customEmojiId.rawValue != 0 else { return }
        let currentGeneration = generation
        let identifier = info.icon.customEmojiId
        loadTask = Task { [weak self] in
            let sticker = await CustomEmojiStickerRepository.shared.stickers(
                for: [identifier],
                client: client,
            )[identifier]
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.generation == currentGeneration,
                      let sticker
                else { return }
                self.install(sticker, client: client)
            }
        }
    }

    func prepareForReuse() {
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        customEmojiView?.prepareForReuse()
        customEmojiView?.removeFromSuperview()
        customEmojiView = nil
        backgroundView.isHidden = false
        fallbackLabel.isHidden = false
        fallbackLabel.text = nil
        fallbackImageView.isHidden = true
        fallbackImageView.image = nil
    }

    private func install(_ sticker: Sticker, client: TDLibClient) {
        let view = CustomEmojiInlineView()
        customEmojiView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: centerXAnchor),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: 24),
            view.heightAnchor.constraint(equalToConstant: 24),
        ])
        view.configure(sticker: sticker, client: client)
        view.onFirstFrameReady = { [weak self, weak view] in
            guard let self, customEmojiView === view else { return }
            backgroundView.isHidden = true
            fallbackLabel.isHidden = true
            fallbackImageView.isHidden = true
        }
        view.setPlaybackVisible(window != nil)
    }
}
