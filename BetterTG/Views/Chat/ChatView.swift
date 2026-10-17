// ChatView.swift

import AVFoundation
import Combine
import Photos
import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - AttachmentMenuBotStart

/// ChatControllerInitialAttachBotStart: the attachment menu bot a `startattach` link opens in a chat, with the
/// link's start parameter and whether the link just added it.
struct AttachmentMenuBotStart {
    let bot: TDNativeAttachmentMenuBot
    let url: String
    let justInstalled: Bool
}

// MARK: - ChatClientRestorationViewport

/// One initial anchor, never a delayed scroll after the user takes control.
struct ChatClientRestorationViewport {
    let source: TdUpdateSource
    let messageID: Int64?
    let pixelOffset: CGFloat
    let keepsLatest: Bool
    let fallbackOffset: CGFloat
    var snapshotApplied = false
    var appeared = false
    private(set) var pending = true

    mutating func take(currentSource: TdUpdateSource?, hasLayout: Bool, keyboardChanging: Bool) -> Bool {
        guard pending, source == currentSource, snapshotApplied, appeared, hasLayout,
              !keyboardChanging else { return false }
        pending = false
        return true
    }

    mutating func invalidate() { pending = false }

    /// A queued snapshot must consult current intent, not its old captured flag.
    mutating func markSnapshotApplied() -> Bool {
        guard pending else { return false }
        snapshotApplied = true
        return true
    }
}

// MARK: - ChatViewController

final class ChatViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate,
    UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate, ClientRestorableNavigationEntry
{
    // MARK: Internal

    enum PresentationMode {
        case full
        case contextPreview
    }

    // MARK: Private

    private enum Section {
        case messages
    }

    private final class PrefetchTaskEntry {
        let generation: UUID
        var task: Task<Void, Never>?

        init(generation: UUID) {
            self.generation = generation
        }
    }

    private struct PendingQuoteDestination {
        let displayedMessageID: DisplayedMessageID
        let quote: MessageQuoteHighlight
        let targetMessageID: Int64
    }

    private struct SnapshotAnchor {
        let itemID: ChatTimelineItemID
        let minYRelativeToViewport: CGFloat
    }

    private struct AutomaticViewportRestoration {
        let ticket: ChatViewportRestorationAuthority.Ticket
        let keepsLatest: Bool
        let anchor: SnapshotAnchor?
    }

    /// The rows on screen before an album gains or loses members, for performAlbumRegroupTransition(_:).
    private struct AlbumRegroupTransition {
        struct Row {
            /// The row as last drawn, placed at its frame, and its bubble's center in that snapshot.
            let snapshot: UIView
            let bubbleCenter: CGPoint
            /// The mosaic's tiles by message, in the collection view; nil when the row showed no mosaic.
            let tiles: [Int64: CGRect]?
            /// The tiles of members that left, placed at their frames.
            let removedTiles: [UIView]
        }

        /// Every visible row's frame, in the collection view.
        let frames: [ChatTimelineItemID: CGRect]
        let rows: [ChatTimelineItemID: Row]
    }

    private struct PendingComposerSendTransition {
        let kind: ComposerSendTransitionKind
        var messageIDs = [Int64]()
        let snapshots: [ComposerSendTransitionSnapshot]
        let timeout: DispatchWorkItem
    }

    /// An additive move every timeline row shares, started at `start` (media time).
    private struct ComposerSendGlide {
        let key: String
        let animation: CABasicAnimation
        let start: CFTimeInterval

        var end: CFTimeInterval { start + animation.duration }
    }

    private static var videoNoteCapturePermissionDenied: Bool {
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        return camera == .denied || camera == .restricted
            || AVAudioApplication.shared.recordPermission == .denied
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        presentationMode == .full && voiceGestureDefersSystemGestures ? .bottom : []
    }

    private let presentationMode: PresentationMode
    private let targetMessageID: Int64?
    private let targetQuote: MessageQuoteHighlight?
    private let location: ChatLocation
    private let chatVM: ChatVM
    private let tdlib: TDLib
    private lazy var galleryPlaybackContext = MediaGalleryPlaybackContext(
        client: chatVM.client,
        location: location,
        tdlib: tdlib,
    )
    private lazy var mediaRevealSession = galleryPlaybackContext.map(MediaRevealSession.init)
    /// Canonical object and render revision each row had when the reveal session last saw it.
    private var revealReconciledRows = [DisplayedMessageID: (message: CustomMessage, revision: UInt64)]()
    private let historyContainerView = UIView()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, ChatTimelineItemID>!
    private var cancellables = Set<AnyCancellable>()
    private var messageCancellables = Set<AnyCancellable>()
    private var messageRenderOwners = ChatMessageRenderOwners()
    private let timelineSnapshots = ChatTimelineSnapshotState()
    private var messageRenderInvalidations = ChatMessageRenderInvalidations()
    private var prefetchTasks = [DisplayedMessageID: PrefetchTaskEntry]()
    /// Voice and video-note files a prefetch asked TDLib for. TDLib keeps downloading them after the prefetch task
    /// ends, so a row that leaves the prefetch range without being shown cancels them; a shown row's view owns them.
    private var prefetchedPlaybackFiles = [DisplayedMessageID: (client: TDLibClient, fileIDs: [Int])]()
    private var inlineVideoPlaybackOwners = [Int64: GalleryVideoPlaybackOwner]()
    /// The title each date header was last configured with. A structural apply reconfigures only headers whose
    /// title changed (midnight, language): reconfiguring every header in each delete's animated apply cut the rows'
    /// collapse into steps.
    private var dateHeaderTitles = [ChatDateHeaderID: String]()
    private var pendingInlineVideoOwnerReturns = Set<Int64>()
    private let customNavigationBar = TelegramChatNavigationBar()
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private let navigationBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let pinnedMessageBanner = PinnedMessageBannerView()
    private var pinnedMessageBannerHeightConstraint: NSLayoutConstraint!
    private let topicReopenBar = TopicReopenBarView()
    private var topicReopenBarHeightConstraint: NSLayoutConstraint!
    private let voicePlaybackHeader = VoicePlaybackHeaderView()
    private var voicePlaybackHeaderHeightConstraint: NSLayoutConstraint!
    private let liveLocationPanel = LiveLocationPanelView()
    private var liveLocationPanelHeightConstraint: NSLayoutConstraint!
    /// The account's live location shared in this chat, shown in `liveLocationPanel`.
    private var liveLocationBroadcast: LiveLocationBroadcast?
    private var liveLocationOpenTask: Task<Void, Never>?
    private var pinnedMessageBannerTransitionGeneration = UInt64.zero
    private let composerKeyboardEdgeView = ComposerKeyboardEdgeView()
    private lazy var composerView: ChatComposerView = {
        let composer = ChatComposerView(chatVM: chatVM)
        if let state = restoredComposerState { composer.restoreClientViewState(state, focus: false) }
        return composer
    }()

    private lazy var inlineKeyboardActions = InlineKeyboardActionPerformer(host: .init(
        presenter: { [weak self] in self },
        isCurrent: { [weak self] in
            guard let self else { return false }
            return routeIsRetained && chatVM.locationContextIsCurrent
        },
        showToast: { [weak self] text in self?.showChatToast(text) },
        openUserProfile: { [weak self] userID in self?.openContactProfile(userID: userID) },
        insertInlineQuery: { [weak self] query in self?.insertInlineQuery(query) },
        chooseInlineChat: { [weak self] text, types, messageID in
            self?.presentSwitchInlinePicker(text: text, types: types, messageID: messageID)
        },
    ))
    /// The attachment menu bots' Web Apps, made with the chat's account on the first launch.
    private var webAppLauncher: WebAppLauncher?
    /// The bot menu button's Web App, made with the chat's account on the first launch.
    private var menuWebAppLauncher: WebAppLauncher?
    /// ChatControllerInitialAttachBotStart: an attachment menu bot link's bot, launched once the chat is on screen.
    private var pendingAttachmentMenuBotStart: AttachmentMenuBotStart?

    private let messageSelectionToolbar = MessageSelectionToolbar()
    private var messageSelectionToolbarHeightConstraint: NSLayoutConstraint!
    private let scrollToLatestButton = UIButton(type: .system)
    private let unreadBadgeLabel = TelegramUnreadBadgeLabel(minimumDiameter: 20, horizontalPadding: 11)
    private var scrollToLatestButtonVisible = false
    /// The chat this full view continues the voice playlist for; the background continuation stays out of it.
    private var voicePlaylistKey: VoicePlaylistContinuation.ChatKey?
    private let mentionsButton = ChatHistoryNavigationButton(
        symbolName: "at", accessibilityLabel: L10n.betterTG("Accessibility.NextUnreadMention"),
    )
    private let reactionsButton = ChatHistoryNavigationButton(
        symbolName: "heart", accessibilityLabel: L10n.betterTG("Accessibility.NextUnreadReaction"),
    )
    private var mentionsButtonBottomConstraint: NSLayoutConstraint?
    private var reactionsButtonBottomConstraint: NSLayoutConstraint?
    /// Mentions and reactions shown, and whether they stack on the scroll-to-latest button.
    private var unreadJumpLayout: (mentions: Bool, reactions: Bool, latest: Bool)?
    private var unreadJumpTask: Task<Void, Never>?
    private var didPresentMicrophoneError = false
    private var didPresentVoiceNoteError = false
    private var didPresentVideoNoteError = false
    private var didPresentReactionError = false
    private var didPresentPinError = false
    private var didPresentMessageActionError = false
    private var didPresentInlineBotLocationRequest = false
    private var didPresentSendError = false
    private var didPresentDraftError = false
    private var lastHighlightedMessageID: Int64?
    private var didPerformInitialScroll = false
    private var pendingScrollMessageID: Int64?
    private var pendingQuoteHighlight: MessageQuoteHighlight?
    /// The message whose quote selection opens once navigation settles (reply options' Select Specific Quote).
    private var pendingReplyQuoteSelectionID: Int64?
    private let messageNavigationScroll = ChatMessageNavigationScroll()
    private var pendingQuoteDestination: PendingQuoteDestination?
    private var messageNavigationTask: Task<Void, Never>?
    private var latestHistoryTask: Task<Void, Never>?
    /// Telegram's scroll to the end of history owns the viewport until it lands. Self-sizing and snapshot anchors
    /// would otherwise stop the animation partway with a non-animated offset write.
    private var latestEdgeScrollInFlight = false
    private var latestEdgeScrollGeneration = 0
    private var metadataNavigationTask: Task<Void, Never>?
    /// The post whose comment thread is opening; its comments bar shows a spinner (Telegram's
    /// `currentMessageWithLoadingReplyThread`).
    private var commentsThreadLoad: (id: UUID, displayedID: DisplayedMessageID)?
    private var messageHighlightTask: Task<Void, Never>?
    private var messageSearchActive = false
    private lazy var messageSearch = makeMessageSearch()
    private let messageSearchPanel = ChatSearchPanel()
    private var messageSearchMemberList: ChatSearchMemberListView?
    /// Telegram's displayHistoryFilterAsList: the results show as a list over the chat.
    private var messageSearchShowsList = false
    private var messageSearchResultsList: ChatSearchResultsListView?
    private var messageSearchQuery = ""
    /// Telegram's ChatSearchDomain: picking a member after "from:", or the member whose messages are searched.
    private var messageSearchChoosesMember = false
    private var messageSearchMember: ChatSearchMemberListView.Member?
    private var messageDateJumpTask: Task<Void, Never>?
    /// The account's favorite stickers by file ID, for the sticker message menu's Add/Remove from Favorites.
    private var favoriteStickerFileIDs = Set<Int>()
    private var stickerActionTask: Task<Void, Never>?
    /// A poll's file being downloaded to open or play (openPollMedia).
    private var pollMediaTask: Task<Void, Never>?
    /// The message menu's Save Image, Save Video or Save to Files in progress.
    private var mediaSaveTask: Task<Void, Never>?
    /// Keeps the Save to Files picker's delegate, which removes the temporary copy when the picker closes.
    private var fileExportDelegate: MessageFileExportDelegate?
    private var isTerminatingNavigation = false
    private var composerLeadingConstraint: NSLayoutConstraint?
    private var composerTrailingConstraint: NSLayoutConstraint?
    private var composerBottomConstraint: NSLayoutConstraint?
    private var composerKeyboardAttached = false
    private var voiceGestureDefersSystemGestures = false
    private var videoNoteRecorder: VideoNoteRecorderViewController?
    private var videoNoteReplyMessage: CustomMessage?
    private var videoNoteReplyInput: InputMessageReplyTo?
    private var videoNoteSendTopic: MessageTopic? {
        didSet { chatVM.recordingVideoTopicDemand = videoNoteSendTopic }
    }

    private var videoNoteChatActionActive = false
    private var videoNoteChatActionTask: Task<Void, Never>?
    /// The chat's RaiseToListenManager (ChatControllerImpl.raiseToListen).
    private var raiseToListen: RaiseToListenActivator?
    private var raiseToListenRecordingTask: Task<Void, Never>?
    private var isChatVisible = false
    /// When the voice playlist last ran out: a recording raised right after waits a second from then.
    private var voicePlaylistDidEndTimestamp: CFTimeInterval = 0
    /// Notes this chat played, which count as listened before TDLib's update arrives.
    private var playedListenableMessageIDs = Set<Int64>()
    private var restoredVideoRecordingDraftIDHandled: UUID?
    private var selectedDisplayedMessageIDs = Set<DisplayedMessageID>()
    private var isSelectingMessages = false
    /// The reply keyboard revision whose automatic opening was decided.
    private var evaluatedReplyKeyboardRevision: Int?
    private var selectionInteractionActive = false
    /// A two-finger pan that ran into the selection limit; its alert waits until the pan ends.
    private var selectionInteractionHitLimit: Int?
    private var selectionCapabilityTask: Task<Void, Never>?
    private var selectionCapabilityGeneration: UUID?
    private var timelineLayoutMutationDepth = 0
    private var viewportCompletionLayoutDepth = 0
    private var acknowledgedVisibleRawIDs = Set<Int64>()
    private var viewportRestorationAuthority = ChatViewportRestorationAuthority()
    private var pendingSelfSizingRestoration: AutomaticViewportRestoration?
    private var selfSizingAnchorRestoreScheduled = false
    private var pendingComposerSendTransitions = [UUID: PendingComposerSendTransition]()
    private var activeComposerSendAnimations = 0
    private var composerSendGlideCount = 0
    private var composerSendGlides = [ComposerSendGlide]()
    /// A media send was accepted while an earlier snapshot was still applying: the composer keeps the sent media until
    /// the snapshot that inserts it, so both change in one transaction.
    private var composerAwaitsSentMediaInsertion = false
    private var composerSentMediaSettleGeneration = 0
    private var sendTransitionMessageIDAliases = [Int64: Int64]()
    private var sendTransitionAliasOrder = [Int64]()
    private var pendingDeleteSnapshotWorkItem: DispatchWorkItem?
    private var pendingDeleteSnapshotDeadline: CFTimeInterval?
    private lazy var importBarrier = ChatComposerImportBarrier(location: location)
    private var clientPreparationTask: Task<Void, Never>?
    private var clientPreparationSource: TdUpdateSource?
    private var preparedClient: (source: TdUpdateSource, client: TDLibClient, chat: CustomChat, topic: ForumTopic?)?
    private var clientRetryScheduled = false
    private var clientOwnerRetired = false
    private var restoredViewport: ChatClientRestorationViewport?
    private var restoredComposerState: ChatComposerView.ClientViewState?
    /// The replaced controller's last history frame. It covers this history until the restored viewport lands, so
    /// a client renewal never shows the latest edge first.
    private var restoredHistoryCover: UIView?
    /// The replaced controller's pinned banner, kept until the renewed client answers for the pinned message.
    private var restoredPinnedBannerCover: UIView?
    private var restorationFocusAttempted = false
    private var restorationFocusSettled = false
    private var keyboardIsChanging = false
    /// The poll whose Add an Option field has the keyboard (Telegram's `focusedPollAddOptionMessageId`).
    private var pollAddOptionFocusMessageID: Int64?
    /// Set when the field takes the keyboard, until the poll has moved above it.
    private var pendingPollAddOptionScroll = false
    #if DEBUG
        private var messageNavigationGeometry: ChatMessageNavigationGeometry?
        private var viewportCompletionProbe: ChatViewportCompletionProbe?
    #endif

    private lazy var messageContextGesture: ContextMenuPressGestureRecognizer = {
        let gesture = ContextMenuPressGestureRecognizer(target: self, action: #selector(messageLongPressed(_:)))
        gesture.pressedViewProvider = { [weak self] gesture in
            guard let self, !isSelectingMessages else { return nil }
            let point = gesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: point),
                  case .message = dataSource.itemIdentifier(for: indexPath),
                  let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
            else { return nil }
            // A reaction chip that lists who reacted takes the long press itself.
            var touched = collectionView.hitTest(point, with: nil)
            while let current = touched, current !== cell {
                if (current as? MessageReactionStripView)?.handlesLongPress == true { return nil }
                touched = current.superview
            }
            return cell.contextPreviewView
        }
        gesture.onPressCancelled = { [weak self] in self?.retryClientRestoration() }
        return gesture
    }()

    var displayedChatID: Int64 { location.chatID }

    var navigationClientSource: TdUpdateSource? {
        location.accountID.map { TdUpdateSource(accountID: $0, clientID: location.clientID) }
    }

    private var showsComposer: Bool {
        presentationMode == .full
            && (location.forumTopicID != nil || chatVM.isAllMessagesForum || chatVM.canShowComposer)
    }

    /// A reply thread is titled "N Comments" or "N Replies", with only typing activity below (ChatTitleView,
    /// `.replyThread`). A forum topic shows who acts in it, else its chat below the topic name.
    private var headerTitleAndStatus: (title: String, status: String) {
        if let title = chatVM.messageThreadTitle {
            return (title, chatVM.actionStatus)
        }
        let title = chatVM.forumTopicInfo?.name ?? chatVM.customChat.displayTitle
        let status =
            if let activity = chatVM.topicActivityStatus {
                activity
            } else if location.isTopicScoped {
                chatVM.isReadOnlyTopic
                    ? (chatVM.forumTopicInfo?.isClosed == true || chatVM.forumTopicInfo?.isHidden == true
                        ? L10n.betterTG("Forum.ClosedTopicReadOnly")
                        : L10n.betterTG("Forum.ReadOnlyStatus", chatVM.customChat.displayTitle))
                    : chatVM.customChat.displayTitle
            } else {
                chatVM.headerStatus
            }
        return (title, status)
    }

    private var isNearLatest: Bool {
        collectionView.contentOffset.y + collectionView.adjustedContentInset.top < 100
    }

    private var selectedDisplayedMessages: [CustomMessage] {
        chatVM.messages.filter { selectedDisplayedMessageIDs.contains($0.displayedID) }
    }

    private var selectedSourceMessageIDs: [Int64] {
        sourceMessageIDs(forDisplayedMessageIDs: selectedDisplayedMessageIDs)
    }

    private var selectionAccessibilityAnnouncement: String {
        let bubbleCount = selectedDisplayedMessageIDs.count
        let sourceCount = selectedSourceMessageIDs.count
        if bubbleCount == sourceCount {
            return L10n.telegramPlural("VoiceOver.Chat.MessagesSelected", count: sourceCount)
        }
        return L10n.betterTG("Accessibility.ConversationsSelected", bubbleCount, sourceCount)
    }

    private var routeIsRetained: Bool {
        !clientOwnerRetired && navigationController?.viewControllers.contains(where: { $0 === self }) == true
    }

    /// The account's client was renewed and a replacement controller takes over this route. Until then the old
    /// client no longer answers, so this controller keeps its chrome and history geometry as they were.
    private var awaitsClientRenewal: Bool {
        presentationMode == .full && !clientOwnerRetired && tdlib.activeAccountID == location.accountID
            && tdlib.activeClient.id != location.clientID
    }

    /// A two-finger selection pan moves the timeline like a scroll, so it suspends viewport restoration.
    private var userIsScrollingTimeline: Bool {
        collectionView.isTracking || collectionView.isDragging || collectionView.isDecelerating
            || selectionInteractionActive
    }

    private var hasPendingMessageNavigation: Bool {
        messageNavigationTask != nil || pendingScrollMessageID != nil
    }

    private var timelineSourceIsCurrent: Bool {
        !clientOwnerRetired && chatVM.locationContextIsCurrent
            && navigationClientSource != nil && navigationClientSource == tdlib.activeUpdateSource
    }

    private var keepsPersistentReplyKeyboard: Bool {
        chatVM.supportsReplyKeyboard && chatVM.customChat.bot != nil
            && chatVM.replyKeyboard.offeredKeyboard?.markup.isPersistent == true
    }

    /// Telegram offers "from:" in groups only (ChatTagSearchInputPanelNode.canSearchMembers).
    private var canSearchMessagesByMember: Bool {
        switch chatVM.customChat.type {
        case .group: true
        case .supergroup(let group): !group.isChannel && !group.isDirectMessagesGroup
        case .bot, .user: false
        }
    }

    /// ChatHistoryEntriesForView's ChatInfoEntry: a bot chat with a description whose history is read back to its
    /// first message shows the bot's info above it; an empty chat shows it as the background instead.
    private var showsBotInfoRow: Bool {
        guard case .bot = chatVM.customChat.type, chatVM.historyReachedStart, !chatVM.messages.isEmpty,
              location.topic == nil, location.messageThreadID == nil,
              let info = chatVM.botInfo, !info.description.isEmpty else { return false }
        return true
    }

    convenience init(
        customChat: CustomChat,
        location: ChatLocation? = nil,
        forumTopic: ForumTopic? = nil,
        presentationMode: PresentationMode = .full,
        targetMessageID: Int64? = nil,
        targetQuote: MessageQuoteHighlight? = nil,
        messageThread: MessageThreadInfo? = nil,
        pendingForward: PendingMessageForward? = nil,
        tdlib: TDLib = .shared,
    ) {
        let resolvedLocation = location ?? ChatLocation.current(
            chatID: customChat.id,
            client: tdlib.activeClient,
        )
        let chatVM = ChatVM(
            customChat: customChat,
            location: resolvedLocation,
            forumTopic: forumTopic,
            messageThread: messageThread,
            previewing: presentationMode == .contextPreview,
            client: tdlib.activeClient,
        )
        if let pendingForward { chatVM.beginForward(pendingForward) }
        self.init(
            chatVM: chatVM,
            presentationMode: presentationMode,
            targetMessageID: targetMessageID,
            targetQuote: targetQuote,
            tdlib: tdlib,
        )
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        clientPreparationTask?.cancel()
        prefetchTasks.values.forEach { $0.task?.cancel() }
        // Rows that were prefetched but never shown still have TDLib downloads; nothing else will cancel them.
        let unshownPlaybackFiles = Array(prefetchedPlaybackFiles.values)
        if !unshownPlaybackFiles.isEmpty {
            Task {
                for files in unshownPlaybackFiles {
                    for fileID in files.fileIDs {
                        _ = try? await files.client.cancelDownloadFile(fileId: fileID, onlyIfPending: true)
                    }
                }
            }
        }
        MainActor.assumeIsolated {
            if let voicePlaylistKey { VoicePlaylistContinuation.shared.unregister(voicePlaylistKey) }
            for owner in inlineVideoPlaybackOwners.values {
                owner.onReturnToInline = nil
                if !GalleryPictureInPictureCoordinator.shared.isRetaining(owner) {
                    owner.invalidate()
                }
            }
        }
        messageNavigationTask?.cancel()
        latestHistoryTask?.cancel()
        metadataNavigationTask?.cancel()
        messageHighlightTask?.cancel()
        selectionCapabilityTask?.cancel()
        pendingDeleteSnapshotWorkItem?.cancel()
        for transition in pendingComposerSendTransitions.values {
            transition.timeout.cancel()
            transition.snapshots.forEach { $0.view.removeFromSuperview() }
        }
    }

    private init(
        chatVM: ChatVM, presentationMode: PresentationMode = .full, targetMessageID: Int64? = nil,
        targetQuote: MessageQuoteHighlight? = nil, tdlib: TDLib,
        viewport: ChatClientRestorationViewport? = nil, composer: ChatComposerView.ClientViewState? = nil,
        historyCover: UIView? = nil,
        pinnedBannerCover: UIView? = nil,
    ) {
        self.presentationMode = presentationMode
        self.location = chatVM.location
        self.chatVM = chatVM
        self.targetMessageID = targetMessageID
        self.targetQuote = targetQuote
        self.tdlib = tdlib
        self.restoredViewport = viewport
        self.restoredComposerState = composer
        self.restoredHistoryCover = viewport == nil ? nil : historyCover
        self.restoredPinnedBannerCover = viewport == nil ? nil : pinnedBannerCover
        super.init(nibName: nil, bundle: nil)
        importBarrier.onQuiescent = { [weak self] in self?.retryClientRestoration() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureCollectionView()
        configureNavigationBar()
        configureDataSource()
        observeState()
        updateSnapshot(animated: false)
        restoreVideoRecordingIfNeeded()
        if let targetMessageID {
            scrollToMessage(id: targetMessageID, quote: targetQuote)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !(presentedViewController is MediaGalleryViewController) {
            pauseInlineVideoPlayback(excluding: nil)
        }
        guard presentationMode == .full else { return }
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        endMessageSelection()
        isTerminatingNavigation = true
        videoNoteRecorder?.teardownForNavigation()
        composerView.cancelActiveRecordingGesture(preservingVoiceDraft: true)
        if chatVM.canWriteBasicMessages {
            Task { [chatVM] in await chatVM.updateDraft() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        acknowledgedVisibleRawIDs.removeAll()
        isChatVisible = false
        raiseToListen?.isEnabled = false
        #if DEBUG
            viewportCompletionProbe?.interrupt("controller disappeared")
        #endif
        cancelMessageNavigation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isTerminatingNavigation = false
        if presentationMode == .full {
            chatVM.resumeVoiceRecordingInteraction()
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoredViewport?.appeared = true
        if restoredHistoryCover != nil {
            // A restoration that never settles must not leave the history covered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.removeRestoredHistoryCover()
            }
        }
        if restoredPinnedBannerCover != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let cover = restoredPinnedBannerCover else { return }
                restoredPinnedBannerCover = nil
                cover.removeFromSuperview()
                updatePinnedMessageBanner(animated: true)
            }
        }
        applyPendingMessageNavigation()
        settleRestoredViewport()
        if preparedClient == nil { clientPreparationSource = nil }
        retryClientRestoration()
        evaluateReplyKeyboardChange()
        // Gallery paging can reveal another album member while the timeline is covered.
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard case .message(let displayedID) = dataSource.itemIdentifier(for: indexPath),
                  let message = message(for: displayedID),
                  message.sourceMessages.contains(where: {
                      let permit = mediaRevealSession?.permit(for: $0)
                      return permit?.key.hasSpoiler == true && permit?.allowsPixels == true
                  }) else { continue }
            reconfigureMessage(id: message.id)
        }
        restoreVisibleInlineVideoPlayback()
        acknowledgeCommittedVisibleMessages(requestHistory: true)
        isChatVisible = true
        setUpRaiseToListen()
        applyPendingAttachmentMenuBotStart()
        #if DEBUG
        if viewportCompletionProbe == nil, presentationMode == .full, chatVM.customChat.isSavedMessages,
           ChatViewportCompletionProbe.enabled
        {
            let probe = ChatViewportCompletionProbe(controller: self)
            viewportCompletionProbe = probe
            probe.start()
        }
        if presentationMode == .full, chatVM.customChat.isSavedMessages {
            ChatTimelineValueCostProbe.start { [weak self] in self?.chatVM.messages ?? [] }
        }
        guard presentationMode == .full,
              ProcessInfo.processInfo.arguments.contains("-ui-smoke-keyboard")
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.composerView.focusInput()
        }
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollToLatestButton.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        if showsComposer {
            let keyboardAttached = view.keyboardLayoutGuide.layoutFrame.minY
                < view.bounds.maxY - view.safeAreaInsets.bottom - 1
            updateComposerFloatingState(keyboardAttached)
            composerKeyboardEdgeView.setVisible(
                keyboardAttached && !messageSearchActive && !isSelectingMessages && pollAddOptionFocusMessageID == nil,
                animated: view.window != nil,
            )
        }
        updateHistoryInsets()
        applyPendingMessageNavigation()
        settleRestoredViewport()
        retryClientRestoration()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator,
    ) {
        let restoration = captureAutomaticViewportRestoration(allowInitial: false)
        timelineLayoutMutationDepth += 1
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }) { [weak self] _ in
            guard let self else { return }
            defer { finishTimelineLayoutMutation() }
            synchronizeNativeSelection()
            layoutForViewportCompletion()
            restoreAutomaticViewport(restoration)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + customNavigationBar.visibleContentHeight
        messageSelectionToolbarHeightConstraint?.constant =
            MessageSelectionToolbar.contentHeight + view.safeAreaInsets.bottom
    }

    /// Hands a forward draft to its destination. A chat already open for it in the stack takes the draft, as in
    /// Telegram (ChatControllerForwardMessages reuses the open chat), so one chat never gets a second composer.
    static func openForward(
        _ draft: PendingMessageForward,
        in chat: CustomChat,
        topic: ForumTopic?,
        destination: ChatLocation,
        navigationController: UINavigationController?,
    ) {
        guard let navigationController else { return }
        let open = navigationController.viewControllers.last {
            ($0 as? ChatViewController).map { $0.presentationMode == .full && $0.location == destination } == true
        } as? ChatViewController
        if let open {
            if navigationController.topViewController !== open {
                navigationController.popToViewController(open, animated: true)
            }
            open.chatVM.beginForward(draft)
        } else {
            navigationController.pushViewController(
                ChatViewController(customChat: chat, location: destination, forumTopic: topic, pendingForward: draft),
                animated: true,
            )
        }
    }

    /// moveReplyToChat: the destination, already open or pushed, takes the reply to the other chat's message.
    static func openExternalReply(
        to message: CustomMessage,
        targetMessageID: Int64,
        quote: InputTextQuote?,
        in chat: CustomChat,
        topic: ForumTopic?,
        destination: ChatLocation,
        navigationController: UINavigationController?,
    ) {
        openChat(chat, topic: topic, destination: destination, navigationController: navigationController)?
            .chatVM
            .beginExternalReply(to: message, targetMessageID: targetMessageID, quote: quote)
    }

    /// Switch inline's chosen chat (ChatControllerOpenPeer `peerSelected`): the destination, already open or
    /// pushed, gets "@bot query" in its composer, in place of its draft.
    static func openSwitchInline(
        _ text: String,
        in chat: CustomChat,
        topic: ForumTopic?,
        destination: ChatLocation,
        navigationController: UINavigationController?,
    ) {
        guard let controller = openChat(
            chat,
            topic: topic,
            destination: destination,
            navigationController: navigationController,
        ) else { return }
        controller.loadViewIfNeeded()
        controller.insertInlineQuery(text)
    }

    /// The destination's full chat on top of the stack: popped back to when open, pushed otherwise.
    private static func openChat(
        _ chat: CustomChat,
        topic: ForumTopic?,
        destination: ChatLocation,
        navigationController: UINavigationController?,
    ) -> ChatViewController? {
        guard let navigationController else { return nil }
        let open = navigationController.viewControllers.last {
            ($0 as? ChatViewController).map { $0.presentationMode == .full && $0.location == destination } == true
        } as? ChatViewController
        if let open {
            if navigationController.topViewController !== open {
                navigationController.popToViewController(open, animated: true)
            }
            return open
        }
        let controller = ChatViewController(customChat: chat, location: destination, forumTopic: topic)
        navigationController.pushViewController(controller, animated: true)
        return controller
    }

    private static func isChatGalleryMedia(_ message: Message) -> Bool {
        switch message.content {
        case .messagePhoto, .messageVideo: true
        default: false
        }
    }

    /// The content `ChatVM.editMessage` changes through editMessageText or editMessageCaption.
    private static func editsText(_ content: MessageContent) -> Bool {
        switch content {
        case .messageAnimation, .messageAudio, .messageDocument, .messagePhoto, .messageText, .messageVideo,
             .messageVoiceNote:
            true
        default:
            false
        }
    }

    private static func readDateTitle(_ readDate: TDNativeMessageReadDate) -> String {
        switch readDate {
        case .messageReadDateRead(let read):
            let date = Date(timeIntervalSince1970: TimeInterval(read.readDate))
            let time = date.formatted(date: .omitted, time: .shortened)
            if Calendar.current.isDateInToday(date) {
                return L10n.telegram("Chat.PrivateMessageSeenTimestamp.TodayAt", time)
            }
            if Calendar.current.isDateInYesterday(date) {
                return L10n.telegram("Chat.PrivateMessageSeenTimestamp.YesterdayAt", time)
            }
            return L10n.telegram(
                "Chat.PrivateMessageSeenTimestamp.Date",
                date.formatted(date: .abbreviated, time: .shortened),
            )
        case .messageReadDateMyPrivacyRestricted:
            return L10n.telegram("Chat.ContextMenuReadDate.ReadAvailablePrefix") + " · "
                + L10n.telegram("Chat.ContextMenuReadDate.ReadAvailableBadge")
        default:
            return L10n.telegram("Chat.ContextMenuReadDate.ReadAvailablePrefix")
        }
    }

    /// The message as TDLib has it now, if it still lets its media be saved (the gallery's export rules).
    private static func savableMessage(chatID: Int64, messageID: Int64, client: TDLibClient) async throws -> Message {
        async let messageRequest = client.getMessage(chatId: chatID, messageId: messageID)
        async let propertiesRequest = client.getMessageProperties(chatId: chatID, messageId: messageID)
        let (resolved, properties) = try await (messageRequest, propertiesRequest)
        try Task.checkCancellation()
        if case .messagePaidMedia = resolved.content { throw MediaGallerySaveError.protectedContent }
        guard resolved.chatId == chatID, resolved.id == messageID,
              properties.canBeSaved,
              !properties.hasProtectedContentByCurrentUser,
              !properties.hasProtectedContentByOtherUser,
              resolved.selfDestructType == nil,
              resolved.selfDestructIn == 0
        else { throw MediaGallerySaveError.protectedContent }
        return resolved
    }

    /// The document or audio file of a message and the name Save to Files gives it (Telegram uses the file name,
    /// else "performer - title" for music).
    private static func exportableFile(of message: Message) -> (file: File, filename: String)? {
        let file: File
        let name: String
        let mimeType: String
        switch message.content {
        case .messageDocument(let content):
            file = content.document.document
            name = content.document.fileName
            mimeType = content.document.mimeType
        case .messageAudio(let content):
            file = content.audio.audio
            let tags = [content.audio.performer, content.audio.title]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            name = content.audio.fileName.isEmpty ? tags.joined(separator: " - ") : content.audio.fileName
            mimeType = content.audio.mimeType
        default:
            return nil
        }
        let lastComponent = URL(filePath: name.replacingOccurrences(of: "\\", with: "/")).lastPathComponent
        var fileExtension = URL(filePath: lastComponent).pathExtension
        if fileExtension.isEmpty {
            fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension
                ?? URL(filePath: file.local.path).pathExtension
        }
        return (file, MediaGalleryExport.sanitizedFilename(
            lastComponent,
            fallbackStem: "bettertg-file-\(message.id)",
            fileExtension: fileExtension.isEmpty ? "bin" : fileExtension,
        ))
    }

    /// Links or copies a downloaded file into a fresh temporary folder under its export name.
    private static func temporaryExportCopy(of sourceURL: URL, filename: String) async throws
        -> (directory: URL, file: URL)
    {
        let directoryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-file-export-\(UUID().uuidString)", isDirectory: true)
        let destinationURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                do {
                    try fileManager.linkItem(at: sourceURL, to: destinationURL)
                } catch {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                try? fileManager.removeItem(at: directoryURL)
                throw MediaGallerySaveError.downloadFailed
            }
        }.value
        return (directoryURL, destinationURL)
    }

    /// Telegram's list transitions run 0.4 s (ListView's insertionAnimationDuration) on `.spring`, which on iOS 26
    /// samples a critically damped spring (mass 1, stiffness 555.027, damping 47.118) across its 0.5 s.
    private static func listTransitionAnimation(
        _ keyPath: String,
        from: Any,
        to: Any,
        additive: Bool = false,
    ) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = 555.027
        animation.damping = 47.118
        animation.duration = 0.5
        animation.speed = Float(0.5 / 0.4)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isAdditive = additive
        animation.fromValue = from
        animation.toValue = to
        return animation
    }

    /// Telegram leaves a group's upgrade to a supergroup out of the history (ChatHistoryEntriesForView).
    private static func isUpgradeNotice(_ content: MessageContent) -> Bool {
        switch content {
        case .messageChatUpgradeFrom, .messageChatUpgradeTo: true
        default: false
        }
    }

    private nonisolated static func pollOptionProperties(
        _ option: PollOption,
        chatID: Int64,
        messageID: Int64,
        client: TDLibClient,
    ) async -> TDNativePollOptionProperties? {
        guard !option.id.isEmpty else { return nil }
        return try? await client.send(TDNativeRequests.getPollOptionProperties(
            chatId: chatID,
            messageId: messageID,
            pollOptionId: option.id,
        ))
    }

    /// Who added the answer: a user's first name or a chat's title, with the avatar when its photo is downloaded.
    private nonisolated static func pollOptionAuthor(
        _ sender: MessageSender?,
        accountUserID: Int64?,
        client: TDLibClient,
    ) async -> PollOptionMenu.Author? {
        let name: String
        let photo: TDNativeFile?
        var isCurrentUser = false
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await client.getUser(userId: value.userId) else { return nil }
            name = [user.firstName, user.lastName].first { !$0.isEmpty } ?? ServiceMessageText.displayTitle(user)
            photo = user.profilePhoto?.small
            isCurrentUser = user.id == accountUserID
        case .messageSenderChat(let value):
            guard let chat = try? await client.getChat(chatId: value.chatId) else { return nil }
            name = chat.title
            photo = chat.photo?.small
        case nil:
            return nil
        }
        let avatar = photo.flatMap { file in
            file.local.isDownloadingCompleted ? PollOptionMenu.avatar(path: file.local.path) : nil
        }
        return PollOptionMenu.Author(name: name, isCurrentUser: isCurrentUser, avatar: avatar)
    }

    /// A bot start link for a chat the router has just created shows Start before the chat appears.
    func beginBotStart(parameter: String) {
        chatVM.beginBotStart(parameter: parameter)
    }

    /// An attachment menu bot link's bot for this chat: launched now when the chat is on screen, or as it appears.
    func beginAttachmentMenuBot(_ start: AttachmentMenuBotStart) {
        pendingAttachmentMenuBotStart = start
        if isChatVisible { applyPendingAttachmentMenuBotStart() }
    }

    /// ChatController's sendBotCommand for a "/command" tapped in a message: it's sent where the user can write.
    func sendBotCommand(_ command: String) {
        guard showsComposer, !clientOwnerRetired, chatVM.locationContextIsCurrent, chatVM.canWriteBasicMessages
        else { return }
        Task { [weak self] in await self?.chatVM.sendBotCommandText(command) }
    }

    /// ChatControllerImpl.openPeer for the peer already on screen: a link to one of its messages scrolls there and a
    /// bot start link shows Start here, and an attachment menu bot link launches its bot here, instead of a second
    /// copy of the chat. False when this isn't that chat.
    func openLinkInPlace(
        chatID: Int64,
        topic: MessageTopic?,
        messageID: Int64?,
        botStartParameter: String?,
        attachmentMenuBotStart: AttachmentMenuBotStart? = nil,
    ) -> Bool {
        guard presentationMode == .full, !clientOwnerRetired, chatVM.locationContextIsCurrent,
              location.chatID == chatID, location.topic == topic,
              navigationController?.topViewController === self else { return false }
        if let messageID { navigate(to: .message(chatID: chatID, messageID: messageID, quote: nil)) }
        if let botStartParameter { chatVM.beginBotStart(parameter: botStartParameter) }
        if let attachmentMenuBotStart { beginAttachmentMenuBot(attachmentMenuBotStart) }
        return true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        recordMessageNavigationGeometry("scroll")
        if userIsScrollingTimeline { viewportRestorationAuthority.invalidate() }
        messageNavigationScroll.didScroll()
        updateScrollToLatestButtonVisibility(animated: true)
        updateInlineVideoPlaybackVisibility()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        #if DEBUG
            viewportCompletionProbe?.dragBegan()
        #endif
        recordMessageNavigationGeometry("drag-begin")
        viewportRestorationAuthority.invalidate()
        if hasPendingMessageNavigation { didPerformInitialScroll = true }
        cancelMessageNavigation()
        latestEdgeScrollInFlight = false
        abandonRestoredViewport()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        recordMessageNavigationGeometry("drag-end", settled: true)
        if !decelerate {
            applyPendingMessageNavigation()
            retryClientRestoration()
        }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        recordMessageNavigationGeometry("deceleration-end", settled: true)
        applyPendingMessageNavigation()
        retryClientRestoration()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        recordMessageNavigationGeometry("animation-end", settled: true)
        latestEdgeScrollInFlight = false
        messageNavigationScroll.animationEnded()
    }

    func presentationControllerDidDismiss(_: UIPresentationController) {
        retryClientRestoration()
        acknowledgeCommittedVisibleMessages(requestHistory: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [weak self] in
            self?.retryClientRestoration()
            self?.acknowledgeCommittedVisibleMessages(requestHistory: true)
        }
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
        picker.dismiss(animated: true) { [weak self] in
            self?.retryClientRestoration()
            self?.acknowledgeCommittedVisibleMessages(requestHistory: true)
        }
        guard let image = info[.originalImage] as? UIImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        importImages([image])
    }

    func documentPicker(
        _: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL],
    ) {
        guard !urls.isEmpty else { return }
        guard let token = importBarrier.begin() else { return }
        let barrier = importBarrier
        Task { [weak self] in
            let documents = await Task.detached(priority: .userInitiated) {
                SelectedDocumentFileStore.copy(urls)
            }.value
            let accepted = barrier.finish(
                token, currentAccountID: self?.tdlib.activeAccountID,
                routeIsRetained: self?.routeIsRetained == true,
            ) {
                guard let self, !documents.isEmpty else { return }
                self.chatVM.discardDisplayedImages()
                self.chatVM.replaceDisplayedDocuments(documents)
            }
            if !accepted {
                await Task.detached { SelectedDocumentFileStore.remove(documents.map(\.url)) }.value
            }
        }
    }

    func documentPickerWasCancelled(_: UIDocumentPickerViewController) { retryClientRestoration() }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        applyComposerSendGlides(to: cell)
        if case .message(let displayedMessageID) = dataSource.itemIdentifier(for: indexPath) {
            prefetchedPlaybackFiles[displayedMessageID] = nil
        }
        guard case .message(let displayedMessageID) = dataSource.itemIdentifier(for: indexPath),
              let cell = cell as? MessageCell,
              let row = currentBoundRenderRow(cell)
        else { return }
        for owner in inlineVideoPlaybackOwners(for: row).values {
            if cell.restoreInlineVideoPlaybackOwner(owner) {
                pendingInlineVideoOwnerReturns.remove(owner.messageID)
            }
        }
        cell.setMediaPlaybackVisible(
            presentedViewController == nil,
            allowsInlineVideoPlayback: false,
        )
        applyPendingQuoteHighlight(to: cell, displayedMessageID: displayedMessageID)
        updateInlineVideoPlaybackVisibility()
        acknowledgeCommittedVisibleMessages(requestHistory: true)
    }

    func collectionView(
        _: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt _: IndexPath,
    ) {
        (cell as? MessageCell)?.setMediaPlaybackVisible(false)
        DispatchQueue.main.async { [weak self] in
            self?.pruneInlineVideoPlaybackOwners()
            self?.updateInlineVideoPlaybackVisibility()
            self?.acknowledgeCommittedVisibleMessages()
        }
    }

    func collectionView(_: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard case .message(let displayedMessageID) = dataSource.itemIdentifier(for: indexPath),
                  let message = message(for: displayedMessageID),
                  prefetchTasks[displayedMessageID] == nil
            else { continue }
            let messages = message.album.isEmpty ? [message.message] : message.album
            mediaRevealSession?.reconcile(messages)
            let permits = Dictionary(uniqueKeysWithValues: messages.compactMap { item in
                mediaRevealSession?.permit(for: item).map { (item.id, $0) }
            })
            let client = chatVM.client
            let generation = UUID()
            let entry = PrefetchTaskEntry(generation: generation)
            prefetchTasks[displayedMessageID] = entry
            let playbackFileIDs = messages.flatMap(TDMediaPrefetcher.playbackFileIDs(in:))
            if !playbackFileIDs.isEmpty { prefetchedPlaybackFiles[displayedMessageID] = (client, playbackFileIDs) }
            entry.task = Task { [weak self] in
                for item in messages where !Task.isCancelled {
                    await TDMediaPrefetcher.prefetch(message: item, client: client, revealPermit: permits[item.id])
                }
                await MainActor.run {
                    guard self?.prefetchTasks[displayedMessageID]?.generation == generation else { return }
                    self?.prefetchTasks[displayedMessageID] = nil
                }
            }
        }
    }

    func collectionView(_: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard case .message(let id) = dataSource.itemIdentifier(for: indexPath) else { continue }
            prefetchTasks[id]?.task?.cancel()
            prefetchTasks[id] = nil
            if let files = prefetchedPlaybackFiles.removeValue(forKey: id),
               !collectionView.indexPathsForVisibleItems.contains(indexPath)
            {
                let client = files.client
                Task {
                    for fileID in files.fileIDs {
                        _ = try? await client.cancelDownloadFile(fileId: fileID, onlyIfPending: true)
                    }
                }
            }
        }
    }

    func beginMessageSearch() {
        guard presentationMode == .full else { return }
        customNavigationBar.beginSearch()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer else { return true }
        var touchedView = touch.view
        while let current = touchedView, current !== collectionView {
            if current is UIControl { return false }
            touchedView = current.superview
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // ChatMessageBubbleItemNode opens no message menu while a poll's new answer is typed.
        gestureRecognizer !== messageContextGesture || pollAddOptionFocusMessageID == nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        // The message press is exclusive: when it begins, UIKit fails the history tap and pans still possible.
        gestureRecognizer !== messageContextGesture && otherGestureRecognizer !== messageContextGesture
    }

    /// Telegram uses a two-finger vertical selection pan. UIKit owns gesture tracking,
    /// range reversal and edge scrolling; the chat keeps one shared selection model.
    func collectionView(_: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        // Same eligibility as the menu's Select: a read-only topic offers no selection.
        guard presentationMode == .full, !messageSearchActive, !chatVM.isReadOnlyTopic,
              case .message(let id) = dataSource.itemIdentifier(for: indexPath),
              let message = message(for: id) else { return false }
        return canSelectMessage(message)
    }

    func collectionView(_: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        guard case .message(let id) = dataSource.itemIdentifier(for: indexPath) else { return }
        selectionInteractionActive = true
        selectionInteractionHitLimit = nil
        if !isSelectingMessages { beginMessageSelection(with: id, selectInitialMessage: false) }
    }

    func collectionViewDidEndMultipleSelectionInteraction(_: UICollectionView) {
        selectionInteractionActive = false
        if selectedDisplayedMessageIDs.isEmpty { endMessageSelection() }
        if let count = selectionInteractionHitLimit {
            selectionInteractionHitLimit = nil
            presentSelectionLimitAlert(count: count)
        }
    }

    func collectionView(_: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard isSelectingMessages,
              case .message(let id) = dataSource.itemIdentifier(for: indexPath),
              let message = message(for: id), canSelectMessage(message) else { return false }
        let count = sourceMessageIDs(forDisplayedMessageIDs: selectedDisplayedMessageIDs.union([id])).count
        guard count > 100 else { return true }
        if selectionInteractionActive {
            selectionInteractionHitLimit = max(selectionInteractionHitLimit ?? 0, count)
        } else {
            presentSelectionLimitAlert(count: count)
        }
        return false
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard isSelectingMessages, case .message(let id) = dataSource.itemIdentifier(for: indexPath) else { return }
        selectionCapabilityTask?.cancel()
        selectionCapabilityTask = nil
        selectionCapabilityGeneration = nil
        selectedDisplayedMessageIDs.insert(id)
        updateMessageSelectionChrome(reconfigureIDs: [id])
    }

    func collectionView(_: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard isSelectingMessages, case .message(let id) = dataSource.itemIdentifier(for: indexPath) else { return }
        selectionCapabilityTask?.cancel()
        selectionCapabilityTask = nil
        selectionCapabilityGeneration = nil
        selectedDisplayedMessageIDs.remove(id)
        if selectedDisplayedMessageIDs.isEmpty, !selectionInteractionActive {
            endMessageSelection()
        } else {
            updateMessageSelectionChrome(reconfigureIDs: [id])
        }
    }

    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard canRestoreClient(source) else { return nil }
        guard let prepared = preparedClient, prepared.source == source else {
            prepareClientMetadata(source)
            return nil
        }
        guard let history = chatVM.historyRestorationState(),
              let transfer = chatVM.prepareComposerRestoration() else { return nil }
        let composer = restoredViewport?.pending == true && !restorationFocusAttempted
            ? restoredComposerState
            : isViewLoaded ? composerView.clientRestorationState() : restoredComposerState
        let anchor = isViewLoaded ? captureSnapshotAnchor() : nil
        let anchorID = anchor?.itemID.displayedMessageID.flatMap { message(for: $0)?.message.id }
        let previous = restoredViewport?.pending == true ? restoredViewport : nil
        let viewport = ChatClientRestorationViewport(
            source: source, messageID: previous?.messageID ?? anchorID,
            pixelOffset: previous?.pixelOffset ?? anchor?.minYRelativeToViewport ?? 0,
            keepsLatest: previous?.keepsLatest ?? (!isViewLoaded || isNearLatest),
            fallbackOffset: previous?.fallbackOffset ?? (isViewLoaded ? collectionView.contentOffset.y : 0),
        )
        let destination = ChatLocation(
            accountID: source.accountID, chatID: location.chatID, clientID: source.clientID, topic: location.topic,
        )
        return PreparedClientNavigationReplacement(
            preflight: { [weak self] in self?.canRestoreClient(source) == true },
            commit: { [self] in
                guard canRestoreClient(source),
                      let replacementVM = ChatVM.restoringComposer(
                          from: transfer, customChat: prepared.chat, location: destination, forumTopic: prepared.topic,
                          history: history, visibleMessageIDs: [viewport.messageID].compactMap(\.self),
                          client: prepared.client,
                      ) else { return nil }
                // No rejection after ownership moved. The coordinator installs
                // the returned controller unconditionally in this exact slot.
                clientOwnerRetired = true
                timelineSnapshots.retire()
                _ = importBarrier.retire()
                cancellables.removeAll()
                messageCancellables.removeAll()
                if isViewLoaded { composerView.retireClientView() }
                let cover = isViewLoaded && view.window != nil
                    ? historyContainerView.snapshotView(afterScreenUpdates: false)
                    : nil
                let bannerCover = isViewLoaded && view.window != nil && !pinnedMessageBanner.isHidden
                    && pinnedMessageBannerHeightConstraint.constant > 0
                    ? pinnedMessageBanner.snapshotView(afterScreenUpdates: false)
                    : nil
                return ChatViewController(
                    chatVM: replacementVM, tdlib: tdlib, viewport: viewport, composer: composer, historyCover: cover,
                    pinnedBannerCover: bannerCover,
                )
            },
        )
    }

    func makeProfile(
        customChat: CustomChat, restoration: PeerProfileRestorationState? = nil,
    ) -> PeerProfileViewController? {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent,
              let accountID = location.accountID, customChat.id == location.chatID,
              restoration.map({ $0.matches(
                  accountID: accountID, actorID: tdlib.activeAccount?.userID,
                  chatID: location.chatID, topic: location.topic,
              ) }) != false else { return nil }
        let profile = PeerProfileViewController(
            customChat: customChat,
            topic: location.topic,
            client: chatVM.client,
            accountID: accountID,
            restoration: restoration,
        )
        profile.onOpenMessage = { [weak self, weak profile] messageID in
            guard let self, chatVM.locationContextIsCurrent, routeIsRetained,
                  let profile, navigationController?.topViewController === profile else { return }
            profile.navigationController?.popViewController(animated: true)
            DispatchQueue.main.async { [weak self] in
                guard let self, chatVM.locationContextIsCurrent, routeIsRetained,
                      navigationController?.topViewController === self else { return }
                scrollToMessage(id: messageID)
            }
        }
        profile.onPrepareGalleryReturn = { [weak self] messageID in
            guard let self, await prepareGalleryReturn(to: messageID), let navigationController else { return false }
            navigationController.popToViewController(self, animated: false)
            return true
        }
        profile.galleryReturnTarget = { [weak self] messageID in
            self?.galleryReturnTarget(for: messageID)
        }
        profile.onGalleryReturnCompleted = { [weak self] messageID in
            self?.highlightMessage(id: messageID)
        }
        profile.onSearch = { [weak self, weak profile] in
            guard let self, chatVM.locationContextIsCurrent, routeIsRetained,
                  let profile, navigationController?.topViewController === profile else { return }
            profile.navigationController?.popViewController(animated: true)
            DispatchQueue.main.async { [weak self] in
                guard let self, chatVM.locationContextIsCurrent, routeIsRetained,
                      navigationController?.topViewController === self else { return }
                beginMessageSearch()
            }
        }
        return profile
    }

    func canRestoreProfile(_ state: PeerProfileRestorationState, source: TdUpdateSource) -> Bool {
        navigationClientSource == source && chatVM.locationContextIsCurrent && chatListActionOwnerIsAttached
            && state.matches(
                accountID: source.accountID,
                actorID: tdlib.activeAccount?.userID,
                chatID: location.chatID,
                topic: location.topic,
            )
    }

    #if DEBUG
        func viewportProbeSample(anchor requestedAnchor: ChatTimelineItemID?) -> ChatViewportCompletionProbe.Sample? {
            guard isViewLoaded, let dataSource, let accountID = location.accountID,
                  let anchor = requestedAnchor ?? captureSnapshotAnchor(ensuringLayout: false)?.itemID,
                  let path = dataSource.indexPath(for: anchor),
                  let attributes = collectionView.layoutAttributesForItem(at: path) else { return nil }
            let insets = collectionView.adjustedContentInset
            let minimum = -insets.top
            let maximum = max(minimum, collectionView.contentSize.height - collectionView.bounds.height + insets.bottom)
            return .init(
                source: .init(accountID: accountID, clientID: location.clientID),
                ownerCurrent: !clientOwnerRetired && chatVM.locationContextIsCurrent
                    && view.window != nil && navigationController?.topViewController === self,
                ready: didPerformInitialScroll && !hasPendingMessageNavigation && restoredViewport?.pending != true
                    && !keyboardIsChanging && !isSelectingMessages && !messageSearchActive
                    && presentedViewController == nil && pendingComposerSendTransitions.isEmpty
                    && activeComposerSendAnimations == 0 && pendingDeleteSnapshotWorkItem == nil
                    && !selfSizingAnchorRestoreScheduled && pendingSelfSizingRestoration == nil
                    && viewportCompletionLayoutDepth == 0 && transitionCoordinator == nil
                    && navigationController?.transitionCoordinator == nil && !isNearLatest,
                scrolling: userIsScrollingTimeline,
                layoutDepth: timelineLayoutMutationDepth,
                ids: dataSource.snapshot().itemIdentifiers,
                anchor: anchor,
                anchorFrame: attributes.frame,
                offset: collectionView.contentOffset,
                size: collectionView.bounds.size,
                contentSize: collectionView.contentSize,
                insets: insets,
                minimumOffset: minimum,
                maximumOffset: maximum,
            )
        }

        func viewportProbeApplySnapshot() {
            updateSnapshot(animated: true)
        }

        func viewportProbeMove(to offset: CGPoint, invalidatingByDrag: Bool) {
            if invalidatingByDrag { scrollViewWillBeginDragging(collectionView) }
            collectionView.setContentOffset(offset, animated: false)
            collectionView.layoutIfNeeded()
            if invalidatingByDrag { scrollViewDidEndDragging(collectionView, willDecelerate: false) }
        }

        private func messageNavigationGeometryValues(
            _ diagnostic: ChatMessageNavigationGeometry,
            desiredOffset: CGFloat?, animated: Bool?, keepsLatest: Bool?, checkDelay: Double?,
        ) -> [String: Double] {
            let displayed = chatVM.displayedMessageID(containing: diagnostic.messageID)
            let path = displayed.flatMap { dataSource.indexPath(for: .message($0)) }
            let attributes = path.flatMap { collectionView.layoutAttributesForItem(at: $0) }
            let insets = collectionView.adjustedContentInset
            let visible = collectionView.indexPathsForVisibleItems
            let viewport = CGRect(
                x: collectionView.contentOffset.x, y: collectionView.contentOffset.y + insets.top,
                width: collectionView.bounds.width,
                height: max(0, collectionView.bounds.height - insets.top - insets.bottom),
            )
            let mappedMessage = displayed.flatMap { message(for: $0) }
            let mappedMessageContainsTarget = mappedMessage?.sourceMessages
                .contains { $0.id == diagnostic.messageID } == true
            let presentationBoundsY = collectionView.layer.presentation()?.bounds.minY ?? collectionView.bounds.minY
            var values: [String: Double] = [
                "sourceCurrent": tdlib.activeUpdateSource == diagnostic.source ? 1 : 0,
                "ownerCurrent": !clientOwnerRetired && chatVM.locationContextIsCurrent ? 1 : 0,
                "windowAttached": view.window != nil ? 1 : 0,
                "controllerIsTop": navigationController?.topViewController === self ? 1 : 0,
                "initialScrollCompleted": didPerformInitialScroll ? 1 : 0,
                "pendingNavigation": hasPendingMessageNavigation ? 1 : 0,
                "pendingClientViewport": restoredViewport?.pending == true ? 1 : 0,
                "layoutDepth": Double(timelineLayoutMutationDepth),
                "tracking": collectionView.isTracking ? 1 : 0,
                "dragging": collectionView.isDragging ? 1 : 0,
                "decelerating": collectionView.isDecelerating ? 1 : 0,
                "nearLatest": isNearLatest ? 1 : 0,
                "offsetX": collectionView.contentOffset.x,
                "offsetY": collectionView.contentOffset.y,
                "presentationBoundsY": Double(presentationBoundsY),
                "contentWidth": collectionView.contentSize.width,
                "contentHeight": collectionView.contentSize.height,
                "viewportWidth": collectionView.bounds.width,
                "viewportHeight": collectionView.bounds.height,
                "insetTop": insets.top,
                "insetBottom": insets.bottom,
                "snapshotCount": Double(dataSource.snapshot().numberOfItems),
                "visibleCount": Double(visible.count),
                "visibleIndexMin": Double(visible.map(\.item).min() ?? -1),
                "visibleIndexMax": Double(visible.map(\.item).max() ?? -1),
                "targetMapped": displayed != nil ? 1 : 0,
                "targetSnapshotMember": path != nil ? 1 : 0,
                "targetIndex": Double(path?.item ?? -1),
                "targetSection": Double(path?.section ?? -1),
                "targetVisible": path.map { visible.contains($0) } == true ? 1 : 0,
                "targetCellPresent": path.flatMap { collectionView.cellForItem(at: $0) } != nil ? 1 : 0,
                "targetIntersectsViewport": attributes?.frame.intersects(viewport) == true ? 1 : 0,
                "mappingMatchesCommand": diagnostic.commandTarget.map { $0 == displayed } == true ? 1 : 0,
                "mappedMessageContainsTarget": mappedMessageContainsTarget ? 1 : 0,
            ]
            if let attributes {
                values["targetMinY"] = attributes.frame.minY
                values["targetHeight"] = attributes.frame.height
                values["targetCenterY"] = attributes.center.y
                let centerOffset = (collectionView.bounds.height + insets.top - insets.bottom) / 2
                let maximum = max(
                    -insets.top,
                    collectionView.contentSize.height - collectionView.bounds.height + insets.bottom,
                )
                let currentTargetOffset = min(max(attributes.center.y - centerOffset, -insets.top), maximum)
                values["currentTargetOffset"] = currentTargetOffset
                values["currentTargetOffsetError"] = collectionView.contentOffset.y - currentTargetOffset
            }
            if let desiredOffset { values["commandOffset"] = desiredOffset }
            if let animated { values["animated"] = animated ? 1 : 0 }
            if let keepsLatest { values["keepsLatest"] = keepsLatest ? 1 : 0 }
            if let checkDelay { values["checkDelaySeconds"] = checkDelay }
            return values
        }
    #endif

    /// Telegram's reply keyboard buttons (ChatControllerInteraction): the phone and location requests ask first and
    /// then send as a reply to the keyboard's message (shareAccountContact, shareCurrentLocation); the users and chat
    /// requests open the picker (openRequestedPeerSelection); text buttons send at once.
    private func handleReplyKeyboardButton(_ button: TDNativeKeyboardButton, keyboardMessageID: Int64) {
        let chatVM = chatVM
        switch button.type {
        case .keyboardButtonTypeRequestPhoneNumber:
            confirmKeyboardRequest(
                title: "Conversation.ShareBotContactConfirmationTitle",
                message: "Conversation.ShareBotContactConfirmation",
            ) {
                Task {
                    guard let content = await chatVM.ownContactContent() else { return }
                    await chatVM.sendKeyboardRequest(content, keyboardMessageID: keyboardMessageID)
                }
            }
        case .keyboardButtonTypeRequestLocation:
            confirmKeyboardRequest(
                title: "Conversation.ShareBotLocationConfirmationTitle",
                message: "Conversation.ShareBotLocationConfirmation",
            ) { [weak self] in
                Task { [weak self] in
                    guard let coordinate = await OneShotLocation.current() else {
                        self?.presentKeyboardRequestFailure()
                        return
                    }
                    await chatVM.sendKeyboardRequest(
                        .inputMessageLocation(TDNativeInputMessageLocation(location: TDNativeLocation(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            horizontalAccuracy: 0,
                        ))),
                        keyboardMessageID: keyboardMessageID,
                    )
                }
            }
        case .keyboardButtonTypeRequestUsers(let users):
            presentBotPeerRequest(.users(users), keyboardMessageID: keyboardMessageID)
        case .keyboardButtonTypeRequestChat(let chat):
            presentBotPeerRequest(.chat(chat), keyboardMessageID: keyboardMessageID)
        case .keyboardButtonTypeRequestPoll(let poll):
            presentRequestedPoll(
                forcedQuiz: poll.forceQuiz ? true : poll.forceRegular ? false : nil,
                keyboardMessageID: keyboardMessageID,
            )
        case .keyboardButtonTypeWebApp(let webApp):
            inlineKeyboardActions.openKeyboardWebApp(
                url: webApp.url,
                buttonText: button.text,
                keyboardMessageID: keyboardMessageID,
                chatID: chatVM.location.chatID,
                client: chatVM.client,
            )
        default:
            Task { await chatVM.pressReplyKeyboardButton(button, keyboardMessageID: keyboardMessageID) }
        }
    }

    private func confirmKeyboardRequest(title: String, message: String, perform: @escaping () -> Void) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.telegram(title),
            message: L10n.telegram(message),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { _ in perform() })
        present(alert, animated: true)
    }

    /// ChatButtonKeyboardInputNode's `setupPoll`: the poll creator in the kind the bot asks for, sent like the
    /// attachment menu's poll (`openPollCreation(nil, isQuiz)`).
    private func presentRequestedPoll(forcedQuiz: Bool?, keyboardMessageID: Int64) {
        guard presentedViewController == nil, chatVM.canCreatePoll,
              chatVM.replyKeyboard.offeredKeyboard?.messageID == keyboardMessageID else { return }
        let poll = CreatePollViewController(
            isChannel: chatVM.createsChannelPoll,
            client: chatVM.client,
            forcedQuiz: forcedQuiz,
            accountID: chatVM.accountID,
            chatID: chatVM.chatID,
        ) { [weak chatVM] content in
            Task { await chatVM?.sendAttachmentContents([content], kind: .poll) }
        }
        poll.onDismiss = { [weak self] in self?.attachmentSheetDidDismiss() }
        present(poll.makeNavigationController(), animated: true)
    }

    /// The attachment menu's Checklist (`.todo`): ComposeTodoScreen for a Telegram Premium account, which sends the
    /// checklist with the composer's reply; without Premium, Telegram's checklist notice.
    private func showChecklistComposer() {
        guard chatVM.canCreateChecklist else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let isPremium = await chatVM.accountHasPremium(), chatVM.locationContextIsCurrent,
                  chatVM.canCreateChecklist, presentedViewController == nil
            else {
                attachmentSheetDidDismiss()
                return
            }
            guard isPremium else {
                presentChecklistPremiumNotice { [weak self] in self?.attachmentSheetDidDismiss() }
                return
            }
            let composer = ChecklistComposerViewController(
                client: chatVM.client,
                accountID: chatVM.accountID,
                chatID: chatVM.chatID,
            ) { [weak chatVM = self.chatVM] outcome in
                guard case .checklist(let checklist) = outcome else { return }
                let content = InputMessageContent
                    .inputMessageChecklist(TDNativeInputMessageChecklist(checklist: checklist))
                Task { await chatVM?.sendAttachmentContents([content], kind: .checklist) }
            }
            composer.onDismiss = { [weak self] in self?.attachmentSheetDidDismiss() }
            present(composer.makeNavigationController(), animated: true)
        }
    }

    private func presentKeyboardRequestFailure() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: nil, message: L10n.telegram("Login.UnknownError"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    private func presentBotPeerRequest(_ request: BotPeerRequestViewController.Request, keyboardMessageID: Int64) {
        // The bot is the keyboard's sender; in its own chat, the chat itself.
        let sender = chatVM.messages.first { $0.sourceMessages.contains { $0.id == keyboardMessageID } }?.senderUser
        let botName = sender.map { $0.firstName.isEmpty ? $0.lastName : $0.firstName } ?? chatVM.customChat.displayTitle
        BotPeerRequestViewController.present(
            request,
            source: .keyboardButtonSourceMessage(TDNativeKeyboardButtonSourceMessage(
                chatId: chatVM.chatID,
                messageId: keyboardMessageID,
            )),
            botName: botName,
            from: self,
        ) { [weak self] in self?.chatVM.noteKeyboardRequestAnswered(keyboardMessageID: keyboardMessageID) }
    }

    /// Telegram's Scheduled Messages for this chat or topic, from the input panel's button or after a message was
    /// scheduled (ChatController.openScheduledMessages).
    private func openScheduledMessages() {
        guard presentationMode == .full, chatVM.locationContextIsCurrent,
              navigationController?.topViewController === self else { return }
        navigationController?.pushViewController(
            ScheduledMessagesViewController(
                location: location,
                isReminders: chatVM.customChat.isSavedMessages,
                canSendWhenOnline: chatVM.canSendWhenOnline,
            ),
            animated: true,
        )
    }

    /// The send menu's Schedule Message: Telegram's date picker, then the composer goes out at that time.
    private func presentScheduleMessagePicker(mediaMode: ComposerMediaSendMode = .grouped) {
        guard presentationMode == .full, chatVM.locationContextIsCurrent, chatVM.canScheduleMessages else { return }
        ScheduleMessagePickerViewController.present(
            from: self,
            isReminder: chatVM.customChat.isSavedMessages,
            showsSendWhenOnline: chatVM.canSendWhenOnline,
        ) { [weak self] state in
            guard let self, chatVM.locationContextIsCurrent else { return }
            composerView.send(options: ChatVM.sendOptions(schedulingState: state), mediaMode: mediaMode)
        }
    }

    private func acknowledgeCommittedVisibleMessages(requestHistory: Bool = false) {
        guard !timelineSnapshots.isBusy, timelineSourceIsCurrent else { return }
        #if DEBUG
            // Diagnostic motion must not issue read receipts or demand more history.
            if viewportCompletionProbe?.isExercising == true { return }
        #endif
        guard viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive,
              chatListActionOwnerIsAttached
        else {
            acknowledgedVisibleRawIDs.removeAll()
            return
        }
        var visibleIDs = Set<Int64>()
        var tailIDs = Set<Int64>()
        var visibleDisplayedIDs = Set<DisplayedMessageID>()
        let tailRows = Set(chatVM.messages.suffix(5).map(\.displayedID))
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? MessageCell,
                  let row = currentBoundRenderRow(cell),
                  timelineSnapshots.committed.rows[.message(row.value.displayedID)]?.message === row else { continue }
            let ids = Set(row.value.sourceMessages.map(\.id))
            visibleIDs.formUnion(ids)
            visibleDisplayedIDs.insert(row.value.displayedID)
            if tailRows.contains(row.value.displayedID) { tailIDs.formUnion(ids) }
        }
        if requestHistory { chatVM.loadHistoryGaps(near: visibleDisplayedIDs) }
        // A context preview may page history, but must never acknowledge it read.
        if presentationMode == .contextPreview {
            acknowledgedVisibleRawIDs.removeAll()
            if requestHistory, !tailIDs.isEmpty { chatVM.loadMessages() }
            return
        }
        guard navigationController?.topViewController === self, presentedViewController == nil,
              !isTerminatingNavigation
        else {
            acknowledgedVisibleRawIDs.removeAll()
            return
        }
        acknowledgedVisibleRawIDs.formIntersection(visibleIDs)
        let newlyVisible = visibleIDs.subtracting(acknowledgedVisibleRawIDs)
        acknowledgedVisibleRawIDs.formUnion(newlyVisible)
        if !newlyVisible.isEmpty { chatVM.viewMessages(ids: Array(newlyVisible)) }
        if requestHistory, !tailIDs.isEmpty { chatVM.loadMessages() }
    }

    private func openProfile() {
        guard presentationMode == .full,
              navigationController?.topViewController === self
        else { return }
        abandonRestoredViewport()
        guard let profile = makeProfile(customChat: chatVM.customChat) else { return }
        navigationController?.pushViewController(profile, animated: true)
    }

    /// Telegram's forum More menu while the forum reads as messages (ChatListControllerImpl.openMoreMenu,
    /// isViewingAsTopics: false, from ChatController). Add Member needs a member picker BetterTG lacks.
    private func showForumMoreMenu(from source: UIView) {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent,
              presentedViewController == nil, navigationController?.topViewController === self else { return }
        var actions = [
            TelegramContextMenuAction(title: L10n.telegram("Chat.ContextViewAsTopics"), image: UIImage()) {
                [weak self] in self?.viewForumAsTopics()
            },
            TelegramContextMenuAction(
                title: L10n.telegram("Chat.ContextViewAsMessages"),
                image: UIImage(systemName: "checkmark"),
            ),
            TelegramContextMenuAction(
                title: L10n.telegram("GroupInfo.Title"),
                image: UIImage(systemName: "person.2"),
                startsNewSection: true,
            ) { [weak self] in self?.openProfile() },
            TelegramContextMenuAction(
                title: L10n.telegram("Conversation.Search"),
                image: UIImage(systemName: "magnifyingglass"),
                startsNewSection: true,
            ) { [weak self] in self?.customNavigationBar.beginSearch() },
        ]
        // After Search, without another separator, as Telegram adds New Topic for a ChatController source.
        if chatVM.customChat.canCreateForumTopics {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.CreateTopic"),
                image: UIImage(systemName: "square.and.pencil"),
            ) { [weak self] in self?.presentCreateTopic() })
        }
        presentTelegramContextMenu(sourceView: source, actions: actions, presentationStyle: .sourceMorph)
    }

    private func presentCreateTopic() {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent,
              presentedViewController == nil else { return }
        ForumCreateTopicViewController.present(
            from: self,
            customChat: chatVM.customChat,
            location: location,
            client: chatVM.client,
            canOpen: { [weak self] in
                guard let self else { return false }
                return routeIsRetained && chatVM.locationContextIsCurrent
                    && navigationController?.topViewController === self
            },
        )
    }

    /// Telegram replaces the forum's history with its topic list and stores the choice on the server.
    private func viewForumAsTopics() {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent else { return }
        let client = chatVM.client
        let location = location
        let chatID = location.chatID
        Task { [weak self] in
            guard await (try? client.send(TDNativeRequests.toggleChatViewAsTopics(chatId: chatID, viewAsTopics: true)))
                != nil,
                let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client),
                chat.chat.viewAsTopics, let self, routeIsRetained, chatVM.locationContextIsCurrent,
                let navigationController,
                let index = navigationController.viewControllers.firstIndex(where: { $0 === self })
            else { return }
            var stack = navigationController.viewControllers
            stack[index] = ForumTopicsViewController(customChat: chat, location: location, client: client)
            navigationController.setViewControllers(stack, animated: false)
        }
    }

    private func canRestoreClient(_ source: TdUpdateSource) -> Bool {
        guard presentationMode == .full, routeIsRetained, source == tdlib.activeUpdateSource,
              source.accountID == location.accountID, source.clientID != location.clientID,
              RootVM.shared.activeAccountID == source.accountID, importBarrier.isQuiescent,
              !isTerminatingNavigation, presentedViewController == nil, transitionCoordinator == nil,
              !isPresentingTelegramContextMenu, !keyboardIsChanging, videoNoteRecorder == nil,
              !voiceGestureDefersSystemGestures, !isSelectingMessages, !messageSearchActive,
              messageNavigationTask == nil, metadataNavigationTask == nil,
              pendingScrollMessageID == nil, pendingComposerSendTransitions.isEmpty, activeComposerSendAnimations == 0,
              pendingDeleteSnapshotDeadline == nil, timelineLayoutMutationDepth == 0, !timelineSnapshots.isBusy,
              !selfSizingAnchorRestoreScheduled else { return false }
        guard isViewLoaded else { return true }
        return !collectionView.isTracking && !collectionView.isDragging && !collectionView.isDecelerating
            && !messageContextGesture.isPressing && composerView.clientRestorationState() != nil
    }

    private func prepareClientMetadata(_ source: TdUpdateSource) {
        guard clientPreparationSource != source else { return }
        clientPreparationTask?.cancel()
        clientPreparationSource = source
        let client = tdlib.activeClient
        guard client.id == source.clientID else { return }
        clientPreparationTask = Task { [weak self] in
            guard let self else { return }
            let chat = await RootVM.shared.getCustomChatForNavigation(from: location.chatID, client: client)
            guard !Task.isCancelled, routeIsRetained, tdlib.activeUpdateSource == source,
                  RootVM.shared.activeAccountID == source.accountID, let chat else { return }
            let topic: ForumTopic?
            if let id = location.forumTopicID {
                topic = try? await client.getForumTopic(chatId: location.chatID, forumTopicId: id)
                guard topic != nil else { return }
            } else { topic = nil }
            guard !Task.isCancelled, routeIsRetained, tdlib.activeUpdateSource == source,
                  clientPreparationSource == source, RootVM.shared.activeAccountID == source.accountID else { return }
            preparedClient = (source, client, chat, topic)
            clientPreparationTask = nil
            retryClientRestoration()
        }
    }

    private func retryClientRestoration() {
        guard !clientOwnerRetired, !clientRetryScheduled,
              tdlib.activeAccountID == location.accountID, tdlib.activeClient.id != location.clientID else { return }
        cancelMessageNavigation()
        clientRetryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            clientRetryScheduled = false
            NavigationStorage.shared.retryClientRestoration()
        }
    }

    /// Pasted and camera images join the composer as the media picker's picks do: up to MediaPickerScreen's 100, sent
    /// in albums of ten.
    private func importImages(_ images: [UIImage]) {
        guard let token = importBarrier.begin() else { return }
        let barrier = importBarrier
        Task { [self] in
            let selected = await Task.detached(priority: .userInitiated) {
                SelectedDocumentFileStore.removeExpiredFiles()
                return images.prefix(100).compactMap { writeImage($0) }
            }.value
            finishImageImport(selected, token: token, barrier: barrier)
        }
    }

    /// True when the import reached the composer.
    @discardableResult private func finishImageImport(
        _ images: [SelectedImage],
        token: ChatComposerImportBarrier.Token,
        barrier: ChatComposerImportBarrier,
    ) -> Bool {
        let accepted = barrier
            .finish(token, currentAccountID: tdlib.activeAccountID, routeIsRetained: routeIsRetained) {
                guard !images.isEmpty else { return }
                chatVM.discardDisplayedDocuments()
                chatVM.replaceDisplayedImages(images)
            }
        if !accepted {
            let urls = images.flatMap(\.fileURLs)
            Task.detached { SelectedDocumentFileStore.removeUnleased(urls) }
        }
        return accepted
    }

    private func abandonRestoredViewport() {
        guard restoredViewport?.pending == true else { return }
        restoredViewport?.invalidate()
        restoredComposerState = nil
        removeRestoredHistoryCover()
        chatVM.beginRestoredHistoryRefresh()
    }

    private func removeRestoredHistoryCover() {
        guard let cover = restoredHistoryCover else { return }
        restoredHistoryCover = nil
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState]) {
            cover.alpha = 0
        } completion: { _ in cover.removeFromSuperview() }
    }

    private func settleRestoredViewport() {
        guard !timelineSnapshots.isBusy, !hasPendingMessageNavigation, restoredViewport?.pending == true, isViewLoaded,
              view.window != nil,
              navigationController?.topViewController === self, presentedViewController == nil,
              chatVM.locationContextIsCurrent else { return }
        if !restorationFocusAttempted, restoredViewport?.appeared == true {
            restorationFocusAttempted = true
            if let composer = restoredComposerState { composerView.restoreClientViewState(composer, focus: true) }
            view.setNeedsLayout()
            DispatchQueue.main.async { [weak self] in
                self?.restorationFocusSettled = true
                self?.settleRestoredViewport()
            }
            return
        }
        guard restorationFocusSettled else { return }
        guard restoredViewport?.take(
            currentSource: tdlib.activeUpdateSource,
            hasLayout: collectionView.bounds.height > 0 && timelineLayoutMutationDepth == 0
                && (chatVM.messages.isEmpty || collectionView.contentSize.height > 0),
            keyboardChanging: keyboardIsChanging,
        ) == true, let viewport = restoredViewport else { return }
        recordMessageNavigationGeometry("client-viewport-restore", keepsLatest: viewport.keepsLatest)
        collectionView.layoutIfNeeded()
        if viewport.keepsLatest { pinToLatestEdge(animated: false) }
        else if let id = viewport.messageID, let displayed = chatVM.displayedMessageID(containing: id) {
            landSnapshotAnchor(.init(itemID: .message(displayed), minYRelativeToViewport: viewport.pixelOffset))
        } else {
            let minimum = -collectionView.adjustedContentInset.top
            let maximum = max(
                minimum,
                collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset
                    .bottom,
            )
            recordMessageNavigationGeometry(
                "client-fallback-before", desiredOffset: min(max(viewport.fallbackOffset, minimum), maximum),
                writer: "client-fallback",
            )
            collectionView.setContentOffset(
                .init(x: 0, y: min(max(viewport.fallbackOffset, minimum), maximum)),
                animated: false,
            )
            recordMessageNavigationGeometry("client-fallback-after")
        }
        didPerformInitialScroll = true
        restoredComposerState = nil
        removeRestoredHistoryCover()
        updateScrollToLatestButtonVisibility(animated: true)
        #if DEBUG
            log("Chat client restoration: viewport settled; fresh history starts")
        #endif
        chatVM.beginRestoredHistoryRefresh()
    }

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(80),
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 5
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        return ChatTimelineLayout(section: section)
    }

    private func configureNavigationBar() {
        navigationBackground.translatesAutoresizingMaskIntoConstraints = false
        navigationBackground.isUserInteractionEnabled = false
        view.addSubview(navigationBackground)
        customNavigationBar.useSharedBackground()
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        customNavigationBar.onBack = presentationMode == .full ? { NavigationStorage.shared.pop() } : nil
        customNavigationBar.onProfile = presentationMode == .full ? { [weak self] in self?.openProfile() } : nil
        if presentationMode == .full, chatVM.isAllMessagesForum {
            customNavigationBar.setShowsMoreButton(true)
            customNavigationBar.onMore = { [weak self] source in self?.showForumMoreMenu(from: source) }
        }
        if presentationMode == .full, location.forumTopicID != nil {
            customNavigationBar.setAvatarMenuActions { [weak self] in self?.topicAvatarMenuActions() ?? [] }
        }
        customNavigationBar.onSelectionCancel = { [weak self] in
            self?.endMessageSelection()
        }
        customNavigationBar.onSearchQueryChange = { [weak self] query in
            self?.messageSearchQueryChanged(query)
        }
        customNavigationBar.onSearchMemberScopeCleared = { [weak self] previous in
            self?.messageSearchMemberScopeCleared(previous)
        }
        customNavigationBar.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            messageSearchActive = active
            navigationBarHeightConstraint.constant = view.safeAreaInsets.top + customNavigationBar.visibleContentHeight
            if active { abandonRestoredViewport() }
            else { retryClientRestoration() }
            composerView.setHiddenForSearch(active)
            updateScrollToLatestButtonVisibility(animated: true)
            if !active {
                resetMessageSearch()
                customNavigationBar.setSearchResultFound(nil)
            }
            setMessageSearchPanelVisible(active)
            view.setNeedsLayout()
            updatePinnedMessageBanner(animated: true)
        }
        if presentationMode == .contextPreview {
            customNavigationBar.isUserInteractionEnabled = false
            customNavigationBar.setBackButtonHidden(true)
        }
        view.addSubview(customNavigationBar)
        navigationBarHeightConstraint = customNavigationBar.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + customNavigationBar.visibleContentHeight,
        )
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
        configurePinnedMessageBanner()
        updateChatHeader()
        updateStatus()
    }

    private func configurePinnedMessageBanner() {
        voicePlaybackHeader.translatesAutoresizingMaskIntoConstraints = false
        voicePlaybackHeader.isHidden = true
        view.addSubview(voicePlaybackHeader)
        voicePlaybackHeaderHeightConstraint = voicePlaybackHeader.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            voicePlaybackHeader.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            voicePlaybackHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            voicePlaybackHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            voicePlaybackHeaderHeightConstraint,
        ])
        configureVoicePlaybackHeader()
        liveLocationPanel.translatesAutoresizingMaskIntoConstraints = false
        liveLocationPanel.isHidden = true
        view.addSubview(liveLocationPanel)
        liveLocationPanelHeightConstraint = liveLocationPanel.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            liveLocationPanel.topAnchor.constraint(equalTo: voicePlaybackHeader.bottomAnchor),
            liveLocationPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            liveLocationPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            liveLocationPanelHeightConstraint,
        ])
        configureLiveLocationPanel()
        pinnedMessageBanner.translatesAutoresizingMaskIntoConstraints = false
        pinnedMessageBanner.isHidden = true
        view.addSubview(pinnedMessageBanner)
        pinnedMessageBannerHeightConstraint = pinnedMessageBanner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            pinnedMessageBanner.topAnchor.constraint(equalTo: liveLocationPanel.bottomAnchor),
            pinnedMessageBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pinnedMessageBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pinnedMessageBannerHeightConstraint,
        ])
        topicReopenBar.translatesAutoresizingMaskIntoConstraints = false
        topicReopenBar.isHidden = true
        topicReopenBar.onReopen = { [weak self] in self?.reopenTopic() }
        view.addSubview(topicReopenBar)
        topicReopenBarHeightConstraint = topicReopenBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            topicReopenBar.topAnchor.constraint(equalTo: pinnedMessageBanner.bottomAnchor),
            topicReopenBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topicReopenBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topicReopenBarHeightConstraint,
            navigationBackground.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBackground.bottomAnchor.constraint(equalTo: topicReopenBar.bottomAnchor),
        ])
        if let cover = restoredPinnedBannerCover {
            cover.isUserInteractionEnabled = false
            // Pinned to the banner's edges: the banner is still zero-sized here, and resizing masks would add its
            // whole final size to the snapshot's.
            cover.translatesAutoresizingMaskIntoConstraints = false
            pinnedMessageBanner.addSubview(cover)
            NSLayoutConstraint.activate([
                cover.topAnchor.constraint(equalTo: pinnedMessageBanner.topAnchor),
                cover.leadingAnchor.constraint(equalTo: pinnedMessageBanner.leadingAnchor),
                cover.trailingAnchor.constraint(equalTo: pinnedMessageBanner.trailingAnchor),
                cover.bottomAnchor.constraint(equalTo: pinnedMessageBanner.bottomAnchor),
            ])
            pinnedMessageBanner.isHidden = false
            pinnedMessageBannerHeightConstraint.constant = PinnedMessageBannerView.contentHeight
        }
        updatePinnedMessageBanner(animated: false)
    }

    /// Telegram's playback header sits under the navigation bar while a voice note of this account is loaded; one of
    /// another chat keeps the text its own chat gave it, and opens there (ChatControllerNode's media panel).
    private func configureVoicePlaybackHeader() {
        voicePlaybackHeader.onTogglePlayback = { Media.shared.togglePlayback() }
        voicePlaybackHeader.onCycleRate = { Media.shared.cyclePlaybackRate() }
        voicePlaybackHeader.onClose = { Media.shared.close() }
        voicePlaybackHeader.onPlayNext = { Media.shared.swipeTrack(toNext: true) }
        voicePlaybackHeader.onPlayPrevious = { Media.shared.swipeTrack(toNext: false) }
        voicePlaybackHeader.onOpen = { [weak self] in
            guard let self, let item = Media.shared.nowPlaying, item.accountID == location.accountID else { return }
            // MediaPlaybackHeaderPanelComponent's tapAction opens OverlayAudioPlayerController for music.
            if item.isMusic {
                MusicPlayerViewController.present(from: self)
                return
            }
            navigate(to: .message(chatID: item.chatID, messageID: item.messageID, quote: nil))
        }
        Publishers.CombineLatest4(
            Media.shared.$nowPlaying,
            Media.shared.$isPlaying,
            Media.shared.$playbackPosition,
            Media.shared.$playbackRate,
        )
        .combineLatest(Media.shared.$nowPlayingDisplay)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] playback, display in
            self?.updateVoicePlaybackHeader(
                nowPlaying: playback.0,
                display: display,
                isPlaying: playback.1,
                position: playback.2,
                rate: playback.3,
            )
        }
        .store(in: &cancellables)
        if presentationMode == .full, voicePlaylistKey == nil {
            let key = VoicePlaylistContinuation.ChatKey(accountID: location.accountID, chatID: chatVM.chatID)
            voicePlaylistKey = key
            VoicePlaylistContinuation.shared.register(key)
        }
        Media.shared
            .playbackFinished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] finished in
                // Music plays on through VoicePlaylistContinuation, open chat or not.
                guard let self, !finished.isMusic, !finished.isFile, finished.chatID == chatVM.chatID,
                      finished.accountID == location.accountID else { return }
                playNextPlaylistItem(after: finished.messageID)
            }
            .store(in: &cancellables)
        VideoNotePlaybackView.playbackFinished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] finished in
                guard let self, finished.chatID == chatVM.chatID,
                      finished.source == navigationClientSource else { return }
                playedListenableMessageIDs.insert(finished.messageID)
                playNextPlaylistItem(after: finished.messageID)
            }
            .store(in: &cancellables)
    }

    /// Telegram's live location panel in a chat (LocationBroadcastNavigationAccessoryPanel in peer mode) while the
    /// account shares its live location here: tapping it opens the location viewer, and close asks before stopping.
    private func configureLiveLocationPanel() {
        liveLocationPanel.configure(subtitle: L10n.telegram("Conversation.LiveLocationYou"), isAccent: true)
        liveLocationPanel.onOpen = { [weak self] in
            guard let self, let broadcast = liveLocationBroadcast else { return }
            openLiveLocationMessage(broadcast)
        }
        liveLocationPanel.onClose = { [weak self] in self?.confirmStopLiveLocation() }
        LiveLocationManager.shared
            .$broadcasts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] broadcasts in self?.updateLiveLocationPanel(broadcasts) }
            .store(in: &cancellables)
    }

    private func updateLiveLocationPanel(_ broadcasts: [LiveLocationBroadcast]) {
        guard liveLocationPanelHeightConstraint != nil else { return }
        let broadcast = presentationMode == .full
            ? broadcasts.first(where: { $0.source.matches(location) && $0.chatID == chatVM.chatID })
            : nil
        liveLocationBroadcast = broadcast
        let desiredHeight = broadcast == nil ? 0 : LiveLocationPanelView.contentHeight
        guard abs(liveLocationPanelHeightConstraint.constant - desiredHeight) > 0.5 else { return }
        if broadcast != nil { liveLocationPanel.isHidden = false }
        liveLocationPanelHeightConstraint.constant = desiredHeight
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) {
            self.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self else { return }
            liveLocationPanel.isHidden = liveLocationPanelHeightConstraint.constant == 0
            updateHistoryInsets()
        }
    }

    /// LiveLocationHeaderPanelComponent's close in a chat: Stop Sharing Location, then cancelLiveLocation.
    private func confirmStopLiveLocation() {
        guard let broadcast = liveLocationBroadcast else { return }
        let sheet = LiveLocationPanelView.stopSheet(sourceView: liveLocationPanel) {
            LiveLocationManager.shared.stop(chatID: broadcast.chatID, source: broadcast.source)
        }
        view.endEditing(true)
        present(sheet, animated: true)
    }

    /// LiveLocationHeaderPanelComponent's presentLiveLocationController: the account's live location message opens in
    /// the location viewer, which shows every live location in the chat.
    private func openLiveLocationMessage(_ broadcast: LiveLocationBroadcast) {
        let client = chatVM.client
        liveLocationOpenTask?.cancel()
        liveLocationOpenTask = Task { [weak self] in
            let message = try? await client.getMessage(chatId: broadcast.chatID, messageId: broadcast.messageID)
            guard let self, !Task.isCancelled, let message, let subject = LocationViewSubject(message: message),
                  liveLocationBroadcast?.messageID == broadcast.messageID else { return }
            liveLocationOpenTask = nil
            presentLocationViewer(subject, showsAllLiveLocations: true)
        }
    }

    /// Telegram's voice playlist (`.voiceOrInstantVideo`, OpenChatMessage) continues with the chat's next voice
    /// note or instant video when one ends; the history scrolls to a next instant video (ChatHistoryListNode).
    /// Self-destructing notes stay out of it: they only play in their play-once overlay.
    private func playNextPlaylistItem(after finishedID: Int64) {
        guard presentationMode == .full, chatVM.locationContextIsCurrent else { return }
        let candidates = chatVM.messages.flatMap { $0.album.isEmpty ? [$0.message] : $0.album }
        guard let next = candidates
            .filter({ $0.id > finishedID && $0.selfDestructType == nil })
            .filter({
                switch $0.content {
                case .messageVoiceNote: true
                case .messageVideoNote(let content): !content.isSecret
                default: false
                }
            })
            .min(by: { $0.id < $1.id })
        else {
            voicePlaylistEnded()
            return
        }
        playListenableMessage(next)
    }

    /// OpenChatMessage for a voice note or instant video, as the playlist and Raise to Listen open them.
    private func playListenableMessage(_ next: Message) {
        if case .messageVideoNote = next.content {
            guard let source = navigationClientSource else { return }
            scrollToMessage(id: next.id)
            VideoNotePlaybackView.requestPlaylistPlayback(.init(
                source: source,
                chatID: next.chatId,
                messageID: next.id,
            ))
            return
        }
        guard case .messageVoiceNote(let content) = next.content else { return }
        let client = chatVM.client
        let item = Media.NowPlaying(accountID: location.accountID, chatID: next.chatId, messageID: next.id)
        Task { [weak self] in
            guard let file = try? await client.downloadFile(
                fileId: content.voiceNote.voice.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            ), file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }
            guard let self, chatVM.locationContextIsCurrent, TDLib.shared.activeClient.id == client.id,
                  Media.shared.savedMediaPath.isEmpty else { return }
            Media.shared.toggle(with: file.local.path, duration: content.voiceNote.duration, item: item)
            if !next.isOutgoing, !content.isListened {
                _ = try? await client.openMessageContent(chatId: next.chatId, messageId: next.id)
            }
        }
    }

    // MARK: Raise to Listen

    /// ChatControllerImpl sets up raiseToListen once the chat appears; it runs while the chat is on screen and the
    /// app is in the foreground (canReadHistory).
    private func setUpRaiseToListen() {
        guard presentationMode == .full else { return }
        if raiseToListen == nil {
            raiseToListen = RaiseToListenActivator(
                shouldActivate: { [weak self] in self?.raiseToListenShouldActivate() ?? false },
                activate: { [weak self] in self?.activateRaiseGesture() },
                deactivate: { [weak self] in self?.deactivateRaiseGesture() },
            )
            NotificationCenter.default
                .publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in
                    guard let self else { return }
                    raiseToListen?.applicationResignedActive()
                    raiseToListen?.isEnabled = false
                }
                .store(in: &cancellables)
            NotificationCenter.default
                .publisher(for: UIApplication.willEnterForegroundNotification)
                .sink { [weak self] _ in
                    guard let self else { return }
                    raiseToListen?.isEnabled = isChatVisible
                }
                .store(in: &cancellables)
            Media.shared
                .$nowPlaying
                .compactMap(\.self)
                .sink { [weak self] item in
                    guard let self, !item.isMusic, item.chatID == chatVM.chatID,
                          item.accountID == location.accountID else { return }
                    playedListenableMessageIDs.insert(item.messageID)
                }
                .store(in: &cancellables)
        }
        raiseToListen?.isEnabled = UIApplication.shared.applicationState != .background
    }

    /// RaiseToListenManager's shouldActivate: Raise to Listen is on, the chat is the top screen with nothing over it,
    /// nothing plays or records, no message is being edited, and there is a note to hear or a voice reply to record.
    private func raiseToListenShouldActivate() -> Bool {
        guard RaiseToListenSettings.isEnabled, isChatVisible, chatVM.locationContextIsCurrent,
              navigationController?.topViewController === self, presentedViewController == nil,
              chatVM.editCustomMessage == nil, Media.shared.nowPlaying == nil,
              !chatVM.recordingVoiceNote, videoNoteRecorder == nil
        else { return false }
        if firstMessageToListen() != nil { return true }
        return showsComposer && !messageSearchActive && !isSelectingMessages && chatVM.canRecordVoiceNote
    }

    /// firstLoadedMessageToListen: the oldest loaded incoming voice note or instant video not yet listened to.
    /// Self-destructing notes open only in their play-once overlay, so they wait for a tap.
    private func firstMessageToListen() -> Message? {
        var oldest: Message?
        for item in chatVM.messages {
            for message in item.album.isEmpty ? [item.message] : item.album {
                guard isMessageToListen(message), oldest.map({ message.id < $0.id }) ?? true else { continue }
                oldest = message
            }
        }
        return oldest
    }

    private func isMessageToListen(_ message: Message) -> Bool {
        guard !message.isOutgoing, message.selfDestructType == nil,
              !playedListenableMessageIDs.contains(message.id) else { return false }
        switch message.content {
        case .messageVoiceNote(let content): return !content.isListened
        case .messageVideoNote(let content): return !content.isViewed && !content.isSecret
        default: return false
        }
    }

    /// activateRaiseGesture: the note to listen to plays. Without one a voice recording starts after its tone,
    /// at least a second after the voice playlist ran out.
    private func activateRaiseGesture() {
        raiseToListenRecordingTask?.cancel()
        raiseToListenRecordingTask = nil
        if let message = firstMessageToListen() {
            playedListenableMessageIDs.insert(message.id)
            playListenableMessage(message)
            return
        }
        let delay = max(0, voicePlaylistDidEndTimestamp + 1 - CACurrentMediaTime())
        raiseToListenRecordingTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self, raiseToListen?.isActivated == true else { return }
            Media.shared.setAudioSessionRecord()
            await RecordingTone.play()
            guard !Task.isCancelled, raiseToListen?.isActivated == true else {
                Media.shared.endAudioSessionRecord()
                return
            }
            let started = await composerView.startRaisedVoiceRecording()
            // The phone left the ear while the recording started.
            if started, raiseToListen?.isActivated != true { chatVM.pauseVoiceRecording() }
        }
    }

    /// deactivateRaiseGesture: a recording about to start is called off, and one in progress stops into its preview
    /// (dismissMediaRecorder(.pause)). A playing note pauses on its own through Media.
    private func deactivateRaiseGesture() {
        raiseToListenRecordingTask?.cancel()
        raiseToListenRecordingTask = nil
        guard chatVM.recordingVoiceNote, chatVM.voiceRecordingInteractionState == .locked else { return }
        chatVM.pauseVoiceRecording()
    }

    /// setTempVoicePlaylistEnded: once the notes run out, a phone still at the ear records the reply.
    private func voicePlaylistEnded() {
        guard let raiseToListen, chatVM.canRecordVoiceNote else { return }
        voicePlaylistDidEndTimestamp = CACurrentMediaTime()
        raiseToListen.activateBasedOnProximity()
    }

    private func updateVoicePlaybackHeader(
        nowPlaying: Media.NowPlaying?,
        display: Media.NowPlayingDisplay?,
        isPlaying: Bool,
        position: TimeInterval,
        rate: Float,
    ) {
        guard voicePlaybackHeaderHeightConstraint != nil else { return }
        let item = nowPlaying.flatMap { item in
            presentationMode == .full && item.accountID == location.accountID ? item : nil
        }
        let text: Media.NowPlayingDisplay? = item.flatMap { item in
            let recorded = display?.item == item ? display : nil
            guard item.chatID == chatVM.chatID else { return recorded }
            // A poll's audio keeps the track's text its poll gave it.
            if item.isFile, let recorded { return recorded }
            let message = chatVM.messages.first { message in
                message.id == item.messageID || message.album.contains { $0.id == item.messageID }
            }
            // Another route of this chat (a thread, a topic) that hasn't loaded the note keeps the recorded text.
            if message == nil, let recorded { return recorded }
            let played = message?.album.first { $0.id == item.messageID } ?? message?.message
            let local: Media.NowPlayingDisplay =
                if case .messageAudio(let content) = played?.content {
                    .music(content.audio, item: item)
                } else {
                    Media.NowPlayingDisplay(
                        item: item,
                        title: voicePlaybackTitle(message),
                        subtitle: voicePlaybackSubtitle(),
                    )
                }
            if message != nil { Media.shared.setDisplay(local) }
            return local
        }
        if let text {
            let duration = Media.shared.playbackDuration
            voicePlaybackHeader.configure(.init(
                title: text.title,
                subtitle: text.subtitle,
                isPlaying: isPlaying,
                progress: duration > 0 ? CGFloat(position / duration) : 0,
                rate: rate,
                showsRate: text.showsRate,
                isMusic: text.item.isMusic,
            ))
        }
        let desiredHeight = text == nil ? 0 : VoicePlaybackHeaderView.contentHeight
        guard abs(voicePlaybackHeaderHeightConstraint.constant - desiredHeight) > 0.5 else { return }
        if text != nil { voicePlaybackHeader.isHidden = false }
        voicePlaybackHeaderHeightConstraint.constant = desiredHeight
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) {
            self.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self else { return }
            voicePlaybackHeader.isHidden = voicePlaybackHeaderHeightConstraint.constant == 0
            updateHistoryInsets()
        }
    }

    /// MediaHeaderItemNode's voice title: the author's name, or the chat's for a channel post.
    private func voicePlaybackTitle(_ message: CustomMessage?) -> String {
        if let user = message?.senderUser { return ServiceMessageText.displayTitle(user) }
        return chatVM.customChat.displayTitle
    }

    /// "Voice Message" in private chats and channels; a group's title in groups.
    private func voicePlaybackSubtitle() -> String {
        switch chatVM.customChat.chat.type {
        case .chatTypeBasicGroup:
            chatVM.customChat.displayTitle
        case .chatTypeSupergroup(let supergroup) where !supergroup.isChannel:
            chatVM.customChat.displayTitle
        default:
            L10n.telegram("MusicPlayer.VoiceNote")
        }
    }

    private func configureCollectionView() {
        historyContainerView.translatesAutoresizingMaskIntoConstraints = false
        historyContainerView.transform = CGAffineTransform(scaleX: 1, y: -1)
        view.addSubview(historyContainerView)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.keyboardDismissMode = presentationMode == .full ? .interactive : .none
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.topEdgeEffect.isHidden = true
        collectionView.bottomEdgeEffect.isHidden = true
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(MessageCell.self, forCellWithReuseIdentifier: MessageCell.reuseIdentifier)
        collectionView.register(
            ForumTopicRunHeaderCell.self,
            forCellWithReuseIdentifier: ForumTopicRunHeaderCell.reuseIdentifier,
        )
        collectionView.register(
            ChatDateHeaderCell.self,
            forCellWithReuseIdentifier: ChatDateHeaderCell.reuseIdentifier,
        )
        collectionView.register(
            ChatReplyCountCell.self,
            forCellWithReuseIdentifier: ChatReplyCountCell.reuseIdentifier,
        )
        collectionView.register(ChatBotInfoCell.self, forCellWithReuseIdentifier: ChatBotInfoCell.reuseIdentifier)
        if presentationMode == .full {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(historyTapped(_:)))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delegate = self
            collectionView.addGestureRecognizer(tapGesture)
            messageContextGesture.delegate = self
            collectionView.addGestureRecognizer(messageContextGesture)
        }
        historyContainerView.addSubview(collectionView)
        if let restoredHistoryCover {
            // Inside the flipped container, as the snapshot was taken, so it draws the old frame unchanged.
            restoredHistoryCover.isUserInteractionEnabled = false
            restoredHistoryCover.frame = historyContainerView.bounds
            restoredHistoryCover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            historyContainerView.addSubview(restoredHistoryCover)
        }
        var constraints = [
            historyContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            historyContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            historyContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            historyContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.topAnchor.constraint(equalTo: historyContainerView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: historyContainerView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: historyContainerView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: historyContainerView.bottomAnchor),
        ]
        if showsComposer {
            view.keyboardLayoutGuide.usesBottomSafeArea = false
            composerView.onOpenAttachments = { [weak self] in self?.showAttachmentSheet() }
            composerView.onExpandMediaSearch = { [weak self] mode in
                self?.showComposerMediaPicker(mode: mode, expandedSearch: true)
            }
            composerView.onPasteImages = { [weak self] in self?.importImages($0) }
            composerView.onInteractionSettled = { [weak self] in self?.retryClientRestoration() }
            composerView.onUserInteraction = { [weak self] in self?.abandonRestoredViewport() }
            composerView.onNavigateToMessage = { [weak self] target in self?.navigate(to: target) }
            composerView.onChangeForwardRecipient = { [weak self] forward in
                self?.presentForwardPicker(
                    request: forward.prepared.request,
                    initialMode: forward.mode,
                    replacingForwardID: forward.id,
                )
            }
            composerView.onOpenReplyOptions = { [weak self] source in self?.presentReplyOptions(from: source) }
            composerView.onScheduleMessage = { [weak self] in self?.presentScheduleMessagePicker() }
            composerView.suggestedStickerPeekActions = { [weak self] sticker in
                self?.suggestedStickerPeekActions(sticker) ?? []
            }
            composerView.stickerPeekSendActions = { [weak self] sticker in
                guard let self else { return [] }
                let chatVM = chatVM
                return stickerPeekSendActions(sticker) { sticker, options in
                    Task { await chatVM.sendSticker(sticker, options: options) }
                }
            }
            composerView.onOpenScheduledMessages = { [weak self] in self?.openScheduledMessages() }
            composerView.onOpenBotMenuWebApp = { [weak self] button in self?.openBotMenuWebApp(button) }
            composerView.onVoiceGestureActivityChange = { [weak self] active in
                guard let self, voiceGestureDefersSystemGestures != active else { return }
                voiceGestureDefersSystemGestures = active
                setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
                if !active { retryClientRestoration() }
            }
            composerView.onConfirmVoiceTrimResume = { [weak self] in
                self?.confirmVoiceTrimAndResume()
            }
            composerView.onStartVideoNoteRecording = { [weak self] in
                await self?.beginVideoNoteRecording() ?? false
            }
            composerView.onCancelVideoNoteRecording = { [weak self] in
                self?.videoNoteRecorder?.cancel()
            }
            composerView.onLockVideoNoteRecording = { [weak self] in
                self?.videoNoteRecorder?.lockRecording()
            }
            composerView.onPauseVideoNoteRecording = { [weak self] in
                self?.videoNoteRecorder?.finishForPreview()
            }
            composerView.onRecordMoreVideoNoteRecording = { [weak self] in
                self?.videoNoteRecorder?.recordMore()
            }
            composerView.onSendVideoNoteRecording = { [weak self] in
                self?.videoNoteRecorder?.finishForSend()
            }
            composerView.onToggleVideoNotePreview = { [weak self] in
                self?.videoNoteRecorder?.togglePreviewPlayback()
            }
            composerView.onViewOnceEnabled = { [weak self] text in self?.showChatToast(text) }
            composerView.onUpdateVideoNoteTrim = { [weak self] start, end, updatedEnd, finished in
                self?.videoNoteRecorder?.updateTrim(
                    start: start,
                    end: end,
                    updatedEnd: updatedEnd,
                    finished: finished,
                )
            }
            composerView.onReplyKeyboardButton = { [weak self] button, messageID in
                guard let self, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
                handleReplyKeyboardButton(button, keyboardMessageID: messageID)
            }
            view.addSubview(composerKeyboardEdgeView)
            view.addSubview(composerView)
            let leadingConstraint = composerView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            let trailingConstraint = composerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            let bottomConstraint = composerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
            composerLeadingConstraint = leadingConstraint
            composerTrailingConstraint = trailingConstraint
            composerBottomConstraint = bottomConstraint
            constraints.append(contentsOf: [
                leadingConstraint,
                trailingConstraint,
                bottomConstraint,
                composerKeyboardEdgeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                composerKeyboardEdgeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                composerKeyboardEdgeView.topAnchor.constraint(equalTo: composerView.topAnchor, constant: -20),
                // Telegram extends the edge material behind the keyboard, through its rounded corners.
                composerKeyboardEdgeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        if presentationMode == .full {
            configureScrollToLatestButton(bottomAnchor: showsComposer
                ? composerView.topAnchor
                : view.safeAreaLayoutGuide.bottomAnchor)
            configureMessageSelectionToolbar()
            configureMessageSearchPanel()
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func configureMessageSearchPanel() {
        messageSearchPanel.translatesAutoresizingMaskIntoConstraints = false
        messageSearchPanel.isHidden = true
        messageSearchPanel.alpha = 0
        messageSearchPanel.onCalendar = { [weak self] in self?.presentMessageSearchCalendar() }
        messageSearchPanel.onMembers = { [weak self] in self?.beginMessageSearchMemberChoice() }
        messageSearchPanel.onOlder = { [weak self] in
            self?.customNavigationBar.dismissSearchKeyboard()
            self?.messageSearch.showOlder()
        }
        messageSearchPanel.onNewer = { [weak self] in
            self?.customNavigationBar.dismissSearchKeyboard()
            self?.messageSearch.showNewer()
        }
        messageSearchPanel.onDisplayMode = { [weak self] in self?.toggleMessageSearchListMode() }
        view.addSubview(messageSearchPanel)
        // The controls sit on the keyboard, or on the safe area while it is hidden; the material reaches the bottom.
        let keyboardAttachment = messageSearchPanel.contentBottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor,
        )
        keyboardAttachment.priority = .defaultHigh
        let safeAreaAttachment = messageSearchPanel.contentBottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
        )
        safeAreaAttachment.priority = UILayoutPriority(UILayoutPriority.defaultHigh.rawValue - 1)
        NSLayoutConstraint.activate([
            messageSearchPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageSearchPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageSearchPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            messageSearchPanel.contentBottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor),
            messageSearchPanel.contentBottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
            keyboardAttachment,
            safeAreaAttachment,
        ])
    }

    private func configureMessageSelectionToolbar() {
        messageSelectionToolbar.translatesAutoresizingMaskIntoConstraints = false
        messageSelectionToolbar.isHidden = true
        messageSelectionToolbar.alpha = 0
        messageSelectionToolbar.onDelete = { [weak self] in
            self?.prepareSelectedMessagesForDeletion()
        }
        messageSelectionToolbar.onForward = { [weak self] in
            self?.forwardSelectedMessages()
        }
        view.addSubview(messageSelectionToolbar)
        messageSelectionToolbarHeightConstraint = messageSelectionToolbar.heightAnchor.constraint(
            equalToConstant: MessageSelectionToolbar.contentHeight + view.safeAreaInsets.bottom,
        )
        NSLayoutConstraint.activate([
            messageSelectionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageSelectionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageSelectionToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            messageSelectionToolbarHeightConstraint,
        ])
    }

    private func confirmVoiceTrimAndResume() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.betterTG("Voice.TrimAlertTitle"),
            message: L10n.betterTG("Voice.TrimAlertText"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert
            .addAction(UIAlertAction(
                title: L10n.betterTG("Voice.TrimAndContinue"),
                style: .destructive,
            ) { [weak self] _ in
                self?.chatVM.resumeVoiceRecording(confirmingTrim: true)
            })
        present(alert, animated: true)
    }

    private func beginVideoNoteRecording() async -> Bool {
        if let videoNoteRecorder {
            return await videoNoteRecorder.beginHolding()
        }
        // Like the photo camera, check for a camera before starting capture. Without one (the Simulator), AVCapture
        // reports a runtime error and the user saw "capture stopped unexpectedly" instead of the camera being absent.
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentVideoNoteErrorIfNeeded(L10n.betterTG("VideoNote.CameraUnavailable"))
            return false
        }
        guard let context = try? chatVM.resolveSendContext(
            for: .videoNote,
            replyingTo: chatVM.replyMessage,
            useCurrentReplyOverride: true,
        ) else { return false }
        videoNoteReplyMessage = chatVM.replyMessage
        videoNoteReplyInput = context.replyTo
        videoNoteSendTopic = context.destinationTopic
        composerView.setVideoNoteReplyContext(message: videoNoteReplyMessage, input: videoNoteReplyInput)
        let recorder = installVideoNoteRecorder()
        return await recorder.beginHolding()
    }

    private func installVideoNoteRecorder(
        restoring restoredDraft: VideoNoteRecordingDraft? = nil,
        restoredReply: CustomMessage? = nil,
    ) -> VideoNoteRecorderViewController {
        let replySnapshot = restoredDraft == nil ? videoNoteReplyMessage : restoredReply
        let replyInput = restoredDraft?.replyTo ?? videoNoteReplyInput ?? chatVM.getMessageReplyTo(from: replySnapshot)
        let sendTopic = restoredDraft?.sendTopic ?? videoNoteSendTopic
        videoNoteReplyInput = replyInput
        videoNoteSendTopic = sendTopic
        composerView.setVideoNoteReplyContext(message: replySnapshot, input: replyInput)
        let recorder = VideoNoteRecorderViewController(
            chatID: chatVM.chatID,
            draftKey: chatVM.location.draftKey,
            replyMessageID: restoredDraft?.replyMessageID ?? replySnapshot?.id,
            replyTo: replyInput,
            sendTopic: sendTopic,
        )
        recorder.onStateChange = { [weak self, weak recorder] state in
            guard let self, videoNoteRecorder === recorder else { return }
            composerView.updateVideoNoteState(state)
            switch state {
            case .holding, .locked:
                if let recorder { RecordingIdleTimer.hold(recorder) }
                if !videoNoteChatActionActive {
                    videoNoteChatActionActive = true
                    // TDLib expires a chat action after a few seconds; Telegram repeats it while recording.
                    videoNoteChatActionTask = Task { [weak self] in
                        while !Task.isCancelled {
                            guard let self, videoNoteChatActionActive else { return }
                            _ = try? await chatVM.tdSendFrozenMediaChatAction(
                                .chatActionRecordingVideoNote,
                                sendTopic: videoNoteSendTopic,
                                replyTo: videoNoteReplyInput,
                            )
                            try? await Task.sleep(for: .seconds(4))
                        }
                    }
                }
            case .failed(let message):
                if let recorder { RecordingIdleTimer.release(recorder) }
                stopVideoNoteChatAction()
                presentVideoNoteErrorIfNeeded(message)
            case .idle, .preview, .sending:
                if let recorder { RecordingIdleTimer.release(recorder) }
                stopVideoNoteChatAction()
            case .preparing, .stopping:
                break
            }
        }
        recorder.onError = { [weak self] message in
            self?.presentVideoNoteRetryErrorIfNeeded(message)
        }
        recorder.onPreviewData = { [weak self] draft, thumbnails in
            self?.composerView.updateVideoNotePreview(draft: draft, thumbnails: thumbnails)
        }
        recorder.onThumbnailData = { [weak self] thumbnails, segmentIDs in
            self?.composerView.updateVideoNoteThumbnails(thumbnails, segmentIDs: segmentIDs)
        }
        recorder.onDiscard = { [weak chatVM] asset in
            if let chatVM {
                await chatVM.discardVideoNoteAsset(asset)
            } else {
                await VideoNoteFileStore.shared.discardAsset(at: asset.url)
            }
        }
        recorder.onSubmit = {
            [weak self, weak chatVM] asset,
            thumbnail,
            originRecordingDraftID,
            storedReplyMessageID,
            storedReplyTo in
            guard let self, let chatVM else {
                return .retained(
                    asset,
                    originConsumed: false,
                    message: L10n.betterTG("VideoNote.ChatClosed"),
                )
            }
            let transitionID = UUID()
            prepareComposerSendTransition(ComposerSendTransitionRequest(
                id: transitionID,
                kind: .videoNote,
            ))
            let result = await chatVM.submitVideoNote(
                asset,
                thumbnail: thumbnail,
                originRecordingDraftID: originRecordingDraftID,
                replyingTo: replySnapshot,
                storedReplyMessageID: storedReplyMessageID,
                storedReplyTo: storedReplyTo,
                storedSendTopic: sendTopic,
            )
            switch result {
            case .enqueued(let messageID):
                if let messageID {
                    acceptComposerSendTransition(ComposerSendTransitionAcceptance(
                        id: transitionID,
                        messageIDs: [messageID],
                    ))
                } else {
                    cancelComposerSendTransition(id: transitionID)
                }
            case .retained:
                cancelComposerSendTransition(id: transitionID)
            }
            return result
        }
        recorder.onDismiss = { [weak self, weak recorder] in
            guard let self, let recorder, videoNoteRecorder === recorder else { return }
            recorder.willMove(toParent: nil)
            recorder.view.removeFromSuperview()
            recorder.removeFromParent()
            RecordingIdleTimer.release(recorder)
            videoNoteRecorder = nil
            stopVideoNoteChatAction()
            videoNoteReplyMessage = nil
            videoNoteReplyInput = nil
            videoNoteSendTopic = nil
            composerView.setVideoNoteReplyContext(message: nil, input: nil)
            composerView.updateVideoNoteState(.idle)
        }

        addChild(recorder)
        recorder.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recorder.view)
        NSLayoutConstraint.activate([
            recorder.view.topAnchor.constraint(equalTo: view.topAnchor),
            recorder.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            recorder.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            recorder.view.bottomAnchor.constraint(equalTo: composerView.topAnchor),
        ])
        recorder.didMove(toParent: self)
        videoNoteRecorder = recorder
        if let restoredDraft {
            recorder.restore(restoredDraft)
        }
        return recorder
    }

    private func restoreVideoRecordingIfNeeded() {
        guard showsComposer,
              !isTerminatingNavigation,
              videoNoteRecorder == nil,
              let draft = chatVM.restoredVideoRecordingDraft,
              restoredVideoRecordingDraftIDHandled != draft.id
        else { return }
        restoredVideoRecordingDraftIDHandled = draft.id
        videoNoteReplyMessage = chatVM.restoredVideoRecordingReplyMessage
        videoNoteReplyInput = draft.replyTo
        videoNoteSendTopic = draft.sendTopic
        composerView.setVideoNoteReplyContext(message: videoNoteReplyMessage, input: videoNoteReplyInput)
        _ = installVideoNoteRecorder(
            restoring: draft,
            restoredReply: videoNoteReplyMessage,
        )
        chatVM.consumeRestoredVideoRecordingDraft(id: draft.id)
    }

    private func presentVideoNoteErrorIfNeeded(_ message: String) {
        guard !didPresentVideoNoteError, presentedViewController == nil else { return }
        didPresentVideoNoteError = true
        let alert = UIAlertController(
            title: L10n.telegram("Message.VideoMessage"),
            message: message,
            preferredStyle: .alert,
        )
        if videoNoteRecorder?.hasPersistedRecordingDraft == true {
            alert
                .addAction(UIAlertAction(
                    title: L10n.telegram("ChatImportActivity.Retry"),
                    style: .default,
                ) { [weak self] _ in
                    self?.didPresentVideoNoteError = false
                    self?.videoNoteRecorder?.retryPersistedPreview()
                })
            alert.addAction(UIAlertAction(
                title: L10n.telegram("Conversation.DiscardVoiceMessageAction"),
                style: .destructive,
            ) { [weak self] _ in
                self?.didPresentVideoNoteError = false
                self?.videoNoteRecorder?.cancel()
            })
            present(alert, animated: true)
            return
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .cancel) { [weak self] _ in
            self?.didPresentVideoNoteError = false
            if self?.videoNoteRecorder?.state.isActive != true {
                self?.videoNoteRecorder?.cancel()
            }
        })
        if Self.videoNoteCapturePermissionDenied {
            alert
                .addAction(UIAlertAction(
                    title: L10n.telegram("AccessDenied.Settings"),
                    style: .default,
                ) { [weak self] _ in
                    self?.didPresentVideoNoteError = false
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    if self?.videoNoteRecorder?.state.isActive != true {
                        self?.videoNoteRecorder?.cancel()
                    }
                })
        }
        present(alert, animated: true)
    }

    private func presentVideoNoteRetryErrorIfNeeded(_ message: String) {
        guard !didPresentVideoNoteError, presentedViewController == nil else { return }
        didPresentVideoNoteError = true
        let alert = UIAlertController(
            title: L10n.telegram("Message.VideoMessage"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            self?.didPresentVideoNoteError = false
        })
        present(alert, animated: true)
    }

    private func stopVideoNoteChatAction() {
        guard videoNoteChatActionActive else { return }
        videoNoteChatActionActive = false
        videoNoteChatActionTask?.cancel()
        videoNoteChatActionTask = nil
        let sendTopic = videoNoteSendTopic
        let replyTo = videoNoteReplyInput
        Task { [weak chatVM] in
            _ = try? await chatVM?.tdSendFrozenMediaChatAction(
                .chatActionCancel,
                sendTopic: sendTopic,
                replyTo: replyTo,
            )
        }
    }

    private func configureScrollToLatestButton(bottomAnchor: NSLayoutYAxisAnchor) {
        scrollToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToLatestButton.setImage(UIImage(systemName: "arrow.down"), for: .normal)
        scrollToLatestButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .bold),
            forImageIn: .normal,
        )
        scrollToLatestButton.tintColor = .label
        scrollToLatestButton.backgroundColor = .secondarySystemBackground
        scrollToLatestButton.layer.cornerRadius = 18
        scrollToLatestButton.layer.borderWidth = 1 / view.traitCollection.displayScale
        scrollToLatestButton.layer.borderColor = UIColor.separator.cgColor
        scrollToLatestButton.layer.shadowColor = UIColor.black.cgColor
        scrollToLatestButton.layer.shadowOpacity = 0.2
        scrollToLatestButton.layer.shadowRadius = 7
        scrollToLatestButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        // A replacement after a client renewal keeps the button its predecessor showed away from the latest edge.
        scrollToLatestButtonVisible = restoredViewport.map { $0.pending && !$0.keepsLatest } ?? false
        scrollToLatestButton.alpha = scrollToLatestButtonVisible ? 1 : 0
        scrollToLatestButton.transform = scrollToLatestButtonVisible
            ? .identity
            : CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.72, y: 0.72)
        scrollToLatestButton.accessibilityLabel = L10n.betterTG("Accessibility.ScrollToLatest")
        scrollToLatestButton.addTarget(self, action: #selector(scrollToLatest), for: .touchUpInside)

        unreadBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        unreadBadgeLabel.backgroundColor = .systemBlue
        unreadBadgeLabel.textColor = .white
        unreadBadgeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        scrollToLatestButton.addSubview(unreadBadgeLabel)
        view.addSubview(scrollToLatestButton)
        NSLayoutConstraint.activate([
            scrollToLatestButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scrollToLatestButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            scrollToLatestButton.widthAnchor.constraint(equalToConstant: 36),
            scrollToLatestButton.heightAnchor.constraint(equalToConstant: 36),
            unreadBadgeLabel.topAnchor.constraint(equalTo: scrollToLatestButton.topAnchor, constant: -7),
            unreadBadgeLabel.centerXAnchor.constraint(equalTo: scrollToLatestButton.centerXAnchor),
            unreadBadgeLabel.heightAnchor.constraint(equalToConstant: 20),
        ])
        configureUnreadJumpButtons()
    }

    /// Telegram's mention and reaction buttons stack above the scroll-to-latest button, or take its place while it is
    /// hidden; a tap jumps to the earliest unread one and a long press offers clearing them all.
    private func configureUnreadJumpButtons() {
        for button in [mentionsButton, reactionsButton] {
            view.addSubview(button)
            button.trailingAnchor.constraint(equalTo: scrollToLatestButton.trailingAnchor).isActive = true
            button.addGestureRecognizer(UILongPressGestureRecognizer(
                target: self, action: #selector(showUnreadJumpMenu(_:)),
            ))
        }
        mentionsButtonBottomConstraint = mentionsButton.bottomAnchor
            .constraint(equalTo: scrollToLatestButton.bottomAnchor)
        reactionsButtonBottomConstraint = reactionsButton.bottomAnchor
            .constraint(equalTo: scrollToLatestButton.bottomAnchor)
        mentionsButtonBottomConstraint?.isActive = true
        reactionsButtonBottomConstraint?.isActive = true
        mentionsButton.addTarget(self, action: #selector(jumpToUnreadMention), for: .touchUpInside)
        reactionsButton.addTarget(self, action: #selector(jumpToUnreadReaction), for: .touchUpInside)
        Publishers.Merge3(
            chatVM.$chatUnreadMentionCount.map { _ in () },
            chatVM.$chatUnreadReactionCount.map { _ in () },
            chatVM.$forumTopic.map { _ in () },
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in DispatchQueue.main.async { self?.updateUnreadJumpButtons(animated: true) } }
        .store(in: &cancellables)
        updateUnreadJumpButtons(animated: false)
    }

    private func updateUnreadJumpButtons(animated: Bool) {
        guard let mentionsButtonBottomConstraint, let reactionsButtonBottomConstraint else { return }
        let allowed = presentationMode == .full && !messageSearchActive && !isSelectingMessages
            && pollAddOptionFocusMessageID == nil
        let mentions = chatVM.unreadMentionCount
        let reactions = chatVM.unreadReactionCount
        mentionsButton.setCount(mentions)
        reactionsButton.setCount(reactions)
        let layout = (
            mentions: allowed && mentions > 0,
            reactions: allowed && reactions > 0,
            latest: scrollToLatestButtonVisible,
        )
        if let unreadJumpLayout, unreadJumpLayout == layout { return }
        unreadJumpLayout = layout
        let step: CGFloat = 36 + 12
        let mentionsOffset = layout.latest ? step : 0
        let reactionsOffset = mentionsOffset + (layout.mentions ? step : 0)
        let changes = {
            mentionsButtonBottomConstraint.constant = -mentionsOffset
            reactionsButtonBottomConstraint.constant = -reactionsOffset
            for (button, visible) in [(self.mentionsButton, layout.mentions), (
                self.reactionsButton,
                layout.reactions,
            )] {
                button.alpha = visible ? 1 : 0
                button.transform = visible ? .identity : ChatHistoryNavigationButton.hiddenTransform
            }
            self.view.layoutIfNeeded()
        }
        mentionsButton.isUserInteractionEnabled = layout.mentions
        reactionsButton.isUserInteractionEnabled = layout.reactions
        guard animated, view.window != nil else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        )
    }

    @objc private func jumpToUnreadMention() {
        jumpToUnread(reactions: false)
    }

    @objc private func jumpToUnreadReaction() {
        jumpToUnread(reactions: true)
    }

    private func jumpToUnread(reactions: Bool) {
        unreadJumpTask?.cancel()
        unreadJumpTask = Task { [weak self] in
            guard let self, let messageID = await chatVM.earliestUnreadMessageID(reactions: reactions),
                  !Task.isCancelled, !clientOwnerRetired else { return }
            unreadJumpTask = nil
            navigate(to: .message(chatID: chatVM.chatID, messageID: messageID, quote: nil))
        }
    }

    @objc private func showUnreadJumpMenu(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? ChatHistoryNavigationButton else { return }
        let action =
            if button === mentionsButton {
                TelegramContextMenuAction(
                    title: L10n.telegram("WebSearch.RecentSectionClear"),
                    image: UIImage(systemName: "checkmark.message"),
                ) { [weak self] in self?.chatVM.readAllMentions() }
            } else {
                TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.ReadAllReactions"),
                    image: UIImage(systemName: "checkmark.message"),
                ) { [weak self] in self?.chatVM.readAllReactions() }
            }
        presentTelegramContextMenu(
            sourceView: button,
            actions: [action],
            tracking: gesture,
            presentationStyle: .sourceMorph,
        )
    }

    private func updateScrollToLatestButtonVisibility(animated: Bool) {
        // Until the restored viewport lands, the offset is not the one the user sees under the history cover.
        guard restoredViewport?.pending != true else { return }
        let isAwayFromLatest = collectionView.contentOffset.y + collectionView.adjustedContentInset.top > 160
        let visible = isAwayFromLatest && !messageSearchActive && !isSelectingMessages
            && pollAddOptionFocusMessageID == nil
        defer { updateUnreadJumpButtons(animated: animated) }
        guard scrollToLatestButtonVisible != visible else { return }
        scrollToLatestButtonVisible = visible
        let changes = {
            self.scrollToLatestButton.alpha = visible ? 1 : 0
            self.scrollToLatestButton.transform = visible
                ? .identity
                : CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.72, y: 0.72)
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: visible ? 0.38 : 0.2,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        )
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, ChatTimelineItemID>(
            collectionView: collectionView,
        ) { [weak self] collectionView, indexPath, itemID in
            switch itemID {
            case .dateHeader(let headerID):
                ChatTimelineCellProvider.dequeue(
                    ChatDateHeaderCell.self, from: collectionView, at: indexPath,
                    reuseIdentifier: ChatDateHeaderCell.reuseIdentifier,
                    configure: { [weak self] cell in
                        guard let self, timelineSourceIsCurrent,
                              case .date = timelineSnapshots.row(for: itemID) else { return false }
                        dateHeaderTitles[headerID] = cell.configure(id: headerID)
                        return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
            case .threadStart:
                ChatTimelineCellProvider.dequeue(
                    ChatReplyCountCell.self, from: collectionView, at: indexPath,
                    reuseIdentifier: ChatReplyCountCell.reuseIdentifier,
                    configure: { [weak self] cell in
                        guard let self, timelineSourceIsCurrent,
                              case .notice(let text) = timelineSnapshots.row(for: itemID) else { return false }
                        cell.configure(text: text)
                        return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
            case .botInfo:
                ChatTimelineCellProvider.dequeue(
                    ChatBotInfoCell.self, from: collectionView, at: indexPath,
                    reuseIdentifier: ChatBotInfoCell.reuseIdentifier,
                    configure: { [weak self] cell in
                        guard let self, timelineSourceIsCurrent,
                              case .botInfo(let info, let client) = timelineSnapshots.row(for: itemID)
                        else { return false }
                        cell.configure(info: info, client: client)
                        return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
            case .topicHeader(let headerID):
                ChatTimelineCellProvider.dequeue(
                    ForumTopicRunHeaderCell.self, from: collectionView, at: indexPath,
                    reuseIdentifier: ForumTopicRunHeaderCell.reuseIdentifier,
                    configure: { [weak self] cell in
                        guard let self, timelineSourceIsCurrent,
                              case .topic(_, let info, let client, let source) = timelineSnapshots.row(for: itemID)
                        else { return false }
                        cell.configure(
                            id: headerID,
                            info: info,
                            client: client,
                            onOpen: { [weak self] in
                                guard let self, timelineSourceIsCurrent, navigationClientSource == source,
                                      timelineSnapshots.committed.ids.contains(itemID) else { return }
                                openForumTopic(id: headerID.topicID)
                            },
                        )
                        return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
            case .message(let displayedMessageID):
                ChatTimelineCellProvider.dequeue(
                    MessageCell.self, from: collectionView, at: indexPath,
                    reuseIdentifier: MessageCell.reuseIdentifier,
                    preserve: { [weak self] cell in
                        self?.timelineSourceIsCurrent == true
                            && self?.timelineSnapshots.canPreserveDeletingCell(cell, id: displayedMessageID) == true
                    },
                    configure: { [weak self] cell in
                        guard let self, timelineSourceIsCurrent,
                              !timelineSnapshots.deleting.contains(displayedMessageID),
                              let row = timelineSnapshots.row(for: itemID)?.message else { return false }
                        let message = row.renderedMessage
                        let authority = ChatMessageActionAuthority(
                            message: row.canonical, cell: cell, source: row.source, location: row.location,
                            selected: row.inputs.selected, renderValue: row.value,
                        )
                        cell.configure(
                            message: message,
                            chat: chatVM.customChat,
                            highlightedMessageID: row.inputs.highlightedMessageID,
                            client: row.client,
                            spoilerSource: row.source,
                            mediaRevealSession: row.mediaRevealSession,
                            pollInteractionStore: row.polls,
                            videoPlaybackOwners: inlineVideoPlaybackOwners(for: row),
                            canAddReactions: row.inputs.canAddReactions,
                            selectionActive: row.inputs.selectionActive,
                            selected: row.inputs.selected,
                            onSwipeToReply: row.inputs.canReply
                                ? { [weak self, weak cell] in
                                    guard let self, let current = currentActionMessage(
                                        authority,
                                        cell: cell,
                                        intent: .reply,
                                    )
                                    else { return }
                                    chatVM.beginReply(to: current)
                                }
                                : nil,
                            onSelectionToggle: row.inputs.selectionActive
                                ? { [weak self, weak cell] in
                                    guard let self,
                                          currentActionMessage(authority, cell: cell, intent: .selection) != nil
                                    else { return }
                                    toggleMessageSelection(displayedMessageID: displayedMessageID)
                                }
                                : nil,
                            onReactionTap: { [weak self, weak cell] type in
                                guard let self, let current = currentActionMessage(
                                    authority,
                                    cell: cell,
                                    intent: .reaction(type),
                                )
                                else { return }
                                chatVM.toggleReaction(on: current, type: type, isBig: false)
                            },
                            onReactionLongPress: { [weak self, weak cell] type in
                                guard let self, let current = currentActionMessage(
                                    authority,
                                    cell: cell,
                                    intent: .reactionList(type),
                                )
                                else { return }
                                MessageInteractionsViewController.present(
                                    .reactions(
                                        isOutgoing: current.message.isOutgoing,
                                        count: current.reactions?.reactions.first { $0.type == type }?.totalCount ?? 0,
                                        type: type,
                                    ),
                                    chatID: current.message.chatId,
                                    messageID: current.id,
                                    from: self,
                                )
                            },
                            onMetadataNavigate: { [weak self, weak cell] target in
                                guard let self,
                                      currentActionMessage(authority, cell: cell, intent: .metadata(target)) != nil
                                else { return }
                                navigate(to: target)
                            },
                            onReplyQuoteExpand: { [weak self, weak cell] in
                                guard let self, let current = currentActionMessage(
                                    authority,
                                    cell: cell,
                                    intent: .quote,
                                )
                                else { return }
                                expandReplyQuote(for: current)
                            },
                            onContentAction: { [
                                weak self,
                                weak cell,
                                weak polls = row.polls,
                            ] action in
                                guard let self,
                                      let current = currentActionMessage(
                                          authority,
                                          cell: cell,
                                          intent: .content(action),
                                      )
                                else {
                                    action.rejectPollSubmission(in: polls)
                                    return
                                }
                                performContentAction(action, for: current)
                            },
                            onMediaTap: { [weak self, weak cell] messages, selection in
                                guard let self, currentActionMessage(authority, cell: cell, intent: .media) != nil
                                else { return }
                                showMedia(messages, selection: selection)
                            },
                            actionBindingID: authority.bindingID,
                            timelineRowID: row.id,
                            showsProfileImage: row.inputs.showsProfileImage,
                            commentsLoading: commentsThreadLoad?.displayedID == displayedMessageID,
                        )
                        cell.setSearchHighlight(query: messageSearchHighlightQuery(for: message))
                        cell.onSelfSizingHeightChange = { [weak self] in
                            self?.messageCellWillChangeHeight()
                        }
                        if renderRowIsCurrent(row) {
                            row.videoOwners.keys.forEach { self.pendingInlineVideoOwnerReturns.remove($0) }
                        }
                        return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
            }
        }
    }

    private func currentActionMessage(
        _ authority: ChatMessageActionAuthority, cell: MessageCell?, intent: ChatMessageActionAuthority.Intent,
    ) -> CustomMessage? {
        let path = cell.flatMap { collectionView.indexPath(for: $0) }
        return authority.resolve(
            intent,
            current: message(for: authority.displayedID),
            source: tdlib.activeUpdateSource,
            location: chatVM.location,
            ownerIsCurrent: routeIsRetained && chatVM.locationContextIsCurrent
                && chatListActionOwnerIsAttached && navigationController?.topViewController === self
                && presentedViewController == nil,
            rowIsCurrent: !timelineSnapshots.deleting.contains(authority.displayedID)
                && path.map { dataSource.itemIdentifier(for: $0) == .message(authority.displayedID) } == true,
            state: .init(
                isFull: presentationMode == .full, isSelecting: isSelectingMessages,
                isReadOnly: chatVM.isReadOnlyTopic, canAddReactions: chatVM.canAddReactions,
                isSelected: selectedDisplayedMessageIDs.contains(authority.displayedID),
            ),
        )
    }

    private func observeState() {
        observeFavoriteStickers()
        NotificationCenter.default
            .publisher(for: UIScene.didActivateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.acknowledgeCommittedVisibleMessages(requestHistory: true) }
            .store(in: &cancellables)
        tdlib.activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, source != navigationClientSource else { return }
                timelineSnapshots.retire()
                viewportRestorationAuthority.invalidate()
                pendingDeleteSnapshotWorkItem?.cancel()
                pendingDeleteSnapshotWorkItem = nil
                pendingDeleteSnapshotDeadline = nil
                retryClientRestoration()
            }
            .store(in: &cancellables)
        mediaRevealSession?.observeAcceptedMessages(
            changes: chatVM.messagesDidChange.eraseToAnyPublisher(),
            current: { [weak chatVM] in chatVM?.messages ?? [] },
        )
        .store(in: &cancellables)
        mediaRevealSession?.revisionsChanged
            .sink { [weak self] changed in
                guard let self else { return }
                for id in changed.ids {
                    guard let displayedID = chatVM.displayedMessageID(containing: id) else { continue }
                    prefetchTasks.removeValue(forKey: displayedID)?.task?.cancel()
                }
                DispatchQueue.main.async { [weak self] in
                    for id in changed.ids {
                        self?.reconfigureMessage(id: id)
                    }
                }
            }
            .store(in: &cancellables)
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification] {
            NotificationCenter.default
                .publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    keyboardIsChanging = name == UIResponder.keyboardWillChangeFrameNotification
                    if !keyboardIsChanging { settleRestoredViewport()
                        retryClientRestoration()
                        scrollFocusedPollAddOptionIntoView()
                    }
                }
                .store(in: &cancellables)
        }
        chatVM.pollInteractionStore
            .addOptionFocusChanges
            .removeDuplicates()
            .sink { [weak self] messageID in self?.pollAddOptionFocusChanged(messageID) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .updateConnectionState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let update = TdScopedUpdate<UpdateConnectionState>(notification: note),
                      update.source == tdlib.activeUpdateSource, update.source.accountID == location.accountID,
                      case .connectionStateReady = update.value.state else { return }
                if preparedClient == nil { clientPreparationSource = nil }
                retryClientRestoration()
            }
            .store(in: &cancellables)
        // ChatBotInfoItem arrives with the bot's full info; an empty bot chat shows it in place of the placeholder.
        chatVM.$botInfo
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if collectionView.backgroundView != nil { collectionView.backgroundView = emptyStateView() }
                    updateSnapshot(animated: false)
                }
            }
            .store(in: &cancellables)
        // The bot info row joins the top once the history is read back to its first message.
        chatVM.$historyReachedStart
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, case .bot = chatVM.customChat.type else { return }
                    updateSnapshot(animated: false)
                }
            }
            .store(in: &cancellables)
        chatVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    retryClientRestoration()
                    guard !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
                    updateStatus()
                    if showsComposer {
                        let voiceDestinationUnavailable = (chatVM.recordingVoiceNote || chatVM.startingVoiceNote)
                            && !chatVM.canContinueVoiceRecording
                        if isTerminatingNavigation || !chatVM.canWriteAnyMessage || voiceDestinationUnavailable {
                            composerView.cancelActiveRecordingGesture(preservingVoiceDraft: true)
                        } else {
                            chatVM.resumeVoiceRecordingInteraction()
                        }
                        if !composerAwaitsSentMediaInsertion { composerView.update(from: chatVM) }
                    }
                    updateHighlightState()
                    updatePinnedMessageBanner(animated: true)
                    presentMicrophoneErrorIfNeeded()
                    presentVoiceNoteErrorIfNeeded()
                    presentVideoNoteSendErrorIfNeeded()
                    presentSendErrorIfNeeded()
                    presentDraftErrorIfNeeded()
                    presentReactionErrorIfNeeded()
                    presentPinErrorIfNeeded()
                    presentMessageActionErrorIfNeeded()
                    presentInlineBotLocationRequestIfNeeded()
                    restoreVideoRecordingIfNeeded()
                }
            }
            .store(in: &cancellables)
        chatVM.recordingTimeChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, showsComposer, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
                composerView.updateRecordingTime()
            }
            .store(in: &cancellables)
        chatVM.replyKeyboard
            .$revision
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // After the composer update queued for the same change.
                DispatchQueue.main.async { self?.evaluateReplyKeyboardChange() }
            }
            .store(in: &cancellables)
        chatVM.messagesDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateSnapshot(animated: true) }
            }
            .store(in: &cancellables)
        chatVM.messageBubblesWillDelete
            .sink { [weak self] ids in self?.prepareDeleteTransition(for: ids) }
            .store(in: &cancellables)
        chatVM.sendTransitionWillBegin
            .sink { [weak self] request in self?.prepareComposerSendTransition(request) }
            .store(in: &cancellables)
        chatVM.sendTransitionAccepted
            .sink { [weak self] acceptance in self?.acceptComposerSendTransition(acceptance) }
            .store(in: &cancellables)
        chatVM.sendTransitionCancelled
            .sink { [weak self] id in self?.cancelComposerSendTransition(id: id) }
            .store(in: &cancellables)
        chatVM.scheduledComposerSend
            .sink { [weak self] in self?.openScheduledMessages() }
            .store(in: &cancellables)
        chatVM.sendTransitionMessageIDReplaced
            .sink { [weak self] replacement in
                self?.replacePendingComposerSendMessageID(
                    old: replacement.old,
                    new: replacement.new,
                )
            }
            .store(in: &cancellables)
        chatVM.customChat
            .$chat
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateChatHeader() }
            }
            .store(in: &cancellables)
        chatVM.customChat
            .$unreadCount
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatus() } }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.significantTimeChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSnapshot(animated: false) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIContentSizeCategory.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.invalidateSelfSizingLayoutPreservingAnchor() }
            }
            .store(in: &cancellables)
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            self?.updateChatHeader()
        }
    }

    private func updateChatHeader() {
        let chat = chatVM.customChat.chat
        let (title, status) = headerTitleAndStatus
        let statusColor: UIColor = chatVM.headerStatusIsActive ? .systemBlue : .secondaryLabel
        customNavigationBar.configure(
            title: title,
            status: status,
            statusColor: statusColor,
        )
        customNavigationBar.configureAvatar(
            file: chat.photo?.small,
            largeFile: chat.photo?.big,
            minithumbnail: chat.photo?.minithumbnail,
            placeholder: chatVM.customChat.telegramAvatarPlaceholder,
            client: chatVM.client,
        )
    }

    private func subscribeToMessages() {
        messageCancellables.removeAll()
        for message in chatVM.messages {
            message.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak message, weak model = chatVM] in
                    guard let self, let message, let model,
                          messageRenderInvalidations.enqueue(message, owner: model) else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        let model = chatVM
                        let ids = messageRenderInvalidations.drain(current: model.messages, owner: model)
                        guard !ids.isEmpty, !clientOwnerRetired, model.locationContextIsCurrent else { return }
                        reconcileChangedRevealRows()
                        reconfigureMessages(ids: ids)
                    }
                }
                .store(in: &messageCancellables)
        }
    }

    private func updateStatus() {
        let (title, status) = headerTitleAndStatus
        let statusColor: UIColor = chatVM.headerStatusIsActive ? .systemBlue : .secondaryLabel
        customNavigationBar.configure(
            title: title,
            status: status,
            statusColor: statusColor,
        )
        // TDLib reports a thread's unread count only in its one-off read, so a thread shows none.
        let unreadCount =
            if location.messageThreadID != nil {
                0
            } else if location.isTopicScoped {
                chatVM.forumTopic?.unreadCount ?? 0
            } else {
                chatVM.customChat.unreadCount
            }
        unreadBadgeLabel.text = unreadCount > 0 ? compactNumericCountString(unreadCount) : nil
        unreadBadgeLabel.isHidden = unreadCount == 0
        scrollToLatestButton.accessibilityValue = unreadCount == 0
            ? nil
            : L10n.telegramPlural("VoiceOver.Chat.UnreadMessages", count: unreadCount)
    }

    private func updateTopicReopenBar(visible: Bool, animated: Bool) {
        guard topicReopenBarHeightConstraint != nil else { return }
        let desiredHeight = visible ? TopicReopenBarView.contentHeight : 0
        guard abs(topicReopenBarHeightConstraint.constant - desiredHeight) > 0.5 else { return }
        if visible {
            topicReopenBar.isBusy = false
            topicReopenBar.isHidden = false
        }
        view.layoutIfNeeded()
        topicReopenBarHeightConstraint.constant = desiredHeight
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            topicReopenBar.isHidden = topicReopenBarHeightConstraint.constant == 0
            updateHistoryInsets()
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            view.layoutIfNeeded()
            completion(true)
            return
        }
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: { self.view.layoutIfNeeded() },
            completion: completion,
        )
    }

    /// Telegram's Restart Topic action (ChatControllerLoadDisplayNode, restartTopic). TDLib's updateForumTopicInfo
    /// then reports the topic open and the bar leaves.
    private func reopenTopic() {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent, chatVM.canReopenTopic,
              !topicReopenBar.isBusy, let topicID = location.forumTopicID else { return }
        let client = chatVM.client
        let chatID = location.chatID
        topicReopenBar.isBusy = true
        Task { [weak self] in
            let reopened = await (try? client.send(TDNativeRequests.toggleForumTopicIsClosed(
                chatId: chatID, forumTopicId: topicID, isClosed: false,
            ))) != nil
            // A failed request leaves the bar tappable again; Telegram's panel sends and forgets.
            if !reopened { self?.topicReopenBar.isBusy = false }
        }
    }

    /// Telegram's avatar menu inside a forum topic (ChatController, `avatarNode.contextAction` for `.replyThread`):
    /// Search, then Close or Reopen for whoever may toggle the topic. Its mute items are disabled upstream.
    private func topicAvatarMenuActions() -> [TelegramContextMenuAction] {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent,
              let topicID = location.forumTopicID else { return [] }
        var actions = [TelegramContextMenuAction(
            title: L10n.telegram("Conversation.Search"),
            image: UIImage(systemName: "magnifyingglass"),
        ) { [weak self] in self?.beginMessageSearch() }]
        if chatVM.canToggleTopicClosed, let info = chatVM.forumTopicInfo {
            let isClosed = info.isClosed
            let client = chatVM.client
            let chatID = location.chatID
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isClosed ? "ChatList.Context.ReopenTopic" : "ChatList.Context.CloseTopic"),
                image: UIImage(systemName: isClosed ? "play" : "pause"),
            ) { [weak self] in
                guard let self, routeIsRetained, chatVM.locationContextIsCurrent else { return }
                // TDLib's updateForumTopicInfo then shows or hides the Restart Topic bar and the closed composer.
                Task {
                    _ = try? await client.send(TDNativeRequests.toggleForumTopicIsClosed(
                        chatId: chatID, forumTopicId: topicID, isClosed: !isClosed,
                    ))
                }
            })
        }
        return actions
    }

    private func updatePinnedMessageBanner(animated: Bool) {
        guard pinnedMessageBannerHeightConstraint != nil, !awaitsClientRenewal else { return }
        // Telegram shows one title panel: a closed topic's Restart Topic panel replaces the pinned message.
        let showsReopenBar = presentationMode == .full && !messageSearchActive && !isSelectingMessages
            && chatVM.canReopenTopic
        updateTopicReopenBar(visible: showsReopenBar, animated: animated)
        let message: Message? =
            if presentationMode == .full,
            !messageSearchActive,
            !isSelectingMessages,
            !showsReopenBar {
                chatVM.visiblePinnedMessage
            } else {
                nil
            }
        if let cover = restoredPinnedBannerCover {
            if message == nil, chatVM.pinnedMessageIsLoading { return }
            restoredPinnedBannerCover = nil
            if message == nil {
                cover.removeFromSuperview()
            } else {
                // The banner below shows the same message; its thumbnail decodes asynchronously, so the snapshot
                // fades out over it instead of leaving the thumbnail empty for a frame.
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: { cover.alpha = 0 },
                    completion: { _ in cover.removeFromSuperview() },
                )
            }
        }
        if let message {
            pinnedMessageBanner.configure(
                message: message,
                client: chatVM.client,
                onOpen: { [weak self] in
                    self?.scrollToMessage(id: message.id)
                },
                onHide: { [weak self] in
                    self?.closePinnedMessageBanner()
                },
            )
            pinnedMessageBanner.isHidden = false
        }
        let desiredHeight = message == nil ? CGFloat.zero : PinnedMessageBannerView.contentHeight
        guard abs(pinnedMessageBannerHeightConstraint.constant - desiredHeight) > 0.5 else {
            view.setNeedsLayout()
            return
        }
        pinnedMessageBannerTransitionGeneration &+= 1
        let transitionGeneration = pinnedMessageBannerTransitionGeneration
        view.layoutIfNeeded()
        pinnedMessageBannerHeightConstraint.constant = desiredHeight
        let changes = {
            self.pinnedMessageBanner.alpha = desiredHeight == 0 ? 0 : 1
            self.view.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self,
                  pinnedMessageBannerTransitionGeneration == transitionGeneration
            else { return }
            if desiredHeight == 0 {
                pinnedMessageBanner.isHidden = true
                pinnedMessageBanner.prepareForReuse()
            }
            updateHistoryInsets()
        }
        guard animated else {
            changes()
            completion(true)
            return
        }
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: changes,
            completion: completion,
        )
    }

    private func updateSnapshot(animated: Bool) {
        enqueueTimeline(.init(
            structural: true,
            animated: animated,
            restoresViewport: true,
            viewportRevision: viewportRestorationAuthority.invalidationRevision,
        ))
    }

    private func enqueueTimeline(_ demand: ChatTimelineSnapshotState.Demand) {
        guard isViewLoaded else { return }
        guard timelineSourceIsCurrent else { timelineSnapshots.retire()
            return
        }
        timelineSnapshots.enqueue(demand)
        drainTimelineSnapshots()
    }

    /// Reveal keys read native TDLib fields, so a pass reconciles only rows whose canonical object or render revision
    /// changed since the previous one. Array replacements already reconcile through `observeAcceptedMessages`.
    private func reconcileChangedRevealRows() {
        guard let mediaRevealSession else { return }
        var rows = [DisplayedMessageID: (message: CustomMessage, revision: UInt64)](
            minimumCapacity: chatVM.messages.count,
        )
        var changed = [Message]()
        for message in chatVM.messages {
            let previous = revealReconciledRows[message.displayedID]
            if previous?.message !== message || previous?.revision != message.renderRevision {
                changed += message.sourceMessages
            }
            rows[message.displayedID] = (message, message.renderRevision)
        }
        revealReconciledRows = rows
        if !changed.isEmpty { mediaRevealSession.reconcile(changed) }
    }

    private func makeTimelineContent(_ demand: ChatTimelineSnapshotState.Demand) -> ChatTimelineSnapshotState.Content {
        reconcileChangedRevealRows()
        let wasSelectingMessages = isSelectingMessages
        if demand.structural, isSelectingMessages {
            let displayedIDs = Set(chatVM.messages.map(\.displayedID))
            selectedDisplayedMessageIDs.formIntersection(displayedIDs)
            if selectedDisplayedMessageIDs.isEmpty, !selectionInteractionActive {
                endMessageSelection(reconfigure: false)
            } else {
                updateMessageSelectionChrome(reconfigureIDs: [])
            }
        }
        let threadHead = chatVM.messageThreadHeadDisplay
        let itemIDs = demand.structural
            ? ChatTimelineProjection.items(
                messages: chatVM.messages.filter {
                    !timelineSnapshots.deleting.contains($0.displayedID) && !chatVM.holdsIncompleteOutgoingAlbum($0)
                        && !chatVM.holdsComposerSendMessage($0) && !Self.isUpgradeNotice($0.message.content)
                },
                includesTopicHeaders: chatVM.isAllMessagesForum,
                threadHeadID: threadHead?.id,
                includesBotInfo: showsBotInfoRow,
            )
            : timelineSnapshots.committed.ids
        let models = Dictionary(chatVM.messages.map { ($0.displayedID, $0) }, uniquingKeysWith: { _, latest in latest })
        let changedOwners = messageRenderOwners.replace(chatVM.messages)
        if demand.structural || !changedOwners.isEmpty { subscribeToMessages() }
        var rows = [ChatTimelineItemID: ChatTimelineRenderRow]()
        var changed = Set<ChatTimelineItemID>()
        for item in itemIDs {
            switch item {
            case .dateHeader(let id):
                rows[item] = .date(id)
                // A header never configured has no cell to refresh; it gets its title when dequeued.
                if demand.structural, let shown = dateHeaderTitles[id], shown != ChatDateHeaderCell.title(for: id) {
                    changed.insert(item)
                }
            case .topicHeader(let id):
                rows[item] = .topic(id, chatVM.forumTopic(id: id.topicID)?.info, chatVM.client, navigationClientSource)
                changed.insert(item)
            case .threadStart:
                let text = ChatReplyCountCell.text(hasReplies: threadHead?.hasReplies ?? true)
                rows[item] = .notice(text)
                if case .notice(let shown) = timelineSnapshots.committed.rows[item], shown == text {} else {
                    changed.insert(item)
                }
            case .botInfo:
                if let info = chatVM.botInfo {
                    rows[item] = .botInfo(info, chatVM.client)
                    changed.insert(item)
                }
            case .message(let id):
                let previous = timelineSnapshots.committed.rows[item]?.message
                guard !timelineSnapshots.deleting.contains(id), let canonical = models[id] else {
                    rows[item] = timelineSnapshots.committed.rows[item]
                    continue
                }
                let inputs = ChatTimelineMessageRow.Inputs(
                    highlightedMessageID: canonical.sourceMessages.first { $0.id == chatVM.highlightedMessageId }?.id,
                    selectionActive: isSelectingMessages && canSelectMessage(canonical),
                    selected: selectedDisplayedMessageIDs.contains(id),
                    showsProfileImage: chatVM.customChat.shouldShowProfileImage,
                    canAddReactions: chatVM.canAddReactions,
                    canReply: presentationMode == .full && !isSelectingMessages
                        && !chatVM.isReadOnlyTopic && canonical.properties.canBeReplied,
                )
                let mustRefresh = demand.ids.contains(id) || changedOwners.contains(id)
                    || wasSelectingMessages && !isSelectingMessages
                let reusable = previous.flatMap { previous in
                    !mustRefresh && previous.canonical === canonical && previous.inputs == inputs ? previous : nil
                }
                // Unchanged revision: the value cannot differ, so skip building and deep-comparing it.
                if let reusable, reusable.revision == canonical.renderRevision {
                    rows[item] = .message(reusable)
                    continue
                }
                let value = ChatMessageRenderValue(canonical)
                if let reusable, reusable.value == value {
                    reusable.revision = canonical.renderRevision
                    rows[item] = .message(reusable)
                } else {
                    // Capture matching handles only. Creating new players is lazy,
                    // after a visible provider verifies this exact canonical payload.
                    let owners = Dictionary(uniqueKeysWithValues: value.sourceMessages.compactMap { raw in
                        inlineVideoPlaybackOwners[raw.id].flatMap { $0.matches(message: raw) ? (raw.id, $0) : nil }
                    })
                    rows[item] = .message(ChatTimelineMessageRow(
                        canonical: canonical, value: value, inputs: inputs, client: chatVM.client,
                        source: navigationClientSource, location: location, polls: chatVM.pollInteractionStore,
                        mediaRevealSession: mediaRevealSession, videoOwners: owners,
                    ))
                    changed.insert(item)
                }
            }
        }
        return .init(ids: itemIDs, rows: rows, reconfigure: changed)
    }

    private func drainTimelineSnapshots() {
        guard timelineSourceIsCurrent else { timelineSnapshots.retire()
            return
        }
        guard timelineLayoutMutationDepth == 0, viewportCompletionLayoutDepth == 0,
              timelineSnapshots.canBegin, let demand = timelineSnapshots.pending else { return }
        if demand.structural, deferSnapshotForDeleteTransitionIfNeeded() { return }
        var restoration: AutomaticViewportRestoration?
        guard let batch = timelineSnapshots.begin(makeContent: { demand in
            if demand.permitsRestoration(at: viewportRestorationAuthority.invalidationRevision) {
                if let quoteID = demand.quoteID, !userIsScrollingTimeline, !hasPendingMessageNavigation,
                   let path = dataSource.indexPath(for: .message(quoteID)),
                   let frame = collectionView.collectionViewLayout.layoutAttributesForItem(at: path)?.frame
                {
                    restoration = .init(
                        ticket: viewportRestorationAuthority.begin(),
                        keepsLatest: false,
                        anchor: .init(
                            itemID: .message(quoteID),
                            minYRelativeToViewport: frame.minY - collectionView.contentOffset.y,
                        ),
                    )
                } else if demand.restoresViewport { restoration = captureAutomaticViewportRestoration() }
            }
            return makeTimelineContent(demand)
        }) else { return }
        var snapshot = NSDiffableDataSourceSnapshot<Section, ChatTimelineItemID>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(batch.content.ids)
        snapshot.reconfigureItems(Array(batch.content.reconfigure.filter { item in
            item.displayedMessageID.map { !timelineSnapshots.deleting.contains($0) } ?? true
        }))
        timelineLayoutMutationDepth += 1
        recordMessageNavigationGeometry("snapshot-before")
        #if DEBUG
            let geometryAtSnapshot = messageNavigationGeometry
            let probeSnapshot = batch.demand.structural ? viewportCompletionProbe?.snapshotWillApply() : nil
            viewportCompletionProbe?.ownRestoration(sequence: probeSnapshot) { [weak self] in
                guard let self, let restoration else { return }
                _ = viewportRestorationAuthority.consume(
                    restoration.ticket, contextIsCurrent: false, userIsScrolling: true,
                )
            }
        #endif
        let batchID = batch.id
        let structural = batch.demand.structural
        let highlighted = batch.demand.highlight
        let viewportRevision = batch.demand.viewportRevision
        let regroup = structural || batch.demand.animated ? nil : captureAlbumRegroupTransition(batch.content)
        let completion = { [weak self, timelineSnapshots] in
            guard let owner = self else {
                timelineSnapshots.retire()
                timelineSnapshots.complete(batchID) { _ in }
                return
            }
            var removedDeletionIDs = Set<DisplayedMessageID>()
            guard timelineSnapshots.complete(batchID, finish: { exact in
                removedDeletionIDs = timelineSnapshots.deleting
                    .subtracting(exact.content.ids.compactMap(\.displayedMessageID))
                defer { owner.finishTimelineLayoutMutation(retryPendingNavigation: false) }
            #if DEBUG
                if owner.messageNavigationGeometry === geometryAtSnapshot {
                    owner.recordMessageNavigationGeometry("snapshot-completion")
                }
            #endif
                owner.synchronizeNativeSelection()
                owner.layoutForViewportCompletion()
            #if DEBUG
                if owner.messageNavigationGeometry === geometryAtSnapshot {
                    owner.recordMessageNavigationGeometry("snapshot-layout")
                }
            #endif
                guard owner.timelineSourceIsCurrent, !timelineSnapshots.retired else { return }
                if structural, owner.restoredViewport?.markSnapshotApplied() == true { return }
                if !owner.hasPendingMessageNavigation {
                    owner.restoreAutomaticViewport(restoration)
                    if structural { owner.didPerformInitialScroll = true }
                }
            #if DEBUG
                if highlighted, owner.messageNavigationGeometry === geometryAtSnapshot {
                    owner.recordMessageNavigationGeometry("highlight-completion", command: true)
                }
            #endif
            }) else { return }
            if owner.timelineSourceIsCurrent, !removedDeletionIDs.isEmpty {
                timelineSnapshots.reconcileRemovedRows(
                    removedDeletionIDs, current: Set(owner.chatVM.messages.map(\.displayedID)),
                    viewportRevision: viewportRevision,
                )
            }
            owner.drainTimelineSnapshots()
            guard !timelineSnapshots.isBusy else { return }
            owner.settleRestoredViewport()
            owner.applyPendingMessageNavigation()
            owner.performPendingComposerSendTransitions()
            // A reconfigured row can bring a new inline video, such as a sent video replacing its pending bubble,
            // without a scroll or a newly displayed cell to start it.
            owner.updateInlineVideoPlaybackVisibility()
            owner.acknowledgeCommittedVisibleMessages(requestHistory: structural)
            owner.retryClientRestoration()
        }
        let previousItemIDs = batch.demand.animated ? Set(dataSource.snapshot().itemIdentifiers) : []
        dataSource.apply(snapshot, animatingDifferences: batch.demand.animated) { [weak self] in
            #if DEBUG
                if self?.viewportCompletionProbe?.holdNativeCompletion(
                    sequence: probeSnapshot, completion: completion,
                ) == true { return }
            #endif
            completion()
        }
        collectionView.visibleCells.forEach(applyComposerSendGlides)
        if structural, composerAwaitsSentMediaInsertion { settleComposerForSentMedia() }
        if batch.demand.animated, !previousItemIDs.isEmpty {
            riseInsertedLatestRows(after: previousItemIDs, ids: batch.content.ids)
        }
        if let regroup {
            // The reconfigured row self-sizes in this layout pass, before the frame commits; the native completion
            // comes on the next turn, one frame after the rows moved. Restore the viewport and start the motion now.
            layoutForViewportCompletion()
            if timelineSourceIsCurrent, !timelineSnapshots.retired, !hasPendingMessageNavigation {
                restoreAutomaticViewport(restoration)
                restoration = nil
            }
            performAlbumRegroupTransition(regroup)
        }
        collectionView.backgroundView = batch.content.ids.isEmpty ? emptyStateView() : nil
    }

    /// Telegram builds a group entry only for two or more messages, so an album that becomes one message, or one
    /// that becomes an album, is a removed list item and an inserted one; an album that keeps two or more members
    /// lays its mosaic out again in the same bubble. Here the album keeps its row, which is reconfigured, so the row
    /// takes its new height at once and the rows above it jump.
    private func captureAlbumRegroupTransition(
        _ content: ChatTimelineSnapshotState.Content,
    ) -> AlbumRegroupTransition? {
        guard view.window != nil, !UIAccessibility.isReduceMotionEnabled, !userIsScrollingTimeline,
              !hasPendingMessageNavigation, !latestEdgeScrollInFlight else { return nil }
        var regrouped = [ChatTimelineItemID: Set<Int64>]()
        for item in content.reconfigure {
            guard case .message(.album) = item,
                  let previous = timelineSnapshots.committed.rows[item]?.message?.value.sourceMessages.map(\.id),
                  let current = content.rows[item]?.message?.value.sourceMessages.map(\.id),
                  previous.count != current.count
            else { continue }
            regrouped[item] = Set(previous).subtracting(current)
        }
        guard !regrouped.isEmpty else { return nil }
        var frames = [ChatTimelineItemID: CGRect]()
        var rows = [ChatTimelineItemID: AlbumRegroupTransition.Row]()
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let id = dataSource.itemIdentifier(for: indexPath),
                  let cell = collectionView.cellForItem(at: indexPath) else { continue }
            frames[id] = cell.frame
            guard let removed = regrouped[id], let cell = cell as? MessageCell,
                  let snapshot = cell.snapshotView(afterScreenUpdates: false) else { continue }
            snapshot.frame = cell.frame
            let tiles = cell.albumTileFrames(in: collectionView)
            let removedTiles = removed.compactMap { messageID -> UIView? in
                guard let frame = tiles?[messageID], let tile = cell.albumTileSnapshot(for: messageID) else {
                    return nil
                }
                tile.frame = frame
                return tile
            }
            rows[id] = .init(
                snapshot: snapshot, bubbleCenter: cell.bubbleCenter, tiles: tiles, removedTiles: removedTiles,
            )
        }
        return rows.isEmpty ? nil : .init(frames: frames, rows: rows)
    }

    /// Every row moves from where it was over ListView's 0.4 s on Telegram's `.spring` curve. An album that stays
    /// one moves its tiles to their new frames as ChatMessageBubbleItemNode does, and a member that left fades out in
    /// 0.25 s (animateRemovalFromBubble). Otherwise the item is replaced: the old one shrinks into its bubble's center
    /// and fades out in 0.15 s (animateRemoved), and the new one fades in over 0.2 s (animateInsertion) inside an
    /// apparent height that grows from the old one, so the rows above never cover it.
    private func performAlbumRegroupTransition(_ transition: AlbumRegroupTransition) {
        var moves = [(UICollectionViewCell, ChatTimelineItemID, CGFloat)]()
        // Rows are ordered newest first from the screen's bottom; a row that came on screen moves with the one below.
        var carriedShift: CGFloat = 0
        for indexPath in collectionView.indexPathsForVisibleItems.sorted() {
            guard let id = dataSource.itemIdentifier(for: indexPath),
                  let cell = collectionView.cellForItem(at: indexPath) else { continue }
            var shift = carriedShift
            if let previous = transition.frames[id] {
                shift = previous.minY - cell.frame.minY
                carriedShift = previous.maxY - cell.frame.maxY
            }
            moves.append((cell, id, shift))
        }
        guard moves.allSatisfy({ abs($0.2) < collectionView.bounds.height }) else { return }
        for (cell, id, shift) in moves {
            let glide = Self.listTransitionAnimation(
                "position",
                from: CGPoint(x: 0, y: shift),
                to: CGPoint.zero,
                additive: true,
            )
            if abs(shift) > 0.5 { cell.layer.add(glide, forKey: "chat.albumRegroupGlide") }
            guard let row = transition.rows[id], let previous = transition.frames[id] else { continue }
            // The tiles start where they were drawn, against the row's own move.
            if let tiles = row.tiles, let cell = cell as? MessageCell,
               cell.animateAlbumTiles(from: tiles.mapValues { $0.offsetBy(dx: 0, dy: -shift) }, in: collectionView)
            {
                for tile in row.removedTiles {
                    tile.isUserInteractionEnabled = false
                    tile.layer.zPosition = 1
                    tile.frame = tile.frame.offsetBy(dx: 0, dy: -shift)
                    collectionView.addSubview(tile)
                    if abs(shift) > 0.5 { tile.layer.add(glide, forKey: "chat.albumRegroupGlide") }
                    UIView.animate(withDuration: 0.25) {
                        tile.alpha = 0
                    } completion: { _ in
                        tile.removeFromSuperview()
                    }
                }
                continue
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.2
            cell.contentView.layer.add(fade, forKey: "chat.albumRegroupFade")
            // The cell's own coordinates start at the screen's bottom edge, where the row grows from.
            let mask = CALayer()
            mask.backgroundColor = UIColor.black.cgColor
            mask.anchorPoint = .zero
            mask.position = CGPoint(x: -cell.bounds.width, y: -cell.bounds.height)
            mask.bounds = CGRect(x: 0, y: 0, width: cell.bounds.width * 3, height: cell.bounds.height * 2)
            let previousHeight = CGSize(width: mask.bounds.width, height: previous.height + cell.bounds.height)
            mask.add(
                Self.listTransitionAnimation("bounds.size", from: previousHeight, to: mask.bounds.size),
                forKey: "chat.albumRegroupHeight",
            )
            cell.layer.mask = mask
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak cell, weak mask] in
                guard let cell, let mask, cell.layer.mask === mask else { return }
                cell.layer.mask = nil
            }
            let snapshot = row.snapshot
            let center = row.bubbleCenter
            snapshot.isUserInteractionEnabled = false
            snapshot.layer.anchorPoint = CGPoint(
                x: center.x / max(1, previous.width),
                y: center.y / max(1, previous.height),
            )
            snapshot.layer.position = CGPoint(x: previous.minX + center.x, y: previous.minY + center.y)
            snapshot.layer.zPosition = 1
            collectionView.addSubview(snapshot)
            CATransaction.begin()
            CATransaction.setCompletionBlock { snapshot.removeFromSuperview() }
            let removal = CAAnimationGroup()
            let alpha = CABasicAnimation(keyPath: "opacity")
            alpha.fromValue = 1
            alpha.toValue = 0
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 0.1
            removal.animations = [alpha, scale]
            removal.duration = 0.15
            removal.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            snapshot.layer.opacity = 0
            snapshot.layer.add(removal, forKey: "chat.albumRegroupRemoval")
            CATransaction.commit()
        }
    }

    /// Telegram moves a new latest message in from the bottom edge together with the rows it pushes up. UIKit adds
    /// the new cell at its final place with animations off, while the rows above slide up by its height, so they
    /// slid across it: a sticker or GIF showed under the bubble moving up. Every row moves by the same distance, so
    /// the new rows take the additive move UIKit gave the first row above them.
    private func riseInsertedLatestRows(after previous: Set<ChatTimelineItemID>, ids: [ChatTimelineItemID]) {
        let inserted = ids.prefix { !previous.contains($0) }
        guard !inserted.isEmpty, inserted.count < ids.count,
              let neighbourPath = dataSource.indexPath(for: ids[inserted.count]),
              let motion = collectionView.cellForItem(at: neighbourPath)?.layer.animation(forKey: "position")
              as? CABasicAnimation, motion.isAdditive
        else { return }
        for id in inserted {
            guard let path = dataSource.indexPath(for: id), let cell = collectionView.cellForItem(at: path) else {
                continue
            }
            cell.layer.add(motion, forKey: "chat.latestRowRise")
        }
    }

    private func prepareDeleteTransition(for ids: Set<DisplayedMessageID>) {
        timelineSnapshots.markDeleting(ids)
        var animatedVisibleCell = false
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard case .message(let displayedID) = dataSource.itemIdentifier(for: indexPath),
                  ids.contains(displayedID),
                  let cell = collectionView.cellForItem(at: indexPath) as? MessageCell,
                  let message = message(for: displayedID)
            else { continue }
            animatedVisibleCell = true
            cell.isUserInteractionEnabled = false
            let horizontalOffset: CGFloat = message.message.isOutgoing ? 24 : -24
            UIView.animate(
                withDuration: 0.14,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn],
            ) {
                cell.setDeletionPresentation(
                    alpha: 0,
                    transform: CGAffineTransform(translationX: horizontalOffset, y: 0)
                        .scaledBy(x: 0.98, y: 0.98),
                )
            }
        }
        guard animatedVisibleCell else { return }
        pendingDeleteSnapshotDeadline = CACurrentMediaTime() + 0.14
    }

    private func deferSnapshotForDeleteTransitionIfNeeded() -> Bool {
        guard let deadline = pendingDeleteSnapshotDeadline else { return false }
        let delay = deadline - CACurrentMediaTime()
        guard delay > 0 else {
            pendingDeleteSnapshotDeadline = nil
            pendingDeleteSnapshotWorkItem = nil
            return false
        }
        pendingDeleteSnapshotWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingDeleteSnapshotDeadline = nil
            pendingDeleteSnapshotWorkItem = nil
            drainTimelineSnapshots()
        }
        pendingDeleteSnapshotWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return true
    }

    private func prepareComposerSendTransition(_ request: ComposerSendTransitionRequest) {
        let snapshots = composerView.makeSendTransitionSnapshots(kind: request.kind, in: view)
        guard !snapshots.isEmpty else { return }
        let timeout = DispatchWorkItem { [weak self] in
            self?.cancelComposerSendTransition(id: request.id)
        }
        pendingComposerSendTransitions[request.id] = PendingComposerSendTransition(
            kind: request.kind,
            snapshots: snapshots,
            timeout: timeout,
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    private func acceptComposerSendTransition(_ acceptance: ComposerSendTransitionAcceptance) {
        guard !acceptance.messageIDs.isEmpty,
              var transition = pendingComposerSendTransitions[acceptance.id]
        else {
            cancelComposerSendTransition(id: acceptance.id)
            return
        }
        transition.messageIDs = acceptance.messageIDs.map(resolveSendTransitionMessageID)
        pendingComposerSendTransitions[acceptance.id] = transition
        if transition.kind == .media, isViewLoaded, timelineSourceIsCurrent {
            // The view model released the sent media and cleared the composer in this turn. Telegram inserts the
            // message in the transaction that shrinks the input panel; the snapshot that inserts it, now or after the
            // one applying, also shrinks the composer, so the history moves once.
            composerAwaitsSentMediaInsertion = true
            composerSentMediaSettleGeneration &+= 1
            let generation = composerSentMediaSettleGeneration
            updateSnapshot(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, composerAwaitsSentMediaInsertion,
                      composerSentMediaSettleGeneration == generation else { return }
                settleComposerForSentMedia()
            }
        }
        DispatchQueue.main.async { [weak self] in self?.performPendingComposerSendTransitions() }
    }

    private func settleComposerForSentMedia() {
        composerAwaitsSentMediaInsertion = false
        guard showsComposer else { return }
        // The thumbnails leave the composer now; their snapshots hold the place until they fly.
        for transition in pendingComposerSendTransitions.values where !transition.messageIDs.isEmpty {
            transition.snapshots.filter { $0.view.superview == nil }.forEach(placeComposerSendSnapshot)
        }
        composerView.update(from: chatVM)
        view.layoutIfNeeded()
    }

    private func placeComposerSendSnapshot(_ source: ComposerSendTransitionSnapshot) {
        let snapshot = source.view
        snapshot.frame = source.sourceFrame
        snapshot.layer.cornerCurve = .continuous
        snapshot.layer.cornerRadius = min(12, snapshot.bounds.height / 2)
        snapshot.clipsToBounds = true
        view.addSubview(snapshot)
    }

    private func cancelComposerSendTransition(id: UUID) {
        guard let transition = pendingComposerSendTransitions.removeValue(forKey: id) else { return }
        transition.timeout.cancel()
        transition.snapshots.forEach { $0.view.removeFromSuperview() }
        retryClientRestoration()
    }

    private func replacePendingComposerSendMessageID(old: Int64, new: Int64) {
        if sendTransitionMessageIDAliases[old] == nil { sendTransitionAliasOrder.append(old) }
        sendTransitionMessageIDAliases[old] = new
        // Evict the oldest alias; a dictionary's first key is arbitrary and could drop one a transition still needs.
        while sendTransitionAliasOrder.count > 128 {
            sendTransitionMessageIDAliases[sendTransitionAliasOrder.removeFirst()] = nil
        }
        for id in Array(pendingComposerSendTransitions.keys) {
            guard var transition = pendingComposerSendTransitions[id],
                  transition.messageIDs.contains(old)
            else { continue }
            transition.messageIDs = transition.messageIDs.map(resolveSendTransitionMessageID)
            pendingComposerSendTransitions[id] = transition
        }
        performPendingComposerSendTransitions()
    }

    private func resolveSendTransitionMessageID(_ id: Int64) -> Int64 {
        var resolved = id
        var visited = Set<Int64>()
        while let replacement = sendTransitionMessageIDAliases[resolved],
              visited.insert(resolved).inserted
        {
            resolved = replacement
        }
        return resolved
    }

    private func performPendingComposerSendTransitions() {
        guard isViewLoaded, timelineSourceIsCurrent, !timelineSnapshots.isBusy else { return }
        defer { retryClientRestoration() }
        // The composer clears just before acceptance, but its update may still be queued; settle it first so the
        // snapshots fly to where the bubble ends up once the composer has shrunk.
        if showsComposer, !composerAwaitsSentMediaInsertion,
           pendingComposerSendTransitions.values.contains(where: { !$0.messageIDs.isEmpty })
        {
            composerView.update(from: chatVM)
            view.layoutIfNeeded()
        }
        collectionView.layoutIfNeeded()
        for (id, transition) in pendingComposerSendTransitions where !transition.messageIDs.isEmpty {
            guard let displayedID = transition.messageIDs
                .lazy
                .compactMap({ rawID -> DisplayedMessageID? in
                    guard let displayed = self.chatVM.displayedMessageID(containing: rawID),
                          self.timelineSnapshots.committedContains(rawID: rawID, displayedID: displayed)
                    else { return nil }
                    return displayed
                })
                .first,
                let indexPath = dataSource.indexPath(for: .message(displayedID))
            else { continue }
            let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
            let fallbackTarget = CGRect(
                x: view.bounds.midX - 4,
                y: max(customNavigationBar.frame.maxY, composerView.frame.minY - 8),
                width: 8,
                height: 8,
            )
            let targetFrame = cell.map {
                $0.contextPreviewView.convert($0.contextPreviewView.bounds, to: view)
            } ?? fallbackTarget
            pendingComposerSendTransitions[id] = nil
            transition.timeout.cancel()
            animateComposerSendTransition(transition, targetFrame: targetFrame)
        }
    }

    private func animateComposerSendTransition(
        _ transition: PendingComposerSendTransition,
        targetFrame: CGRect,
    ) {
        let inset: CGFloat = transition.kind == .media ? 2 : 8
        let destination = targetFrame.insetBy(
            dx: min(inset, targetFrame.width / 4),
            dy: min(inset, targetFrame.height / 4),
        )
        for (index, source) in transition.snapshots.enumerated() {
            let snapshot = source.view
            if snapshot.superview == nil { placeComposerSendSnapshot(source) }
            activeComposerSendAnimations += 1
            UIView.animate(
                withDuration: 0.32,
                delay: Double(index) * 0.025,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
            ) {
                snapshot.frame = destination
                snapshot.alpha = 0
                snapshot.layer.cornerRadius = min(8, destination.height / 2)
            } completion: { [weak self] _ in
                snapshot.removeFromSuperview()
                self?.activeComposerSendAnimations -= 1
                self?.retryClientRestoration()
            }
        }
    }

    private func captureSnapshotAnchor(ensuringLayout: Bool = true) -> SnapshotAnchor? {
        if ensuringLayout {
            collectionView.layoutIfNeeded()
        }
        let viewportCenterY = collectionView.contentOffset.y + collectionView.bounds.height / 2
        return collectionView.indexPathsForVisibleItems
            .compactMap { indexPath -> (ChatTimelineItemID, UICollectionViewLayoutAttributes)? in
                guard let itemID = dataSource.itemIdentifier(for: indexPath),
                      case .message(let displayedID) = itemID,
                      message(for: displayedID) != nil,
                      let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
                else { return nil }
                return (itemID, attributes)
            }
            .min { lhs, rhs in
                abs(lhs.1.frame.midY - viewportCenterY) < abs(rhs.1.frame.midY - viewportCenterY)
            }
            .map { itemID, attributes in
                SnapshotAnchor(
                    itemID: itemID,
                    minYRelativeToViewport: attributes.frame.minY - collectionView.contentOffset.y,
                )
            }
    }

    private func captureAutomaticViewportRestoration(
        allowInitial: Bool = true,
        ensuringLayout: Bool = true,
    ) -> AutomaticViewportRestoration? {
        #if DEBUG
            viewportCompletionProbe?.automaticCapture()
        #endif
        if ensuringLayout { collectionView.layoutIfNeeded() }
        let ticket = viewportRestorationAuthority.begin()
        guard !clientOwnerRetired, chatVM.locationContextIsCurrent, !userIsScrollingTimeline,
              !hasPendingMessageNavigation, !latestEdgeScrollInFlight,
              allowInitial || didPerformInitialScroll else { return nil }
        let keepsLatest = !didPerformInitialScroll || isNearLatest
        recordMessageNavigationGeometry("automatic-capture", keepsLatest: keepsLatest)
        return AutomaticViewportRestoration(
            ticket: ticket,
            keepsLatest: keepsLatest,
            anchor: keepsLatest ? nil : captureSnapshotAnchor(ensuringLayout: false),
        )
    }

    private func restoreAutomaticViewport(_ restoration: AutomaticViewportRestoration?) {
        guard !hasPendingMessageNavigation, !latestEdgeScrollInFlight, let restoration,
              viewportRestorationAuthority.consume(
                  restoration.ticket,
                  contextIsCurrent: !clientOwnerRetired && chatVM.locationContextIsCurrent,
                  userIsScrolling: userIsScrollingTimeline,
              ) else { return }
        #if DEBUG
            viewportCompletionProbe?.automaticRestore()
        #endif
        recordMessageNavigationGeometry("automatic-restore", keepsLatest: restoration.keepsLatest)
        if restoration.keepsLatest {
            pinToLatestEdge(animated: false)
        } else if let anchor = restoration.anchor {
            restoreSnapshotAnchor(anchor)
        }
    }

    private func finishTimelineLayoutMutation(retryPendingNavigation: Bool = true) {
        guard ChatViewportRestorationAuthority.finishLayoutMutation(depth: &timelineLayoutMutationDepth) else { return }
        drainTimelineSnapshots()
        if retryPendingNavigation { applyPendingMessageNavigation() }
    }

    private func layoutForViewportCompletion() {
        viewportCompletionLayoutDepth += 1
        defer { viewportCompletionLayoutDepth -= 1 }
        collectionView.layoutIfNeeded()
    }

    private func restoreSnapshotAnchor(_ anchor: SnapshotAnchor) {
        guard !hasPendingMessageNavigation, !latestEdgeScrollInFlight,
              let indexPath = dataSource.indexPath(for: anchor.itemID),
              let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
        else { return }
        let insets = collectionView.adjustedContentInset
        let minimumOffset = -insets.top
        let maximumOffset = max(
            minimumOffset,
            collectionView.contentSize.height - collectionView.bounds.height + insets.bottom,
        )
        let desiredOffset = attributes.frame.minY - anchor.minYRelativeToViewport
        recordMessageNavigationGeometry("anchor-before", desiredOffset: desiredOffset, writer: "anchor")
        collectionView.setContentOffset(
            CGPoint(
                x: collectionView.contentOffset.x,
                y: min(max(desiredOffset, minimumOffset), maximumOffset),
            ),
            animated: false,
        )
        recordMessageNavigationGeometry("anchor-after")
    }

    /// A fresh collection view carries estimated heights everywhere. Landing makes the rows on screen self-size,
    /// which moves the anchor, so land again until it holds, as `centerCommittedMessage` does.
    private func landSnapshotAnchor(_ anchor: SnapshotAnchor) {
        timelineLayoutMutationDepth += 1
        defer { finishTimelineLayoutMutation(retryPendingNavigation: false) }
        for _ in 0..<4 {
            collectionView.layoutIfNeeded()
            guard let indexPath = dataSource.indexPath(for: anchor.itemID),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
            let current = attributes.frame.minY - collectionView.contentOffset.y
            guard abs(current - anchor.minYRelativeToViewport) > 0.5 else { return }
            restoreSnapshotAnchor(anchor)
        }
    }

    private func messageCellWillChangeHeight() {
        let userIsScrolling = collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
            || selectionInteractionActive
        guard didPerformInitialScroll,
              timelineLayoutMutationDepth == 0, !timelineSnapshots.isBusy,
              !userIsScrolling
        else { return }
        guard !selfSizingAnchorRestoreScheduled else { return }
        pendingSelfSizingRestoration = captureAutomaticViewportRestoration(
            allowInitial: false, ensuringLayout: false,
        )
        selfSizingAnchorRestoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard timelineLayoutMutationDepth == 0, !timelineSnapshots.isBusy else {
                pendingSelfSizingRestoration = nil
                selfSizingAnchorRestoreScheduled = false
                return
            }
            let restoration = pendingSelfSizingRestoration
            pendingSelfSizingRestoration = nil
            selfSizingAnchorRestoreScheduled = false
            let userIsScrolling = collectionView.isTracking
                || collectionView.isDragging
                || collectionView.isDecelerating
                || selectionInteractionActive
            guard !userIsScrolling, !hasPendingMessageNavigation else { return }
            timelineLayoutMutationDepth += 1
            defer { finishTimelineLayoutMutation() }
            synchronizeNativeSelection()
            layoutForViewportCompletion()
            restoreAutomaticViewport(restoration)
        }
    }

    private func reconfigureMessage(id: Int64) {
        guard let displayedID = chatVM.displayedMessageID(containing: id) else { return }
        reconfigureMessages(ids: [displayedID])
    }

    private func updateHighlightState() {
        // Any ChatVM publish lands here; only a highlight change reconfigures rows and retires viewport restoration.
        guard lastHighlightedMessageID != chatVM.highlightedMessageId else { return }
        let changed = Set([lastHighlightedMessageID, chatVM.highlightedMessageId].compactMap(\.self))
        lastHighlightedMessageID = chatVM.highlightedMessageId
        guard !changed.isEmpty else { return }
        let identifiers = Set(changed.compactMap { chatVM.displayedMessageID(containing: $0) })
        guard !identifiers.isEmpty else { return }
        viewportRestorationAuthority.invalidate()
        #if DEBUG
            viewportCompletionProbe?.interrupt("highlight snapshot changed")
            if messageNavigationGeometry?.isRecording == true {
                recordMessageNavigationGeometry("highlight-before", command: true)
            }
        #endif
        enqueueTimeline(.init(
            ids: identifiers,
            highlight: true,
            viewportRevision: viewportRestorationAuthority.invalidationRevision,
        ))
        #if DEBUG
            if messageNavigationGeometry?.isRecording == true {
                recordMessageNavigationGeometry("highlight-after", command: true)
            }
        #endif
    }

    /// ChatBotInfoItem in a bot chat without messages, otherwise Telegram's empty placeholder.
    private func emptyStateView() -> UIView {
        guard case .bot = chatVM.customChat.type, let info = chatVM.botInfo, !info.description.isEmpty else {
            return emptyLabel()
        }
        let container = UIView()
        let card = ChatBotInfoView(info: info, client: chatVM.client)
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)
        let preferredWidth = card.widthAnchor.constraint(equalToConstant: 320)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            card.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 24),
            preferredWidth,
        ])
        // The history is flipped; its background turns back upright.
        container.transform = CGAffineTransform(scaleX: 1, y: -1)
        return container
    }

    private func emptyLabel() -> UIView {
        let label = UILabel()
        label.text = L10n.telegram("Conversation.EmptyPlaceholder")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.transform = CGAffineTransform(scaleX: 1, y: -1)
        return label
    }

    private func updateHistoryInsets() {
        // The old client's permissions read as unavailable once the client is renewed, which would drop the composer
        // from the insets and move the history before the replacement controller takes over.
        guard !awaitsClientRenewal else { return }
        let visualBottomInset: CGFloat =
            if isSelectingMessages, messageSelectionToolbar.frame.minY > 0 {
                view.bounds.maxY - messageSelectionToolbar.frame.minY + 8
            } else if messageSearchActive {
                if messageSearchPanel.superview != nil, messageSearchPanel.frame.minY > 0 {
                    view.bounds.maxY - messageSearchPanel.frame.minY + 8
                } else {
                    max(
                        view.safeAreaInsets.bottom,
                        view.bounds.maxY - view.keyboardLayoutGuide.layoutFrame.minY,
                    ) + 8
                }
            } else if pollAddOptionFocusMessageID != nil {
                // The input panel steps aside for the poll's field, so the history ends at the keyboard.
                max(
                    view.safeAreaInsets.bottom,
                    view.bounds.maxY - view.keyboardLayoutGuide.layoutFrame.minY,
                ) + 8
            } else if showsComposer, composerView.frame.minY > 0 {
                max(view.safeAreaInsets.bottom, view.bounds.maxY - composerView.frame.minY) + 10
            } else {
                view.safeAreaInsets.bottom + 8
            }
        let visualTopInset = (pinnedMessageBannerHeightConstraint?.constant ?? 0) > 0
            || (voicePlaybackHeaderHeightConstraint?.constant ?? 0) > 0
            || (liveLocationPanelHeightConstraint?.constant ?? 0) > 0
            || (topicReopenBarHeightConstraint?.constant ?? 0) > 0
            ? topicReopenBar.frame.maxY + 8
            : customNavigationBar.frame.maxY + 8
        let updatedInsets = UIEdgeInsets(top: visualBottomInset, left: 0, bottom: visualTopInset, right: 0)
        guard abs(collectionView.contentInset.top - updatedInsets.top) > 0.5
            || abs(collectionView.contentInset.bottom - updatedInsets.bottom) > 0.5
        else { return }

        // Inset changes caused by this completion's own layout are part of its
        // compensation. Independent keyboard/layout changes retire older work.
        if viewportCompletionLayoutDepth == 0 {
            #if DEBUG
                viewportCompletionProbe?.interrupt("independent history insets changed")
            #endif
            viewportRestorationAuthority.invalidate()
        }
        let userIsScrolling = userIsScrollingTimeline
        let keepLatestVisible = !userIsScrolling && !hasPendingMessageNavigation
            && (!didPerformInitialScroll || isNearLatest)
        let previousOffset = collectionView.contentOffset
        let bottomInsetDelta = updatedInsets.top - collectionView.contentInset.top
        let anchor = !userIsScrolling && !hasPendingMessageNavigation && !keepLatestVisible
            ? captureSnapshotAnchor().map {
                // The timeline is inverted: preserve distance from the composer as its top edge moves.
                SnapshotAnchor(itemID: $0.itemID, minYRelativeToViewport: $0.minYRelativeToViewport + bottomInsetDelta)
            }
            : nil
        timelineLayoutMutationDepth += 1
        defer { finishTimelineLayoutMutation() }
        recordMessageNavigationGeometry("insets-before", keepsLatest: keepLatestVisible, writer: "insets")
        collectionView.contentInset = updatedInsets
        collectionView.verticalScrollIndicatorInsets = updatedInsets
        collectionView.layoutIfNeeded()
        // UIKit may shift its inset geometry; the explicit target remeasures it.
        // Replaying previousOffset would stop the native navigation animation.
        guard !hasPendingMessageNavigation else { return }
        if keepLatestVisible {
            pinToLatestEdge(animated: false)
        } else if let anchor {
            restoreSnapshotAnchor(anchor)
        } else {
            recordMessageNavigationGeometry(
                "insets-offset-before",
                desiredOffset: previousOffset.y,
                writer: "insets-offset",
            )
            collectionView.setContentOffset(previousOffset, animated: false)
        }
        // Measured from before the inset change: UIKit may already move the offset when the inset changes.
        if !pendingComposerSendTransitions.isEmpty || activeComposerSendAnimations > 0 {
            glideRowsAfterComposerSendShift(collectionView.contentOffset.y - previousOffset.y)
        }
        recordMessageNavigationGeometry("insets-after")
    }

    /// Telegram moves the history in the transaction that inserts a sent message and shrinks the input panel. Here
    /// the cleared composer shrinks just after the insertion, so pinning the history would jump it by the composer's
    /// change while the insertion still moves it the other way. The rows glide by that change on the insertion's
    /// curve instead, so the history settles in one move.
    private func glideRowsAfterComposerSendShift(_ shift: CGFloat) {
        guard abs(shift) > 0.5, view.window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let insertion = collectionView.visibleCells
            .lazy
            .compactMap { $0.layer.animation(forKey: "position") as? CABasicAnimation }
            .first { $0.isAdditive }
        // A copy keeps UIKit's curve, including a spring.
        let glide = (insertion?.copy() as? CABasicAnimation) ?? CABasicAnimation(keyPath: "position")
        if insertion == nil {
            glide.duration = 0.3
            glide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        glide.isAdditive = true
        glide.fromValue = CGPoint(x: 0, y: shift)
        glide.toValue = CGPoint.zero
        glide.byValue = nil
        composerSendGlideCount += 1
        composerSendGlides.append(.init(
            key: "chat.composerSendGlide.\(composerSendGlideCount)",
            animation: glide,
            start: CACurrentMediaTime(),
        ))
        collectionView.visibleCells.forEach(applyComposerSendGlides)
    }

    /// A row dequeued during a glide, or one whose animations were reset, joins it where the other rows are.
    private func applyComposerSendGlides(to cell: UICollectionViewCell) {
        guard !composerSendGlides.isEmpty else { return }
        let now = CACurrentMediaTime()
        composerSendGlides.removeAll { $0.end <= now }
        for glide in composerSendGlides where cell.layer.animation(forKey: glide.key) == nil {
            guard let animation = glide.animation.copy() as? CABasicAnimation else { continue }
            animation.beginTime = cell.layer.convertTime(glide.start, from: nil)
            cell.layer.add(animation, forKey: glide.key)
        }
    }

    private func invalidateSelfSizingLayoutPreservingAnchor() {
        guard isViewLoaded, didPerformInitialScroll else { return }
        let restoration = captureAutomaticViewportRestoration(allowInitial: false)
        timelineLayoutMutationDepth += 1
        defer { finishTimelineLayoutMutation() }
        collectionView.collectionViewLayout.invalidateLayout()
        layoutForViewportCompletion()
        restoreAutomaticViewport(restoration)
    }

    private func updateComposerFloatingState(_ keyboardAttached: Bool) {
        guard composerKeyboardAttached != keyboardAttached else { return }
        composerKeyboardAttached = keyboardAttached
        composerLeadingConstraint?.constant = keyboardAttached ? 8 : 0
        composerTrailingConstraint?.constant = keyboardAttached ? -8 : 0
        composerBottomConstraint?.constant = keyboardAttached ? -8 : 0
        let animated = view.window != nil
        composerView.setKeyboardAttached(keyboardAttached, animated: animated)
        guard animated else { return }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    private func message(for id: DisplayedMessageID) -> CustomMessage? {
        chatVM.messages.first(where: { $0.displayedID == id })
    }

    private func scrollToMessage(id: Int64, quote: MessageQuoteHighlight? = nil, opensQuoteSelection: Bool = false) {
        guard !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
        viewportRestorationAuthority.invalidate()
        cancelMessageNavigation()
        pendingReplyQuoteSelectionID = opensQuoteSelection ? id : nil
        #if DEBUG
            if ChatMessageNavigationGeometry.enabled, let source = navigationClientSource {
                messageNavigationGeometry = .init(messageID: id, source: source)
                recordMessageNavigationGeometry("request", command: true)
            }
        #endif
        abandonRestoredViewport()
        if chatVM.displayedMessageID(containing: id) != nil {
            recordMessageNavigationPhase("loaded")
            pendingScrollMessageID = id
            pendingQuoteHighlight = quote
            applyPendingMessageNavigation()
            return
        }
        recordMessageNavigationPhase("fetching")
        messageNavigationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled {
                    messageNavigationTask = nil
                    if !hasPendingMessageNavigation, !didPerformInitialScroll,
                       !clientOwnerRetired, chatVM.locationContextIsCurrent { updateSnapshot(animated: false) }
                    retryClientRestoration()
                }
            }
            guard let window = await chatVM.prepareMessageWindow(around: id),
                  !Task.isCancelled, !clientOwnerRetired, chatVM.locationContextIsCurrent
            else {
                if !Task.isCancelled, !clientOwnerRetired, chatVM.locationContextIsCurrent {
                    recordMessageNavigationPhase("failed")
                }
                return
            }
            pendingQuoteHighlight = quote
            chatVM.applyMessageWindow(window)
            pendingScrollMessageID = chatVM.displayedMessageID(containing: id) == nil ? nil : id
            if pendingScrollMessageID == nil {
                pendingQuoteHighlight = nil
                recordMessageNavigationPhase("target-not-admitted")
            } else { recordMessageNavigationPhase("window-ready") }
            messageNavigationTask = nil
            applyPendingMessageNavigation()
        }
    }

    private func cancelMessageNavigation() {
        if hasPendingMessageNavigation { recordMessageNavigationPhase("superseded") }
        messageNavigationTask?.cancel()
        messageNavigationTask = nil
        latestHistoryTask?.cancel()
        latestHistoryTask = nil
        pendingQuoteDestination = nil
        pendingScrollMessageID = nil
        pendingQuoteHighlight = nil
        pendingReplyQuoteSelectionID = nil
        messageNavigationScroll.cancel()
    }

    private func applyPendingMessageNavigation() {
        guard !timelineSnapshots.isBusy else { return }
        guard let id = pendingScrollMessageID else { return }
        if messageNavigationScroll.ownsViewport {
            messageNavigationScroll.layoutDidSettle()
            return
        }
        guard !clientOwnerRetired, chatVM.locationContextIsCurrent, let source = navigationClientSource,
              timelineLayoutMutationDepth == 0, !userIsScrollingTimeline, isViewLoaded,
              view.window != nil, navigationController?.topViewController === self,
              presentedViewController == nil, collectionView.bounds.height > 0 else { return }
        viewportRestorationAuthority.invalidate()
        if let displayed = chatVM.displayedMessageID(containing: id),
           !timelineSnapshots.committedContains(rawID: id, displayedID: displayed)
        {
            recordMessageNavigationPhase("awaiting-snapshot")
            updateSnapshot(animated: false)
            return
        }
        do {
            timelineLayoutMutationDepth += 1
            defer { finishTimelineLayoutMutation(retryPendingNavigation: false) }
            collectionView.layoutIfNeeded()
        }
        let animated = didPerformInitialScroll
        messageNavigationScroll.start(
            scrollView: collectionView, animated: animated,
            resolve: { [weak self] in self?.resolveMessageNavigation(id: id, source: source) ?? .cancelled },
            onCommand: { [weak self] target, animated in
                guard let self else { return }
                didPerformInitialScroll = true
                recordMessageNavigationPhase("offset-command")
                #if DEBUG
                    messageNavigationGeometry?.commandTarget = chatVM.displayedMessageID(containing: id)
                #endif
                recordMessageNavigationGeometry(
                    "command-before", desiredOffset: target.offset.y, animated: animated,
                    writer: "explicit-target", command: true,
                )
            },
            completion: { [weak self] outcome in
                guard let self, pendingScrollMessageID == id else { return }
                let quote = pendingQuoteHighlight
                let opensQuoteSelection = pendingReplyQuoteSelectionID == id
                pendingScrollMessageID = nil
                pendingQuoteHighlight = nil
                pendingReplyQuoteSelectionID = nil
                viewportRestorationAuthority.invalidate()
                switch outcome {
                case .settled:
                    recordMessageNavigationPhase("scroll-settled")
                    recordMessageNavigationGeometry("target-settled", settled: true)
                    if navigationClientSource == source, chatVM.locationContextIsCurrent {
                        if opensQuoteSelection {
                            presentReplyQuoteSelection(messageID: id, requiresFullyVisible: false)
                        } else {
                            highlightNavigatedMessage(id: id, quote: quote)
                        }
                    }
                case .missing: recordMessageNavigationPhase("target-missing")
                case .failed: recordMessageNavigationPhase("scroll-failed")
                case .cancelled: recordMessageNavigationPhase("superseded")
                }
                retryClientRestoration()
            },
        )
        scheduleMessageNavigationGeometryChecks()
    }

    private func resolveMessageNavigation(id: Int64, source: TdUpdateSource) -> ChatMessageNavigationScroll.Resolution {
        guard pendingScrollMessageID == id, !clientOwnerRetired, chatVM.locationContextIsCurrent,
              navigationClientSource == source, !userIsScrollingTimeline,
              navigationController?.topViewController === self, presentedViewController == nil,
              isViewLoaded, view.window != nil else { return .cancelled }
        guard timelineLayoutMutationDepth == 0, !timelineSnapshots.isBusy,
              collectionView.bounds.height > 0 else { return .deferred }
        guard let displayedID = chatVM.displayedMessageID(containing: id),
              message(for: displayedID)?.sourceMessages.contains(where: { $0.id == id }) == true
        else { return .missing }
        guard timelineSnapshots.committedContains(rawID: id, displayedID: displayedID) else { return .deferred }
        guard let path = dataSource.indexPath(for: .message(displayedID)),
              let attributes = collectionView.layoutAttributesForItem(at: path) else { return .deferred }
        let insets = collectionView.adjustedContentInset
        let visibleCenterOffset = (collectionView.bounds.height + insets.top - insets.bottom) / 2
        let minimum = -insets.top
        let maximum = max(minimum, collectionView.contentSize.height - collectionView.bounds.height + insets.bottom)
        let visible = collectionView.bounds.inset(by: insets)
        return .ready(.init(
            offset: CGPoint(
                x: collectionView.contentOffset.x,
                y: min(maximum, max(minimum, attributes.center.y - visibleCenterOffset)),
            ),
            isVisible: attributes.frame.intersects(visible)
                && collectionView.indexPathsForVisibleItems.contains(path)
                && collectionView.cellForItem(at: path) != nil,
        ))
    }

    private func highlightNavigatedMessage(id: Int64, quote: MessageQuoteHighlight?) {
        guard let displayedID = chatVM.displayedMessageID(containing: id),
              let indexPath = dataSource.indexPath(for: .message(displayedID)),
              message(for: displayedID)?.sourceMessages.contains(where: { $0.id == id }) == true else { return }
        messageHighlightTask?.cancel()
        chatVM.highlightedMessageId = id
        updateHighlightState()
        messageHighlightTask = Task { [weak self, weak chatVM] in
            try? await Task<Never, Never>.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            chatVM?.highlightedMessageId = nil
            self?.updateHighlightState()
            self?.messageHighlightTask = nil
        }
        if let quote {
            // ChatControllerLoadDisplayNode: when an edit removed the quoted text, only the message is highlighted.
            guard let target = message(for: displayedID)?.sourceMessages.first(where: { $0.id == id }),
                  let resolved = quote.resolved(in: target.content)
            else {
                showChatToast(L10n.telegram("Chat.ToastQuoteNotFound"))
                return
            }
            pendingQuoteDestination = PendingQuoteDestination(
                displayedMessageID: displayedID,
                quote: resolved,
                targetMessageID: id,
            )
            if let cell = collectionView.cellForItem(at: indexPath) as? MessageCell {
                applyPendingQuoteHighlight(to: cell, displayedMessageID: displayedID)
            }
        }
    }

    private func highlightMessage(id: Int64) {
        messageHighlightTask?.cancel()
        chatVM.highlightedMessageId = id
        updateHighlightState()
        messageHighlightTask = Task { [weak self, weak chatVM] in
            try? await Task<Never, Never>.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            chatVM?.highlightedMessageId = nil
            self?.updateHighlightState()
            self?.messageHighlightTask = nil
        }
    }

    private func recordMessageNavigationPhase(_ phase: String) {
        #if DEBUG
            ChatMessageNavigationDiagnostic.record(phase)
        #endif
    }

    private func recordMessageNavigationGeometry(
        _ event: StaticString,
        desiredOffset: CGFloat? = nil,
        animated: Bool? = nil,
        keepsLatest: Bool? = nil,
        writer: StaticString? = nil,
        command: Bool = false,
        settled: Bool = false,
        checkDelay: Double? = nil,
    ) {
        #if DEBUG
            guard let diagnostic = messageNavigationGeometry, diagnostic.isRecording, isViewLoaded else { return }
            diagnostic.record(event, writer: writer, lane: settled ? .settled : command ? .command : .event) {
                messageNavigationGeometryValues(
                    diagnostic, desiredOffset: desiredOffset, animated: animated,
                    keepsLatest: keepsLatest, checkDelay: checkDelay,
                )
            }
        #endif
    }

    private func scheduleMessageNavigationGeometryChecks() {
        #if DEBUG
            guard let diagnostic = messageNavigationGeometry, diagnostic.beginSettledChecks() else { return }
            for delay in [0.0, 0.05, 0.25, 0.75, 1.25, 3, 10, 25] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, messageNavigationGeometry === diagnostic else { return }
                    recordMessageNavigationGeometry("settled", settled: true, checkDelay: delay)
                    if delay == 25 { diagnostic.finish() }
                }
            }
        #endif
    }

    private func applyPendingQuoteHighlight(to cell: MessageCell, displayedMessageID: DisplayedMessageID) {
        guard let destination = pendingQuoteDestination,
              destination.displayedMessageID == displayedMessageID
        else { return }
        pendingQuoteDestination = nil
        guard message(for: displayedMessageID)?.sourceMessages.contains(where: {
            $0.id == destination.targetMessageID
        }) == true else { return }
        cell.highlightQuote(destination.quote, messageID: destination.targetMessageID)
    }

    /// Telegram opens self-destructing media alone in SecretMediaPreviewController, which consumes it on the
    /// message's own client (ChatControllerImpl openMessage with `isSecretMedia`).
    private func presentSecretMedia(_ message: Message) {
        guard presentedViewController == nil, let permit = mediaRevealSession?.permit(for: message),
              permit.matches(message),
              let backend = VideoNotePlaybackBackend.captured(client: chatVM.client, context: galleryPlaybackContext),
              let controller = SecretMediaPreviewViewController(
                  message: message,
                  backend: backend,
                  permit: permit,
                  peerTitle: chatVM.customChat.user?.compactDisplayTitle ?? chatVM.customChat.displayTitle,
              )
        else { return }
        view.endEditing(true)
        present(controller, animated: true)
    }

    private func showMedia(_ messages: [Message], selection: Int64) {
        guard let galleryPlaybackContext, galleryPlaybackContext.isCurrent else { return }
        guard let captured = messages.first(where: { $0.id == selection }),
              let displayedID = chatVM.displayedMessageID(containing: selection),
              let current = message(for: displayedID)?.sourceMessages.first(where: { $0.id == selection })
        else { return }
        switch mediaRevealSession?.timelineTap(captured: captured, current: current) ?? .rejected {
        case .rejected:
            return
        case .revealed:
            reconfigureMessage(id: selection)
            DispatchQueue.main.async { [weak self] in self?.updateInlineVideoPlaybackVisibility() }
            return
        case .openSecret:
            presentSecretMedia(current)
            return
        case .open:
            break
        }
        // Telegram opens a sticker's pack (OpenChatMessage, StickerPackScreen) instead of a gallery.
        if case .messageSticker(let content) = current.content, content.sticker.setId != 0 {
            presentStickerPack(setID: content.sticker.setId)
            return
        }
        let messages = messages.compactMap { captured -> Message? in
            guard let displayedID = chatVM.displayedMessageID(containing: captured.id) else { return nil }
            return message(for: displayedID)?.sourceMessages.first(where: { $0.id == captured.id })
        }
        // Chat photos and videos open in one gallery of every loaded chat media item, as in Telegram. Self-destructing
        // media stays out of it and opens alone, as Telegram keeps secret media out of the history gallery.
        let isChatMedia = messages.first(where: { $0.id == selection }).map { message in
            message.selfDestructType == nil && Self.isChatGalleryMedia(message)
        } ?? false
        let galleryMessages: [Message]
        if isChatMedia {
            let loaded = (chatVM.messages.flatMap(\.sourceMessages) + messages).filter { message in
                message.selfDestructType == nil && Self.isChatGalleryMedia(message) && location
                    .matches(message: message)
            }
            galleryMessages = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                .values
                .sorted { $0.id > $1.id }
        } else {
            galleryMessages = messages
        }
        mediaRevealSession?.reconcile(galleryMessages)
        let transferredOwners = galleryMessages.compactMap { message -> GalleryVideoPlaybackOwner? in
            guard let owner = inlineVideoPlaybackOwners[message.id], owner.matches(message: message) else { return nil }
            return owner
        }
        let transferredOwner = transferredOwners.first { $0.messageID == selection }
        let transitionSource = galleryTransitionTarget(for: selection)
        pauseInlineVideoPlayback(excluding: transferredOwner?.messageID)
        let gallery = MediaGalleryViewController(
            messages: galleryMessages,
            selection: selection,
            tdlib: tdlib,
            actionClient: chatVM.client,
            sourceLocation: location,
            playbackContext: galleryPlaybackContext,
            mediaRevealSession: mediaRevealSession,
            transferredPlaybackOwner: transferredOwner,
            transferredPlaybackOwners: transferredOwners,
            transitionSource: transitionSource,
            transitionSourceProvider: { [weak self] messageID in
                self?.galleryTransitionTarget(for: messageID)
            },
        )
        gallery.contextIsCurrent = { [weak self] in
            guard let self else { return false }
            // A same-account client renewal keeps the route: the gallery reloads its items through the renewed
            // client, and this chat is replaced once the gallery closes.
            return TDLib.shared.activeAccountID == location.accountID && routeIsRetained
        }
        gallery.onPrepareOpenMessageID = { [weak self] messageID in
            await self?.prepareGalleryReturn(to: messageID) ?? false
        }
        gallery.openInChatTransitionSourceProvider = { [weak self] messageID in
            self?.galleryReturnTarget(for: messageID)
        }
        gallery.onOpenMessageTransitionCompleted = { [weak self] messageID in
            self?.highlightMessage(id: messageID)
        }
        if chatVM.canWriteBasicMessages {
            gallery.onReplyToMessageID = { [weak self] messageID in self?.replyFromGallery(to: messageID) }
        }
        if isChatMedia { gallery.enableChatHistoryPaging(client: chatVM.client, location: location) }
        // End the composer's editing session before UIKit retains it for the modal transition.
        // Otherwise cancelling an interactive dismissal can restore its keyboard over the gallery.
        view.endEditing(true)
        present(gallery, animated: true)
    }

    /// The gallery's Reply: the message becomes the composer's reply, as its context menu's Reply does.
    private func replyFromGallery(to messageID: Int64) {
        Task { [weak self] in
            guard let self, let message = await chatVM.getCustomMessage(fromId: messageID),
                  chatVM.locationContextIsCurrent, message.properties.canBeReplied
            else { return }
            chatVM.beginReply(to: message)
        }
    }

    private func prepareGalleryReturn(to messageID: Int64) async -> Bool {
        guard TDLib.shared.activeAccountID == location.accountID,
              TDLib.shared.activeClient.id == location.clientID
        else { return false }
        cancelMessageNavigation()
        if chatVM.displayedMessageID(containing: messageID) == nil {
            guard let window = await chatVM.prepareMessageWindow(around: messageID),
                  !Task.isCancelled
            else { return false }
            chatVM.applyMessageWindow(window)
        }
        updateSnapshot(animated: false)
        // The frozen timeline commits asynchronously; wait a bounded time for the target row.
        func targetIsCommitted() -> Bool {
            guard let displayedID = chatVM.displayedMessageID(containing: messageID) else { return false }
            return timelineSnapshots.committedContains(rawID: messageID, displayedID: displayedID)
                && !timelineSnapshots.isBusy
        }
        for _ in 0..<180 {
            if targetIsCommitted() || clientOwnerRetired { break }
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return false }
        }
        // Fail rather than return to a row the timeline hasn't laid out: centering and the return flight need its
        // frame.
        return !Task.isCancelled && !clientOwnerRetired
            && TDLib.shared.activeAccountID == location.accountID
            && TDLib.shared.activeClient.id == location.clientID
            && targetIsCommitted()
    }

    private func galleryReturnTarget(for messageID: Int64) -> MediaGalleryTransitionTarget? {
        guard let displayedID = chatVM.displayedMessageID(containing: messageID) else { return nil }
        // Resolve after the presenting navigation stack has been reattached to the window.
        view.layoutIfNeeded()
        updateHistoryInsets()
        centerCommittedMessage(displayedID)
        collectionView.layoutIfNeeded()
        return galleryTransitionTarget(for: messageID)
    }

    /// Centers a committed message without animation, so a returning gallery lands on its current frame.
    private func centerCommittedMessage(_ displayedID: DisplayedMessageID) {
        guard let path = dataSource.indexPath(for: .message(displayedID)) else { return }
        viewportRestorationAuthority.invalidate()
        // Rows away from the viewport carry estimated heights. Landing makes them self-size, which moves the target,
        // so center again until it settles. The mutation depth keeps self-sizing from scheduling its own restore.
        timelineLayoutMutationDepth += 1
        defer { finishTimelineLayoutMutation(retryPendingNavigation: false) }
        for _ in 0..<4 {
            collectionView.layoutIfNeeded()
            guard let attributes = collectionView.layoutAttributesForItem(at: path) else { return }
            let insets = collectionView.adjustedContentInset
            let visibleCenterOffset = (collectionView.bounds.height + insets.top - insets.bottom) / 2
            let minimum = -insets.top
            let maximum = max(
                minimum,
                collectionView.contentSize.height - collectionView.bounds.height + insets.bottom,
            )
            // Telegram's `.center(.bottom)` in its flipped list: a row taller than the content area shows its top,
            // which here is the row's maxY at the bottom inset under the navigation bar.
            let contentHeight = collectionView.bounds.height - insets.top - insets.bottom
            let proposedY = attributes.size.height > contentHeight
                ? attributes.frame.maxY - collectionView.bounds.height + insets.bottom
                : attributes.center.y - visibleCenterOffset
            let targetY = min(maximum, max(minimum, proposedY))
            guard abs(collectionView.contentOffset.y - targetY) > 0.5 else { break }
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: targetY), animated: false)
        }
        didPerformInitialScroll = true
    }

    private func navigate(to target: MessageMetadataNavigationTarget) {
        metadataNavigationTask?.cancel()
        metadataNavigationTask = nil
        pendingQuoteDestination = nil
        switch target {
        case .message(let chatID, let messageID, let quote) where chatID == chatVM.chatID:
            if location.isTopicScoped {
                navigateToMessageInCurrentChat(messageID: messageID, quote: quote)
            } else {
                scrollToMessage(id: messageID, quote: quote)
            }
        case .message(let chatID, let messageID, let quote):
            openMetadataChat(chatID: chatID, targetMessageID: messageID, quote: quote)
        case .chat(let chatID) where chatID == chatVM.chatID:
            break
        case .chat(let chatID):
            openMetadataChat(chatID: chatID, targetMessageID: nil, quote: nil)
        case .unavailable:
            presentMetadataUnavailable()
        case .user(let userID):
            let client = chatVM.client
            let accountID = TDLib.shared.activeAccountID
            metadataNavigationTask = Task { [weak self] in
                guard let self, !Task.isCancelled else { return }
                defer { if !Task.isCancelled { metadataNavigationTask = nil
                    retryClientRestoration()
                } }
                let chat = try? await client.createPrivateChat(force: false, userId: userID)
                guard !Task.isCancelled,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                guard let chat else {
                    presentMetadataUnavailable()
                    return
                }
                guard let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client)
                else {
                    presentMetadataUnavailable()
                    return
                }
                guard !Task.isCancelled, chatVM.locationContextIsCurrent, routeIsRetained else { return }
                NavigationStorage.shared.push(.customChat(customChat))
                metadataNavigationTask = nil
            }
        }
    }

    private func openForumTopic(id: Int) {
        guard presentationMode == .full,
              navigationController?.topViewController === self
        else { return }
        metadataNavigationTask?.cancel()
        let client = chatVM.client
        let currentLocation = location
        metadataNavigationTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { metadataNavigationTask = nil
                retryClientRestoration()
            } }
            let topic = try? await client.getForumTopic(
                chatId: currentLocation.chatID,
                forumTopicId: id,
            )
            guard !Task.isCancelled,
                  TDLib.shared.activeAccountID == currentLocation.accountID,
                  TDLib.shared.activeClient.id == currentLocation.clientID,
                  navigationController?.topViewController === self,
                  let topic
            else {
                metadataNavigationTask = nil
                return
            }
            NavigationStorage.shared.push(.customChat(
                chatVM.customChat,
                location: currentLocation.withForumTopic(id: id),
                forumTopic: topic,
            ))
            metadataNavigationTask = nil
        }
    }

    private func navigateToMessageInCurrentChat(
        messageID: Int64,
        quote: MessageQuoteHighlight?,
    ) {
        let client = chatVM.client
        let currentLocation = location
        metadataNavigationTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { metadataNavigationTask = nil
                retryClientRestoration()
            } }
            let message = try? await client.getMessage(
                chatId: currentLocation.chatID,
                messageId: messageID,
            )
            guard !Task.isCancelled,
                  TDLib.shared.activeAccountID == currentLocation.accountID,
                  TDLib.shared.activeClient.id == currentLocation.clientID,
                  let message
            else { return }
            if currentLocation.matches(message: message) {
                scrollToMessage(id: messageID, quote: quote)
                metadataNavigationTask = nil
                return
            }
            // Telegram leaves a reply thread for a message outside it and shows the message in its chat.
            if currentLocation.messageThreadID != nil {
                guard !Task.isCancelled, chatVM.locationContextIsCurrent, routeIsRetained,
                      message.chatId == currentLocation.chatID else { return }
                NavigationStorage.shared.push(.customChat(
                    chatVM.customChat,
                    targetMessageID: messageID,
                    targetQuote: quote,
                ))
                metadataNavigationTask = nil
                return
            }
            guard case .messageTopicForum(let forumTopic) = message.topicId,
                  let topic = try? await client.getForumTopic(
                      chatId: currentLocation.chatID,
                      forumTopicId: forumTopic.forumTopicId,
                  )
            else {
                presentMetadataUnavailable()
                return
            }
            guard !Task.isCancelled, chatVM.locationContextIsCurrent, routeIsRetained else { return }
            NavigationStorage.shared.push(.customChat(
                chatVM.customChat,
                location: currentLocation.withForumTopic(id: forumTopic.forumTopicId),
                forumTopic: topic,
                targetMessageID: messageID,
                targetQuote: quote,
            ))
            metadataNavigationTask = nil
        }
    }

    private func openMetadataChat(
        chatID: Int64,
        targetMessageID: Int64?,
        quote: MessageQuoteHighlight?,
    ) {
        let client = chatVM.client
        let accountID = TDLib.shared.activeAccountID
        metadataNavigationTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            defer { if !Task.isCancelled { metadataNavigationTask = nil
                retryClientRestoration()
            } }
            guard TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            let customChat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
            guard !Task.isCancelled,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            guard let customChat else {
                presentMetadataUnavailable()
                return
            }
            NavigationStorage.shared.push(.customChat(
                customChat,
                targetMessageID: targetMessageID,
                targetQuote: quote,
            ))
            metadataNavigationTask = nil
        }
    }

    private func presentMetadataUnavailable() {
        metadataNavigationTask = nil
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.betterTG("Chat.MessageUnavailableTitle"),
            message: L10n.betterTG("Chat.MessageUnavailableText"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    private func expandReplyQuote(for message: CustomMessage) {
        guard !message.isReplyQuoteExpanded else { return }
        #if DEBUG
            viewportCompletionProbe?.interrupt("reply quote snapshot changed")
        #endif
        message.isReplyQuoteExpanded = true
        enqueueTimeline(.init(
            ids: [message.displayedID],
            quoteID: message.displayedID,
            viewportRevision: viewportRestorationAuthority.invalidationRevision,
        ))
    }

    private func performContentAction(_ action: MessageContentAction, for message: CustomMessage) {
        switch action {
        case .richContentLayoutChanged:
            collectionView.collectionViewLayout.invalidateLayout()
        case .openContact(let contact):
            // ChatMessageContactBubbleContentNode.contactTap: a Telegram user opens their profile.
            if contact.userId != 0 {
                openContactProfile(userID: contact.userId)
            } else {
                presentContactDetails(contact)
            }
        case .messageContact(let userID):
            navigate(to: .user(userID: userID))
        case .viewContact(let contact):
            presentContactDetails(contact)
        case .diceTapped(let emoji):
            presentDiceTooltip(emoji: emoji)
        case .openServiceTarget(let messageID):
            navigate(to: .message(chatID: chatVM.chatID, messageID: messageID, quote: nil))
        case .openChatPhoto(let photo):
            presentChatPhoto(photo)
        case .openDocument(let url):
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 1,
                height: 1,
            )
            present(activity, animated: true)
        case .openLocation(let location, _):
            // Telegram opens a location, venue or live location message in LocationViewController.
            let subject = message.sourceMessages.lazy.compactMap { LocationViewSubject(message: $0) }.first
                ?? LocationViewSubject(location: location)
            presentLocationViewer(subject)
        case .submitPollAnswer(let messageID, let optionIDs, let submission):
            chatVM.submitPollAnswer(messageID: messageID, optionIDs: optionIDs, submission: submission)
        case .addPollOption(let messageID, let text, let submission):
            chatVM.addPollOption(messageID: messageID, text: text, submission: submission) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        case .openPollResults(let messageID, let optionID):
            openPollResults(messageID: messageID, optionID: optionID, in: message)
        case .openPollMedia(let messageID, let media):
            openPollMedia(media, messageID: messageID, in: message)
        case .cancelSending(let messageID):
            // ChatMessageInteractiveMediaNode.progressPressed deletes a sending message for everyone.
            chatVM.deleteMessages(ids: [messageID], deleteForBoth: true)
        case .pressInlineKeyboardButton(let press):
            guard let source = message.sourceMessages.first(where: { $0.id == press.messageID }) else { return }
            inlineKeyboardActions.perform(press, in: source, client: chatVM.client)
        case .openComments(let messageID):
            openComments(messageID: messageID, displayedID: message.displayedID)
        case .toggleChecklistTask(let toggle):
            chatVM.toggleChecklistTask(toggle) { [weak self] in
                self?.showChatToast(ChatVM.checklistPremiumRequiredText)
            }
        case .checklistToggleUnavailable(let messageID):
            presentChecklistToggleUnavailable(messageID: messageID, in: message)
        case .openStory(let posterChatID, let storyID, let sourceView, let sourceIsRound):
            openStory(
                posterChatID: posterChatID,
                storyID: storyID,
                sourceView: sourceView,
                sourceIsRound: sourceIsRound,
            )
        }
    }

    /// Telegram's LocationViewController for the chat: a live location shares the account's own from it where live
    /// locations can be sent, except in a channel where the account isn't sharing one.
    private func presentLocationViewer(_ subject: LocationViewSubject, showsAllLiveLocations: Bool = false) {
        guard !clientOwnerRetired, presentedViewController == nil else { return }
        view.endEditing(true)
        let isChannel = chatVM.customChat.supergroup?.isChannel == true
        let viewer = LocationViewController(
            subject: subject,
            client: chatVM.client,
            source: navigationClientSource,
            canShareLiveLocation: chatVM.canShareLiveLocation && chatVM.canSendLocationAndContact && !isChannel,
            peerName: chatVM.liveLocationPeerName,
            showsAllLiveLocations: showsAllLiveLocations,
        ) { [weak chatVM] content in
            Task { await chatVM?.sendAttachmentContents([content], kind: .text) }
        }
        present(viewer.makeNavigationController(), animated: true)
    }

    /// Telegram's openChatMessage opens a shared story or a mention on its own in the story viewer
    /// (SingleStoryContentContextImpl), which marks it viewed, or says it's gone (Story.TooltipExpired).
    private func openStory(posterChatID: Int64, storyID: Int, sourceView: UIView, sourceIsRound: Bool) {
        guard presentationMode == .full, !clientOwnerRetired, chatVM.locationContextIsCurrent,
              presentedViewController == nil else { return }
        view.endEditing(true)
        StoryViewerController.present(
            .story(chatID: posterChatID, storyID: storyID),
            client: chatVM.client,
            from: self,
            sourceView: sourceView,
            sourceIsAvatar: sourceIsRound,
        ) { [weak self] in
            self?.showChatToast(L10n.telegram("Story.TooltipExpired"))
        }
    }

    /// Telegram's displayTodoToggleUnavailable: a forwarded checklist can't change, a scheduled one waits for its
    /// publication, marking needs Telegram Premium, and otherwise the author keeps the tasks to themselves.
    private func presentChecklistToggleUnavailable(messageID: Int64, in message: CustomMessage) {
        guard let source = message.sourceMessages.first(where: { $0.id == messageID }) else { return }
        if source.forwardInfo != nil {
            showChatToast(L10n.telegram("Chat.Todo.CompletionLimitedForward"))
            return
        }
        if source.schedulingState != nil {
            chatVM.messageActionErrorMessage = L10n.telegram("ScheduledMessages.TodoUnavailable")
            return
        }
        let author = message.senderUser?.compactDisplayTitle ?? chatVM.customChat.chat.title
        Task { [weak self] in
            guard let self, let isPremium = await chatVM.accountHasPremium(), chatVM.locationContextIsCurrent
            else { return }
            showChatToast(isPremium
                ? L10n.telegram("Chat.Todo.CompletionLimited", author)
                : ChatVM.checklistPremiumRequiredText)
        }
    }

    /// Telegram's Add a Task: the checklist editor on the empty task after the list.
    private func presentAddChecklistTask(_ message: CustomMessage) {
        openChecklistEditor(message, focusedTaskID: nil, appends: true)
    }

    /// ChatControllerOpenAttachmentMenu's openTodoEditing: the checklist editor for a published checklist, Edit
    /// Checklist where it may be edited and Add a Task otherwise, after the Telegram Premium check Telegram makes.
    private func openChecklistEditor(_ message: CustomMessage, focusedTaskID: Int?, appends: Bool) {
        guard presentedViewController == nil else { return }
        Task { [weak self, weak message] in
            guard let self, let isPremium = await chatVM.accountHasPremium(), let message,
                  chatVM.locationContextIsCurrent, presentedViewController == nil,
                  case .messageChecklist(let content) = message.message.content
            else { return }
            guard isPremium else {
                presentChecklistPremiumNotice()
                return
            }
            let canEdit = chatVM.canEditChecklist(message)
            guard canEdit || chatVM.canAddChecklistTask(message) else { return }
            let editor = ChecklistComposerViewController(
                client: chatVM.client,
                accountID: chatVM.accountID,
                chatID: chatVM.chatID,
                existing: ChecklistComposerViewController.Existing(
                    checklist: content.list,
                    focusedTaskID: focusedTaskID,
                    appends: appends,
                    canEdit: canEdit,
                ),
            ) { [weak chatVM = self.chatVM, weak message] outcome in
                guard let chatVM, let message else { return }
                chatVM.applyChecklistEditor(outcome, to: message)
            }
            editor.onDismiss = { [weak self] in self?.retryClientRestoration() }
            present(editor.makeNavigationController(), animated: true)
        }
    }

    /// PremiumDemoScreen's checklist page, without the subscription it offers.
    private func presentChecklistPremiumNotice(onDismiss: (() -> Void)? = nil) {
        guard presentedViewController == nil else {
            onDismiss?()
            return
        }
        let alert = UIAlertController(
            title: L10n.telegram("Premium.Todo"),
            message: L10n.telegram("Premium.TodoInfo"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .cancel) { _ in onDismiss?() })
        present(alert, animated: true)
    }

    /// Telegram's `openMessageReplies`: a post's comments are a thread in the channel's discussion group, found with
    /// `getMessageThread` on this chat's client, and open as that thread's own chat (`ChatLocation.replyThread`).
    private func openComments(messageID: Int64, displayedID: DisplayedMessageID) {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent,
              navigationController?.topViewController === self, commentsThreadLoad == nil
        else { return }
        metadataNavigationTask?.cancel()
        let client = chatVM.client
        let currentLocation = location
        let loadID = UUID()
        setCommentsThreadLoad((id: loadID, displayedID: displayedID))
        metadataNavigationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if commentsThreadLoad?.id == loadID { setCommentsThreadLoad(nil) }
                if !Task.isCancelled {
                    metadataNavigationTask = nil
                    retryClientRestoration()
                }
            }
            let thread = try? await client.getMessageThread(chatId: currentLocation.chatID, messageId: messageID)
            guard !Task.isCancelled,
                  TDLib.shared.activeAccountID == currentLocation.accountID,
                  TDLib.shared.activeClient.id == currentLocation.clientID
            else { return }
            guard let thread else {
                presentMetadataUnavailable()
                return
            }
            let discussion = await RootVM.shared.getCustomChatForNavigation(from: thread.chatId, client: client)
            guard !Task.isCancelled,
                  TDLib.shared.activeAccountID == currentLocation.accountID,
                  TDLib.shared.activeClient.id == currentLocation.clientID,
                  chatVM.locationContextIsCurrent, routeIsRetained,
                  navigationController?.topViewController === self
            else { return }
            guard let discussion else {
                presentMetadataUnavailable()
                return
            }
            NavigationStorage.shared.push(.customChat(
                discussion,
                location: currentLocation.withMessageThread(chatID: thread.chatId, id: thread.messageThreadId),
                messageThread: thread,
            ))
            metadataNavigationTask = nil
        }
    }

    /// ChatInterfaceStateContextMenus: in a group chat (not inside a thread), a message with replies offers
    /// "View N Replies", and in a discussion group a message from a comment thread offers "View Thread". Both open the
    /// thread through `openMessageReplies`.
    private func viewRepliesTitle(for message: CustomMessage) -> String? {
        guard location.topic == nil, let supergroup = chatVM.customChat.supergroup, !supergroup.isChannel,
              !supergroup.isForum, message.message.sendingState == nil, message.properties.canGetMessageThread
        else { return nil }
        if supergroup.hasLinkedChat, case .messageTopicThread? = message.message.topicId {
            return L10n.telegram("Conversation.ContextViewThread")
        }
        let count = message.message.interactionInfo?.replyInfo?.replyCount ?? 0
        return count > 0 ? L10n.telegramPlural("Conversation.ContextViewReplies", count: count) : nil
    }

    private func setCommentsThreadLoad(_ load: (id: UUID, displayedID: DisplayedMessageID)?) {
        let previous = commentsThreadLoad?.displayedID
        commentsThreadLoad = load
        for case let cell as MessageCell in collectionView.visibleCells {
            guard let displayedID = cell.timelineDisplayedID,
                  displayedID == previous || displayedID == load?.displayedID else { continue }
            cell.setCommentsLoading(displayedID == load?.displayedID)
        }
    }

    /// Telegram opens a photoUpdated action's image in the avatar gallery (`.chatAvatars`).
    private func presentChatPhoto(_ photo: ChatPhoto) {
        guard presentedViewController == nil, let accountID = location.accountID else { return }
        let item = ProfileAvatarGalleryItem(photo: photo)
        let gallery = ProfileAvatarGalleryViewController(
            accountID: accountID,
            client: chatVM.client,
            items: [item],
            selection: item.id,
            totalCount: 1,
            transitionSource: nil,
            transitionSourceProvider: nil,
        )
        gallery.contextIsCurrent = { [weak self] in
            guard let self else { return false }
            return TDLib.shared.activeAccountID == accountID && chatVM.locationContextIsCurrent
        }
        gallery.allowsSaving = !chatVM.customChat.chat.hasProtectedContent
        present(gallery, animated: true)
    }

    private func presentContactDetails(_ contact: Contact) {
        guard presentedViewController == nil else { return }
        let details = TelegramContactDetailsViewController(contact: contact, client: chatVM.client)
        details.onSendMessage = { [weak self] userID in
            self?.dismiss(animated: true) { [weak self] in
                self?.navigate(to: .user(userID: userID))
            }
        }
        let navigation = TelegramNavigationController(rootViewController: details)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }

    /// Telegram's poll results (requestOpenMessagePollResults), pushed on this chat's client as the profile's member
    /// list is.
    private func openPollResults(messageID: Int64, optionID: Int?, in message: CustomMessage) {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent,
              let accountID = location.accountID,
              let source = message.sourceMessages.first(where: { $0.id == messageID }),
              case .messagePoll(let content) = source.content,
              let navigation = navigationController, navigation.topViewController === self
        else { return }
        let results = PollResultsViewController(
            chatID: source.chatId,
            messageID: messageID,
            poll: content.poll,
            focusedOptionID: optionID,
            client: chatVM.client,
            accountID: accountID,
        )
        navigation.pushViewController(results, animated: true)
    }

    /// Telegram's openPollMedia (ChatControllerOpenPollOptionMedia): a sticker offers Add to Favorites and View
    /// Sticker Set, a link opens behind the hidden link alert, and other media open as their own message would: a
    /// photo, video or GIF alone in the gallery, a place in the location viewer, and a file as a file message's.
    private func openPollMedia(_ media: TDNativePollMedia, messageID: Int64, in message: CustomMessage) {
        guard presentationMode == .full, !clientOwnerRetired, chatVM.locationContextIsCurrent,
              presentedViewController == nil else { return }
        view.endEditing(true)
        switch media {
        case .pollMediaSticker(let value):
            presentPollSticker(value.sticker)
        case .pollMediaLink(let value):
            openPollLink(value.url)
        case .pollMediaLocation(let value):
            presentLocationViewer(LocationViewSubject(location: value.location))
        case .pollMediaVenue(let value):
            presentLocationViewer(LocationViewSubject(venue: value.venue))
        case .pollMediaDocument(let value):
            openPollFile(value.document.document, audio: nil, messageID: messageID, in: message)
        case .pollMediaAudio(let value):
            openPollFile(value.audio.audio, audio: value.audio, messageID: messageID, in: message)
        case .pollMediaAnimation, .pollMediaPhoto, .pollMediaVideo:
            presentPollMediaGallery(media, messageID: messageID, in: message)
        }
    }

    /// Telegram opens a poll's photo, video or GIF in a standalone gallery (openChatMessage with `standalone` and the
    /// poll media subject), described in PollMediaGallery.
    private func presentPollMediaGallery(_ media: TDNativePollMedia, messageID: Int64, in message: CustomMessage) {
        guard let galleryPlaybackContext, galleryPlaybackContext.isCurrent,
              let accountID = location.accountID,
              let source = message.sourceMessages.first(where: { $0.id == messageID }),
              let pollGallery = PollMediaGallery(media: media, in: source)
        else { return }
        let gallery = MediaGalleryViewController(
            messages: pollGallery.pages,
            selection: pollGallery.selection,
            tdlib: tdlib,
            actionClient: chatVM.client,
            playbackContext: galleryPlaybackContext,
            embeddedMediaSource: pollGallery.embeddedSource(accountID: accountID, clientID: location.clientID),
        )
        gallery.contextIsCurrent = { [weak self] in
            guard let self else { return false }
            return TDLib.shared.activeAccountID == location.accountID && routeIsRetained
        }
        present(gallery, animated: true)
    }

    /// Telegram's poll sticker peek menu (openPollMedia): Add to or Remove from Favorites, and View Sticker Set.
    private func presentPollSticker(_ sticker: Sticker) {
        let fileID = sticker.sticker.id
        let isFavorite = favoriteStickerFileIDs.contains(fileID)
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: L10n.telegram(isFavorite ? "Stickers.RemoveFromFavorites" : "Stickers.AddToFavorites"),
            style: .default,
        ) { [weak self] _ in self?.setStickerFavorite(fileID: fileID, favorite: !isFavorite) })
        if sticker.setId != 0 {
            let setID = sticker.setId
            sheet
                .addAction(UIAlertAction(
                    title: L10n.telegram("StickerPack.ViewPack"),
                    style: .default,
                ) { [weak self] _ in
                    self?.presentStickerPack(setID: setID)
                })
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1,
        )
        present(sheet, animated: true)
    }

    /// Telegram opens a poll's link concealed (openUserGeneratedUrl with `forceConcealed`), so it always asks first.
    private func openPollLink(_ string: String) {
        guard let url = getUrl(from: string) else { return }
        let displayURL = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("Generic.OpenHiddenLinkAlert", displayURL),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.No"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Yes"), style: .default) { [weak self] _ in
            guard let self, chatVM.locationContextIsCurrent else { return }
            TelegramLinkRouter.shared.open(url, from: self)
        })
        present(alert, animated: true)
    }

    /// A poll's file opens as a file message's does: downloaded, then an audio file plays and a document goes to the
    /// share sheet.
    private func openPollFile(_ file: File, audio: Audio?, messageID: Int64, in message: CustomMessage) {
        pollMediaTask?.cancel()
        let client = chatVM.client
        pollMediaTask = Task { [weak self] in
            let downloaded = try? await client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            )
            guard let self, !Task.isCancelled else { return }
            pollMediaTask = nil
            guard !clientOwnerRetired, chatVM.locationContextIsCurrent, let downloaded,
                  downloaded.local.isDownloadingCompleted, !downloaded.local.path.isEmpty else { return }
            if let audio {
                // openChatMessage's standalone playlist for the poll: the header names the track and opens the poll.
                let item = Media.NowPlaying(
                    accountID: location.accountID,
                    chatID: message.message.chatId,
                    messageID: messageID,
                    isFile: true,
                )
                Media.shared.toggle(with: downloaded.local.path, duration: audio.duration, item: item)
                Media.shared.setDisplay(.music(audio, item: item))
            } else if presentedViewController == nil {
                performContentAction(.openDocument(URL(fileURLWithPath: downloaded.local.path)), for: message)
            }
        }
    }

    /// Opens a user's profile on this chat's client (Telegram's `openPeer(.info)` for a shared contact or a user
    /// button), or this chat's own profile when the user is its peer.
    private func openContactProfile(userID: Int64) {
        guard presentationMode == .full, routeIsRetained, chatVM.locationContextIsCurrent,
              let accountID = location.accountID else { return }
        metadataNavigationTask?.cancel()
        let client = chatVM.client
        metadataNavigationTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            defer { if !Task.isCancelled { metadataNavigationTask = nil
                retryClientRestoration()
            } }
            let chat = try? await client.createPrivateChat(force: false, userId: userID)
            guard !Task.isCancelled,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            guard let chat,
                  let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client)
            else {
                presentMetadataUnavailable()
                return
            }
            guard !Task.isCancelled, chatVM.locationContextIsCurrent, routeIsRetained,
                  let navigation = navigationController, navigation.topViewController === self
            else { return }
            if customChat.id == location.chatID, let profile = makeProfile(customChat: customChat) {
                navigation.pushViewController(profile, animated: true)
            } else {
                let profile = PeerProfileViewController(
                    customChat: customChat,
                    topic: nil,
                    client: client,
                    accountID: accountID,
                )
                profile.configureOpensChatItself()
                navigation.pushViewController(profile, animated: true)
            }
            metadataNavigationTask = nil
        }
    }

    /// Telegram's displayDiceTooltip: the emoji's hint, with Send when this chat accepts dice.
    private func presentDiceTooltip(emoji: String) {
        let scalars = emoji.unicodeScalars.filter { $0.value != 0xFE0F }
        let key = "Conversation.Dice.u" + scalars.map { String(format: "%02X", $0.value) }.joined()
        let text = L10n.telegram(key)
        guard text != key else { return }
        let canSend = (try? chatVM.resolveSendContext(for: .sticker, replyingTo: nil)) != nil
        showChatToast(
            text,
            actionTitle: L10n.telegram("Conversation.SendDice"),
            action: canSend
                ? { [weak self] in
                    guard let self else { return }
                    Task { await self.chatVM.sendDice(emoji) }
                }
                : nil,
        )
    }

    /// A short notice above the composer, as Telegram's bot callback toast and copied-text overlay.
    private func showChatToast(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let bottomInset = showsComposer && composerView.frame.minY > 0
            ? max(0, view.bounds.maxY - view.safeAreaInsets.bottom - composerView.frame.minY) + 8
            : 8
        TelegramUndoToast.show(text: text, in: view, bottomInset: bottomInset, actionTitle: actionTitle, undo: action)
    }

    /// Telegram's switch inline button for this chat puts "@bot query" into the composer (`activateSwitchInline`).
    private func insertInlineQuery(_ query: String) {
        guard showsComposer, chatVM.locationContextIsCurrent, chatVM.editCustomMessage == nil,
              chatVM.canWriteBasicMessages else { return }
        chatVM.updateComposerTextFromUser(AttributedString(query))
        composerView.update(from: chatVM)
        composerView.focusInput()
    }

    private func galleryTransitionTarget(for messageID: Int64) -> MediaGalleryTransitionTarget? {
        guard let displayedMessageID = chatVM.displayedMessageID(containing: messageID),
              let indexPath = dataSource.indexPath(for: .message(displayedMessageID)),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
        else { return nil }
        return cell.galleryTransitionTarget(for: messageID)
    }

    private func inlineVideoPlaybackOwners(for message: CustomMessage) -> [Int64: GalleryVideoPlaybackOwner] {
        guard presentationMode == .full else { return [:] }
        let messages = message.album.isEmpty ? [message.message] : message.album
        return Dictionary(uniqueKeysWithValues: messages.compactMap { message in
            inlineVideoPlaybackOwner(for: message).map { (message.id, $0) }
        })
    }

    private func renderRowIsCurrent(_ row: ChatTimelineMessageRow) -> Bool {
        timelineSourceIsCurrent && row.source == navigationClientSource && row.location == location
            && row.client.id == chatVM.client.id && !timelineSnapshots.deleting.contains(row.value.displayedID)
            && message(for: row.value.displayedID) === row.canonical
            && row.value.message == row.canonical.message && row.value.sourceMessages == row.canonical.sourceMessages
    }

    private func currentBoundRenderRow(_ cell: MessageCell) -> ChatTimelineMessageRow? {
        guard let row = timelineSnapshots.boundRow(for: cell), renderRowIsCurrent(row) else { return nil }
        return row
    }

    private func inlineVideoPlaybackOwners(for row: ChatTimelineMessageRow) -> [Int64: GalleryVideoPlaybackOwner] {
        guard renderRowIsCurrent(row) else {
            return row.videoOwners.filter { id, owner in
                row.value.sourceMessages.contains { $0.id == id && owner.matches(message: $0) }
            }
        }
        row.videoOwners = inlineVideoPlaybackOwners(for: row.canonical)
        return row.videoOwners
    }

    private func inlineVideoPlaybackOwner(for message: Message) -> GalleryVideoPlaybackOwner? {
        // ChatMessageInteractiveMediaNode turns automatic playback off for an unsent message, so a sending video
        // shows its thumbnail under the upload disc until TDLib replaces it with the sent message.
        guard message.sendingState == nil else { return nil }
        if let owner = inlineVideoPlaybackOwners[message.id] {
            if owner.matches(message: message) { return owner }
            owner.invalidate()
            inlineVideoPlaybackOwners[message.id] = nil
        }
        let permit = mediaRevealSession?.permit(for: message)
        guard MediaRevealPermit.allows(message, permit: permit, requiresPermit: true),
              let source = GalleryPlayableMessage(message: message, revealPermit: permit), !source.isSecret,
              let galleryPlaybackContext, galleryPlaybackContext.isCurrent
        else { return nil }
        guard let owner = GalleryVideoPlaybackOwner(
            message: message,
            tdlib: tdlib,
            playbackContext: galleryPlaybackContext,
            revealPermit: permit,
            deferPlaybackUntilVisible: true,
        ) else { return nil }
        owner.onReturnToInline = { [weak self, weak owner] returnedOwner in
            guard let self,
                  let owner,
                  owner === returnedOwner,
                  inlineVideoPlaybackOwners[returnedOwner.messageID] === returnedOwner
            else { return false }
            pendingInlineVideoOwnerReturns.insert(returnedOwner.messageID)
            restoreReturnedInlineVideoOwnerIfVisible(returnedOwner)
            DispatchQueue.main.async { [weak self] in
                self?.restoreVisibleInlineVideoPlayback()
                self?.pruneInlineVideoPlaybackOwnerIfOffscreen(messageID: returnedOwner.messageID)
            }
            return true
        }
        owner.onPermanentDeletion = { [weak self] deletedOwner in
            guard let self,
                  inlineVideoPlaybackOwners[deletedOwner.messageID] === deletedOwner
            else { return }
            inlineVideoPlaybackOwners[deletedOwner.messageID] = nil
            pendingInlineVideoOwnerReturns.remove(deletedOwner.messageID)
        }
        inlineVideoPlaybackOwners[message.id] = owner
        return owner
    }

    private func restoreReturnedInlineVideoOwnerIfVisible(_ owner: GalleryVideoPlaybackOwner) {
        guard let displayedMessageID = chatVM.displayedMessageID(containing: owner.messageID),
              let indexPath = dataSource.indexPath(for: .message(displayedMessageID)),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCell,
              let row = currentBoundRenderRow(cell),
              row.value.sourceMessages.contains(where: { $0.id == owner.messageID && owner.matches(message: $0) }),
              cell.restoreInlineVideoPlaybackOwner(owner)
        else { return }
        pendingInlineVideoOwnerReturns.remove(owner.messageID)
    }

    private func pauseInlineVideoPlayback(excluding excludedMessageID: Int64?) {
        for (messageID, owner) in inlineVideoPlaybackOwners where messageID != excludedMessageID {
            owner.setPlaybackVisible(false)
        }
    }

    private func restoreVisibleInlineVideoPlayback() {
        guard presentedViewController == nil else { return }
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard case .message(let displayedMessageID) = dataSource.itemIdentifier(for: indexPath),
                  let cell = collectionView.cellForItem(at: indexPath) as? MessageCell,
                  let row = currentBoundRenderRow(cell), row.value.displayedID == displayedMessageID
            else { continue }
            for owner in inlineVideoPlaybackOwners(for: row).values
                where pendingInlineVideoOwnerReturns.contains(owner.messageID)
            {
                if cell.restoreInlineVideoPlaybackOwner(owner) {
                    pendingInlineVideoOwnerReturns.remove(owner.messageID)
                }
            }
            cell.setMediaPlaybackVisible(true, allowsInlineVideoPlayback: false)
        }
        updateInlineVideoPlaybackVisibility()
    }

    private func pruneInlineVideoPlaybackOwnerIfOffscreen(messageID: Int64) {
        guard let owner = inlineVideoPlaybackOwners[messageID],
              !owner.isAttachedToGallery,
              !visibleInlineVideoPlaybackOwnerIDs().contains(messageID)
        else { return }
        inlineVideoPlaybackOwners[messageID] = nil
        pendingInlineVideoOwnerReturns.remove(messageID)
        owner.onPermanentDeletion = nil
        owner.onReturnToInline = nil
        owner.invalidate()
    }

    private func pruneInlineVideoPlaybackOwners() {
        let visibleMessageIDs = visibleInlineVideoPlaybackOwnerIDs()
        for messageID in Array(inlineVideoPlaybackOwners.keys) where !visibleMessageIDs.contains(messageID) {
            pruneInlineVideoPlaybackOwnerIfOffscreen(messageID: messageID)
        }
    }

    private func visibleInlineVideoPlaybackOwnerIDs() -> Set<Int64> {
        Set(collectionView.indexPathsForVisibleItems.flatMap { indexPath in
            (collectionView.cellForItem(at: indexPath) as? MessageCell)?
                .inlineVideoPlaybackCandidates(in: collectionView)
                .map(\.0) ?? []
        })
    }

    private func updateInlineVideoPlaybackVisibility() {
        guard presentedViewController == nil, dataSource != nil else { return }
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let candidates = collectionView.indexPathsForVisibleItems
            .flatMap { indexPath in
                guard let cell = collectionView.cellForItem(at: indexPath) as? MessageCell,
                      let row = currentBoundRenderRow(cell) else { return [(Int64, CGRect)]() }
                return cell.inlineVideoPlaybackCandidates(in: collectionView).filter { id, _ in
                    inlineVideoPlaybackOwners[id].map { owner in
                        row.value.sourceMessages.contains { $0.id == id && owner.matches(message: $0) }
                    } == true
                }
            }
            .compactMap { messageID, frame -> InlineMediaPlaybackPolicy.Candidate? in
                guard let owner = inlineVideoPlaybackOwners[messageID] else { return nil }
                let intersection = visibleRect.intersection(frame)
                guard !intersection.isNull, !intersection.isEmpty else { return nil }
                return .init(
                    messageID: messageID, visibleArea: intersection.width * intersection.height,
                    isAnimation: owner.isAnimation,
                )
            }
        let activeMessageIDs = InlineMediaPlaybackPolicy.visibleMessageIDs(candidates)
        for (messageID, owner) in inlineVideoPlaybackOwners where !owner.isAttachedToGallery {
            owner.setPlaybackVisible(activeMessageIDs.contains(messageID))
        }
    }

    @objc private func scrollToLatest() {
        abandonRestoredViewport()
        scrollToLatestMessage(animated: true)
        loadLatestHistoryIfNeeded()
    }

    /// Telegram's scroll to the end of history reloads it at the upper bound when the loaded rows don't reach it,
    /// then scrolls there.
    private func loadLatestHistoryIfNeeded() {
        guard !clientOwnerRetired, chatVM.locationContextIsCurrent, presentationMode == .full else { return }
        #if DEBUG
            log("Scroll to latest: \(chatVM.historyDiagnosticSummary)")
        #endif
        latestHistoryTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { latestHistoryTask = nil } }
            guard let latest = await chatVM.prepareLatestMessageWindow(), !Task.isCancelled,
                  !clientOwnerRetired, chatVM.locationContextIsCurrent, !userIsScrollingTimeline,
                  pendingScrollMessageID == nil
            else { return }
            chatVM.applyMessageWindow(latest.window)
            #if DEBUG
                log("Scroll to latest: loaded the latest window; \(chatVM.historyDiagnosticSummary)")
            #endif
            updateSnapshot(animated: false)
            for _ in 0..<180 {
                if !timelineSnapshots.isBusy, timelineSnapshots.committedContains(
                    rawID: latest.messageID, displayedID: latest.window.displayedMessageID,
                ) { break }
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
            }
            guard !clientOwnerRetired, chatVM.locationContextIsCurrent, !userIsScrollingTimeline,
                  !hasPendingMessageNavigation else { return }
            pinToLatestEdge(animated: true)
        }
    }

    private func scrollToLatestMessage(animated: Bool) {
        cancelMessageNavigation()
        viewportRestorationAuthority.invalidate()
        guard dataSource.snapshot().numberOfItems > 0 else { return }
        pinToLatestEdge(animated: animated)
    }

    private func pinToLatestEdge(animated: Bool) {
        guard !hasPendingMessageNavigation else { return }
        collectionView.layoutIfNeeded()
        let target = -collectionView.adjustedContentInset.top
        recordMessageNavigationGeometry(
            "pin-latest-before", desiredOffset: target,
            animated: animated, writer: "pin-latest",
        )
        let distance = collectionView.contentOffset.y - target
        if animated, distance > 0.5 {
            beginLatestEdgeScroll()
            // A row that self-sizes above the viewport moves the offset, which ends an animated scroll where it is.
            // Lay out the destination first, as Telegram's list does before it animates to an item, then animate at
            // most one screen over rows that already have their sizes.
            collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            collectionView.layoutIfNeeded()
            let maximum = collectionView.contentSize.height - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
            collectionView.setContentOffset(
                CGPoint(x: 0, y: max(target, min(target + min(distance, collectionView.bounds.height), maximum))),
                animated: false,
            )
            collectionView.layoutIfNeeded()
        }
        collectionView.setContentOffset(
            CGPoint(x: 0, y: target),
            animated: animated,
        )
        recordMessageNavigationGeometry("pin-latest-after")
    }

    private func beginLatestEdgeScroll() {
        latestEdgeScrollInFlight = true
        latestEdgeScrollGeneration &+= 1
        let generation = latestEdgeScrollGeneration
        // A later non-animated offset write can end the animation without a callback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, latestEdgeScrollGeneration == generation else { return }
            latestEdgeScrollInFlight = false
        }
    }

    // MARK: Message search

    private func makeMessageSearch() -> ChatMessageSearch {
        let search = ChatMessageSearch(
            client: chatVM.client,
            location: chatVM.location,
            isSecretChat: chatVM.customChat.secretChatID != nil,
        ) { [weak self] in
            guard let self else { return false }
            return !clientOwnerRetired && chatVM.locationContextIsCurrent
        }
        search.onChange = { [weak self] in self?.updateMessageSearchPanel() }
        search.onNavigate = { [weak self] id in self?.scrollToMessage(id: id) }
        return search
    }

    private func updateMessageSearchPanel() {
        updateMessageSearchHighlights()
        let status: ChatSearchPanel.Status = messageSearchChoosesMember ? .idle : messageSearch.status
        let queryIsEmpty = messageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        messageSearchPanel.update(
            status: status,
            showsMembers: canSearchMessagesByMember && !messageSearchChoosesMember && messageSearchMember == nil
                && queryIsEmpty,
            showsDisplayMode: status.hasResults,
            isListMode: messageSearchShowsList,
            resultCount: messageSearch.totalResultCount,
        )
        updateMessageSearchResultsList()
        guard messageSearchActive else { return }
        customNavigationBar.setSearchResultFound(status == .noResults ? false : nil)
    }

    /// ChatTagSearchInputPanelNode's Show as List / Show as Chat.
    private func toggleMessageSearchListMode() {
        guard messageSearchActive, !messageSearchChoosesMember, chatVM.locationContextIsCurrent else { return }
        messageSearchShowsList.toggle()
        customNavigationBar.dismissSearchKeyboard()
        updateMessageSearchPanel()
    }

    /// The list stays in list mode across queries, as Telegram's does, and shows while there is a search to list.
    private func updateMessageSearchResultsList() {
        guard messageSearchActive, messageSearchShowsList, !messageSearchChoosesMember, messageSearch.isActive else {
            messageSearchResultsList?.removeFromSuperview()
            messageSearchResultsList = nil
            return
        }
        let list: ChatSearchResultsListView
        if let current = messageSearchResultsList {
            list = current
        } else {
            list = ChatSearchResultsListView(client: chatVM.client, accountID: chatVM.accountID) { [weak self] in
                guard let self else { return false }
                return !clientOwnerRetired && chatVM.locationContextIsCurrent
            }
            list.translatesAutoresizingMaskIntoConstraints = false
            list.onSelect = { [weak self] id in self?.selectMessageSearchListResult(id) }
            list.onNeedsMore = { [weak self] in self?.messageSearch.loadMore() }
            view.insertSubview(list, belowSubview: messageSearchPanel)
            NSLayoutConstraint.activate([
                list.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
                list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                list.bottomAnchor.constraint(equalTo: messageSearchPanel.topAnchor),
            ])
            messageSearchResultsList = list
        }
        let found = messageSearch.foundMessages
        list.update(messages: messageSearch.messageIDs.compactMap { found[$0] }, isLoading: messageSearch.isLoading)
    }

    /// ChatControllerNode's messageSelected: back to the chat at the picked result, which becomes the current one.
    private func selectMessageSearchListResult(_ messageID: Int64) {
        guard messageSearchActive, chatVM.locationContextIsCurrent else { return }
        messageSearchShowsList = false
        customNavigationBar.dismissSearchKeyboard()
        messageSearch.select(messageID: messageID)
        updateMessageSearchPanel()
    }

    private func setMessageSearchPanelVisible(_ visible: Bool) {
        guard messageSearchPanel.superview != nil else { return }
        if visible {
            updateMessageSearchPanel()
            messageSearchPanel.isHidden = false
        }
        UIView.animate(withDuration: 0.2) {
            self.messageSearchPanel.alpha = visible ? 1 : 0
        } completion: { _ in
            if !self.messageSearchActive { self.messageSearchPanel.isHidden = true }
        }
    }

    /// Telegram highlights the query in the text of found messages only (updateItemNodesSearchTextHighlightStates).
    private func messageSearchHighlightQuery(for message: CustomMessage) -> String? {
        guard messageSearchActive, !messageSearchChoosesMember, !messageSearch.query.isEmpty else { return nil }
        let results = messageSearch.resultIDs
        return message.sourceMessages.contains { results.contains($0.id) } ? messageSearch.query : nil
    }

    /// Visible rows follow the query and results at once; rows configured later read them in their configuration.
    private func updateMessageSearchHighlights() {
        for case let cell as MessageCell in collectionView.visibleCells {
            guard let displayedID = cell.timelineDisplayedID, let message = message(for: displayedID) else { continue }
            cell.setSearchHighlight(query: messageSearchHighlightQuery(for: message))
        }
    }

    private func messageSearchQueryChanged(_ query: String) {
        messageSearchQuery = query
        if messageSearchChoosesMember {
            messageSearchMemberList?.update(query: query)
        } else {
            messageSearch.update(query: query, sender: messageSearchMember?.sender)
        }
        updateMessageSearchPanel()
    }

    private func resetMessageSearch() {
        messageSearch.reset()
        messageSearchChoosesMember = false
        messageSearchMember = nil
        messageSearchQuery = ""
        messageSearchShowsList = false
        hideMessageSearchMemberList()
        updateMessageSearchPanel()
    }

    /// ChatPanelInterfaceInteraction.toggleMembersSearch(true): the field shows "from:" and lists the members.
    private func beginMessageSearchMemberChoice() {
        guard messageSearchActive, canSearchMessagesByMember, chatVM.locationContextIsCurrent else { return }
        messageSearchChoosesMember = true
        messageSearchMember = nil
        messageSearchQuery = ""
        messageSearch.reset()
        customNavigationBar.setSearchMemberScope(.choosing)
        customNavigationBar.focusSearchField()
        showMessageSearchMemberList()
        updateMessageSearchPanel()
    }

    private func selectMessageSearchMember(_ member: ChatSearchMemberListView.Member) {
        guard messageSearchActive, messageSearchChoosesMember else { return }
        messageSearchChoosesMember = false
        messageSearchMember = member
        messageSearchQuery = ""
        hideMessageSearchMemberList()
        customNavigationBar.setSearchMemberScope(.chosen(member.compactTitle))
        messageSearch.update(query: "", sender: member.sender)
        updateMessageSearchPanel()
    }

    /// Erasing the member's token returns to the member list and erasing "from:" to the whole chat, as Telegram's
    /// toggleMembersSearch(false) steps back one domain.
    private func messageSearchMemberScopeCleared(_ previous: TelegramChatNavigationBar.SearchMemberScope) {
        guard messageSearchActive else { return }
        if case .chosen = previous {
            beginMessageSearchMemberChoice()
            return
        }
        messageSearchChoosesMember = false
        messageSearchMember = nil
        messageSearchQuery = ""
        hideMessageSearchMemberList()
        customNavigationBar.setSearchMemberScope(.none)
        messageSearch.update(query: "", sender: nil)
        updateMessageSearchPanel()
    }

    private func showMessageSearchMemberList() {
        if messageSearchMemberList == nil {
            let list = ChatSearchMemberListView(
                client: chatVM.client, chatID: chatVM.location.chatID, accountID: chatVM.accountID,
            ) { [weak self] in
                guard let self else { return false }
                return !clientOwnerRetired && chatVM.locationContextIsCurrent
            }
            list.translatesAutoresizingMaskIntoConstraints = false
            list.onSelect = { [weak self] member in self?.selectMessageSearchMember(member) }
            view.insertSubview(list, belowSubview: messageSearchPanel)
            NSLayoutConstraint.activate([
                list.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
                list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                list.bottomAnchor.constraint(equalTo: messageSearchPanel.topAnchor),
            ])
            messageSearchMemberList = list
        }
        messageSearchMemberList?.update(query: "")
    }

    private func hideMessageSearchMemberList() {
        messageSearchMemberList?.cancel()
        messageSearchMemberList?.removeFromSuperview()
        messageSearchMemberList = nil
    }

    /// ChatControllerOpenCalendarSearch with isMedia false: pick a day, then the search closes and the chat jumps to
    /// the first message sent on that day or later.
    private func presentMessageSearchCalendar() {
        guard messageSearchActive, presentedViewController == nil, chatVM.locationContextIsCurrent else { return }
        customNavigationBar.dismissSearchKeyboard()
        let picker = ChatSearchDatePickerViewController { [weak self] date in self?.jumpToMessageSearchDate(date) }
        let navigation = UINavigationController(rootViewController: picker)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigation, animated: true)
    }

    private func jumpToMessageSearchDate(_ date: Date) {
        guard !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
        let start = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let client = chatVM.client
        let location = chatVM.location
        customNavigationBar.cancelSearch()
        messageDateJumpTask?.cancel()
        messageDateJumpTask = Task { [weak self] in
            let id = await ChatMessageSearch.firstMessageID(sentSince: start, in: location, client: client)
            guard let self, !Task.isCancelled else { return }
            messageDateJumpTask = nil
            guard let id, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
            scrollToMessage(id: id)
        }
    }

    // MARK: Stickers and GIFs

    private func observeFavoriteStickers() {
        guard presentationMode == .full else { return }
        nc.scopedPublisher(&cancellables, for: .updateFavoriteStickers) { [weak self] update in
            guard let self, update.source.matches(chatVM.location) else { return }
            favoriteStickerFileIDs = Set(update.value.stickerIds)
        }
        let client = chatVM.client
        Task { [weak self] in
            guard let favorites = try? await client.send(TDNativeRequests.getFavoriteStickers()) else { return }
            guard let self, chatVM.locationContextIsCurrent else { return }
            favoriteStickerFileIDs = Set(favorites.stickers.map(\.sticker.id))
        }
    }

    /// Telegram's StickerPackScreen from a sticker in the chat; its stickers send here when the chat takes them.
    private func presentStickerPack(setID: Int64) {
        guard presentationMode == .full, presentedViewController == nil, !clientOwnerRetired,
              chatVM.locationContextIsCurrent else { return }
        let canSend = showsComposer && chatVM.canSendStickersAndAnimations && chatVM.editCustomMessage == nil
        let send: ((Sticker) -> Void)? = canSend
            ? { [weak self] sticker in
                guard let self, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
                let chatVM = chatVM
                Task { await chatVM.sendSticker(sticker) }
            }
            : nil
        StickerPackPreviewViewController.present(setID: setID, client: chatVM.client, from: self, onSend: send)
    }

    /// InlineReactionSearchPanel's peek menu for a sticker suggested by the typed emoji: the send items, Add to or
    /// Remove from Favorites, and View Pack.
    private func suggestedStickerPeekActions(_ sticker: Sticker) -> [TelegramContextMenuAction] {
        guard presentationMode == .full, presentedViewController == nil, !clientOwnerRetired,
              chatVM.locationContextIsCurrent else { return [] }
        var actions = stickerPeekSendActions(sticker) { [weak self] sticker, options in
            self?.composerView.sendSuggestedSticker(sticker, options: options)
        }
        let fileID = sticker.sticker.id
        let isFavorite = favoriteStickerFileIDs.contains(fileID)
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram(isFavorite ? "Stickers.RemoveFromFavorites" : "Stickers.AddToFavorites"),
            image: UIImage(systemName: isFavorite ? "star.slash" : "star"),
        ) { [weak self] in self?.setStickerFavorite(fileID: fileID, favorite: !isFavorite) })
        if sticker.setId != 0 {
            let setID = sticker.setId
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("StickerPack.ViewPack"),
                image: UIImage(systemName: "square.grid.2x2"),
            ) { [weak self] in self?.presentStickerPack(setID: setID) })
        }
        return actions
    }

    /// The send items of Telegram's sticker peek menus (ChatEntityKeyboardInputNode, InlineReactionSearchPanel):
    /// Send Silently outside Saved Messages and secret chats, and Schedule Message where scheduling is allowed.
    private func stickerPeekSendActions(
        _ sticker: Sticker,
        send: @escaping (Sticker, TDNativeMessageSendOptions) -> Void,
    ) -> [TelegramContextMenuAction] {
        guard presentationMode == .full, !clientOwnerRetired, chatVM.locationContextIsCurrent,
              chatVM.canSendStickersAndAnimations, chatVM.editCustomMessage == nil else { return [] }
        var actions = [TelegramContextMenuAction]()
        let isSecret =
            if case .chatTypeSecret = chatVM.customChat.chat.type {
                true
            } else {
                false
            }
        if !chatVM.customChat.isSavedMessages, !isSecret {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.SendMessage.SendSilently"),
                image: UIImage(systemName: "bell.slash"),
            ) { send(sticker, ChatVM.sendOptions(silent: true)) })
        }
        if chatVM.canScheduleMessages {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.SendMessage.ScheduleMessage"),
                image: UIImage(systemName: "calendar.badge.clock"),
            ) { [weak self] in self?.presentStickerSchedulePicker(sticker, send: send) })
        }
        return actions
    }

    /// The peek menu's Schedule Message: `sendSticker` with `schedule` opens the date picker, and the sticker goes out
    /// at the picked time.
    private func presentStickerSchedulePicker(
        _ sticker: Sticker,
        send: @escaping (Sticker, TDNativeMessageSendOptions) -> Void,
    ) {
        guard presentationMode == .full, chatVM.locationContextIsCurrent, chatVM.canScheduleMessages else { return }
        ScheduleMessagePickerViewController.present(
            from: self,
            isReminder: chatVM.customChat.isSavedMessages,
            showsSendWhenOnline: chatVM.canSendWhenOnline,
        ) { [weak self] state in
            guard let self, chatVM.locationContextIsCurrent else { return }
            send(sticker, ChatVM.sendOptions(schedulingState: state))
        }
    }

    /// Telegram's sticker and GIF message items (ChatInterfaceStateContextMenus): Add to or Remove from Favorites and
    /// View Sticker Set for a sticker, Save GIF for a GIF the chat lets save.
    private func stickerAndAnimationActions(for message: CustomMessage) -> [TelegramContextMenuAction] {
        switch message.message.content {
        case .messageSticker(let content):
            var actions = [TelegramContextMenuAction]()
            let sticker = content.sticker
            let isPremium =
                if case .stickerFullTypeRegular(let regular) = sticker.fullType {
                    regular.premiumAnimation != nil
                } else {
                    false
                }
            if !isPremium {
                let fileID = sticker.sticker.id
                let isFavorite = favoriteStickerFileIDs.contains(fileID)
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram(isFavorite ? "Stickers.RemoveFromFavorites" : "Stickers.AddToFavorites"),
                    image: UIImage(systemName: isFavorite ? "star.slash" : "star"),
                ) { [weak self] in self?.setStickerFavorite(fileID: fileID, favorite: !isFavorite) })
            }
            if sticker.setId != 0 {
                let setID = sticker.setId
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("StickerPack.ViewPack"),
                    image: UIImage(systemName: "square.grid.2x2"),
                ) { [weak self] in self?.presentStickerPack(setID: setID) })
            }
            return actions
        case .messageAnimation(let content):
            if case .chatTypeSecret = chatVM.customChat.chat.type { return [] }
            guard message.properties.canBeSaved, message.message.selfDestructType == nil else { return [] }
            let fileID = content.animation.animation.id
            return [TelegramContextMenuAction(
                title: L10n.telegram("Conversation.SaveGif"),
                image: UIImage(systemName: "square.and.arrow.down"),
            ) { [weak self] in self?.saveAnimation(fileID: fileID) }]
        default:
            return []
        }
    }

    private func setStickerFavorite(fileID: Int, favorite: Bool) {
        guard stickerActionTask == nil, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
        let client = chatVM.client
        stickerActionTask = Task { [weak self] in
            let input = InputFile.inputFileId(InputFileId(id: fileID))
            let request = favorite
                ? TDNativeRequests.addFavoriteSticker(sticker: input)
                : TDNativeRequests.removeFavoriteSticker(sticker: input)
            let succeeded = await (try? client.send(request)) != nil
            guard let self else { return }
            stickerActionTask = nil
            guard succeeded, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
            if favorite {
                favoriteStickerFileIDs.insert(fileID)
            } else {
                favoriteStickerFileIDs.remove(fileID)
            }
            showChatToast(L10n.telegram(
                favorite ? "Conversation.StickerAddedToFavorites" : "Conversation.StickerRemovedFromFavorites",
            ))
        }
    }

    /// Telegram's Save GIF (toggleGifSaved) with its "GIF Saved" toast.
    private func saveAnimation(fileID: Int) {
        guard stickerActionTask == nil, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
        let client = chatVM.client
        stickerActionTask = Task { [weak self] in
            let succeeded = await (try? client.send(TDNativeRequests.addSavedAnimation(
                animation: .inputFileId(InputFileId(id: fileID)),
            ))) != nil
            guard let self else { return }
            stickerActionTask = nil
            guard succeeded, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
            showChatToast(L10n.telegram("Gallery.GifSaved"))
        }
    }

    /// Telegram's Translate message item (canTranslateText): with Show Translate Button on, for text in a language the
    /// user doesn't read. Secret chats never offer it; a protected chat's translation can't be copied.
    private func translateAction(for message: CustomMessage) -> TelegramContextMenuAction? {
        if case .chatTypeSecret = chatVM.customChat.chat.type { return nil }
        guard MessageTranslation.showsTranslateButton else { return nil }
        var foundText = copyableText(from: message.message.content)
        for source in message.sourceMessages where foundText == nil {
            foundText = copyableText(from: source.content)
        }
        guard let messageText = foundText,
              let language = MessageTranslation.translatableLanguage(of: messageText.text)
        else {
            return nil
        }
        let canCopy = message.properties.canBeCopied
        return TelegramContextMenuAction(
            title: L10n.telegram("Conversation.ContextMenuTranslate"),
            image: UIImage(systemName: "translate"),
        ) { [weak self] in
            self?.presentTranslation(of: messageText, sourceLanguage: language, canCopy: canCopy)
        }
    }

    /// TextSelectionNode's Translate for the selected part of a message, where the chat offers Telegram's
    /// translation.
    private func selectionTranslateAction(canCopy: Bool) -> ((String) -> Void)? {
        if case .chatTypeSecret = chatVM.customChat.chat.type { return nil }
        guard MessageTranslation.showsTranslateButton else { return nil }
        return { [weak self] selected in
            self?.presentTranslation(
                of: FormattedText(entities: [], text: selected),
                sourceLanguage: MessageTranslation.detectedLanguage(of: selected),
                canCopy: canCopy,
            )
        }
    }

    private func presentTranslation(of messageText: FormattedText, sourceLanguage: String?, canCopy: Bool) {
        MessageTranslationViewController.present(
            text: messageText,
            sourceLanguage: sourceLanguage,
            canCopy: canCopy,
            from: self,
        ) { [weak self] in self?.showChatToast(L10n.telegram("Conversation.TextCopied")) }
    }

    /// Telegram's Save Image / Save Video (saveToCameraRoll) and Save to Files (saveMediaToFiles) message items for a
    /// media message the chat lets save, following the gallery's export rules. In an album they save the item that
    /// was pressed, as Telegram's per-item album menus do.
    private func mediaSaveActions(
        for message: CustomMessage,
        albumItemID: Int64? = nil,
    ) -> [TelegramContextMenuAction] {
        if case .chatTypeSecret = chatVM.customChat.chat.type { return [] }
        let source: Message
        if message.sourceMessages.count <= 1 {
            source = message.message
        } else if let albumItemID, let item = message.sourceMessages.first(where: { $0.id == albumItemID }) {
            source = item
        } else {
            return []
        }
        guard message.properties.canBeSaved,
              !message.properties.hasProtectedContentByCurrentUser,
              !message.properties.hasProtectedContentByOtherUser,
              source.selfDestructType == nil
        else { return [] }
        let messageID = source.id
        switch source.content {
        case .messagePhoto, .messageVideo:
            guard let asset = MediaGalleryExportAsset(source), !asset.isSecretMedia,
                  let saveTitle = asset.saveActionTitle else { return [] }
            return [TelegramContextMenuAction(
                title: saveTitle,
                image: UIImage(systemName: "square.and.arrow.down"),
            ) { [weak self] in self?.saveMessageMediaToPhotos(messageID: messageID) }]
        case .messageAudio, .messageDocument:
            return [TelegramContextMenuAction(
                title: L10n.telegram("Conversation.SaveToFiles"),
                image: UIImage(systemName: "folder"),
            ) { [weak self] in self?.saveMessageMediaToFiles(messageID: messageID) }]
        default:
            return []
        }
    }

    /// Saves a photo, live photo or video message to Photos with the gallery's pipeline and Telegram's
    /// "Image Saved" / "Video Saved" toast.
    private func saveMessageMediaToPhotos(messageID: Int64) {
        guard mediaSaveTask == nil, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
        let client = chatVM.client
        let chatID = location.chatID
        mediaSaveTask = Task { [weak self] in
            var savedText: String?
            var failure: Swift.Error?
            do {
                let resolved = try await Self.savableMessage(chatID: chatID, messageID: messageID, client: client)
                guard let asset = MediaGalleryExportAsset(resolved), !asset.isSecretMedia, asset.photosKind != nil
                else { throw MediaGallerySaveError.messageUnavailable }
                let localURL = try await MediaGalleryExport.resolvedURL(for: asset, client: client)
                try await MediaGalleryExport.requestPhotosAccess()
                let liveResources = try await MediaGalleryExport.livePhotoResources(
                    asset: asset,
                    photoURL: localURL,
                    client: client,
                )
                defer { liveResources?.cleanup() }
                var filename = ""
                if liveResources == nil {
                    filename = try await MediaGalleryExport.photosFilename(for: asset, localURL: localURL)
                }
                let latest = try await Self.savableMessage(chatID: chatID, messageID: messageID, client: client)
                guard MediaGalleryExportAsset(latest)?.fileID == asset.fileID else {
                    throw MediaGallerySaveError.messageUnavailable
                }
                if let liveResources {
                    try await liveResources.save(creationDate: asset.creationDate)
                } else {
                    try await MediaGalleryExport.saveToPhotos(asset: asset, localURL: localURL, filename: filename)
                }
                savedText = asset.saveSuccessText
            } catch is CancellationError {
            } catch {
                failure = error
            }
            guard let self else { return }
            mediaSaveTask = nil
            guard !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
            if let failure {
                presentMediaSaveFailure(failure)
            } else if let savedText {
                showChatToast(savedText)
            }
        }
    }

    /// Telegram's Save to Files (saveMediaToFiles): downloads the file and hands a copy named after the message's
    /// file to the system export picker.
    private func saveMessageMediaToFiles(messageID: Int64) {
        guard mediaSaveTask == nil, !clientOwnerRetired, chatVM.locationContextIsCurrent else { return }
        let client = chatVM.client
        let chatID = location.chatID
        mediaSaveTask = Task { [weak self] in
            var export: (directory: URL, file: URL)?
            var failure: Swift.Error?
            do {
                let resolved = try await Self.savableMessage(chatID: chatID, messageID: messageID, client: client)
                guard let source = Self.exportableFile(of: resolved) else {
                    throw MediaGallerySaveError.messageUnavailable
                }
                let downloaded = try await client.downloadFile(
                    fileId: source.file.id,
                    limit: 0,
                    offset: 0,
                    priority: 16,
                    synchronous: true,
                )
                try Task.checkCancellation()
                guard downloaded.id == source.file.id,
                      downloaded.local.isDownloadingCompleted,
                      !downloaded.local.path.isEmpty,
                      FileManager.default.fileExists(atPath: downloaded.local.path)
                else { throw MediaGallerySaveError.downloadFailed }
                let latest = try await Self.savableMessage(chatID: chatID, messageID: messageID, client: client)
                guard Self.exportableFile(of: latest)?.file.id == source.file.id else {
                    throw MediaGallerySaveError.messageUnavailable
                }
                export = try await Self.temporaryExportCopy(
                    of: URL(filePath: downloaded.local.path),
                    filename: source.filename,
                )
            } catch is CancellationError {
            } catch {
                failure = error
            }
            guard let self else {
                if let export { try? FileManager.default.removeItem(at: export.directory) }
                return
            }
            mediaSaveTask = nil
            guard !clientOwnerRetired, chatVM.locationContextIsCurrent, presentedViewController == nil else {
                if let export { try? FileManager.default.removeItem(at: export.directory) }
                return
            }
            if let export {
                let picker = UIDocumentPickerViewController(forExporting: [export.file], asCopy: true)
                let delegate = MessageFileExportDelegate(directoryURL: export.directory)
                fileExportDelegate = delegate
                picker.delegate = delegate
                present(picker, animated: true)
            } else if let failure {
                presentMediaSaveFailure(failure)
            }
        }
    }

    private func presentMediaSaveFailure(_ error: Swift.Error) {
        guard presentedViewController == nil else { return }
        let shownError = error is MediaGallerySaveError ? error : MediaGallerySaveError.downloadFailed
        present(
            MediaGalleryExport.failureAlert(for: shownError, title: L10n.betterTG("Gallery.SaveFailedTitle")),
            animated: true,
        )
    }

    /// Telegram's attach button: the attachment sheet with Gallery current and the chat's other attachments in its
    /// panel, in ChatControllerOpenAttachmentMenu's order and under its rules. View Once is offered in a private chat
    /// with someone other than the user (`hasTimer`), and Saved Messages sets reminders.
    private func showAttachmentSheet() {
        guard presentationMode == .full, chatVM.editCustomMessage == nil else { return }
        var tabs: [AttachmentSheetTab] = [.gallery]
        if chatVM.canAttachDocuments { tabs.append(.file) }
        let canSendLocationAndContact = chatVM.canSendLocationAndContact
        if canSendLocationAndContact { tabs.append(.location) }
        if chatVM.canCreatePoll { tabs.append(.poll) }
        if chatVM.canCreateChecklist { tabs.append(.checklist) }
        if canSendLocationAndContact { tabs.append(.contact) }
        if chatVM.canWriteBasicMessages || chatVM.canSendStickersAndAnimations { tabs.append(.sticker) }
        tabs.insert(contentsOf: attachmentMenuBotTabs(), at: 1)
        let customChat = chatVM.customChat
        var allowsViewOnce = false
        if case .chatTypePrivate = customChat.chat.type, !customChat.isSavedMessages {
            allowsViewOnce = true
        }
        let configuration = AttachmentSheetConfiguration(
            allowsPhotos: chatVM.canAttachPhotos,
            allowsVideos: chatVM.canAttachVideos,
            allowsCamera: chatVM.canAttachPhotos,
            tabs: tabs,
            allowsSendAsFile: chatVM.canAttachDocuments,
            allowsSpoiler: chatVM.canHideMediaWithSpoiler,
            showsLivePhotos: chatVM.canSendLivePhotos,
            allowsViewOnce: allowsViewOnce,
            allowsVideoCover: chatVM.allowsVideoCover,
            isReminders: customChat.isSavedMessages,
            canSchedule: chatVM.canScheduleMessages,
            canSendWhenOnline: chatVM.canSendWhenOnline,
            caption: String(chatVM.text.characters).trimmingCharacters(in: .whitespacesAndNewlines),
            captionIsAbove: chatVM.mediaCaptionIsAbove,
        )
        let sheet = AttachmentSheetViewController(configuration: configuration)
        // LegacyAttachmentMenu resets the video quality to the server's upload default as the menu opens.
        if chatVM.canAttachVideos {
            let client = chatVM.client
            Task { [weak sheet] in
                let preset = await VideoSendPreset.uploadDefault(client: client)
                sheet?.setDefaultVideoPreset(preset)
            }
        }
        sheet.onSelectTab = { [weak self] tab in self?.openAttachmentTab(tab) }
        sheet.onCamera = { [weak self] in self?.showCamera() }
        sheet.onSend = { [weak self] request in self?.sendAttachmentMedia(request) }
        sheet.onDismiss = { [weak self] in self?.attachmentSheetDidDismiss() }
        present(sheet.makeNavigationController(), animated: true)
    }

    /// The attachment panel's other buttons, opened once the sheet has closed.
    private func openAttachmentTab(_ tab: AttachmentSheetTab) {
        switch tab {
        case .gallery, .link: break
        case .file: showDocumentPicker()
        case .location: showLocationPicker()
        case .poll: showPollCreator()
        case .checklist: showChecklistComposer()
        case .contact: showContactPicker()
        case .sticker:
            if !composerView.showMediaInput(mode: .stickers) { showComposerMediaPicker(mode: .stickers) }
        case .app(let bot): openAttachmentMenuBot(bot)
        }
    }

    /// ChatControllerOpenAttachmentMenu's `.app` buttons: the account's attachment menu bots whose peer types meet
    /// this chat's (`sameBot` in the bot's own chat), in the list's order. A secret chat has none.
    private func attachmentMenuBotTabs() -> [AttachmentSheetTab] {
        guard chatVM.canWriteBasicMessages, let accountID = chatVM.accountID,
              let supports = attachmentMenuBotSupport() else { return [] }
        let source = TdUpdateSource(accountID: accountID, clientID: chatVM.client.id)
        return AttachmentMenuBotStore.shared
            .entries(for: source)
            .filter { $0.bot.showInAttachmentMenu && supports($0.bot) }
            .map { entry in
                AttachmentSheetTab.app(AttachmentMenuBotButton(
                    botUserID: entry.bot.botUserId,
                    name: entry.bot.name,
                    animatedIconPath: entry.animatedIconPath,
                    imageIconPath: entry.imageIconPath,
                ))
            }
    }

    /// Whether an attachment menu bot's peer types meet this chat's; nil in a secret chat, which has no bots.
    private func attachmentMenuBotSupport() -> ((TDNativeAttachmentMenuBot) -> Bool)? {
        let customChat = chatVM.customChat
        switch customChat.chat.type {
        case .chatTypePrivate(let type):
            if customChat.bot != nil {
                return { $0.botUserId == type.userId ? $0.supportsSelfChat : $0.supportsBotChats }
            } else {
                return { $0.supportsUserChats }
            }
        case .chatTypeBasicGroup:
            return { $0.supportsGroupChats }
        case .chatTypeSupergroup(let type):
            if type.isChannel {
                return { $0.supportsChannelChats }
            } else {
                return { $0.supportsGroupChats }
            }
        case .chatTypeSecret:
            return nil
        }
    }

    /// ChatController's presentAttachmentBot (`presentAttachmentMenu(subject: .bot)`): a bot that serves this chat
    /// opens its Web App here with the link's start parameter, the composer's topic and reply, and Telegram's
    /// shortcut notice when it was just added; otherwise the notice that it's added (or was just) shows instead.
    private func applyPendingAttachmentMenuBotStart() {
        guard let start = pendingAttachmentMenuBotStart else { return }
        pendingAttachmentMenuBotStart = nil
        guard presentationMode == .full, chatVM.locationContextIsCurrent, let accountID = chatVM.accountID else {
            return
        }
        let bot = start.bot
        let addedNotice = L10n.telegram(
            bot.showInSideMenu ? "WebApp.ShortcutsSettingsAdded" : "WebApp.ShortcutsAdded",
            bot.name,
        )
        .replacingOccurrences(of: "**", with: "")
        guard chatVM.canWriteBasicMessages, let supports = attachmentMenuBotSupport(), supports(bot) else {
            showChatToast(start.justInstalled ? addedNotice : L10n.telegram("WebApp.AddToAttachmentAlreadyAddedError"))
            return
        }
        let context = try? chatVM.resolveSendContext(
            for: .text,
            replyingTo: chatVM.replyMessage,
            useCurrentReplyOverride: true,
        )
        attachmentWebAppLauncher(accountID: accountID).openAttachmentMenuBot(
            botUserID: bot.botUserId,
            name: bot.name,
            isAdded: true,
            chatID: chatVM.chatID,
            topic: context?.destinationTopic,
            replyTo: context?.replyTo,
            url: start.url,
            notice: start.justInstalled ? addedNotice : nil,
        )
    }

    /// ChatControllerOpenAttachmentMenu's `.app` button: the bot's Web App for this chat with the composer's topic
    /// and reply (`replyToMessageId`, `threadId`), after webAppTermsAlertController when the bot isn't added.
    private func openAttachmentMenuBot(_ button: AttachmentMenuBotButton) {
        guard chatVM.locationContextIsCurrent, let accountID = chatVM.accountID,
              let entry = AttachmentMenuBotStore.shared.entry(
                  botUserID: button.botUserID,
                  source: TdUpdateSource(accountID: accountID, clientID: chatVM.client.id),
              ),
              let context = try? chatVM.resolveSendContext(
                  for: .text,
                  replyingTo: chatVM.replyMessage,
                  useCurrentReplyOverride: true,
              )
        else { return }
        attachmentWebAppLauncher(accountID: accountID).openAttachmentMenuBot(
            botUserID: entry.bot.botUserId,
            name: entry.bot.name,
            isAdded: entry.bot.isAdded,
            chatID: chatVM.chatID,
            topic: context.destinationTopic,
            replyTo: context.replyTo,
        )
    }

    private func attachmentWebAppLauncher(accountID: UUID) -> WebAppLauncher {
        if let webAppLauncher { return webAppLauncher }
        let launcher = WebAppLauncher(host: .init(
            accountID: accountID,
            client: chatVM.client,
            presenter: { [weak self] in self },
            isCurrent: { [weak self] in
                guard let self else { return false }
                return routeIsRetained && chatVM.locationContextIsCurrent
            },
            actions: .init(
                openTelegramLink: { [weak self] url in TelegramLinkRouter.shared.open(url, from: self) },
                switchInline: { [weak self] text, types in
                    // The chat picker forwards from a message, which a menu launch doesn't have.
                    if types == nil { self?.insertInlineQuery(text) }
                },
                messageSent: { [weak self] in self?.attachmentWebAppSentMessage() },
            ),
        ))
        webAppLauncher = launcher
        return launcher
    }

    /// WebAppController's `completion` for an attachment menu launch: the sent message drops the reply and the chat
    /// scrolls to its end.
    private func attachmentWebAppSentMessage() {
        guard chatVM.locationContextIsCurrent else { return }
        chatVM.cancelReply()
        scrollToLatestMessage(animated: true)
    }

    /// ChatTextInputPanelNode's `menuButtonPressed` for a `.webView` menu: ChatControllerOpenWebApp's
    /// `openWebApp(buttonText:url:simple: false, source: .menu)` dismisses the input, hides the command list
    /// (`updatedForceInputCommandsHidden`) and opens the button's Web App for this chat and topic.
    private func openBotMenuWebApp(_ button: TDNativeBotMenuButton) {
        guard chatVM.locationContextIsCurrent, let accountID = chatVM.accountID else { return }
        view.endEditing(true)
        chatVM.showsBotCommandMenu = false
        let launcher = botMenuWebAppLauncher(accountID: accountID)
        #if DEBUG
            if WebAppLauncher.probeHTML != nil {
                return launcher.openProbeMenuWebApp(name: chatVM.customChat.displayTitle)
            }
        #endif
        guard case .bot(let bot) = chatVM.customChat.type else { return }
        let topic = (try? chatVM.resolveSendContext(for: .text, replyingTo: nil))?.destinationTopic
        launcher.openMenuWebApp(bot: bot, chatID: chatVM.chatID, url: button.url, topic: topic)
    }

    /// The menu's Web App sends no reply; its `completion` scrolls the chat to its end.
    private func botMenuWebAppLauncher(accountID: UUID) -> WebAppLauncher {
        if let menuWebAppLauncher { return menuWebAppLauncher }
        let launcher = WebAppLauncher(host: .init(
            accountID: accountID,
            client: chatVM.client,
            presenter: { [weak self] in self },
            isCurrent: { [weak self] in
                guard let self else { return false }
                return routeIsRetained && chatVM.locationContextIsCurrent
            },
            actions: .init(
                openTelegramLink: { [weak self] url in TelegramLinkRouter.shared.open(url, from: self) },
                switchInline: { [weak self] text, types in
                    if types == nil { self?.insertInlineQuery(text) }
                },
                messageSent: { [weak self] in
                    guard let self, chatVM.locationContextIsCurrent else { return }
                    scrollToLatestMessage(animated: true)
                },
            ),
        ))
        menuWebAppLauncher = launcher
        return launcher
    }

    /// The sheet's picked items become the composer's media and go out with the sheet's send choice, so they take the
    /// composer's text as the caption, its reply, and its albums of ten.
    private func sendAttachmentMedia(_ request: AttachmentMediaSendRequest) {
        guard let token = importBarrier.begin() else { return }
        let barrier = importBarrier
        PhotoAssetSelectionLoader.load(
            request.assets,
            cropAdjustments: request.cropAdjustments,
            videoEdits: request.videoEdits,
            livePhotoAssetIDs: request.livePhotoAssetIDs,
            highQualityPhotos: request.highQualityPhotos,
            spoilerAssetIDs: request.spoilerAssetIDs,
            selfDestructTimer: request.selfDestructTimer,
            videoPreset: request.videoPreset,
        ) { [self] images in
            // Telegram's sheet sends at once; a scheduled send waits in the composer for its time.
            let sendsAtOnce = request.timing != .schedule
            composerView.hidesSheetMedia = sendsAtOnce
            guard finishImageImport(images, token: token, barrier: barrier), !images.isEmpty,
                  chatVM.locationContextIsCurrent
            else {
                revealSheetMedia()
                return
            }
            chatVM.mediaCaptionIsAbove = request.captionIsAbove
            switch request.timing {
            case .now:
                composerView.send(options: nil, mediaMode: request.mode)
            case .silently:
                composerView.send(options: ChatVM.sendOptions(silent: true), mediaMode: request.mode)
            case .whenOnline:
                composerView.send(
                    options: ChatVM.sendOptions(schedulingState: .messageSchedulingStateSendWhenOnline),
                    mediaMode: request.mode,
                )
            case .schedule:
                presentScheduleMessagePicker(mediaMode: request.mode)
            }
            guard sendsAtOnce else { return }
            let send = chatVM.sendMessageTask
            Task { [weak self] in
                await send?.value
                self?.revealSheetMedia()
            }
        }
    }

    /// What the sheet's send left in the composer, after a failure, shows again.
    private func revealSheetMedia() {
        guard composerView.hidesSheetMedia else { return }
        composerView.hidesSheetMedia = false
        if !composerAwaitsSentMediaInsertion { composerView.update(from: chatVM) }
    }

    private func showDocumentPicker() {
        guard chatVM.canAttachDocuments else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.presentationController?.delegate = self
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    /// Telegram's attachment menu Location: the location picker in a sheet. What it sends replies to the composer's
    /// reply as other attachments do; TDLib takes locations and venues under `canSendBasicMessages`.
    private func showLocationPicker() {
        guard chatVM.canSendLocationAndContact else { return }
        let picker = LocationPickerViewController(
            peerName: chatVM.liveLocationPeerName,
            allowsLiveLocation: chatVM.canShareLiveLocation,
            client: chatVM.client,
            chatID: chatVM.chatID,
        ) { [weak chatVM] content in
            Task { await chatVM?.sendAttachmentContents([content], kind: .text) }
        }
        picker.onDismiss = { [weak self] in self?.attachmentSheetDidDismiss() }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.presentationController?.delegate = self
        present(navigation, animated: true)
    }

    /// Telegram's attachment menu Contact: ContactSelectionController with the account's contacts that show a number
    /// and the phonebook, several at once. What it sends replies to the composer's reply as other attachments do.
    private func showContactPicker() {
        guard chatVM.canSendLocationAndContact else { return }
        let picker = ContactSelectionViewController(
            client: chatVM.client,
            accountID: chatVM.accountID,
        ) { [weak chatVM] contents in
            Task { await chatVM?.sendAttachmentContents(contents, kind: .text) }
        }
        picker.onDismiss = { [weak self] in self?.attachmentSheetDidDismiss() }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.presentationController?.delegate = self
        present(navigation, animated: true)
    }

    /// Telegram's attachment menu Poll: the poll creator, with a channel's defaults in channels.
    private func showPollCreator() {
        guard chatVM.canCreatePoll else { return }
        let poll = CreatePollViewController(
            isChannel: chatVM.createsChannelPoll,
            client: chatVM.client,
            accountID: chatVM.accountID,
            chatID: chatVM.chatID,
        ) { [weak chatVM] content in
            Task { await chatVM?.sendAttachmentContents([content], kind: .poll) }
        }
        poll.onDismiss = { [weak self] in self?.attachmentSheetDidDismiss() }
        present(poll.makeNavigationController(), animated: true)
    }

    /// The same upkeep as a swiped-away sheet once an attachment screen closes itself.
    private func attachmentSheetDidDismiss() {
        retryClientRestoration()
        acknowledgeCommittedVisibleMessages(requestHistory: true)
    }

    /// The emoji, sticker and GIF picker as a sheet. From the media panel's search field it is Telegram's expanded
    /// search: full height with the field focused, and closing it brings the panel back (`.media(expanded: nil)`).
    private func showComposerMediaPicker(
        mode: ComposerMediaPickerViewController.Mode = .emoji,
        expandedSearch: Bool = false,
    ) {
        guard chatVM.canWriteBasicMessages || chatVM.canSendStickersAndAnimations,
              let accountID = chatVM.accountID
        else { return }
        let picker = ComposerMediaPickerViewController(
            accountID: accountID,
            chatID: chatVM.chatID,
            client: chatVM.client,
        )
        picker.allowsStickersAndGIFs = chatVM.editCustomMessage == nil && chatVM.canSendStickersAndAnimations
        picker.initialMode = mode
        picker.focusesSearchOnAppear = expandedSearch
        if expandedSearch {
            picker.onDidDismiss = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, presentedViewController == nil, chatVM.locationContextIsCurrent else { return }
                    composerView.showMediaInput(mode: mode)
                }
            }
        }
        picker.onEmoji = { [weak self] emoji in
            self?.composerView.insertEmoji(emoji)
        }
        picker.onCustomEmoji = { [weak self] sticker in
            guard case .stickerFullTypeCustomEmoji(let type) = sticker.fullType else { return }
            self?.composerView.insertEmoji(sticker.emoji, customID: type.customEmojiId)
        }
        picker.onDismiss = { [weak self] in self?.retryClientRestoration() }
        picker.onSticker = { [weak self, weak picker, weak chatVM] sticker in
            picker?.navigationController?.dismiss(animated: true) {
                self?.retryClientRestoration()
                Task { await chatVM?.sendSticker(sticker) }
            }
        }
        picker.stickerSendActions = { [weak self, weak picker] sticker in
            self?.stickerPeekSendActions(sticker) { [weak self, weak picker] sticker, options in
                let chatVM = self?.chatVM
                picker?.navigationController?.dismiss(animated: true) {
                    self?.retryClientRestoration()
                    Task { await chatVM?.sendSticker(sticker, options: options) }
                }
            } ?? []
        }
        picker.onAnimation = { [weak self, weak picker, weak chatVM] animation in
            picker?.navigationController?.dismiss(animated: true) {
                self?.retryClientRestoration()
                Task { await chatVM?.sendAnimation(animation) }
            }
        }
        picker.onInlineAnimation = { [weak self, weak picker, weak chatVM] queryID, resultID in
            picker?.navigationController?.dismiss(animated: true) {
                self?.retryClientRestoration()
                Task { await chatVM?.sendInlineAnimation(queryID: queryID, resultID: resultID) }
            }
        }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = expandedSearch ? [.large()] : [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = false
        navigation.presentationController?.delegate = self
        present(navigation, animated: true)
    }

    private func showCamera() {
        guard chatVM.canAttachPhotos else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            let alert = UIAlertController(
                title: L10n.betterTG("Chat.CameraUnavailable"),
                message: nil,
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            present(alert, animated: true)
            return
        }
        let picker = UIImagePickerController()
        picker.presentationController?.delegate = self
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentMicrophoneErrorIfNeeded() {
        guard chatVM.errorShown, !didPresentMicrophoneError else { return }
        didPresentMicrophoneError = true
        chatVM.errorShown = false
        let alert = UIAlertController(
            title: L10n.betterTG("Permissions.MicrophoneTitle"),
            message: L10n.betterTG("Permissions.MicrophoneMessage"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
            self?.didPresentMicrophoneError = false
        })
        alert
            .addAction(UIAlertAction(
                title: L10n.telegram("Notifications.PermissionsOpenSettings"),
                style: .default,
            ) { [weak self] _ in
                self?.didPresentMicrophoneError = false
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
        present(alert, animated: true)
    }

    private func presentVoiceNoteErrorIfNeeded() {
        guard let message = chatVM.voiceNoteErrorMessage, !didPresentVoiceNoteError else { return }
        didPresentVoiceNoteError = true
        chatVM.voiceNoteErrorMessage = nil
        let alert = UIAlertController(title: L10n.telegram("Message.Audio"), message: message, preferredStyle: .alert)
        if chatVM.hasPendingVoiceNote {
            alert.addAction(UIAlertAction(
                title: L10n.telegram("Conversation.DiscardVoiceMessageAction"),
                style: .destructive,
            ) { [weak self] _ in
                self?.didPresentVoiceNoteError = false
                self?.chatVM.discardPendingVoiceNote()
            })
            alert.addAction(UIAlertAction(title: L10n.betterTG("Chat.KeepDraft"), style: .cancel) { [weak self] _ in
                self?.didPresentVoiceNoteError = false
            })
            if chatVM.canRetryPendingVoiceNote {
                alert
                    .addAction(UIAlertAction(
                        title: L10n.telegram("ChatImportActivity.Retry"),
                        style: .default,
                    ) { [weak self] _ in
                        self?.didPresentVoiceNoteError = false
                        self?.chatVM.retryPendingVoiceNote()
                    })
            }
        } else {
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
                self?.didPresentVoiceNoteError = false
            })
        }
        present(alert, animated: true)
    }

    private func presentVideoNoteSendErrorIfNeeded() {
        guard let message = chatVM.videoNoteErrorMessage,
              !didPresentVideoNoteError,
              presentedViewController == nil
        else { return }
        didPresentVideoNoteError = true
        chatVM.videoNoteErrorMessage = nil
        let alert = UIAlertController(
            title: L10n.telegram("Message.VideoMessage"),
            message: message,
            preferredStyle: .alert,
        )
        if chatVM.hasPendingVideoNote {
            alert.addAction(UIAlertAction(
                title: L10n.telegram("Conversation.DiscardVoiceMessageAction"),
                style: .destructive,
            ) { [weak self] _ in
                self?.didPresentVideoNoteError = false
                self?.chatVM.discardPendingVideoNote()
            })
            alert.addAction(UIAlertAction(title: L10n.betterTG("Chat.KeepDraft"), style: .cancel) { [weak self] _ in
                self?.didPresentVideoNoteError = false
            })
            if chatVM.canRetryPendingVideoNote {
                alert
                    .addAction(UIAlertAction(
                        title: L10n.telegram("ChatImportActivity.Retry"),
                        style: .default,
                    ) { [weak self] _ in
                        self?.didPresentVideoNoteError = false
                        self?.chatVM.retryPendingVideoNote()
                    })
            }
        } else {
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
                self?.didPresentVideoNoteError = false
            })
        }
        present(alert, animated: true)
    }

    private func presentReactionErrorIfNeeded() {
        guard let message = chatVM.reactionErrorMessage,
              !didPresentReactionError,
              presentedViewController == nil
        else { return }
        didPresentReactionError = true
        chatVM.reactionErrorMessage = nil
        let alert = UIAlertController(
            title: L10n.betterTG("Chat.ReactionErrorTitle"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            self?.didPresentReactionError = false
        })
        present(alert, animated: true)
    }

    private func presentSendErrorIfNeeded() {
        guard let message = chatVM.sendErrorMessage,
              !didPresentSendError,
              presentedViewController == nil
        else { return }
        didPresentSendError = true
        chatVM.sendErrorMessage = nil
        let alert = UIAlertController(title: L10n.betterTG("Message.Generic"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            self?.didPresentSendError = false
        })
        present(alert, animated: true)
    }

    private func presentDraftErrorIfNeeded() {
        guard let message = chatVM.draftErrorMessage,
              !didPresentDraftError,
              presentedViewController == nil
        else { return }
        didPresentDraftError = true
        chatVM.draftErrorMessage = nil
        let alert = UIAlertController(
            title: L10n.telegram("DialogList.Draft"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            self?.didPresentDraftError = false
        })
        present(alert, animated: true)
    }

    private func presentPinErrorIfNeeded() {
        guard let message = chatVM.pinErrorMessage,
              !didPresentPinError,
              presentedViewController == nil
        else { return }
        didPresentPinError = true
        chatVM.pinErrorMessage = nil
        let alert = UIAlertController(
            title: L10n.telegram("Conversation.PinnedMessage"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            self?.didPresentPinError = false
        })
        present(alert, animated: true)
    }

    private func presentMessageActionErrorIfNeeded() {
        guard let message = chatVM.messageActionErrorMessage,
              !didPresentMessageActionError,
              presentedViewController == nil
        else { return }
        didPresentMessageActionError = true
        chatVM.messageActionErrorMessage = nil
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            self?.didPresentMessageActionError = false
        })
        present(alert, animated: true)
    }

    /// requestBotLocationStatus: an inline bot that needs the location asks once before its first query, with
    /// Telegram's text, Cancel and OK. OK shares the location with the bot from then on.
    private func presentInlineBotLocationRequestIfNeeded() {
        guard chatVM.inlineBotLocationRequest != nil,
              !didPresentInlineBotLocationRequest,
              presentedViewController == nil
        else { return }
        didPresentInlineBotLocationRequest = true
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("Conversation.ShareInlineBotLocationConfirmation"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
            self?.didPresentInlineBotLocationRequest = false
            self?.chatVM.answerInlineBotLocationRequest(allowed: false)
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            self?.didPresentInlineBotLocationRequest = false
            self?.chatVM.answerInlineBotLocationRequest(allowed: true)
        })
        present(alert, animated: true)
    }

    @objc private func messageLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, !isSelectingMessages else { return }
        cancelHistoryPanGesture()
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              case .message(let displayedMessageID) = dataSource.itemIdentifier(for: indexPath),
              let message = message(for: displayedMessageID),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
        else { return }
        // A file or music album quotes the caption of the file under the finger, replying to that file.
        let quoteTarget = cell.contextQuoteTarget(at: gesture.location(in: cell))
        let albumItemID = cell.contextAlbumItemID(at: gesture.location(in: cell))
        let messageActions = menu(for: message, albumItemID: albumItemID)
        // ChatControllerOpenTodoContextMenu: a checklist task under the finger opens its own actions first.
        let taskSources = cell.contextChecklistTaskID(at: gesture.location(in: cell))
            .flatMap { checklistTaskMenu(for: message, taskID: $0) }?
            .sources(messageActions: messageActions) ?? []
        // ChatControllerOpenPollContextMenu: a poll answer under the finger opens its own actions first.
        if taskSources.isEmpty, let optionIndex = cell.contextPollOptionIndex(at: gesture.location(in: cell)) {
            presentPollOptionMenu(
                for: message,
                optionIndex: optionIndex,
                cell: cell,
                gesture: gesture,
                messageActions: messageActions,
            )
            return
        }
        presentTelegramContextMenu(
            sourceView: cell.contextPreviewView,
            actions: messageActions,
            tracking: gesture,
            reactionsProvider: contextReactionsProvider(for: message),
            quoteSelection: quoteTarget.flatMap { target -> TelegramContextQuoteSelection? in
                // ChatMessageTextBubbleContentNode: text is selected to quote it or, where it can't be replied to,
                // to copy part of it.
                let canQuote = allowsQuoteSelection(in: message, sourceMessageID: target.sourceMessageID)
                guard canQuote || allowsCopySelection(in: message, sourceMessageID: target.sourceMessageID)
                else { return nil }
                var selection = TelegramContextQuoteSelection(
                    textView: target.textView,
                    allowsCopy: message.properties.canBeCopied,
                    allowsQuote: canQuote,
                ) { [weak self, weak message] range in
                    guard let self, let message else { return }
                    chatVM.beginQuoteReply(to: message, range: range, sourceMessageID: target.sourceMessageID)
                }
                selection.translate = selectionTranslateAction(canCopy: message.properties.canBeCopied)
                return selection
            },
            sources: taskSources,
            onDismiss: { [weak self] in self?.retryClientRestoration() },
        )
    }

    /// ChatControllerOpenTodoContextMenu for a task of a checklist, or nil where the message's menu shows alone.
    private func checklistTaskMenu(for message: CustomMessage, taskID: Int) -> ChecklistTaskMenu? {
        guard !chatVM.isReadOnlyTopic, case .messageChecklist(let content) = message.message.content,
              let task = content.list.tasks.first(where: { $0.id == taskID })
        else { return nil }
        return ChecklistTaskMenu(
            task: task,
            isDone: chatVM.pollInteractionStore.checklistTaskIsDone(
                messageID: message.id,
                taskID: taskID,
                sourceIsDone: task.completedBy != nil,
            ),
            taskCount: content.list.tasks.count,
            permissions: .init(
                canMark: chatVM.canMarkChecklistTasks(message),
                canReply: message.properties.canBeReplied,
                canCopy: message.properties.canBeCopied,
                canCopyLink: message.properties.canGetLink,
                canEdit: chatVM.canEditChecklist(message),
            ),
            handlers: .init(
                toggle: { [weak self, weak message] in
                    guard let self, let message else { return }
                    toggleChecklistTask(taskID, in: message)
                },
                reply: { [weak self, weak message] in
                    guard let self, let message else { return }
                    chatVM.beginChecklistTaskReply(to: message, taskID: taskID)
                },
                copy: { [weak self] in
                    UIPasteboard.setFormattedText(task.text)
                    self?.showChatToast(L10n.telegram("Conversation.TextCopied"))
                },
                copyLink: { [weak self, weak message] in
                    guard let self, let message else { return }
                    copyMessageLink(message, checklistTaskID: taskID)
                },
                edit: { [weak self, weak message] in
                    guard let self, let message else { return }
                    presentEditChecklistTask(message, task: task)
                },
                delete: { [weak self, weak message] in
                    guard let self, let message else { return }
                    chatVM.deleteChecklistTask(message, taskID: taskID)
                },
            ),
        )
    }

    /// The task menu's Check and Uncheck toggle the task as a tap on its circle does.
    private func toggleChecklistTask(_ taskID: Int, in message: CustomMessage) {
        guard case .messageChecklist(let content) = message.message.content,
              let task = content.list.tasks.first(where: { $0.id == taskID }),
              let toggle = chatVM.pollInteractionStore.beginChecklistToggle(
                  messageID: message.id,
                  taskID: taskID,
                  sourceIsDone: task.completedBy != nil,
              )
        else { return }
        chatVM.toggleChecklistTask(toggle) { [weak self] in
            self?.showChatToast(ChatVM.checklistPremiumRequiredText)
        }
    }

    /// ChatControllerOpenPollContextMenu for an answer of a poll. Its Reply, Copy Link and Remove follow TDLib's
    /// pollOptionProperties, and its last row names who added the answer, so the menu opens once both are known.
    private func presentPollOptionMenu(
        for message: CustomMessage,
        optionIndex: Int,
        cell: MessageCell,
        gesture: ContextMenuPressGestureRecognizer,
        messageActions: [TelegramContextMenuAction],
    ) {
        guard !chatVM.isReadOnlyTopic, case .messagePoll(let content) = message.message.content,
              content.poll.options.indices.contains(optionIndex) else { return }
        let option = content.poll.options[optionIndex]
        let client = chatVM.client
        let chatID = message.message.chatId
        let messageID = message.id
        let accountUserID = TDLib.shared.activeAccount?.userID
        Task { [weak self, weak cell, weak message] in
            async let properties = Self.pollOptionProperties(
                option,
                chatID: chatID,
                messageID: messageID,
                client: client,
            )
            async let author = Self.pollOptionAuthor(option.author, accountUserID: accountUserID, client: client)
            let (optionProperties, optionAuthor) = await (properties, author)
            guard let self, let cell, let message, chatVM.locationContextIsCurrent, !isSelectingMessages,
                  self.message(for: message.displayedID) === message
            else { return }
            let menu = PollOptionMenu(
                option: option,
                author: optionAuthor,
                permissions: .init(
                    canVote: chatVM.canVoteInPoll(message),
                    canReply: optionProperties?.canBeReplied ?? false,
                    canCopyLink: optionProperties?.canGetLink ?? false,
                    canRemove: optionProperties?.canBeDeleted ?? false,
                ),
                handlers: pollOptionMenuHandlers(option: option, index: optionIndex, message: message),
            )
            presentTelegramContextMenu(
                sourceView: cell.contextPreviewView,
                actions: messageActions,
                tracking: gesture,
                reactionsProvider: contextReactionsProvider(for: message),
                sources: menu.sources(messageActions: messageActions),
                onDismiss: { [weak self] in self?.retryClientRestoration() },
            )
        }
    }

    private func pollOptionMenuHandlers(
        option: PollOption,
        index: Int,
        message: CustomMessage,
    ) -> PollOptionMenu.Handlers {
        PollOptionMenu.Handlers(
            vote: { [weak self, weak message] in
                guard let self, let message else { return }
                chatVM.setPollOption(message, index: index, isChosen: true)
            },
            retractVote: { [weak self, weak message] in
                guard let self, let message else { return }
                chatVM.setPollOption(message, index: index, isChosen: false)
            },
            reply: { [weak self, weak message] in
                guard let self, let message else { return }
                chatVM.beginPollOptionReply(to: message, optionID: option.id)
            },
            copy: { [weak self] in
                UIPasteboard.setFormattedText(option.text)
                self?.showChatToast(L10n.telegram("Conversation.TextCopied"))
            },
            copyLink: { [weak self, weak message] in
                guard let self, let message else { return }
                copyMessageLink(message, pollOptionID: option.id)
            },
            remove: { [weak self, weak message] in
                guard let self, let message else { return }
                chatVM.deletePollOption(message, optionID: option.id)
            },
            openAuthor: { [weak self] in
                switch option.author {
                case .messageSenderUser(let user):
                    self?.navigate(to: .user(userID: user.userId))
                case .messageSenderChat(let chat):
                    self?.navigate(to: .chat(chatID: chat.chatId))
                case nil:
                    break
                }
            },
        )
    }

    /// Telegram's Edit Item: the checklist editor on the task.
    private func presentEditChecklistTask(_ message: CustomMessage, task: ChecklistTask) {
        openChecklistEditor(message, focusedTaskID: task.id, appends: false)
    }

    /// ChatMessageActionOptions' reply options, opened from the composer's reply panel.
    private func presentReplyOptions(from sourceView: UIView) {
        guard let reply = chatVM.replyMessage else { return }
        let quote = chatVM.replyQuote
        // A quote from an album file's caption replies to that file.
        let targetID = chatVM.replyTargetMessageID ?? reply.id
        var actions = [TelegramContextMenuAction(
            title: L10n.telegram("Story.ViewMessage"),
            image: UIImage(systemName: "text.bubble"),
        ) { [weak self] in
            self?.navigate(to: .message(
                chatID: reply.message.chatId,
                messageID: targetID,
                quote: quote.flatMap { MessageQuoteHighlight(text: $0.text.text, position: $0.position) },
            ))
        }]
        if reply.message.chatId == chatVM.chatID, allowsQuoteSelection(in: reply, sourceMessageID: targetID) {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.MessageOptionsQuoteSelect"),
                image: UIImage(systemName: "text.quote"),
            ) { [weak self] in
                guard let self else { return }
                if !presentReplyQuoteSelection(messageID: targetID, requiresFullyVisible: true) {
                    scrollToMessage(id: targetID, opensQuoteSelection: true)
                }
            })
        }
        if reply.message.chatId == chatVM.chatID, reply.properties.canBeRepliedInAnotherChat {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.MessageOptionsReplyInAnotherChat"),
                image: UIImage(systemName: "arrowshape.turn.up.right"),
            ) { [weak self] in self?.presentReplyInAnotherChat(targetMessageID: targetID) })
        }
        if quote != nil {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.MessageOptionsQuoteRemove"),
                image: UIImage(systemName: "text.badge.xmark"),
                isDestructive: true,
                startsNewSection: true,
            ) { [weak self] in self?.chatVM.removeReplyQuote() })
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("Conversation.MessageOptionsReplyCancel"),
            image: UIImage(systemName: "trash"),
            isDestructive: true,
            startsNewSection: quote == nil,
        ) { [weak self] in self?.chatVM.cancelReply() })
        // The panel spans the composer, so the menu opens above it.
        presentTelegramContextMenu(sourceView: sourceView, actions: actions, presentationStyle: .menuOnly)
    }

    /// ChatMessageActionOptions' Reply in Another Chat (moveReplyMessageToAnotherChat): the Forward picker in its
    /// reply purpose offers the chats the user can write to. Choosing this chat keeps the reply; another chat takes
    /// it, with its quote, as a reply to this chat's message, and this chat's reply is cleared.
    private func presentReplyInAnotherChat(targetMessageID: Int64) {
        guard presentationMode == .full,
              presentedViewController == nil,
              let reply = chatVM.replyMessage,
              let accountID = TDLib.shared.activeAccountID,
              TDLib.shared.activeClient.id == chatVM.client.id,
              let request = try? MessageForwardRequest(sourceLocation: chatVM.location, messageIDs: [targetMessageID])
        else { return }
        let quote = chatVM.replyQuote
        var seen = Set<Int64>()
        let seedChats = RootVM.shared
            .allFolders
            .flatMap(\.chats)
            .map(\.chat)
            .filter { seen.insert($0.id).inserted }
        let picker = ForwardMessagesViewController(
            request: request,
            client: chatVM.client,
            accountID: accountID,
            seedChats: seedChats,
            purpose: .replyInAnotherChat,
        )
        picker.onChosenChat = { [weak self, weak reply] chat, topic in
            guard let self, let reply, TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == chatVM.client.id else { return }
            let destination = ChatLocation.current(
                chatID: chat.id,
                topic: topic.map { .messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId)) },
                client: chatVM.client,
            )
            guard destination != location else { return }
            chatVM.cancelReply()
            Self.openExternalReply(
                to: reply,
                targetMessageID: targetMessageID,
                quote: quote,
                in: chat,
                topic: topic,
                destination: destination,
                navigationController: navigationController,
            )
        }
        let pickerNavigation = TelegramNavigationController(rootViewController: picker)
        pickerNavigation.modalPresentationStyle = .fullScreen
        present(pickerNavigation, animated: true)
    }

    /// Switch inline's `targetChatChosen` (ChatControllerOpenPeer with `peerTypes`): the Forward picker offers the
    /// writable chats of the button's kinds. This chat takes the query in its composer; another chat opens with it.
    private func presentSwitchInlinePicker(text: String, types: InlineTargetChatTypes, messageID: Int64) {
        guard presentationMode == .full,
              presentedViewController == nil,
              let accountID = TDLib.shared.activeAccountID,
              TDLib.shared.activeClient.id == chatVM.client.id,
              let request = try? MessageForwardRequest(sourceLocation: chatVM.location, messageIDs: [messageID])
        else { return }
        var seen = Set<Int64>()
        let seedChats = RootVM.shared
            .allFolders
            .flatMap(\.chats)
            .map(\.chat)
            .filter { seen.insert($0.id).inserted }
        let picker = ForwardMessagesViewController(
            request: request,
            client: chatVM.client,
            accountID: accountID,
            seedChats: seedChats,
            purpose: .switchInline(types),
        )
        picker.onChosenChat = { [weak self] chat, topic in
            guard let self, TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == chatVM.client.id else { return }
            let destination = ChatLocation.current(
                chatID: chat.id,
                topic: topic.map { .messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId)) },
                client: chatVM.client,
            )
            guard destination != location else { return insertInlineQuery(text) }
            Self.openSwitchInline(
                text,
                in: chat,
                topic: topic,
                destination: destination,
                navigationController: navigationController,
            )
        }
        let pickerNavigation = TelegramNavigationController(rootViewController: picker)
        pickerNavigation.modalPresentationStyle = .fullScreen
        present(pickerNavigation, animated: true)
    }

    /// Select Specific Quote: the replied message opens with its text selected, from the current quote or in full
    /// (Telegram's beginTextSelection). Quote Selected Part, or Quote over the selection, sets the reply's quote.
    /// False while the message is not on screen.
    @discardableResult private func presentReplyQuoteSelection(messageID: Int64, requiresFullyVisible: Bool) -> Bool {
        guard let displayedID = chatVM.displayedMessageID(containing: messageID),
              let indexPath = dataSource.indexPath(for: .message(displayedID)),
              let message = message(for: displayedID),
              let source = message.sourceMessages.first(where: { $0.id == messageID }),
              allowsQuoteSelection(in: message, sourceMessageID: messageID),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCell,
              let textView = cell.contextQuoteTextView(forMessageID: messageID)
        else { return false }
        if requiresFullyVisible,
           !collectionView.bounds.inset(by: collectionView.adjustedContentInset).contains(cell.frame) { return false }
        var quoteRange: NSRange?
        if chatVM.replyTargetMessageID == messageID, let quote = chatVM.replyQuote,
           let resolved = MessageQuoteHighlight(text: quote.text.text, position: quote.position)?
               .resolved(in: source.content)
        {
            quoteRange = NSRange(location: resolved.position, length: resolved.length)
        }
        let applyQuote: (NSRange) -> Void = { [weak self, weak message] range in
            guard let self, let message else { return }
            chatVM.beginQuoteReply(to: message, range: range, sourceMessageID: messageID)
        }
        let presented = presentTelegramContextMenu(
            sourceView: cell.contextPreviewView,
            actions: [TelegramContextMenuAction(
                title: L10n.telegram("Conversation.MessageOptionsQuoteSelectedPart"),
                image: UIImage(systemName: "text.quote"),
            ) { [weak textView] in
                guard let range = textView?.lastQuoteSelection else { return }
                applyQuote(range)
            }],
            quoteSelection: TelegramContextQuoteSelection(
                textView: textView,
                allowsCopy: message.properties.canBeCopied,
                handler: applyQuote,
            ),
            onDismiss: { [weak self] in self?.retryClientRestoration() },
        )
        guard presented else { return false }
        Task { @MainActor [weak textView] in
            // After the preview's 0.34 s spring settles, where the selection's edit menu is placed.
            try? await Task.sleep(for: .milliseconds(350))
            textView?.beginQuoteSelection(range: quoteRange)
        }
        return true
    }

    /// Telegram's `focusedPollAddOptionMessageId`: while a poll's new answer is typed the input panel and the jump
    /// buttons go away and the history holds still with the poll above the keyboard (ChatControllerNode).
    private func pollAddOptionFocusChanged(_ messageID: Int64?) {
        guard presentationMode == .full, pollAddOptionFocusMessageID != messageID else { return }
        pollAddOptionFocusMessageID = messageID
        let focused = messageID != nil
        collectionView.isScrollEnabled = !focused
        if showsComposer {
            composerView.isUserInteractionEnabled = !focused
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) {
                self.composerView.alpha = focused ? 0 : 1
            }
        }
        updateScrollToLatestButtonVisibility(animated: true)
        view.setNeedsLayout()
        pendingPollAddOptionScroll = focused
        guard focused else { return }
        abandonRestoredViewport()
        // The keyboard may already be up, so no frame change follows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.scrollFocusedPollAddOptionIntoView()
        }
    }

    /// Moves the focused poll above the keyboard (`navigateToMessage` in ChatControllerNode); a poll taller than the
    /// history keeps its bottom, where the field is, in view.
    private func scrollFocusedPollAddOptionIntoView() {
        guard pendingPollAddOptionScroll, let messageID = pollAddOptionFocusMessageID,
              let displayedID = chatVM.displayedMessageID(containing: messageID),
              let indexPath = dataSource.indexPath(for: .message(displayedID)),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath)
        else { return }
        pendingPollAddOptionScroll = false
        let insets = collectionView.adjustedContentInset
        let visibleHeight = collectionView.bounds.height - insets.top - insets.bottom - 16
        // The history is flipped: the cell's minY is its bottom on screen.
        var target = attributes.frame.insetBy(dx: 0, dy: -8)
        target.size.height = min(target.height, max(1, visibleHeight))
        collectionView.scrollRectToVisible(target, animated: true)
    }

    @objc private func historyTapped(_: UITapGestureRecognizer) {
        abandonRestoredViewport()
        // Telegram's `dismissInput`: a bot's persistent keyboard stays, and another dismissed keyboard stays closed.
        if showsComposer, composerView.isReplyKeyboardActive {
            if keepsPersistentReplyKeyboard { return }
            chatVM.replyKeyboard.setClosed(true)
        }
        view.endEditing(true)
        // A bot's persistent keyboard returns once text input ends (`chatInputTextNodeDidFinishEditing`).
        if showsComposer, keepsPersistentReplyKeyboard {
            composerView.showReplyKeyboard()
        }
    }

    /// Telegram opens a new bot keyboard in place of the system keyboard once per keyboard change
    /// (`updateChatPresentationInterfaceStateImpl`); a change from before the chat appeared is decided when it does.
    private func evaluateReplyKeyboardChange() {
        guard showsComposer, presentationMode == .full, chatVM.supportsReplyKeyboard, view.window != nil else { return }
        let revision = chatVM.replyKeyboard.revision
        guard evaluatedReplyKeyboardRevision != revision else { return }
        evaluatedReplyKeyboardRevision = revision
        guard !clientOwnerRetired, chatVM.locationContextIsCurrent, !messageSearchActive, !isSelectingMessages,
              chatVM.replyKeyboard.opensAutomatically(
                  isEditing: chatVM.editCustomMessage != nil,
                  hasText: !chatVM.text.characters.isEmpty,
              )
        else { return }
        composerView.showReplyKeyboard()
    }

    private func cancelHistoryPanGesture() {
        let panGesture = collectionView.panGestureRecognizer
        guard panGesture.state == .began || panGesture.state == .changed else { return }
        panGesture.isEnabled = false
        panGesture.isEnabled = true
    }

    /// The message menu; `albumItemID` is the album item the long press was on, for actions on a single item.
    private func menu(for message: CustomMessage, albumItemID: Int64? = nil) -> [TelegramContextMenuAction] {
        if chatVM.isReadOnlyTopic {
            var readOnlyActions = [TelegramContextMenuAction]()
            if message.properties.canBeCopied,
               let text = copyableText(from: message.message.content)
            {
                readOnlyActions.append(TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.ContextMenuCopy"),
                    image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
                ) { UIPasteboard.setFormattedText(text) })
            }
            if let translateAction = translateAction(for: message) {
                readOnlyActions.append(translateAction)
            }
            readOnlyActions.append(contentsOf: mediaSaveActions(for: message, albumItemID: albumItemID))
            return readOnlyActions
        }
        var elements = [TelegramContextMenuAction]()
        let resendableIDs = chatVM.resendableMessageIDs(in: message)
        if !resendableIDs.isEmpty {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.MessageDialogRetry"),
                image: UIImage(systemName: "arrow.clockwise"),
            ) { [weak self] in
                self?.chatVM.resendMessages(ids: resendableIDs)
            })
            let groups = chatVM.resendableMessageGroups()
            if groups.count > 1 {
                elements.append(TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.MessageDialogRetryAll", groups.count),
                    image: UIImage(systemName: "arrow.clockwise"),
                ) { [weak self] in
                    self?.chatVM.resendMessages(ids: groups.flatMap(\.self))
                })
            }
        }
        if message.properties.canBeReplied {
            elements
                .append(TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.ContextMenuReply"),
                    image: UIImage(systemName: "arrowshape.turn.up.left"),
                ) { [weak self] in
                    self?.chatVM.beginReply(to: message)
                })
        }
        let isRichMessage =
            if case .messageRichMessage = message.message.content {
                true
            } else {
                false
            }
        // For polls, live locations and checklists `canBeEdited` means stop or update, not a text edit.
        if message.properties.canBeEdited, !isRichMessage, Self.editsText(message.message.content) {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Common.Edit"),
                image: UIImage(systemName: "square.and.pencil"),
            ) { [weak self] in
                self?.chatVM.beginMessageEditing(message)
            })
        }
        // Telegram lists Retract Vote ahead of Stop Poll.
        if chatVM.canRetractPollVote(message) {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.UnvotePoll"),
                image: UIImage(systemName: "arrow.uturn.backward.circle"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                chatVM.retractPollVote(message)
            })
        }
        if chatVM.canAddChecklistTask(message) {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.Todo.ContextMenu.AddTask"),
                image: UIImage(systemName: "plus.circle"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                presentAddChecklistTask(message)
            })
        }
        if let stopAction = contentStopAction(for: message) {
            elements.append(stopAction)
        }
        if let repliesTitle = viewRepliesTitle(for: message) {
            elements.append(TelegramContextMenuAction(
                title: repliesTitle,
                image: UIImage(systemName: "bubble.left.and.bubble.right"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                openComments(messageID: message.id, displayedID: message.displayedID)
            })
        }
        if message.properties.canBeCopied,
           let text = copyableText(from: message.message.content)
        {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuCopy"),
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            ) { UIPasteboard.setFormattedText(text) })
        }
        if let translateAction = translateAction(for: message) {
            elements.append(translateAction)
        }
        if message.properties.canGetLink {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuCopyLink"),
                image: UIImage(systemName: "link"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                copyMessageLink(message)
            })
        }
        elements.append(contentsOf: stickerAndAnimationActions(for: message))
        elements.append(contentsOf: mediaSaveActions(for: message, albumItemID: albumItemID))
        if canOfferPinAction(for: message) {
            if message.isPinned {
                // Telegram unpins from the message menu without a confirmation (askForConfirmation: false).
                elements.append(TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.Unpin"),
                    image: UIImage(systemName: "pin.slash"),
                ) { [weak self, weak message] in
                    guard let self, let message, canOfferPinAction(for: message) else { return }
                    chatVM.unpinMessage(message)
                })
            } else {
                elements.append(pinMenuAction(for: message))
            }
        }
        if canForwardMessageContent(message),
           message.properties.canBeForwarded || message.properties.canBeCopied
        {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuForward"),
                image: UIImage(systemName: "arrowshape.turn.up.right"),
            ) { [weak self] in
                self?.presentForwardPicker(forDisplayedMessageIDs: [message.displayedID])
            })
        }
        // ChatInterfaceStateContextMenus: Report for messages TDLib lets the user report (canReportChat).
        if message.properties.canReportChat, !message.message.isOutgoing {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuReport"),
                image: UIImage(systemName: "exclamationmark.bubble"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                ReportContentViewController.present(
                    chatID: message.message.chatId,
                    messageIDs: message.sourceMessages.map(\.id),
                    from: self,
                ) { [weak self] in
                    self?.showChatToast(L10n.telegram("Report.Succeed"))
                }
            })
        }
        if canSelectMessage(message) {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuSelect"),
                image: UIImage(systemName: "checkmark.circle"),
            ) { [weak self] in
                self?.beginMessageSelection(with: message.displayedID)
            })
        }

        var deleteActions = [TelegramContextMenuAction]()
        if message.properties.canBeDeletedOnlyForSelf {
            deleteActions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.DeleteMessagesForMe"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: false) })
        }
        if message.properties.canBeDeletedForAllUsers {
            deleteActions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.DeleteMessagesForEveryone"),
                image: UIImage(systemName: "trash.fill"),
                isDestructive: true,
            ) { [weak self] in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: true) })
        }
        if let request = adminDeleteRequest(for: message) {
            // ChatControllerAdminBanUsers: an admin deleting another member's message gets AdminUserActionsSheet.
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Common.Delete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in
                guard let self else { return }
                AdminDeleteMessagesViewController.present(request, from: self) { [weak self] text in
                    self?.showChatToast(text)
                }
            })
        } else if !deleteActions.isEmpty {
            elements.append(TelegramContextMenuAction(
                title: L10n.telegram("Common.Delete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
                children: deleteActions,
            ))
        }
        elements.append(contentsOf: interactionActions(for: message))
        if let readDateAction = readDateAction(for: message) {
            if !elements.isEmpty { elements[0].startsNewSection = true }
            elements.insert(readDateAction, at: 0)
        }
        return elements
    }

    /// ChatReadReportContextItem in a private chat: when the other person read an outgoing message
    /// (`getMessageReadDate`), at the top of the menu, or Telegram's "show when" when the user hides their own read
    /// time; tapping that one offers to show it.
    private func readDateAction(for message: CustomMessage) -> TelegramContextMenuAction? {
        guard case .user(let user) = chatVM.customChat.type, !chatVM.customChat.isSavedMessages,
              message.message.isOutgoing, message.properties.canGetReadDate, message.deliveryState == .read
        else { return nil }
        let readDate = CurrentValueSubject<TDNativeMessageReadDate?, Never>(nil)
        var action = TelegramContextMenuAction(
            title: L10n.telegram("Chat.ContextMenuReadDate.ReadAvailablePrefix"),
            image: UIImage(systemName: "checkmark.message"),
        ) { [weak self] in
            guard case .messageReadDateMyPrivacyRestricted? = readDate.value else { return }
            self?.presentShowReadTimeHint(name: user.firstName.isEmpty ? user.lastName : user.firstName)
        }
        action.titleUpdates = readDate.compactMap { $0.map(Self.readDateTitle) }.eraseToAnyPublisher()
        let client = chatVM.client
        let chatID = message.message.chatId
        let messageID = message.id
        Task { [weak self] in
            let value = try? await client.send(TDNativeRequests.getMessageReadDate(
                chatId: chatID,
                messageId: messageID,
            ))
            guard let self, chatVM.locationContextIsCurrent else { return }
            readDate.send(value)
        }
        return action
    }

    /// PremiumPrivacyScreen's `.readTime` without the Premium offer: Show My Read Time
    /// (setReadDatePrivacySettings) only after the user taps it.
    private func presentShowReadTimeHint(name: String) {
        guard chatVM.locationContextIsCurrent, presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.telegram("PrivacyInfo.ShowReadTime.Title"),
            message: L10n.telegram("PrivacyInfo.ShowReadTime.Text", name).withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        let client = chatVM.client
        alert.addAction(UIAlertAction(title: L10n.telegram("PrivacyInfo.ShowReadTime.ButtonTitle"), style: .default) {
            [weak self] _ in
            guard let self, chatVM.locationContextIsCurrent else { return }
            Task {
                _ = try? await client.send(TDNativeRequests.setReadDatePrivacySettings(
                    settings: TDNativeReadDatePrivacySettings(showReadDate: true),
                ))
            }
        })
        present(alert, animated: true)
    }

    /// ChatInterfaceStateContextMenus' `banAuthor`: in a group, an admin who can delete messages or ban members
    /// deleting an incoming message from a person or another chat.
    private func adminDeleteRequest(for message: CustomMessage) -> AdminDeleteMessagesViewController.Request? {
        guard !message.message.isOutgoing, message.properties.canBeDeletedForAllUsers else { return nil }
        return adminDeleteRequest(for: message.sourceMessages)
    }

    /// ChatInterfaceStateContextMenus' `banAuthors`: the people and other chats behind the incoming messages being
    /// deleted, for an admin who can delete messages or ban members. The user's own messages and the group posting as
    /// itself are deleted without being acted on.
    private func adminDeleteRequest(for messages: [Message]) -> AdminDeleteMessagesViewController.Request? {
        let customChat = chatVM.customChat
        guard let supergroup = customChat.supergroup, !supergroup.isChannel else { return nil }
        let canBan: Bool =
            switch supergroup.status {
            case .chatMemberStatusCreator: true
            case .chatMemberStatusAdministrator(let administrator): administrator.rights.canRestrictMembers
            default: false
            }
        let canDeleteAll = customChat.canDeleteAllMessages
        guard canBan || canDeleteAll else { return nil }
        var senders = [MessageSender]()
        var spamMessageIDs = [Int64]()
        for message in messages where !message.isOutgoing && message.sendingState == nil {
            if case .messageSenderChat(let sender) = message.senderId, sender.chatId == message.chatId { continue }
            spamMessageIDs.append(message.id)
            if !senders.contains(message.senderId) {
                senders.append(message.senderId)
            }
        }
        guard !senders.isEmpty else { return nil }
        return AdminDeleteMessagesViewController.Request(
            chatID: customChat.chat.id,
            supergroupID: supergroup.id,
            messageIDs: messages.map(\.id),
            spamMessageIDs: spamMessageIDs,
            senders: senders,
            canDeleteAll: canDeleteAll,
            canBan: canBan,
            chatPermissions: customChat.chat.permissions,
        )
    }

    /// ChatMessageContextMenu's read receipts and reactions below the actions: who saw the message in a small group
    /// (canGetViewers) and who reacted to it (canGetAddedReactions).
    private func interactionActions(for message: CustomMessage) -> [TelegramContextMenuAction] {
        var actions = [TelegramContextMenuAction]()
        if message.properties.canGetViewers {
            actions.append(TelegramContextMenuAction(
                title: L10n.betterTG("Message.SeenBy"),
                image: UIImage(systemName: "eye"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                MessageInteractionsViewController.present(
                    .viewers,
                    chatID: message.message.chatId,
                    messageID: message.id,
                    from: self,
                )
            })
        }
        let reactionCount = message.reactions?.reactions.reduce(0) { $0 + $1.totalCount } ?? 0
        if message.reactions?.canGetAddedReactions == true, reactionCount > 0 {
            let isOutgoing = message.message.isOutgoing
            actions.append(TelegramContextMenuAction(
                title: L10n.telegramPlural(
                    isOutgoing ? "Chat.OutgoingContextReactionCount" : "Chat.ContextReactionCount",
                    count: reactionCount,
                ),
                image: UIImage(systemName: "heart"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                MessageInteractionsViewController.present(
                    .reactions(isOutgoing: isOutgoing, count: reactionCount),
                    chatID: message.message.chatId,
                    messageID: message.id,
                    from: self,
                )
            })
        }
        if !actions.isEmpty { actions[0].startsNewSection = true }
        return actions
    }

    /// Telegram's Copy Link (getMessageLink): an album's link, or a thread's or topic's in one, and the toast that
    /// says a private link works only for members. A checklist task's or a poll answer's link opens that item.
    private func copyMessageLink(_ message: CustomMessage, checklistTaskID: Int = 0, pollOptionID: String = "") {
        let client = chatVM.client
        let currentLocation = location
        let isAlbum =
            if case .album = message.displayedID {
                true
            } else {
                false
            }
        let messageID = message.id
        Task { [weak self] in
            let link = try? await client.send(TDNativeRequests.getMessageLink(
                chatId: currentLocation.chatID,
                messageId: messageID,
                mediaTimestamp: 0,
                checklistTaskId: checklistTaskID,
                pollOptionId: pollOptionID,
                forAlbum: isAlbum,
                inMessageThread: currentLocation.isTopicScoped,
            ))
            guard let self, chatVM.locationContextIsCurrent, let link else { return }
            UIPasteboard.setPlainText(link.link)
            showChatToast(L10n.telegram(link.isPublic
                    ? "Conversation.LinkCopied"
                    : "Conversation.PrivateMessageLinkCopiedLong"))
        }
    }

    private func synchronizeNativeSelection() {
        for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
            guard case .message(let id) = dataSource.itemIdentifier(for: indexPath),
                  selectedDisplayedMessageIDs.contains(id), isSelectingMessages
            else {
                collectionView.deselectItem(at: indexPath, animated: false)
                continue
            }
        }
        guard isSelectingMessages else { return }
        for id in selectedDisplayedMessageIDs {
            if let indexPath = dataSource.indexPath(for: .message(id)),
               collectionView.indexPathsForSelectedItems?.contains(indexPath) != true
            {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
    }

    private func beginMessageSelection(with displayedMessageID: DisplayedMessageID, selectInitialMessage: Bool = true) {
        guard presentationMode == .full,
              let message = message(for: displayedMessageID),
              canSelectMessage(message)
        else { return }
        view.endEditing(true)
        isSelectingMessages = true
        selectedDisplayedMessageIDs = selectInitialMessage ? [displayedMessageID] : []
        collectionView.isEditing = true
        messageContextGesture.isEnabled = false
        composerView.setHiddenForSearch(true)
        updateScrollToLatestButtonVisibility(animated: true)
        messageSelectionToolbar.isHidden = false
        messageSelectionToolbar.alpha = 0
        messageSelectionToolbar.transform = CGAffineTransform(
            translationX: 0,
            y: MessageSelectionToolbar.contentHeight + view.safeAreaInsets.bottom,
        )
        updatePinnedMessageBanner(animated: true)
        updateMessageSelectionChrome()
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
        ) {
            self.messageSelectionToolbar.alpha = 1
            self.messageSelectionToolbar.transform = .identity
            self.view.layoutIfNeeded()
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: selectionAccessibilityAnnouncement,
        )
    }

    private func toggleMessageSelection(displayedMessageID: DisplayedMessageID) {
        guard isSelectingMessages,
              let selectedMessage = message(for: displayedMessageID),
              canSelectMessage(selectedMessage)
        else { return }
        selectionCapabilityTask?.cancel()
        selectionCapabilityTask = nil
        selectionCapabilityGeneration = nil
        if selectedDisplayedMessageIDs.contains(displayedMessageID) {
            selectedDisplayedMessageIDs.remove(displayedMessageID)
        } else {
            let proposedIDs = selectedDisplayedMessageIDs.union([displayedMessageID])
            let proposedCount = sourceMessageIDs(forDisplayedMessageIDs: proposedIDs).count
            if proposedCount > 100 {
                presentSelectionLimitAlert(count: proposedCount)
                return
            }
            selectedDisplayedMessageIDs.insert(selectedMessage.displayedID)
        }
        if selectedDisplayedMessageIDs.isEmpty {
            endMessageSelection()
        } else {
            updateMessageSelectionChrome(reconfigureIDs: [displayedMessageID])
            UIAccessibility.post(
                notification: .announcement,
                argument: selectionAccessibilityAnnouncement,
            )
        }
    }

    private func presentSelectionLimitAlert(count: Int) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.betterTG("Chat.SelectionLimitTitle"),
            message: MessageForwardingError.tooManyMessages(count).localizedDescription,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    private func endMessageSelection(reconfigure: Bool = true) {
        guard isSelectingMessages else { return }
        defer { retryClientRestoration() }
        selectionCapabilityTask?.cancel()
        selectionCapabilityTask = nil
        selectionCapabilityGeneration = nil
        isSelectingMessages = false
        selectionInteractionActive = false
        collectionView.isEditing = false
        selectedDisplayedMessageIDs.removeAll()
        synchronizeNativeSelection()
        messageContextGesture.isEnabled = presentationMode == .full
        customNavigationBar.setSelectionCount(nil)
        composerView.setHiddenForSearch(messageSearchActive)
        updatePinnedMessageBanner(animated: true)
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
        ) {
            self.messageSelectionToolbar.alpha = 0
            self.messageSelectionToolbar.transform = CGAffineTransform(
                translationX: 0,
                y: MessageSelectionToolbar.contentHeight + self.view.safeAreaInsets.bottom,
            )
        } completion: { [weak self] _ in
            guard let self, !isSelectingMessages else { return }
            messageSelectionToolbar.isHidden = true
            messageSelectionToolbar.transform = .identity
            view.setNeedsLayout()
        }
        if reconfigure {
            reconfigureMessages(ids: dataSource.snapshot().itemIdentifiers.compactMap(\.displayedMessageID))
        }
        updateScrollToLatestButtonVisibility(animated: false)
        view.setNeedsLayout()
    }

    private func updateMessageSelectionChrome(
        reconfigureIDs: [DisplayedMessageID]? = nil,
        isBusy: Bool = false,
    ) {
        guard isSelectingMessages else { return }
        let sourceIDs = selectedSourceMessageIDs
        let messages = selectedDisplayedMessages
        let canForward = !sourceIDs.isEmpty && sourceIDs.count <= 100
            && messages.allSatisfy { canForwardMessageContent($0) }
            && (messages.allSatisfy(\.properties.canBeForwarded)
                || messages.allSatisfy(\.properties.canBeCopied))
        let canDelete = !messages.isEmpty && messages.allSatisfy {
            $0.properties.canBeDeletedOnlyForSelf || $0.properties.canBeDeletedForAllUsers
        }
        synchronizeNativeSelection()
        customNavigationBar.setSelectionCount(sourceIDs.count)
        messageSelectionToolbar.update(
            selectedCount: sourceIDs.count,
            canDelete: canDelete,
            canForward: canForward,
            isBusy: isBusy,
        )
        if let reconfigureIDs {
            reconfigureMessages(ids: reconfigureIDs)
        } else {
            reconfigureMessages(ids: dataSource.snapshot().itemIdentifiers.compactMap(\.displayedMessageID))
        }
        view.setNeedsLayout()
    }

    private func sourceMessageIDs(forDisplayedMessageIDs displayedIDs: Set<DisplayedMessageID>) -> [Int64] {
        let sourceIDs = chatVM.messages
            .filter { displayedIDs.contains($0.displayedID) }
            .flatMap { $0.sourceMessages.map(\.id) }
        return Array(Set(sourceIDs)).sorted()
    }

    private func canSelectMessage(_ message: CustomMessage) -> Bool {
        !message.contentPresentation.isService && message.message.selfDestructType == nil
    }

    private func canForwardMessageContent(_ message: CustomMessage) -> Bool {
        if case .messagePaidMedia = message.message.content {
            false
        } else {
            true
        }
    }

    private func canOfferReactionPicker(for message: CustomMessage) -> Bool {
        chatVM.location.matches(message: message.message)
            && !message.contentPresentation.isService
            && message.message.selfDestructType == nil
            && message.message.ephemeralMessageId == 0
            && message.message.sendingState == nil
            && chatVM.canAddReactions
    }

    private func canOfferPinAction(for message: CustomMessage) -> Bool {
        chatVM.supportsPinnedMessages
            && message.album.isEmpty
            && chatVM.acceptsChatLevelPin(message.message)
            && !message.contentPresentation.isService
            && message.message.sendingState == nil
            && message.properties.canBePinned
    }

    /// Telegram's message-menu pin (ChatControllerLoadDisplayNode, pinMessage): channels and Saved Messages pin at
    /// once; private chats and groups replace the menu with their two pin options.
    private func pinMenuAction(for message: CustomMessage) -> TelegramContextMenuAction {
        let title = L10n.telegram("Conversation.Pin")
        let image = UIImage(systemName: "pin")
        let children: [TelegramContextMenuAction]
        if chatVM.customChat.isSavedMessages {
            return pinOption(title: title, image: image, mode: .savedMessages, message: message)
        }
        switch chatVM.customChat.type {
        case .bot(let user), .user(let user):
            children = [
                pinOption(
                    title: L10n.telegram("Conversation.PinMessagesFor", user.compactDisplayTitle),
                    mode: .privateForBoth,
                    message: message,
                ),
                pinOption(
                    title: L10n.telegram("Conversation.PinMessagesForMe"),
                    mode: .privateForSelf,
                    message: message,
                ),
            ]
        case .supergroup(let supergroup) where supergroup.isChannel:
            return pinOption(title: title, image: image, mode: .channel, message: message)
        case .group, .supergroup:
            children = [
                pinOption(
                    title: L10n.telegram("Conversation.PinMessageAlert.PinAndNotifyMembers"),
                    mode: .groupNotify,
                    message: message,
                ),
                pinOption(
                    title: L10n.telegram("Conversation.PinMessageAlert.OnlyPin"),
                    mode: .groupSilent,
                    message: message,
                ),
            ]
        }
        return TelegramContextMenuAction(title: title, image: image, children: children)
    }

    private func pinOption(
        title: String,
        image: UIImage? = nil,
        mode: MessagePinMode,
        message: CustomMessage,
    ) -> TelegramContextMenuAction {
        TelegramContextMenuAction(title: title, image: image) { [weak self, weak message] in
            guard let self, let message, canOfferPinAction(for: message) else { return }
            chatVM.pinMessage(message, mode: mode)
        }
    }

    /// Telegram's pinned-panel close: those who may unpin are asked to unpin (Conversation.UnpinMessageAlert);
    /// everyone else hides the banner for themselves.
    private func closePinnedMessageBanner() {
        guard let pinned = chatVM.visiblePinnedMessage, presentedViewController == nil else {
            chatVM.hidePinnedMessageBanner()
            return
        }
        if let message = chatVM.messages.first(where: { $0.id == pinned.id }) {
            guard canOfferPinAction(for: message) else {
                chatVM.hidePinnedMessageBanner()
                return
            }
            presentUnpinAlert { [weak self, weak message] in
                guard let self, let message, canOfferPinAction(for: message) else { return }
                chatVM.unpinMessage(message)
            }
            return
        }
        // Outside the loaded history: ask TDLib whether this account may unpin before offering it.
        let pinnedID = pinned.id
        Task { [weak self] in
            guard let self else { return }
            let canUnpin = await chatVM.canUnpinMessage(id: pinnedID)
            guard chatVM.visiblePinnedMessage?.id == pinnedID, presentedViewController == nil else { return }
            guard canUnpin else {
                chatVM.hidePinnedMessageBanner()
                return
            }
            presentUnpinAlert { [weak self] in self?.chatVM.unpinBannerMessage(id: pinnedID) }
        }
    }

    private func presentUnpinAlert(unpin: @escaping () -> Void) {
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("Conversation.UnpinMessageAlert"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Conversation.Unpin"), style: .default) { _ in unpin() })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func contextReactionsProvider(for message: CustomMessage) -> TelegramContextReactionsProvider? {
        guard canOfferReactionPicker(for: message),
              let accountID = TDLib.shared.activeAccountID, accountID == chatVM.accountID else { return nil }
        let client = chatVM.client
        let chatID = chatVM.chatID
        let messageID = message.id
        return { [weak self, weak message] in
            guard let self, let message, TDLib.shared.activeClient.id == client.id else { return [] }
            do {
                async let availableRequest = client.getMessageAvailableReactions(
                    chatId: chatID,
                    messageId: messageID,
                    rowSize: 7,
                )
                async let userRequest = client.getMe()
                let (available, user) = try await (availableRequest, userRequest)
                let types = Array(available.contextReactionTypes(isPremium: user.isPremium).prefix(24))
                let stickers = await CustomEmojiStickerRepository.shared.stickers(
                    for: types.compactMap(\.customEmojiID),
                    client: client,
                )
                guard !Task.isCancelled, TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id,
                      chatVM.displayedMessageID(containing: messageID).flatMap({ self.message(for: $0) }) === message
                else { return [] }
                return types.map { type in
                    TelegramContextMenuReaction(
                        type: type,
                        isChosen: MessageReactionStateReducer.isChosen(
                            type,
                            in: message.reactions,
                        ),
                        sticker: type.customEmojiID.flatMap { stickers[$0] },
                        client: client,
                    ) { [
                        weak self,
                        weak message,
                    ] in
                        guard let self, let message, TDLib.shared.activeAccountID == accountID,
                              TDLib.shared.activeClient.id == client.id else { return }
                        chatVM.toggleReaction(on: message, type: type, isBig: false)
                    }
                }
            } catch { return [] }
        }
    }

    private func reconfigureMessages(ids: [DisplayedMessageID]) {
        guard !ids.isEmpty else { return }
        enqueueTimeline(.init(
            structural: restoredViewport?.pending == true,
            ids: Set(ids),
            restoresViewport: true,
            viewportRevision: viewportRestorationAuthority.invalidationRevision,
        ))
    }

    private func forwardSelectedMessages() {
        presentForwardPicker(forDisplayedMessageIDs: selectedDisplayedMessageIDs)
    }

    private func presentForwardPicker(forDisplayedMessageIDs displayedIDs: Set<DisplayedMessageID>) {
        do {
            let request = try MessageForwardRequest(
                sourceLocation: chatVM.location,
                messageIDs: sourceMessageIDs(forDisplayedMessageIDs: displayedIDs),
            )
            presentForwardPicker(request: request, initialMode: nil, replacingForwardID: nil)
        } catch {
            presentForwardRequestError(error)
        }
    }

    /// `replacingForwardID` is the composer's pending forward when Change Recipient reopens the picker: a choice
    /// moves it to the new destination.
    private func presentForwardPicker(
        request: MessageForwardRequest,
        initialMode: MessageForwardMode?,
        replacingForwardID: UUID?,
    ) {
        guard presentationMode == .full,
              presentedViewController == nil,
              let accountID = TDLib.shared.activeAccountID,
              TDLib.shared.activeClient.id == chatVM.client.id
        else { return }
        var seen = Set<Int64>()
        let seedChats = RootVM.shared
            .allFolders
            .flatMap(\.chats)
            .map(\.chat)
            .filter { seen.insert($0.id).inserted }
        let picker = ForwardMessagesViewController(
            request: request,
            client: chatVM.client,
            accountID: accountID,
            seedChats: seedChats,
            initialMode: initialMode,
        )
        picker.onSelect = { [weak self] chat, topic, draft in
            guard let self, TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == chatVM.client.id else { return }
            endMessageSelection()
            let destination = ChatLocation.current(
                chatID: chat.id,
                topic: topic.map { .messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId)) },
                client: chatVM.client,
            )
            if let replacingForwardID, destination != location, chatVM.pendingForward?.id == replacingForwardID {
                chatVM.pendingForward = nil
            }
            Self.openForward(
                draft,
                in: chat,
                topic: topic,
                destination: destination,
                navigationController: navigationController,
            )
        }
        let navigationController = TelegramNavigationController(rootViewController: picker)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    private func presentForwardRequestError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.betterTG("Chat.CantForward"),
            message: (error as? LocalizedError)?.errorDescription
                ?? L10n.betterTG("Chat.ForwardFailed"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    private func prepareSelectedMessagesForDeletion() {
        let sourceIDs = selectedSourceMessageIDs
        guard isSelectingMessages,
              !sourceIDs.isEmpty,
              selectionCapabilityTask == nil
        else { return }
        updateMessageSelectionChrome(isBusy: true)
        let client = chatVM.client
        let accountID = TDLib.shared.activeAccountID
        let generation = UUID()
        selectionCapabilityGeneration = generation
        selectionCapabilityTask = Task { [weak self] in
            guard let self else { return }
            var canDeleteForSelf = true
            var canDeleteForAll = true
            var resolvedMessages = [Message]()
            do {
                for messageID in sourceIDs {
                    try Task.checkCancellation()
                    let properties = try await client.getMessageProperties(
                        chatId: chatVM.chatID,
                        messageId: messageID,
                    )
                    let resolved = try await client.getMessage(chatId: chatVM.chatID, messageId: messageID)
                    resolvedMessages.append(resolved)
                    canDeleteForSelf = canDeleteForSelf && properties.canBeDeletedOnlyForSelf
                    canDeleteForAll = canDeleteForAll && properties.canBeDeletedForAllUsers
                }
                guard selectedSourceMessageIDs == sourceIDs,
                      selectionCapabilityGeneration == generation,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else {
                    throw MessageForwardingError.accountChanged
                }
                selectionCapabilityTask = nil
                selectionCapabilityGeneration = nil
                updateMessageSelectionChrome()
                // ChatControllerLoadDisplayNode deleteSelectedMessages: incoming messages of other members open
                // AdminUserActionsSheet for an admin, which deletes the whole selection for everyone.
                if canDeleteForAll, let request = adminDeleteRequest(for: resolvedMessages) {
                    AdminDeleteMessagesViewController.present(request, from: self) { [weak self] text in
                        self?.endMessageSelection()
                        self?.showChatToast(text)
                    }
                    return
                }
                presentDeleteSelectedConfirmation(
                    messageIDs: sourceIDs,
                    canDeleteForSelf: canDeleteForSelf,
                    canDeleteForAll: canDeleteForAll,
                    accountID: accountID,
                )
            } catch is CancellationError {
                guard selectionCapabilityGeneration == generation else { return }
                selectionCapabilityTask = nil
                selectionCapabilityGeneration = nil
                updateMessageSelectionChrome()
            } catch {
                guard selectionCapabilityGeneration == generation else { return }
                selectionCapabilityTask = nil
                selectionCapabilityGeneration = nil
                updateMessageSelectionChrome()
                let alert = UIAlertController(
                    title: L10n.betterTG("Chat.CantDelete"),
                    message: L10n.betterTG("Chat.DeleteCheckFailed"),
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func presentDeleteSelectedConfirmation(
        messageIDs: [Int64],
        canDeleteForSelf: Bool,
        canDeleteForAll: Bool,
        accountID: UUID?,
    ) {
        guard canDeleteForSelf || canDeleteForAll else {
            let alert = UIAlertController(
                title: L10n.betterTG("Chat.CantDelete"),
                message: L10n.betterTG("Chat.DeleteTogetherUnavailable"),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            present(alert, animated: true)
            return
        }
        let count = messageIDs.count
        let alert = UIAlertController(
            title: L10n.telegramPlural("Chat.DeleteMessagesConfirmation", count: count),
            message: nil,
            preferredStyle: .actionSheet,
        )
        if canDeleteForSelf {
            alert.addAction(UIAlertAction(
                title: L10n.telegram("Conversation.DeleteMessagesForMe"),
                style: .destructive,
            ) { [weak self] _ in
                self?.deleteSelectedMessages(messageIDs, forBoth: false, accountID: accountID)
            })
        }
        if canDeleteForAll {
            alert.addAction(UIAlertAction(
                title: L10n.telegram("Conversation.DeleteMessagesForEveryone"),
                style: .destructive,
            ) { [weak self] _ in
                self?.deleteSelectedMessages(messageIDs, forBoth: true, accountID: accountID)
            })
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = messageSelectionToolbar
            popover.sourceRect = messageSelectionToolbar.bounds
        }
        present(alert, animated: true)
    }

    private func deleteSelectedMessages(
        _ messageIDs: [Int64],
        forBoth: Bool,
        accountID: UUID?,
    ) {
        guard TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == chatVM.client.id
        else {
            endMessageSelection()
            return
        }
        chatVM.deleteMessages(ids: messageIDs, deleteForBoth: forBoth)
        endMessageSelection()
    }

    /// ChatMessageTextBubbleContentNode: Quote follows the ability to reply; copy protection removes only Copy and
    /// Share. Secret chats and self-destructing messages never offer it.
    /// `sourceMessageID` is the album file whose caption is quoted; nil, or the message's own ID, quotes its text.
    private func allowsQuoteSelection(in message: CustomMessage, sourceMessageID: Int64? = nil) -> Bool {
        if case .chatTypeSecret = chatVM.customChat.chat.type { return false }
        let source = sourceMessageID.flatMap { id in message.sourceMessages.first { $0.id == id } } ?? message.message
        return message.properties.canBeReplied && !chatVM.isReadOnlyTopic && message.message.selfDestructType == nil
            && formattedText(from: source.content)?.text.isEmpty == false
    }

    /// Copyable text is selectable in any chat, including channels the user only reads and closed topics.
    private func allowsCopySelection(in message: CustomMessage, sourceMessageID: Int64? = nil) -> Bool {
        let source = sourceMessageID.flatMap { id in message.sourceMessages.first { $0.id == id } } ?? message.message
        return message.properties.canBeCopied && formattedText(from: source.content)?.text.isEmpty == false
    }

    private func formattedText(from content: MessageContent) -> FormattedText? {
        switch content {
        case .messageText(let text):
            text.text.text.isEmpty ? nil : text.text
        case .messagePhoto(let photo):
            photo.caption.text.isEmpty ? nil : photo.caption
        case .messageVoiceNote(let voice):
            voice.caption.text.isEmpty ? nil : voice.caption
        case .messageAnimation(let animation):
            animation.caption.text.isEmpty ? nil : animation.caption
        case .messageAudio(let audio):
            audio.caption.text.isEmpty ? nil : audio.caption
        case .messageDocument(let document):
            document.caption.text.isEmpty ? nil : document.caption
        case .messageVideo(let video):
            video.caption.text.isEmpty ? nil : video.caption
        case .messagePoll(let poll):
            poll.description.text.isEmpty ? nil : poll.description
        default:
            nil
        }
    }

    private func copyableText(from content: MessageContent) -> FormattedText? {
        if case .messageRichMessage(let message) = content {
            let text = RichMessageText.copyText(message.message)
            return text.isEmpty ? nil : FormattedText(entities: [], text: text)
        }
        return formattedText(from: content)
    }

    /// Telegram's Stop Poll / Stop Quiz (ChatInterfaceStateContextMenus) and Stop Sharing for an outgoing live
    /// location, where TDLib's `canBeEdited` allows them.
    private func contentStopAction(for message: CustomMessage) -> TelegramContextMenuAction? {
        guard message.properties.canBeEdited else { return nil }
        switch message.message.content {
        case .messagePoll(let poll) where !poll.poll.isClosed:
            let isQuiz =
                if case .pollTypeQuiz = poll.poll.type {
                    true
                } else {
                    false
                }
            return TelegramContextMenuAction(
                title: L10n.telegram(isQuiz ? "Conversation.StopQuiz" : "Conversation.StopPoll"),
                image: UIImage(systemName: "stop.circle"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                confirmStopPoll(message, isQuiz: isQuiz)
            }
        case .messageLiveLocation(let live) where message.message.isOutgoing && live.expiresIn > 0:
            return TelegramContextMenuAction(
                title: L10n.telegram("Conversation.StopLiveLocation"),
                image: UIImage(systemName: "location.slash"),
            ) { [weak self, weak message] in
                guard let self, let message else { return }
                chatVM.stopLiveLocation(message)
            }
        default:
            return nil
        }
    }

    /// Telegram asks before closing a poll for good (requestStopPollInMessage).
    private func confirmStopPoll(_ message: CustomMessage, isQuiz: Bool) {
        let sheet = UIAlertController(
            title: nil,
            message: L10n.telegram(isQuiz
                ? "Conversation.StopQuizConfirmationTitle"
                : "Conversation.StopPollConfirmationTitle"),
            preferredStyle: .actionSheet,
        )
        sheet.addAction(UIAlertAction(
            title: L10n.telegram(isQuiz ? "Conversation.StopQuizConfirmation" : "Conversation.StopPollConfirmation"),
            style: .destructive,
        ) { [weak self, weak message] _ in
            guard let self, let message else { return }
            chatVM.stopPoll(message)
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }
}

private extension User {
    /// Telegram's EnginePeer.compactDisplayTitle for users: the first name, else the last name.
    var compactDisplayTitle: String {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return last.isEmpty ? L10n.telegram("User.DeletedAccount") : last
    }
}

// MARK: - MessageFileExportDelegate

/// Removes the temporary copy handed to Save to Files once the export picker closes.
private final class MessageFileExportDelegate: NSObject, UIDocumentPickerDelegate {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt _: [URL]) {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
