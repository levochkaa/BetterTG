// PeerProfileViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - PeerProfileViewController

@MainActor final class PeerProfileViewController: UIViewController, UICollectionViewDelegate,
ClientRestorableNavigationEntry {
    enum SharedTab: Int, CaseIterable {
        case media
        case files
        case links
        case audio

        var title: String {
            switch self {
            case .media: L10n.telegram("PeerInfo.PaneMedia")
            case .files: L10n.telegram("PeerInfo.PaneFiles")
            case .links: L10n.telegram("PeerInfo.PaneLinks")
            case .audio: L10n.telegram("PeerInfo.PaneAudio")
            }
        }

        var loadFailedText: String {
            switch self {
            case .media: L10n.betterTG("Profile.SharedMediaLoadFailed")
            case .files: L10n.betterTG("Profile.SharedFilesLoadFailed")
            case .links: L10n.betterTG("Profile.SharedLinksLoadFailed")
            case .audio: L10n.betterTG("Profile.SharedAudioLoadFailed")
            }
        }

        var emptyText: String {
            switch self {
            case .media: L10n.betterTG("Profile.SharedMediaEmpty")
            case .files: L10n.betterTG("Profile.SharedFilesEmpty")
            case .links: L10n.betterTG("Profile.SharedLinksEmpty")
            case .audio: L10n.betterTG("Profile.SharedAudioEmpty")
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
    var onPrepareGalleryReturn: ((Int64) async -> Bool)?
    var onGalleryReturnCompleted: ((Int64) -> Void)?
    var galleryReturnTarget: ((Int64) -> MediaGalleryTransitionTarget?)?
    var onSearch: (() -> Void)?

    private let accountID: UUID
    private let accountUserID: Int64?
    private let client: TDLibClient
    private let customChat: CustomChat
    private let isSelfProfile: Bool
    private let topic: MessageTopic?
    private let restoration: PeerProfileRestorationState?
    private var restoredViewport: PeerProfileViewport?
    private var restoredSnapshotApplied = false
    private var restorationIdentity: PeerProfileRestorationIdentity
    private let metadataPreparation = PeerProfileMetadataPreparation()
    private var preparedMetadata: (TdUpdateSource, CustomChat)?
    private var clientOwnerRetired = false
    private let editorRetention = PeerProfileEditorRetention()
    private weak var membersChild: PeerProfileMembersViewController?
    private var infoPermission: PeerProfileInfoPermissionState
    private var currentChatTitle: String
    private var currentChatPhotoInfo: ChatPhotoInfo?
    private var currentUserProfilePhoto: ProfilePhoto?
    private var currentUserPhotoRoleSignature: UserPhotoRoleSignature?
    private var currentStatusText: String
    private var currentStatusIsOnline = false
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
    private lazy var messageActionButton = profileButton(
        title: L10n.telegram("PeerInfo.ButtonMessage"),
        symbol: "message.fill",
        action: #selector(messagePressed),
    )
    private lazy var searchActionButton = profileButton(
        title: L10n.telegram("PeerInfo.ButtonSearch"),
        symbol: "magnifyingglass",
        action: #selector(searchPressed),
    )
    private lazy var membersActionButton = profileButton(
        title: L10n.telegram("Group.Info.Members"),
        symbol: "person.2.fill",
        action: #selector(membersPressed),
    )
    private lazy var administratorsActionButton = profileButton(
        title: L10n.telegram("Channel.Info.Management"),
        symbol: "person.badge.key.fill",
        action: #selector(administratorsPressed),
    )
    private let profileHeaderView = UIView()
    private let sharedTabs = FolderPickerView()
    private var selectedSharedTab = SharedTab.media
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
    private var sharedMessageRefresh: PeerProfileSharedMessageRefresh?
    private var sharedSnapshotScheduled = false
    private var sharedViewportGeneration = UInt64.zero
    private var sharedCellReadiness = [Int64: Bool]()
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

    var navigationClientSource: TdUpdateSource? { restorationIdentity.origin }

    private var currentSharedTab: SharedTab {
        selectedSharedTab
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
        currentUserProfilePhoto.map { $0.id != 0 } == true
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
        if let currentUserProfilePhoto, currentUserProfilePhoto.id != 0 {
            return currentUserProfilePhoto.id
        }
        if let currentProfilePhoto {
            return currentProfilePhoto.id
        }
        guard !isSelfProfile, let currentChatPhotoInfo else { return nil }
        return -Int64(currentChatPhotoInfo.big.id) - 1
    }

    private var contextIsCurrent: Bool {
        !clientOwnerRetired && !restorationIdentity.revoked
            && TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    private var sortedSharedMessages: [Message] {
        messagesByID.values.sorted {
            $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date
        }
    }

    private var canWaitForClientRestoration: Bool {
        !clientOwnerRetired && !restorationIdentity.revoked && accountUserID != nil
            && TDLib.shared.activeAccountID == accountID && TDLib.shared.activeAccount?.userID == accountUserID
            && chatListActionOwnerIsAttached
            && (navigationController?.topViewController === self || membersChild?.canRetain(
                parent: self, accountID: accountID, actorID: accountUserID, chatID: customChat.id,
            ) == true)
            && presentedViewController == nil && activeMediaGallery == nil && activeAvatarGallery == nil
            && avatarGalleryTask == nil && !isPresentingTelegramContextMenu
    }

    /// A same-account client renewal (the app returning from the background) keeps an open shared-media gallery, as
    /// it keeps the chat's: the gallery reloads its items through the renewed client, and this profile is replaced
    /// once the gallery closes.
    private var keepsMediaGalleryThroughClientRenewal: Bool {
        activeMediaGallery != nil && !clientOwnerRetired && !restorationIdentity.revoked && accountUserID != nil
            && TDLib.shared.activeAccountID == accountID && TDLib.shared.activeAccount?.userID == accountUserID
    }

    init(
        customChat: CustomChat, topic: MessageTopic?, client: TDLibClient, accountID: UUID,
        restoration: PeerProfileRestorationState? = nil,
    ) {
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
        self.restorationIdentity = PeerProfileRestorationIdentity(
            origin: TdUpdateSource(accountID: accountID, clientID: client.id), actorID: accountUserID,
        )
        let restoration = restoration.flatMap {
            $0.matches(accountID: accountID, actorID: accountUserID, chatID: customChat.id, topic: topic) ? $0 : nil
        }
        self.restoration = restoration
        self.restoredViewport = restoration?.viewport
        if let restoration {
            self.messagesByID = Dictionary(
                restoration.messages.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest },
            )
            self.oldestMessageID = restoration.cursor
            self.hasMore = restoration.hasMore
            self.sharedTotalMessageCount = restoration.total
            self.historyError = restoration.error
            self.currentBioText = restoration.bio
            self.currentDetailTexts = restoration.details
        }
        self.isSelfProfile = accountUserID.map { customChat.user?.id == $0 } == true
        self.currentChatTitle = customChat.displayTitle
        self.currentChatPhotoInfo = customChat.chat.photo
        self.currentUserProfilePhoto = customChat.user?.profilePhoto
        self.currentStatusText = isSelfProfile ? "" : Self.statusText(for: customChat)
        if !isSelfProfile, case .user(let user) = customChat.type {
            self.currentStatusIsOnline = Self.isOnline(user.status)
        }
        super.init(nibName: nil, bundle: nil)
        observeClientOwnership()
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
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.betterTG("Profile.Title")
        view.backgroundColor = .systemBackground
        configureHeader()
        configureCollectionView()
        configureDataSource()
        configureSharedMessageRefresh()
        observeAccount()
        handleClientReadiness(restorationIdentity.readySource)
        loadProfileInfo()
        if restoration != nil {
            applySnapshot(animated: false) { [weak self] in
                self?.restoredSnapshotApplied = true
                self?.restoreViewportIfNeeded()
            }
        } else {
            loadMore()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        refreshInfoPermission()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !contextIsCurrent {
            handleAccountChange()
            return
        }
        resumeSharedHistoryIfNeeded()
        // Gallery selection grants only the members actually opened in this profile route.
        for cell in collectionView.visibleCells.compactMap({ $0 as? SharedMediaGridCell }) {
            cell.refreshRevealState()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        sharedMessageRefresh?.stop()
        metadataPreparation.cancel()
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
        restoreViewportIfNeeded()
    }

    #if DEBUG
    static func verifyUnloadedMembersParent() throws {
        guard let accountID = TDLib.shared.activeAccountID, let actorID = TDLib.shared.activeAccount?.userID else {
            throw PeerProfileMembersRestorationProbe
                .Failure(description: "unloaded parent probe requires an active account")
        }
        let client = TDLib.shared.activeClient
        let origin = TdUpdateSource(accountID: accountID, clientID: client.id)
        var expectedReady: TdUpdateSource?
        var replayedReadiness = false
        let readiness = TDLib.shared.readyClientChanges.prefix(1).sink {
            expectedReady = $0
            replayedReadiness = true
        }
        defer { readiness.cancel() }
        let chat = ProbeFixtures.chat(
            .init(isPinned: false, list: .chatListMain, order: 1, source: nil),
            title: "Retained profile",
            id: 8,
        )
        let seed = PeerProfileRestorationState(
            source: origin,
            actorID: actorID,
            chatID: 8,
            topic: nil,
            tab: .files,
            messages: [],
            cursor: 61,
            hasMore: true,
            total: 200,
            error: nil,
            resumePage: true,
            bio: "accepted bio",
            details: ["accepted detail"],
            viewport: .init(messageID: 70, minY: -12, distanceFromTop: 600),
        )
        let parent = PeerProfileViewController(
            customChat: chat,
            topic: nil,
            client: client,
            accountID: accountID,
            restoration: seed,
        )
        try PeerProfileMembersRestorationProbe.require(
            !parent.isViewLoaded && replayedReadiness
            && parent.restorationIdentity.readySource == expectedReady,
            "init did not admit client ownership independently of view load",
        )
        for nextID in [client.id &+ 1, client.id &+ 2] {
            let next = TdUpdateSource(accountID: accountID, clientID: nextID)
            parent.handleClientSource(next, actorID: actorID)
            parent.handleClientReadiness(nil)
            try PeerProfileMembersRestorationProbe.require(
                !parent.restorationIdentity.accepts(next, current: next, actorID: actorID),
                "unloaded parent admitted pre-ready epoch",
            )
            parent.handleClientReadiness(next)
            guard let retained = parent.restorationState() else {
                throw PeerProfileMembersRestorationProbe.Failure(description: "unloaded parent lost transferable state")
            }
            try PeerProfileMembersRestorationProbe.require(
                !parent.isViewLoaded && parent.sharedMessageRefresh == nil
                && parent.infoTask == nil && parent.historyTask == nil && parent.permissionTask == nil
                && parent.restorationIdentity.accepts(next, current: next, actorID: actorID)
                && retained.source == origin && retained.tab == .files && retained.cursor == 61
                && retained.viewport.messageID == 70 && retained.viewport.minY == -12 && retained.resumePage,
                "unloaded parent epoch lost readiness/state or started view-owned work",
            )
        }
        let foreign = TdUpdateSource(accountID: UUID(), clientID: client.id &+ 3)
        parent.handleClientSource(foreign, actorID: actorID)
        parent.handleClientSource(origin, actorID: actorID)
        try PeerProfileMembersRestorationProbe.require(
            parent.restorationIdentity.revoked && !parent.isViewLoaded,
            "unloaded parent account ABA revived",
        )
    }
    #endif

    private static func statusText(for customChat: CustomChat) -> String {
        switch customChat.type {
        case .bot:
            L10n.telegram("Bot.GenericBotStatus")
        case .user(let user):
            statusText(for: user.status)
        case .group(let group):
            memberCountText(group.memberCount, isChannel: false)
        case .supergroup(let group):
            kindText(isChannel: group.isChannel, isForum: group.isForum)
        }
    }

    private static func memberCountText(_ count: Int, isChannel: Bool) -> String {
        L10n.telegramPlural(
            isChannel ? "Conversation.StatusSubscribers" : "Conversation.StatusMembers",
            count: count,
            formattedCount: String(count),
        )
    }

    private static func kindText(isChannel: Bool, isForum: Bool) -> String {
        if isChannel { return L10n.telegram("Channel.Status") }
        return isForum ? L10n.betterTG("Profile.ForumStatus") : L10n.telegram("Group.Status")
    }

    private static func isOnline(_ status: UserStatus) -> Bool {
        if case .userStatusOnline = status { return true }
        return false
    }

    private static func statusText(for status: UserStatus) -> String {
        switch status {
        case .userStatusOnline: L10n.telegram("Presence.online")
        case .userStatusRecently: L10n.telegram("LastSeen.Lately")
        case .userStatusLastWeek: L10n.telegram("LastSeen.WithinAWeek")
        case .userStatusLastMonth: L10n.telegram("LastSeen.WithinAMonth")
        case .userStatusEmpty, .userStatusOffline: L10n.telegram("LastSeen.Offline")
        }
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        sharedViewportGeneration &+= 1
        let hadPendingViewport = restoredViewport != nil
        restoredViewport = nil
        sharedMessageRefresh?.start()
        if hadPendingViewport, restoration?.shouldResumePage == true { loadMore() }
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { retryClientRestoration() }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) { retryClientRestoration() }

    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard canRestoreClient(source), let state = restorationState(),
              let host = restorationHost(state: state, source: source) else { return nil }
        guard let preparedMetadata, preparedMetadata.0 == source else {
            prepareClientMetadata(source)
            return nil
        }
        return PreparedClientNavigationReplacement(
            preflight: { [weak self, weak host] in
                guard let self else { return false }
                return canRestoreClient(source) && restorationHost(state: state, source: source) === host
            },
            commit: { [self, weak host] in
                guard canRestoreClient(source), let host,
                      restorationHost(state: state, source: source) === host,
                      let replacement = host.makeProfile(customChat: preparedMetadata.1, restoration: state)
                else { return nil }
                if let membersChild, navigationController?.topViewController === membersChild {
                    guard membersChild.canRetain(
                        parent: self,
                        accountID: accountID,
                        actorID: accountUserID,
                        chatID: customChat.id,
                    ),
                        membersChild.transferParent(from: self, to: replacement) else { return nil }
                    replacement.membersChild = membersChild
                }
                clientOwnerRetired = true
                metadataPreparation.cancel()
                historyRequest.invalidate()
                historyTask?.cancel()
                infoTask?.cancel()
                permissionTask?.cancel()
                chatMetadataTask?.cancel()
                avatarGalleryTask?.cancel()
                avatarHistoryTask?.cancel()
                avatarReconciliationTask?.cancel()
                avatarGalleryRequestID = nil
                avatarHistoryRequestID = nil
                avatarReconciliationRequestID = nil
                sharedMessageRefresh?.stop()
                cancellables.removeAll()
                if isViewLoaded {
                    avatarView.prepareForReuse()
                    collectionView.visibleCells.compactMap { $0 as? SharedMediaGridCell }.forEach { $0.pauseLoading() }
                }
                #if DEBUG
                log("Profile client restoration: replacement accepted")
                #endif
                return replacement
            },
        )
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let message = messagesByID[id]
        else { return }
        let performed = sharedMessageRefresh?.perform(id: id) {
            if currentSharedTab == .media, SharedMediaGridPreview.opensGallery(message) {
                openMediaGallery(selectedMessage: message)
            } else {
                // Rich and paid media messages share the photo and video index; the gallery plays only photo and
                // video messages, so these open where they were sent.
                onOpenMessage?(message.id)
            }
        }
        if performed != true { sharedMessageRefresh?.retry() }
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? SharedMediaGridCell)?.resumeLoading()
        guard historyError == nil, indexPath.item >= max(0, messagesByID.count - 6) else { return }
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

    func canRestoreMembers(_ child: PeerProfileMembersViewController, source: TdUpdateSource) -> Bool {
        contextIsCurrent && navigationClientSource == source && membersChild === child
            && child.canRetain(parent: self, accountID: accountID, actorID: accountUserID, chatID: customChat.id)
    }

    func makeRestoredMembers(
        _ child: PeerProfileMembersViewController, state: PeerProfileMembersRestorationState, source: TdUpdateSource,
    ) -> PeerProfileMembersViewController? {
        guard canRestoreMembers(child, source: source), state.source.accountID == accountID,
              state.actorID == accountUserID, state.chatID == customChat.id,
              let memberSource = membersSource(administrators: state.administrators) else { return nil }
        let replacement = PeerProfileMembersViewController(
            accountID: accountID, accountUserID: accountUserID, client: client,
            source: memberSource, title: profileTitle(), restoration: state,
        )
        replacement.attach(to: self)
        membersChild = replacement
        return replacement
    }

    private func restoreViewportIfNeeded() {
        guard restoredSnapshotApplied, profileHeaderView.bounds.height > 0, let viewport = restoredViewport,
              viewport.restore(collectionView, indexPath: { dataSource.indexPath(for: $0) }) else { return }
        restoredViewport = nil
        sharedMessageRefresh?.start()
        if restoration?.shouldResumePage == true { loadMore() }
    }

    private func canRestoreClient(_ source: TdUpdateSource) -> Bool {
        canWaitForClientRestoration && restorationIdentity.accepts(
            source, current: TDLib.shared.activeUpdateSource, actorID: TDLib.shared.activeAccount?.userID,
        ) && RootVM.shared.activeAccountID == accountID && transitionCoordinator == nil
            && (!isViewLoaded || !collectionView.isDragging && !collectionView.isDecelerating)
    }

    private func restorationState() -> PeerProfileRestorationState? {
        guard let accountUserID else { return nil }
        let tab: SharedTab
        let viewport: PeerProfileViewport
        if isViewLoaded {
            tab = currentSharedTab
            viewport = restoredViewport ?? .capture(collectionView, messageID: { dataSource.itemIdentifier(for: $0) })
        } else if let restoration {
            // A covered replacement may never load its view before another client
            // epoch. Transfer accepted state, not an uninitialized collection offset.
            tab = restoration.tab
            viewport = restoredViewport ?? restoration.viewport
        } else { return nil }
        return PeerProfileRestorationState(
            source: restorationIdentity.origin, actorID: accountUserID, chatID: customChat.id, topic: topic,
            tab: tab, messages: sortedSharedMessages, cursor: oldestMessageID,
            hasMore: hasMore, total: sharedTotalMessageCount, error: historyError,
            resumePage: historyRequest.needsResume || restoredViewport != nil && restoration?.shouldResumePage == true,
            bio: currentBioText, details: currentDetailTexts,
            viewport: viewport,
        )
    }

    private func restorationHost(state: PeerProfileRestorationState, source: TdUpdateSource) -> ChatViewController? {
        guard let stack = navigationController?.viewControllers,
              let index = stack.firstIndex(where: { $0 === self }), index > 0,
              let chat = stack[index - 1] as? ChatViewController,
              chat.canRestoreProfile(state, source: source) else { return nil }
        return chat
    }

    private func prepareClientMetadata(_ source: TdUpdateSource) {
        let client = TDLib.shared.activeClient
        guard client.id == source.clientID else { return }
        let chatID = customChat.id
        metadataPreparation.request(source: source, fetch: {
            await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
        }, accepts: { [weak self] in
            self?.restorationIdentity.accepts(
                source,
                current: TDLib.shared.activeUpdateSource,
                actorID: TDLib.shared.activeAccount?.userID,
            ) == true
                && self?.canWaitForClientRestoration == true
        }, completion: { [weak self] chat in
            guard let self else { return }
            guard let chat, chat.id == chatID else {
                navigationItem.prompt = L10n.betterTG("Profile.ReloadFailed")
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    title: L10n.telegram("ChatImportActivity.Retry"),
                    style: .plain,
                    target: self,
                    action: #selector(retryClientRestoration),
                )
                return
            }
            preparedMetadata = (source, chat)
            retryClientRestoration()
        })
    }

    @objc private func retryClientRestoration() {
        guard !clientOwnerRetired, canWaitForClientRestoration, !contextIsCurrent else { return }
        NavigationStorage.shared.retryClientRestoration()
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
        avatarView.accessibilityLabel = L10n.betterTG("Accessibility.ProfilePhotoOf", profileTitle())
        avatarView.accessibilityHint = avatarGalleryIsAvailable
            ? L10n.betterTG("Accessibility.OpenProfilePhotosHint")
            : nil
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

        actionStack.addArrangedSubview(membersActionButton)
        actionStack.addArrangedSubview(administratorsActionButton)
        updateActionAvailability()

        if let tab = restoration?.tab { selectedSharedTab = tab }
        sharedTabs.translatesAutoresizingMaskIntoConstraints = false
        sharedTabs.configure(
            items: SharedTab.allCases.map { .init(id: $0.rawValue, title: $0.title) },
            selectedID: selectedSharedTab.rawValue,
        )
        sharedTabs.onSelection = { [weak self] id in
            guard let self, let tab = SharedTab(rawValue: id), tab != selectedSharedTab else { return }
            selectedSharedTab = tab
            tabChanged()
        }
        profileHeaderView.addSubview(sharedTabs)
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
            sharedTabs.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            sharedTabs.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor),
            sharedTabs.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor),
            sharedTabs.heightAnchor.constraint(equalToConstant: 58),
            sharedTabs.bottomAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: -8),
        ])
    }

    private func profileButton(title: String, symbol: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .top
        configuration.imagePadding = 4
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 12, weight: .medium)
            return outgoing
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 2, bottom: 8, trailing: 2)
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
        collectionView.register(
            SharedMediaPendingCell.self,
            forCellWithReuseIdentifier: SharedMediaPendingCell.reuseIdentifier,
        )
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
        let anchor = dataSource.map { source in
            PeerProfileViewport.capture(collectionView, messageID: { source.itemIdentifier(for: $0) })
        }
        collectionView.contentInset.top = height
        collectionView.verticalScrollIndicatorInsets.top = height
        collectionView.contentOffset.y = distanceFromTop - height
        if let anchor, anchor.messageID != nil {
            _ = anchor.restore(collectionView, indexPath: { dataSource.indexPath(for: $0) })
        }
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
            guard sharedMessageRefresh?.allows(id) == true else {
                let state = sharedMessageRefresh?.state(for: id) ?? .loading
                if currentSharedTab != .media {
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: SharedMediaRowCell.reuseIdentifier, for: indexPath,
                    ) as? SharedMediaRowCell
                    cell?.configurePending(state: state)
                    return cell ?? UICollectionViewCell()
                }
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SharedMediaPendingCell.reuseIdentifier, for: indexPath,
                ) as? SharedMediaPendingCell
                cell?.configure(state: state)
                return cell ?? UICollectionViewCell()
            }
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
              sharedMessageRefresh?.allows(selectedMessage.id) == true,
              let mediaPlaybackContext, mediaPlaybackContext.isCurrent else { return }
        let messages = sortedSharedMessages.filter { message in
            guard sharedMessageRefresh?.allows(message.id) == true else { return false }
            return switch message.content {
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
            // A same-account client renewal keeps the route: the gallery reloads its items through the renewed
            // client, and this profile is replaced once the gallery closes.
            guard let self else { return false }
            return TDLib.shared.activeAccountID == accountID && !clientOwnerRetired && !restorationIdentity.revoked
        }
        gallery.onPrepareOpenMessageID = onPrepareGalleryReturn
        gallery.openInChatTransitionSourceProvider = galleryReturnTarget
        gallery.onOpenMessageTransitionCompleted = onGalleryReturnCompleted
        gallery.onGalleryRestored = { [weak self] restoredGallery in
            guard let self, contextIsCurrent, currentSharedTab == originatingTab else { return }
            activeMediaGallery = restoredGallery
            restoredGallery
                .updateMessages(sortedSharedMessages.filter { self.sharedMessageRefresh?.allows($0.id) == true })
            restoredGallery.updateTotalMessageCount(sharedTotalMessageCount)
        }
        gallery.onDismissed = { [weak self, weak gallery] in
            guard let self, let gallery, activeMediaGallery === gallery else { return }
            activeMediaGallery = nil
            // A client renewed while the gallery covered this profile replaces the profile now, without waiting
            // for the next scroll.
            DispatchQueue.main.async { [weak self] in
                guard let self, !contextIsCurrent else { return }
                handleAccountChange()
            }
        }
        activeMediaGallery = gallery
        (navigationController ?? self).present(gallery, animated: true)
    }

    private func mediaTransitionTarget(for messageID: Int64) -> MediaGalleryTransitionTarget? {
        guard contextIsCurrent, sharedMessageRefresh?.allows(messageID) == true, let message = messagesByID[messageID],
              let indexPath = dataSource.indexPath(for: messageID),
              let cell = collectionView.cellForItem(at: indexPath) as? SharedMediaGridCell
        else { return nil }
        cell.refreshRevealState()
        return cell.transitionTarget(for: messageID) { [weak self, weak cell] in
            guard let self, let cell, contextIsCurrent, sharedMessageRefresh?.allows(messageID) == true,
                  let currentIndexPath = dataSource.indexPath(for: messageID),
                  let current = messagesByID[messageID],
                  MediaRevealSession.Key(message: current) == MediaRevealSession.Key(message: message)
            else { return false }
            return collectionView.cellForItem(at: currentIndexPath) === cell
        }
    }

    /// Source lifetime is independent of view lifetime: a Profile underneath
    /// Members may remain unloaded across more than one replacement epoch.
    private func observeClientOwnership() {
        TDLib.shared
            .activeClientChanges
            .sink { [weak self] source in
                self?.handleClientSource(source, actorID: TDLib.shared.activeAccount?.userID)
            }
            .store(in: &cancellables)
        TDLib.shared
            .readyClientChanges
            .sink { [weak self] source in
                self?.handleClientReadiness(source)
            }
            .store(in: &cancellables)
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            self?.restorationIdentity.observe(
                source: TDLib.shared.activeUpdateSource,
                actorID: TDLib.shared.activeAccount?.userID,
            )
            self?.handleAccountChange()
        }
    }

    private func handleClientSource(_ source: TdUpdateSource, actorID: Int64?) {
        restorationIdentity.observe(source: source, actorID: actorID)
        if preparedMetadata?.0 != source { preparedMetadata = nil }
        metadataPreparation.cancel()
        handleAccountChange()
    }

    private func handleClientReadiness(_ source: TdUpdateSource?) {
        restorationIdentity.readySource = source
        if source == nil { metadataPreparation.cancel() }
        if isViewLoaded {
            if source == restorationIdentity.origin {
                if sharedMessageRefresh == nil { configureSharedMessageRefresh() }
                resumeSharedHistoryIfNeeded()
            } else {
                sharedMessageRefresh?.stop()
                sharedMessageRefresh = nil
                historyTask?.cancel()
                historyTask = nil
                if source.map({ $0.accountID != accountID }) ?? false || !keepsMediaGalleryThroughClientRenewal {
                    revokeSharedMessages(Set(messagesByID.keys))
                }
            }
        }
        retryClientRestoration()
    }

    private func observeAccount() {
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
        nc.scopedPublisher(&cancellables, for: .updateMessageContent) { [weak self] event in
            self?.sharedMessageRefresh?.invalidate(
                id: event.value.messageId,
                chatID: event.value.chatId,
                source: event.source,
            )
        }
        nc.scopedPublisher(&cancellables, for: .updateMessageEdited) { [weak self] event in
            self?.sharedMessageRefresh?.invalidate(
                id: event.value.messageId,
                chatID: event.value.chatId,
                source: event.source,
            )
        }
        nc.scopedPublisher(&cancellables, for: .updateDeleteMessages) { [weak self] event in
            self?.sharedMessageRefresh?.delete(event.value, source: event.source)
        }
    }

    private func handleAccountChange() {
        guard !contextIsCurrent else { return }
        guard !editorRetention.shouldRetain(
            parent: self, accountID: accountID, currentAccountID: TDLib.shared.activeAccountID,
        ) else { return }
        if !restorationIdentity.revoked, membersChild?.retainsMemberTag(
            parent: self, accountID: accountID, actorID: accountUserID, chatID: customChat.id,
        ) == true { return }
        if canWaitForClientRestoration {
            // The replacement usually lands within a frame; the prompt marks only a restoration that takes longer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !clientOwnerRetired, !contextIsCurrent, canWaitForClientRestoration else { return }
                navigationItem.prompt = L10n.betterTG("Session.Reconnecting")
            }
            retryClientRestoration()
            return
        }
        if keepsMediaGalleryThroughClientRenewal { return }
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
        currentStatusIsOnline = !isSelfProfile && Self.isOnline(update.status)
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
        currentStatusIsOnline = !isSelfProfile && Self.isOnline(update.user.status)
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
        currentStatusText = Self.memberCountText(update.basicGroup.memberCount, isChannel: false)
        scheduleMetadataRender()
    }

    private func handleSupergroupUpdate(_ update: UpdateSupergroup, source: TdUpdateSource) {
        guard contextIsCurrent, update.supergroup.id == customChat.supergroup?.id,
              infoPermission.updateStatus(
                  update.supergroup.status,
                  chatType: .chatTypeSupergroup(.init(
                      supergroupId: update.supergroup.id,
                      isChannel: update.supergroup.isChannel,
                  )), source: source,
              )
        else { return }
        customChat.type = .supergroup(update.supergroup)
        currentStatusText =
            if update.supergroup.memberCount > 0 {
                Self.memberCountText(update.supergroup.memberCount, isChannel: update.supergroup.isChannel)
            } else {
                Self.kindText(isChannel: update.supergroup.isChannel, isForum: update.supergroup.isForum)
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
        applyFullInfo(
            bio: update.supergroupFullInfo.description,
            details: group.usernames?.activeUsernames.map { "@\($0)" } ?? [],
            status: update.supergroupFullInfo.memberCount > 0
                ? Self.memberCountText(update.supergroupFullInfo.memberCount, isChannel: group.isChannel)
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
            currentChatTitle = isSelfProfile ? L10n.telegram("Conversation.SavedMessages") : chat.title
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
            mainID: info.photo?.id,
            personalID: isSelfProfile ? nil : info.personalPhoto?.id,
            publicID: info.publicPhoto?.id,
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
        guard !clientOwnerRetired else { return }
        titleLabel.text = profileTitle()
        statusLabel.text = currentStatusText
        statusLabel.textColor = currentStatusIsOnline ? .systemGreen : .secondaryLabel
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
        avatarView.accessibilityLabel = L10n.betterTG("Accessibility.ProfilePhotoOf", profileTitle())
        avatarView.accessibilityHint = avatarGalleryIsAvailable
            ? L10n.betterTG("Accessibility.OpenProfilePhotosHint")
            : nil
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
        let canEdit =
            if let user = customChat.user {
                user.id == accountUserID
            } else {
                infoPermission.canChangeInfo
            }
        navigationItem.rightBarButtonItem = canEdit
            ? UIBarButtonItem(
                title: L10n.telegram("Common.Edit"), style: .plain, target: self, action: #selector(editPressed),
            )
            : nil
    }

    private func configureSharedMessageRefresh() {
        sharedMessageRefresh?.stop()
        let source = restorationIdentity.origin
        let tab = currentSharedTab
        let client = client
        let chatID = customChat.id
        let topic = topic
        let refresh = PeerProfileSharedMessageRefresh(
            source: source,
            location: ChatLocation(accountID: accountID, chatID: chatID, clientID: client.id, topic: topic),
            tab: tab, seedIDs: sortedSharedMessages.map(\.id),
            visibleIDs: [restoredViewport?.messageID].compactMap(\.self),
            accepts: { [weak self] in
                guard let self else { return false }
                return contextIsCurrent && restorationIdentity.readySource == source
                    && TDLib.shared.activeAccount?.userID == accountUserID && currentSharedTab == tab
                    && chatListActionOwnerIsAttached
            },
            canStart: { [weak self] in self?.restoredViewport == nil },
            read: { try await client.getMessage(chatId: chatID, messageId: $0) },
            searchMembership: { messageID in
                // Offset -1 starts the page at the message itself, so it is returned if the tab's filter matches.
                try await client.searchChatMessages(
                    chatId: chatID, filter: tab.filter, fromMessageId: messageID, limit: 2, offset: -1, query: "",
                    senderId: nil, topicId: topic,
                )
                .messages
                .contains { $0.id == messageID }
            },
        )
        refresh.onChange = { [weak self, weak refresh] change in
            guard let self, let refresh, sharedMessageRefresh === refresh else { return }
            switch change {
            case .quarantine(let ids): revokeSharedMessages(ids)
            case .message(let message): messagesByID[message.id] = message
            case .remove(let id):
                if messagesByID.removeValue(forKey: id) != nil, let total = sharedTotalMessageCount {
                    sharedTotalMessageCount = max(messagesByID.count, total - 1)
                }
            case .retry: break
            }
            scheduleSharedSnapshot()
        }
        sharedMessageRefresh = refresh
    }

    private func resumeSharedHistoryIfNeeded() {
        sharedMessageRefresh?.resume(
            needsPage: messagesByID.isEmpty || historyRequest.needsResume,
            hasError: historyError != nil,
            loadPage: { loadMore() },
        )
    }

    private func revokeSharedMessages(_ ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        mediaRevealSession?.revoke(messageIDs: ids)
        // Revoked permits cannot escape through retained PiP or a transition snapshot.
        if let mediaPlaybackContext {
            GalleryPictureInPictureCoordinator.shared.contextWasRevoked(mediaPlaybackContext, revokeContext: false)
        }
        if let gallery = activeMediaGallery {
            activeMediaGallery = nil
            gallery.invalidateForContextChange(revokePlaybackContext: false, completion: {})
        }
        for path in collectionView.indexPathsForVisibleItems {
            guard let id = dataSource.itemIdentifier(for: path), ids.contains(id),
                  let cell = collectionView.cellForItem(at: path) else { continue }
            cell.prepareForReuse()
            cell.contentView.isHidden = true
            cell.accessibilityElementsHidden = true
            cell.accessibilityLabel = L10n.betterTG("Profile.LoadingMessage")
        }
        scheduleSharedSnapshot()
    }

    private func scheduleSharedSnapshot() {
        guard !sharedSnapshotScheduled else { return }
        sharedSnapshotScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            sharedSnapshotScheduled = false
            guard !clientOwnerRetired, isViewLoaded else { return }
            applySnapshot(animated: false)
        }
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
                    guard !Task.isCancelled,
                          contextIsCurrent,
                          fullInfoGeneration == generation
                    else { return }
                    currentSupergroupCanGetMembers = info.canGetMembers
                    applyFullInfo(
                        bio: info.description,
                        details: group.usernames?.activeUsernames.map { "@\($0)" } ?? [],
                        status: info.memberCount > 0
                            ? Self.memberCountText(info.memberCount, isChannel: group.isChannel)
                            : nil,
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
        guard restoredViewport == nil, historyTask == nil, hasMore, contextIsCurrent,
              let refresh = sharedMessageRefresh, let readToken = refresh.beginPage() else { return }
        let fromMessageID = oldestMessageID ?? 0
        let requestedTab = currentSharedTab
        let requestID = historyRequest.begin()
        historyError = nil
        historyTask = Task { [weak self] in
            guard let self else {
                refresh.finishPage()
                return
            }
            guard !Task.isCancelled, refresh.canRead, sharedMessageRefresh === refresh else {
                if historyRequest.finish(requestID) { historyTask = nil }
                refresh.finishPage()
                return
            }
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
                      contextIsCurrent, refresh.canRead,
                      currentSharedTab == requestedTab, sharedMessageRefresh === refresh
                else {
                    if historyRequest.finish(requestID) {
                        historyTask = nil
                        refresh.finishPage()
                    }
                    return
                }
                guard historyRequest.finish(requestID, settled: true) else { return }
                let messages = result.messages
                let nextCursor = messages.last?.id
                refresh.acceptPage(messages, token: readToken).install(into: &messagesByID)
                sharedTotalMessageCount = max(messagesByID.count, result.totalCount)
                oldestMessageID = nextCursor
                hasMore = !messages.isEmpty && (fromMessageID == 0 || nextCursor != fromMessageID)
                historyError = nil
                historyTask = nil
                applySnapshot()
            } catch is CancellationError {
                guard historyRequest.finish(requestID) else { return }
                refresh.finishPage()
                historyTask = nil
                guard contextIsCurrent, currentSharedTab == requestedTab,
                      sharedMessageRefresh === refresh else { return }
                applySnapshot()
            } catch {
                guard historyRequest.finish(
                    requestID,
                    settled: !Task.isCancelled && refresh.canRead && sharedMessageRefresh === refresh,
                )
                else { return }
                refresh.finishPage()
                historyTask = nil
                guard !Task.isCancelled, refresh.canRead, sharedMessageRefresh === refresh else { return }
                historyError = requestedTab.loadFailedText
                activeMediaGallery?.allowMoreMessagesRetry()
                applySnapshot()
            }
        }
        if messagesByID.isEmpty {
            applySnapshot()
        }
    }

    private func applySnapshot(animated: Bool = true, completion: (() -> Void)? = nil) {
        let messages = sortedSharedMessages
        // Revoke accepted same-ID revisions before either grid cells or the gallery can use old pixels.
        let admitted = messages.filter { sharedMessageRefresh?.allows($0.id) == true }
        mediaRevealSession?.reconcile(admitted)
        let existingIDs = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(messages.map(\.id))
        let readiness = Dictionary(uniqueKeysWithValues: messages.map { (
            $0.id,
            sharedMessageRefresh?.allows($0.id) == true,
        ) })
        let existing = messages.map(\.id).filter(existingIDs.contains)
        let changedKinds = currentSharedTab == .media
            ? existing.filter { sharedCellReadiness[$0] != readiness[$0] }
            : []
        snapshot.reloadItems(changedKinds)
        snapshot.reconfigureItems(existing.filter { !changedKinds.contains($0) })
        sharedCellReadiness = readiness
        let viewport = restoredViewport == nil
            ? PeerProfileViewport.capture(collectionView, messageID: { dataSource.itemIdentifier(for: $0) })
            : nil
        sharedViewportGeneration &+= 1
        let generation = sharedViewportGeneration
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self, !clientOwnerRetired else { return }
            if sharedViewportGeneration == generation, let viewport {
                _ = viewport.restore(collectionView, indexPath: { self.dataSource.indexPath(for: $0) })
            }
            completion?()
        }
        if currentSharedTab == .media {
            activeMediaGallery?.updateMessages(admitted)
            activeMediaGallery?.updateTotalMessageCount(sharedTotalMessageCount)
        }
        guard messages.isEmpty else {
            collectionView.backgroundView = nil
            return
        }
        if let historyError {
            var configuration = UIButton.Configuration.plain()
            configuration.title = L10n.betterTG("Profile.TapToRetryFormat", historyError)
            let button = UIButton(configuration: configuration)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.addTarget(self, action: #selector(retrySharedMedia), for: .touchUpInside)
            button.accessibilityHint = L10n.betterTG("Accessibility.RetrySharedMediaHint")
            collectionView.backgroundView = button
        } else {
            let label = UILabel()
            label.text = historyTask == nil ? currentSharedTab.emptyText : L10n.betterTG("Profile.Loading")
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            collectionView.backgroundView = label
        }
    }

    private func initialStatus() -> String {
        currentStatusText
    }

    private func profileTitle() -> String {
        isSelfProfile ? L10n.telegram("Conversation.SavedMessages") : currentChatTitle
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
            let effectiveID = currentUserProfilePhoto?.id
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
            let resultIDs = Set(result.photos.map(\.id))
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
        sharedViewportGeneration &+= 1
        restoredViewport = nil
        historyRequest.invalidate()
        historyTask?.cancel()
        historyTask = nil
        sharedMessageRefresh?.stop()
        messagesByID = [:]
        oldestMessageID = nil
        hasMore = true
        historyError = nil
        sharedTotalMessageCount = nil
        configureSharedMessageRefresh()
        collectionView.collectionViewLayout.invalidateLayout()
        loadMore()
    }

    @objc private func messagePressed() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func membersPressed() {
        guard contextIsCurrent else { return }
        if case .supergroup = customChat.type, !currentSupergroupCanGetMembers { return }
        guard let source = membersSource(administrators: false) else { return }
        pushMembers(source)
    }

    private func membersSource(administrators: Bool) -> PeerProfileMembersViewController.Source? {
        switch customChat.type {
        case .group(let group):
            administrators
                ? .administrators(chatID: customChat.id, group: .basic(group.id))
                : .basicGroup(chatID: customChat.id, id: group.id)
        case .supergroup(let group):
            administrators
                ? .administrators(chatID: customChat.id, group: .supergroup(group.id))
                : .supergroup(chatID: customChat.id, id: group.id)
        case .bot, .user:
            nil
        }
    }

    private func pushMembers(_ source: PeerProfileMembersViewController.Source) {
        let child = PeerProfileMembersViewController(
            accountID: accountID,
            accountUserID: accountUserID,
            client: client,
            source: source,
            title: profileTitle(),
        )
        child.attach(to: self)
        membersChild = child
        navigationController?.pushViewController(child, animated: true)
    }

    @objc private func administratorsPressed() {
        guard contextIsCurrent else { return }
        guard let source = membersSource(administrators: true) else { return }
        pushMembers(source)
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
        let editor = PeerProfileEditViewController(
            accountID: accountID,
            accountUserID: accountUserID,
            mode: mode,
        )
        editorRetention.editor = editor
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func retrySharedMedia() {
        sharedMessageRefresh?.retry()
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
        guard let representedMessage, let context else { return false }
        if MediaRevealSession.Key(message: representedMessage) == nil {
            // No reveal session covers these items: only an unspoilered preview shows its pixels.
            return context.isCurrent && SharedMediaGridPreview(message: representedMessage)?.hasSpoiler == false
        }
        guard permit?.matches(context) == true else { return false }
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
        imageView.alpha = 1
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
        contentView.isHidden = false
        accessibilityElementsHidden = false
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
            accessibilityHint = L10n.betterTG("Accessibility.OpenMedia")
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
            accessibilityHint = permit?.key.isSecret == true ? nil : L10n.betterTG("Accessibility.OpenMedia")
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
                imageView.loadPlaceholder(data: photo.photo.minithumbnail?.data, client: client)
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
                imageView.loadPlaceholder(data: video.video.minithumbnail?.data, client: client)
            }
            videoBadge.isHidden = false
        default:
            if let preview = SharedMediaGridPreview(message: message) {
                if let file = preview.file {
                    imageView.load(
                        file: file,
                        placeholderData: preview.minithumbnail,
                        maximumPixelSize: 480,
                        accountID: accountID,
                        client: client,
                    )
                } else {
                    imageView.loadPlaceholder(data: preview.minithumbnail, client: client)
                }
                videoBadge.isHidden = !preview.isVideo
            } else {
                imageView.loadPlaceholder(data: nil, origin: nil)
                videoBadge.isHidden = true
            }
        }
    }
}

// MARK: - SharedMediaGridPreview

/// The picture of a photo and video index item that is neither a photo nor a video message: the first photo, video or
/// animation block of a rich message, or the first item of paid media. Telegram's grid likewise shows a message's
/// first image or file (`PeerInfoVisualMediaPaneNode`, `message.effectiveMedia`).
struct SharedMediaGridPreview {
    let file: File?
    let minithumbnail: Data?
    let isVideo: Bool
    let hasSpoiler: Bool

    init?(message: Message) {
        switch message.content {
        case .messageRichMessage(let rich):
            guard let preview = Self.first(in: rich.message.blocks, depth: 0) else { return nil }
            self = preview
        case .messagePaidMedia(let paid):
            guard let media = paid.media.first else { return nil }
            switch media {
            case .paidMediaPhoto(let value):
                self = Self(photo: value.photo, hasSpoiler: false)
            case .paidMediaVideo(let value):
                self = Self(
                    file: value.video.thumbnail?.file, minithumbnail: value.video.minithumbnail?.data, isVideo: true,
                    hasSpoiler: false,
                )
            case .paidMediaPreview(let value):
                self = Self(
                    file: nil,
                    minithumbnail: value.minithumbnail?.data,
                    isVideo: value.duration > 0,
                    hasSpoiler: false,
                )
            case .paidMediaUnsupported:
                return nil
            }
        default:
            return nil
        }
    }

    private init(file: File?, minithumbnail: Data?, isVideo: Bool, hasSpoiler: Bool) {
        self.file = file
        self.minithumbnail = minithumbnail
        self.isVideo = isVideo
        self.hasSpoiler = hasSpoiler
    }

    private init(photo: Photo, hasSpoiler: Bool) {
        self.init(
            file: (photo.sizes.getSize(.yBox) ?? photo.sizes.first)?.photo, minithumbnail: photo.minithumbnail?.data,
            isVideo: false, hasSpoiler: hasSpoiler,
        )
    }

    static func opensGallery(_ message: Message) -> Bool {
        switch message.content {
        case .messagePhoto, .messageVideo: true
        default: false
        }
    }

    private static func first(in blocks: [TDNativePageBlock], depth: Int) -> Self? {
        guard depth < 16 else { return nil }
        for block in blocks.prefix(64) {
            let preview: Self? =
                switch block {
                case .pageBlockPhoto(let value):
                    value.photo.map { Self(photo: $0, hasSpoiler: value.hasSpoiler) }
                case .pageBlockVideo(let value):
                    value.video.map {
                        Self(
                            file: $0.thumbnail?.file, minithumbnail: $0.minithumbnail?.data, isVideo: true,
                            hasSpoiler: value.hasSpoiler,
                        )
                    }
                case .pageBlockAnimation(let value):
                    value.animation.map {
                        Self(
                            file: $0.thumbnail?.file, minithumbnail: $0.minithumbnail?.data, isVideo: true,
                            hasSpoiler: value.hasSpoiler,
                        )
                    }
                case .pageBlockCover(let value): first(in: [value.cover], depth: depth + 1)
                case .pageBlockCollage(let value): first(in: value.blocks, depth: depth + 1)
                case .pageBlockSlideshow(let value): first(in: value.blocks, depth: depth + 1)
                case .pageBlockEmbeddedPost(let value): first(in: value.blocks, depth: depth + 1)
                default: nil
                }
            if let preview { return preview }
        }
        return nil
    }
}

// MARK: - SharedMediaPendingCell

/// Actual loading/error state. No seed text, thumbnail, file or reveal capability enters this cell.
final class SharedMediaPendingCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedMediaPendingCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.clipsToBounds = true
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func configure(state: PeerProfileSharedMessageRefresh.State) {
        contentView.isHidden = false
        accessibilityElementsHidden = false
        label.text = state == .retry
            ? L10n.betterTG("Profile.RefreshFailedMultiline")
            : L10n.betterTG("Profile.LoadingMessage")
        isAccessibilityElement = true
        accessibilityLabel = label.text
        accessibilityTraits = state == .retry ? .button : .staticText
    }
}

// MARK: - SharedMediaRowCell

final class SharedMediaRowCell: UICollectionViewCell {
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

    func configurePending(state: PeerProfileSharedMessageRefresh.State) {
        contentView.isHidden = false
        accessibilityElementsHidden = false
        titleLabel.text = state == .retry
            ? L10n.betterTG("Profile.RefreshFailed")
            : L10n.betterTG("Profile.LoadingMessage")
        subtitleLabel.text = state == .retry ? L10n.betterTG("Profile.TapToRetry") : " "
        iconView.image = UIImage(systemName: state == .retry ? "arrow.clockwise" : "clock")
        isAccessibilityElement = true
        accessibilityTraits = state == .retry ? .button : .staticText
        accessibilityLabel = state == .retry
            ? L10n.betterTG("Profile.RefreshFailedTapToRetry")
            : L10n.betterTG("Profile.LoadingMessage")
    }

    func configure(message: Message) {
        contentView.isHidden = false
        accessibilityElementsHidden = false
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
