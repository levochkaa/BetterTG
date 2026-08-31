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

    private struct AvatarGalleryPayload {
        let hasExtraCurrentPhoto: Bool
        let historyRawOffset: Int
        let historyTotalCount: Int
        let items: [ProfileAvatarGalleryItem]
        let totalCount: Int
        let userID: Int64?
    }

    var onOpenMessage: ((Message) -> Void)?
    var onSearch: (() -> Void)?

    private let accountID: UUID
    private let client: TDLibClient
    private let customChat: CustomChat
    private let topic: MessageTopic?
    private var currentChatTitle: String
    private var currentChatPhotoInfo: ChatPhotoInfo?
    private var currentStatusText: String
    private var currentBioText = ""
    private var currentDetailTexts = [String]()
    private let avatarView = ProfileAvatarView()
    private lazy var avatarTapGesture = UITapGestureRecognizer(target: self, action: #selector(avatarPressed))
    private let avatarLoadingIndicator = UIActivityIndicatorView(style: .medium)
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
    private var avatarGalleryTask: Task<Void, Never>?
    private var avatarHistoryTask: Task<Void, Never>?
    private var chatMetadataTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var messageRefreshTasks = [Int64: Task<Void, Never>]()
    private var messageRefreshGenerations = [Int64: UUID]()
    private var oldestMessageID: Int64?
    private var hasMore = true
    private var historyError: String?
    private var sharedTotalMessageCount: Int?
    private var currentProfilePhoto: ChatPhoto?
    private var avatarHistoryRawOffset = 0
    private var avatarHistoryTotalCount = 0
    private var avatarHistoryHasExtraCurrentPhoto = false
    private var avatarHistoryKnownPhotoIDs = Set<Int64>()
    private var avatarHistoryUserID: Int64?
    private var metadataGeneration = UInt64.zero
    private var fullInfoGeneration = UInt64.zero
    private var avatarMetadataGeneration = UInt64.zero
    private var hasHydratedFullInfo = false
    private var metadataRenderScheduled = false
    private weak var activeMediaGallery: MediaGalleryViewController?
    private weak var activeAvatarGallery: ProfileAvatarGalleryViewController?

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
        self.currentChatTitle = customChat.displayTitle
        self.currentChatPhotoInfo = customChat.chat.photo
        self.currentStatusText = Self.statusText(for: customChat)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        infoTask?.cancel()
        avatarGalleryTask?.cancel()
        avatarHistoryTask?.cancel()
        chatMetadataTask?.cancel()
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        avatarGalleryTask?.cancel()
        avatarHistoryTask?.cancel()
        finishAvatarGalleryLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateProfileHeaderLayout()
    }

    private static func statusText(for customChat: CustomChat) -> String {
        if customChat.isSavedMessages {
            return "Saved Messages"
        }
        switch customChat.type {
        case .bot:
            return "bot"
        case .user(let user):
            return statusText(for: user.status)
        case .group(let group):
            return "\(group.memberCount) members"
        case .supergroup(let group):
            return group.isChannel ? "channel" : (group.isForum ? "forum" : "group")
        }
    }

    private static func statusText(for status: UserStatus) -> String {
        switch status {
        case .userStatusOnline: "online"
        case .userStatusRecently: "last seen recently"
        case .userStatusLastWeek: "last seen within a week"
        case .userStatusLastMonth: "last seen within a month"
        case .userStatusEmpty, .userStatusOffline: "offline"
        }
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
            file: currentChatPhotoInfo?.big,
            minithumbnail: currentChatPhotoInfo?.minithumbnail,
            placeholder: customChat.telegramAvatarPlaceholder,
        )
        avatarView.layer.cornerRadius = 48
        avatarView.clipsToBounds = true
        let avatarGalleryIsAvailable = !customChat.isSavedMessages && currentChatPhotoInfo != nil
        avatarView.isAccessibilityElement = true
        avatarView.accessibilityLabel = "\(profileTitle()) profile photo"
        avatarView.accessibilityHint = avatarGalleryIsAvailable ? "Opens profile photos" : nil
        avatarView.accessibilityTraits = avatarGalleryIsAvailable ? [.button, .image] : .image
        avatarTapGesture.isEnabled = avatarGalleryIsAvailable
        avatarView.addGestureRecognizer(avatarTapGesture)
        headerStack.addArrangedSubview(avatarView)
        avatarLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        avatarLoadingIndicator.color = .white
        avatarLoadingIndicator.hidesWhenStopped = true
        avatarView.addSubview(avatarLoadingIndicator)

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
            avatarLoadingIndicator.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarLoadingIndicator.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
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
        nc.publisher(&cancellables, for: .updateChatTitle) { [weak self] update in
            self?.handleChatTitleUpdate(update)
        }
        nc.publisher(&cancellables, for: .updateChatPhoto) { [weak self] update in
            self?.handleChatPhotoUpdate(update)
        }
        nc.publisher(&cancellables, for: .updateUserStatus) { [weak self] update in
            self?.handleUserStatusUpdate(update)
        }
        nc.publisher(&cancellables, for: .updateUser) { [weak self] update in
            self?.handleUserUpdate(update)
        }
        nc.publisher(&cancellables, for: .updateBasicGroup) { [weak self] update in
            self?.handleBasicGroupUpdate(update)
        }
        nc.publisher(&cancellables, for: .updateSupergroup) { [weak self] update in
            self?.handleSupergroupUpdate(update)
        }
        nc.publisher(&cancellables, for: .updateUserFullInfo) { [weak self] update in
            self?.handleUserFullInfoUpdate(update)
        }
        nc.publisher(&cancellables, for: .updateBasicGroupFullInfo) { [weak self] update in
            self?.handleBasicGroupFullInfoUpdate(update)
        }
        nc.publisher(&cancellables, for: .updateSupergroupFullInfo) { [weak self] update in
            self?.handleSupergroupFullInfoUpdate(update)
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

    private func handleChatTitleUpdate(_ update: UpdateChatTitle) {
        guard contextIsCurrent, update.chatId == customChat.id else { return }
        currentChatTitle = update.title
        scheduleMetadataRender()
        refreshChatMetadata()
    }

    private func handleChatPhotoUpdate(_ update: UpdateChatPhoto) {
        guard contextIsCurrent, update.chatId == customChat.id else { return }
        currentChatPhotoInfo = update.photo
        currentProfilePhoto = nil
        hasHydratedFullInfo = false
        resetAvatarGalleryForMetadataChange()
        scheduleMetadataRender()
        refreshChatMetadata()
        loadProfileInfo()
    }

    private func handleUserStatusUpdate(_ update: UpdateUserStatus) {
        guard contextIsCurrent, update.userId == customChat.user?.id else { return }
        currentStatusText = Self.statusText(for: update.status)
        scheduleMetadataRender()
    }

    private func handleUserUpdate(_ update: UpdateUser) {
        guard contextIsCurrent, update.user.id == customChat.user?.id else { return }
        metadataGeneration &+= 1
        chatMetadataTask?.cancel()
        chatMetadataTask = nil
        customChat.updatePrivateUser(update.user)
        let name = [update.user.firstName, update.user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty, !customChat.isSavedMessages {
            currentChatTitle = name
        }
        currentStatusText = Self.statusText(for: update.user.status)
        currentDetailTexts = update.user.usernames?.activeUsernames.map { "@\($0)" } ?? []
        if !update.user.phoneNumber.isEmpty {
            currentDetailTexts.append("+\(update.user.phoneNumber)")
        }
        scheduleMetadataRender()
        loadProfileInfo()
    }

    private func handleBasicGroupUpdate(_ update: UpdateBasicGroup) {
        guard contextIsCurrent, update.basicGroup.id == customChat.group?.id else { return }
        customChat.type = .group(update.basicGroup)
        currentStatusText = "\(update.basicGroup.memberCount) members"
        scheduleMetadataRender()
    }

    private func handleSupergroupUpdate(_ update: UpdateSupergroup) {
        guard contextIsCurrent, update.supergroup.id == customChat.supergroup?.id else { return }
        customChat.type = .supergroup(update.supergroup)
        currentStatusText =
            if update.supergroup.memberCount > 0 {
                "\(update.supergroup.memberCount) \(update.supergroup.isChannel ? "subscribers" : "members")"
            } else {
                update.supergroup.isChannel
                    ? "channel"
                    : (update.supergroup.isForum ? "forum" : "group")
            }
        currentDetailTexts = update.supergroup.usernames?.activeUsernames.map { "@\($0)" } ?? []
        scheduleMetadataRender()
    }

    private func handleUserFullInfoUpdate(_ update: UpdateUserFullInfo) {
        guard contextIsCurrent,
              update.userId == customChat.user?.id,
              let user = customChat.user
        else { return }
        fullInfoGeneration &+= 1
        infoTask?.cancel()
        infoTask = nil
        applyUserFullInfo(update.userFullInfo, user: user)
    }

    private func handleBasicGroupFullInfoUpdate(_ update: UpdateBasicGroupFullInfo) {
        guard contextIsCurrent,
              update.basicGroupId == customChat.group?.id
        else { return }
        fullInfoGeneration &+= 1
        infoTask?.cancel()
        infoTask = nil
        applyFullInfo(
            bio: update.basicGroupFullInfo.description,
            details: [],
            status: nil,
            photo: update.basicGroupFullInfo.photo,
        )
    }

    private func handleSupergroupFullInfoUpdate(_ update: UpdateSupergroupFullInfo) {
        guard contextIsCurrent,
              let group = customChat.supergroup,
              update.supergroupId == group.id
        else { return }
        fullInfoGeneration &+= 1
        infoTask?.cancel()
        infoTask = nil
        let noun = group.isChannel ? "subscribers" : "members"
        applyFullInfo(
            bio: update.supergroupFullInfo.description,
            details: group.usernames?.activeUsernames.map { "@\($0)" } ?? [],
            status: update.supergroupFullInfo.memberCount > 0
                ? "\(update.supergroupFullInfo.memberCount) \(noun)"
                : nil,
            photo: update.supergroupFullInfo.photo,
        )
    }

    private func refreshChatMetadata() {
        metadataGeneration &+= 1
        let generation = metadataGeneration
        chatMetadataTask?.cancel()
        chatMetadataTask = Task { [weak self] in
            guard let self else { return }
            let chat = try? await client.getChat(chatId: customChat.id)
            guard !Task.isCancelled,
                  contextIsCurrent,
                  metadataGeneration == generation,
                  let chat
            else { return }
            customChat.chat = chat
            currentChatTitle = customChat.isSavedMessages ? "Saved Messages" : chat.title
            if currentChatPhotoInfo != chat.photo {
                currentProfilePhoto = nil
                hasHydratedFullInfo = false
                resetAvatarGalleryForMetadataChange()
            }
            currentChatPhotoInfo = chat.photo
            chatMetadataTask = nil
            scheduleMetadataRender()
        }
    }

    private func applyUserFullInfo(_ info: UserFullInfo, user: User) {
        var details = user.usernames?.activeUsernames.map { "@\($0)" } ?? []
        if !user.phoneNumber.isEmpty {
            details.append("+\(user.phoneNumber)")
        }
        applyFullInfo(
            bio: info.bio?.text ?? info.botInfo?.description ?? info.botInfo?.shortDescription,
            details: details,
            status: nil,
            photo: info.personalPhoto ?? info.photo ?? info.publicPhoto,
        )
    }

    private func applyFullInfo(
        bio: String?,
        details: [String],
        status: String?,
        photo: ChatPhoto?,
    ) {
        currentBioText = bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        currentDetailTexts = details
        if let status {
            currentStatusText = status
        }
        if hasHydratedFullInfo, currentProfilePhoto?.id != photo?.id {
            resetAvatarGalleryForMetadataChange()
        }
        hasHydratedFullInfo = true
        currentProfilePhoto = photo
        scheduleMetadataRender()
    }

    private func resetAvatarGalleryForMetadataChange() {
        avatarMetadataGeneration &+= 1
        avatarGalleryTask?.cancel()
        avatarHistoryTask?.cancel()
        avatarGalleryTask = nil
        avatarHistoryTask = nil
        avatarHistoryRawOffset = 0
        avatarHistoryTotalCount = 0
        avatarHistoryHasExtraCurrentPhoto = false
        avatarHistoryKnownPhotoIDs = []
        avatarHistoryUserID = nil
        activeAvatarGallery?.dismiss(animated: false)
        activeAvatarGallery = nil
        avatarLoadingIndicator.stopAnimating()
    }

    private func scheduleMetadataRender() {
        guard !metadataRenderScheduled else { return }
        metadataRenderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            metadataRenderScheduled = false
            renderMetadata()
        }
    }

    private func renderMetadata() {
        titleLabel.text = profileTitle()
        statusLabel.text = currentStatusText
        statusLabel.textColor = currentStatusText == "online" ? .systemGreen : .secondaryLabel
        bioLabel.text = currentBioText
        bioLabel.textColor = .label
        bioLabel.isHidden = currentBioText.isEmpty
        detailsLabel.text = currentDetailTexts.joined(separator: " · ")
        detailsLabel.isHidden = currentDetailTexts.isEmpty
        avatarView.configure(
            file: currentChatPhotoInfo?.big,
            minithumbnail: currentChatPhotoInfo?.minithumbnail,
            placeholder: customChat.telegramAvatarPlaceholder,
        )
        let avatarGalleryIsAvailable = !customChat.isSavedMessages && currentChatPhotoInfo != nil
        avatarTapGesture.isEnabled = avatarGalleryIsAvailable
        avatarView.accessibilityLabel = "\(profileTitle()) profile photo"
        avatarView.accessibilityHint = avatarGalleryIsAvailable ? "Opens profile photos" : nil
        avatarView.accessibilityTraits = avatarGalleryIsAvailable ? [.button, .image] : .image
        view.setNeedsLayout()
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
        fullInfoGeneration &+= 1
        let generation = fullInfoGeneration
        infoTask?.cancel()
        infoTask = Task { [weak self] in
            guard let self else { return }
            do {
                switch customChat.type {
                case .bot(let user), .user(let user):
                    let info = try await client.getUserFullInfo(userId: user.id)
                    guard !Task.isCancelled,
                          contextIsCurrent,
                          fullInfoGeneration == generation
                    else { return }
                    applyUserFullInfo(info, user: user)
                case .group(let group):
                    let info = try await client.getBasicGroupFullInfo(basicGroupId: group.id)
                    guard !Task.isCancelled,
                          contextIsCurrent,
                          fullInfoGeneration == generation
                    else { return }
                    applyFullInfo(bio: info.description, details: [], status: nil, photo: info.photo)
                case .supergroup(let group):
                    let info = try await client.getSupergroupFullInfo(supergroupId: group.id)
                    let noun = group.isChannel ? "subscribers" : "members"
                    guard !Task.isCancelled,
                          contextIsCurrent,
                          fullInfoGeneration == generation
                    else { return }
                    applyFullInfo(
                        bio: info.description,
                        details: group.usernames?.activeUsernames.map { "@\($0)" } ?? [],
                        status: info.memberCount > 0 ? "\(info.memberCount) \(noun)" : nil,
                        photo: info.photo,
                    )
                }
                if fullInfoGeneration == generation {
                    infoTask = nil
                }
            } catch {
                guard !Task.isCancelled,
                      contextIsCurrent,
                      fullInfoGeneration == generation
                else { return }
                infoTask = nil
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
        currentStatusText
    }

    private func profileTitle() -> String {
        guard customChat.isSavedMessages, let user = customChat.user else {
            return currentChatTitle
        }
        let name = [user.firstName, user.lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? customChat.displayTitle : name
    }

    @objc private func avatarPressed() {
        guard !customChat.isSavedMessages,
              currentChatPhotoInfo != nil,
              avatarGalleryTask == nil,
              contextIsCurrent,
              presentedViewController == nil
        else { return }
        avatarLoadingIndicator.startAnimating()
        let avatarGeneration = avatarMetadataGeneration
        avatarGalleryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await loadAvatarGalleryPayload()
                guard !Task.isCancelled,
                      contextIsCurrent,
                      avatarMetadataGeneration == avatarGeneration,
                      view.window != nil,
                      navigationController?.topViewController === self,
                      presentedViewController == nil,
                      let selectedItem = payload.items.first
                else {
                    finishAvatarGalleryLoad()
                    return
                }
                let transitionSource = avatarTransitionTarget(itemID: selectedItem.id)
                let gallery = ProfileAvatarGalleryViewController(
                    accountID: accountID,
                    client: client,
                    items: payload.items,
                    selection: selectedItem.id,
                    totalCount: payload.totalCount,
                    transitionSource: transitionSource,
                    transitionSourceProvider: { [weak self] itemID in
                        guard itemID == selectedItem.id else { return nil }
                        return self?.avatarTransitionTarget(itemID: itemID)
                    },
                )
                gallery.contextIsCurrent = { [weak self] in
                    self?.contextIsCurrent == true
                }
                avatarHistoryRawOffset = payload.historyRawOffset
                avatarHistoryTotalCount = payload.historyTotalCount
                avatarHistoryHasExtraCurrentPhoto = payload.hasExtraCurrentPhoto
                avatarHistoryKnownPhotoIDs = Set(payload.items.map(\.id))
                avatarHistoryUserID = payload.userID
                activeAvatarGallery = gallery
                if payload.userID != nil {
                    gallery.onRequestMoreItems = { [weak self] in
                        self?.loadMoreAvatarHistory()
                    }
                }
                finishAvatarGalleryLoad()
                present(gallery, animated: true)
            } catch {
                guard !Task.isCancelled else { return }
                let fallback = ProfileAvatarGalleryItem(current: currentChatPhotoInfo)
                guard contextIsCurrent,
                      avatarMetadataGeneration == avatarGeneration,
                      view.window != nil,
                      navigationController?.topViewController === self,
                      presentedViewController == nil,
                      let fallback
                else {
                    finishAvatarGalleryLoad()
                    return
                }
                let transitionSource = avatarTransitionTarget(itemID: fallback.id)
                let gallery = ProfileAvatarGalleryViewController(
                    accountID: accountID,
                    client: client,
                    items: [fallback],
                    selection: fallback.id,
                    totalCount: 1,
                    transitionSource: transitionSource,
                    transitionSourceProvider: { [weak self] itemID in
                        guard itemID == fallback.id else { return nil }
                        return self?.avatarTransitionTarget(itemID: itemID)
                    },
                )
                gallery.contextIsCurrent = { [weak self] in
                    self?.contextIsCurrent == true
                }
                avatarHistoryRawOffset = 0
                avatarHistoryTotalCount = 0
                avatarHistoryHasExtraCurrentPhoto = false
                avatarHistoryKnownPhotoIDs = [fallback.id]
                avatarHistoryUserID = nil
                activeAvatarGallery = gallery
                finishAvatarGalleryLoad()
                present(gallery, animated: true)
            }
        }
    }

    private func loadAvatarGalleryPayload() async throws -> AvatarGalleryPayload {
        switch customChat.type {
        case .bot(let user), .user(let user):
            let info = try await client.getUserFullInfo(userId: user.id)
            let currentPhoto = info.personalPhoto ?? info.photo ?? info.publicPhoto ?? currentProfilePhoto
            let result = try await client.getUserProfilePhotos(limit: 100, offset: 0, userId: user.id)
            var photos = result.photos
            var totalCount = result.totalCount
            let hasExtraCurrentPhoto: Bool
            if let currentPhoto {
                photos.removeAll(where: { $0.id == currentPhoto.id })
                photos.insert(currentPhoto, at: 0)
                hasExtraCurrentPhoto = !result.photos.contains(where: { $0.id == currentPhoto.id })
                if hasExtraCurrentPhoto {
                    totalCount += 1
                }
            } else {
                hasExtraCurrentPhoto = false
            }
            var items = photos.map(ProfileAvatarGalleryItem.init(photo:))
            if items.isEmpty, let fallback = ProfileAvatarGalleryItem(current: currentChatPhotoInfo) {
                items = [fallback]
                totalCount = max(totalCount, 1)
            }
            return AvatarGalleryPayload(
                hasExtraCurrentPhoto: hasExtraCurrentPhoto,
                historyRawOffset: result.photos.count,
                historyTotalCount: result.totalCount,
                items: items,
                totalCount: totalCount,
                userID: user.id,
            )
        case .group(let group):
            let info = try await client.getBasicGroupFullInfo(basicGroupId: group.id)
            let photo = info.photo ?? currentProfilePhoto
            if let photo {
                return AvatarGalleryPayload(
                    hasExtraCurrentPhoto: false,
                    historyRawOffset: 0,
                    historyTotalCount: 0,
                    items: [ProfileAvatarGalleryItem(photo: photo)],
                    totalCount: 1,
                    userID: nil,
                )
            }
        case .supergroup(let group):
            let info = try await client.getSupergroupFullInfo(supergroupId: group.id)
            let photo = info.photo ?? currentProfilePhoto
            if let photo {
                return AvatarGalleryPayload(
                    hasExtraCurrentPhoto: false,
                    historyRawOffset: 0,
                    historyTotalCount: 0,
                    items: [ProfileAvatarGalleryItem(photo: photo)],
                    totalCount: 1,
                    userID: nil,
                )
            }
        }
        if let fallback = ProfileAvatarGalleryItem(current: currentChatPhotoInfo) {
            return AvatarGalleryPayload(
                hasExtraCurrentPhoto: false,
                historyRawOffset: 0,
                historyTotalCount: 0,
                items: [fallback],
                totalCount: 1,
                userID: nil,
            )
        }
        return AvatarGalleryPayload(
            hasExtraCurrentPhoto: false,
            historyRawOffset: 0,
            historyTotalCount: 0,
            items: [],
            totalCount: 0,
            userID: nil,
        )
    }

    private func loadMoreAvatarHistory() {
        guard avatarHistoryTask == nil,
              let userID = avatarHistoryUserID,
              avatarHistoryRawOffset < avatarHistoryTotalCount,
              let activeAvatarGallery,
              contextIsCurrent
        else { return }
        let offset = avatarHistoryRawOffset
        avatarHistoryTask = Task { [weak self, weak activeAvatarGallery] in
            guard let self else { return }
            do {
                let result = try await client.getUserProfilePhotos(limit: 100, offset: offset, userId: userID)
                avatarHistoryTask = nil
                guard let activeAvatarGallery else {
                    return
                }
                guard !Task.isCancelled,
                      contextIsCurrent,
                      self.activeAvatarGallery === activeAvatarGallery
                else { return }
                avatarHistoryRawOffset += result.photos.count
                avatarHistoryTotalCount = result.totalCount
                if result.photos.isEmpty {
                    avatarHistoryRawOffset = result.totalCount
                }
                let newItems = result.photos.compactMap { photo -> ProfileAvatarGalleryItem? in
                    let item = ProfileAvatarGalleryItem(photo: photo)
                    return self.avatarHistoryKnownPhotoIDs.insert(item.id).inserted ? item : nil
                }
                activeAvatarGallery.appendItems(
                    newItems,
                    totalCount: result.totalCount + (avatarHistoryHasExtraCurrentPhoto ? 1 : 0),
                )
            } catch {
                avatarHistoryTask = nil
                guard let activeAvatarGallery else {
                    return
                }
                guard self.activeAvatarGallery === activeAvatarGallery else { return }
                activeAvatarGallery.showMoreItemsRetry()
            }
        }
    }

    private func avatarTransitionTarget(itemID: Int64) -> MediaGalleryTransitionTarget? {
        guard contextIsCurrent,
              avatarView.window != nil
        else { return nil }
        return MediaGalleryTransitionTarget(
            messageID: itemID,
            sourceView: avatarView,
            validation: { [weak self, weak avatarView] in
                guard let self, let avatarView else { return false }
                return contextIsCurrent && self.avatarView === avatarView && avatarView.window != nil
            },
        )
    }

    private func finishAvatarGalleryLoad() {
        avatarGalleryTask = nil
        avatarLoadingIndicator.stopAnimating()
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
