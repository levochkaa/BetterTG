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
        let displayedMessageID: Int64
        let quote: MessageQuoteHighlight
        let targetMessageID: Int64
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        presentationMode == .full && voiceGestureDefersSystemGestures ? .bottom : []
    }

    private let presentationMode: PresentationMode
    private let targetMessageID: Int64?
    private let targetQuote: MessageQuoteHighlight?
    private let chatVM: ChatVM
    private let tdlib: TDLib
    private let historyContainerView = UIView()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Int64>!
    private var cancellables = Set<AnyCancellable>()
    private var messageCancellables = Set<AnyCancellable>()
    private var prefetchTasks = [Int64: PrefetchTaskEntry]()
    private var inlineVideoPlaybackOwners = [Int64: GalleryVideoPlaybackOwner]()
    private var pendingInlineVideoOwnerReturns = Set<Int64>()
    private let customNavigationBar = TelegramChatNavigationBar()
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private lazy var composerView = ChatComposerView(chatVM: chatVM)
    private let scrollToLatestButton = UIButton(type: .system)
    private let unreadBadgeLabel = TelegramUnreadBadgeLabel(minimumDiameter: 20, horizontalPadding: 11)
    private var scrollToLatestButtonVisible = false
    private var didPresentMicrophoneError = false
    private var didPresentVoiceNoteError = false
    private var didPresentVideoNoteError = false
    private var lastHighlightedMessageID: Int64?
    private var didPerformInitialScroll = false
    private var pendingScrollMessageID: Int64?
    private var pendingQuoteHighlight: MessageQuoteHighlight?
    private var pendingQuoteTargetMessageID: Int64?
    private var pendingQuoteDestination: PendingQuoteDestination?
    private var messageNavigationTask: Task<Void, Never>?
    private var metadataNavigationTask: Task<Void, Never>?
    private var messageHighlightTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
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
    private var videoNoteChatActionActive = false
    private var restoredVideoRecordingDraftIDHandled: UUID?

    private lazy var messageContextGesture: TelegramContextGestureRecognizer = {
        let gesture = TelegramContextGestureRecognizer(target: self, action: #selector(messageLongPressed(_:)))
        gesture.onPressingChanged = { [weak self, weak gesture] pressing in
            guard let self, let gesture else { return }
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
        presentationMode == .full && chatVM.customChat.canPostMessages
    }

    private var isNearLatest: Bool {
        collectionView.contentOffset.y + collectionView.adjustedContentInset.top < 100
    }

    init(
        customChat: CustomChat,
        presentationMode: PresentationMode = .full,
        targetMessageID: Int64? = nil,
        targetQuote: MessageQuoteHighlight? = nil,
        tdlib: TDLib = .shared,
    ) {
        self.presentationMode = presentationMode
        self.chatVM = ChatVM(customChat: customChat, previewing: presentationMode == .contextPreview)
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
        isTerminatingNavigation = true
        videoNoteRecorder?.teardownForNavigation()
        composerView.cancelActiveRecordingGesture()
        Task { [chatVM] in await chatVM.updateDraft() }
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

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + TelegramChatNavigationBar.contentHeight
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
        guard let messageID = dataSource.itemIdentifier(for: indexPath) else { return }
        if let cell = cell as? MessageCell, let message = message(for: messageID) {
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
            applyPendingQuoteHighlight(to: cell, displayedMessageID: messageID)
        }
        updateInlineVideoPlaybackVisibility()
        if presentationMode == .full {
            chatVM.viewMessage(id: messageID)
        }
        if indexPath.item >= max(chatVM.messages.count - 5, 0) {
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
            guard let messageID = dataSource.itemIdentifier(for: indexPath),
                  let message = message(for: messageID),
                  prefetchTasks[messageID] == nil
            else { continue }
            let messages = message.album.isEmpty ? [message.message] : message.album
            let client = chatVM.client
            let generation = UUID()
            let entry = PrefetchTaskEntry(generation: generation)
            prefetchTasks[messageID] = entry
            entry.task = Task { [weak self] in
                for item in messages where !Task.isCancelled {
                    await TDMediaPrefetcher.prefetch(message: item, client: client)
                }
                await MainActor.run {
                    guard self?.prefetchTasks[messageID]?.generation == generation else { return }
                    self?.prefetchTasks[messageID] = nil
                }
            }
        }
    }

    func collectionView(_: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
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
        updateChatHeader()
        updateStatus()
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
        }
        NSLayoutConstraint.activate(constraints)
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
        let recorder: VideoNoteRecorderViewController
        if let videoNoteRecorder {
            recorder = videoNoteRecorder
        } else {
            videoNoteReplyMessage = chatVM.replyMessage
            videoNoteReplyInput = chatVM.getMessageReplyTo(from: videoNoteReplyMessage)
            composerView.setVideoNoteReplyContext(message: videoNoteReplyMessage, input: videoNoteReplyInput)
            recorder = installVideoNoteRecorder()
        }
        return await recorder.beginHolding()
    }

    private func installVideoNoteRecorder(
        restoring restoredDraft: VideoNoteRecordingDraft? = nil,
        restoredReply: CustomMessage? = nil,
    ) -> VideoNoteRecorderViewController {
        let replySnapshot = restoredDraft == nil ? videoNoteReplyMessage : restoredReply
        let replyInput = restoredDraft?.replyTo ?? videoNoteReplyInput ?? chatVM.getMessageReplyTo(from: replySnapshot)
        videoNoteReplyInput = replyInput
        composerView.setVideoNoteReplyContext(message: replySnapshot, input: replyInput)
        let recorder = VideoNoteRecorderViewController(
            chatID: chatVM.chatID,
            replyMessageID: restoredDraft?.replyMessageID ?? replySnapshot?.id,
            replyTo: replyInput,
        )
        recorder.onStateChange = { [weak self, weak recorder] state in
            guard let self, videoNoteRecorder === recorder else { return }
            composerView.updateVideoNoteState(state)
            switch state {
            case .holding, .locked:
                if !videoNoteChatActionActive {
                    videoNoteChatActionActive = true
                    Task { [weak chatVM] in
                        try? await chatVM?.tdSendChatAction(.chatActionRecordingVideoNote)
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
            [weak chatVM] asset,
            thumbnail,
            originRecordingDraftID,
            storedReplyMessageID,
            storedReplyTo in
            guard let chatVM else {
                return .retained(
                    asset,
                    originConsumed: false,
                    message: "The chat was closed before the video message could be sent.",
                )
            }
            return await chatVM.submitVideoNote(
                asset,
                thumbnail: thumbnail,
                originRecordingDraftID: originRecordingDraftID,
                replyingTo: replySnapshot,
                storedReplyMessageID: storedReplyMessageID,
                storedReplyTo: storedReplyTo,
            )
        }
        recorder.onDismiss = { [weak self, weak recorder] in
            guard let self, let recorder, videoNoteRecorder === recorder else { return }
            recorder.willMove(toParent: nil)
            recorder.view.removeFromSuperview()
            recorder.removeFromParent()
            videoNoteRecorder = nil
            videoNoteReplyMessage = nil
            videoNoteReplyInput = nil
            composerView.setVideoNoteReplyContext(message: nil, input: nil)
            stopVideoNoteChatAction()
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
        Task { [weak chatVM] in try? await chatVM?.tdSendChatAction(.chatActionCancel) }
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
        let visible = isAwayFromLatest && !messageSearchActive
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
        dataSource = UICollectionViewDiffableDataSource<Section, Int64>(
            collectionView: collectionView,
        ) { [weak self] collectionView, indexPath, messageID in
            guard let self,
                  let cell = collectionView.dequeueReusableCell(
                      withReuseIdentifier: MessageCell.reuseIdentifier,
                      for: indexPath,
                  ) as? MessageCell,
                  let message = message(for: messageID)
            else { return UICollectionViewCell() }
            cell.configure(
                message: message,
                chat: chatVM.customChat,
                highlighted: chatVM.highlightedMessageId == messageID,
                client: chatVM.client,
                pollInteractionStore: chatVM.pollInteractionStore,
                videoPlaybackOwners: inlineVideoPlaybackOwners(for: message),
                onSwipeToReply: presentationMode == .full && message.properties.canBeReplied
                    ? { [weak self] in self?.chatVM.beginReply(to: message) }
                    : nil,
                onMetadataNavigate: { [weak self] target in
                    guard self?.presentationMode == .full else { return }
                    self?.navigate(to: target)
                },
                onReplyQuoteExpand: { [weak self] in
                    self?.expandReplyQuote(for: message)
                },
                onContentAction: { [weak self] action in
                    guard self?.presentationMode == .full else { return }
                    self?.performContentAction(action)
                },
                onMediaTap: { [weak self] messages, selection in
                    guard self?.presentationMode == .full else { return }
                    self?.showMedia(messages, selection: selection)
                },
            )
            pendingInlineVideoOwnerReturns.remove(messageID)
            return cell
        }
    }

    private func observeState() {
        chatVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    updateStatus()
                    composerView.update(from: chatVM)
                    updateHighlightState()
                    presentMicrophoneErrorIfNeeded()
                    presentVoiceNoteErrorIfNeeded()
                    presentVideoNoteSendErrorIfNeeded()
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
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            self?.updateChatHeader()
        }
        subscribeToMessages()
    }

    private func updateChatHeader() {
        let chat = chatVM.customChat.chat
        let status = chatVM.actionStatus.isEmpty ? chatVM.onlineStatus : chatVM.actionStatus
        let statusColor: UIColor = !chatVM.actionStatus.isEmpty || status == "online" ? .systemBlue : .secondaryLabel
        customNavigationBar.configure(
            title: chatVM.customChat.displayTitle,
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
        let status = chatVM.actionStatus.isEmpty ? chatVM.onlineStatus : chatVM.actionStatus
        let statusColor: UIColor = !chatVM.actionStatus.isEmpty || status == "online" ? .systemBlue : .secondaryLabel
        customNavigationBar.configure(
            title: chatVM.customChat.displayTitle,
            status: status,
            statusColor: statusColor,
        )
        let unreadCount = chatVM.customChat.unreadCount
        unreadBadgeLabel.text = unreadCount > 0 ? compactNumericCountString(unreadCount) : nil
        unreadBadgeLabel.isHidden = unreadCount == 0
        scrollToLatestButton.accessibilityValue = unreadCount == 0 ? nil : "\(unreadCount) unread"
    }

    private func updateSnapshot(animated: Bool) {
        guard isViewLoaded else { return }
        subscribeToMessages()
        let shouldKeepLatestVisible = !didPerformInitialScroll || isNearLatest
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(chatVM.messages.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self, !snapshot.itemIdentifiers.isEmpty else { return }
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
            }
            didPerformInitialScroll = true
        }
        collectionView.backgroundView = chatVM.messages.isEmpty ? emptyLabel() : nil
    }

    private func reconfigureMessage(id: Int64) {
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(id) != nil else { return }
        snapshot.reconfigureItems([id])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func updateHighlightState() {
        let changed = Array(Set([lastHighlightedMessageID, chatVM.highlightedMessageId].compactMap(\.self)))
        lastHighlightedMessageID = chatVM.highlightedMessageId
        guard !changed.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        let presentIdentifiers = changed.filter { snapshot.indexOfItem($0) != nil }
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
            if messageSearchActive {
                max(
                    view.safeAreaInsets.bottom,
                    view.bounds.maxY - view.keyboardLayoutGuide.layoutFrame.minY,
                ) + 8
            } else if showsComposer, composerView.frame.minY > 0 {
                max(view.safeAreaInsets.bottom, view.bounds.maxY - composerView.frame.minY) + 10
            } else {
                view.safeAreaInsets.bottom + 8
            }
        let visualTopInset = customNavigationBar.frame.maxY + 8
        let updatedInsets = UIEdgeInsets(top: visualBottomInset, left: 0, bottom: visualTopInset, right: 0)
        guard abs(collectionView.contentInset.top - updatedInsets.top) > 0.5
            || abs(collectionView.contentInset.bottom - updatedInsets.bottom) > 0.5
        else { return }

        let userIsScrolling = collectionView.isTracking || collectionView.isDragging || collectionView.isDecelerating
        let keepLatestVisible = !didPerformInitialScroll || (!userIsScrolling && isNearLatest)
        let previousOffset = collectionView.contentOffset
        let previousVisualBottomInset = collectionView.contentInset.top
        collectionView.contentInset = updatedInsets
        collectionView.verticalScrollIndicatorInsets = updatedInsets
        if keepLatestVisible {
            pinToLatestEdge(animated: false)
        } else if !userIsScrolling {
            collectionView.setContentOffset(
                CGPoint(
                    x: previousOffset.x,
                    y: previousOffset.y - (updatedInsets.top - previousVisualBottomInset),
                ),
                animated: false,
            )
        } else {
            collectionView.setContentOffset(previousOffset, animated: false)
        }
    }

    private func updateComposerFloatingState(_ keyboardAttached: Bool) {
        guard composerKeyboardAttached != keyboardAttached else { return }
        composerKeyboardAttached = keyboardAttached
        composerLeadingConstraint?.constant = keyboardAttached ? 8 : 0
        composerTrailingConstraint?.constant = keyboardAttached ? -8 : 0
        composerBottomConstraint?.constant = keyboardAttached ? -8 : 0
    }

    private func message(for id: Int64) -> CustomMessage? {
        chatVM.messages.first(where: { $0.id == id })
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
        id: Int64,
        quote: MessageQuoteHighlight? = nil,
        quoteTargetMessageID: Int64? = nil,
    ) {
        guard let index = dataSource.snapshot().indexOfItem(id) else {
            pendingScrollMessageID = id
            pendingQuoteHighlight = quote
            pendingQuoteTargetMessageID = quoteTargetMessageID
            updateSnapshot(animated: false)
            return
        }
        collectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: index, section: 0)
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
        chatVM.highlightedMessageId = id
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

    private func applyPendingQuoteHighlight(to cell: MessageCell, displayedMessageID: Int64) {
        guard let destination = pendingQuoteDestination,
              destination.displayedMessageID == displayedMessageID
        else { return }
        pendingQuoteDestination = nil
        guard destination.targetMessageID == displayedMessageID else { return }
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
            scrollToMessage(id: messageID, quote: quote)
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
        guard !message.isReplyQuoteExpanded,
              let index = dataSource.snapshot().indexOfItem(message.id)
        else { return }
        collectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: index, section: 0)
        let oldFrame = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
        let oldOffset = collectionView.contentOffset
        message.isReplyQuoteExpanded = true
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([message.id])
        UIView.performWithoutAnimation {
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
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
              let index = dataSource.snapshot().indexOfItem(displayedMessageID),
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? MessageCell
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
              let index = dataSource.snapshot().indexOfItem(displayedMessageID),
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? MessageCell,
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
            guard let messageID = dataSource.itemIdentifier(for: indexPath),
                  let message = message(for: messageID),
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
            let result = try? await td.searchChatMessages(
                chatId: chatVM.customChat.id,
                filter: nil,
                fromMessageId: 0,
                limit: 50,
                offset: 0,
                query: normalizedQuery,
                senderId: nil,
                topicId: nil,
            )
            guard !Task.isCancelled else { return }
            let firstID = result?.messages.first?.id
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

    @objc private func messageLongPressed(_ gesture: TelegramContextGestureRecognizer) {
        guard gesture.state == .began else { return }
        cancelHistoryPanGesture()
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              let messageID = dataSource.itemIdentifier(for: indexPath),
              let message = message(for: messageID),
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
        if let text = formattedText(from: message.message.content) {
            elements.append(TelegramContextMenuAction(
                title: "Copy",
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            ) { UIPasteboard.setFormattedText(text) })
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
