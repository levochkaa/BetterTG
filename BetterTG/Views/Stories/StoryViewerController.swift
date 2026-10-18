// StoryViewerController.swift

import AVFoundation
import Combine
import TDLibKit
import UIKit

// MARK: - StoryViewerController

/// Telegram's story viewer (StoryContainerScreen with StoryItemSetContainerComponent): a poster's stories full screen
/// under the progress strip and the poster's header, with the caption at the bottom. A tap on the left quarter goes
/// back and anywhere else forward; holding pauses and hides the interface; dragging down closes the viewer and dragging
/// sideways turns Telegram's cube to the neighbouring poster, whose face shows its story as the cube turns. A photo
/// shows for five seconds and a video for its duration, then the next story opens, across posters, and the viewer
/// closes after the last one. The story's areas draw their reactions and weather, and a tap on a location, message or
/// link area offers to open it. Someone else's story has Telegram's More menu beside the close button, and under a
/// user's or group's story Telegram's reply panel: a private reply or comment, a reaction sent as a message while the
/// field is empty, the like button that holds another reaction, and the share button.
final class StoryViewerController: UIViewController, UIGestureRecognizerDelegate {
    enum Subject {
        /// One story, as a shared story or a story mention opens it (SingleStoryContentContextImpl).
        case story(chatID: Int64, storyID: Int)
        /// Posters' active stories, opened at one poster and paging through the others in order.
        case activeStories(chatIDs: [Int64], initialChatID: Int64)
    }

    private enum PanAxis {
        case dismissal
        case poster
    }

    /// What the reactions above the reply panel do.
    private enum ReplyReactionsMode {
        /// The empty field edits: a reaction goes to the poster as a message replying to the story.
        case message
        /// The like button is held: the reaction picked becomes the story's.
        case like
    }

    private static let contentCornerRadius = StoryChromeLayout.cornerRadius
    /// The newest open request; an older one finishing later is dropped.
    private static var openRequest: UUID?

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    private let session: StoryViewerSession
    private var state: StoryViewerState
    private let followsActiveStories: Bool
    private let sourceIsAvatar: Bool
    private weak var sourceView: UIView?

    private let backdropView = UIView()
    private let containerView = UIView()
    /// The cube's faces: the shown poster's in front, its neighbours' beside it while a drag or a turn shows them.
    private let focusedFace = StoryCubeFaceView()
    private let previousFace = StoryCubeFaceView()
    private let nextFace = StoryCubeFaceView()
    private let previousPreview = StoryCubePreviewView()
    private let nextPreview = StoryCubePreviewView()
    private let contentView = UIView()
    private let imageView = TDImageLoadingView()
    private let playerSurface = LocalVideoSurfaceView()
    private let player = LocalMediaPlayer()
    private let areaOverlay = StoryAreaOverlayView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()
    private let topShade = StoryShadeView(fromTop: true)
    private let bottomShade = StoryShadeView(fromTop: false)
    private let chromeView = UIView()
    private let progressStrip = StoryProgressStripView()
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let captionView = UITextView()
    private let replyPanel = StoryReplyPanelView()
    /// Telegram dims the story to black at 0.8 while the reply field edits; it also takes the tap that closes the
    /// reactions over the story.
    private let replyDimView = UIView()
    private let replyReactions = TelegramReactionStripView()

    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    private lazy var holdGesture = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))

    private var displayLink: CADisplayLink?
    private var lastTickTime: CFTimeInterval?
    private var mediaTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var neighborTask: Task<Void, Never>?
    private var headerTask: Task<Void, Never>?
    private var areaMessageTask: Task<Void, Never>?
    private var moreTask: Task<Void, Never>?
    private var menuActionTask: Task<Void, Never>?
    private var replyPosterTask: Task<Void, Never>?
    private var replyReactionsTask: Task<Void, Never>?
    /// The reply panel's posters, each resolved once while the viewer is open.
    private var replyPosters = [Int64: StoryReplyPanel.Poster]()
    /// The story the panel shows, so an update to it animates the like button and a new poster's story clears it.
    private var replyPanelKey: StoryViewerSession.StoryKey?
    /// getStoryAvailableReactions with the custom emoji among them, loaded once.
    private var storyReactions: (types: [ReactionType], stickers: [Int64: Sticker])?
    private var replyReactionsMode: ReplyReactionsMode?
    /// How far the keyboard covers the viewer.
    private var keyboardOverlap = CGFloat(0)
    /// Story replies sent from the viewer, by the id sendMessage returned, under the id TDLib sent them with.
    private var sentReplyIDs = [Int64: Int64]()
    private var areaTooltip: StoryAreaTooltipView?
    /// The area whose tooltip is up, or was just dismissed: a second tap on a message area opens the message.
    private var selectedArea: (key: StoryViewerSession.StoryKey, index: Int)?
    private var mediaGeneration = UUID()
    private var shownKey: StoryViewerSession.StoryKey?
    private var shownStory: Story?
    private var showsVideo = false
    private var isCaptionExpanded = false
    private var captionIsTruncated = false
    private var isChromeHidden = false
    private var dragChromeAlpha = CGFloat(1)
    private var panAxis: PanAxis?
    /// Telegram's itemSetPanState.fraction: positive while the cube turns towards the next poster.
    private var cubeFraction = CGFloat(0)
    /// The running turn back to rest, from the fraction it started at.
    private var cubeTurn: (from: CGFloat, start: CFTimeInterval)?
    private var isClosing = false
    private var didAppear = false
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
        /// The UI probe's poster for the More menu, and where its choices, a chat picked to share to among them, go
        /// instead of TDLib.
        private var probeMenuPoster: StoryMoreMenu.Poster?
        private var probeMenuActionHandler: ((String) -> Void)?
        /// The UI probe's poster for the reply panel; its likes, replies and reactions go to the menu's handler.
        private var probeReplyPoster: StoryReplyPanel.Poster?
    #endif

    /// Whether the shown video should play: every pause but buffering stops it.
    private var shouldPlay: Bool {
        !isClosing && state.pauseReasons.subtracting([.buffering]).isEmpty
    }

    /// The side faces take part while a poster drag or a turn runs.
    private var isCubeActive: Bool {
        panAxis == .poster || cubeTurn != nil
    }

    /// Toasts rise above the reply panel's resting place while it shows; the keyboard closes as one appears.
    private var toastBottomInset: CGFloat {
        guard !replyPanel.isHidden else { return 8 }
        let insets = view.safeAreaInsets
        return max(8, Self.panelBottomInset(insets) - insets.bottom + StoryReplyPanelView.height + 8)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(
        session: StoryViewerSession,
        state: StoryViewerState,
        followsActiveStories: Bool,
        sourceView: UIView?,
        sourceIsAvatar: Bool,
    ) {
        self.session = session
        self.state = state
        self.followsActiveStories = followsActiveStories
        self.sourceView = sourceView
        self.sourceIsAvatar = sourceIsAvatar
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // Telegram's story screens, menus and sheets use its dark theme.
        overrideUserInterfaceStyle = .dark
        view.accessibilityViewIsModal = true
        configureViews()
        configureGestures()
        bindSession()
        bindPlayer()
        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.setPaused(true, for: .inactive) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.setPaused(false, for: .inactive) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .sink { [weak self] in self?.keyboardWillChangeFrame($0, hides: false) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] in self?.keyboardWillChangeFrame($0, hides: true) }
            .store(in: &cancellables)
        nc.scopedPublisher(&cancellables, for: .updateMessageSendSucceeded) { [weak self] event in
            guard let self, event.source.clientID == session.client.id,
                  sentReplyIDs[event.value.oldMessageId] != nil else { return }
            sentReplyIDs[event.value.oldMessageId] = event.value.message.id
        }
        showCurrentStory()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !didAppear else { return }
        view.layoutIfNeeded()
        backdropView.alpha = 0
        containerView.alpha = 0
        if let target = sourceFrame() {
            containerView.transform = containerTransform(matching: target)
            contentView.layer.cornerRadius = sourceIsAvatar
                ? contentView.bounds.width / 2
                : Self.contentCornerRadius
        } else {
            containerView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAppear else { return }
        didAppear = true
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.35,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.backdropView.alpha = 1
            self.containerView.alpha = 1
            self.containerView.transform = .identity
            self.contentView.layer.cornerRadius = Self.contentCornerRadius
        }
        startClock()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { tearDown() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        backdropView.frame = bounds
        containerView.bounds = CGRect(origin: .zero, size: bounds.size)
        containerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        for face in [previousFace, focusedFace, nextFace] {
            face.bounds = containerView.bounds
            face.center = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY)
        }
        // Telegram's 9:16 story under the status bar, above the reply panel's place (bottomContentInset), narrowed
        // when the screen is too short for it.
        let insets = view.safeAreaInsets
        let availableHeight = max(
            1,
            bounds.height - insets.top - Self.panelBottomInset(insets) - StoryReplyPanelView.height,
        )
        var size = CGSize(width: bounds.width, height: (bounds.width * 16 / 9).rounded())
        if size.height > availableHeight {
            size = CGSize(width: (availableHeight * 9 / 16).rounded(), height: availableHeight)
        }
        contentView.frame = CGRect(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: insets.top,
            width: size.width,
            height: size.height,
        )
        previousFace.layoutContent(frame: contentView.frame)
        nextFace.layoutContent(frame: contentView.frame)
        layoutContent()
        layoutReplyPanel()
        layoutCube()
    }

    // MARK: Presentation

    /// Opens the viewer over `presenter` once the story or the first poster's stories load, as Telegram waits for
    /// its story content before presenting. `onUnavailable` runs when TDLib can't return them.
    static func present(
        _ subject: Subject,
        client: TDLibClient,
        from presenter: UIViewController,
        sourceView: UIView?,
        sourceIsAvatar: Bool = false,
        onUnavailable: (() -> Void)? = nil,
    ) {
        guard let session = StoryViewerSession(client: client) else { return }
        let request = UUID()
        openRequest = request
        Task { @MainActor [weak presenter, weak sourceView] in
            let state: StoryViewerState?
            let followsActiveStories: Bool
            switch subject {
            case .story(let chatID, let storyID):
                followsActiveStories = false
                let story = await session.story(.init(chatID: chatID, storyID: storyID))
                state = story == nil
                    ? nil
                    : StoryViewerState(posters: [.init(chatID: chatID, storyIDs: [storyID])], initialChatID: chatID)
            case .activeStories(let chatIDs, let initialChatID):
                followsActiveStories = true
                let active = await session.activeStories(chatID: initialChatID)
                var seen = Set<Int64>()
                let order = (chatIDs.contains(initialChatID) ? chatIDs : [initialChatID] + chatIDs)
                    .filter { seen.insert($0).inserted }
                let storyIDs = active?.stories.map(\.storyId) ?? []
                state = storyIDs.isEmpty
                    ? nil
                    : StoryViewerState(
                        posters: order.map { chatID -> StoryViewerState.Poster in
                            chatID == initialChatID
                                ? StoryViewerState.Poster(
                                    chatID: chatID,
                                    storyIDs: storyIDs,
                                    maxReadStoryID: active?.maxReadStoryId ?? 0,
                                )
                                : StoryViewerState.Poster(chatID: chatID)
                        },
                        initialChatID: initialChatID,
                    )
            }
            guard openRequest == request else {
                session.invalidate()
                return
            }
            openRequest = nil
            guard let state else {
                let isCurrent = session.isCurrent
                session.invalidate()
                if isCurrent { onUnavailable?() }
                return
            }
            guard let presenter, session.isCurrent, presenter.view.window != nil,
                  presenter.presentedViewController == nil
            else {
                session.invalidate()
                return
            }
            let viewer = StoryViewerController(
                session: session,
                state: state,
                followsActiveStories: followsActiveStories,
                sourceView: sourceView,
                sourceIsAvatar: sourceIsAvatar,
            )
            presenter.present(viewer, animated: false)
        }
    }

    // MARK: Reply panel

    /// The reply panel's bottom inset: Telegram's safe area plus a point, where the screen has one.
    private static func panelBottomInset(_ insets: UIEdgeInsets) -> CGFloat {
        insets.bottom > 0 ? insets.bottom + 1 : 0
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !(touch.view is UIControl), !isClosing else { return false }
        // The reply panel, the reactions above it and the dimmed story under the keyboard keep their touches.
        guard let touched = touch.view else { return true }
        return ![replyPanel, replyReactions, replyDimView].contains { touched.isDescendant(of: $0) }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return true }
        if captionView.isScrollEnabled, captionView.bounds.contains(panGesture.location(in: captionView)) {
            return false
        }
        let velocity = panGesture.velocity(in: view)
        if abs(velocity.y) > abs(velocity.x) { return velocity.y > 0 }
        // Telegram's horizontal pan runs with a single poster too: it bands at the ends, and a flick there closes.
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        // Holding a story and then dragging it down closes it, as in Telegram.
        Set([ObjectIdentifier(gestureRecognizer), ObjectIdentifier(otherGestureRecognizer)])
            == Set([ObjectIdentifier(holdGesture), ObjectIdentifier(panGesture)])
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let interval = lastTickTime.map { link.timestamp - $0 } ?? 0
        lastTickTime = link.timestamp
        stepCubeTurn()
        guard !isClosing else { return }
        let isCovered = presentedViewController != nil
        if isCovered != state.pauseReasons.contains(.presentation) { setPaused(isCovered, for: .presentation) }
        if showsVideo {
            if state.duration != nil, player.hasItem { state.setElapsed(player.currentTime) }
        } else {
            let transition = state.advance(by: min(interval, 0.25))
            if transition != .none {
                apply(transition)
                return
            }
        }
        progressStrip.setProgress(CGFloat(state.progress))
    }

    // MARK: Views

    private func configureViews() {
        backdropView.backgroundColor = .black
        view.addSubview(backdropView)
        view.addSubview(containerView)
        for face in [previousFace, nextFace] {
            face.isUserInteractionEnabled = false
            face.isHidden = true
            containerView.addSubview(face)
        }
        containerView.addSubview(focusedFace)

        contentView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = Self.contentCornerRadius
        contentView.layer.cornerCurve = .continuous
        focusedFace.contentHost.addSubview(contentView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: L10n.betterTG("Accessibility.NextStory")) { [weak self] _ in
                guard let self else { return false }
                apply(state.next())
                return true
            },
            UIAccessibilityCustomAction(name: L10n.betterTG("Accessibility.PreviousStory")) { [weak self] _ in
                guard let self else { return false }
                apply(state.previous())
                return true
            },
        ]
        contentView.addSubview(imageView)

        playerSurface.playerLayer.videoGravity = .resizeAspectFill
        playerSurface.isUserInteractionEnabled = false
        playerSurface.isHidden = true
        contentView.addSubview(playerSurface)

        contentView.addSubview(areaOverlay)

        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        contentView.addSubview(loadingIndicator)

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        contentView.addSubview(messageLabel)

        contentView.addSubview(topShade)
        contentView.addSubview(bottomShade)

        contentView.addSubview(chromeView)
        chromeView.addSubview(progressStrip)

        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        avatarView.isAccessibilityElement = false
        avatarView.layer.cornerRadius = 16
        avatarView.clipsToBounds = true
        chromeView.addSubview(avatarView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .white
        chromeView.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        chromeView.addSubview(subtitleLabel)

        moreButton.tintColor = .white
        moreButton.setImage(StoryChromeLayout.moreImage, for: .normal)
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.isHidden = true
        moreButton.addTarget(self, action: #selector(morePressed), for: .touchUpInside)
        chromeView.addSubview(moreButton)

        closeButton.tintColor = .white
        closeButton.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
            ),
            for: .normal,
        )
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        chromeView.addSubview(closeButton)

        captionView.backgroundColor = .clear
        captionView.isEditable = false
        captionView.isSelectable = false
        captionView.isScrollEnabled = false
        captionView.showsVerticalScrollIndicator = false
        captionView.textContainerInset = .zero
        captionView.textContainer.lineFragmentPadding = 0
        captionView.textContainer.lineBreakMode = .byTruncatingTail
        captionView.isAccessibilityElement = false
        captionView.isHidden = true
        chromeView.addSubview(captionView)

        configureReplyPanel()
    }

    private func layoutContent() {
        let bounds = contentView.bounds
        imageView.frame = bounds
        playerSurface.frame = bounds
        areaOverlay.frame = bounds
        loadingIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let messageSize = messageLabel.sizeThatFits(CGSize(width: bounds.width - 48, height: bounds.height))
        messageLabel.frame = CGRect(
            x: 24,
            y: ((bounds.height - messageSize.height) / 2).rounded(),
            width: bounds.width - 48,
            height: messageSize.height,
        )
        chromeView.frame = bounds
        topShade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 96)
        // MediaNavigationStripComponent sits 8 pt from the story's top and sides.
        progressStrip.frame = StoryChromeLayout.progressFrame(in: bounds)
        avatarView.frame = StoryChromeLayout.avatarFrame
        closeButton.frame = StoryChromeLayout.closeFrame(in: bounds)
        moreButton.frame = StoryChromeLayout.moreFrame(in: bounds)
        let textFrames = StoryChromeLayout.textFrames(
            in: bounds,
            trailingLimit: StoryChromeLayout.textTrailingLimit(in: bounds, showsMore: !moreButton.isHidden),
        )
        titleLabel.frame = textFrames.title
        subtitleLabel.frame = textFrames.subtitle
        layoutCaption()
    }

    /// Telegram's caption (StoryContentCaptionComponent): three lines at the bottom, the whole text once expanded.
    private func layoutCaption() {
        let bounds = contentView.bounds
        guard let text = captionView.attributedText, text.length > 0 else {
            captionView.isHidden = true
            bottomShade.isHidden = true
            captionIsTruncated = false
            return
        }
        let width = max(1, bounds.width - 32)
        let fullHeight = ceil(text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil,
        )
        .height)
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let collapsedHeight = min(fullHeight, ceil((font?.lineHeight ?? 20) * 3))
        let expandedLimit = (bounds.height * 0.6).rounded()
        captionIsTruncated = fullHeight > collapsedHeight + 1
        let height = isCaptionExpanded ? min(fullHeight, expandedLimit) : collapsedHeight
        captionView.textContainer.maximumNumberOfLines = isCaptionExpanded ? 0 : 3
        captionView.isScrollEnabled = isCaptionExpanded && fullHeight > expandedLimit
        captionView.isUserInteractionEnabled = captionView.isScrollEnabled
        captionView.frame = CGRect(x: 16, y: bounds.height - 16 - height, width: width, height: height)
        captionView.isHidden = false
        let shadeTop = max(0, captionView.frame.minY - (isCaptionExpanded ? 160 : 64))
        bottomShade.frame = CGRect(x: 0, y: shadeTop, width: bounds.width, height: bounds.height - shadeTop)
        bottomShade.isHidden = false
    }

    private func configureGestures() {
        holdGesture.minimumPressDuration = 0.2
        holdGesture.delegate = self
        tapGesture.delegate = self
        tapGesture.require(toFail: holdGesture)
        panGesture.delegate = self
        containerView.addGestureRecognizer(tapGesture)
        containerView.addGestureRecognizer(holdGesture)
        containerView.addGestureRecognizer(panGesture)
    }

    // MARK: Showing stories

    private func showCurrentStory() {
        resetMedia()
        let chatID = state.currentChatID
        if replyPanelKey?.chatID != chatID { applyReplyPanel(nil, key: nil) }
        progressStrip.configure(count: state.storyCount, index: state.storyIndex)
        renderPoster(chatID)
        refreshNeighborFaces()
        preloadNeighbors()
        guard let storyID = state.currentStoryID else {
            loadingIndicator.startAnimating()
            loadActiveStories(of: chatID)
            return
        }
        let key = StoryViewerSession.StoryKey(chatID: chatID, storyID: storyID)
        if let story = session.cachedStory(key) {
            render(story, key: key)
            return
        }
        loadingIndicator.startAnimating()
        let generation = mediaGeneration
        mediaTask = Task { [weak self] in
            guard let self else { return }
            let story = await session.story(key)
            guard !Task.isCancelled, mediaGeneration == generation, !isClosing else { return }
            if let story {
                render(story, key: key)
            } else {
                apply(state.removeStory(chatID: key.chatID, storyID: key.storyID))
            }
        }
    }

    private func loadActiveStories(of chatID: Int64) {
        let generation = mediaGeneration
        mediaTask = Task { [weak self] in
            guard let self else { return }
            let active = await session.activeStories(chatID: chatID)
            guard !Task.isCancelled, mediaGeneration == generation, !isClosing else { return }
            apply(state.updateStories(
                chatID: chatID,
                storyIDs: active?.stories.map(\.storyId) ?? [],
                maxReadStoryID: active?.maxReadStoryId ?? 0,
            ))
        }
    }

    private func resetMedia() {
        mediaGeneration = UUID()
        mediaTask?.cancel()
        mediaTask = nil
        areaTooltip?.dismiss()
        areaOverlay.update(areas: [], client: session.client, loadsStickers: false)
        if let moreTask {
            // The menu was still loading for the story that leaves.
            moreTask.cancel()
            self.moreTask = nil
            state.setPaused(false, for: .moreMenu)
        }
        moreButton.isHidden = true
        hideReplyReactions()
        if replyPanel.isEditing { replyPanel.endEditing() }
        session.closeOpenedStory()
        imageView.onFullImage = nil
        imageView.cancel()
        imageView.image = nil
        player.stop()
        playerSurface.isHidden = true
        showsVideo = false
        shownKey = nil
        shownStory = nil
        messageLabel.isHidden = true
        loadingIndicator.stopAnimating()
        subtitleLabel.text = nil
        captionView.attributedText = nil
        if isCaptionExpanded {
            isCaptionExpanded = false
            state.setPaused(false, for: .caption)
        }
        imageView.accessibilityLabel = titleLabel.text
        view.setNeedsLayout()
    }

    private func renderPoster(_ chatID: Int64) {
        headerTask?.cancel()
        if let chat = session.cachedChat(chatID) {
            configureHeader(chat)
            return
        }
        titleLabel.text = nil
        avatarView.prepareForReuse()
        headerTask = Task { [weak self] in
            guard let self, let chat = await session.chat(chatID), !Task.isCancelled,
                  state.currentChatID == chatID else { return }
            configureHeader(chat)
        }
    }

    private func configureHeader(_ chat: Chat) {
        titleLabel.text = chat.title
        avatarView.configure(
            file: chat.photo?.small,
            minithumbnail: chat.photo?.minithumbnail,
            placeholder: TelegramAvatarPlaceholder(
                peerID: chat.id,
                accentColorID: chat.accentColorId,
                upgradedGiftColors: chat.upgradedGiftColors,
                letters: chat.title.telegramAvatarFirstLetter.map { [$0] } ?? [],
                isDeleted: false,
            ),
            client: session.client,
        )
        updateAccessibilityLabel()
    }

    private func render(_ story: Story, key: StoryViewerSession.StoryKey) {
        guard key.chatID == state.currentChatID, key.storyID == state.currentStoryID else { return }
        shownKey = key
        shownStory = story
        renderDetails(story)
        let origin = TDImageOrigin.captured(client: session.client)
        switch story.content {
        case .storyContentPhoto(let content):
            guard let file = StoryMedia.photoFile(content.photo) else {
                showMessage(L10n.betterTG("Story.Unsupported"), key: key)
                break
            }
            loadingIndicator.startAnimating()
            session.prioritizeDownload(of: file)
            imageView.onFullImage = { [weak self] in
                self?.mediaDidBecomeReady(duration: StoryViewerState.photoDuration, key: key)
            }
            imageView.load(
                file: file,
                placeholderData: content.photo.minithumbnail?.data,
                maximumPixelSize: 2560,
                origin: origin,
            )
        case .storyContentVideo(let content):
            startVideo(content.video, origin: origin)
        case .storyContentLive, .storyContentUnsupported:
            showMessage(L10n.betterTG("Story.Unsupported"), key: key)
        }
        preloadUpcoming()
    }

    /// The header's time and edited mark (StoryAuthorInfoComponent) and the caption with its entities.
    private func renderDetails(_ story: Story) {
        var subtitle = StoryTimestamp.string(date: story.date)
        if story.isEdited { subtitle += " • " + L10n.telegram("Story.HeaderEdited") }
        subtitleLabel.text = subtitle
        let caption = story.caption
        captionView.attributedText = caption.text.isEmpty
            ? nil
            : NSAttributedString(getAttributedString(from: caption, .white))
        areaOverlay.update(areas: story.areas, client: session.client, loadsStickers: !session.isOffline)
        moreButton.isHidden = !StoryMoreMenu.showsButton(for: story)
        renderReplyPanel(story)
        updateAccessibilityLabel()
        view.setNeedsLayout()
    }

    private func updateAccessibilityLabel() {
        imageView.accessibilityLabel = [titleLabel.text, subtitleLabel.text, shownStory?.caption.text]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
    }

    /// Live streams and story kinds BetterTG can't show get a notice for a photo's duration.
    private func showMessage(_ text: String, key: StoryViewerSession.StoryKey) {
        loadingIndicator.stopAnimating()
        messageLabel.text = text
        messageLabel.isHidden = false
        view.setNeedsLayout()
        mediaDidBecomeReady(duration: StoryViewerState.photoDuration, key: key)
    }

    private func mediaDidBecomeReady(duration: TimeInterval, key: StoryViewerSession.StoryKey) {
        guard shownKey == key, state.duration == nil, !isClosing else { return }
        loadingIndicator.stopAnimating()
        state.mediaDidBecomeReady(duration: duration)
        session.open(key)
    }

    // MARK: Video

    private func bindPlayer() {
        player.attach(to: playerSurface.playerLayer)
        player.setMuted(false)
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.playerStateChanged(state) }
            .store(in: &cancellables)
        playerSurface.playerLayer
            .publisher(for: \.isReadyForDisplay, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                guard let self else { return }
                playerSurface.isHidden = !(isReady && showsVideo)
            }
            .store(in: &cancellables)
    }

    /// A video streams through the gallery's TDLib range loader, or plays from disk once downloaded.
    private func startVideo(_ video: StoryVideo, origin: TDImageOrigin?) {
        showsVideo = true
        loadingIndicator.startAnimating()
        if let thumbnail = video.thumbnail {
            imageView.load(
                file: thumbnail.file,
                placeholderData: video.minithumbnail?.data,
                maximumPixelSize: 1280,
                origin: origin,
            )
        } else {
            imageView.loadPlaceholder(data: video.minithumbnail?.data, maximumPixelSize: 1280, origin: origin)
        }
        // A story's sound takes over from a voice note or round video, as the gallery's videos do.
        if !Media.shared.savedMediaPath.isEmpty { Media.shared.stop() }
        VideoNotePlaybackView.pauseActivePlayback()
        let file = video.video
        if file.local.isDownloadingCompleted, !file.local.path.isEmpty {
            player.load(url: URL(filePath: file.local.path), autoplay: shouldPlay)
            return
        }
        let generation = mediaGeneration
        let ranges = session.vodRanges
        mediaTask = Task { [weak self] in
            let lease = await ranges.acquire(file: file)
            guard let self, !Task.isCancelled, mediaGeneration == generation, session.isCurrent, !isClosing else {
                await lease.invalidate()
                return
            }
            guard let vodSession = TDLibVODResourceLoaderSession(
                lease: lease,
                mimeType: "video/mp4",
                fileName: "story.mp4",
            ) else {
                await lease.invalidate()
                playDownloadedVideo(file, generation: generation)
                return
            }
            player.load(vodSession: vodSession, autoplay: shouldPlay)
        }
    }

    private func playDownloadedVideo(_ file: File, generation: UUID) {
        let client = session.client
        mediaTask = Task { [weak self] in
            let downloaded = try? await client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            )
            guard let self, !Task.isCancelled, mediaGeneration == generation, session.isCurrent, !isClosing,
                  let downloaded, downloaded.local.isDownloadingCompleted, !downloaded.local.path.isEmpty
            else { return }
            player.load(url: URL(filePath: downloaded.local.path), autoplay: shouldPlay)
        }
    }

    private func playerStateChanged(_ playerState: LocalMediaPlayer.State) {
        guard showsVideo, let key = shownKey, !isClosing else { return }
        switch playerState {
        case .playing:
            loadingIndicator.stopAnimating()
            state.setPaused(false, for: .buffering)
            if state.duration == nil {
                let storyDuration: TimeInterval =
                    if case .storyContentVideo(let content) = shownStory?.content {
                        content.video.duration
                    } else {
                        0
                    }
                mediaDidBecomeReady(duration: storyDuration > 0 ? storyDuration : player.duration, key: key)
            }
        case .buffering, .preparing:
            guard state.duration != nil else { return }
            state.setPaused(true, for: .buffering)
            loadingIndicator.startAnimating()
        case .ended:
            state.setElapsed(state.duration ?? 0)
            apply(state.next())
        case .failed:
            showsVideo = false
            playerSurface.isHidden = true
            if state.duration == nil {
                showMessage(L10n.betterTG("Story.PlaybackFailed"), key: key)
            }
        case .idle, .paused:
            break
        }
    }

    private func updatePlayback() {
        guard showsVideo, player.hasItem else { return }
        if shouldPlay, !player.isPlaybackRequested {
            player.play()
        } else if !shouldPlay, player.isPlaybackRequested {
            player.pause()
        }
    }

    // MARK: Preloading

    /// The next story's details and media, or the next poster's story list (StoryContentContextImpl preloads both).
    private func preloadUpcoming() {
        preloadTask?.cancel()
        guard let upcoming = state.upcoming else { return }
        preloadTask = Task { [weak self] in
            guard let self else { return }
            _ = await session.chat(upcoming.chatID)
            if let storyID = upcoming.storyID {
                guard let story = await session.story(.init(chatID: upcoming.chatID, storyID: storyID)),
                      !Task.isCancelled else { return }
                session.preloadMedia(of: story)
            } else if let active = await session.activeStories(chatID: upcoming.chatID), !Task.isCancelled,
                      !isClosing
            {
                apply(state.updateStories(
                    chatID: upcoming.chatID,
                    storyIDs: active.stories.map(\.storyId),
                    maxReadStoryID: active.maxReadStoryId,
                ))
            }
        }
    }

    /// The neighbouring posters' headers, story lists and shown stories, so their cube faces are ready before a drag
    /// (StoryContainerScreen keeps the sets beside the focused one mounted).
    private func preloadNeighbors() {
        neighborTask?.cancel()
        neighborTask = Task { [weak self] in
            for forward in [true, false] {
                guard let self, !Task.isCancelled, !isClosing,
                      let neighbor = state.neighbor(forward: forward) else { continue }
                _ = await session.chat(neighbor.chatID)
                if neighbor.storyID == nil, let active = await session.activeStories(chatID: neighbor.chatID),
                   !Task.isCancelled, !isClosing
                {
                    apply(state.updateStories(
                        chatID: neighbor.chatID,
                        storyIDs: active.stories.map(\.storyId),
                        maxReadStoryID: active.maxReadStoryId,
                    ))
                }
                guard !Task.isCancelled, !isClosing else { return }
                if let loaded = state.neighbor(forward: forward), loaded.chatID == neighbor.chatID,
                   let storyID = loaded.storyID,
                   let story = await session.story(.init(chatID: loaded.chatID, storyID: storyID)),
                   !Task.isCancelled
                {
                    session.preloadMedia(of: story)
                }
                refreshNeighborFaces()
            }
        }
    }

    // MARK: TDLib

    private func bindSession() {
        session.onStoryChanged = { [weak self] story in
            guard let self, shownKey == .init(chatID: story.posterChatId, storyID: story.id) else { return }
            shownStory = story
            renderDetails(story)
        }
        session.onStoryDeleted = { [weak self] key in
            guard let self, !isClosing else { return }
            apply(state.removeStory(chatID: key.chatID, storyID: key.storyID))
        }
        session.onActiveStoriesChanged = { [weak self] active in
            guard let self, followsActiveStories, !isClosing else { return }
            apply(state.updateStories(
                chatID: active.chatId,
                storyIDs: active.stories.map(\.storyId),
                maxReadStoryID: active.maxReadStoryId,
            ))
        }
        session.onRetired = { [weak self] in
            self?.close()
        }
    }

    // MARK: Clock

    private func startClock() {
        guard displayLink == nil, !isClosing else { return }
        let link = CADisplayLink(
            target: StoryViewerDisplayLinkTarget(self),
            selector: #selector(StoryViewerDisplayLinkTarget.tick(_:)),
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTickTime = nil
    }

    private func stopClock() {
        displayLink?.invalidate()
        displayLink = nil
        lastTickTime = nil
    }

    // MARK: Navigation

    private func apply(_ transition: StoryViewerState.Transition) {
        switch transition {
        case .none:
            break
        case .story:
            showCurrentStory()
        case .poster(let forward):
            turnCube(forward: forward)
        case .rewind:
            if showsVideo, player.hasItem { player.seek(to: 0) }
            progressStrip.setProgress(0)
        case .dismiss:
            close()
        }
    }

    private func setPaused(_ isPaused: Bool, for reason: StoryViewerState.PauseReason) {
        state.setPaused(isPaused, for: reason)
        updatePlayback()
    }

    private func setChromeHidden(_ hidden: Bool) {
        isChromeHidden = hidden
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.updateChromeAlpha()
        }
    }

    private func updateChromeAlpha() {
        let alpha = isChromeHidden ? 0 : dragChromeAlpha
        chromeView.alpha = alpha
        topShade.alpha = alpha
        bottomShade.alpha = alpha
        replyPanel.alpha = alpha
    }

    private func setCaptionExpanded(_ expanded: Bool) {
        guard expanded != isCaptionExpanded else { return }
        isCaptionExpanded = expanded
        setPaused(expanded, for: .caption)
        captionView.setContentOffset(.zero, animated: false)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.layoutCaption()
        }
    }

    @objc private func closePressed() {
        close()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard !isClosing else { return }
        if isCaptionExpanded {
            setCaptionExpanded(false)
            return
        }
        if !captionView.isHidden, captionIsTruncated,
           captionView.bounds.insetBy(dx: 0, dy: -8).contains(gesture.location(in: captionView))
        {
            setCaptionExpanded(true)
            return
        }
        handleStoryTap(at: gesture.location(in: contentView))
    }

    /// StoryItemSetContainerComponent.tapGesture: a suggested reaction or another area under the finger takes the tap,
    /// otherwise the left quarter goes back and the rest forward.
    private func handleStoryTap(at point: CGPoint) {
        if let story = shownStory,
           let reaction = StoryAreaGeometry.reaction(at: point, in: contentView.bounds.size, areas: story.areas)
        {
            activateInlineReaction(reaction, on: story)
            return
        }
        if let areas = shownStory?.areas,
           let index = StoryAreaGeometry.area(at: point, in: contentView.bounds.size, areas: areas)
        {
            activateArea(at: index, point: point)
            return
        }
        apply(point.x < contentView.bounds.width * 0.25 ? state.previous() : state.next())
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            setPaused(true, for: .hold)
            setChromeHidden(true)
        case .cancelled, .ended, .failed:
            setPaused(false, for: .hold)
            setChromeHidden(false)
        default:
            break
        }
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        switch gesture.state {
        case .began:
            panAxis = abs(velocity.y) > abs(velocity.x) ? .dismissal : .poster
            areaTooltip?.dismiss()
            if panAxis == .poster { beginPosterPan() }
            setPaused(true, for: .drag)
        case .changed:
            switch panAxis {
            case .dismissal: updateDismissalDrag(translation.y)
            case .poster: updatePosterPan(translation.x)
            case nil: break
            }
        case .cancelled, .ended, .failed:
            let axis = panAxis
            panAxis = nil
            let ended = gesture.state == .ended
            switch axis {
            case .dismissal:
                if ended, translation.y > 100 || velocity.y > 900 {
                    close()
                } else {
                    cancelDrag()
                }
            case .poster:
                finishPosterPan(velocity: velocity.x)
            case nil:
                setPaused(false, for: .drag)
            }
        default:
            break
        }
    }

    /// The story follows the finger down while the chat behind shows through, like the gallery's dismissal drag.
    private func updateDismissalDrag(_ offset: CGFloat) {
        let y = offset > 0 ? offset : offset * 0.2
        let fraction = min(1, max(0, y) / max(1, view.bounds.height))
        let scale = 1 - fraction * 0.2
        containerView.transform = CGAffineTransform(translationX: 0, y: y).scaledBy(x: scale, y: scale)
        backdropView.alpha = 1 - min(0.9, max(0, y) / 300)
        dragChromeAlpha = 1 - min(1, max(0, y) / 50)
        updateChromeAlpha()
    }

    private func cancelDrag() {
        dragChromeAlpha = 1
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.containerView.transform = .identity
            self.backdropView.alpha = 1
            self.updateChromeAlpha()
        } completion: { [weak self] _ in
            self?.setPaused(false, for: .drag)
        }
    }

    // MARK: Areas

    /// StoryItemSetContainerViewSendMessage.activateMediaArea: a location or venue offers View Location, a message
    /// View Message under the finger (a second tap on it opens the message), and a link Open Link with its address.
    /// Weather takes the tap without a tooltip.
    private func activateArea(at index: Int, point: CGPoint) {
        guard let key = shownKey, let areas = shownStory?.areas, areas.indices.contains(index) else { return }
        let area = areas[index]
        let title: String
        var subtitle: String?
        var anchorsAtTap = false
        let action: () -> Void
        switch area.type {
        case .storyAreaTypeLocation(let location):
            title = L10n.telegram("Story.ViewLocation")
            action = { [weak self] in self?.openLocation(LocationViewSubject(location: location.location)) }
        case .storyAreaTypeVenue(let venue):
            title = L10n.telegram("Story.ViewLocation")
            action = { [weak self] in self?.openLocation(LocationViewSubject(venue: venue.venue)) }
        case .storyAreaTypeMessage(let message):
            let open: () -> Void = { [weak self] in
                self?.openAreaMessage(chatID: message.chatId, messageID: message.messageId)
            }
            if let selectedArea, selectedArea.key == key, selectedArea.index == index {
                areaTooltip?.dismiss()
                open()
                return
            }
            title = L10n.telegram("Story.ViewMessage")
            anchorsAtTap = true
            action = open
        case .storyAreaTypeLink(let link):
            title = L10n.telegram("Story.ViewLink")
            subtitle = link.url
            action = { [weak self] in self?.openAreaLink(link.url) }
        case .storyAreaTypeSuggestedReaction, .storyAreaTypeUpgradedGift, .storyAreaTypeWeather:
            return
        }
        let size = contentView.bounds.size
        let source = anchorsAtTap
            ? CGRect(origin: CGPoint(x: point.x, y: point.y + 44), size: .zero)
            : StoryAreaGeometry.tooltipSource(of: area.position, in: size)
        areaTooltip?.dismiss()
        let tooltip = StoryAreaTooltipView(title: title, subtitle: subtitle, action: action)
        tooltip.onDismiss = { [weak self, weak tooltip] in
            self?.areaTooltipDidDismiss(tooltip)
        }
        areaTooltip = tooltip
        selectedArea = (key, index)
        setPaused(true, for: .menu)
        // The menu stays 64 pt clear of the story's top and bottom (ContextMenuControllerPresentationArguments).
        tooltip.show(
            in: view,
            source: contentView.convert(source, to: view),
            container: CGRect(origin: .zero, size: size).insetBy(dx: 0, dy: 64),
        )
    }

    /// Telegram drops the menu 0.1 s after it starts to leave, when the story resumes; the area stays selected
    /// while the tooltip fades, so a tap that dismissed it can still open its message.
    private func areaTooltipDidDismiss(_ tooltip: StoryAreaTooltipView?) {
        guard let tooltip, areaTooltip === tooltip else { return }
        areaTooltip = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, areaTooltip == nil else { return }
            setPaused(false, for: .menu)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, areaTooltip == nil else { return }
            selectedArea = nil
        }
    }

    /// BetterTG opens a location or venue area in its location viewer, where Telegram lists the place's stories.
    private func openLocation(_ subject: LocationViewSubject) {
        guard session.isCurrent, !isClosing, presentedViewController == nil else { return }
        let viewer = LocationViewController(subject: subject, client: session.client, source: session.source)
        present(viewer.makeNavigationController(), animated: true)
    }

    /// The message loads from the server first; a deleted one gets Telegram's toast, and an existing one opens in
    /// its chat once the viewer closes.
    private func openAreaMessage(chatID: Int64, messageID: Int64) {
        guard session.isCurrent, !isClosing else { return }
        let client = session.client
        // The UI probe's message is on no server.
        let isOffline = session.isOffline
        areaMessageTask?.cancel()
        areaMessageTask = Task { [weak self] in
            var message: Message?
            if !isOffline { message = try? await client.getMessage(chatId: chatID, messageId: messageID) }
            guard let self, !Task.isCancelled, session.isCurrent, !isClosing else { return }
            guard message != nil else {
                TelegramUndoToast.show(
                    text: L10n.telegram("Conversation.MessageDoesntExist"),
                    in: view,
                    bottomInset: toastBottomInset,
                    undo: nil,
                )
                return
            }
            TelegramLinkRouter.shared.openMessage(chatID: chatID, messageID: messageID, from: self)
        }
    }

    /// openUserGeneratedUrl: an address without a scheme opens over http; Telegram links stay in the app.
    private func openAreaLink(_ link: String) {
        let string = link.contains("://") ? link : "http://" + link
        guard let url = URL(string: string) else { return }
        TelegramLinkRouter.shared.open(url, from: self)
    }

    // MARK: More menu

    /// performMoreAction on someone else's story: the poster's details load, then Telegram's menu opens from the
    /// button, and the story waits until it closes.
    @objc private func morePressed() {
        guard !isClosing, moreTask == nil, presentedViewController == nil, !isPresentingTelegramContextMenu,
              let key = shownKey, StoryMoreMenu.showsButton(for: shownStory) else { return }
        areaTooltip?.dismiss()
        setPaused(true, for: .moreMenu)
        moreTask = Task { [weak self] in
            guard let self else { return }
            let poster = await menuPoster(chatID: key.chatID)
            guard !Task.isCancelled else { return }
            moreTask = nil
            if let poster, let story = shownStory, shownKey == key, session.isCurrent, !isClosing,
               presentMoreMenu(story: story, poster: poster)
            {
                return
            }
            setPaused(false, for: .moreMenu)
        }
    }

    private func menuPoster(chatID: Int64) async -> StoryMoreMenu.Poster? {
        #if DEBUG
            if session.isOffline { return probeMenuPoster }
        #endif
        return await StoryMoreMenu.resolvePoster(chatID: chatID, client: session.client)
    }

    private func presentMoreMenu(story: Story, poster: StoryMoreMenu.Poster) -> Bool {
        // The reply panel's share button stands in for the menu's Share, as in Telegram.
        let sharesFromPanel = !replyPanel.isHidden && replyPanel.configuration?.showsForward == true
        let actions = StoryMoreMenu.items(story: story, poster: poster, sharesFromPanel: sharesFromPanel).map { item in
            TelegramContextMenuAction(
                title: StoryMoreMenu.title(of: item),
                image: StoryMoreMenu.image(of: item),
                handler: { [weak self] in self?.performMoreItem(item, story: story, poster: poster) },
            )
        }
        return presentTelegramContextMenu(
            sourceView: moreButton,
            actions: actions,
            presentationStyle: .sourceMorph,
            onDismiss: { [weak self] in self?.setPaused(false, for: .moreMenu) },
        )
    }

    private func performMoreItem(_ item: StoryMoreMenu.Item, story: Story, poster: StoryMoreMenu.Poster) {
        #if DEBUG
            if session.isOffline {
                probeMenuActionHandler?(StoryMoreMenu.identifier(of: item))
                // Share opens its chat picker; the chat picked reaches only the probe.
                if item == .share { share(story) }
                return
            }
        #endif
        guard session.isCurrent, !isClosing else { return }
        switch item {
        case .notify(let isMuted):
            toggleStoryNotifications(of: poster, wereMuted: isMuted)
        case .copyLink:
            copyLink(to: story, poster: poster)
        case .share:
            share(story)
        case .archive(let isHidden):
            setStoriesHidden(!isHidden, of: poster, offersUndo: true)
        case .save:
            save(story, poster: poster)
        case .report:
            report(story)
        }
    }

    private func showMenuToast(_ text: String, undo: (() -> Void)? = nil) {
        TelegramUndoToast.show(text: text, in: view, bottomInset: toastBottomInset, undo: undo)
    }

    /// togglePeerStoriesMuted, with Telegram's tooltip naming the poster.
    private func toggleStoryNotifications(of poster: StoryMoreMenu.Poster, wereMuted: Bool) {
        let client = session.client
        let chatID = poster.chatID
        Task {
            guard let chat = try? await client.send(TDNativeRequests.getChat(chatId: chatID)) else { return }
            let settings = chat.notificationSettings.settingMuteStories(!wereMuted)
            _ = try? await client.send(TDNativeRequests.setChatNotificationSettings(
                chatId: chatID,
                notificationSettings: settings,
            ))
        }
        let key = wereMuted ? "StoryFeed.TooltipNotifyOn" : "StoryFeed.TooltipNotifyOff"
        showMenuToast(L10n.telegram(key, poster.title).withoutTelegramMarkup)
    }

    /// exportStoryLink: TDLib's https link to the story by its poster's username, copied with Telegram's toast.
    private func copyLink(to story: Story, poster: StoryMoreMenu.Poster) {
        guard let username = poster.username else { return }
        let client = session.client
        let link = TDNativeInternalLinkTypeStory(storyPosterUsername: username, storyId: story.id)
        menuActionTask?.cancel()
        menuActionTask = Task { [weak self] in
            let url = try? await client.send(TDNativeRequests.getInternalLink(
                type: .internalLinkTypeStory(link),
                isHttp: true,
            ))
            .url
            guard let self, !Task.isCancelled, session.isCurrent, !isClosing, let url else { return }
            UIPasteboard.general.string = url
            showMenuToast(L10n.telegram("Story.ToastLinkCopied"))
        }
    }

    /// performShareAction: the Forward picker's chats a story can go to, then the story as a message there.
    private func share(_ story: Story) {
        let client = session.client
        guard presentedViewController == nil, let accountID = TDLib.shared.activeAccountID,
              TDLib.shared.activeClient.id == client.id
        else { return }
        var seen = Set<Int64>()
        let seedChats = RootVM.shared
            .allFolders
            .flatMap(\.chats)
            .map(\.chat)
            .filter { seen.insert($0.id).inserted }
        guard let picker = ForwardMessagesViewController(
            choosingChatFor: .shareStory,
            client: client,
            accountID: accountID,
            seedChats: seedChats,
        ) else { return }
        let storyChatID = story.posterChatId
        let storyID = story.id
        picker.onChosenChat = { [weak self] chat, topic in
            guard let self, TDLib.shared.activeAccountID == accountID, TDLib.shared.activeClient.id == client.id
            else { return }
            #if DEBUG
                if session.isOffline {
                    probeMenuActionHandler?("share-to \(chat.chat.id)")
                    return
                }
            #endif
            send(storyChatID: storyChatID, storyID: storyID, to: chat.chat, topic: topic)
        }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    /// The shared story as an inputMessageStory, with Telegram's forwarded tooltip.
    private func send(storyChatID: Int64, storyID: Int, to chat: Chat, topic: ForumTopic?) {
        let client = session.client
        let chatID = chat.id
        let topicID = topic
            .map { MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId)) }
        let content = TDNativeInputMessageStory(storyPosterChatId: storyChatID, storyId: storyID)
        let tooltip = chatID == TDLib.shared.activeAccount?.userID
            ? L10n.telegram("Conversation.StoryForwardTooltip.SavedMessages.One")
            : L10n.telegram("Conversation.StoryForwardTooltip.Chat.One", chat.title)
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.sendMessage(
                    chatId: chatID,
                    topicId: topicID,
                    replyTo: nil,
                    options: nil,
                    replyMarkup: nil,
                    inputMessageContent: .inputMessageStory(content),
                ))
                guard let self, !isClosing else { return }
                showMenuToast(tooltip.withoutTelegramMarkup)
            } catch {
                guard let self, !isClosing else { return }
                presentChatListActionFailure()
            }
        }
    }

    /// updatePeerStoriesHidden, with Telegram's tooltip and its Undo.
    private func setStoriesHidden(_ isHidden: Bool, of poster: StoryMoreMenu.Poster, offersUndo: Bool) {
        let client = session.client
        let chatID = poster.chatID
        let list: TDNativeStoryList = isHidden ? .storyListArchive : .storyListMain
        Task { _ = try? await client.send(TDNativeRequests.setChatActiveStoriesList(chatId: chatID, storyList: list)) }
        guard offersUndo else { return }
        let key = isHidden ? "StoryFeed.TooltipArchive" : "StoryFeed.TooltipUnarchive"
        showMenuToast(L10n.telegram(key, poster.compactTitle).withoutTelegramMarkup) { [weak self] in
            self?.setStoriesHidden(!isHidden, of: poster, offersUndo: false)
        }
    }

    /// requestSave: a Premium account saves the story's photo or video with Telegram's Saving and Saved tooltips;
    /// without Premium, Telegram's toast names the subscription.
    private func save(_ story: Story, poster: StoryMoreMenu.Poster) {
        guard poster.accountIsPremium else {
            showMenuToast(L10n.telegram("Story.ToastPremiumSaveToGallery").withoutTelegramLinkMarkup)
            return
        }
        guard let media = StoryMoreMenu.savedFile(of: story) else { return }
        let client = session.client
        showMenuToast(L10n.telegram("Story.TooltipSaving"))
        menuActionTask?.cancel()
        menuActionTask = Task { [weak self] in
            do {
                try await StoryMoreMenu.saveToPhotos(media.file, isVideo: media.isVideo, client: client)
                guard let self, !Task.isCancelled, !isClosing else { return }
                showMenuToast(L10n.telegram("Story.TooltipSaved"))
            } catch {
                guard let self, !(error is CancellationError), !isClosing else { return }
                let alert = MediaGalleryExport.failureAlert(for: error, title: L10n.betterTG("Gallery.SaveFailedTitle"))
                present(alert, animated: true)
            }
        }
    }

    /// makeContentReportScreen with the story as its subject; the story waits while the sheet is up.
    private func report(_ story: Story) {
        ReportContentViewController.present(
            storyChatID: story.posterChatId,
            storyID: story.id,
            from: self,
            onReported: { [weak self] in self?.showMenuToast(L10n.telegram("Report.Succeed")) },
        )
    }

    // MARK: Cube

    /// beginHorizontalPan: a running turn stops where it rests, and the neighbours' faces join.
    private func beginPosterPan() {
        if cubeTurn != nil { finishCubeTurn() }
        cubeFraction = 0
        refreshNeighborFaces()
        setCubeFrameRate(isTurning: true)
        layoutCube()
    }

    /// updateHorizontalPan: the cube follows the finger, banding where no poster lies ahead.
    private func updatePosterPan(_ offset: CGFloat) {
        var offset = offset
        if offset > 0, state.neighbor(forward: false) == nil {
            offset = StoryCubeGeometry.rubberBand(offset)
        } else if offset < 0, state.neighbor(forward: true) == nil {
            offset = -StoryCubeGeometry.rubberBand(-offset)
        }
        cubeFraction = -min(1, max(-1, offset / max(1, containerView.bounds.width)))
        layoutCube()
    }

    /// commitHorizontalPan: past 30% of the width, or on a flick, the cube turns to the neighbour; a flick with no
    /// neighbour that way closes the viewer. Otherwise the cube springs back.
    private func finishPosterPan(velocity: CGFloat) {
        let hasPrevious = state.neighbor(forward: false) != nil
        let hasNext = state.neighbor(forward: true) != nil
        var forward: Bool?
        var mayDismiss = false
        if cubeFraction <= -StoryCubeGeometry.commitFraction {
            forward = hasPrevious ? false : nil
        } else if cubeFraction >= StoryCubeGeometry.commitFraction {
            forward = hasNext ? true : nil
        } else if abs(velocity) >= StoryCubeGeometry.commitVelocity {
            if velocity < 0 {
                if hasNext { forward = true } else { mayDismiss = true }
            } else {
                if hasPrevious { forward = false } else { mayDismiss = true }
            }
        }
        if let forward, case .poster = state.movePoster(forward: forward) {
            turnCube(forward: forward)
            return
        }
        startCubeTurn()
        if mayDismiss { close() }
    }

    /// The state entered the neighbouring poster: the story left behind stays on the face turning away, the new
    /// poster's story shows in front, and the cube turns from where it stood (a tap or the clock turns it whole).
    private func turnCube(forward: Bool) {
        // A turn still running rests first, as navigate's beginHorizontalPan drops it.
        if cubeTurn != nil { finishCubeTurn() }
        let leaving = contentView.snapshotView(afterScreenUpdates: false)
            ?? imageView.makeImageSnapshot(contentMode: .scaleAspectFill)
        leaving?.layer.cornerRadius = Self.contentCornerRadius
        leaving?.layer.cornerCurve = .continuous
        leaving?.clipsToBounds = true
        leaving?.isUserInteractionEnabled = false
        (forward ? previousFace : nextFace).setContent(leaving, frame: contentView.frame)
        (forward ? nextFace : previousFace).setContent(nil, frame: contentView.frame)
        cubeFraction = forward ? cubeFraction - 1 : cubeFraction + 1
        startCubeTurn()
        showCurrentStory()
    }

    /// Springs the cube back to rest over Telegram's 0.4 s, holding the story's clock meanwhile.
    private func startCubeTurn() {
        guard abs(cubeFraction) > 0.0001, !isClosing else {
            finishCubeTurn()
            return
        }
        cubeTurn = (from: cubeFraction, start: CACurrentMediaTime())
        setPaused(true, for: .drag)
        setCubeFrameRate(isTurning: true)
        layoutCube()
    }

    private func stepCubeTurn() {
        guard let turn = cubeTurn else { return }
        let fraction = (CACurrentMediaTime() - turn.start) / StoryCubeGeometry.turnDuration
        guard fraction < 1 else {
            finishCubeTurn()
            return
        }
        cubeFraction = turn.from * CGFloat(1 - StoryCubeGeometry.springProgress(fraction))
        layoutCube()
    }

    private func finishCubeTurn() {
        cubeTurn = nil
        cubeFraction = 0
        guard panAxis != .poster else {
            layoutCube()
            return
        }
        setCubeFrameRate(isTurning: false)
        refreshNeighborFaces()
        layoutCube()
        setPaused(false, for: .drag)
    }

    /// Places every face at its rotation: the previous poster's at -1, the shown one's at 0 and the next one's at 1,
    /// all shifted by the drag. A face turned a whole side away is off screen and hidden.
    private func layoutCube() {
        let width = containerView.bounds.width
        guard width > 0 else { return }
        let sideAngle = StoryCubeGeometry.sideAngle(
            width: width,
            sideDistance: StoryCubeGeometry
                .sideDistance(isRegularWidth: traitCollection.horizontalSizeClass == .regular),
        )
        let reducesMotion = UIAccessibility.isReduceMotionEnabled
        let isActive = isCubeActive
        for (face, offset) in [(previousFace, CGFloat(-1)), (focusedFace, 0), (nextFace, 1)] {
            let rotation = -cubeFraction + offset
            if face !== focusedFace {
                face.isHidden = !isActive || !face.hasContent || abs(rotation) >= 1
            }
            face.setRotation(rotation, sideAngle: sideAngle, reducesMotion: reducesMotion)
        }
    }

    /// The neighbouring posters' previews, from what the session has loaded; a turn's face keeps the story it left.
    private func refreshNeighborFaces() {
        guard cubeTurn == nil, !isClosing else { return }
        for forward in [false, true] {
            let face = forward ? nextFace : previousFace
            guard let neighbor = state.neighbor(forward: forward) else {
                face.setContent(nil, frame: contentView.frame)
                continue
            }
            let preview = forward ? nextPreview : previousPreview
            preview.configure(
                neighbor: neighbor,
                chat: session.cachedChat(neighbor.chatID),
                story: neighbor.storyID.flatMap { session.cachedStory(.init(chatID: neighbor.chatID, storyID: $0)) },
                client: session.client,
            )
            face.setContent(preview, frame: contentView.frame)
        }
        layoutCube()
    }

    /// Telegram runs its story transitions at up to 120 Hz; the story's clock needs no more than the default.
    private func setCubeFrameRate(isTurning: Bool) {
        displayLink?.preferredFrameRateRange = isTurning
            ? CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            : .default
    }

    private func configureReplyPanel() {
        replyDimView.backgroundColor = UIColor(white: 0, alpha: 0.001)
        replyDimView.isHidden = true
        replyDimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(replyDimTapped)))
        focusedFace.contentHost.addSubview(replyDimView)

        replyPanel.isHidden = true
        replyPanel.onSend = { [weak self] text in self?.sendReplyText(text) }
        replyPanel.onLike = { [weak self] in self?.likePressed() }
        replyPanel.onLikeOptions = { [weak self] gesture in self?.likeHeld(gesture) }
        replyPanel.onForward = { [weak self] in
            guard let self, let story = shownStory, !isClosing else { return }
            share(story)
        }
        replyPanel.onEditingChanged = { [weak self] editing in self?.replyEditingChanged(editing) }
        replyPanel.onTextChanged = { [weak self] in self?.replyTextChanged() }
        focusedFace.contentHost.addSubview(replyPanel)

        replyReactions.isHidden = true
        replyReactions.accessibilityIdentifier = "story-reply-reactions"
        replyReactions.onSelect = { [weak self] reaction in self?.selectReplyReaction(reaction) }
        focusedFace.contentHost.addSubview(replyReactions)
    }

    /// MessageInputPanelComponent's place: its bottom on the safe area, or on the keyboard while the field edits.
    private func layoutReplyPanel() {
        let bounds = view.bounds
        replyDimView.frame = bounds
        let height = replyPanel.preferredHeight(width: bounds.width)
        let restingBottom = bounds.height - Self.panelBottomInset(view.safeAreaInsets)
        let bottom = keyboardOverlap > 0 ? min(restingBottom, bounds.height - keyboardOverlap) : restingBottom
        replyPanel.frame = CGRect(x: 0, y: bottom - height, width: bounds.width, height: height)
        replyPanel.layoutIfNeeded()
        layoutReplyReactions()
    }

    /// ReactionContextNode's anchor: the field's send slot while it edits, the like button while it's held.
    private func layoutReplyReactions() {
        guard let mode = replyReactionsMode else { return }
        let bounds = view.bounds
        let width = min(bounds.width - 16, replyReactions.preferredWidth)
        let height = replyReactions.preferredHeight
        let anchor: CGRect =
            switch mode {
            case .message:
                CGRect(
                    x: replyPanel.frame.maxX - 40,
                    y: replyPanel.frame.minY + StoryReplyPanelView.topInset - 5,
                    width: 32,
                    height: 32,
                )
            case .like:
                replyPanel.likeButton.convert(replyPanel.likeButton.bounds, to: focusedFace.contentHost)
            }
        let x = min(bounds.width - 8 - width, max(8, anchor.maxX + 8 - width))
        replyReactions.frame = CGRect(x: x, y: anchor.minY - 8 - height, width: width, height: height)
    }

    /// The panel for the shown story once its poster is known; another poster's story hides it until then.
    private func renderReplyPanel(_ story: Story) {
        let key = StoryViewerSession.StoryKey(chatID: story.posterChatId, storyID: story.id)
        if let poster = replyPosters[key.chatID] {
            applyReplyPanel(StoryReplyPanel.configuration(story: story, poster: poster), key: key, story: story)
            return
        }
        applyReplyPanel(nil, key: nil)
        replyPosterTask?.cancel()
        replyPosterTask = Task { [weak self] in
            guard let self, let poster = await replyPoster(chatID: key.chatID), !Task.isCancelled else { return }
            replyPosters[key.chatID] = poster
            guard shownKey == key, let story = shownStory, !isClosing else { return }
            applyReplyPanel(StoryReplyPanel.configuration(story: story, poster: poster), key: key, story: story)
        }
    }

    private func replyPoster(chatID: Int64) async -> StoryReplyPanel.Poster? {
        #if DEBUG
            if session.isOffline { return probeReplyPoster }
        #endif
        return await StoryReplyPanel.resolvePoster(chatID: chatID, client: session.client)
    }

    private func applyReplyPanel(
        _ configuration: StoryReplyPanel.Configuration?,
        key: StoryViewerSession.StoryKey?,
        story: Story? = nil,
    ) {
        let isSameStory = key != nil && key == replyPanelKey
        if configuration?.acceptsInput != true, replyPanel.isEditing { replyPanel.endEditing() }
        if key?.chatID != replyPanelKey?.chatID { replyPanel.clearText() }
        replyPanelKey = configuration == nil ? nil : key
        replyPanel.configure(configuration)
        replyPanel.isHidden = configuration == nil
        if let story, configuration?.showsLike == true {
            replyPanel.setReaction(
                story.chosenReactionType,
                client: session.client,
                loadsSticker: !session.isOffline,
                animated: isSameStory,
            )
        }
        if configuration != nil { loadStoryReactions() }
        view.setNeedsLayout()
    }

    private func replyEditingChanged(_ editing: Bool) {
        if editing {
            areaTooltip?.dismiss()
            if replyPanel.text.isEmpty { showReplyReactions(.message) }
        } else if replyReactionsMode == .message {
            hideReplyReactions()
        }
        updateReplyState()
    }

    private func replyTextChanged() {
        if replyPanel.isEditing {
            if replyPanel.text.isEmpty, replyReactionsMode == nil {
                showReplyReactions(.message)
            } else if !replyPanel.text.isEmpty, replyReactionsMode == .message {
                hideReplyReactions()
            }
        }
        view.setNeedsLayout()
    }

    /// The story waits while the field edits or reactions show over it, dimmed under the keyboard.
    private func updateReplyState() {
        let isEditing = replyPanel.isEditing
        let isActive = isEditing || replyReactionsMode != nil
        setPaused(isActive, for: .reply)
        if isActive { replyDimView.isHidden = false }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.replyDimView.backgroundColor = UIColor(white: 0, alpha: isEditing ? 0.8 : 0.001)
        } completion: { [weak self] _ in
            guard let self else { return }
            replyDimView.isHidden = !(replyPanel.isEditing || replyReactionsMode != nil)
        }
    }

    @objc private func replyDimTapped() {
        if replyPanel.isEditing {
            replyPanel.endEditing()
        } else {
            hideReplyReactions()
            updateReplyState()
        }
    }

    private func keyboardWillChangeFrame(_ notification: Notification, hides: Bool) {
        guard isViewLoaded, view.window != nil, hides || replyPanel.isEditing || keyboardOverlap > 0 else { return }
        var overlap = CGFloat(0)
        if !hides, let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY)
        }
        guard overlap != keyboardOverlap else { return }
        keyboardOverlap = overlap
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        view.setNeedsLayout()
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState, .allowUserInteraction],
        ) {
            self.view.layoutIfNeeded()
        }
    }

    /// ReactionContextNode over the story: titled Send Reaction as a Message while the empty field edits, untitled
    /// over the held like button.
    private func showReplyReactions(_ mode: ReplyReactionsMode) {
        guard shownStory != nil, replyPanel.configuration != nil else { return }
        let wasShown = replyReactionsMode != nil
        replyReactionsMode = mode
        replyReactions.title =
            switch mode {
            case .message:
                L10n.telegram(
                    replyPanel.configuration?.isGroup == true
                        ? "Story.SendReactionAsGroupMessage"
                        : "Story.SendReactionAsMessage",
                )
            case .like:
                nil
            }
        configureReplyReactions()
        layoutReplyPanel()
        replyReactions.isHidden = false
        if !wasShown {
            replyReactions.alpha = 0
            replyReactions.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            UIView.animate(
                withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.3,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
            ) {
                self.replyReactions.alpha = 1
                self.replyReactions.transform = .identity
            }
        }
        updateReplyState()
    }

    private func hideReplyReactions() {
        guard replyReactionsMode != nil else { return }
        replyReactionsMode = nil
        replyReactions.updateTracking(at: nil)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
            self.replyReactions.alpha = 0
        } completion: { [weak self] _ in
            guard let self, replyReactionsMode == nil else { return }
            replyReactions.isHidden = true
            replyReactions.prepareForReuse()
        }
    }

    /// The reactions offered, with the story's own reaction marked as chosen.
    private func configureReplyReactions() {
        guard let reactions = storyReactions else { return }
        let client = session.client
        let chosen = replyPanel.likeButton.reaction
        replyReactions.configure(reactions.types.map { type in
            TelegramContextMenuReaction(
                type: type,
                isChosen: type == chosen,
                sticker: type.customEmojiID.flatMap { reactions.stickers[$0] },
                client: client,
                handler: {},
            )
        })
        layoutReplyReactions()
    }

    /// getStoryAvailableReactions in Telegram's order, without the ones that need Premium for an account without it.
    private func loadStoryReactions() {
        guard storyReactions == nil, replyReactionsTask == nil else { return }
        #if DEBUG
            if session.isOffline {
                storyReactions = (
                    ["❤", "👍", "🔥", "🥰", "👏", "😁", "🤔", "🤯"].map {
                        ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: $0))
                    },
                    [:],
                )
                return
            }
        #endif
        let client = session.client
        replyReactionsTask = Task { [weak self] in
            async let availableRequest = client.send(TDNativeRequests.getStoryAvailableReactions(rowSize: 7))
            async let meRequest = client.send(TDNativeRequests.getMe())
            let available = try? await availableRequest
            let isPremium = await (try? meRequest)?.isPremium ?? false
            let types = available.map { Array($0.contextReactionTypes(isPremium: isPremium).prefix(24)) } ?? []
            let stickers = await CustomEmojiStickerRepository.shared.stickers(
                for: types.compactMap(\.customEmojiID),
                client: client,
            )
            guard let self, !Task.isCancelled else { return }
            replyReactionsTask = nil
            guard !types.isEmpty else { return }
            storyReactions = (types, stickers)
            if replyReactionsMode != nil {
                configureReplyReactions()
            }
        }
    }

    private func selectReplyReaction(_ reaction: TelegramContextMenuReaction) {
        guard let mode = replyReactionsMode, let story = shownStory, !isClosing else { return }
        hideReplyReactions()
        switch mode {
        case .like:
            // Picking the story's own reaction again takes it back.
            setStoryReaction(reaction.type == replyPanel.likeButton.reaction ? nil : reaction.type, on: story)
            updateReplyState()
        case .message:
            replyPanel.endEditing()
            guard let text = StoryReplyPanel.messageText(for: reaction.type, sticker: reaction.sticker) else { return }
            sendStoryReply(text, to: story, toast: L10n.telegram("Story.ToastReactionSent"))
        }
    }

    /// activateInlineReaction: someone else's story takes the reaction area's reaction; the account's own story only
    /// answers the tap.
    private func activateInlineReaction(_ reaction: ReactionType, on story: Story) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard !reaction.isPaid, story.posterChatId != TDLib.shared.activeAccount?.userID, !isClosing else { return }
        setStoryReaction(reaction, on: story)
    }

    /// performLikeAction: Telegram's heart, or no reaction once the story has one.
    private func likePressed() {
        guard let story = shownStory, replyPanel.configuration?.showsLike == true, !isClosing else { return }
        let heart = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: "❤"))
        setStoryReaction(replyPanel.likeButton.reaction == nil ? heart : nil, on: story)
    }

    /// performLikeOptionsAction: the reactions open over the held like button and follow the finger; letting go on
    /// one picks it, elsewhere it leaves them open.
    private func likeHeld(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard replyPanel.configuration?.offersLikeOptions == true, shownStory != nil, !isClosing else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if replyPanel.isEditing { replyPanel.endEditing() }
            showReplyReactions(.like)
        case .changed:
            guard replyReactionsMode == .like else { return }
            replyReactions.updateTracking(at: gesture.location(in: replyReactions))
        case .ended:
            guard replyReactionsMode == .like else { return }
            replyReactions.updateTracking(at: gesture.location(in: replyReactions))
            if !replyReactions.selectTrackedReaction() { replyReactions.updateTracking(at: nil) }
        case .cancelled, .failed:
            replyReactions.updateTracking(at: nil)
        default:
            break
        }
    }

    /// setStoryReaction, shown on the like button at once and taken back if TDLib refuses it.
    private func setStoryReaction(_ type: ReactionType?, on story: Story) {
        let previous = replyPanel.likeButton.reaction
        let client = session.client
        replyPanel.setReaction(type, client: client, loadsSticker: !session.isOffline, animated: true)
        #if DEBUG
            if session.isOffline {
                probeMenuActionHandler?("like \(type?.accessibilityIdentifierComponent ?? "none")")
                return
            }
        #endif
        let key = StoryViewerSession.StoryKey(chatID: story.posterChatId, storyID: story.id)
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setStoryReaction(
                    storyPosterChatId: key.chatID,
                    storyId: key.storyID,
                    reactionType: type,
                    updateRecentReactions: true,
                ))
            } catch {
                guard let self, shownKey == key, !isClosing else { return }
                replyPanel.setReaction(previous, client: client, loadsSticker: true, animated: false)
                presentChatListActionFailure()
            }
        }
    }

    // MARK: Replies

    private func sendReplyText(_ text: String) {
        guard let story = shownStory, replyPanel.configuration?.acceptsInput == true, !isClosing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replyPanel.clearText()
        replyPanel.endEditing()
        sendStoryReply(
            FormattedText(entities: [], text: trimmed),
            to: story,
            toast: L10n.telegram("Story.TooltipMessageSent"),
        )
    }

    /// The text as a message to the poster replying to the story (replyToStoryId), then Telegram's toast with View in
    /// Chat, which opens the message.
    private func sendStoryReply(_ text: FormattedText, to story: Story, toast: String) {
        let chatID = story.posterChatId
        #if DEBUG
            if session.isOffline {
                probeMenuActionHandler?("reply \(text.text)")
                showReplyToast(toast, chatID: chatID, messageID: nil)
                return
            }
        #endif
        let client = session.client
        let replyTo = InputMessageReplyTo.inputMessageReplyToStory(
            TDNativeInputMessageReplyToStory(storyPosterChatId: chatID, storyId: story.id),
        )
        let content = InputMessageContent.inputMessageText(
            InputMessageText(clearDraft: false, linkPreviewOptions: nil, text: text),
        )
        Task { [weak self] in
            do {
                let message = try await client.send(TDNativeRequests.sendMessage(
                    chatId: chatID,
                    topicId: nil,
                    replyTo: replyTo,
                    options: nil,
                    replyMarkup: nil,
                    inputMessageContent: content,
                ))
                guard let self, !isClosing else { return }
                sentReplyIDs[message.id] = message.id
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showReplyToast(toast, chatID: chatID, messageID: message.id)
            } catch {
                guard let self, !isClosing else { return }
                presentChatListActionFailure()
            }
        }
    }

    private func showReplyToast(_ text: String, chatID: Int64, messageID: Int64?) {
        TelegramUndoToast.show(
            text: text,
            in: view,
            bottomInset: toastBottomInset,
            actionTitle: messageID == nil ? nil : L10n.telegram("Story.ToastViewInChat"),
            undo: messageID.map { messageID in
                { [weak self] in
                    guard let self, session.isCurrent, !isClosing else { return }
                    let sentID = sentReplyIDs[messageID] ?? messageID
                    TelegramLinkRouter.shared.openMessage(chatID: chatID, messageID: sentID, from: self)
                }
            },
        )
    }

    // MARK: Closing

    /// Telegram returns the story to the avatar or bubble it opened from, or lets it fall away.
    private func close() {
        guard !isClosing else { return }
        isClosing = true
        stopClock()
        areaTooltip?.dismiss()
        hideReplyReactions()
        if replyPanel.isEditing { replyPanel.endEditing() }
        player.pause()
        session.closeOpenedStory()
        containerView.isUserInteractionEnabled = false
        guard view.window != nil else {
            finishClosing()
            return
        }
        let target = sourceFrame()
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut],
        ) {
            self.backdropView.alpha = 0
            self.chromeView.alpha = 0
            // A flick past the last poster closes while the cube springs back; it comes to rest as the story leaves.
            if self.cubeTurn != nil { self.finishCubeTurn() }
            if let target, !UIAccessibility.isReduceMotionEnabled {
                self.containerView.transform = self.containerTransform(matching: target)
                self.contentView.layer.cornerRadius = self.sourceIsAvatar
                    ? self.contentView.bounds.width / 2
                    : Self.contentCornerRadius
                self.containerView.alpha = 0
            } else {
                self.containerView.alpha = 0
                if !UIAccessibility.isReduceMotionEnabled {
                    self.containerView.transform = self.containerView
                        .transform
                        .translatedBy(x: 0, y: self.view.bounds.height / 3)
                }
            }
        } completion: { [weak self] _ in
            self?.finishClosing()
        }
    }

    private func finishClosing() {
        tearDown()
        if presentingViewController != nil {
            dismiss(animated: false)
        }
    }

    private func tearDown() {
        stopClock()
        mediaTask?.cancel()
        preloadTask?.cancel()
        neighborTask?.cancel()
        areaMessageTask?.cancel()
        moreTask?.cancel()
        menuActionTask?.cancel()
        headerTask?.cancel()
        replyPosterTask?.cancel()
        replyReactionsTask?.cancel()
        mediaTask = nil
        preloadTask = nil
        neighborTask = nil
        headerTask = nil
        imageView.onFullImage = nil
        imageView.cancel()
        player.stop()
        session.invalidate()
    }

    /// The avatar or bubble the viewer opened from, while it's still on screen.
    private func sourceFrame() -> CGRect? {
        guard let sourceView, sourceView.window != nil, !sourceView.isHidden,
              sourceView.alpha > 0.01 else { return nil }
        let frame = sourceView.convert(sourceView.bounds, to: nil)
        guard frame.width > 1, frame.height > 1, frame.intersects(view.bounds) else { return nil }
        return frame
    }

    /// Maps the story's frame onto `target`, scaling the whole container about its center.
    private func containerTransform(matching target: CGRect) -> CGAffineTransform {
        let content = contentView.frame
        let scale = target.width / max(1, content.width)
        let center = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY)
        let translationX = target.midX - center.x - scale * (content.midX - center.x)
        let translationY = target.midY - center.y - scale * (content.midY - center.y)
        return CGAffineTransform(translationX: translationX, y: translationY).scaledBy(x: scale, y: scale)
    }
}

#if DEBUG

    // MARK: - StoryViewerController + UI probe

    extension StoryViewerController {
        /// The cube as the UI probe reads it: the turn's fraction, the neighbours' faces on screen with a preview,
        /// and whether the shown face is turned away from rest.
        struct ProbeCube {
            let fraction: CGFloat
            let showsPrevious: Bool
            let showsNext: Bool
            let turnsFocused: Bool
        }

        var probeShownChatID: Int64 {
            state.currentChatID
        }

        var probeShownStory: Story? {
            shownStory
        }

        var probeStorySize: CGSize {
            contentView.bounds.size
        }

        /// The open area tooltip's title and subtitle.
        var probeTooltipText: String? {
            areaTooltip?.probeText
        }

        /// The reactions and weather the overlay draws; the other areas are part of the story's picture.
        var probeDrawnAreaCount: Int {
            areaOverlay.subviews.count
        }

        var probeShowsMoreMenu: Bool {
            isPresentingTelegramContextMenu
        }

        var probeCube: ProbeCube {
            ProbeCube(
                fraction: cubeFraction,
                showsPrevious: !previousFace.isHidden && previousFace.hasContent,
                showsNext: !nextFace.isHidden && nextFace.hasContent,
                turnsFocused: !CATransform3DIsIdentity(focusedFace.transform3D),
            )
        }

        /// Opens the viewer at `initialChatID` on the UI probe's seeded stories, which never reach TDLib, and holds
        /// the story still. The More menu reads `menuPoster`, and its choices go to `onMenuItem`.
        static func presentProbe(
            stories: [Story],
            chats: [Chat],
            activeStories: [ChatActiveStories],
            initialChatID: Int64,
            menuPoster: StoryMoreMenu.Poster,
            replyPoster: StoryReplyPanel.Poster = .user(isBot: false, isService: false, isSelf: false),
            onMenuItem: @escaping (String) -> Void,
            client: TDLibClient,
            from presenter: UIViewController,
        ) -> StoryViewerController? {
            guard let session = StoryViewerSession(client: client) else { return nil }
            session.seedOffline(stories: stories, chats: chats, activeStories: activeStories)
            let posters = activeStories.map { list in
                StoryViewerState.Poster(
                    chatID: list.chatId,
                    storyIDs: list.stories.map(\.storyId),
                    maxReadStoryID: list.maxReadStoryId,
                )
            }
            guard let state = StoryViewerState(posters: posters, initialChatID: initialChatID) else {
                session.invalidate()
                return nil
            }
            let viewer = StoryViewerController(
                session: session,
                state: state,
                followsActiveStories: false,
                sourceView: nil,
                sourceIsAvatar: false,
            )
            viewer.probeMenuPoster = menuPoster
            viewer.probeReplyPoster = replyPoster
            viewer.probeMenuActionHandler = onMenuItem
            viewer.state.setPaused(true, for: .probe)
            presenter.present(viewer, animated: false)
            return viewer
        }

        /// Holds the cube `fraction` of a turn towards the next poster, or the previous one when negative, as a
        /// drag standing still there would.
        func probeHoldCube(at fraction: CGFloat) {
            guard !isClosing else { return }
            areaTooltip?.dismiss()
            panAxis = .poster
            beginPosterPan()
            setPaused(true, for: .drag)
            updatePosterPan(-fraction * containerView.bounds.width)
        }

        /// Lets the held cube go as a drag that stops: past 30% of the width it turns on, short of it it springs back.
        func probeReleaseCube() {
            guard panAxis == .poster else { return }
            panAxis = nil
            finishPosterPan(velocity: 0)
        }

        /// A tap at `point` in the story, taken as the tap gesture takes it.
        func probeTap(at point: CGPoint) {
            guard !isClosing else { return }
            handleStoryTap(at: point)
        }

        func probeOpenMoreMenu() {
            morePressed()
        }

        /// The reply panel as shown, or nil while it's hidden.
        var probeReplyConfiguration: StoryReplyPanel.Configuration? {
            replyPanel.isHidden ? nil : replyPanel.configuration
        }

        var probeReplyPanelFrame: CGRect {
            replyPanel.frame
        }

        var probeLikeReaction: ReactionType? {
            replyPanel.likeButton.reaction
        }

        var probeReplyIsEditing: Bool {
            replyPanel.isEditing
        }

        /// The reactions over the story: whether they're for a message or the like button, their title and count.
        var probeReplyReactions: (mode: String, title: String?, count: Int)? {
            guard let mode = replyReactionsMode, !replyReactions.isHidden else { return nil }
            return (mode == .message ? "message" : "like", replyReactions.title, storyReactions?.types.count ?? 0)
        }

        var probeIsPausedForReply: Bool {
            state.pauseReasons.contains(.reply)
        }

        func probeLike() {
            likePressed()
        }

        func probeBeginReply() {
            replyPanel.beginEditing()
        }

        /// Holding the like button, as its long press's start does.
        func probeHoldLike() {
            guard replyPanel.configuration?.offersLikeOptions == true, shownStory != nil else { return }
            showReplyReactions(.like)
        }

        func probeSendReply(_ text: String) {
            replyPanel.probeSetText(text)
            sendReplyText(text)
        }
    }
#endif

// MARK: - StoryViewerDisplayLinkTarget

/// CADisplayLink keeps its target alive; this one holds the viewer weakly.
private final class StoryViewerDisplayLinkTarget: NSObject {
    private weak var viewer: StoryViewerController?

    init(_ viewer: StoryViewerController) {
        self.viewer = viewer
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let viewer else {
            link.invalidate()
            return
        }
        viewer.tick(link)
    }
}
