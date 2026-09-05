// ForumTopicsViewController.swift

import Combine
import Foundation
import TDLibKit
import UIKit

// MARK: - ForumTopicsViewController

@MainActor final class ForumTopicsViewController: UIViewController, UITableViewDelegate {
    private enum Section {
        case topics
    }

    #if DEBUG
    var probeSnapshotCompletion: ((@escaping () -> Void) -> Void)?
    var probeModel: ForumTopicsVM { viewModel }
    var probeSearch: UISearchController { searchController }
    var probeTable: UITableView { tableView }
    var probeSnapshotBusy: Bool { snapshotState.isApplying || snapshotState.hasPending }
    var probeIDs: [Int] { snapshotState.displayedIDs }
    var probeFailure: Bool { preparationFailure != nil }
    var probeCurrent: Bool { contextIsCurrent }
    var probeRetired: Bool { retired }
    var probePrepared: Bool { preparedClient != nil }
    private(set) var probeSearchDismissals = 0
    var probePreparationTask: Task<Void, Never>? { preparationTask }
    var probeActor: Int64? { actorID }
    var probePages: ForumTopicsRestorationState { restorationState().pages }
    func probeRetryEvent() { retryClientRestoration() }
    #endif

    private var viewModel: ForumTopicsVM
    private var bindingID = UUID()
    private var boundSource: TdUpdateSource?
    private let environment: ForumTopicsClientEnvironment
    private var actorID: Int64?
    private var readySource: TdUpdateSource?
    private var identityRevoked = false
    private let targetMessageID: Int64?
    private let targetQuote: MessageQuoteHighlight?
    private let tableView = ForumTopicsTableView(frame: .zero, style: .plain)
    private lazy var navigationBarView = TelegramListNavigationBar(
        title: viewModel.customChat.displayTitle,
        placeholder: "Search Topics",
        leftImage: UIImage(systemName: "chevron.left"),
        rightImage: nil,
        leftAction: { [weak self] in self?.navigationController?.popViewController(animated: true) },
        rightAction: nil,
        showsBackButton: true,
    )
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private var searchQuery = ""
    private var didSetInitialSearchOffset = false
    private var topicsByID = [Int: ForumTopic]()
    private var isApplyingSnapshot = false
    private var pendingTopics: [ForumTopic]?
    private var dataSource: UITableViewDiffableDataSource<Section, Int>!
    private var snapshotState = ForumTopicsSnapshotState()
    private var cancellables = Set<AnyCancellable>()
    private var ownershipCancellables = Set<AnyCancellable>()
    private var targetResolutionTask: Task<Void, Never>?
    private var targetIntent: ForumTopicTargetIntent
    private let initialQuery: String
    private var previousSearchQuery: String
    private var viewportRestoration: ChatListViewportRestoration
    private var didPresentLoadError = false
    private var retired = false
    private var preparationTask: Task<Void, Never>?
    private var preparationSource: TdUpdateSource?
    private var preparationID: UUID?
    private var preparedClient: ForumTopicsClientEnvironment.Metadata?
    private var preparationFailure: (id: UUID, source: TdUpdateSource, binding: UUID)?
    private var retryScheduled = false

    var navigationClientSource: TdUpdateSource? {
        boundSource
    }

    private var routeIsRetained: Bool {
        !retired && chatListActionOwnerIsAttached
            && navigationController?.viewControllers.contains(where: { $0 === self }) == true
    }

    private var contextIsCurrent: Bool {
        guard let source = navigationClientSource else { return false }
        return routeIsRetained && !identityRevoked && (actorID == nil || actorID == environment.currentActor())
            && source == environment.currentSource() && source == readySource
            && environment.currentAccount() == viewModel.location.accountID
    }

    init(
        customChat: CustomChat,
        location: ChatLocation,
        client: TDLibClient,
        targetMessageID: Int64? = nil,
        targetQuote: MessageQuoteHighlight? = nil,
        restoration: ClientRestorationState? = nil,
        environment: ForumTopicsClientEnvironment? = nil,
    ) {
        let environment = environment ?? .live
        self.environment = environment
        self.actorID = environment.currentActor()
        self.boundSource = location.accountID.map { .init(accountID: $0, clientID: location.clientID) }
        self.viewModel = environment.model(customChat, location, client, restoration?.pages)
        self.targetMessageID = targetMessageID
        self.targetQuote = targetQuote
        self.targetIntent = ForumTopicTargetIntent(consumed: restoration?.targetConsumed ?? false)
        self.initialQuery = restoration?.rawQuery ?? ""
        self.previousSearchQuery = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.viewportRestoration = ChatListViewportRestoration(restoration?.viewport)
        super.init(nibName: nil, bundle: nil)
        observeOwnership()
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
        updateBackgroundView()
        observeState()
        viewModel.start()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        resolveTargetIfNeeded()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateNavigationBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didSetInitialSearchOffset, tableView.bounds.height > 0 else { return }
        didSetInitialSearchOffset = true
        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top + ChatListNavigationSearchView.scrollHeight),
            animated: false,
        )
        updateNavigationBar()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView, withVelocity _: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>,
    ) {
        guard !navigationBarView.isSearchActive else { return }
        let top = -scrollView.adjustedContentInset.top
        let distance = targetContentOffset.pointee.y - top
        let searchHeight = ChatListNavigationSearchView.scrollHeight
        guard distance > 0, distance < searchHeight else { return }
        targetContentOffset.pointee.y = top + (distance < searchHeight / 2 ? 0 : searchHeight)
    }

    func scrollViewDidScroll(_: UIScrollView) {
        updateNavigationBar()
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicID = dataSource.itemIdentifier(for: indexPath),
              let topic = topicsByID[topicID]
        else { return }
        open(topic: topic, targetMessageID: nil, quote: nil, model: viewModel, binding: bindingID)
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        if contextIsCurrent, snapshotState.canSelect, indexPath.row >= max(0, snapshotState.displayedIDs.count - 5) {
            viewModel.loadMore()
        }
    }

    private func updateNavigationBar() {
        guard navigationBarHeightConstraint != nil else { return }
        navigationBarView.applyScroll(offset: didSetInitialSearchOffset
            ? tableView.contentOffset.y + tableView.adjustedContentInset.top
            : ChatListNavigationSearchView.scrollHeight)
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 70
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
        tableView.register(ForumTopicCell.self, forCellReuseIdentifier: ForumTopicCell.reuseID)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureSearch() {
        tableView.contentInset.top = TelegramListNavigationBar.expandedContentHeight
        tableView.verticalScrollIndicatorInsets.top = TelegramListNavigationBar.expandedContentHeight
        navigationBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationBarView)
        navigationBarHeightConstraint = navigationBarView.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + TelegramListNavigationBar.titleHeight,
        )
        NSLayoutConstraint.activate([
            navigationBarView.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
        navigationBarView.onQueryChange = { [weak self] query in
            self?.searchQuery = query
            self?.viewModel.search(query)
        }
        navigationBarView.onVisibleHeightChange = { [weak self] height in
            guard let self else { return }
            navigationBarHeightConstraint.constant = view.safeAreaInsets.top + height
        }
        navigationBarView.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            tableView.searchScrollRange = active ? 0 : ChatListNavigationSearchView.scrollHeight
            let height = active
                ? ChatListNavigationSearchView.scrollHeight
                : TelegramListNavigationBar.expandedContentHeight
            tableView.contentInset.top = height
            tableView.verticalScrollIndicatorInsets.top = height
            tableView.layoutIfNeeded()
            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        }
        updateNavigationBar()
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Int>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, topicID in
            guard let self else { return nil }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ForumTopicCell.reuseID,
                for: indexPath,
            ) as? ForumTopicCell,
                let topic = topicsByID[topicID]
            else { return nil }
            cell.configure(topic: topic, client: viewModel.client)
            return cell
        }
    }

    private func observeState() {
        let model = viewModel
        let binding = bindingID
        model.$topics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] topics in
                guard let self, owns(model, binding: binding) else { return }
                applySnapshot(topics, client: model.client)
            }
            .store(in: &cancellables)
        model.$loading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateBackgroundView() }
            .store(in: &cancellables)
        model.$errorMessage
            .compactMap(\.self)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.presentLoadError(message, model: model, binding: binding)
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(_ topics: [ForumTopic]) {
        guard !isApplyingSnapshot else {
            pendingTopics = topics
            return
        }
        isApplyingSnapshot = true
        for topic in topics {
            topicsByID[topic.info.forumTopicId] = topic
        }
        let previousIDs = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
        snapshot.appendSections([.topics])
        snapshot.appendItems(batch.ids)
        let retainedIDs = batch.ids.filter(previousIDs.contains)
        if !retainedIDs.isEmpty {
            snapshot.reconfigureItems(retainedIDs)
        }
        dataSource.apply(snapshot, animatingDifferences: !previousIDs.isEmpty) { [weak self] in
            guard let self else { return }
            let retainedIDs = Set(topicIDs)
            topicsByID = topicsByID.filter { retainedIDs.contains($0.key) }
            isApplyingSnapshot = false
            if let pending = pendingTopics {
                pendingTopics = nil
                applySnapshot(pending)
            }
        }
        updateBackgroundView()
    }

    private func completeSnapshot(_ token: UUID, viewportToken: UUID, model: ForumTopicsVM, binding: UUID) {
        // Native UIKit ownership must close even when this binding has departed.
        guard snapshotState.complete(token) else { return }
        viewportRestoration.completeApply(viewportToken)
        guard !retired else { snapshotState.retire()
            return
        }
        if snapshotState.hasPending { drainSnapshot()
            return
        }
        if owns(model, binding: binding) {
            restoreViewportIfNeeded()
            if view.window != nil, navigationController?.topViewController === self,
               tableView.indexPathsForVisibleRows?.contains(where: {
                   $0.row >= max(0, self.snapshotState.displayedIDs.count - 5)
               }) == true { model.loadMore() }
        }
        retryClientRestoration()
    }

    private func updateBackgroundView() {
        if let failure = preparationFailure {
            let button = UIButton(type: .system)
            button.setTitle("Couldn't reconnect topics.\nTap to retry", for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.addAction(UIAction { [weak self] _ in
                guard let self, preparationFailure?.id == failure.id, bindingID == failure.binding,
                      canRenewSearch(failure.source, requiresIdleSnapshot: false) || canRestoreClient(failure.source)
                else { return }
                preparationFailure = nil
                updateBackgroundView()
                retryClientRestoration()
            }, for: .touchUpInside)
            tableView.backgroundView = button
            return
        }
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
            label.text = !searchQuery.isEmpty
                ? "No topics found"
                : "No topics"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        }
    }

    private func resolveTargetIfNeeded() {
        guard contextIsCurrent, let targetMessageID, targetResolutionTask == nil,
              !searchController.isActive,
              navigationController?.topViewController === self, let attempt = targetIntent.begin()
        else { return }
        let model = viewModel
        let binding = bindingID
        let client = model.client
        let location = model.location
        targetResolutionTask = Task { [weak self] in
            defer {
                if let self, owns(model, binding: binding, current: false), targetIntent.owns(attempt) {
                    targetIntent.finish(attempt)
                    targetResolutionTask = nil
                }
            }
            guard self?.owns(model, binding: binding) == true, self?.targetIntent.owns(attempt) == true,
                  !Task.isCancelled else { return }
            let message = try? await client.getMessage(
                chatId: location.chatID,
                messageId: targetMessageID,
            )
            guard !Task.isCancelled, self?.owns(model, binding: binding) == true,
                  self?.targetIntent.owns(attempt) == true else { return }
            guard let message, message.chatId == location.chatID, message.id == targetMessageID,
                  case .messageTopicForum(let forumTopic) = message.topicId
            else {
                self?.presentLoadError("The message topic couldn't be opened.", model: model, binding: binding)
                return
            }
            let topic = try? await client.getForumTopic(chatId: location.chatID, forumTopicId: forumTopic.forumTopicId)
            guard let self, !Task.isCancelled, owns(model, binding: binding), targetIntent.owns(attempt) else { return }
            guard let topic, topic.info.chatId == location.chatID,
                  topic.info.forumTopicId == forumTopic.forumTopicId
            else {
                presentLoadError("The message topic couldn't be opened.", model: model, binding: binding)
                return
            }
            let opened = open(
                topic: topic,
                targetMessageID: targetMessageID,
                quote: targetQuote,
                model: model,
                binding: binding,
            )
            targetIntent.finish(attempt, opened: opened)
            targetResolutionTask = nil
        }
    }

    @discardableResult private func open(
        topic: ForumTopic,
        targetMessageID: Int64?,
        quote: MessageQuoteHighlight?,
        model: ForumTopicsVM,
        binding: UUID,
    ) -> Bool {
        guard owns(model, binding: binding), targetMessageID == nil || !searchController.isActive,
              navigationController?.topViewController === self else { return false }
        let location = model.location.withForumTopic(id: topic.info.forumTopicId)
        NavigationStorage.shared.push(.customChat(
            model.customChat,
            location: location,
            forumTopic: topic,
            targetMessageID: targetMessageID,
            targetQuote: quote,
        ))
        return true
    }

    private func presentLoadError(_ message: String, model: ForumTopicsVM, binding: UUID) {
        guard owns(model, binding: binding), navigationController?.topViewController === self,
              !didPresentLoadError, presentedViewController == nil else { return }
        didPresentLoadError = true
        let alert = UIAlertController(title: "Topics", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self, weak alert] _ in
            guard let self, let alert, owns(model, binding: binding, current: false),
                  presentedViewController === alert else { return }
            didPresentLoadError = false
            if owns(model, binding: binding) { model.loadInitial()
                resolveTargetIfNeeded()
            }
            dismiss(animated: true) { [weak self] in self?.retryClientRestoration() }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self, weak alert] _ in
            guard let self, let alert, owns(model, binding: binding, current: false),
                  presentedViewController === alert else { return }
            didPresentLoadError = false
            dismiss(animated: true) { [weak self] in self?.retryClientRestoration() }
        })
        present(alert, animated: true)
    }
}

// MARK: - ForumTopicsTableView

/// A native footer gives short lists enough travel to hide search. UITableView
/// must own contentSize: overriding it makes its self-sizing row layout repeatedly
/// reconcile different content extents and animate the rows while idle.
private final class ForumTopicsTableView: UITableView {
    var searchScrollRange = ChatListNavigationSearchView.scrollHeight {
        didSet { updateScrollExtent() }
    }

    private let searchTravelFooter = UIView()

    override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollExtent()
    }

    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        updateScrollExtent()
    }

    private func updateScrollExtent() {
        guard bounds.height > 0 else { return }
        let minimumHeight = max(
            0,
            bounds.height - adjustedContentInset.top
                - adjustedContentInset.bottom + searchScrollRange,
        )
        // Section geometry excludes the table footer, so its own height cannot
        // feed back into the next calculation as contentSize would.
        let rowsBottom = numberOfSections > 0
            ? rect(forSection: numberOfSections - 1).maxY
            : tableHeaderView?.frame.maxY ?? 0
        let height = max(0, minimumHeight - rowsBottom)
        guard tableFooterView !== searchTravelFooter
            || abs(searchTravelFooter.frame.height - height) > 0.5
            || searchTravelFooter.frame.width != bounds.width else { return }
        searchTravelFooter.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        tableFooterView = searchTravelFooter
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

    static func dequeue(
        from tableView: UITableView, at indexPath: IndexPath, topic: ForumTopic?, client: TDLibClient?,
    ) -> ForumTopicCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseID, for: indexPath) as! ForumTopicCell
        if let topic, let client { cell.configure(topic: topic, client: client) }
        else { cell.configureUnavailable() }
        return cell
    }

    private static func draftPreview(_ content: DraftMessageContent) -> String {
        switch content {
        case .draftMessageContentText(let text):
            "Draft: \(text.text.text)"
        case .draftMessageContentInputRichMessage, .draftMessageContentRichMessage:
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
        iconView.isHidden = false
        selectionStyle = .default
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

    private func configureUnavailable() {
        iconView.prepareForReuse()
        iconView.isHidden = true
        titleLabel.text = "Topic unavailable"
        previewLabel.text = nil
        dateLabel.text = nil
        unreadBadge.text = nil
        unreadBadge.isHidden = true
        pinView.isHidden = true
        closedView.isHidden = true
        backgroundColor = .systemBackground
        contentView.backgroundColor = backgroundColor
        selectionStyle = .none
        accessibilityLabel = "Topic unavailable"
        accessibilityIdentifier = nil
        accessibilityTraits = [.staticText]
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
    private var representedEmojiID: Int64?
    private var representedClientID: Int32?

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
        let sameIcon = representedEmojiID == info.icon.customEmojiId && representedClientID == client.id
        if !sameIcon {
            prepareForReuse()
            representedEmojiID = info.icon.customEmojiId
            representedClientID = client.id
        }
        backgroundView.backgroundColor = UIColor(rgb: info.icon.color)
        if info.isGeneral {
            fallbackImageView.image = UIImage(
                systemName: "bubble.left.and.bubble.right.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
            )
            if !backgroundView.isHidden {
                fallbackImageView.isHidden = false
                fallbackLabel.isHidden = true
            }
        } else {
            fallbackLabel.text = info.name.first.map { String($0).uppercased() }
            fallbackImageView.isHidden = true
            fallbackLabel.isHidden = backgroundView.isHidden
        }
        guard !sameIcon, info.icon.customEmojiId != 0 else { return }
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
        representedEmojiID = nil
        representedClientID = nil
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
        view.onFirstFrameReady = { [weak self, weak view] in
            guard let self, customEmojiView === view else { return }
            backgroundView.isHidden = true
            fallbackLabel.isHidden = true
            fallbackImageView.isHidden = true
        }
        view.configure(sticker: sticker)
        view.setPlaybackVisible(window != nil)
    }
}
