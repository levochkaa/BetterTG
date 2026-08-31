// PeerProfileViewController.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - PeerProfileViewController

@MainActor final class PeerProfileViewController: UIViewController, UICollectionViewDelegate {
    enum SharedTab: Int, CaseIterable {
        case media
        case files
        case links
        case audio

        var title: String {
            switch self {
            case .media: "Media"
            case .files: "Files"
            case .links: "Links"
            case .audio: "Audio"
            }
        }

        var filter: SearchMessagesFilter {
            switch self {
            case .media: .searchMessagesFilterPhotoAndVideo
            case .files: .searchMessagesFilterDocument
            case .links: .searchMessagesFilterUrl
            case .audio: .searchMessagesFilterAudio
            }
        }
    }

    private enum Section {
        case messages
    }

    var onOpenMessage: ((Message) -> Void)?
    var onSearch: (() -> Void)?

    private let accountID: UUID
    private let client: TDLibClient
    private let customChat: CustomChat
    private let topic: MessageTopic?
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let bioLabel = UILabel()
    private let detailsLabel = UILabel()
    private let actionStack = UIStackView()
    private let profileHeaderView = UIView()
    private let segmentedControl = UISegmentedControl(items: SharedTab.allCases.map(\.title))
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Int64>!
    private var messagesByID = [Int64: Message]()
    private var cancellables = Set<AnyCancellable>()
    private var infoTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var messageRefreshTasks = [Int64: Task<Void, Never>]()
    private var messageRefreshGenerations = [Int64: UUID]()
    private var oldestMessageID: Int64?
    private var hasMore = true
    private var historyError: String?
    private var sharedTotalMessageCount: Int?
    private weak var activeMediaGallery: MediaGalleryViewController?

    private var currentSharedTab: SharedTab {
        SharedTab(rawValue: segmentedControl.selectedSegmentIndex) ?? .media
    }

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    private var sortedSharedMessages: [Message] {
        messagesByID.values.sorted {
            $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date
        }
    }

    init(customChat: CustomChat, topic: MessageTopic?, client: TDLibClient, accountID: UUID) {
        self.customChat = customChat
        self.topic = topic
        self.client = client
        self.accountID = accountID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        infoTask?.cancel()
        historyTask?.cancel()
        messageRefreshTasks.values.forEach { $0.cancel() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        view.backgroundColor = .systemBackground
        configureHeader()
        configureCollectionView()
        configureDataSource()
        observeAccount()
        loadProfileInfo()
        loadMore()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateProfileHeaderLayout()
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let message = messagesByID[id]
        else { return }
        if currentSharedTab == .media {
            openMediaGallery(selectedMessage: message)
            return
        }
        onOpenMessage?(message)
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? SharedMediaGridCell)?.resumeLoading()
        guard indexPath.item >= max(0, messagesByID.count - 6) else { return }
        loadMore()
    }

    func collectionView(
        _: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt _: IndexPath,
    ) {
        (cell as? SharedMediaGridCell)?.pauseLoading()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard historyError != nil,
              scrollView.isDragging || scrollView.isDecelerating
        else { return }
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height - scrollView.adjustedContentInset
            .bottom
        guard scrollView.contentSize.height - visibleBottom < 160 else { return }
        loadMore()
    }

    private func configureHeader() {
        profileHeaderView.backgroundColor = .systemBackground
        let headerStack = UIStackView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.axis = .vertical
        headerStack.alignment = .center
        headerStack.spacing = 7
        profileHeaderView.addSubview(headerStack)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.configure(
            file: customChat.chat.photo?.big,
            minithumbnail: customChat.chat.photo?.minithumbnail,
            placeholder: customChat.telegramAvatarPlaceholder,
        )
        avatarView.layer.cornerRadius = 48
        avatarView.clipsToBounds = true
        headerStack.addArrangedSubview(avatarView)

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.text = profileTitle()
        headerStack.addArrangedSubview(titleLabel)

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.text = initialStatus()
        headerStack.addArrangedSubview(statusLabel)

        bioLabel.font = .preferredFont(forTextStyle: .body)
        bioLabel.adjustsFontForContentSizeCategory = true
        bioLabel.textAlignment = .center
        bioLabel.numberOfLines = 3
        bioLabel.isHidden = true
        headerStack.addArrangedSubview(bioLabel)

        detailsLabel.font = .preferredFont(forTextStyle: .footnote)
        detailsLabel.adjustsFontForContentSizeCategory = true
        detailsLabel.textColor = .secondaryLabel
        detailsLabel.textAlignment = .center
        detailsLabel.numberOfLines = 3
        detailsLabel.isHidden = true
        headerStack.addArrangedSubview(detailsLabel)
        for label in [titleLabel, statusLabel, bioLabel, detailsLabel] {
            label.widthAnchor.constraint(lessThanOrEqualTo: headerStack.widthAnchor).isActive = true
        }

        actionStack.axis = .horizontal
        actionStack.distribution = .fillEqually
        actionStack.spacing = 10
        let messageButton = profileButton(title: "Message", symbol: "message.fill", action: #selector(messagePressed))
        let searchButton = profileButton(title: "Search", symbol: "magnifyingglass", action: #selector(searchPressed))
        actionStack.addArrangedSubview(messageButton)
        actionStack.addArrangedSubview(searchButton)
        headerStack.addArrangedSubview(actionStack)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentIndex = SharedTab.media.rawValue
        segmentedControl.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        profileHeaderView.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: profileHeaderView.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -20),
            avatarView.widthAnchor.constraint(equalToConstant: 96),
            avatarView.heightAnchor.constraint(equalToConstant: 96),
            actionStack.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
            actionStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            segmentedControl.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -12),
            segmentedControl.bottomAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: -8),
        ])
    }

    private func profileButton(title: String, symbol: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .top
        configuration.imagePadding = 2
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(
            SharedMediaGridCell.self,
            forCellWithReuseIdentifier: SharedMediaGridCell.reuseIdentifier,
        )
        collectionView.register(SharedMediaRowCell.self, forCellWithReuseIdentifier: SharedMediaRowCell.reuseIdentifier)
        view.addSubview(collectionView)
        collectionView.addSubview(profileHeaderView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func updateProfileHeaderLayout() {
        let width = collectionView.bounds.width
        guard width > 0 else { return }
        let oldInset = collectionView.contentInset.top
        let distanceFromTop = collectionView.contentOffset.y + oldInset
        let size = profileHeaderView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        let height = ceil(size.height)
        guard height > 0 else { return }
        profileHeaderView.frame = CGRect(x: 0, y: -height, width: width, height: height)
        guard abs(oldInset - height) > 0.5 else { return }
        collectionView.contentInset.top = height
        collectionView.verticalScrollIndicatorInsets.top = height
        collectionView.contentOffset.y = distanceFromTop - height
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] _, _ in
            guard self?.currentSharedTab == .media else {
                let size = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(64),
                )
                let item = NSCollectionLayoutItem(layoutSize: size)
                let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 20, trailing: 12)
                section.interGroupSpacing = 1
                return section
            }
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / 3),
                heightDimension: .fractionalHeight(1),
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalWidth(1 / 3),
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 3)
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 1, bottom: 20, trailing: 1)
            return section
        }
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Int64>(
            collectionView: collectionView,
        ) { [weak self] collectionView, indexPath, id in
            guard let self, let message = messagesByID[id] else { return UICollectionViewCell() }
            if currentSharedTab == .media {
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SharedMediaGridCell.reuseIdentifier,
                    for: indexPath,
                ) as? SharedMediaGridCell
                cell?.configure(message: message)
                return cell ?? UICollectionViewCell()
            }
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SharedMediaRowCell.reuseIdentifier,
                for: indexPath,
            ) as? SharedMediaRowCell
            cell?.configure(message: message)
            return cell ?? UICollectionViewCell()
        }
    }

    private func openMediaGallery(selectedMessage: Message) {
        guard contextIsCurrent, presentedViewController == nil else { return }
        let messages = sortedSharedMessages.filter { message in
            switch message.content {
            case .messagePhoto, .messageVideo:
                true
            default:
                false
            }
        }
        guard messages.contains(where: { $0.id == selectedMessage.id }) else { return }
        let transitionSource = mediaTransitionTarget(for: selectedMessage.id)
        let gallery = MediaGalleryViewController(
            messages: messages,
            selection: selectedMessage.id,
            totalMessageCount: sharedTotalMessageCount,
            tdlib: .shared,
            transitionSource: transitionSource,
            transitionSourceProvider: { [weak self] messageID in
                self?.mediaTransitionTarget(for: messageID)
            },
        )
        gallery.onRequestMoreMessages = { [weak self] in
            guard let self, contextIsCurrent else { return }
            loadMore()
        }
        gallery.contextIsCurrent = { [weak self] in
            self?.contextIsCurrent == true
        }
        activeMediaGallery = gallery
        present(gallery, animated: true)
    }

    private func mediaTransitionTarget(for messageID: Int64) -> MediaGalleryTransitionTarget? {
        guard let indexPath = dataSource.indexPath(for: messageID),
              let cell = collectionView.cellForItem(at: indexPath) as? SharedMediaGridCell
        else { return nil }
        return cell.transitionTarget(for: messageID) { [weak self, weak cell] in
            guard let self, let cell, contextIsCurrent,
                  let currentIndexPath = dataSource.indexPath(for: messageID)
            else { return false }
            return collectionView.cellForItem(at: currentIndexPath) === cell
        }
    }

    private func observeAccount() {
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            self?.handleAccountChange()
        }
        nc.publisher(&cancellables, for: .updateMessageContent) { [weak self] update in
            self?.refreshSharedMessage(id: update.messageId, chatID: update.chatId)
        }
        nc.publisher(&cancellables, for: .updateMessageEdited) { [weak self] update in
            self?.refreshSharedMessage(id: update.messageId, chatID: update.chatId)
        }
        TDLib.shared
            .deleteMessageUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self,
                      contextIsCurrent,
                      !update.fromCache,
                      update.isPermanent,
                      update.chatId == customChat.id
                else { return }
                let deletedIDs = Set(update.messageIds)
                let previousCount = messagesByID.count
                messagesByID = messagesByID.filter { !deletedIDs.contains($0.key) }
                guard messagesByID.count != previousCount else { return }
                if let sharedTotalMessageCount {
                    self.sharedTotalMessageCount = max(
                        messagesByID.count,
                        sharedTotalMessageCount - (previousCount - messagesByID.count),
                    )
                }
                if let oldestMessageID, deletedIDs.contains(oldestMessageID) {
                    self.oldestMessageID = sortedSharedMessages.last?.id
                }
                applySnapshot()
            }
            .store(in: &cancellables)
    }

    private func handleAccountChange() {
        guard !contextIsCurrent else { return }
        let leaveProfile: () -> Void = { [weak self] in
            _ = self?.navigationController?.popViewController(animated: true)
        }
        if let activeMediaGallery {
            activeMediaGallery.invalidateForContextChange(completion: leaveProfile)
            return
        }
        if presentedViewController != nil {
            dismiss(animated: false, completion: leaveProfile)
        } else {
            leaveProfile()
        }
    }

    private func refreshSharedMessage(id: Int64, chatID: Int64) {
        guard contextIsCurrent,
              chatID == customChat.id,
              messagesByID[id] != nil
        else { return }
        messageRefreshTasks[id]?.cancel()
        let generation = UUID()
        messageRefreshGenerations[id] = generation
        let requestedTab = currentSharedTab
        messageRefreshTasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await client.getMessage(chatId: customChat.id, messageId: id)
                guard messageRefreshGenerations[id] == generation else { return }
                guard !Task.isCancelled,
                      contextIsCurrent,
                      currentSharedTab == requestedTab
                else {
                    finishMessageRefresh(id: id, generation: generation)
                    return
                }
                messagesByID[id] =
                    if let topic, message.topicId != topic {
                        nil
                    } else {
                        message
                    }
                finishMessageRefresh(id: id, generation: generation)
                applySnapshot()
            } catch {
                finishMessageRefresh(id: id, generation: generation)
            }
        }
    }

    private func finishMessageRefresh(id: Int64, generation: UUID) {
        guard messageRefreshGenerations[id] == generation else { return }
        messageRefreshGenerations[id] = nil
        messageRefreshTasks[id] = nil
    }

    private func loadProfileInfo() {
        infoTask?.cancel()
        infoTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result: (bio: String?, details: [String], status: String?)
                switch customChat.type {
                case .bot(let user), .user(let user):
                    let info = try await client.getUserFullInfo(userId: user.id)
                    var details = user.usernames?.activeUsernames.map { "@\($0)" } ?? []
                    if !user.phoneNumber.isEmpty {
                        details.append("+\(user.phoneNumber)")
                    }
                    let bio = info.bio?.text ?? info.botInfo?.description ?? info.botInfo?.shortDescription
                    result = (bio, details, nil)
                case .group(let group):
                    let info = try await client.getBasicGroupFullInfo(basicGroupId: group.id)
                    result = (info.description, [], nil)
                case .supergroup(let group):
                    let info = try await client.getSupergroupFullInfo(supergroupId: group.id)
                    let usernames = group.usernames?.activeUsernames.map { "@\($0)" } ?? []
                    let noun = group.isChannel ? "subscribers" : "members"
                    result = (info.description, usernames, info.memberCount > 0 ? "\(info.memberCount) \(noun)" : nil)
                }
                guard !Task.isCancelled, contextIsCurrent else { return }
                if let status = result.status {
                    statusLabel.text = status
                }
                let bio = result.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                bioLabel.text = bio
                bioLabel.isHidden = bio.isEmpty
                detailsLabel.text = result.details.joined(separator: " · ")
                detailsLabel.isHidden = result.details.isEmpty
                infoTask = nil
                view.setNeedsLayout()
            } catch {
                guard !Task.isCancelled, contextIsCurrent else { return }
                bioLabel.text = "Profile information is unavailable."
                bioLabel.textColor = .secondaryLabel
                bioLabel.isHidden = false
                infoTask = nil
                view.setNeedsLayout()
            }
        }
    }

    private func loadMore() {
        guard historyTask == nil, hasMore, contextIsCurrent else { return }
        let fromMessageID = oldestMessageID ?? 0
        let requestedTab = currentSharedTab
        historyError = nil
        historyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.searchChatMessages(
                    chatId: customChat.id,
                    filter: requestedTab.filter,
                    fromMessageId: fromMessageID,
                    limit: 30,
                    offset: 0,
                    query: "",
                    senderId: nil,
                    topicId: topic,
                )
                guard !Task.isCancelled,
                      contextIsCurrent,
                      currentSharedTab == requestedTab
                else { return }
                let messages = result.messages
                let nextCursor = messages.last?.id
                for message in messages {
                    messagesByID[message.id] = message
                }
                sharedTotalMessageCount = max(messagesByID.count, result.totalCount)
                oldestMessageID = nextCursor
                hasMore = !messages.isEmpty && (fromMessageID == 0 || nextCursor != fromMessageID)
                historyError = nil
                historyTask = nil
                applySnapshot()
            } catch is CancellationError {
                if currentSharedTab == requestedTab {
                    historyTask = nil
                    applySnapshot()
                }
            } catch {
                guard contextIsCurrent, currentSharedTab == requestedTab else { return }
                historyError = "Couldn't load shared \(requestedTab.title.lowercased())."
                historyTask = nil
                activeMediaGallery?.allowMoreMessagesRetry()
                applySnapshot()
            }
        }
        if messagesByID.isEmpty {
            applySnapshot()
        }
    }

    private func applySnapshot() {
        let messages = sortedSharedMessages
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(messages.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: true)
        if currentSharedTab == .media {
            activeMediaGallery?.updateMessages(messages)
            activeMediaGallery?.updateTotalMessageCount(sharedTotalMessageCount)
        }
        guard messages.isEmpty else {
            collectionView.backgroundView = nil
            return
        }
        if let historyError {
            var configuration = UIButton.Configuration.plain()
            configuration.title = "\(historyError)\nTap to retry"
            let button = UIButton(configuration: configuration)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.addTarget(self, action: #selector(retrySharedMedia), for: .touchUpInside)
            button.accessibilityHint = "Retries loading shared media"
            collectionView.backgroundView = button
        } else {
            let label = UILabel()
            label.text = historyTask == nil ? "No shared \(currentSharedTab.title.lowercased())" : "Loading…"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            collectionView.backgroundView = label
        }
    }

    private func initialStatus() -> String {
        if customChat.isSavedMessages {
            return "Saved Messages"
        }
        switch customChat.type {
        case .bot:
            return "bot"
        case .user(let user):
            return switch user.status {
            case .userStatusOnline: "online"
            case .userStatusRecently: "last seen recently"
            case .userStatusLastWeek: "last seen within a week"
            case .userStatusLastMonth: "last seen within a month"
            case .userStatusEmpty, .userStatusOffline: "offline"
            }
        case .group(let group):
            return "\(group.memberCount) members"
        case .supergroup(let group):
            return group.isChannel ? "channel" : (group.isForum ? "forum" : "group")
        }
    }

    private func profileTitle() -> String {
        guard customChat.isSavedMessages, let user = customChat.user else {
            return customChat.displayTitle
        }
        let name = [user.firstName, user.lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? customChat.displayTitle : name
    }

    @objc private func tabChanged() {
        historyTask?.cancel()
        historyTask = nil
        messageRefreshTasks.values.forEach { $0.cancel() }
        messageRefreshTasks = [:]
        messageRefreshGenerations = [:]
        messagesByID = [:]
        oldestMessageID = nil
        hasMore = true
        historyError = nil
        sharedTotalMessageCount = nil
        collectionView.collectionViewLayout.invalidateLayout()
        loadMore()
    }

    @objc private func messagePressed() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func retrySharedMedia() {
        loadMore()
    }

    @objc private func searchPressed() {
        onSearch?()
    }
}

// MARK: - SharedMediaGridCell

private final class SharedMediaGridCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedMediaGridCell"

    private let imageView = TDImageLoadingView()
    private let videoBadge = UIImageView(image: UIImage(systemName: "play.fill"))
    private var representedMessage: Message?
    private var loadingIsPaused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        videoBadge.translatesAutoresizingMaskIntoConstraints = false
        videoBadge.tintColor = .white
        videoBadge.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        videoBadge.layer.cornerRadius = 10
        videoBadge.contentMode = .center
        contentView.addSubview(videoBadge)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            videoBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            videoBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            videoBadge.widthAnchor.constraint(equalToConstant: 24),
            videoBadge.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
        imageView.image = nil
        representedMessage = nil
        loadingIsPaused = false
    }

    func configure(message: Message) {
        representedMessage = message
        loadingIsPaused = false
        loadThumbnail(for: message)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(MessageContentPresentation.make(message).summary), \(profileDateString(message.date))"
    }

    func pauseLoading() {
        guard representedMessage != nil else { return }
        loadingIsPaused = true
        imageView.cancel()
    }

    func resumeLoading() {
        guard loadingIsPaused, let representedMessage else { return }
        loadingIsPaused = false
        loadThumbnail(for: representedMessage)
    }

    func transitionTarget(
        for messageID: Int64,
        validation additionalValidation: @escaping () -> Bool,
    ) -> MediaGalleryTransitionTarget? {
        guard representedMessage?.id == messageID else { return nil }
        return MediaGalleryTransitionTarget(
            messageID: messageID,
            sourceView: imageView,
            snapshotFactory: { [weak imageView] in
                imageView?.makeImageSnapshot(contentMode: .scaleAspectFill)
            },
            validation: { [weak self] in
                self?.representedMessage?.id == messageID
                    && self?.window != nil
                    && additionalValidation()
            },
        )
    }

    private func loadThumbnail(for message: Message) {
        switch message.content {
        case .messagePhoto(let photo):
            imageView.load(photo: photo.photo, preferredSize: .yBox)
            videoBadge.isHidden = true
        case .messageVideo(let video):
            if let thumbnail = video.video.thumbnail {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: video.video.minithumbnail?.data,
                    maximumPixelSize: 480,
                )
            } else {
                imageView.loadPlaceholder(data: video.video.minithumbnail?.data)
            }
            videoBadge.isHidden = false
        default:
            imageView.loadPlaceholder(data: nil)
            videoBadge.isHidden = true
        }
    }
}

// MARK: - SharedMediaRowCell

private final class SharedMediaRowCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedMediaRowCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .systemBlue
        iconView.contentMode = .center
        contentView.addSubview(iconView)
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 2
        contentView.addSubview(labels)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            labels.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func configure(message: Message) {
        let presentation = MessageContentPresentation.make(message)
        titleLabel.text = presentation.summary
        subtitleLabel.text = profileDateString(message.date)
        iconView.image = UIImage(systemName: icon(for: message.content))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(presentation.summary), \(profileDateString(message.date))"
    }

    private func icon(for content: MessageContent) -> String {
        switch content {
        case .messageDocument: "doc.fill"
        case .messageAudio: "music.note"
        default: "link"
        }
    }
}

// MARK: - ProfileDateFormatting

private enum ProfileDateFormatting {
    static let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
}

private func profileDateString(_ timestamp: Int) -> String {
    Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(ProfileDateFormatting.style)
}
