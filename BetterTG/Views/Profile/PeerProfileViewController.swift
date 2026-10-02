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
        let extraPhotoCount: Int
        let historyRawOffset: Int
        let historyTotalCount: Int
        let items: [ProfileAvatarGalleryItem]
        let totalCount: Int
        let trailingPhotoID: Int64?
        let userID: Int64?
    }

    private struct UserPhotoRoleSignature: Equatable {
        let mainID: Int64?
        let personalID: Int64?
        let publicID: Int64?
    }

    var onOpenMessage: ((Int64) -> Void)?
    var onSearch: (() -> Void)?

    private let accountID: UUID
    private let accountUserID: Int64?
    private let client: TDLibClient
    private let customChat: CustomChat
    private let isSelfProfile: Bool
    private let topic: MessageTopic?
    private var infoPermission: PeerProfileInfoPermissionState
    private var currentChatTitle: String
    private var currentChatPhotoInfo: ChatPhotoInfo?
    private var currentUserProfilePhoto: ProfilePhoto?
    private var currentUserPhotoRoleSignature: UserPhotoRoleSignature?
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
    private let managementActionStack = UIStackView()
    private lazy var messageActionButton = profileButton(
        title: "Message",
        symbol: "message.fill",
        action: #selector(messagePressed),
    )
    private lazy var searchActionButton = profileButton(
        title: "Search",
        symbol: "magnifyingglass",
        action: #selector(searchPressed),
    )
    private lazy var membersActionButton = profileButton(
        title: "Members",
        symbol: "person.2.fill",
        action: #selector(membersPressed),
    )
    private lazy var administratorsActionButton = profileButton(
        title: "Admins",
        symbol: "person.badge.key.fill",
        action: #selector(administratorsPressed),
    )
    private lazy var editActionButton = profileButton(
        title: "Edit",
        symbol: "pencil",
        action: #selector(editPressed),
    )
    private let profileHeaderView = UIView()
    private let segmentedControl = UISegmentedControl(items: SharedTab.allCases.map(\.title))
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Int64>!
    private var messagesByID = [Int64: Message]()
    private var cancellables = Set<AnyCancellable>()
    private var infoTask: Task<Void, Never>?
    private var avatarGalleryTask: Task<Void, Never>?
    private var avatarGalleryRequestID: UUID?
    private var avatarHistoryTask: Task<Void, Never>?
    private var avatarHistoryRequestID: UUID?
    private var avatarReconciliationTask: Task<Void, Never>?
    private var avatarReconciliationRequestID: UUID?
    private var chatMetadataTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var historyRequest = PeerProfileHistoryRequest()
    private var messageRefreshTasks = [Int64: Task<Void, Never>]()
    private var messageRefreshGenerations = [Int64: UUID]()
    private var oldestMessageID: Int64?
    private var hasMore = true
    private var historyError: String?
    private var sharedTotalMessageCount: Int?
    private var currentProfilePhoto: ChatPhoto?
    private var currentBasicGroupMembers = [ChatMember]()
    private var currentSupergroupCanGetMembers = false
    private var avatarHistoryRawOffset = 0
    private var avatarHistoryTotalCount = 0
    private var avatarHistoryExtraPhotoCount = 0
    private var avatarHistoryKnownPhotoIDs = Set<Int64>()
    private var avatarHistoryTrailingPhotoID: Int64?
    private var avatarHistoryUserID: Int64?
    private var metadataGeneration = UInt64.zero
    private var fullInfoGeneration = UInt64.zero
    private var avatarMetadataGeneration = UInt64.zero
    private var hasHydratedFullInfo = false
    private var metadataRenderScheduled = false
    private var renderedAvatarFileID: Int?
    private var renderedAvatarItemID: Int64?
    private weak var activeMediaGallery: MediaGalleryViewController?
    private weak var activeAvatarGallery: ProfileAvatarGalleryViewController?
    private lazy var mediaPlaybackContext = MediaGalleryPlaybackContext(
        client: client,
        location: ChatLocation(accountID: accountID, chatID: customChat.id, clientID: client.id, topic: topic),
        tdlib: .shared,
    )
    private lazy var mediaRevealSession = mediaPlaybackContext.map(MediaRevealSession.init)

    private var currentSharedTab: SharedTab {
        SharedTab(rawValue: segmentedControl.selectedSegmentIndex) ?? .media
    }

    private var displayedAvatarFile: File? {
        currentUserProfilePhoto?.big ?? currentProfilePhotoSize?.photo ?? currentChatPhotoInfo?.big
    }

    private var displayedAvatarMinithumbnail: Minithumbnail? {
        currentUserProfilePhoto?.minithumbnail
            ?? currentProfilePhoto?.minithumbnail
            ?? currentChatPhotoInfo?.minithumbnail
    }

    private var avatarGalleryIsAvailable: Bool {
        currentUserProfilePhoto.map { $0.id.rawValue != 0 } == true
            || currentProfilePhoto != nil
            || !isSelfProfile && currentChatPhotoInfo != nil
    }

    private var avatarGalleryFallbackItem: ProfileAvatarGalleryItem? {
        if let currentUserProfilePhoto,
           let item = ProfileAvatarGalleryItem(profilePhoto: currentUserProfilePhoto)
        {
            return item
        }
        if let currentProfilePhoto {
            return ProfileAvatarGalleryItem(photo: currentProfilePhoto)
        }
        guard !isSelfProfile else { return nil }
        return ProfileAvatarGalleryItem(current: currentChatPhotoInfo)
    }

    private var currentProfilePhotoSize: PhotoSize? {
        currentProfilePhoto?.sizes.max { lhs, rhs in
            let lhsPixels = Int64(lhs.width) * Int64(lhs.height)
            let rhsPixels = Int64(rhs.width) * Int64(rhs.height)
            if lhsPixels == rhsPixels {
                return max(lhs.photo.size, lhs.photo.expectedSize) < max(rhs.photo.size, rhs.photo.expectedSize)
            }
            return lhsPixels < rhsPixels
        }
    }

    private var displayedAvatarItemID: Int64? {
        if let currentUserProfilePhoto, currentUserProfilePhoto.id.rawValue != 0 {
            return currentUserProfilePhoto.id.rawValue
        }
        if let currentProfilePhoto {
            return currentProfilePhoto.id.rawValue
        }
        guard !isSelfProfile, let currentChatPhotoInfo else { return nil }
        return -Int64(currentChatPhotoInfo.big.id) - 1
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
        self.infoPermission = PeerProfileInfoPermissionState(
            source: TdUpdateSource(accountID: accountID, clientID: client.id),
            chatID: customChat.id, chatType: customChat.chat.type, permissions: customChat.chat.permissions,
            status: customChat.group?.status ?? customChat.supergroup?.status,
        )
        let accountUserID = TDLib.shared.activeAccountID == accountID ? TDLib.shared.activeAccount?.userID : nil
        self.accountUserID = accountUserID
        self.isSelfProfile = accountUserID.map { customChat.user?.id == $0 } == true
        self.currentChatTitle = customChat.displayTitle
        self.currentChatPhotoInfo = customChat.chat.photo
        self.currentUserProfilePhoto = customChat.user?.profilePhoto
        self.currentStatusText = isSelfProfile ? "" : Self.statusText(for: customChat)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        infoTask?.cancel()
        avatarGalleryTask?.cancel()
        avatarHistoryTask?.cancel()
        avatarReconciliationTask?.cancel()
        chatMetadataTask?.cancel()
        permissionTask?.cancel()
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
        refreshInfoPermission()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Gallery selection grants only the members actually opened in this profile route.
        for cell in collectionView.visibleCells.compactMap({ $0 as? SharedMediaGridCell }) {
            cell.refreshRevealState()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        avatarGalleryTask?.cancel()
        avatarHistoryTask?.cancel()
        avatarReconciliationTask?.cancel()
        avatarHistoryRequestID = nil
        avatarReconciliationRequestID = nil
        finishAvatarGalleryLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateProfileHeaderLayout()
    }

    private static func statusText(for customChat: CustomChat) -> String {
        switch customChat.type {
        case .bot:
            "bot"
        case .user(let user):
            statusText(for: user.status)
        case .group(let group):
            "\(group.memberCount) members"
        case .supergroup(let group):
            group.isChannel ? "channel" : (group.isForum ? "forum" : "group")
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
        onOpenMessage?(message.id)
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
            file: displayedAvatarFile,
            minithumbnail: displayedAvatarMinithumbnail,
            placeholder: customChat.telegramAvatarPlaceholder,
            usesPeerPhotoForSavedMessages: isSelfProfile,
            accountID: accountID,
            accountUserID: accountUserID,
            client: client,
        )
        renderedAvatarItemID = displayedAvatarItemID
        renderedAvatarFileID = displayedAvatarFile?.id
        avatarView.layer.cornerRadius = 48
        avatarView.clipsToBounds = true
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
        statusLabel.isHidden = currentStatusText.isEmpty
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
            label.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
        }

        actionStack.axis = .horizontal
        actionStack.distribution = .fillEqually
        actionStack.spacing = 10
        actionStack.addArrangedSubview(messageActionButton)
        actionStack.addArrangedSubview(searchActionButton)
        headerStack.addArrangedSubview(actionStack)

        managementActionStack.axis = .horizontal
        managementActionStack.distribution = .fillEqually
        managementActionStack.spacing = 10
        managementActionStack.addArrangedSubview(membersActionButton)
        managementActionStack.addArrangedSubview(administratorsActionButton)
        managementActionStack.addArrangedSubview(editActionButton)
        headerStack.addArrangedSubview(managementActionStack)
        updateActionAvailability()

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
            managementActionStack.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
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
        #if DEBUG
            ProfileHeaderLayoutProbe.recordIfRequested(
                header: profileHeaderView, avatar: avatarView,
                labels: [titleLabel, statusLabel, bioLabel, detailsLabel],
            )
        #endif
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
                cell?.configure(
                    message: message,
                    context: mediaPlaybackContext,
                    permit: mediaRevealSession?.permit(for: message),
                )
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
        guard contextIsCurrent, presentedViewController == nil,
              let mediaPlaybackContext, mediaPlaybackContext.isCurrent else { return }
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
            actionClient: client,
            sourceLocation: ChatLocation(
                accountID: accountID,
                chatID: customChat.id,
                clientID: client.id,
                topic: topic,
            ),
            playbackContext: mediaPlaybackContext,
            mediaRevealSession: mediaRevealSession,
            transitionSource: transitionSource,
            transitionSourceProvider: { [weak self] messageID in
                self?.mediaTransitionTarget(for: messageID)
            },
        )
        let originatingTab = currentSharedTab
        gallery.paginationIsCurrent = { [weak self] in
            guard let self else { return false }
            return contextIsCurrent && currentSharedTab == originatingTab
        }
        gallery.onRequestMoreMessages = { [weak self] in
            guard let self, contextIsCurrent, currentSharedTab == originatingTab else { return }
            loadMore()
        }
        gallery.contextIsCurrent = { [weak self] in
            self?.contextIsCurrent == true
        }
        gallery.onOpenMessageID = { [weak self] messageID in
            self?.onOpenMessage?(messageID)
        }
        gallery.onGalleryRestored = { [weak self] restoredGallery in
            guard let self, contextIsCurrent, currentSharedTab == originatingTab else { return }
            activeMediaGallery = restoredGallery
            restoredGallery.updateMessages(sortedSharedMessages)
            restoredGallery.updateTotalMessageCount(sharedTotalMessageCount)
        }
        activeMediaGallery = gallery
        present(gallery, animated: true)
    }

    private func mediaTransitionTarget(for messageID: Int64) -> MediaGalleryTransitionTarget? {
        guard contextIsCurrent, let message = messagesByID[messageID],
              let indexPath = dataSource.indexPath(for: messageID),
              let cell = collectionView.cellForItem(at: indexPath) as? SharedMediaGridCell
        else { return nil }
        cell.refreshRevealState()
        return cell.transitionTarget(for: messageID) { [weak self, weak cell] in
            guard let self, let cell, contextIsCurrent,
                  let currentIndexPath = dataSource.indexPath(for: messageID),
                  let current = messagesByID[messageID],
                  MediaRevealSession.Key(message: current) == MediaRevealSession.Key(message: message)
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
        nc.scopedPublisher(&cancellables, for: .updateChatPermissions) { [weak self] event in
            guard let self, contextIsCurrent,
                  infoPermission.updatePermissions(event.value, source: event.source)
            else { return }
            scheduleMetadataRender()
        }
        nc.scopedPublisher(&cancellables, for: .updateBasicGroup) { [weak self] event in
            self?.handleBasicGroupUpdate(event.value, source: event.source)
        }
        nc.scopedPublisher(&cancellables, for: .updateSupergroup) { [weak self] event in
            self?.handleSupergroupUpdate(event.value, source: event.source)
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
            guard let self,
                  let navigationController,
                  let profileIndex = navigationController.viewControllers.firstIndex(where: { $0 === self }),
                  profileIndex > 0
            else { return }
            navigationController.setViewControllers(
                Array(navigationController.viewControllers.prefix(upTo: profileIndex)),
                animated: false,
            )
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
        currentStatusText = isSelfProfile ? "" : Self.statusText(for: update.status)
        scheduleMetadataRender()
    }

    private func handleUserUpdate(_ update: UpdateUser) {
        guard contextIsCurrent, update.user.id == customChat.user?.id else { return }
        metadataGeneration &+= 1
        chatMetadataTask?.cancel()
        chatMetadataTask = nil
        customChat.updatePrivateUser(update.user)
        if currentUserProfilePhoto?.id != update.user.profilePhoto?.id {
            currentUserProfilePhoto = update.user.profilePhoto
            resetAvatarGalleryForMetadataChange()
        } else {
            currentUserProfilePhoto = update.user.profilePhoto
        }
        let name = [update.user.firstName, update.user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty, !isSelfProfile {
            currentChatTitle = name
        }
        currentStatusText = isSelfProfile ? "" : Self.statusText(for: update.user.status)
        currentDetailTexts = update.user.usernames?.activeUsernames.map { "@\($0)" } ?? []
        if !update.user.phoneNumber.isEmpty {
            currentDetailTexts.append("+\(update.user.phoneNumber)")
        }
        scheduleMetadataRender()
        loadProfileInfo()
    }

    private func handleBasicGroupUpdate(_ update: UpdateBasicGroup, source: TdUpdateSource) {
        guard contextIsCurrent, update.basicGroup.id == customChat.group?.id,
              infoPermission.updateStatus(
                  update.basicGroup.status,
                  chatType: .chatTypeBasicGroup(.init(basicGroupId: update.basicGroup.id)), source: source,
              )
        else { return }
        customChat.type = .group(update.basicGroup)
        currentStatusText = "\(update.basicGroup.memberCount) members"
        scheduleMetadataRender()
    }

    private func handleSupergroupUpdate(_ update: UpdateSupergroup, source: TdUpdateSource) {
        guard contextIsCurrent, update.supergroup.id == customChat.supergroup?.id,
              infoPermission.updateStatus(
                  update.supergroup.status,
                  chatType: .chatTypeSupergroup(.init(
                      isChannel: update.supergroup.isChannel, supergroupId: update.supergroup.id,
                  )), source: source,
              )
        else { return }
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
        currentBasicGroupMembers = update.basicGroupFullInfo.members
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
        currentSupergroupCanGetMembers = update.supergroupFullInfo.canGetMembers
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

    private func refreshInfoPermission() {
        guard contextIsCurrent, let accountUserID else { return }
        switch infoPermission.chatType {
        case .chatTypeBasicGroup, .chatTypeSupergroup: break
        case .chatTypePrivate, .chatTypeSecret: return
        }
        let authorization = PeerProfileInfoEditAuthorization.live(
            accountID: accountID, actorUserID: accountUserID, chatID: customChat.id, client: client,
        )
        let revision = infoPermission.revision
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await authorization.loadSnapshot()
                guard !Task.isCancelled, contextIsCurrent else { return }
                infoPermission.refresh(
                    chatID: snapshot.chatID, chatType: snapshot.chatType, permissions: snapshot.permissions,
                    status: snapshot.status, ifRevision: revision,
                )
                permissionTask = nil
                scheduleMetadataRender()
            } catch {
                guard !Task.isCancelled, contextIsCurrent else { return }
                permissionTask = nil
            }
        }
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
            currentChatTitle = isSelfProfile ? "Saved Messages" : chat.title
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
        let signature = UserPhotoRoleSignature(
            mainID: info.photo?.id.rawValue,
            personalID: isSelfProfile ? nil : info.personalPhoto?.id.rawValue,
            publicID: info.publicPhoto?.id.rawValue,
        )
        let selectedPhoto = isSelfProfile
            ? info.photo
            : (info.personalPhoto ?? info.photo ?? info.publicPhoto)
        let photoIDWillChange = hasHydratedFullInfo && currentProfilePhoto?.id != selectedPhoto?.id
        let roleSignatureChanged = currentUserPhotoRoleSignature != signature
        currentUserPhotoRoleSignature = signature
        applyFullInfo(
            bio: info.bio?.text ?? info.botInfo?.description ?? info.botInfo?.shortDescription,
            details: details,
            status: nil,
            photo: selectedPhoto,
        )
        if roleSignatureChanged, !photoIDWillChange, activeAvatarGallery != nil {
            resetAvatarGalleryForMetadataChange()
        }
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
        let photoChanged = hasHydratedFullInfo && currentProfilePhoto?.id != photo?.id
        hasHydratedFullInfo = true
        currentProfilePhoto = photo
        if photoChanged {
            resetAvatarGalleryForMetadataChange()
        }
        scheduleMetadataRender()
    }

    private func resetAvatarGalleryForMetadataChange() {
        avatarMetadataGeneration &+= 1
        avatarGalleryTask?.cancel()
        avatarHistoryTask?.cancel()
        avatarReconciliationTask?.cancel()
        avatarGalleryTask = nil
        avatarGalleryRequestID = nil
        avatarHistoryTask = nil
        avatarHistoryRequestID = nil
        avatarReconciliationTask = nil
        avatarReconciliationRequestID = nil
        if let activeAvatarGallery, contextIsCurrent {
            let generation = avatarMetadataGeneration
            let requestID = UUID()
            avatarReconciliationRequestID = requestID
            avatarReconciliationTask = Task { [weak self, weak activeAvatarGallery] in
                guard let self else { return }
                defer {
                    if avatarReconciliationRequestID == requestID {
                        avatarReconciliationRequestID = nil
                        avatarReconciliationTask = nil
                    }
                }
                guard let activeAvatarGallery else { return }
                do {
                    let payload = try await loadAvatarGalleryPayload()
                    guard !Task.isCancelled,
                          contextIsCurrent,
                          avatarMetadataGeneration == generation,
                          avatarReconciliationRequestID == requestID,
                          self.activeAvatarGallery === activeAvatarGallery
                    else { return }
                    avatarHistoryRawOffset = payload.historyRawOffset
                    avatarHistoryTotalCount = payload.historyTotalCount
                    avatarHistoryExtraPhotoCount = payload.extraPhotoCount
                    avatarHistoryKnownPhotoIDs = Set(payload.items.map(\.id))
                    avatarHistoryTrailingPhotoID = payload.trailingPhotoID
                    avatarHistoryUserID = payload.userID
                    if payload.items.isEmpty {
                        activeAvatarGallery.onRequestMoreItems = nil
                        activeAvatarGallery.reconcileItems([], totalCount: 0)
                        self.activeAvatarGallery = nil
                        return
                    }
                    activeAvatarGallery.onRequestMoreItems = payload.userID == nil
                        ? nil
                        : { [weak self] in
                            self?.loadMoreAvatarHistory()
                        }
                    activeAvatarGallery.reconcileItems(payload.items, totalCount: payload.totalCount)
                } catch {
                    guard !Task.isCancelled,
                          avatarMetadataGeneration == generation,
                          avatarReconciliationRequestID == requestID,
                          self.activeAvatarGallery === activeAvatarGallery
                    else { return }
                    activeAvatarGallery.onRequestMoreItems = { [weak self] in
                        self?.resetAvatarGalleryForMetadataChange()
                    }
                    activeAvatarGallery.showMoreItemsRetry()
                }
            }
            avatarLoadingIndicator.stopAnimating()
            return
        }
        avatarHistoryRawOffset = 0
        avatarHistoryTotalCount = 0
        avatarHistoryExtraPhotoCount = 0
        avatarHistoryKnownPhotoIDs = []
        avatarHistoryTrailingPhotoID = nil
        avatarHistoryUserID = nil
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
        statusLabel.isHidden = currentStatusText.isEmpty
        bioLabel.text = currentBioText
        bioLabel.textColor = .label
        bioLabel.isHidden = currentBioText.isEmpty
        detailsLabel.text = currentDetailTexts.joined(separator: " · ")
        detailsLabel.isHidden = currentDetailTexts.isEmpty
        avatarView.configure(
            file: displayedAvatarFile,
            minithumbnail: displayedAvatarMinithumbnail,
            placeholder: customChat.telegramAvatarPlaceholder,
            usesPeerPhotoForSavedMessages: isSelfProfile,
            accountID: accountID,
            accountUserID: accountUserID,
            client: client,
        )
        renderedAvatarItemID = displayedAvatarItemID
        renderedAvatarFileID = displayedAvatarFile?.id
        avatarTapGesture.isEnabled = avatarGalleryIsAvailable
        avatarView.accessibilityLabel = "\(profileTitle()) profile photo"
        avatarView.accessibilityHint = avatarGalleryIsAvailable ? "Opens profile photos" : nil
        avatarView.accessibilityTraits = avatarGalleryIsAvailable ? [.button, .image] : .image
        updateActionAvailability()
        view.setNeedsLayout()
    }

    private func updateActionAvailability() {
        messageActionButton.isHidden = isSelfProfile
        membersActionButton.isHidden =
            switch customChat.type {
            case .group:
                false
            case .supergroup:
                !currentSupergroupCanGetMembers
            case .bot, .user:
                true
            }
        administratorsActionButton.isHidden =
            switch customChat.type {
            case .group, .supergroup:
                false
            case .bot, .user:
                true
            }
        editActionButton.isHidden =
            if let user = customChat.user {
                user.id != accountUserID
            } else {
                !infoPermission.canChangeInfo
            }
        managementActionStack.isHidden = managementActionStack.arrangedSubviews.allSatisfy(\.isHidden)
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
                    currentBasicGroupMembers = info.members
                    applyFullInfo(bio: info.description, details: [], status: nil, photo: info.photo)
                case .supergroup(let group):
                    let info = try await client.getSupergroupFullInfo(supergroupId: group.id)
                    let noun = group.isChannel ? "subscribers" : "members"
                    guard !Task.isCancelled,
                          contextIsCurrent,
                          fullInfoGeneration == generation
                    else { return }
                    currentSupergroupCanGetMembers = info.canGetMembers
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
        let requestID = historyRequest.begin()
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
                else {
                    if historyRequest.finish(requestID) { historyTask = nil }
                    return
                }
                guard historyRequest.finish(requestID) else { return }
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
                guard historyRequest.finish(requestID) else { return }
                historyTask = nil
                guard contextIsCurrent, currentSharedTab == requestedTab else { return }
                applySnapshot()
            } catch {
                guard historyRequest.finish(requestID) else { return }
                historyTask = nil
                guard !Task.isCancelled, contextIsCurrent, currentSharedTab == requestedTab else { return }
                historyError = "Couldn't load shared \(requestedTab.title.lowercased())."
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
        // Revoke accepted same-ID revisions before either grid cells or the gallery can use old pixels.
        mediaRevealSession?.reconcile(messages)
        let existingIDs = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(messages.map(\.id))
        if currentSharedTab == .media {
            snapshot.reconfigureItems(messages.map(\.id).filter(existingIDs.contains))
        }
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
        isSelfProfile ? "Saved Messages" : currentChatTitle
    }

    @objc private func avatarPressed() {
        guard avatarGalleryIsAvailable,
              avatarGalleryTask == nil,
              contextIsCurrent,
              presentedViewController == nil
        else { return }
        avatarLoadingIndicator.startAnimating()
        let avatarGeneration = avatarMetadataGeneration
        let requestID = UUID()
        avatarGalleryRequestID = requestID
        avatarGalleryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await loadAvatarGalleryPayload()
                guard !Task.isCancelled,
                      contextIsCurrent,
                      avatarMetadataGeneration == avatarGeneration,
                      avatarGalleryRequestID == requestID,
                      view.window != nil,
                      navigationController?.topViewController === self,
                      presentedViewController == nil,
                      let selectedItem = payload.items.first
                else {
                    finishAvatarGalleryLoad(requestID: requestID)
                    return
                }
                let transitionSource = avatarTransitionTarget(item: selectedItem)
                let gallery = ProfileAvatarGalleryViewController(
                    accountID: accountID,
                    client: client,
                    items: payload.items,
                    selection: selectedItem.id,
                    totalCount: payload.totalCount,
                    transitionSource: transitionSource,
                    transitionSourceProvider: { [weak self] itemID in
                        guard itemID == selectedItem.id else { return nil }
                        return self?.avatarTransitionTarget(item: selectedItem)
                    },
                )
                gallery.contextIsCurrent = { [weak self] in
                    self?.contextIsCurrent == true
                }
                avatarHistoryRawOffset = payload.historyRawOffset
                avatarHistoryTotalCount = payload.historyTotalCount
                avatarHistoryExtraPhotoCount = payload.extraPhotoCount
                avatarHistoryKnownPhotoIDs = Set(payload.items.map(\.id))
                avatarHistoryTrailingPhotoID = payload.trailingPhotoID
                avatarHistoryUserID = payload.userID
                activeAvatarGallery = gallery
                if payload.userID != nil {
                    gallery.onRequestMoreItems = { [weak self] in
                        self?.loadMoreAvatarHistory()
                    }
                }
                finishAvatarGalleryLoad(requestID: requestID)
                present(gallery, animated: true)
            } catch {
                guard !Task.isCancelled else { return }
                let fallback = avatarGalleryFallbackItem
                guard contextIsCurrent,
                      avatarMetadataGeneration == avatarGeneration,
                      avatarGalleryRequestID == requestID,
                      view.window != nil,
                      navigationController?.topViewController === self,
                      presentedViewController == nil,
                      let fallback
                else {
                    finishAvatarGalleryLoad(requestID: requestID)
                    return
                }
                let transitionSource = avatarTransitionTarget(item: fallback)
                let gallery = ProfileAvatarGalleryViewController(
                    accountID: accountID,
                    client: client,
                    items: [fallback],
                    selection: fallback.id,
                    totalCount: 1,
                    transitionSource: transitionSource,
                    transitionSourceProvider: { [weak self] itemID in
                        guard itemID == fallback.id else { return nil }
                        return self?.avatarTransitionTarget(item: fallback)
                    },
                )
                gallery.contextIsCurrent = { [weak self] in
                    self?.contextIsCurrent == true
                }
                avatarHistoryRawOffset = 0
                avatarHistoryTotalCount = 0
                avatarHistoryExtraPhotoCount = 0
                avatarHistoryKnownPhotoIDs = [fallback.id]
                avatarHistoryTrailingPhotoID = nil
                avatarHistoryUserID = nil
                activeAvatarGallery = gallery
                finishAvatarGalleryLoad(requestID: requestID)
                present(gallery, animated: true)
            }
        }
    }

    private func loadAvatarGalleryPayload() async throws -> AvatarGalleryPayload {
        switch customChat.type {
        case .bot(let user), .user(let user):
            let info = try await client.getUserFullInfo(userId: user.id)
            let result = try await client.getUserProfilePhotos(limit: 100, offset: 0, userId: user.id)
            let historyItems = result.photos.map(ProfileAvatarGalleryItem.init(photo:))
            let publicItem = info.publicPhoto.map(ProfileAvatarGalleryItem.init(photo:))
            let rolePhotos = isSelfProfile
                ? [info.photo, info.publicPhoto].compactMap(\.self)
                : [info.personalPhoto, info.photo, info.publicPhoto].compactMap(\.self)
            let fullItemsByID = Dictionary(
                (rolePhotos.map(ProfileAvatarGalleryItem.init(photo:)) + historyItems)
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first },
            )
            var items = [ProfileAvatarGalleryItem]()
            var knownIDs = Set<Int64>()
            let appendItem: (ProfileAvatarGalleryItem?) -> Void = { item in
                guard let item, knownIDs.insert(item.id).inserted else { return }
                items.append(item)
            }
            let effectiveID = currentUserProfilePhoto?.id.rawValue
            if let effectiveID, effectiveID != 0 {
                appendItem(fullItemsByID[effectiveID] ??
                    ProfileAvatarGalleryItem(profilePhoto: currentUserProfilePhoto))
            }
            if isSelfProfile {
                appendItem(info.photo.map(ProfileAvatarGalleryItem.init(photo:)))
            } else {
                appendItem((info.personalPhoto ?? info.photo ?? info.publicPhoto)
                    .map(ProfileAvatarGalleryItem.init(photo:)))
                if info.personalPhoto != nil {
                    appendItem(info.photo.map(ProfileAvatarGalleryItem.init(photo:)))
                }
            }
            for item in historyItems where item.id != publicItem?.id {
                appendItem(item)
            }
            let publicWasAlreadyCurrent = publicItem.map { knownIDs.contains($0.id) } == true
            if !publicWasAlreadyCurrent {
                appendItem(publicItem)
            }
            if items.isEmpty, !isSelfProfile,
               let fallback = ProfileAvatarGalleryItem(current: currentChatPhotoInfo)
            {
                items = [fallback]
                knownIDs = [fallback.id]
            }
            let resultIDs = Set(result.photos.map(\.id.rawValue))
            let extraPhotoCount = knownIDs.filter { !resultIDs.contains($0) }.count
            let trailingPhotoID = !publicWasAlreadyCurrent && items.last?.id == publicItem?.id
                ? publicItem?.id
                : nil
            return AvatarGalleryPayload(
                extraPhotoCount: extraPhotoCount,
                historyRawOffset: result.photos.count,
                historyTotalCount: result.totalCount,
                items: items,
                totalCount: max(items.count, result.totalCount + extraPhotoCount),
                trailingPhotoID: trailingPhotoID,
                userID: user.id,
            )
        case .group(let group):
            let info = try await client.getBasicGroupFullInfo(basicGroupId: group.id)
            let photo = info.photo ?? currentProfilePhoto
            if let photo {
                return AvatarGalleryPayload(
                    extraPhotoCount: 0,
                    historyRawOffset: 0,
                    historyTotalCount: 0,
                    items: [ProfileAvatarGalleryItem(photo: photo)],
                    totalCount: 1,
                    trailingPhotoID: nil,
                    userID: nil,
                )
            }
        case .supergroup(let group):
            let info = try await client.getSupergroupFullInfo(supergroupId: group.id)
            let photo = info.photo ?? currentProfilePhoto
            if let photo {
                return AvatarGalleryPayload(
                    extraPhotoCount: 0,
                    historyRawOffset: 0,
                    historyTotalCount: 0,
                    items: [ProfileAvatarGalleryItem(photo: photo)],
                    totalCount: 1,
                    trailingPhotoID: nil,
                    userID: nil,
                )
            }
        }
        if let fallback = avatarGalleryFallbackItem {
            return AvatarGalleryPayload(
                extraPhotoCount: 0,
                historyRawOffset: 0,
                historyTotalCount: 0,
                items: [fallback],
                totalCount: 1,
                trailingPhotoID: nil,
                userID: nil,
            )
        }
        return AvatarGalleryPayload(
            extraPhotoCount: 0,
            historyRawOffset: 0,
            historyTotalCount: 0,
            items: [],
            totalCount: 0,
            trailingPhotoID: nil,
            userID: nil,
        )
    }

    private func loadMoreAvatarHistory() {
        guard avatarHistoryTask == nil,
              avatarReconciliationTask == nil,
              let userID = avatarHistoryUserID,
              avatarHistoryRawOffset < avatarHistoryTotalCount,
              let activeAvatarGallery,
              contextIsCurrent
        else { return }
        let offset = avatarHistoryRawOffset
        let metadataGeneration = avatarMetadataGeneration
        let requestID = UUID()
        avatarHistoryRequestID = requestID
        avatarHistoryTask = Task { [weak self, weak activeAvatarGallery] in
            guard let self else { return }
            defer {
                if avatarHistoryRequestID == requestID {
                    avatarHistoryRequestID = nil
                    avatarHistoryTask = nil
                }
            }
            do {
                let result = try await client.getUserProfilePhotos(limit: 100, offset: offset, userId: userID)
                guard let activeAvatarGallery else {
                    return
                }
                guard !Task.isCancelled,
                      contextIsCurrent,
                      avatarMetadataGeneration == metadataGeneration,
                      avatarHistoryRequestID == requestID,
                      avatarHistoryRawOffset == offset,
                      self.activeAvatarGallery === activeAvatarGallery
                else { return }
                avatarHistoryRawOffset = offset + result.photos.count
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
                    before: avatarHistoryTrailingPhotoID,
                    totalCount: result.totalCount + avatarHistoryExtraPhotoCount,
                )
            } catch {
                guard let activeAvatarGallery else {
                    return
                }
                guard !Task.isCancelled,
                      avatarMetadataGeneration == metadataGeneration,
                      avatarHistoryRequestID == requestID,
                      self.activeAvatarGallery === activeAvatarGallery
                else { return }
                activeAvatarGallery.showMoreItemsRetry()
            }
        }
    }

    private func avatarTransitionTarget(item: ProfileAvatarGalleryItem) -> MediaGalleryTransitionTarget? {
        let itemContainsRenderedFile = item.photo.sizes.contains { $0.photo.id == renderedAvatarFileID }
        guard contextIsCurrent,
              renderedAvatarItemID == item.id,
              itemContainsRenderedFile,
              avatarView.window != nil
        else { return nil }
        return MediaGalleryTransitionTarget(
            messageID: item.id,
            sourceView: avatarView,
            validation: { [weak self, weak avatarView] in
                guard let self, let avatarView else { return false }
                return contextIsCurrent
                    && renderedAvatarItemID == item.id
                    && item.photo.sizes.contains { $0.photo.id == self.renderedAvatarFileID }
                    && self.avatarView === avatarView
                    && avatarView.window != nil
            },
        )
    }

    private func finishAvatarGalleryLoad(requestID: UUID? = nil) {
        if let requestID, avatarGalleryRequestID != requestID {
            return
        }
        avatarGalleryRequestID = nil
        avatarGalleryTask = nil
        avatarLoadingIndicator.stopAnimating()
    }

    @objc private func tabChanged() {
        historyRequest.invalidate()
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

    @objc private func membersPressed() {
        guard contextIsCurrent else { return }
        let source: PeerProfileMembersViewController.Source
        switch customChat.type {
        case .group(let group):
            source = .basicGroup(chatID: customChat.id, id: group.id, members: currentBasicGroupMembers)
        case .supergroup(let group) where currentSupergroupCanGetMembers:
            source = .supergroup(chatID: customChat.id, id: group.id)
        case .bot, .supergroup, .user:
            return
        }
        navigationController?.pushViewController(PeerProfileMembersViewController(
            accountID: accountID,
            accountUserID: accountUserID,
            client: client,
            source: source,
            title: profileTitle(),
        ), animated: true)
    }

    @objc private func administratorsPressed() {
        guard contextIsCurrent else { return }
        switch customChat.type {
        case .group, .supergroup:
            navigationController?.pushViewController(PeerProfileMembersViewController(
                accountID: accountID,
                accountUserID: accountUserID,
                client: client,
                source: .administrators(chatID: customChat.id),
                title: profileTitle(),
            ), animated: true)
        case .bot, .user:
            return
        }
    }

    @objc private func editPressed() {
        guard contextIsCurrent else { return }
        let mode: PeerProfileEditViewController.Mode
        if let user = customChat.user, user.id == accountUserID {
            mode = .selfProfile(
                userID: user.id,
                firstName: user.firstName,
                lastName: user.lastName,
                bio: currentBioText,
            )
        } else {
            guard infoPermission.canChangeInfo else { return }
            mode = .chat(
                chatID: customChat.id,
                title: currentChatTitle,
                description: currentBioText,
            )
        }
        navigationController?.pushViewController(PeerProfileEditViewController(
            accountID: accountID,
            accountUserID: accountUserID,
            client: client,
            mode: mode,
        ), animated: true)
    }

    @objc private func retrySharedMedia() {
        loadMore()
    }

    @objc private func searchPressed() {
        onSearch?()
    }
}

// MARK: - SharedMediaGridCell

final class SharedMediaGridCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedMediaGridCell"

    #if DEBUG
        var debugThumbnailLoader: ((Message, TDImageLoadingView) -> Void)?
        var debugHasRawImage: Bool { imageView.image != nil }
        var debugHasCover: Bool { cover != nil }
    #endif

    private let imageView = TDImageLoadingView()
    private let videoBadge = UIImageView(image: UIImage(systemName: "play.fill"))
    private var representedMessage: Message?
    private var loadingIsPaused = false
    private var context: MediaGalleryPlaybackContext?
    private var permit: MediaRevealPermit?
    private var subscriptions = Set<AnyCancellable>()
    private var cover: MediaConcealmentView?
    private var renderGeneration = UUID()
    private var renderedAllowsPixels = false

    private var allowsPixels: Bool {
        guard let representedMessage, let context, permit?.matches(context) == true else { return false }
        return MediaRevealPermit.allows(representedMessage, permit: permit, requiresPermit: true)
    }

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
        subscriptions.removeAll()
        context = nil
        permit = nil
        cover?.removeFromSuperview()
        cover = nil
        renderedAllowsPixels = false
        renderGeneration = UUID()
        accessibilityLabel = nil
    }

    func configure(message: Message, context: MediaGalleryPlaybackContext?, permit: MediaRevealPermit?) {
        subscriptions.removeAll()
        representedMessage = message
        self.context = context
        self.permit = permit
        loadingIsPaused = false
        permit?.revisionChanges.sink { [weak self] in self?.render() }.store(in: &subscriptions)
        context?.clientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.context?.isCurrent != true else { return }
                render()
            }
            .store(in: &subscriptions)
        isAccessibilityElement = true
        accessibilityTraits = .button
        render()
    }

    func refreshRevealState() {
        guard representedMessage != nil, renderedAllowsPixels != allowsPixels else { return }
        render()
    }

    func pauseLoading() {
        guard representedMessage != nil else { return }
        loadingIsPaused = true
        imageView.cancel()
    }

    func resumeLoading() {
        guard loadingIsPaused, representedMessage != nil else { return }
        loadingIsPaused = false
        render()
    }

    func transitionTarget(
        for messageID: Int64,
        validation additionalValidation: @escaping () -> Bool,
    ) -> MediaGalleryTransitionTarget? {
        guard let message = representedMessage, message.id == messageID,
              permit?.isCurrent == true, context?.isCurrent == true else { return nil }
        let generation = renderGeneration
        let usesImage = renderedAllowsPixels
        let source: UIView = cover ?? imageView
        return MediaGalleryTransitionTarget(
            messageID: messageID,
            sourceView: source,
            snapshotFactory: { [weak imageView] in
                usesImage
                    ? imageView?.makeImageSnapshot(contentMode: .scaleAspectFill)
                    : MediaConcealmentView(message: message)
            },
            validation: { [weak self] in
                guard let self else { return false }
                return representedMessage?.id == messageID && renderGeneration == generation
                    && permit?.isCurrent == true && context?.isCurrent == true
                    && (!usesImage || allowsPixels) && window != nil
                    && additionalValidation()
            },
        )
    }

    private func render() {
        guard let message = representedMessage else { return }
        renderGeneration = UUID()
        imageView.cancel()
        imageView.image = nil
        cover?.removeFromSuperview()
        cover = nil
        renderedAllowsPixels = allowsPixels
        videoBadge.isHidden = true
        if renderedAllowsPixels {
            accessibilityLabel = "\(MessageTextSpoilerPresentation.summary(for: message)), \(profileDateString(message.date))"
            accessibilityHint = "Open media"
            if !loadingIsPaused { loadThumbnail(for: message) }
        } else {
            let cover = MediaConcealmentView(message: message)
            cover.isUserInteractionEnabled = false
            cover.isAccessibilityElement = false
            cover.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(cover)
            NSLayoutConstraint.activate([
                cover.topAnchor.constraint(equalTo: contentView.topAnchor),
                cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                cover.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                cover.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
            self.cover = cover
            accessibilityLabel = cover.accessibilityLabel
            accessibilityHint = permit?.key.isSecret == true ? nil : "Open media"
        }
    }

    private func loadThumbnail(for message: Message) {
        guard allowsPixels else { return }
        #if DEBUG
            if let debugThumbnailLoader {
                debugThumbnailLoader(message, imageView)
                return
            }
        #endif
        guard let context, let client = context.client, let accountID = context.location.accountID else { return }
        switch message.content {
        case .messagePhoto(let photo):
            if let size = photo.photo.sizes.getSize(.yBox) ?? photo.photo.sizes.first {
                imageView.load(
                    file: size.photo,
                    placeholderData: photo.photo.minithumbnail?.data,
                    accountID: accountID,
                    client: client,
                )
            } else {
                imageView.loadPlaceholder(data: photo.photo.minithumbnail?.data)
            }
            videoBadge.isHidden = true
        case .messageVideo(let video):
            if let thumbnail = video.video.thumbnail {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: video.video.minithumbnail?.data,
                    maximumPixelSize: 480,
                    accountID: accountID,
                    client: client,
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
