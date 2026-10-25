// PeerProfileViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - PeerProfileViewController

@MainActor final class PeerProfileViewController: UIViewController, UICollectionViewDelegate,
ClientRestorableNavigationEntry {
    /// Telegram's panes in its order (Members for a large group, `peerInfoAvailableMediaPanes`, Groups for a user,
    /// then a channel's Similar Channels or a bot's Similar Bots). A pane shows only when it has content.
    enum SharedTab: Int, CaseIterable {
        case members = 7
        case media = 0
        case files = 1
        case audio = 2
        case voice = 3
        case links = 4
        case gifs = 5
        case groupsInCommon = 6
        case similarChannels = 8
        case similarBots = 9

        var title: String {
            switch self {
            case .media: L10n.telegram("PeerInfo.PaneMedia")
            case .files: L10n.telegram("PeerInfo.PaneFiles")
            case .audio: L10n.telegram("PeerInfo.PaneAudio")
            case .voice: L10n.telegram("PeerInfo.PaneVoiceAndVideo")
            case .links: L10n.telegram("PeerInfo.PaneLinks")
            case .gifs: L10n.telegram("PeerInfo.PaneGifs")
            case .groupsInCommon: L10n.telegram("PeerInfo.PaneGroups")
            case .members: L10n.telegram("PeerInfo.PaneMembers")
            case .similarChannels: L10n.telegram("PeerInfo.PaneRecommended")
            case .similarBots: L10n.telegram("PeerInfo.PaneRecommendedBots")
            }
        }

        var loadFailedText: String {
            switch self {
            case .media: L10n.betterTG("Profile.SharedMediaLoadFailed")
            case .files: L10n.betterTG("Profile.SharedFilesLoadFailed")
            case .audio: L10n.betterTG("Profile.SharedAudioLoadFailed")
            case .voice: L10n.betterTG("Profile.SharedVoiceLoadFailed")
            case .links: L10n.betterTG("Profile.SharedLinksLoadFailed")
            case .gifs: L10n.betterTG("Profile.SharedGIFsLoadFailed")
            case .groupsInCommon: L10n.betterTG("Profile.SharedGroupsLoadFailed")
            case .members: L10n.betterTG("Profile.SharedMembersLoadFailed")
            case .similarBots,
                 .similarChannels: L10n.betterTG("Profile.SimilarLoadFailed")
            }
        }

        var emptyText: String {
            switch self {
            case .media: L10n.betterTG("Profile.SharedMediaEmpty")
            case .files: L10n.betterTG("Profile.SharedFilesEmpty")
            case .audio: L10n.betterTG("Profile.SharedAudioEmpty")
            case .voice: L10n.betterTG("Profile.SharedVoiceEmpty")
            case .links: L10n.betterTG("Profile.SharedLinksEmpty")
            case .gifs: L10n.betterTG("Profile.SharedGIFsEmpty")
            case .groupsInCommon: L10n.betterTG("Profile.SharedGroupsEmpty")
            case .members: L10n.betterTG("Profile.NoMembers")
            case .similarBots,
                 .similarChannels: L10n.betterTG("Profile.SimilarEmpty")
            }
        }

        /// The message index a pane lists; Groups lists chats and Members lists people instead.
        var filter: SearchMessagesFilter? {
            switch self {
            case .media: .searchMessagesFilterPhotoAndVideo
            case .files: .searchMessagesFilterDocument
            case .audio: .searchMessagesFilterAudio
            case .voice: .searchMessagesFilterVoiceAndVideoNote
            case .links: .searchMessagesFilterUrl
            case .gifs: .searchMessagesFilterAnimation
            case .groupsInCommon,
                 .members,
                 .similarBots,
                 .similarChannels: nil
            }
        }

        /// PeerInfoRecommendedPeersPane: the recommendations TDLib returns at once.
        var isSimilar: Bool {
            self == .similarChannels || self == .similarBots
        }

        /// Media and GIFs show a grid of previews; the other panes list their items.
        var isGrid: Bool {
            self == .media || self == .gifs
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
        /// A group or channel pages its photo history through its chat photo messages.
        var chatID: Int64?
        var nextMessageID: Int64 = 0

        var hasHistory: Bool {
            userID != nil || chatID != nil && nextMessageID != 0
        }
    }

    private struct UserPhotoRoleSignature: Equatable {
        let mainID: Int64?
        let personalID: Int64?
        let publicID: Int64?
    }

    #if DEBUG
        /// `-ui-probe-main-web-app`: Open App shows on every other profile and opens the probe page after the terms.
        static var probeShowsOpenApp = false
    #endif

    var onOpenMessage: ((Int64) -> Void)?
    var onPrepareGalleryReturn: ((Int64) async -> Bool)?
    var onGalleryReturnCompleted: ((Int64) -> Void)?
    var galleryReturnTarget: ((Int64) -> MediaGalleryTransitionTarget?)?
    var onSearch: (() -> Void)?
    /// Opened away from its own chat (forum Group Info, an avatar's Open Profile): the profile opens the chat itself
    /// and rebuilds itself after a same-account client renewal, since no chat below can host it.
    private(set) var opensChatItself = false

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
    /// `updateChatOnlineMemberCount` for a group, which adds ", M online" to its member count.
    private var onlineMemberCount = 0
    private var currentStatusIsOnline = false
    private var currentBioText = ""
    private var currentDetailTexts = [String]()
    private let avatarView = ProfileAvatarView()
    /// Telegram's story ring around the profile photo (PeerInfoAvatarTransformContainerNode: 3 pt, 1.5 pt once seen).
    private let storyRingView = StoryAvatarRingView(activeLineWidth: 3, inactiveLineWidth: 1.5)
    private lazy var avatarTapGesture = UITapGestureRecognizer(target: self, action: #selector(avatarPressed))
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
    private lazy var moreActionButton = profileButton(
        title: L10n.telegram("PeerInfo.ButtonMore"),
        symbol: "ellipsis",
        action: #selector(morePressed),
    )
    /// PeerInfoProfileItems' Open App under a bot's about text (`botInfo.flags.contains(.hasWebApp)`), a 52 pt filled
    /// button. Fake and scam bots get their warning in its place.
    private lazy var openAppButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = L10n.telegram("PeerInfo.OpenAppButton")
        configuration.cornerStyle = .large
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(openAppPressed), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var webAppLauncher = WebAppLauncher(host: .init(
        accountID: accountID,
        client: client,
        presenter: { [weak self] in self },
        isCurrent: { [weak self] in self?.contextIsCurrent == true },
        actions: .init(
            openTelegramLink: { [weak self] url in TelegramLinkRouter.shared.open(url, from: self) },
            switchInline: { _, _ in },
        ),
    ))
    private var moreMenuTask: Task<Void, Never>?
    private let profileHeaderView = UIView()
    private let sharedTabs = FolderPickerView()
    private var selectedSharedTab = SharedTab.media
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Int64>!
    private var messagesByID = [Int64: Message]()
    private var cancellables = Set<AnyCancellable>()
    private var infoTask: Task<Void, Never>?
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
    /// What a shared cell shows. A snapshot reconfigures only cells whose signature changed, so a page load or a
    /// refresh of other items does not restart every thumbnail.
    private var sharedCellSignatures = [Int64: SharedCellSignature]()
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
    private var avatarHistoryChatID: Int64?
    private var avatarHistoryNextMessageID = Int64.zero
    /// The open avatar gallery has its full list, not only the photo it opened on.
    private var avatarGalleryListLoaded = false
    private var metadataGeneration = UInt64.zero
    private var fullInfoGeneration = UInt64.zero
    private var avatarMetadataGeneration = UInt64.zero
    private var hasHydratedFullInfo = false
    private var metadataRenderScheduled = false
    private var renderedAvatarFileID: Int?
    private var renderedAvatarItemID: Int64?
    private weak var activeMediaGallery: MediaGalleryViewController?
    /// The Files or Audio row whose file is downloading to open or play, as Telegram's list pane downloads in place.
    private var sharedItemDownload: (messageID: Int64, fileID: Int, task: Task<Void, Never>, updates: AnyCancellable?)?
    private var sharedItemProgress = [Int64: Float]()
    /// Panes with content, nil until the first counts arrive. A pane whose count is unknown stays until it is known.
    private var availableSharedTabs: [SharedTab]?
    private var sharedTabCounts = [SharedTab: Int]()
    private var sharedTabCountsLoaded = false
    private var sharedTabCountTask: Task<Void, Never>?
    private var sharedTabsHeightConstraint: NSLayoutConstraint!
    private var groupsInCommonCount: Int?
    /// Telegram's Members pane (PeerInfoData's long list), made once the group qualifies.
    private var membersPane: PeerProfileMembersPane?
    private var currentSupergroupMemberCount = 0
    /// The group's full info arrived (or failed): the Members pane's place is known.
    private var membersInfoLoaded = false
    private var groupsInCommon = [Int64]()
    private var groupsByID = [Int64: CustomChat]()
    private var groupsInCommonOffset = Int64.zero
    private var groupsInCommonHasMore = true
    private var groupsInCommonTask: Task<Void, Never>?
    private var groupsInCommonGeneration = UInt64.zero
    /// getChatSimilarChatCount or getBotSimilarBotCount; the pane shows once it is above zero.
    private var similarCount: Int?
    private var similarCountTask: Task<Void, Never>?
    private var similarChats = [Int64]()
    private var similarByID = [Int64: CustomChat]()
    private var similarTask: Task<Void, Never>?
    private var similarGeneration = UInt64.zero
    private var similarLoaded = false
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
            && !isPresentingTelegramContextMenu
    }

    /// A same-account client renewal (the app returning from the background) keeps an open shared-media or avatar
    /// gallery, as it keeps the chat's: the gallery moves its items to the renewed client, and this profile is
    /// replaced once the gallery closes.
    private var keepsGalleryThroughClientRenewal: Bool {
        (activeMediaGallery != nil || activeAvatarGallery != nil) && !clientOwnerRetired && !restorationIdentity
            .revoked && accountUserID != nil
            && TDLib.shared.activeAccountID == accountID && TDLib.shared.activeAccount?.userID == accountUserID
    }

    /// The open avatar gallery's client while it belongs to this account: the profile's own client, or the renewed
    /// client the gallery moved its photos to.
    private var avatarGalleryClient: TDLibClient? {
        guard let activeAvatarGallery,
              !clientOwnerRetired,
              !restorationIdentity.revoked,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == activeAvatarGallery.client.id
        else { return nil }
        return activeAvatarGallery.client
    }

    /// The screen under this profile already shows its chat (a forum's topic list for Group Info).
    private var chatIsBelow: Bool {
        guard let stack = navigationController?.viewControllers,
              let index = stack.firstIndex(where: { $0 === self }), index > 0 else { return false }
        let below = stack[index - 1]
        return (below as? ChatViewController)?.displayedChatID == customChat.id
            || (below as? ForumTopicsViewController)?.displayedChatID == customChat.id
    }

    /// The peer's active stories ring the avatar, which then opens them, as Telegram's profile does
    /// (requestAvatarExpansion opens expiring stories before the photo gallery).
    private var storyRingStyle: StoryAvatarRingView.Style? {
        isSelfProfile ? nil : customChat.activeStoryState?.ringStyle
    }

    /// The owner or an administrator of this group or channel, who reaches Telegram's management screens.
    private var isChatAdministrator: Bool {
        let status: ChatMemberStatus? =
            switch customChat.type {
            case .group(let group): group.status
            case .supergroup(let group): group.status
            case .bot,
                 .user: nil
            }
        return switch status {
        case .chatMemberStatusAdministrator?: true
        case .chatMemberStatusCreator(let creator)?: creator.isMember
        default: false
        }
    }

    /// The chats with a Members pane: groups, outside a topic (PeerInfoData reads members for a peer location only).
    private var listsMembers: Bool {
        guard topic == nil else { return false }
        return switch customChat.type {
        case .group: true
        case .supergroup(let group): !group.isChannel
        case .bot,
             .user: false
        }
    }

    /// PeerInfoData's long list: a group whose members the account may read, with more than five of them.
    private var showsMembersPane: Bool {
        guard listsMembers else { return false }
        return switch customChat.type {
        case .group(let group):
            max(group.memberCount, currentBasicGroupMembers.count) > PeerProfileMembersPane.threshold
        case .supergroup(let group):
            currentSupergroupCanGetMembers
                && max(group.memberCount, currentSupergroupMemberCount) > PeerProfileMembersPane.threshold
        case .bot,
             .user:
            false
        }
    }

    /// A channel's recommendations, outside its topics.
    private var listsSimilarChannels: Bool {
        topic == nil && customChat.supergroup?.isChannel == true
    }

    /// PeerInfoData's group status: the member count, then ", M online" once more than one member is online.
    private var displayedStatusText: String {
        guard topic == nil, onlineMemberCount > 1 else { return currentStatusText }
        let memberCount: Int =
            switch customChat.type {
            case .group(let group): group.memberCount
            case .supergroup(let group) where !group.isChannel:
                currentSupergroupMemberCount > 0 ? currentSupergroupMemberCount : group.memberCount
            default: 0
            }
        guard memberCount > 0 else { return currentStatusText }
        return ChatVM.memberStatus(memberCount: memberCount, onlineMemberCount: onlineMemberCount)
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
        avatarHistoryTask?.cancel()
        avatarReconciliationTask?.cancel()
        chatMetadataTask?.cancel()
        permissionTask?.cancel()
        historyTask?.cancel()
        sharedTabCountTask?.cancel()
        groupsInCommonTask?.cancel()
        similarCountTask?.cancel()
        similarTask?.cancel()
        moreMenuTask?.cancel()
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
            // The first pane loads once the counts show which panes have content.
            applySnapshot()
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
        cancelSharedItemDownload(cancelInTDLib: true)
        metadataPreparation.cancel()
        avatarHistoryTask?.cancel()
        avatarReconciliationTask?.cancel()
        avatarHistoryRequestID = nil
        avatarReconciliationRequestID = nil
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
        case .bot(let user):
            // PeerInfoData's `.bot`: the bot's monthly users once Telegram counts any.
            if case .userTypeBot(let bot) = user.type, bot.activeUserCount > 0 {
                L10n.telegramPlural("Conversation.StatusBotSubscribers", count: bot.activeUserCount)
            } else {
                L10n.telegram("Bot.GenericBotStatus")
            }
        case .user(let user):
            statusText(for: user.status)
        case .group(let group):
            memberCountText(group.memberCount, isChannel: false)
        case .supergroup(let group):
            kindText(isChannel: group.isChannel, isForum: group.isForum)
        }
    }

    private static func memberCountText(_ count: Int, isChannel: Bool) -> String {
        L10n.telegramPlural(isChannel ? "Conversation.StatusSubscribers" : "Conversation.StatusMembers", count: count)
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
        case .userStatusEmpty,
             .userStatusOffline: L10n.telegram("LastSeen.Offline")
        }
    }

    private static func chatPhotoItems(_ messages: [Message]) -> [ProfileAvatarGalleryItem] {
        messages.compactMap { message in
            guard case .messageChatChangePhoto(let change) = message.content else { return nil }
            return ProfileAvatarGalleryItem(photo: change.photo)
        }
    }

    private static func groupSubtitle(_ chat: CustomChat) -> String? {
        let count = chat.supergroup?.memberCount ?? chat.group?.memberCount ?? 0
        guard count > 0 else { return nil }
        return memberCountText(count, isChannel: chat.supergroup?.isChannel == true)
    }

    private static func voiceSenderTitle(of message: Message, client: TDLibClient) async -> String? {
        switch message.senderId {
        case .messageSenderUser(let sender):
            guard let user = try? await client.getUser(userId: sender.userId) else { return nil }
            return ServiceMessageText.displayTitle(user)
        case .messageSenderChat(let sender):
            return try? await client.getChat(chatId: sender.chatId).title
        }
    }

    /// RecommendedPeersListEntry: a channel's subscribers or a bot's monthly users, when known.
    private static func similarSubtitle(_ chat: CustomChat) -> String? {
        if let bot = chat.bot {
            guard bot.activeUserCount > 0 else { return nil }
            return L10n.telegramPlural("SharedMedia.SimilarBot.Users", count: bot.activeUserCount)
        }
        let count = chat.supergroup?.memberCount ?? 0
        guard count > 0 else { return nil }
        return L10n.telegramPlural("SharedMedia.SimilarChannel.Subscribers", count: count)
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
        guard canRestoreClient(source), let state = restorationState() else { return nil }
        let host = restorationHost(state: state, source: source)
        guard host != nil || opensChatItself else { return nil }
        guard let preparedMetadata, preparedMetadata.0 == source else {
            prepareClientMetadata(source)
            return nil
        }
        let makeReplacement = { [weak host] () -> PeerProfileViewController? in
            if let host { return host.makeProfile(customChat: preparedMetadata.1, restoration: state) }
            let client = TDLib.shared.activeClient
            guard client.id == source.clientID else { return nil }
            let replacement = PeerProfileViewController(
                customChat: preparedMetadata.1, topic: self.topic, client: client, accountID: source.accountID,
                restoration: state,
            )
            replacement.configureOpensChatItself()
            return replacement
        }
        let hostIdentity = host.map(ObjectIdentifier.init)
        return PreparedClientNavigationReplacement(
            preflight: { [weak self] in
                guard let self else { return false }
                return canRestoreClient(source)
                    && restorationHost(state: state, source: source).map(ObjectIdentifier.init) == hostIdentity
            },
            commit: { [self] in
                guard canRestoreClient(source),
                      restorationHost(state: state, source: source).map(ObjectIdentifier.init) == hostIdentity,
                      let replacement = makeReplacement()
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
                cancelSharedItemDownload(cancelInTDLib: false)
                historyRequest.invalidate()
                historyTask?.cancel()
                sharedTabCountTask?.cancel()
                groupsInCommonTask?.cancel()
                similarCountTask?.cancel()
                similarTask?.cancel()
                infoTask?.cancel()
                permissionTask?.cancel()
                chatMetadataTask?.cancel()
                avatarHistoryTask?.cancel()
                avatarReconciliationTask?.cancel()
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

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if currentSharedTab == .members {
            collectionView.deselectItem(at: indexPath, animated: true)
            guard contextIsCurrent, let id = dataSource.itemIdentifier(for: indexPath) else { return }
            membersPane?.open(id)
            return
        }
        if currentSharedTab.isSimilar {
            // PeerInfoRecommendedPeersPane opens the channel or the bot (`openPeer`).
            guard contextIsCurrent, let id = dataSource.itemIdentifier(for: indexPath), let chat = similarByID[id]
            else { return }
            NavigationStorage.shared.push(.customChat(chat))
            return
        }
        if currentSharedTab == .groupsInCommon {
            // Telegram's Groups pane opens the group (`PeerInfoGroupsInCommonPaneNode`).
            guard contextIsCurrent, let id = dataSource.itemIdentifier(for: indexPath), let chat = groupsByID[id]
            else { return }
            NavigationStorage.shared.push(.customChat(chat))
            return
        }
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let message = messagesByID[id]
        else { return }
        let performed = sharedMessageRefresh?.perform(id: id) {
            if currentSharedTab == .media, SharedMediaGridPreview.opensGallery(message) {
                openMediaGallery(selectedMessage: message)
            } else if !currentSharedTab.isGrid, openSharedItem(message) {
                // Telegram opens a file, plays a track or voice message and opens a link from the list
                // (`PeerInfoScreenOpenMessage`).
            } else {
                // Rich and paid media messages share the photo and video index, and the gallery plays only photo and
                // video messages: these, GIFs and video messages open where they were sent.
                onOpenMessage?(message.id)
            }
        }
        if performed != true { sharedMessageRefresh?.retry() }
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? SharedMediaGridCell)?.resumeLoading()
        let itemCount =
            switch currentSharedTab {
            case .groupsInCommon: groupsInCommon.count
            case .members: membersPane?.items.count ?? 0
            case .similarBots,
                 .similarChannels: similarChats.count
            case .audio,
                 .files,
                 .gifs,
                 .links,
                 .media,
                 .voice: messagesByID.count
            }
        guard historyError == nil, indexPath.item >= max(0, itemCount - 6) else { return }
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

    /// Sets the callbacks a hosting chat would set, for a profile opened away from its own chat.
    func configureOpensChatItself() {
        opensChatItself = true
        onOpenMessage = { [weak self] messageID in self?.openChat(targetMessageID: messageID) }
        onSearch = { [weak self] in self?.openChatSearch() }
    }

    /// Opens a Files, Audio or Links row's content; false when it has none and the message opens in the chat.
    private func openSharedItem(_ message: Message) -> Bool {
        switch message.content {
        case .messageDocument(let value):
            openSharedFile(value.document.document, of: message, isAudio: false, duration: 0)
            return true
        case .messageAudio(let value):
            openSharedFile(value.audio.audio, of: message, isAudio: true, duration: value.audio.duration)
            return true
        case .messageVoiceNote(let value):
            openSharedFile(value.voiceNote.voice, of: message, isAudio: true, duration: value.voiceNote.duration)
            return true
        case .messageVideoNote(let value):
            // A self-destructing round video plays only in its chat.
            guard !value.isSecret else { return false }
            openSharedFile(value.videoNote.video, of: message, isAudio: true, duration: value.videoNote.duration)
            return true
        default:
            guard let link = SharedLink(message: message) else { return false }
            open(link)
            return true
        }
    }

    private func openSharedFile(_ file: File, of message: Message, isAudio: Bool, duration: Int) {
        guard contextIsCurrent else { return }
        if file.local.isDownloadingCompleted, !file.local.path.isEmpty,
           FileManager.default.fileExists(atPath: file.local.path)
        {
            finishOpening(path: file.local.path, of: message, isAudio: isAudio, duration: duration)
            return
        }
        // A second tap on a downloading row cancels it, as the chat's file view does.
        if let download = sharedItemDownload, download.messageID == message.id {
            cancelSharedItemDownload(cancelInTDLib: true)
            return
        }
        cancelSharedItemDownload(cancelInTDLib: true)
        let client = client
        let fileID = file.id
        let messageID = message.id
        setSharedItemProgress(0, for: messageID)
        let updates = TDImageLoadingView.fileUpdates(source: restorationIdentity.origin, fileID: fileID)
            .sink { [weak self] file in
                guard let self, sharedItemDownload?.fileID == fileID, file.expectedSize > 0 else { return }
                setSharedItemProgress(Float(file.local.downloadedSize) / Float(file.expectedSize), for: messageID)
            }
        let task = Task { [weak self] in
            let downloaded = try? await client.downloadFile(
                fileId: fileID, limit: 0, offset: 0, priority: 32, synchronous: true,
            )
            guard let self, !Task.isCancelled, sharedItemDownload?.messageID == messageID else { return }
            cancelSharedItemDownload(cancelInTDLib: false)
            guard let downloaded, downloaded.local.isDownloadingCompleted, contextIsCurrent,
                  navigationController?.topViewController === self, presentedViewController == nil else { return }
            finishOpening(path: downloaded.local.path, of: message, isAudio: isAudio, duration: duration)
        }
        sharedItemDownload = (messageID, fileID, task, updates)
    }

    private func finishOpening(path: String, of message: Message, isAudio: Bool, duration: Int) {
        if case .messageVideoNote(let value) = message.content {
            playSharedVideoNote(path: path, of: message, content: value)
            return
        }
        if isAudio {
            playSharedAudio(path: path, of: message, duration: duration)
            return
        }
        // The chat opens a document the same way (`MessageContentAction.openDocument`).
        let activity = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1,
        )
        present(activity, animated: true)
    }

    /// PeerInfoScreen plays a track or a voice message in its chat's playlist (openChatMessage's `.messages`
    /// location with the music or voice tag): a track names its title and performer and plays on through the chat's
    /// tracks, with the lock screen's previous and next; a voice message names its sender over "Voice Message" or the
    /// group, and an incoming one is marked listened as PeerMessagesMediaPlaylist's onItemPlaybackStarted does.
    private func playSharedAudio(path: String, of message: Message, duration: Int) {
        let isMusic =
            if case .messageAudio = message.content {
                true
            } else {
                false
            }
        let item = Media.NowPlaying(
            accountID: accountID,
            chatID: message.chatId,
            messageID: message.id,
            isMusic: isMusic,
        )
        let startsItem = Media.shared.nowPlaying != item
        Media.shared.toggle(with: path, duration: duration, item: item)
        switch message.content {
        case .messageAudio(let value):
            Media.shared.setDisplay(.music(value.audio, item: item))
        case .messageVoiceNote(let value):
            let client = client
            let subtitle = voicePlaybackSubtitle()
            let fallbackTitle = customChat.displayTitle
            Task {
                let title = await Self.voiceSenderTitle(of: message, client: client) ?? fallbackTitle
                Media.shared.setDisplay(Media.NowPlayingDisplay(item: item, title: title, subtitle: subtitle))
                guard startsItem, !message.isOutgoing, !value.isListened else { return }
                _ = try? await client.openMessageContent(chatId: message.chatId, messageId: message.id)
            }
        default:
            break
        }
    }

    /// PeerInfoScreen plays a round video through the voice playlist (openChatMessage's .voiceOrInstantVideo tag);
    /// with no bubble on screen it shows in the floating circle (OverlayInstantVideoNode), and an incoming one is
    /// marked viewed as PeerMessagesMediaPlaylist's onItemPlaybackStarted does. A second tap pauses or resumes it.
    private func playSharedVideoNote(path: String, of message: Message, content: MessageVideoNote) {
        guard contextIsCurrent,
              let backend = VideoNotePlaybackBackend.captured(client: client, context: mediaPlaybackContext)
        else { return }
        let item = VideoNotePlaybackView.PlaylistItem(
            source: backend.source, chatID: message.chatId, messageID: message.id,
        )
        let player = FloatingVideoNotePlayer.shared
        if player.holds(item) {
            player.togglePlayback()
            return
        }
        let videoNote = content.videoNote
        let thumbnail = videoNote.thumbnail.flatMap { thumbnail in
            thumbnail.file.local.isDownloadingCompleted ? UIImage(contentsOfFile: thumbnail.file.local.path) : nil
        } ?? videoNote.minithumbnail.flatMap { UIImage(data: $0.data) }
        backend.takePlayback()
        player.adopt(.init(
            item: item,
            url: URL(filePath: path),
            time: 0,
            duration: Double(videoNote.duration),
            thumbnail: thumbnail,
            backend: backend,
        ))
        guard !message.isOutgoing, !content.isViewed else { return }
        let client = client
        Task { _ = try? await client.openMessageContent(chatId: message.chatId, messageId: message.id) }
    }

    /// "Voice Message" in private chats and channels; a group's title in groups, as the chat's playback header has it.
    private func voicePlaybackSubtitle() -> String {
        switch customChat.chat.type {
        case .chatTypeBasicGroup:
            customChat.displayTitle
        case .chatTypeSupergroup(let supergroup) where !supergroup.isChannel:
            customChat.displayTitle
        default:
            L10n.telegram("MusicPlayer.VoiceNote")
        }
    }

    private func cancelSharedItemDownload(cancelInTDLib: Bool) {
        guard let download = sharedItemDownload else { return }
        sharedItemDownload = nil
        download.task.cancel()
        download.updates?.cancel()
        setSharedItemProgress(nil, for: download.messageID)
        guard cancelInTDLib else { return }
        let client = client
        Task { _ = try? await client.cancelDownloadFile(fileId: download.fileID, onlyIfPending: false) }
    }

    /// Redraws one row once a sender it names is known.
    private func reconfigureSharedItem(_ id: Int64) {
        guard isViewLoaded else { return }
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(id) else { return }
        snapshot.reconfigureItems([id])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func setSharedItemProgress(_ progress: Float?, for messageID: Int64) {
        sharedItemProgress[messageID] = progress
        guard isViewLoaded, let path = dataSource.indexPath(for: messageID) else { return }
        let cell = collectionView.cellForItem(at: path)
        (cell as? SharedMediaRowCell)?.setDownloadProgress(progress)
        (cell as? SharedFileRowCell)?.setDownloadProgress(progress)
        (cell as? SharedAudioRowCell)?.setDownloadProgress(progress)
    }

    private func open(_ link: SharedLink) {
        guard contextIsCurrent else { return }
        // A link hidden behind other text asks first, as Telegram's concealed links do.
        guard link.isConcealed else {
            TelegramLinkRouter.shared.open(link.url, from: self)
            return
        }
        let alert = UIAlertController(
            title: L10n.telegram("OpenLinkConfirmation.Title"), message: link.url.absoluteString,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert
            .addAction(UIAlertAction(
                title: L10n.telegram("OpenLinkConfirmation.Open"),
                style: .default,
            ) { [weak self] _ in
                TelegramLinkRouter.shared.open(link.url, from: self)
            })
        present(alert, animated: true)
    }

    /// Telegram's list items keep View in Chat in their context menu.
    @objc private func sharedRowLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if currentSharedTab == .members {
            // PeerInfoScreenNode.openMemberContextMenu.
            guard gesture.state == .began, contextIsCurrent,
                  let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
                  let id = dataSource.itemIdentifier(for: path),
                  let actions = membersPane?.menuActions(for: id), !actions.isEmpty,
                  let cell = collectionView.cellForItem(at: path) else { return }
            presentTelegramContextMenu(sourceView: cell, actions: actions)
            return
        }
        guard gesture.state == .began, currentSharedTab != .media, contextIsCurrent,
              let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
              let id = dataSource.itemIdentifier(for: path), messagesByID[id] != nil,
              sharedMessageRefresh?.allows(id) == true,
              let cell = collectionView.cellForItem(at: path) else { return }
        presentTelegramContextMenu(sourceView: cell, actions: [
            TelegramContextMenuAction(
                title: L10n.telegram("SharedMedia.ViewInChat"),
                image: UIImage(systemName: "bubble.left"),
            ) { [weak self] in
                guard let self, contextIsCurrent, sharedMessageRefresh?.allows(id) == true else { return }
                onOpenMessage?(id)
            },
        ])
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
        avatarView.showsContextMenu = false
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
        avatarView.addGestureRecognizer(avatarTapGesture)
        headerStack.addArrangedSubview(avatarView)
        storyRingView.translatesAutoresizingMaskIntoConstraints = false
        profileHeaderView.addSubview(storyRingView)
        updateStoryRing()

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        applyProfileTitle()
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
        headerStack.addArrangedSubview(openAppButton)
        headerStack.setCustomSpacing(12, after: openAppButton)

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
        actionStack.addArrangedSubview(moreActionButton)
        updateActionAvailability()

        if let tab = restoration?.tab { selectedSharedTab = tab }
        sharedTabs.translatesAutoresizingMaskIntoConstraints = false
        // Until the counts arrive only a restored pane shows, as Telegram shows no panes before it knows them.
        sharedTabs.configure(
            items: restoration == nil ? [] : [.init(id: selectedSharedTab.rawValue, title: selectedSharedTab.title)],
            selectedID: selectedSharedTab.rawValue,
        )
        sharedTabs.alpha = restoration == nil ? 0 : 1
        sharedTabsHeightConstraint = sharedTabs.heightAnchor.constraint(equalToConstant: 58)
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
            storyRingView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            storyRingView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            storyRingView.widthAnchor.constraint(equalTo: avatarView.widthAnchor),
            storyRingView.heightAnchor.constraint(equalTo: avatarView.heightAnchor),
            openAppButton.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
            openAppButton.heightAnchor.constraint(equalToConstant: 52),
            actionStack.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
            actionStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            sharedTabs.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            sharedTabs.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor),
            sharedTabs.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor),
            sharedTabsHeightConstraint,
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
        collectionView.addGestureRecognizer(UILongPressGestureRecognizer(
            target: self, action: #selector(sharedRowLongPressed(_:)),
        ))
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(
            SharedMediaGridCell.self,
            forCellWithReuseIdentifier: SharedMediaGridCell.reuseIdentifier,
        )
        collectionView.register(SharedMediaRowCell.self, forCellWithReuseIdentifier: SharedMediaRowCell.reuseIdentifier)
        collectionView.register(SharedLinkRowCell.self, forCellWithReuseIdentifier: SharedLinkRowCell.reuseIdentifier)
        collectionView.register(SharedFileRowCell.self, forCellWithReuseIdentifier: SharedFileRowCell.reuseIdentifier)
        collectionView.register(SharedAudioRowCell.self, forCellWithReuseIdentifier: SharedAudioRowCell.reuseIdentifier)
        collectionView.register(
            SharedMediaPendingCell.self,
            forCellWithReuseIdentifier: SharedMediaPendingCell.reuseIdentifier,
        )
        collectionView.register(
            SharedGroupRowCell.self,
            forCellWithReuseIdentifier: SharedGroupRowCell.reuseIdentifier,
        )
        collectionView.register(
            SharedMemberRowCell.self,
            forCellWithReuseIdentifier: SharedMemberRowCell.reuseIdentifier,
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
            guard self?.currentSharedTab.isGrid == true else {
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
            guard let self else { return UICollectionViewCell() }
            if currentSharedTab == .members {
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SharedMemberRowCell.reuseIdentifier, for: indexPath,
                ) as? SharedMemberRowCell
                if id == PeerProfileMembersPane.addMemberItem {
                    cell?.configureAddMember()
                } else if let row = membersPane?.row(for: id) {
                    cell?.configure(row: row, accountID: accountID, client: client)
                }
                return cell ?? UICollectionViewCell()
            }
            if currentSharedTab.isSimilar {
                guard let chat = similarByID[id],
                      let cell = collectionView.dequeueReusableCell(
                          withReuseIdentifier: SharedGroupRowCell.reuseIdentifier, for: indexPath,
                      ) as? SharedGroupRowCell
                else { return UICollectionViewCell() }
                cell.configure(chat: chat, subtitle: Self.similarSubtitle(chat), accountID: accountID, client: client)
                return cell
            }
            if currentSharedTab == .groupsInCommon {
                guard let chat = groupsByID[id],
                      let cell = collectionView.dequeueReusableCell(
                          withReuseIdentifier: SharedGroupRowCell.reuseIdentifier, for: indexPath,
                      ) as? SharedGroupRowCell
                else { return UICollectionViewCell() }
                cell.configure(chat: chat, subtitle: Self.groupSubtitle(chat), accountID: accountID, client: client)
                return cell
            }
            guard let message = messagesByID[id] else { return UICollectionViewCell() }
            guard sharedMessageRefresh?.allows(id) == true else {
                let state = sharedMessageRefresh?.state(for: id) ?? .loading
                if !currentSharedTab.isGrid {
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
            if currentSharedTab.isGrid {
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
            if currentSharedTab == .audio || currentSharedTab == .voice,
               let cell = collectionView.dequeueReusableCell(
                   withReuseIdentifier: SharedAudioRowCell.reuseIdentifier,
                   for: indexPath,
               ) as? SharedAudioRowCell,
               cell.configure(message: message, isGlobalSearch: false, client: client, onNameResolved: { [weak self] in
                   self?.reconfigureSharedItem(id)
               })
            {
                cell.setDownloadProgress(sharedItemProgress[message.id])
                return cell
            }
            if currentSharedTab == .files, case .messageDocument = message.content,
               let cell = collectionView.dequeueReusableCell(
                   withReuseIdentifier: SharedFileRowCell.reuseIdentifier,
                   for: indexPath,
               ) as? SharedFileRowCell
            {
                cell.configure(message: message, isGlobalSearch: false, client: client)
                cell.setDownloadProgress(sharedItemProgress[message.id])
                return cell
            }
            if currentSharedTab == .links,
               let snippet = SharedLinkSnippet(message: message, includesDescription: true),
               let cell = collectionView.dequeueReusableCell(
                   withReuseIdentifier: SharedLinkRowCell.reuseIdentifier,
                   for: indexPath,
               ) as? SharedLinkRowCell
            {
                cell.configure(message: message, snippet: snippet, author: nil, client: client)
                return cell
            }
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SharedMediaRowCell.reuseIdentifier,
                for: indexPath,
            ) as? SharedMediaRowCell
            cell?.configure(message: message)
            cell?.setDownloadProgress(sharedItemProgress[message.id])
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
            case .messagePhoto,
                 .messageVideo:
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
            let messages = sortedSharedMessages
            restoredGallery.updateMessages(
                messages,
                pendingRevisionIDs: Set(messages.lazy
                    .filter { self.sharedMessageRefresh?.allows($0.id) != true }
                    .map(\.id)),
            )
            restoredGallery.updateTotalMessageCount(sharedTotalMessageCount)
        }
        gallery.onSelectedMessageChanged = { [weak self] messageID in
            // Telegram scrolls the pane to the gallery's item, so closing flies back into a visible cell.
            guard let self, isViewLoaded, currentSharedTab == originatingTab,
                  let path = dataSource.indexPath(for: messageID),
                  let frame = collectionView.layoutAttributesForItem(at: path)?.frame else { return }
            let visible = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            guard !visible.contains(frame) else { return }
            collectionView.scrollToItem(at: path, at: .centeredVertically, animated: false)
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
                // The pane counts and the Groups pane read once this client is ready.
                if !sharedTabCountsLoaded, sharedTabCountTask == nil { loadSharedTabAvailability() }
                resumeSharedHistoryIfNeeded()
            } else {
                sharedMessageRefresh?.stop()
                sharedMessageRefresh = nil
                historyTask?.cancel()
                historyTask = nil
                sharedTabCountTask?.cancel()
                sharedTabCountTask = nil
                groupsInCommonGeneration &+= 1
                groupsInCommonTask?.cancel()
                groupsInCommonTask = nil
                similarGeneration &+= 1
                similarTask?.cancel()
                similarTask = nil
                membersPane?.suspend()
                if source.map({ $0.accountID != accountID }) ?? false || !keepsGalleryThroughClientRenewal {
                    revokeSharedMessages(Set(messagesByID.keys), closesGallery: true)
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
        onlineMemberCount = TelegramChatListStore.shared.onlineMemberCount(chatID: customChat.id, clientID: client.id)
        TelegramChatListStore.shared
            .onlineMemberCountChanges
            .filter { [chatID = customChat.id] in $0 == chatID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chatID in
                guard let self, contextIsCurrent else { return }
                onlineMemberCount = TelegramChatListStore.shared.onlineMemberCount(chatID: chatID, clientID: client.id)
                scheduleMetadataRender()
            }
            .store(in: &cancellables)
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
        nc.scopedPublisher(&cancellables, for: .updateNewMessage) { [weak self] event in
            self?.receiveNewSharedMessage(event.value.message, source: event.source)
        }
        nc.scopedPublisher(&cancellables, for: .updateMessageSendSucceeded) { [weak self] event in
            self?.receiveNewSharedMessage(event.value.message, source: event.source)
        }
    }

    private func receiveNewSharedMessage(_ message: Message, source: TdUpdateSource) {
        guard contextIsCurrent, message.chatId == customChat.id, messagesByID[message.id] == nil,
              let sharedMessageRefresh else { return }
        sharedMessageRefresh.receiveNew(message, source: source)
        if messagesByID[message.id] != nil, let total = sharedTotalMessageCount {
            sharedTotalMessageCount = total + 1
        }
    }

    private func handleAccountChange() {
        guard !contextIsCurrent, !editorRetention.shouldRetain(
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
        if keepsGalleryThroughClientRenewal { return }
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
        // A bot's status is its users, not a presence.
        guard contextIsCurrent, update.userId == customChat.user?.id, customChat.bot == nil else { return }
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
        currentStatusText = isSelfProfile ? "" : Self.statusText(for: customChat)
        currentStatusIsOnline = !isSelfProfile && customChat.bot == nil && Self.isOnline(update.user.status)
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
        membersInfoLoaded = true
        updateSharedTabAvailability()
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
        currentSupergroupMemberCount = update.supergroupFullInfo.memberCount
        membersInfoLoaded = true
        updateSharedTabAvailability()
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
        case .chatTypeBasicGroup,
             .chatTypeSupergroup: break
        case .chatTypePrivate,
             .chatTypeSecret: return
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
        if !isSelfProfile, groupsInCommonCount != info.groupInCommonCount {
            groupsInCommonCount = info.groupInCommonCount
            updateSharedTabAvailability()
        }
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
        avatarHistoryTask?.cancel()
        avatarReconciliationTask?.cancel()
        avatarHistoryTask = nil
        avatarHistoryRequestID = nil
        avatarReconciliationTask = nil
        avatarReconciliationRequestID = nil
        if avatarGalleryClient != nil {
            reconcileActiveAvatarGallery()
            return
        }
        adoptAvatarHistory(nil)
    }

    /// Telegram (AvatarGalleryController, reconcileItems) replaces the open gallery's list once the full one arrives
    /// and keeps showing the same photo when it is still listed.
    private func reconcileActiveAvatarGallery() {
        guard let activeAvatarGallery, let client = avatarGalleryClient else { return }
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
                let payload = try await loadAvatarGalleryPayload(client: client)
                guard !Task.isCancelled,
                      avatarGalleryClient?.id == client.id,
                      avatarMetadataGeneration == generation,
                      avatarReconciliationRequestID == requestID,
                      self.activeAvatarGallery === activeAvatarGallery
                else { return }
                adoptAvatarHistory(payload)
                avatarGalleryListLoaded = true
                if payload.items.isEmpty {
                    activeAvatarGallery.onRequestMoreItems = nil
                    activeAvatarGallery.reconcileItems([], totalCount: 0)
                    self.activeAvatarGallery = nil
                    return
                }
                activeAvatarGallery.onRequestMoreItems = payload.hasHistory
                    ? { [weak self] in self?.loadMoreAvatarHistory() }
                    : nil
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
    }

    private func adoptAvatarHistory(_ payload: AvatarGalleryPayload?) {
        avatarHistoryRawOffset = payload?.historyRawOffset ?? 0
        avatarHistoryTotalCount = payload?.historyTotalCount ?? 0
        avatarHistoryExtraPhotoCount = payload?.extraPhotoCount ?? 0
        avatarHistoryKnownPhotoIDs = Set(payload?.items.map(\.id) ?? [])
        avatarHistoryTrailingPhotoID = payload?.trailingPhotoID
        avatarHistoryUserID = payload?.userID
        avatarHistoryChatID = payload?.chatID
        avatarHistoryNextMessageID = payload?.nextMessageID ?? 0
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
        applyProfileTitle()
        statusLabel.text = displayedStatusText
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
        avatarView.accessibilityLabel = L10n.betterTG("Accessibility.ProfilePhotoOf", profileTitle())
        updateStoryRing()
        updateActionAvailability()
        view.setNeedsLayout()
    }

    private func updateStoryRing() {
        let style = storyRingStyle
        storyRingView.style = style
        let scale = StoryAvatarRingView.avatarScale(diameter: 96, lineWidth: 3)
        avatarView.transform = style == nil ? .identity : CGAffineTransform(scaleX: scale, y: scale)
        avatarTapGesture.isEnabled = avatarGalleryIsAvailable || style != nil
        avatarView.accessibilityHint =
            if style != nil {
                L10n.betterTG("Accessibility.OpenStoriesHint")
            } else if avatarGalleryIsAvailable {
                L10n.betterTG("Accessibility.OpenProfilePhotosHint")
            } else {
                nil
            }
        avatarView.accessibilityTraits = avatarTapGesture.isEnabled ? [.button, .image] : .image
    }

    private func openStories() -> Bool {
        guard storyRingStyle != nil, contextIsCurrent, presentedViewController == nil else { return false }
        StoryViewerController.present(
            .activeStories(chatIDs: [customChat.id], initialChatID: customChat.id),
            client: client,
            from: self,
            sourceView: avatarView,
            sourceIsAvatar: true,
        )
        return true
    }

    private func updateActionAvailability() {
        messageActionButton.isHidden = isSelfProfile
        let verification = customChat.user?.verificationStatus
        openAppButton.isHidden = isSelfProfile || customChat.bot?.hasMainWebApp != true
            || verification?.isFake == true || verification?.isScam == true
        #if DEBUG
            if Self.probeShowsOpenApp, !isSelfProfile { openAppButton.isHidden = false }
        #endif
        // Telegram's Mute and More act on the whole chat; a topic's profile and Saved Messages have their own.
        moreActionButton.isHidden = isSelfProfile || topic != nil
        membersActionButton.isHidden =
            switch customChat.type {
            case .group:
                false
            case .supergroup:
                !currentSupergroupCanGetMembers
            case .bot,
                 .user:
                true
            }
        // Telegram lists a group's or channel's administrators only to its owner and admins (`PeerInfoProfileItems`:
        // `channel.adminRights != nil || isCreator`).
        let memberStatus: ChatMemberStatus? =
            switch customChat.type {
            case .group(let group): group.status
            case .supergroup(let group): group.status
            case .bot,
                 .user: nil
            }
        administratorsActionButton.isHidden =
            switch memberStatus {
            case .chatMemberStatusAdministrator?: false
            case .chatMemberStatusCreator(let creator)?: !creator.isMember
            default: true
            }
        let canEdit =
            if let user = customChat.user {
                user.id == accountUserID
            } else {
                // Telegram's edit mode is the owner's and the admins' (PeerInfoScreen `canEditPeerInfo` and the
                // management items); the name fields need Change Info.
                infoPermission.canChangeInfo || isChatAdministrator
            }
        navigationItem.rightBarButtonItem = canEdit
            ? UIBarButtonItem(
                title: L10n.telegram("Common.Edit"), style: .plain, target: self, action: #selector(editPressed),
            )
            : nil
    }

    private func configureSharedMessageRefresh() {
        sharedMessageRefresh?.stop()
        sharedMessageRefresh = nil
        // Groups lists chats, which no message refresh covers.
        guard let filter = currentSharedTab.filter else { return }
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
                    chatId: chatID, filter: filter, fromMessageId: messageID, limit: 2, offset: -1, query: "",
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
        if currentSharedTab == .members {
            if membersPane?.rows.isEmpty != false, historyError == nil { loadMore() }
            return
        }
        if currentSharedTab == .groupsInCommon {
            if groupsInCommon.isEmpty, historyError == nil { loadMore() }
            return
        }
        if currentSharedTab.isSimilar {
            if !similarLoaded, historyError == nil { loadMore() }
            return
        }
        sharedMessageRefresh?.resume(
            needsPage: messagesByID.isEmpty || historyRequest.needsResume,
            hasError: historyError != nil,
            loadPage: { loadMore() },
        )
    }

    /// `closesGallery` ends the open gallery and Picture in Picture of this context. Otherwise (an edit or an
    /// unconfirmed delete the refresh re-reads) only the affected items are covered until their revision is admitted:
    /// the gallery keeps their pages, and Picture in Picture closes only when it shows one of them.
    private func revokeSharedMessages(_ ids: Set<Int64>, closesGallery: Bool = false) {
        guard !ids.isEmpty else { return }
        mediaRevealSession?.revoke(messageIDs: ids)
        // Revoked permits cannot escape through retained PiP or a transition snapshot.
        if let mediaPlaybackContext {
            GalleryPictureInPictureCoordinator.shared.contextWasRevoked(
                mediaPlaybackContext, messageIDs: closesGallery ? nil : ids, revokeContext: false,
            )
        }
        if closesGallery, let gallery = activeMediaGallery {
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
                case .bot(let user),
                     .user(let user):
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
                    membersInfoLoaded = true
                    updateSharedTabAvailability()
                    applyFullInfo(bio: info.description, details: [], status: nil, photo: info.photo)
                case .supergroup(let group):
                    let info = try await client.getSupergroupFullInfo(supergroupId: group.id)
                    guard !Task.isCancelled,
                          contextIsCurrent,
                          fullInfoGeneration == generation
                    else { return }
                    currentSupergroupCanGetMembers = info.canGetMembers
                    currentSupergroupMemberCount = info.memberCount
                    membersInfoLoaded = true
                    updateSharedTabAvailability()
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
                // Without the user's full info the common groups are unknown, and the other panes go on without them.
                if groupsInCommonCount == nil {
                    groupsInCommonCount = 0
                    updateSharedTabAvailability()
                }
                if !membersInfoLoaded {
                    membersInfoLoaded = true
                    updateSharedTabAvailability()
                }
            }
        }
    }

    private func loadMore() {
        // Before the counts arrive only a restored pane reads; afterwards only a pane with content does.
        guard availableSharedTabs?.contains(currentSharedTab) ?? (restoration != nil) else { return }
        guard let filter = currentSharedTab.filter else {
            if currentSharedTab == .members {
                guard restoredViewport == nil, contextIsCurrent, let membersPane else { return }
                historyError = nil
                membersPane.loadMore()
                if membersPane.rows.isEmpty { applySnapshot() }
            } else if currentSharedTab.isSimilar {
                loadSimilar()
            } else {
                loadMoreGroupsInCommon()
            }
            return
        }
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
                    filter: filter,
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
        if currentSharedTab == .members {
            applyMembersSnapshot(animated: animated, completion: completion)
            return
        }
        if currentSharedTab == .groupsInCommon {
            applyGroupsSnapshot(animated: animated, completion: completion)
            return
        }
        if currentSharedTab.isSimilar {
            applySimilarSnapshot(animated: animated, completion: completion)
            return
        }
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
        let changedKinds = currentSharedTab.isGrid
            ? existing.filter { sharedCellReadiness[$0] != readiness[$0] }
            : []
        let signatures = Dictionary(uniqueKeysWithValues: messages.map { message in
            (message.id, SharedCellSignature(message: message, ready: readiness[message.id] == true))
        })
        snapshot.reloadItems(changedKinds)
        snapshot.reconfigureItems(existing.filter { id in
            !changedKinds.contains(id) && sharedCellSignatures[id] != signatures[id]
        })
        sharedCellReadiness = readiness
        sharedCellSignatures = signatures
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
            // Items the refresh re-reads keep their gallery pages, covered, until their revision is admitted.
            activeMediaGallery?.updateMessages(
                messages,
                pendingRevisionIDs: Set(messages.lazy.filter { readiness[$0.id] != true }.map(\.id)),
            )
            activeMediaGallery?.updateTotalMessageCount(sharedTotalMessageCount)
        }
        updateEmptyBackground(isEmpty: messages.isEmpty, isLoading: historyTask != nil)
    }

    /// The pane's empty, loading or retry text. A profile without any pane shows nothing, as Telegram does.
    private func updateEmptyBackground(isEmpty: Bool, isLoading: Bool) {
        guard isEmpty, availableSharedTabs?.isEmpty != true else {
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
            label.text = isLoading || availableSharedTabs == nil
                ? L10n.betterTG("Profile.Loading")
                : currentSharedTab.emptyText
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            collectionView.backgroundView = label
        }
    }

    private func initialStatus() -> String {
        displayedStatusText
    }

    /// PeerInfoHeaderNode's title with the credibility icon after it; a topic's profile is titled by the topic.
    private func applyProfileTitle() {
        let badge = topic == nil ? PeerCredibilityBadge(chat: customChat) : nil
        guard let badge else {
            titleLabel.text = profileTitle()
            return
        }
        titleLabel.attributedText = PeerCredibilityBadge.title(
            profileTitle(),
            badge: badge,
            font: titleLabel.font,
            color: .label,
        )
        titleLabel.accessibilityLabel = "\(profileTitle()), \(badge.accessibilityLabel)"
    }

    private func profileTitle() -> String {
        isSelfProfile ? L10n.telegram("Conversation.SavedMessages") : currentChatTitle
    }

    /// Telegram (avatarGalleryFallbackItem) opens the current photo at once and reconciles the list when it arrives.
    @objc private func avatarPressed() {
        if openStories() { return }
        guard avatarGalleryIsAvailable,
              activeAvatarGallery == nil,
              contextIsCurrent,
              presentedViewController == nil,
              let fallback = avatarGalleryFallbackItem
        else { return }
        avatarHistoryTask?.cancel()
        avatarReconciliationTask?.cancel()
        avatarHistoryTask = nil
        avatarHistoryRequestID = nil
        avatarReconciliationTask = nil
        avatarReconciliationRequestID = nil
        adoptAvatarHistory(nil)
        avatarHistoryKnownPhotoIDs = [fallback.id]
        avatarGalleryListLoaded = false
        let gallery = ProfileAvatarGalleryViewController(
            accountID: accountID,
            client: client,
            items: [fallback],
            selection: fallback.id,
            totalCount: 1,
            transitionSource: avatarTransitionTarget(item: fallback),
            transitionSourceProvider: { [weak self] item in
                self?.avatarTransitionTarget(item: item)
            },
        )
        gallery.contextIsCurrent = { [weak self] in
            // A same-account client renewal keeps the gallery: it moves its photos to the renewed client, and this
            // profile is replaced once the gallery closes.
            guard let self else { return false }
            return TDLib.shared.activeAccountID == accountID && !clientOwnerRetired && !restorationIdentity.revoked
        }
        // Telegram hides Share and Save for protected content and lets the account manage its own photos.
        gallery.allowsSaving = !customChat.chat.hasProtectedContent
        gallery.managesOwnPhotos = isSelfProfile
        gallery.onPhotosChanged = { [weak self] in
            self?.resetAvatarGalleryForMetadataChange()
        }
        gallery.onClientRenewed = { [weak self] in
            guard let self else { return }
            // A page or the list requested through the previous client is dropped; ask the renewed one.
            avatarHistoryTask?.cancel()
            avatarHistoryTask = nil
            avatarHistoryRequestID = nil
            if !avatarGalleryListLoaded || avatarReconciliationTask != nil {
                reconcileActiveAvatarGallery()
            }
        }
        gallery.onDismissed = { [weak self, weak gallery] in
            guard let self, let gallery, activeAvatarGallery === gallery else { return }
            activeAvatarGallery = nil
            avatarHistoryTask?.cancel()
            avatarReconciliationTask?.cancel()
            avatarHistoryTask = nil
            avatarHistoryRequestID = nil
            avatarReconciliationTask = nil
            avatarReconciliationRequestID = nil
            // A client renewed while the gallery covered this profile replaces the profile now.
            DispatchQueue.main.async { [weak self] in
                guard let self, !contextIsCurrent else { return }
                handleAccountChange()
            }
        }
        activeAvatarGallery = gallery
        present(gallery, animated: true)
        reconcileActiveAvatarGallery()
    }

    private func loadAvatarGalleryPayload(client: TDLibClient) async throws -> AvatarGalleryPayload {
        try await prepareAvatarGalleryClient(client)
        switch customChat.type {
        case .bot(let user),
             .user(let user):
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
            let extraPhotoCount = knownIDs.count(where: { !resultIDs.contains($0) })
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
            return try await chatPhotoPayload(current: info.photo ?? currentProfilePhoto, client: client)
        case .supergroup(let group):
            let info = try await client.getSupergroupFullInfo(supergroupId: group.id)
            return try await chatPhotoPayload(current: info.photo ?? currentProfilePhoto, client: client)
        }
    }

    /// Telegram (RequestUserPhotos) lists a group's or channel's earlier photos from its chat photo messages, after
    /// the current photo.
    private func chatPhotoPayload(current: ChatPhoto?, client: TDLibClient) async throws -> AvatarGalleryPayload {
        let found = try await client.searchChatMessages(
            chatId: customChat.id,
            filter: .searchMessagesFilterChatPhoto,
            fromMessageId: 0,
            limit: 100,
            offset: 0,
            query: "",
            senderId: nil,
            topicId: nil,
        )
        let history = Self.chatPhotoItems(found.messages)
        var items = [ProfileAvatarGalleryItem]()
        if let current {
            items.append(ProfileAvatarGalleryItem(photo: current))
        } else if let fallback = avatarGalleryFallbackItem {
            items.append(fallback)
        }
        var knownIDs = Set(items.map(\.id))
        for item in history where knownIDs.insert(item.id).inserted {
            items.append(item)
        }
        let historyIDs = Set(history.map(\.id))
        let extraPhotoCount = items.count(where: { !historyIDs.contains($0.id) })
        return AvatarGalleryPayload(
            extraPhotoCount: extraPhotoCount,
            historyRawOffset: 0,
            historyTotalCount: found.totalCount,
            items: items,
            totalCount: found.nextFromMessageId == 0
                ? items.count
                : max(items.count, found.totalCount + extraPhotoCount),
            trailingPhotoID: nil,
            userID: nil,
            chatID: customChat.id,
            nextMessageID: found.nextFromMessageId,
        )
    }

    private func loadMoreAvatarHistory() {
        guard avatarHistoryTask == nil,
              avatarReconciliationTask == nil,
              let client = avatarGalleryClient
        else { return }
        if let userID = avatarHistoryUserID {
            loadMoreUserPhotos(userID: userID, client: client)
        } else if let chatID = avatarHistoryChatID, avatarHistoryNextMessageID != 0 {
            loadMoreChatPhotos(chatID: chatID, client: client)
        }
    }

    /// A renewed client knows the chat's photos only once it has loaded the chat.
    private func prepareAvatarGalleryClient(_ client: TDLibClient) async throws {
        guard client.id != self.client.id else { return }
        _ = try await client.getChat(chatId: customChat.id)
    }

    private func loadMoreUserPhotos(userID: Int64, client: TDLibClient) {
        guard avatarHistoryRawOffset < avatarHistoryTotalCount, let activeAvatarGallery else { return }
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
                try await prepareAvatarGalleryClient(client)
                let result = try await client.getUserProfilePhotos(limit: 100, offset: offset, userId: userID)
                guard let activeAvatarGallery, !Task.isCancelled,
                      avatarGalleryClient?.id == client.id,
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
                guard let activeAvatarGallery, !Task.isCancelled,
                      avatarMetadataGeneration == metadataGeneration,
                      avatarHistoryRequestID == requestID,
                      self.activeAvatarGallery === activeAvatarGallery
                else { return }
                activeAvatarGallery.showMoreItemsRetry()
            }
        }
    }

    private func loadMoreChatPhotos(chatID: Int64, client: TDLibClient) {
        guard let activeAvatarGallery else { return }
        let fromMessageID = avatarHistoryNextMessageID
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
                try await prepareAvatarGalleryClient(client)
                let found = try await client.searchChatMessages(
                    chatId: chatID,
                    filter: .searchMessagesFilterChatPhoto,
                    fromMessageId: fromMessageID,
                    limit: 100,
                    offset: 0,
                    query: "",
                    senderId: nil,
                    topicId: nil,
                )
                guard let activeAvatarGallery,
                      !Task.isCancelled,
                      avatarGalleryClient?.id == client.id,
                      avatarMetadataGeneration == metadataGeneration,
                      avatarHistoryRequestID == requestID,
                      avatarHistoryNextMessageID == fromMessageID,
                      self.activeAvatarGallery === activeAvatarGallery
                else { return }
                avatarHistoryNextMessageID = found.nextFromMessageId
                let newItems = Self.chatPhotoItems(found.messages).filter {
                    self.avatarHistoryKnownPhotoIDs.insert($0.id).inserted
                }
                // The last page fixes the count at what the gallery holds.
                activeAvatarGallery.appendItems(
                    newItems,
                    totalCount: found.nextFromMessageId == 0 ? 0 : found.totalCount + avatarHistoryExtraPhotoCount,
                )
            } catch {
                guard let activeAvatarGallery,
                      !Task.isCancelled,
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

    @objc private func tabChanged() {
        cancelSharedItemDownload(cancelInTDLib: true)
        sharedViewportGeneration &+= 1
        restoredViewport = nil
        historyRequest.invalidate()
        historyTask?.cancel()
        historyTask = nil
        sharedMessageRefresh?.stop()
        messagesByID = [:]
        sharedCellSignatures = [:]
        oldestMessageID = nil
        hasMore = true
        historyError = nil
        sharedTotalMessageCount = nil
        groupsInCommonGeneration &+= 1
        groupsInCommonTask?.cancel()
        groupsInCommonTask = nil
        groupsInCommon = []
        groupsByID = [:]
        groupsInCommonOffset = 0
        groupsInCommonHasMore = true
        similarGeneration &+= 1
        similarTask?.cancel()
        similarTask = nil
        similarChats = []
        similarByID = [:]
        similarLoaded = false
        configureSharedMessageRefresh()
        collectionView.collectionViewLayout.invalidateLayout()
        // An empty snapshot comes first: chat IDs and message IDs never share a cell across panes.
        applySnapshot(animated: false)
        loadMore()
    }

    /// PeerInfoData appends Similar Channels or Similar Bots once the recommendations are known.
    private func loadSimilarCount() {
        guard similarCountTask == nil, similarCount == nil, contextIsCurrent else { return }
        let client = client
        let chatID = customChat.id
        let botID = customChat.bot == nil ? nil : customChat.user?.id
        guard listsSimilarChannels || botID != nil else { return }
        similarCountTask = Task { [weak self] in
            let count: TDNativeCount? =
                if let botID {
                    try? await client.send(TDNativeRequests.getBotSimilarBotCount(botUserId: botID, returnLocal: false))
                } else {
                    try? await client.send(TDNativeRequests.getChatSimilarChatCount(chatId: chatID, returnLocal: false))
                }
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            similarCountTask = nil
            similarCount = count?.count ?? 0
            updateSharedTabAvailability()
        }
    }

    /// PeerInfoRecommendedPeersPane: getChatSimilarChats for a channel, getBotSimilarBots for a bot.
    private func loadSimilar() {
        guard restoredViewport == nil, similarTask == nil, !similarLoaded, contextIsCurrent else { return }
        let client = client
        let chatID = customChat.id
        let botID = customChat.bot == nil ? nil : customChat.user?.id
        let generation = similarGeneration
        historyError = nil
        similarTask = Task { [weak self] in
            do {
                var chatIDs = [Int64]()
                if let botID {
                    let bots = try await client.send(TDNativeRequests.getBotSimilarBots(botUserId: botID))
                    for userID in bots.userIds {
                        guard self?.readsSimilar(generation) == true else { return }
                        if let chat = try? await client.createPrivateChat(force: false, userId: userID) {
                            chatIDs.append(chat.id)
                        }
                    }
                } else {
                    chatIDs = try await client.send(TDNativeRequests.getChatSimilarChats(chatId: chatID)).chatIds
                }
                var loaded = [CustomChat]()
                for id in chatIDs {
                    guard self?.readsSimilar(generation) == true else { return }
                    if let chat = await RootVM.shared.getCustomChatForNavigation(from: id, client: client) {
                        loaded.append(chat)
                    }
                }
                guard let self, readsSimilar(generation) else { return }
                similarTask = nil
                similarLoaded = true
                for chat in loaded where similarByID[chat.id] == nil {
                    similarByID[chat.id] = chat
                    similarChats.append(chat.id)
                }
                applySnapshot()
            } catch {
                guard let self, readsSimilar(generation) else { return }
                similarTask = nil
                historyError = currentSharedTab.loadFailedText
                applySnapshot()
            }
        }
        if similarChats.isEmpty { applySnapshot() }
    }

    private func readsSimilar(_ generation: UInt64) -> Bool {
        !Task.isCancelled && similarGeneration == generation && contextIsCurrent && currentSharedTab.isSimilar
    }

    private func applySimilarSnapshot(animated: Bool, completion: (() -> Void)?) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(similarChats)
        dataSource.apply(snapshot, animatingDifferences: animated) { completion?() }
        updateEmptyBackground(isEmpty: similarChats.isEmpty, isLoading: similarTask != nil)
    }

    /// Telegram shows a pane only when it has content (`peerInfoAvailableMediaPanes`). TDLib's local counts answer at
    /// once; a count TDLib does not know locally comes from the server, and its pane shows meanwhile.
    private func loadSharedTabAvailability() {
        loadSimilarCount()
        sharedTabCountTask?.cancel()
        let client = client
        let chatID = customChat.id
        let topic = topic
        let filters = SharedTab.allCases.compactMap { tab in tab.filter.map { (tab, $0) } }
        sharedTabCountTask = Task { [weak self] in
            var counts = [SharedTab: Int]()
            var unknown = [(SharedTab, SearchMessagesFilter)]()
            for (tab, filter) in filters {
                guard !Task.isCancelled else { return }
                let local = try? await client.getChatMessageCount(
                    chatId: chatID, topicId: topic, filter: filter, returnLocal: true,
                )
                if let count = local?.count, count >= 0 {
                    counts[tab] = count
                } else {
                    unknown.append((tab, filter))
                }
            }
            guard self?.applySharedTabCounts(counts) == true else { return }
            for (tab, filter) in unknown {
                let remote = try? await client.getChatMessageCount(
                    chatId: chatID, topicId: topic, filter: filter, returnLocal: false,
                )
                guard let count = remote?.count, count >= 0 else { continue }
                guard self?.applySharedTabCounts([tab: count]) == true else { return }
            }
            if !Task.isCancelled { self?.sharedTabCountTask = nil }
        }
    }

    /// Records counts read by the current client; false once the read is stale.
    private func applySharedTabCounts(_ counts: [SharedTab: Int]) -> Bool {
        guard !Task.isCancelled, contextIsCurrent else { return false }
        sharedTabCounts.merge(counts) { _, new in new }
        sharedTabCountsLoaded = true
        updateSharedTabAvailability()
        return true
    }

    /// Shows the panes with content and keeps the selection on one of them. A user's Groups pane waits for the
    /// common group count from the full info.
    private func updateSharedTabAvailability() {
        guard sharedTabCountsLoaded else { return }
        let listsGroups = customChat.user != nil && !isSelfProfile
        if listsGroups, groupsInCommonCount == nil { return }
        // A group's Members pane comes first, so the panes wait for the member count in its full info.
        if listsMembers, !membersInfoLoaded { return }
        let showsMembers = showsMembersPane
        let tabs = SharedTab.allCases.filter { tab in
            switch tab {
            case .members: showsMembers
            case .groupsInCommon: listsGroups && (groupsInCommonCount ?? 0) > 0
            case .similarChannels: listsSimilarChannels && (similarCount ?? 0) > 0
            case .similarBots: customChat.bot != nil && (similarCount ?? 0) > 0
            case .audio,
                 .files,
                 .gifs,
                 .links,
                 .media,
                 .voice: sharedTabCounts[tab].map { $0 > 0 } ?? true
            }
        }
        if showsMembers { makeMembersPaneIfNeeded() }
        guard tabs != availableSharedTabs else { return }
        let wasResolved = availableSharedTabs != nil
        availableSharedTabs = tabs
        let previousTab = selectedSharedTab
        // Telegram opens on the first pane, Members for a large group.
        if !tabs.contains(selectedSharedTab) || !wasResolved && restoration == nil, let first = tabs.first {
            selectedSharedTab = first
        }
        sharedTabs.configure(
            items: tabs.map { .init(id: $0.rawValue, title: $0.title) },
            selectedID: tabs.isEmpty ? nil : selectedSharedTab.rawValue,
        )
        sharedTabs.alpha = tabs.isEmpty ? 0 : 1
        sharedTabs.isUserInteractionEnabled = !tabs.isEmpty
        sharedTabsHeightConstraint.constant = tabs.isEmpty ? 0 : 58
        view.setNeedsLayout()
        if selectedSharedTab != previousTab || tabs.isEmpty {
            tabChanged()
        } else if !wasResolved {
            // The first counts start the selected pane, or refresh a restored one's empty text.
            if restoration == nil { loadMore() }
            applySnapshot(animated: false)
        }
    }

    /// Telegram's Groups pane (`PeerInfoGroupsInCommonPaneNode`): the groups shared with this user, a page at a time.
    private func loadMoreGroupsInCommon() {
        guard restoredViewport == nil, groupsInCommonTask == nil, groupsInCommonHasMore, contextIsCurrent,
              let userID = customChat.user?.id else { return }
        let client = client
        let offset = groupsInCommonOffset
        let generation = groupsInCommonGeneration
        historyError = nil
        groupsInCommonTask = Task { [weak self] in
            do {
                let page = try await client.getGroupsInCommon(userId: userID, offsetChatId: offset, limit: 50)
                var loaded = [CustomChat]()
                for chatID in page.chatIds {
                    guard self?.readsGroupsInCommon(generation) == true else { return }
                    if let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client) {
                        loaded.append(chat)
                    }
                }
                guard let self, readsGroupsInCommon(generation) else { return }
                groupsInCommonTask = nil
                for chat in loaded where groupsByID[chat.id] == nil {
                    groupsByID[chat.id] = chat
                    groupsInCommon.append(chat.id)
                }
                groupsInCommonOffset = page.chatIds.last ?? offset
                groupsInCommonHasMore = !page.chatIds.isEmpty && groupsInCommon.count < page.totalCount
                applySnapshot()
            } catch {
                guard let self, readsGroupsInCommon(generation) else { return }
                groupsInCommonTask = nil
                historyError = SharedTab.groupsInCommon.loadFailedText
                applySnapshot()
            }
        }
        if groupsInCommon.isEmpty { applySnapshot() }
    }

    private func makeMembersPaneIfNeeded() {
        guard membersPane == nil else { return }
        let group: PeerProfileMembersPane.Group
        switch customChat.type {
        case .group(let value): group = .basic(value.id)
        case .supergroup(let value): group = .supergroup(value.id)
        case .bot,
             .user: return
        }
        let pane = PeerProfileMembersPane(
            chatID: customChat.id,
            group: group,
            accountID: accountID,
            accountUserID: accountUserID,
            client: client,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return contextIsCurrent && restorationIdentity.readySource == restorationIdentity.origin
            },
        )
        pane.host = self
        pane.onChange = { [weak self] in
            guard let self, currentSharedTab == .members else { return }
            historyError = membersPane?.error
            applySnapshot()
        }
        membersPane = pane
    }

    private func applyMembersSnapshot(animated: Bool, completion: (() -> Void)?) {
        let items = membersPane?.items ?? []
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(items)
        // A reread can change a member's role or presence under the same ID.
        snapshot.reconfigureItems(items.filter(existing.contains))
        dataSource.apply(snapshot, animatingDifferences: animated) { completion?() }
        updateEmptyBackground(isEmpty: items.isEmpty, isLoading: membersPane?.isLoading ?? true)
    }

    private func readsGroupsInCommon(_ generation: UInt64) -> Bool {
        !Task.isCancelled && groupsInCommonGeneration == generation && contextIsCurrent
            && currentSharedTab == .groupsInCommon
    }

    private func applyGroupsSnapshot(animated: Bool, completion: (() -> Void)?) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(groupsInCommon)
        dataSource.apply(snapshot, animatingDifferences: animated) { completion?() }
        updateEmptyBackground(isEmpty: groupsInCommon.isEmpty, isLoading: groupsInCommonTask != nil)
    }

    @objc private func messagePressed() {
        guard opensChatItself, !chatIsBelow else {
            navigationController?.popViewController(animated: true)
            return
        }
        openChat(targetMessageID: nil)
    }

    /// PeerInfoProfileItems' Open App: `openWebApp(… url: "", simple: true, source: .generic,
    /// skipTermsOfService: true)`, the bot's main Web App for its own chat.
    @objc private func openAppPressed() {
        guard contextIsCurrent else { return }
        #if DEBUG
            if Self.probeShowsOpenApp { return webAppLauncher.openProbeMainWebApp(name: customChat.displayTitle) }
        #endif
        guard let user = customChat.user else { return }
        webAppLauncher.openMainWebApp(bot: user, chatID: customChat.id, skipsTerms: true)
    }

    private func openChat(targetMessageID: Int64?) {
        guard contextIsCurrent, navigationController?.topViewController === self else { return }
        let location = ChatLocation(accountID: accountID, chatID: customChat.id, clientID: client.id, topic: topic)
        NavigationStorage.shared.push(.customChat(customChat, location: location, targetMessageID: targetMessageID))
    }

    private func openChatSearch() {
        guard contextIsCurrent, let navigationController, navigationController.topViewController === self else {
            return
        }
        let location = ChatLocation(accountID: accountID, chatID: customChat.id, clientID: client.id, topic: topic)
        let controller = ChatViewController(customChat: customChat, location: location)
        navigationController.pushViewController(controller, animated: true)
        if let coordinator = navigationController.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in controller.beginMessageSearch() }
        } else {
            controller.beginMessageSearch()
        }
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
        case .bot,
             .user:
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
        guard contextIsCurrent, let source = membersSource(administrators: true) else { return }
        pushMembers(source)
    }

    @objc private func editPressed() {
        guard contextIsCurrent else { return }
        if customChat.user == nil, isChatAdministrator || infoPermission.canChangeInfo {
            let isChannel =
                if case .supergroup(let group) = customChat.type {
                    group.isChannel
                } else {
                    false
                }
            navigationController?.pushViewController(ChatManagementViewController(
                chatID: customChat.id,
                isChannel: isChannel,
                accountID: accountID,
                accountUserID: accountUserID,
                openMembers: { [weak self] in self?.membersPressed() },
            ), animated: true)
            return
        }
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

    /// Telegram's Mute and More header buttons, read from the chat's current settings.
    @objc private func morePressed() {
        guard moreMenuTask == nil, presentedViewController == nil else { return }
        let scope = ChatListActionAuthority().scope(owner: self)
        let client = client
        guard scope.isCurrent, client.id == TDLib.shared.activeClient.id else { return }
        let chatID = customChat.id
        moreMenuTask = Task { [weak self] in
            let chat = try? await client.getChat(chatId: chatID)
            guard let self else { return }
            moreMenuTask = nil
            guard let chat, scope.isCurrent, presentedViewController == nil else { return }
            let menu = PeerProfileMoreMenu(
                customChat: customChat,
                chat: chat,
                client: client,
                canChangeInfo: infoPermission.canChangeInfo,
                scope: scope,
                host: self,
            )
            presentTelegramContextMenu(
                sourceView: moreActionButton, actions: menu.actions(), presentationStyle: .sourceMorph,
            )
        }
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
    /// PeerInfoGifPaneNode plays the pane's GIFs in place, muted and looping.
    private let animationView = InlineAnimationMediaView()
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
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.fillsBounds = true
        animationView.isUserInteractionEnabled = false
        animationView.isAccessibilityElement = false
        animationView.isHidden = true
        contentView.addSubview(animationView)
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
            animationView.topAnchor.constraint(equalTo: contentView.topAnchor),
            animationView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            animationView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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
        stopAnimation()
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
        stopAnimation()
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
        let source: UIView = cover ?? (animationView.isHidden ? imageView : animationView)
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

    private func stopAnimation() {
        animationView.prepareForReuse()
        animationView.isHidden = true
    }

    private func render() {
        guard let message = representedMessage else { return }
        renderGeneration = UUID()
        imageView.cancel()
        imageView.image = nil
        stopAnimation()
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
        case .messageAnimation(let animation):
            if let thumbnail = animation.animation.thumbnail {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: animation.animation.minithumbnail?.data,
                    maximumPixelSize: 480,
                    accountID: accountID,
                    client: client,
                )
            } else {
                imageView.loadPlaceholder(data: animation.animation.minithumbnail?.data, client: client)
            }
            animationView.isHidden = false
            animationView.configure(animation: animation.animation, displaySize: nil, client: client)
            animationView.setPlaybackVisible(true)
            videoBadge.isHidden = true
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

// MARK: - SharedLink

/// The link a Links row opens: the first URL in the text, a text link (concealed behind other text), or the link
/// preview's page.
struct SharedLink {
    let url: URL
    let isConcealed: Bool

    init?(message: Message) {
        let presentation = MessageContentPresentation.make(message)
        if let text = presentation.formattedText {
            for entity in text.entities {
                switch entity.type {
                case .textEntityTypeTextUrl(let value):
                    if let url = getUrl(from: value.url) {
                        self.init(url: url, isConcealed: true)
                        return
                    }
                case .textEntityTypeUrl:
                    let utf16 = text.text.utf16
                    guard entity.offset >= 0, entity.length > 0, entity.offset + entity.length <= utf16.count
                    else { continue }
                    let range = stringRange(for: text.text, start: entity.offset, length: entity.length)
                    if let url = getUrl(from: String(text.text[range])) {
                        self.init(url: url, isConcealed: false)
                        return
                    }
                default:
                    continue
                }
            }
        }
        if case .messageText(let value) = message.content, let preview = value.linkPreview,
           let url = getUrl(from: preview.url)
        {
            self.init(url: url, isConcealed: false)
            return
        }
        return nil
    }

    private init(url: URL, isConcealed: Bool) {
        self.url = url
        self.isConcealed = isConcealed
    }
}

// MARK: - SharedCellSignature

/// The parts of a shared item its cell draws: readiness, the revision and the media it reveals.
private struct SharedCellSignature: Equatable {
    let ready: Bool
    let editDate: Int
    let contentType: Int
    let revealKey: MediaRevealSession.Key?

    @MainActor init(message: Message, ready: Bool) {
        self.ready = ready
        self.editDate = message.editDate
        self.contentType = Int(message.content.constructorID)
        self.revealKey = MediaRevealSession.Key(message: message)
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
        case .messagePhoto,
             .messageVideo: true
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
    private let progressView = UIProgressView(progressViewStyle: .default)

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
        progressView.isHidden = true
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, progressView])
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
        setDownloadProgress(nil)
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
        setDownloadProgress(nil)
        let presentation = MessageContentPresentation.make(message)
        titleLabel.text = presentation.summary
        // A voice or video message shows its length after the date, as Telegram's Voice pane does.
        let duration: Int? =
            switch message.content {
            case .messageVoiceNote(let value): value.voiceNote.duration
            case .messageVideoNote(let value): value.videoNote.duration
            default: nil
            }
        let date = profileDateString(message.date)
        let subtitle = duration.map { "\(date) · \(String(format: "%d:%02d", $0 / 60, $0 % 60))" } ?? date
        subtitleLabel.text = subtitle
        iconView.image = UIImage(systemName: icon(for: message.content))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(presentation.summary), \(subtitle)"
    }

    /// A file downloading to open or play; nil hides the bar.
    func setDownloadProgress(_ progress: Float?) {
        progressView.isHidden = progress == nil
        progressView.progress = progress ?? 0
        accessibilityValue = progress.map { L10n.betterTG("Accessibility.PercentDownloaded", Int($0 * 100)) }
    }

    private func icon(for content: MessageContent) -> String {
        switch content {
        case .messageDocument: "doc.fill"
        case .messageAudio: "music.note"
        case .messageVoiceNote: "mic.fill"
        case .messageVideoNote: "video.circle.fill"
        default: "link"
        }
    }
}

// MARK: - SharedGroupRowCell

/// A group shared with the user, after Telegram's ContactsPeerItem in the Groups pane.
final class SharedGroupRowCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedGroupRowCell"

    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 2
        contentView.addSubview(labels)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(chat: CustomChat, subtitle: String?, accountID: UUID, client: TDLibClient) {
        titleLabel.text = chat.displayTitle
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        avatarView.configure(
            file: chat.chat.photo?.small,
            minithumbnail: chat.chat.photo?.minithumbnail,
            placeholder: chat.telegramAvatarPlaceholder,
            accountID: accountID,
            client: client,
        )
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [chat.displayTitle, subtitle].compactMap(\.self).joined(separator: ", ")
    }
}

// MARK: - ProfileDateFormatting

private enum ProfileDateFormatting {
    static let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
}

func profileDateString(_ timestamp: Int) -> String {
    Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(ProfileDateFormatting.style)
}
