// ChatView.swift

import Combine
import PhotosUI
import TDLibKitDynamic
import UIKit

final class ChatViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching,
    PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
    UIGestureRecognizerDelegate
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

    private struct PendingComposerSendTransition {
        let kind: ComposerSendTransitionKind
        var messageIDs = [Int64]()
        let snapshots: [ComposerSendTransitionSnapshot]
        let timeout: DispatchWorkItem
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
    private let historyContainerView = UIView()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, ChatTimelineItemID>!
    private var cancellables = Set<AnyCancellable>()
    private var messageCancellables = Set<AnyCancellable>()
    private var prefetchTasks = [DisplayedMessageID: PrefetchTaskEntry]()
    private var inlineVideoPlaybackOwners = [Int64: GalleryVideoPlaybackOwner]()
    private var pendingInlineVideoOwnerReturns = Set<Int64>()
    private let customNavigationBar = TelegramChatNavigationBar()
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private let pinnedMessageBanner = PinnedMessageBannerView()
    private var pinnedMessageBannerHeightConstraint: NSLayoutConstraint!
    private var displayedPinnedMessage: Message?
    private var pinnedMessageBannerTransitionGeneration = UInt64.zero
    private lazy var composerView = ChatComposerView(chatVM: chatVM)
    private let messageSelectionToolbar = MessageSelectionToolbar()
    private var messageSelectionToolbarHeightConstraint: NSLayoutConstraint!
    private let scrollToLatestButton = UIButton(type: .system)
    private let unreadBadgeLabel = TelegramUnreadBadgeLabel(minimumDiameter: 20, horizontalPadding: 11)
    private var scrollToLatestButtonVisible = false
    private var didPresentMicrophoneError = false
    private var didPresentVoiceNoteError = false
    private var didPresentVideoNoteError = false
    private var didPresentReactionError = false
    private var didPresentPinError = false
    private var didPresentSendError = false
    private var didPresentDraftError = false
    private var lastHighlightedMessageID: Int64?
    private var didPerformInitialScroll = false
    private var pendingScrollMessageID: DisplayedMessageID?
    private var pendingQuoteHighlight: MessageQuoteHighlight?
    private var pendingQuoteTargetMessageID: Int64?
    private var pendingQuoteDestination: PendingQuoteDestination?
    private var messageNavigationTask: Task<Void, Never>?
    private var metadataNavigationTask: Task<Void, Never>?
    private var messageHighlightTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var reactionPickerTask: Task<Void, Never>?
    private var messageSearchActive = false
    private var isTerminatingNavigation = false
    private var composerLeadingConstraint: NSLayoutConstraint?
    private var composerTrailingConstraint: NSLayoutConstraint?
    private var composerBottomConstraint: NSLayoutConstraint?
    private var composerKeyboardAttached = false
    private var voiceGestureDefersSystemGestures = false
    private var videoNoteRecorder: VideoNoteRecorderViewController?
    private var videoNoteReplyMessage: CustomMessage?
    private var videoNoteReplyInput: InputMessageReplyTo?
    private var videoNoteSendTopic: MessageTopic?
    private var videoNoteChatActionActive = false
    private var restoredVideoRecordingDraftIDHandled: UUID?
    private var selectedDisplayedMessageIDs = Set<DisplayedMessageID>()
    private var isSelectingMessages = false
    private var selectionCapabilityTask: Task<Void, Never>?
    private var selectionCapabilityGeneration: UUID?
    private var timelineLayoutMutationDepth = 0
    private var pendingSelfSizingAnchor: SnapshotAnchor?
    private var pendingSelfSizingKeepsLatest = false
    private var selfSizingAnchorRestoreScheduled = false
    private var pendingComposerSendTransitions = [UUID: PendingComposerSendTransition]()
    private var sendTransitionMessageIDAliases = [Int64: Int64]()
    private var pendingDeleteSnapshotWorkItem: DispatchWorkItem?
    private var pendingDeleteSnapshotDeadline: CFTimeInterval?

    private lazy var messageContextGesture: TelegramContextGestureRecognizer = {
        let gesture = TelegramContextGestureRecognizer(target: self, action: #selector(messageLongPressed(_:)))
        gesture.onPressingChanged = { [weak self, weak gesture] pressing in
            guard let self, let gesture else { return }
            guard !isSelectingMessages else {
                restorePressedMessageSource()
                return
            }
            if pressing {
                let point = gesture.location(in: collectionView)
                guard let indexPath = collectionView.indexPathForItem(at: point),
                      let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
                else { return }
                pressedMessageSourceView = cell.contextPreviewView
                pressedMessageSourceTransform = cell.contextPreviewView.transform
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
                UIView.animate(
                    withDuration: 0.16,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    cell.contextPreviewView.transform = self.pressedMessageSourceTransform.scaledBy(x: 0.98, y: 0.98)
                }
            } else {
                restorePressedMessageSource()
            }
        }
        return gesture
    }()

    private weak var pressedMessageSourceView: UIView?
    private var pressedMessageSourceTransform = CGAffineTransform.identity

    private var showsComposer: Bool {
        presentationMode == .full
            && (location.isTopicScoped || chatVM.isAllMessagesForum || chatVM.canShowComposer)
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
            return sourceCount == 1 ? "1 message selected" : "\(sourceCount) messages selected"
        }
        return "\(bubbleCount) conversations selected, \(sourceCount) messages"
    }

    init(
        customChat: CustomChat,
        location: ChatLocation? = nil,
        forumTopic: ForumTopic? = nil,
        presentationMode: PresentationMode = .full,
        targetMessageID: Int64? = nil,
        targetQuote: MessageQuoteHighlight? = nil,
        tdlib: TDLib = .shared,
    ) {
        let resolvedLocation = location ?? ChatLocation.current(
            chatID: customChat.id,
            client: tdlib.activeClient,
        )
        self.presentationMode = presentationMode
        self.location = resolvedLocation
        self.chatVM = ChatVM(
            customChat: customChat,
            location: resolvedLocation,
            forumTopic: forumTopic,
            previewing: presentationMode == .contextPreview,
        )
        self.targetMessageID = targetMessageID
        self.targetQuote = targetQuote
        self.tdlib = tdlib
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        prefetchTasks.values.forEach { $0.task?.cancel() }
        MainActor.assumeIsolated {
            inlineVideoPlaybackOwners.values.forEach { $0.invalidate() }
        }
        messageNavigationTask?.cancel()
        metadataNavigationTask?.cancel()
        messageHighlightTask?.cancel()
        reactionPickerTask?.cancel()
        selectionCapabilityTask?.cancel()
        pendingDeleteSnapshotWorkItem?.cancel()
        for transition in pendingComposerSendTransitions.values {
            transition.timeout.cancel()
            transition.snapshots.forEach { $0.view.removeFromSuperview() }
        }
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
        composerView.cancelActiveRecordingGesture()
        if chatVM.canWriteBasicMessages {
            Task { [chatVM] in await chatVM.updateDraft() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isTerminatingNavigation = false
        if presentationMode == .full {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreVisibleInlineVideoPlayback()
        if presentationMode == .full {
            chatVM.readAllReactions()
        }
        #if DEBUG
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
            composerView.setKeyboardAttached(keyboardAttached)
            updateComposerFloatingState(keyboardAttached)
        }
        updateHistoryInsets()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator,
    ) {
        let userIsScrolling = collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
        let keepLatest = didPerformInitialScroll && !userIsScrolling && isNearLatest
        let anchor = didPerformInitialScroll && !userIsScrolling && !keepLatest
            ? captureSnapshotAnchor()
            : nil
        timelineLayoutMutationDepth += 1
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }) { [weak self] _ in
            guard let self else { return }
            defer { timelineLayoutMutationDepth -= 1 }
            collectionView.layoutIfNeeded()
            if keepLatest {
                pinToLatestEdge(animated: false)
            } else if let anchor {
                restoreSnapshotAnchor(anchor)
            }
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + TelegramChatNavigationBar.contentHeight
        messageSelectionToolbarHeightConstraint?.constant =
            MessageSelectionToolbar.contentHeight + view.safeAreaInsets.bottom
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateScrollToLatestButtonVisibility(animated: true)
        updateInlineVideoPlaybackVisibility()
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        PhotoPickerSelectionLoader.load(results) { [weak self] images in
            self?.chatVM.displayedImages = images
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        Task { [weak self] in
            let selected = await Task.detached(priority: .userInitiated) { writeImage(image) }.value
            guard let selected else { return }
            self?.chatVM.displayedImages = [selected]
        }
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard case .message(let displayedMessageID) = dataSource.itemIdentifier(for: indexPath),
              let message = message(for: displayedMessageID)
        else { return }
        if let cell = cell as? MessageCell {
            for owner in inlineVideoPlaybackOwners(for: message).values {
                if cell.restoreInlineVideoPlaybackOwner(owner) {
                    pendingInlineVideoOwnerReturns.remove(owner.messageID)
                }
            }
        }
        (cell as? MessageCell)?.setMediaPlaybackVisible(
            presentedViewController == nil,
            allowsInlineVideoPlayback: false,
        )
        if let cell = cell as? MessageCell {
            applyPendingQuoteHighlight(to: cell, displayedMessageID: displayedMessageID)
        }
        updateInlineVideoPlaybackVisibility()
        if presentationMode == .full {
            chatVM.viewMessages(ids: message.sourceMessages.map(\.id))
        }
        if Set(chatVM.messages.suffix(5).map(\.displayedID)).contains(displayedMessageID) {
            chatVM.loadMessages()
        }
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
        }
    }

    func collectionView(_: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard case .message(let displayedMessageID) = dataSource.itemIdentifier(for: indexPath),
                  let message = message(for: displayedMessageID),
                  prefetchTasks[displayedMessageID] == nil
            else { continue }
            let messages = message.album.isEmpty ? [message.message] : message.album
            let client = chatVM.client
            let generation = UUID()
            let entry = PrefetchTaskEntry(generation: generation)
            prefetchTasks[displayedMessageID] = entry
            entry.task = Task { [weak self] in
                for item in messages where !Task.isCancelled {
                    await TDMediaPrefetcher.prefetch(message: item, client: client)
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
        }
    }

    func beginMessageSearch() {
        guard presentationMode == .full else { return }
        customNavigationBar.beginSearch()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        if gestureRecognizer === messageContextGesture || otherGestureRecognizer === messageContextGesture {
            if gestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPanGestureRecognizer {
                return false
            }
        }
        return true
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
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func configureNavigationBar() {
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        customNavigationBar.onBack = presentationMode == .full ? { NavigationStorage.shared.pop() } : nil
        customNavigationBar.onSelectionCancel = { [weak self] in
            self?.endMessageSelection()
        }
        customNavigationBar.onSearchQueryChange = { [weak self] query in
            self?.searchMessages(query: query)
        }
        customNavigationBar.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            messageSearchActive = active
            composerView.setHiddenForSearch(active)
            updateScrollToLatestButtonVisibility(animated: true)
            if !active {
                searchTask?.cancel()
                customNavigationBar.setSearchResultFound(nil)
            }
            view.setNeedsLayout()
            updatePinnedMessageBanner(animated: true)
        }
        if presentationMode == .contextPreview {
            customNavigationBar.isUserInteractionEnabled = false
            customNavigationBar.setBackButtonHidden(true)
        }
        view.addSubview(customNavigationBar)
        navigationBarHeightConstraint = customNavigationBar.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + TelegramChatNavigationBar.contentHeight,
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
        pinnedMessageBanner.translatesAutoresizingMaskIntoConstraints = false
        pinnedMessageBanner.isHidden = true
        view.addSubview(pinnedMessageBanner)
        pinnedMessageBannerHeightConstraint = pinnedMessageBanner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            pinnedMessageBanner.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            pinnedMessageBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pinnedMessageBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pinnedMessageBannerHeightConstraint,
        ])
        updatePinnedMessageBanner(animated: false)
    }

    private func configureCollectionView() {
        historyContainerView.translatesAutoresizingMaskIntoConstraints = false
        historyContainerView.transform = CGAffineTransform(scaleX: 1, y: -1)
        view.addSubview(historyContainerView)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
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
        if presentationMode == .full {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(historyTapped(_:)))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delegate = self
            collectionView.addGestureRecognizer(tapGesture)
            messageContextGesture.delegate = self
            collectionView.addGestureRecognizer(messageContextGesture)
        }
        historyContainerView.addSubview(collectionView)
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
            composerView.onPickPhotos = { [weak self] in self?.showPhotoPicker() }
            composerView.onTakePhoto = { [weak self] in self?.showCamera() }
            composerView.onNavigateToMessage = { [weak self] target in self?.navigate(to: target) }
            composerView.onVoiceGestureActivityChange = { [weak self] active in
                guard let self, voiceGestureDefersSystemGestures != active else { return }
                voiceGestureDefersSystemGestures = active
                setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
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
            composerView.onUpdateVideoNoteTrim = { [weak self] start, end, updatedEnd, finished in
                self?.videoNoteRecorder?.updateTrim(
                    start: start,
                    end: end,
                    updatedEnd: updatedEnd,
                    finished: finished,
                )
            }
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
            ])
        }
        if presentationMode == .full {
            configureScrollToLatestButton(bottomAnchor: showsComposer
                ? composerView.topAnchor
                : view.safeAreaLayoutGuide.bottomAnchor)
            configureMessageSelectionToolbar()
        }
        NSLayoutConstraint.activate(constraints)
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
            title: "Trim voice recording?",
            message: "Audio outside the selected range will be removed before recording continues.",
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Trim and Continue", style: .destructive) { [weak self] _ in
            self?.chatVM.resumeVoiceRecording(confirmingTrim: true)
        })
        present(alert, animated: true)
    }

    private func beginVideoNoteRecording() async -> Bool {
        if let videoNoteRecorder {
            return await videoNoteRecorder.beginHolding()
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
                if !videoNoteChatActionActive {
                    videoNoteChatActionActive = true
                    Task { [weak self] in
                        guard let self else { return }
                        _ = try? await chatVM.tdSendFrozenMediaChatAction(
                            .chatActionRecordingVideoNote,
                            sendTopic: videoNoteSendTopic,
                            replyTo: videoNoteReplyInput,
                        )
                    }
                }
            case .failed(let message):
                stopVideoNoteChatAction()
                presentVideoNoteErrorIfNeeded(message)
            case .idle, .preview, .sending:
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
                    message: "The chat was closed before the video message could be sent.",
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
        view.insertSubview(recorder.view, belowSubview: composerView)
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
        let alert = UIAlertController(title: "Video Message", message: message, preferredStyle: .alert)
        if videoNoteRecorder?.hasPersistedRecordingDraft == true {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
                self?.didPresentVideoNoteError = false
                self?.videoNoteRecorder?.retryPersistedPreview()
            })
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                self?.didPresentVideoNoteError = false
                self?.videoNoteRecorder?.cancel()
            })
            present(alert, animated: true)
            return
        }
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
            self?.didPresentVideoNoteError = false
            if self?.videoNoteRecorder?.state.isActive != true {
                self?.videoNoteRecorder?.cancel()
            }
        })
        if message.localizedCaseInsensitiveContains("access") {
            alert.addAction(UIAlertAction(title: "Settings", style: .default) { [weak self] _ in
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
        let alert = UIAlertController(title: "Video Message", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.didPresentVideoNoteError = false
        })
        present(alert, animated: true)
    }

    private func stopVideoNoteChatAction() {
        guard videoNoteChatActionActive else { return }
        videoNoteChatActionActive = false
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
        scrollToLatestButton.alpha = 0
        scrollToLatestButton.transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.72, y: 0.72)
        scrollToLatestButton.accessibilityLabel = "Scroll to latest message"
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
    }

    private func updateScrollToLatestButtonVisibility(animated: Bool) {
        let isAwayFromLatest = collectionView.contentOffset.y + collectionView.adjustedContentInset.top > 160
        let visible = isAwayFromLatest && !messageSearchActive && !isSelectingMessages
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
            guard let self else { return UICollectionViewCell() }
            switch itemID {
            case .dateHeader(let headerID):
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ChatDateHeaderCell.reuseIdentifier,
                    for: indexPath,
                ) as? ChatDateHeaderCell else { return UICollectionViewCell() }
                cell.configure(id: headerID)
                return cell
            case .topicHeader(let headerID):
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ForumTopicRunHeaderCell.reuseIdentifier,
                    for: indexPath,
                ) as? ForumTopicRunHeaderCell else { return UICollectionViewCell() }
                cell.configure(
                    id: headerID,
                    info: chatVM.forumTopic(id: headerID.topicID)?.info,
                    client: chatVM.client,
                    onOpen: { [weak self] in self?.openForumTopic(id: headerID.topicID) },
                )
                return cell
            case .message(let displayedMessageID):
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: MessageCell.reuseIdentifier,
                    for: indexPath,
                ) as? MessageCell,
                    let message = message(for: displayedMessageID)
                else { return UICollectionViewCell() }
                let messageSelectable = canSelectMessage(message)
                cell.configure(
                    message: message,
                    chat: chatVM.customChat,
                    highlighted: message.sourceMessages.contains(where: {
                        $0.id == self.chatVM.highlightedMessageId
                    }),
                    client: chatVM.client,
                    pollInteractionStore: chatVM.pollInteractionStore,
                    videoPlaybackOwners: inlineVideoPlaybackOwners(for: message),
                    canAddReactions: chatVM.canAddReactions,
                    selectionActive: isSelectingMessages && messageSelectable,
                    selected: selectedDisplayedMessageIDs.contains(displayedMessageID),
                    onSwipeToReply: presentationMode == .full
                        && !isSelectingMessages
                        && !chatVM.isReadOnlyTopic
                        && message.properties.canBeReplied
                        ? { [weak self] in self?.chatVM.beginReply(to: message) }
                        : nil,
                    onSelectionToggle: isSelectingMessages && messageSelectable
                        ? { [weak self] in self?.toggleMessageSelection(displayedMessageID: displayedMessageID) }
                        : nil,
                    onReactionTap: { [weak self] type in
                        guard let self,
                              presentationMode == .full,
                              !isSelectingMessages,
                              !chatVM.isReadOnlyTopic
                        else { return }
                        chatVM.toggleReaction(on: message, type: type, isBig: false)
                    },
                    onMetadataNavigate: { [weak self] target in
                        guard self?.presentationMode == .full,
                              self?.isSelectingMessages == false
                        else { return }
                        self?.navigate(to: target)
                    },
                    onReplyQuoteExpand: { [weak self] in
                        self?.expandReplyQuote(for: message)
                    },
                    onContentAction: { [weak self] action in
                        guard self?.presentationMode == .full,
                              self?.isSelectingMessages == false
                        else { return }
                        self?.performContentAction(action)
                    },
                    onMediaTap: { [weak self] messages, selection in
                        guard self?.presentationMode == .full,
                              self?.isSelectingMessages == false
                        else { return }
                        self?.showMedia(messages, selection: selection)
                    },
                )
                cell.onSelfSizingHeightChange = { [weak self] in
                    self?.messageCellWillChangeHeight()
                }
                message.sourceMessages.forEach { self.pendingInlineVideoOwnerReturns.remove($0.id) }
                return cell
            }
        }
    }

    private func observeState() {
        chatVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    updateStatus()
                    if showsComposer {
                        if !chatVM.canWriteAnyMessage {
                            composerView.cancelActiveRecordingGesture()
                        }
                        composerView.update(from: chatVM)
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
                    restoreVideoRecordingIfNeeded()
                }
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
        subscribeToMessages()
    }

    private func updateChatHeader() {
        let chat = chatVM.customChat.chat
        let title = chatVM.forumTopicInfo?.name ?? chatVM.customChat.displayTitle
        let status =
            if location.isTopicScoped {
                chatVM.isReadOnlyTopic
                    ? (chatVM.forumTopicInfo?.isClosed == true || chatVM.forumTopicInfo?.isHidden == true
                        ? "Closed topic · Read-only"
                        : "\(chatVM.customChat.displayTitle) · Read-only")
                    : chatVM.customChat.displayTitle
            } else {
                chatVM.actionStatus.isEmpty ? chatVM.onlineStatus : chatVM.actionStatus
            }
        let statusColor: UIColor = !chatVM.actionStatus.isEmpty || status == "online" ? .systemBlue : .secondaryLabel
        customNavigationBar.configure(
            title: title,
            status: status,
            statusColor: statusColor,
        )
        customNavigationBar.configureAvatar(
            file: chat.photo?.big,
            minithumbnail: chat.photo?.minithumbnail,
            placeholder: chatVM.customChat.telegramAvatarPlaceholder,
        )
    }

    private func subscribeToMessages() {
        messageCancellables.removeAll()
        for message in chatVM.messages {
            message.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self, messageID = message.id] in
                    DispatchQueue.main.async { self?.reconfigureMessage(id: messageID) }
                }
                .store(in: &messageCancellables)
        }
    }

    private func updateStatus() {
        let title = chatVM.forumTopicInfo?.name ?? chatVM.customChat.displayTitle
        let status =
            if location.isTopicScoped {
                chatVM.isReadOnlyTopic
                    ? (chatVM.forumTopicInfo?.isClosed == true || chatVM.forumTopicInfo?.isHidden == true
                        ? "Closed topic · Read-only"
                        : "\(chatVM.customChat.displayTitle) · Read-only")
                    : chatVM.customChat.displayTitle
            } else {
                chatVM.actionStatus.isEmpty ? chatVM.onlineStatus : chatVM.actionStatus
            }
        let statusColor: UIColor = !chatVM.actionStatus.isEmpty || status == "online" ? .systemBlue : .secondaryLabel
        customNavigationBar.configure(
            title: title,
            status: status,
            statusColor: statusColor,
        )
        let unreadCount = location.isTopicScoped
            ? (chatVM.forumTopic?.unreadCount ?? 0)
            : chatVM.customChat.unreadCount
        unreadBadgeLabel.text = unreadCount > 0 ? compactNumericCountString(unreadCount) : nil
        unreadBadgeLabel.isHidden = unreadCount == 0
        scrollToLatestButton.accessibilityValue = unreadCount == 0 ? nil : "\(unreadCount) unread"
    }

    private func updatePinnedMessageBanner(animated: Bool) {
        guard pinnedMessageBannerHeightConstraint != nil else { return }
        let message: Message? =
            if presentationMode == .full,
            !messageSearchActive,
            !isSelectingMessages {
                chatVM.visiblePinnedMessage
            } else {
                nil
            }
        if let message {
            if displayedPinnedMessage != message {
                displayedPinnedMessage = message
                pinnedMessageBanner.configure(
                    message: message,
                    onOpen: { [weak self] in
                        self?.scrollToMessage(id: message.id)
                    },
                    onHide: { [weak self] in
                        self?.chatVM.hidePinnedMessageBanner()
                    },
                )
            }
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
                displayedPinnedMessage = nil
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
        guard isViewLoaded else { return }
        if deferSnapshotForDeleteTransitionIfNeeded() {
            return
        }
        subscribeToMessages()
        if isSelectingMessages {
            let displayedIDs = Set(chatVM.messages.map(\.displayedID))
            selectedDisplayedMessageIDs.formIntersection(displayedIDs)
            if selectedDisplayedMessageIDs.isEmpty {
                endMessageSelection(reconfigure: false)
            } else {
                updateMessageSelectionChrome(reconfigureIDs: [])
            }
        }
        let shouldKeepLatestVisible = !didPerformInitialScroll || isNearLatest
        let anchor = shouldKeepLatestVisible ? nil : captureSnapshotAnchor()
        let itemIDs = ChatTimelineProjection.items(
            messages: chatVM.messages,
            includesTopicHeaders: chatVM.isAllMessagesForum,
        )
        var snapshot = NSDiffableDataSourceSnapshot<Section, ChatTimelineItemID>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(itemIDs)
        let headerIDs = itemIDs.filter {
            if case .dateHeader = $0 {
                true
            } else if case .topicHeader = $0 {
                true
            } else {
                false
            }
        }
        snapshot.reconfigureItems(headerIDs)
        timelineLayoutMutationDepth += 1
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }
            defer { timelineLayoutMutationDepth -= 1 }
            collectionView.layoutIfNeeded()
            if let pendingScrollMessageID {
                let quote = pendingQuoteHighlight
                let quoteTargetMessageID = pendingQuoteTargetMessageID
                self.pendingScrollMessageID = nil
                pendingQuoteHighlight = nil
                pendingQuoteTargetMessageID = nil
                scrollToLoadedMessage(
                    id: pendingScrollMessageID,
                    quote: quote,
                    quoteTargetMessageID: quoteTargetMessageID,
                )
            } else if shouldKeepLatestVisible {
                scrollToLatestMessage(animated: false)
            } else if let anchor {
                restoreSnapshotAnchor(anchor)
            }
            performPendingComposerSendTransitions()
            didPerformInitialScroll = true
        }
        collectionView.backgroundView = chatVM.messages.isEmpty ? emptyLabel() : nil
    }

    private func prepareDeleteTransition(for ids: Set<DisplayedMessageID>) {
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
                cell.alpha = 0
                cell.transform = CGAffineTransform(translationX: horizontalOffset, y: 0)
                    .scaledBy(x: 0.98, y: 0.98)
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
            updateSnapshot(animated: true)
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
        DispatchQueue.main.async { [weak self] in self?.performPendingComposerSendTransitions() }
    }

    private func cancelComposerSendTransition(id: UUID) {
        guard let transition = pendingComposerSendTransitions.removeValue(forKey: id) else { return }
        transition.timeout.cancel()
        transition.snapshots.forEach { $0.view.removeFromSuperview() }
    }

    private func replacePendingComposerSendMessageID(old: Int64, new: Int64) {
        sendTransitionMessageIDAliases[old] = new
        if sendTransitionMessageIDAliases.count > 128,
           let oldestKey = sendTransitionMessageIDAliases.keys.first
        {
            sendTransitionMessageIDAliases[oldestKey] = nil
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
        guard isViewLoaded else { return }
        collectionView.layoutIfNeeded()
        for (id, transition) in pendingComposerSendTransitions where !transition.messageIDs.isEmpty {
            guard let displayedID = transition.messageIDs
                .lazy
                .compactMap({
                    self.chatVM.displayedMessageID(containing: $0)
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
            snapshot.frame = source.sourceFrame
            snapshot.layer.cornerCurve = .continuous
            snapshot.layer.cornerRadius = min(12, snapshot.bounds.height / 2)
            snapshot.clipsToBounds = true
            view.addSubview(snapshot)
            UIView.animate(
                withDuration: 0.32,
                delay: Double(index) * 0.025,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
            ) {
                snapshot.frame = destination
                snapshot.alpha = 0
                snapshot.layer.cornerRadius = min(8, destination.height / 2)
            } completion: { _ in
                snapshot.removeFromSuperview()
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

    private func restoreSnapshotAnchor(_ anchor: SnapshotAnchor) {
        guard let indexPath = dataSource.indexPath(for: anchor.itemID),
              let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
        else { return }
        let insets = collectionView.adjustedContentInset
        let minimumOffset = -insets.top
        let maximumOffset = max(
            minimumOffset,
            collectionView.contentSize.height - collectionView.bounds.height + insets.bottom,
        )
        let desiredOffset = attributes.frame.minY - anchor.minYRelativeToViewport
        collectionView.setContentOffset(
            CGPoint(
                x: collectionView.contentOffset.x,
                y: min(max(desiredOffset, minimumOffset), maximumOffset),
            ),
            animated: false,
        )
    }

    private func messageCellWillChangeHeight() {
        let userIsScrolling = collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
        guard didPerformInitialScroll,
              timelineLayoutMutationDepth == 0,
              !userIsScrolling
        else { return }
        if isNearLatest {
            pendingSelfSizingKeepsLatest = true
        } else if pendingSelfSizingAnchor == nil {
            pendingSelfSizingAnchor = captureSnapshotAnchor(ensuringLayout: false)
        }
        guard !selfSizingAnchorRestoreScheduled else { return }
        selfSizingAnchorRestoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard timelineLayoutMutationDepth == 0 else {
                pendingSelfSizingAnchor = nil
                pendingSelfSizingKeepsLatest = false
                selfSizingAnchorRestoreScheduled = false
                return
            }
            let anchor = pendingSelfSizingAnchor
            let keepLatest = pendingSelfSizingKeepsLatest
            pendingSelfSizingAnchor = nil
            pendingSelfSizingKeepsLatest = false
            selfSizingAnchorRestoreScheduled = false
            let userIsScrolling = collectionView.isTracking
                || collectionView.isDragging
                || collectionView.isDecelerating
            guard !userIsScrolling else { return }
            timelineLayoutMutationDepth += 1
            defer { timelineLayoutMutationDepth -= 1 }
            collectionView.layoutIfNeeded()
            if keepLatest {
                pinToLatestEdge(animated: false)
            } else if let anchor {
                restoreSnapshotAnchor(anchor)
            }
        }
    }

    private func reconfigureMessage(id: Int64) {
        guard let displayedID = chatVM.displayedMessageID(containing: id) else { return }
        let itemID = ChatTimelineItemID.message(displayedID)
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(itemID) != nil else { return }
        let userIsScrolling = collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
        let keepLatest = !userIsScrolling && isNearLatest
        let anchor = !userIsScrolling && !keepLatest ? captureSnapshotAnchor() : nil
        snapshot.reconfigureItems([itemID])
        timelineLayoutMutationDepth += 1
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            defer { timelineLayoutMutationDepth -= 1 }
            collectionView.layoutIfNeeded()
            if keepLatest {
                pinToLatestEdge(animated: false)
            } else if let anchor {
                restoreSnapshotAnchor(anchor)
            }
        }
    }

    private func updateHighlightState() {
        let changed = Array(Set([lastHighlightedMessageID, chatVM.highlightedMessageId].compactMap(\.self)))
        lastHighlightedMessageID = chatVM.highlightedMessageId
        guard !changed.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        let presentIdentifiers = changed.compactMap { id -> ChatTimelineItemID? in
            guard let displayedID = chatVM.displayedMessageID(containing: id) else { return nil }
            let itemID = ChatTimelineItemID.message(displayedID)
            return snapshot.indexOfItem(itemID) == nil ? nil : itemID
        }
        guard !presentIdentifiers.isEmpty else { return }
        snapshot.reconfigureItems(presentIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func emptyLabel() -> UIView {
        let label = UILabel()
        label.text = "No messages"
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.transform = CGAffineTransform(scaleX: 1, y: -1)
        return label
    }

    private func updateHistoryInsets() {
        let visualBottomInset: CGFloat =
            if isSelectingMessages, messageSelectionToolbar.frame.minY > 0 {
                view.bounds.maxY - messageSelectionToolbar.frame.minY + 8
            } else if messageSearchActive {
                max(
                    view.safeAreaInsets.bottom,
                    view.bounds.maxY - view.keyboardLayoutGuide.layoutFrame.minY,
                ) + 8
            } else if showsComposer, composerView.frame.minY > 0 {
                max(view.safeAreaInsets.bottom, view.bounds.maxY - composerView.frame.minY) + 10
            } else {
                view.safeAreaInsets.bottom + 8
            }
        let visualTopInset = (
            pinnedMessageBannerHeightConstraint?.constant ?? 0,
        ) > 0
            ? pinnedMessageBanner.frame.maxY + 8
            : customNavigationBar.frame.maxY + 8
        let updatedInsets = UIEdgeInsets(top: visualBottomInset, left: 0, bottom: visualTopInset, right: 0)
        guard abs(collectionView.contentInset.top - updatedInsets.top) > 0.5
            || abs(collectionView.contentInset.bottom - updatedInsets.bottom) > 0.5
        else { return }

        let userIsScrolling = collectionView.isTracking || collectionView.isDragging || collectionView.isDecelerating
        let keepLatestVisible = !didPerformInitialScroll || (!userIsScrolling && isNearLatest)
        let previousOffset = collectionView.contentOffset
        let anchor = !userIsScrolling && !keepLatestVisible ? captureSnapshotAnchor() : nil
        timelineLayoutMutationDepth += 1
        defer { timelineLayoutMutationDepth -= 1 }
        collectionView.contentInset = updatedInsets
        collectionView.verticalScrollIndicatorInsets = updatedInsets
        collectionView.layoutIfNeeded()
        if keepLatestVisible {
            pinToLatestEdge(animated: false)
        } else if let anchor {
            restoreSnapshotAnchor(anchor)
        } else {
            collectionView.setContentOffset(previousOffset, animated: false)
        }
    }

    private func invalidateSelfSizingLayoutPreservingAnchor() {
        guard isViewLoaded, didPerformInitialScroll else { return }
        let userIsScrolling = collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
        let keepLatest = !userIsScrolling && isNearLatest
        let anchor = !userIsScrolling && !keepLatest ? captureSnapshotAnchor() : nil
        timelineLayoutMutationDepth += 1
        defer { timelineLayoutMutationDepth -= 1 }
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        if keepLatest {
            pinToLatestEdge(animated: false)
        } else if let anchor {
            restoreSnapshotAnchor(anchor)
        }
    }

    private func updateComposerFloatingState(_ keyboardAttached: Bool) {
        guard composerKeyboardAttached != keyboardAttached else { return }
        composerKeyboardAttached = keyboardAttached
        composerLeadingConstraint?.constant = keyboardAttached ? 8 : 0
        composerTrailingConstraint?.constant = keyboardAttached ? -8 : 0
        composerBottomConstraint?.constant = keyboardAttached ? -8 : 0
    }

    private func message(for id: DisplayedMessageID) -> CustomMessage? {
        chatVM.messages.first(where: { $0.displayedID == id })
    }

    private func scrollToMessage(id: Int64, quote: MessageQuoteHighlight? = nil) {
        messageNavigationTask?.cancel()
        messageNavigationTask = nil
        pendingQuoteDestination = nil
        pendingScrollMessageID = nil
        pendingQuoteHighlight = nil
        pendingQuoteTargetMessageID = nil
        if let displayedID = chatVM.displayedMessageID(containing: id) {
            scrollToLoadedMessage(id: displayedID, quote: quote, quoteTargetMessageID: id)
            return
        }
        messageNavigationTask = Task { [weak self] in
            guard let self,
                  let window = await chatVM.prepareMessageWindow(around: id),
                  !Task.isCancelled
            else { return }
            pendingScrollMessageID = window.displayedMessageID
            pendingQuoteHighlight = quote
            pendingQuoteTargetMessageID = id
            chatVM.applyMessageWindow(window)
            messageNavigationTask = nil
        }
    }

    private func scrollToLoadedMessage(
        id: DisplayedMessageID,
        quote: MessageQuoteHighlight? = nil,
        quoteTargetMessageID: Int64? = nil,
    ) {
        let itemID = ChatTimelineItemID.message(id)
        guard let indexPath = dataSource.indexPath(for: itemID) else {
            pendingScrollMessageID = id
            pendingQuoteHighlight = quote
            pendingQuoteTargetMessageID = quoteTargetMessageID
            updateSnapshot(animated: false)
            return
        }
        collectionView.layoutIfNeeded()
        if let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) {
            let insets = collectionView.adjustedContentInset
            let visibleCenterOffset = (collectionView.bounds.height + insets.top - insets.bottom) / 2
            let desiredOffset = attributes.center.y - visibleCenterOffset
            let minimumOffset = -insets.top
            let maximumOffset = max(
                minimumOffset,
                collectionView.contentSize.height - collectionView.bounds.height + insets.bottom,
            )
            collectionView.setContentOffset(
                CGPoint(
                    x: collectionView.contentOffset.x,
                    y: min(max(desiredOffset, minimumOffset), maximumOffset),
                ),
                animated: true,
            )
        } else {
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
        }

        messageHighlightTask?.cancel()
        chatVM.highlightedMessageId = quoteTargetMessageID ?? message(for: id)?.message.id
        updateHighlightState()
        messageHighlightTask = Task { [weak self, weak chatVM] in
            try? await Task<Never, Never>.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            chatVM?.highlightedMessageId = nil
            self?.updateHighlightState()
            self?.messageHighlightTask = nil
        }
        if let quote, let quoteTargetMessageID {
            pendingQuoteDestination = PendingQuoteDestination(
                displayedMessageID: id,
                quote: quote,
                targetMessageID: quoteTargetMessageID,
            )
            if let cell = collectionView.cellForItem(at: indexPath) as? MessageCell {
                applyPendingQuoteHighlight(to: cell, displayedMessageID: id)
            }
        }
    }

    private func applyPendingQuoteHighlight(to cell: MessageCell, displayedMessageID: DisplayedMessageID) {
        guard let destination = pendingQuoteDestination,
              destination.displayedMessageID == displayedMessageID
        else { return }
        pendingQuoteDestination = nil
        guard message(for: displayedMessageID)?.sourceMessages.contains(where: {
            $0.id == destination.targetMessageID
        }) == true else { return }
        cell.highlightQuote(destination.quote)
    }

    private func showMedia(_ messages: [Message], selection: Int64) {
        let transferredOwner = inlineVideoPlaybackOwners[selection]
        let transferredOwners = messages.compactMap { inlineVideoPlaybackOwners[$0.id] }
        let transitionSource = galleryTransitionTarget(for: selection)
        pauseInlineVideoPlayback(excluding: transferredOwner?.messageID)
        present(
            MediaGalleryViewController(
                messages: messages,
                selection: selection,
                tdlib: tdlib,
                transferredPlaybackOwner: transferredOwner,
                transferredPlaybackOwners: transferredOwners,
                transitionSource: transitionSource,
                transitionSourceProvider: { [weak self] messageID in
                    self?.galleryTransitionTarget(for: messageID)
                },
            ),
            animated: true,
        )
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
            guard case .messageTopicForum(let forumTopic) = message.topicId,
                  let topic = try? await client.getForumTopic(
                      chatId: currentLocation.chatID,
                      forumTopicId: forumTopic.forumTopicId,
                  )
            else {
                presentMetadataUnavailable()
                return
            }
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
            title: "Message Unavailable",
            message: "The original chat or message can’t be opened.",
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func expandReplyQuote(for message: CustomMessage) {
        let itemID = ChatTimelineItemID.message(message.displayedID)
        guard !message.isReplyQuoteExpanded,
              let indexPath = dataSource.indexPath(for: itemID)
        else { return }
        collectionView.layoutIfNeeded()
        let oldFrame = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
        let oldOffset = collectionView.contentOffset
        message.isReplyQuoteExpanded = true
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([itemID])
        timelineLayoutMutationDepth += 1
        UIView.performWithoutAnimation {
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                defer { timelineLayoutMutationDepth -= 1 }
                collectionView.layoutIfNeeded()
                guard let oldFrame,
                      let newFrame = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
                else { return }
                collectionView.setContentOffset(
                    CGPoint(x: oldOffset.x, y: oldOffset.y + newFrame.minY - oldFrame.minY),
                    animated: false,
                )
            }
        }
    }

    private func performContentAction(_ action: MessageContentAction) {
        switch action {
        case .openContact(let contact):
            let details = TelegramContactDetailsViewController(contact: contact)
            let navigation = UINavigationController(rootViewController: details)
            navigation.modalPresentationStyle = .pageSheet
            present(navigation, animated: true)
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
        case .openLocation(let location, let title):
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "ll", value: "\(location.latitude),\(location.longitude)"),
                URLQueryItem(name: "q", value: title),
            ]
            if let url = components?.url {
                UIApplication.shared.open(url)
            }
        case .submitPollAnswer(let messageID, let optionIDs):
            chatVM.submitPollAnswer(messageID: messageID, optionIDs: optionIDs)
        }
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

    private func inlineVideoPlaybackOwner(for message: Message) -> GalleryVideoPlaybackOwner? {
        guard case .messageVideo(let video) = message.content, !video.isSecret else { return nil }
        if let owner = inlineVideoPlaybackOwners[message.id], !owner.isDeleted {
            return owner
        }
        guard let owner = GalleryVideoPlaybackOwner(
            message: message,
            tdlib: tdlib,
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
                  let message = message(for: displayedMessageID),
                  let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
            else { continue }
            for owner in inlineVideoPlaybackOwners(for: message).values
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
        let activeMessageID = collectionView.indexPathsForVisibleItems
            .flatMap { indexPath in
                (collectionView.cellForItem(at: indexPath) as? MessageCell)?
                    .inlineVideoPlaybackCandidates(in: collectionView) ?? []
            }
            .compactMap { messageID, frame -> (Int64, CGFloat)? in
                guard inlineVideoPlaybackOwners[messageID] != nil else { return nil }
                let intersection = visibleRect.intersection(frame)
                guard !intersection.isNull, !intersection.isEmpty else { return nil }
                return (messageID, intersection.width * intersection.height)
            }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
        for (messageID, owner) in inlineVideoPlaybackOwners where !owner.isAttachedToGallery {
            owner.setPlaybackVisible(messageID == activeMessageID)
        }
    }

    @objc private func scrollToLatest() {
        scrollToLatestMessage(animated: true)
    }

    private func scrollToLatestMessage(animated: Bool) {
        guard dataSource.snapshot().numberOfItems > 0 else { return }
        pinToLatestEdge(animated: animated)
    }

    private func pinToLatestEdge(animated: Bool) {
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
            animated: animated,
        )
    }

    private func searchMessages(query: String) {
        searchTask?.cancel()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            customNavigationBar.setSearchResultFound(nil)
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            let client = chatVM.client
            let location = chatVM.location
            let result = try? await client.searchChatMessages(
                chatId: location.chatID,
                filter: nil,
                fromMessageId: 0,
                limit: 50,
                offset: 0,
                query: normalizedQuery,
                senderId: nil,
                topicId: location.topic,
            )
            guard !Task.isCancelled,
                  TDLib.shared.activeAccountID == location.accountID,
                  TDLib.shared.activeClient.id == location.clientID
            else { return }
            let firstID = result?.messages.first(where: { location.matches(message: $0) })?.id
            customNavigationBar.setSearchResultFound(firstID != nil)
            if let firstID {
                scrollToMessage(id: firstID)
            }
        }
    }

    private func showPhotoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 10
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func showCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            let alert = UIAlertController(title: "Camera unavailable", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let picker = UIImagePickerController()
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
            title: "Microphone Access Required",
            message: "Enable Microphone in Settings → BetterTG to record voice messages.",
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.didPresentMicrophoneError = false
        })
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { [weak self] _ in
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
        let alert = UIAlertController(title: "Voice Message", message: message, preferredStyle: .alert)
        if chatVM.hasPendingVoiceNote {
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                self?.didPresentVoiceNoteError = false
                self?.chatVM.discardPendingVoiceNote()
            })
            alert.addAction(UIAlertAction(title: "Keep", style: .cancel) { [weak self] _ in
                self?.didPresentVoiceNoteError = false
            })
            if chatVM.canRetryPendingVoiceNote {
                alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
                    self?.didPresentVoiceNoteError = false
                    self?.chatVM.retryPendingVoiceNote()
                })
            }
        } else {
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
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
        let alert = UIAlertController(title: "Video Message", message: message, preferredStyle: .alert)
        if chatVM.hasPendingVideoNote {
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                self?.didPresentVideoNoteError = false
                self?.chatVM.discardPendingVideoNote()
            })
            alert.addAction(UIAlertAction(title: "Keep", style: .cancel) { [weak self] _ in
                self?.didPresentVideoNoteError = false
            })
            if chatVM.canRetryPendingVideoNote {
                alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
                    self?.didPresentVideoNoteError = false
                    self?.chatVM.retryPendingVideoNote()
                })
            }
        } else {
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
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
        let alert = UIAlertController(title: "Reaction", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
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
        let alert = UIAlertController(title: "Message", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
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
        let alert = UIAlertController(title: "Draft", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
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
        let alert = UIAlertController(title: "Pinned Message", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.didPresentPinError = false
        })
        present(alert, animated: true)
    }

    @objc private func messageLongPressed(_ gesture: TelegramContextGestureRecognizer) {
        guard gesture.state == .began, !isSelectingMessages else { return }
        cancelHistoryPanGesture()
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              case .message(let displayedMessageID) = dataSource.itemIdentifier(for: indexPath),
              let message = message(for: displayedMessageID),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
        else { return }
        let baseTransform = pressedMessageSourceView === cell.contextPreviewView
            ? pressedMessageSourceTransform
            : cell.contextPreviewView.transform
        let presented = presentTelegramContextMenu(
            sourceView: cell.contextPreviewView,
            actions: menu(for: message),
            tracking: gesture,
            sourceBaseTransform: baseTransform,
            performsInitialFeedback: false,
        )
        if !presented {
            restorePressedMessageSource()
        }
    }

    @objc private func historyTapped(_: UITapGestureRecognizer) {
        view.endEditing(true)
    }

    private func cancelHistoryPanGesture() {
        let panGesture = collectionView.panGestureRecognizer
        guard panGesture.state == .began || panGesture.state == .changed else { return }
        panGesture.isEnabled = false
        panGesture.isEnabled = true
    }

    private func restorePressedMessageSource() {
        guard let sourceView = pressedMessageSourceView else { return }
        let transform = pressedMessageSourceTransform
        pressedMessageSourceView = nil
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
        ) {
            sourceView.transform = transform
        }
    }

    private func menu(for message: CustomMessage) -> [TelegramContextMenuAction] {
        if chatVM.isReadOnlyTopic {
            var readOnlyActions = [TelegramContextMenuAction]()
            if message.properties.canBeCopied,
               let text = formattedText(from: message.message.content)
            {
                readOnlyActions.append(TelegramContextMenuAction(
                    title: "Copy",
                    image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
                ) { UIPasteboard.setFormattedText(text) })
            }
            return readOnlyActions
        }
        var elements = [TelegramContextMenuAction]()
        if message.properties.canBeReplied {
            elements
                .append(TelegramContextMenuAction(
                    title: "Reply",
                    image: UIImage(systemName: "arrowshape.turn.up.left"),
                ) { [weak self] in
                    self?.chatVM.beginReply(to: message)
                })
            if formattedText(from: message.message.content)?.text.isEmpty == false {
                elements.append(TelegramContextMenuAction(
                    title: "Quote",
                    image: UIImage(systemName: "quote.opening"),
                ) { [weak self] in
                    self?.chatVM.beginQuoteReply(to: message)
                })
            }
        }
        if message.properties.canBeEdited {
            elements.append(TelegramContextMenuAction(
                title: "Edit",
                image: UIImage(systemName: "square.and.pencil"),
            ) { [weak self] in
                self?.chatVM.editCustomMessage = message
                self?.chatVM.setEditMessageText(from: message.message)
            })
        }
        if message.properties.canBeCopied,
           let text = formattedText(from: message.message.content)
        {
            elements.append(TelegramContextMenuAction(
                title: "Copy",
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            ) { UIPasteboard.setFormattedText(text) })
        }
        if canOfferReactionPicker(for: message) {
            elements.append(TelegramContextMenuAction(
                title: "React",
                image: UIImage(systemName: "face.smiling"),
            ) { [weak self, weak message] in
                guard let message else { return }
                self?.presentReactionPicker(for: message)
            })
        }
        if canOfferPinAction(for: message) {
            elements.append(TelegramContextMenuAction(
                title: message.isPinned ? "Unpin" : "Pin",
                image: UIImage(systemName: message.isPinned ? "pin.slash" : "pin"),
            ) { [weak self, weak message] in
                guard let message else { return }
                if message.isPinned {
                    self?.presentUnpinConfirmation(for: message)
                } else {
                    self?.presentPinOptions(for: message)
                }
            })
        }
        if canForwardMessageContent(message),
           message.properties.canBeForwarded || message.properties.canBeCopied
        {
            elements.append(TelegramContextMenuAction(
                title: "Forward",
                image: UIImage(systemName: "arrowshape.turn.up.right"),
                startsNewSection: true,
            ) { [weak self] in
                self?.presentForwardPicker(forDisplayedMessageIDs: [message.displayedID])
            })
        }
        if canSelectMessage(message) {
            elements.append(TelegramContextMenuAction(
                title: "Select",
                image: UIImage(systemName: "checkmark.circle"),
            ) { [weak self] in
                self?.beginMessageSelection(with: message.displayedID)
            })
        }

        let deleteSelf = TelegramContextMenuAction(
            title: "Delete only for me",
            image: UIImage(systemName: "trash"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: false) }
        let deleteAll = TelegramContextMenuAction(
            title: "Delete for both",
            image: UIImage(systemName: "trash.fill"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: true) }
        if message.properties.canBeDeletedOnlyForSelf, message.properties.canBeDeletedForAllUsers {
            elements.append(deleteSelf)
            elements.append(TelegramContextMenuAction(
                title: deleteAll.title,
                image: deleteAll.image,
                isDestructive: true,
            ) { [weak self] in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: true) })
        } else if message.properties.canBeDeletedForAllUsers {
            elements.append(deleteAll)
        } else if message.properties.canBeDeletedOnlyForSelf {
            elements.append(deleteSelf)
        }
        return elements
    }

    private func beginMessageSelection(with displayedMessageID: DisplayedMessageID) {
        guard presentationMode == .full,
              let message = message(for: displayedMessageID),
              canSelectMessage(message)
        else { return }
        view.endEditing(true)
        isSelectingMessages = true
        selectedDisplayedMessageIDs = [displayedMessageID]
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
            if sourceMessageIDs(forDisplayedMessageIDs: proposedIDs).count > 100 {
                let alert = UIAlertController(
                    title: "Selection Limit",
                    message: MessageForwardingError.tooManyMessages(
                        sourceMessageIDs(forDisplayedMessageIDs: proposedIDs).count,
                    )
                    .localizedDescription,
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
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

    private func endMessageSelection(reconfigure: Bool = true) {
        guard isSelectingMessages else { return }
        selectionCapabilityTask?.cancel()
        selectionCapabilityTask = nil
        selectionCapabilityGeneration = nil
        let previouslySelected = selectedDisplayedMessageIDs
        isSelectingMessages = false
        selectedDisplayedMessageIDs.removeAll()
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
            reconfigureMessages(ids: Array(previouslySelected))
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
        let canForward = sourceIDs.count <= 100
            && messages.allSatisfy { canForwardMessageContent($0) }
            && (messages.allSatisfy(\.properties.canBeForwarded)
                || messages.allSatisfy(\.properties.canBeCopied))
        let canDelete = messages.allSatisfy {
            $0.properties.canBeDeletedOnlyForSelf || $0.properties.canBeDeletedForAllUsers
        }
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
            && message.message.topicId == nil
            && !message.contentPresentation.isService
            && message.message.sendingState == nil
            && message.properties.canBePinned
    }

    private func presentPinOptions(for message: CustomMessage) {
        guard canOfferPinAction(for: message),
              presentedViewController == nil
        else { return }
        let alertMessage = chatVM.pinnedMessage != nil
            ? "This message will become the newest pinned message."
            : nil
        let alert = UIAlertController(
            title: "Pin Message?",
            message: alertMessage,
            preferredStyle: .actionSheet,
        )
        if chatVM.customChat.isSavedMessages {
            alert.addAction(UIAlertAction(title: "Pin", style: .default) { [weak self, weak message] _ in
                guard let self, let message else { return }
                chatVM.pinMessage(message, mode: .savedMessages)
            })
        } else {
            switch chatVM.customChat.type {
            case .bot, .user:
                alert.addAction(UIAlertAction(title: "Pin for Both", style: .default) { [weak self, weak message] _ in
                    guard let self, let message else { return }
                    chatVM.pinMessage(message, mode: .privateForBoth)
                })
                alert.addAction(UIAlertAction(title: "Pin for Me", style: .default) { [weak self, weak message] _ in
                    guard let self, let message else { return }
                    chatVM.pinMessage(message, mode: .privateForSelf)
                })
            case .group:
                addGroupPinActions(to: alert, message: message)
            case .supergroup(let supergroup):
                if supergroup.isChannel {
                    alert.addAction(UIAlertAction(title: "Pin", style: .default) { [weak self, weak message] _ in
                        guard let self, let message else { return }
                        chatVM.pinMessage(message, mode: .channel)
                    })
                } else {
                    addGroupPinActions(to: alert, message: message)
                }
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        configureActionSheetPopover(alert)
        present(alert, animated: true)
    }

    private func addGroupPinActions(
        to alert: UIAlertController,
        message: CustomMessage,
    ) {
        alert.addAction(UIAlertAction(title: "Pin and Notify", style: .default) { [weak self, weak message] _ in
            guard let self, let message else { return }
            chatVM.pinMessage(message, mode: .groupNotify)
        })
        alert.addAction(UIAlertAction(title: "Only Pin", style: .default) { [weak self, weak message] _ in
            guard let self, let message else { return }
            chatVM.pinMessage(message, mode: .groupSilent)
        })
    }

    private func presentUnpinConfirmation(for message: CustomMessage) {
        guard canOfferPinAction(for: message),
              presentedViewController == nil
        else { return }
        let alert = UIAlertController(
            title: "Unpin Message?",
            message: nil,
            preferredStyle: .actionSheet,
        )
        alert.addAction(UIAlertAction(title: "Unpin", style: .destructive) { [weak self, weak message] _ in
            guard let self, let message else { return }
            chatVM.unpinMessage(message)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        configureActionSheetPopover(alert)
        present(alert, animated: true)
    }

    private func configureActionSheetPopover(_ alert: UIAlertController) {
        guard let popover = alert.popoverPresentationController else { return }
        popover.sourceView = view
        popover.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.maxY - view.safeAreaInsets.bottom,
            width: 1,
            height: 1,
        )
    }

    private func presentReactionPicker(for message: CustomMessage) {
        guard canOfferReactionPicker(for: message),
              reactionPickerTask == nil,
              let accountID = TDLib.shared.activeAccountID,
              accountID == chatVM.accountID,
              TDLib.shared.activeClient.id == chatVM.client.id
        else { return }
        let client = chatVM.client
        let messageID = message.id
        reactionPickerTask = Task { [weak self, weak message] in
            guard let self else { return }
            guard let message else {
                reactionPickerTask = nil
                return
            }
            do {
                let available = try await client.getMessageAvailableReactions(
                    chatId: chatVM.chatID,
                    messageId: messageID,
                    rowSize: 8,
                )
                guard !Task.isCancelled,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id,
                      chatVM.displayedMessageID(containing: messageID)
                          .flatMap({ self.message(for: $0) }) === message
                else {
                    reactionPickerTask = nil
                    return
                }
                reactionPickerTask = nil
                if let reason = available.unavailabilityReason {
                    presentReactionUnavailable(reason)
                    return
                }
                let emojiTypes = available.nonPremiumReactionTypes.compactMap { type -> ReactionType? in
                    type.standardEmoji == nil ? nil : type
                }
                guard !emojiTypes.isEmpty else {
                    presentReactionUnavailable(nil)
                    return
                }
                let picker = UIAlertController(
                    title: "React",
                    message: nil,
                    preferredStyle: .actionSheet,
                )
                for type in emojiTypes.prefix(12) {
                    guard let emoji = type.standardEmoji else { continue }
                    picker.addAction(UIAlertAction(title: emoji, style: .default) { [weak self, weak message] _ in
                        guard let self, let message,
                              TDLib.shared.activeAccountID == accountID,
                              TDLib.shared.activeClient.id == client.id
                        else { return }
                        chatVM.toggleReaction(on: message, type: type, isBig: true)
                    })
                }
                picker.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                if let popover = picker.popoverPresentationController {
                    popover.sourceView = view
                    popover.sourceRect = CGRect(
                        x: view.bounds.midX,
                        y: view.bounds.maxY - view.safeAreaInsets.bottom,
                        width: 1,
                        height: 1,
                    )
                }
                guard presentedViewController == nil else { return }
                present(picker, animated: true)
            } catch is CancellationError {
                reactionPickerTask = nil
            } catch {
                reactionPickerTask = nil
                presentReactionUnavailable(nil)
            }
        }
    }

    private func presentReactionUnavailable(_ reason: ReactionUnavailabilityReason?) {
        guard presentedViewController == nil else { return }
        let message =
            switch reason {
            case .reactionUnavailabilityReasonAnonymousAdministrator:
                "Anonymous administrators can't add reactions here."
            case .reactionUnavailabilityReasonGuest:
                "Join the group before adding reactions."
            case .reactionUnavailabilityReasonRestricted:
                "Your reaction permission is restricted in this chat."
            case nil:
                "No non-Premium emoji reactions are available for this message."
            }
        let alert = UIAlertController(title: "Reaction Unavailable", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func reconfigureMessages(ids: [DisplayedMessageID]) {
        guard !ids.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        let existing = ids
            .map(ChatTimelineItemID.message)
            .filter { snapshot.indexOfItem($0) != nil }
        guard !existing.isEmpty else { return }
        let userIsScrolling = collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
        let keepLatest = !userIsScrolling && isNearLatest
        let anchor = !userIsScrolling && !keepLatest ? captureSnapshotAnchor() : nil
        snapshot.reconfigureItems(existing)
        timelineLayoutMutationDepth += 1
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            defer { timelineLayoutMutationDepth -= 1 }
            collectionView.layoutIfNeeded()
            if keepLatest {
                pinToLatestEdge(animated: false)
            } else if let anchor {
                restoreSnapshotAnchor(anchor)
            }
        }
    }

    private func forwardSelectedMessages() {
        presentForwardPicker(forDisplayedMessageIDs: selectedDisplayedMessageIDs)
    }

    private func presentForwardPicker(forDisplayedMessageIDs displayedIDs: Set<DisplayedMessageID>) {
        guard presentationMode == .full,
              presentedViewController == nil,
              let accountID = TDLib.shared.activeAccountID,
              TDLib.shared.activeClient.id == chatVM.client.id
        else { return }
        do {
            let request = try MessageForwardRequest(
                sourceLocation: chatVM.location,
                messageIDs: sourceMessageIDs(forDisplayedMessageIDs: displayedIDs),
            )
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
            )
            picker.onFinished = { [weak self] _ in
                self?.endMessageSelection()
            }
            let navigationController = UINavigationController(rootViewController: picker)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        } catch {
            let alert = UIAlertController(
                title: "Can't Forward",
                message: (error as? LocalizedError)?.errorDescription
                    ?? "The selected messages couldn't be forwarded.",
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
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
            do {
                for messageID in sourceIDs {
                    try Task.checkCancellation()
                    let properties = try await client.getMessageProperties(
                        chatId: chatVM.chatID,
                        messageId: messageID,
                    )
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
                    title: "Can't Delete",
                    message: "The selected messages couldn't be checked.",
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
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
                title: "Can't Delete",
                message: "The selected messages can't be deleted together.",
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let count = messageIDs.count
        let alert = UIAlertController(
            title: count == 1 ? "Delete Message?" : "Delete \(count) Messages?",
            message: nil,
            preferredStyle: .actionSheet,
        )
        if canDeleteForSelf {
            alert.addAction(UIAlertAction(title: "Delete for Me", style: .destructive) { [weak self] _ in
                self?.deleteSelectedMessages(messageIDs, forBoth: false, accountID: accountID)
            })
        }
        if canDeleteForAll {
            alert.addAction(UIAlertAction(title: "Delete for Everyone", style: .destructive) { [weak self] _ in
                self?.deleteSelectedMessages(messageIDs, forBoth: true, accountID: accountID)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
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
}
