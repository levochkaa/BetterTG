// ChatViewAlbum.swift

import AVKit
import Combine
import TDLibKit
import UIKit

enum GalleryPlaybackCommand: Equatable {
    case jump(TimeInterval)
    case togglePictureInPicture
    case togglePlayback
}

final class MediaGalleryViewController: UIViewController, UICollectionViewDelegate {
    init(
        messages: [Message],
        selection: Int64,
        tdlib: TDLib = .shared,
        transferredPlaybackOwner: GalleryVideoPlaybackOwner? = nil,
    ) {
        self.tdlib = tdlib
        self.messages = messages.filter { message in
            switch message.content {
            case .messageAnimation, .messagePhoto, .messageSticker, .messageVideo:
                true
            default:
                false
            }
        }
        self.selectedIndex = self.messages.firstIndex(where: { $0.id == selection }) ?? 0
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        if let transferredPlaybackOwner,
           transferredPlaybackOwner.tdlib === tdlib,
           self.messages.contains(where: { $0.id == transferredPlaybackOwner.messageID })
        {
            videoPlaybackOwners[transferredPlaybackOwner.messageID] = transferredPlaybackOwner
            transferredPlaybackOwner.galleryController = self
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCollectionView()
        configureToolbar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
           layout.itemSize != collectionView.bounds.size
        {
            layout.itemSize = collectionView.bounds.size
            layout.invalidateLayout()
        }
        guard !didSetInitialPosition, messages.indices.contains(selectedIndex) else { return }
        didSetInitialPosition = true
        collectionView.scrollToItem(
            at: IndexPath(item: selectedIndex, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        updateCounter()
        prunePlaybackOwners(around: selectedIndex)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            releasePlaybackOwnersForDismissal()
        }
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            makeKeyCommand(
                input: " ",
                modifierFlags: [],
                action: #selector(toggleSelectedPlayback),
                discoverabilityTitle: "Play or Pause",
            ),
            makeKeyCommand(
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [.shift],
                action: #selector(jumpSelectedPlaybackBackward),
                discoverabilityTitle: "Back 5 Seconds",
            ),
            makeKeyCommand(
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [.shift],
                action: #selector(jumpSelectedPlaybackForward),
                discoverabilityTitle: "Forward 5 Seconds",
            ),
            makeKeyCommand(
                input: "p",
                modifierFlags: [.command],
                action: #selector(toggleSelectedPictureInPicture),
                discoverabilityTitle: "Picture in Picture",
            ),
        ]
    }

    private func makeKeyCommand(
        input: String,
        modifierFlags: UIKeyModifierFlags,
        action: Selector,
        discoverabilityTitle: String,
    ) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        command.discoverabilityTitle = discoverabilityTitle
        return command
    }

    private var messages: [Message]
    private let tdlib: TDLib
    private var selectedIndex: Int
    private var didSetInitialPosition = false
    private var videoPlaybackOwners = [Int64: GalleryVideoPlaybackOwner]()
    private let toolbar = UIToolbar()
    private let counterLabel = UILabel()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())

    private func makeLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        return layout
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(MediaGalleryCell.self, forCellWithReuseIdentifier: MediaGalleryCell.reuseIdentifier)
        view.addSubview(collectionView)
    }

    private func configureToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.barStyle = .black
        toolbar.isTranslucent = true
        counterLabel.textColor = .white
        counterLabel.font = .preferredFont(forTextStyle: .subheadline)
        counterLabel.textAlignment = .center
        toolbar.setItems([
            UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close)),
            UIBarButtonItem.flexibleSpace(),
            UIBarButtonItem(customView: counterLabel),
            UIBarButtonItem.flexibleSpace(),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share)),
        ], animated: false)
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateSelection(from: scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateSelection(from: scrollView)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateSelection(from: scrollView)
    }

    func collectionView(
        _: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath,
    ) {
        (cell as? MediaGalleryCell)?.setPlaybackVisible(shouldPlayItem(at: indexPath.item))
    }

    func collectionView(
        _: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt _: IndexPath,
    ) {
        (cell as? MediaGalleryCell)?.setPlaybackVisible(false)
    }

    private func updateCounter() {
        counterLabel.text = messages.count > 1 ? "\(selectedIndex + 1) of \(messages.count)" : ""
    }

    private func updateSelection(from scrollView: UIScrollView) {
        guard !messages.isEmpty else { return }
        let updatedIndex = min(
            messages.count - 1,
            max(0, Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))),
        )
        guard updatedIndex != selectedIndex else {
            collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
                .flatMap { $0 as? MediaGalleryCell }?
                .setPlaybackVisible(shouldPlayItem(at: selectedIndex))
            prunePlaybackOwners(around: selectedIndex)
            return
        }
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? MediaGalleryCell }?
            .setPlaybackVisible(false)
        selectedIndex = updatedIndex
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? MediaGalleryCell }?
            .setPlaybackVisible(shouldPlayItem(at: selectedIndex))
        updateCounter()
        prunePlaybackOwners(around: selectedIndex)
    }

    private func playbackOwner(for message: Message) -> GalleryVideoPlaybackOwner? {
        guard case .messageVideo = message.content else { return nil }
        if let owner = videoPlaybackOwners[message.id] {
            owner.galleryController = self
            return owner
        }
        guard let owner = GalleryVideoPlaybackOwner(message: message, tdlib: tdlib) else { return nil }
        owner.galleryController = self
        videoPlaybackOwners[message.id] = owner
        return owner
    }

    private func releasePlaybackOwnersForDismissal() {
        let pictureInPictureCoordinator = GalleryPictureInPictureCoordinator.shared
        pictureInPictureCoordinator.galleryWillDismiss(self)
        for owner in videoPlaybackOwners.values {
            if pictureInPictureCoordinator.isRetaining(owner) {
                owner.detachFromGallery()
            } else {
                owner.invalidate()
            }
        }
        videoPlaybackOwners.removeAll()
    }

    private func shouldPlayItem(at index: Int) -> Bool {
        guard index == selectedIndex, messages.indices.contains(index) else { return false }
        guard let activeOwner = GalleryPictureInPictureCoordinator.shared.activeOwner else { return true }
        return activeOwner.messageID == messages[index].id
    }

    private func prunePlaybackOwners(around index: Int) {
        guard messages.indices.contains(index) else { return }
        let lowerBound = max(messages.startIndex, index - 1)
        let upperBound = min(messages.index(before: messages.endIndex), index + 1)
        let retainedMessageIDs = Set(messages[lowerBound ... upperBound].compactMap { message -> Int64? in
            guard case .messageVideo = message.content else { return nil }
            return message.id
        })
        let evictedMessageIDs = videoPlaybackOwners.compactMap { messageID, owner in
            !retainedMessageIDs.contains(messageID) && !owner.isPictureInPictureRetained
                ? messageID
                : nil
        }
        for messageID in evictedMessageIDs {
            videoPlaybackOwners.removeValue(forKey: messageID)?.invalidate()
        }
    }

    @objc private func close() {
        releasePlaybackOwnersForDismissal()
        dismiss(animated: true)
    }

    @objc private func toggleSelectedPlayback() {
        performOnSelectedItem(.togglePlayback)
    }

    @objc private func jumpSelectedPlaybackBackward() {
        performOnSelectedItem(.jump(-5))
    }

    @objc private func jumpSelectedPlaybackForward() {
        performOnSelectedItem(.jump(5))
    }

    @objc private func toggleSelectedPictureInPicture() {
        performOnSelectedItem(.togglePictureInPicture)
    }

    private func performOnSelectedItem(_ command: GalleryPlaybackCommand) {
        if command == .togglePictureInPicture,
           let activeOwner = GalleryPictureInPictureCoordinator.shared.activeOwner
        {
            activeOwner.performPlaybackCommand(command)
            return
        }
        guard messages.indices.contains(selectedIndex) else { return }
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        (collectionView.cellForItem(at: indexPath) as? MediaGalleryCell)?
            .performPlaybackCommand(command)
    }

    @objc private func share() {
        guard messages.indices.contains(selectedIndex), let url = localURL(for: messages[selectedIndex]) else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activity, animated: true)
    }

    private func localURL(for message: Message) -> URL? {
        let path: String? =
            switch message.content {
            case .messagePhoto(let photo):
                photo.photo.sizes.getSize(.yBox)?.photo.local.path
            case .messageAnimation(let animation):
                animation.animation.animation.local.path
            case .messageSticker(let sticker):
                sticker.sticker.sticker.local.path
            case .messageVideo(let video):
                video.video.video.local.path
            default:
                nil
            }
        guard let path, !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(filePath: path)
    }

    func preparePictureInPicture(for owner: GalleryVideoPlaybackOwner) -> Bool {
        GalleryPictureInPictureCoordinator.shared.prepare(
            owner: owner,
            gallery: self,
            messages: messages,
        )
    }

    func playbackOwnerWasDeleted(_ owner: GalleryVideoPlaybackOwner) {
        guard let deletedIndex = messages.firstIndex(where: {
            $0.chatId == owner.chatID && $0.id == owner.messageID
        }) else { return }
        if deletedIndex == selectedIndex
            || GalleryPictureInPictureCoordinator.shared.isRetaining(owner)
        {
            releasePlaybackOwnersForDismissal()
            dismiss(animated: true)
            return
        }
        let selectedMessageID = messages.indices.contains(selectedIndex)
            ? messages[selectedIndex].id
            : nil
        videoPlaybackOwners.removeValue(forKey: owner.messageID)
        owner.galleryController = nil
        owner.invalidate()
        messages.remove(at: deletedIndex)
        if let selectedMessageID,
           let preservedIndex = messages.firstIndex(where: { $0.id == selectedMessageID })
        {
            selectedIndex = preservedIndex
        } else {
            selectedIndex = min(selectedIndex, max(0, messages.count - 1))
        }
        collectionView.reloadData()
        updateCounter()
        guard messages.indices.contains(selectedIndex) else {
            dismiss(animated: true)
            return
        }
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: selectedIndex, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? MediaGalleryCell }?
            .setPlaybackVisible(shouldPlayItem(at: selectedIndex))
        prunePlaybackOwners(around: selectedIndex)
    }

    func restorePictureInPicture(
        owner: GalleryVideoPlaybackOwner,
        completion: @escaping (Bool) -> Void,
    ) {
        guard let index = messages.firstIndex(where: { $0.id == owner.messageID }) else {
            completion(false)
            return
        }
        videoPlaybackOwners[owner.messageID] = owner
        owner.galleryController = self
        selectedIndex = index
        loadViewIfNeeded()
        view.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        collectionView.layoutIfNeeded()
        guard let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? MediaGalleryCell else {
            completion(false)
            return
        }
        cell.configure(message: messages[index], videoPlaybackOwner: owner)
        cell.setPlaybackVisible(true)
        updateCounter()
        prunePlaybackOwners(around: index)
        completion(true)
    }

    func pictureInPictureDidFinish(for _: GalleryVideoPlaybackOwner) {
        if messages.indices.contains(selectedIndex) {
            collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
                .flatMap { $0 as? MediaGalleryCell }?
                .setPlaybackVisible(true)
            prunePlaybackOwners(around: selectedIndex)
        }
    }
}

// MARK: UICollectionViewDataSource

extension MediaGalleryViewController: UICollectionViewDataSource {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        messages.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MediaGalleryCell.reuseIdentifier,
            for: indexPath,
        ) as? MediaGalleryCell else { return UICollectionViewCell() }
        let message = messages[indexPath.item]
        cell.configure(message: message, videoPlaybackOwner: playbackOwner(for: message))
        return cell
    }
}

// MARK: - GalleryVideoPlaybackOwner

@MainActor final class GalleryVideoPlaybackOwner: NSObject, @preconcurrency AVPictureInPictureControllerDelegate {
    // MARK: Lifecycle

    init?(message: Message, tdlib: TDLib) {
        guard case .messageVideo(let video) = message.content else { return nil }
        self.tdlib = tdlib
        chatID = message.chatId
        messageID = message.id
        allowsPictureInPicture = !video.isSecret
        super.init()
        mediaView.configure(
            file: video.video.video,
            thumbnail: video.video.thumbnail,
            minithumbnail: video.video.minithumbnail,
            canPlay: true,
            loops: false,
            mimeType: video.video.mimeType,
            fileName: video.video.fileName,
            supportsStreaming: video.video.supportsStreaming,
            isSecret: video.isSecret,
            startTimestamp: TimeInterval(video.startTimestamp),
            vodRanges: tdlib.vodRanges,
        )
        configurePictureInPicture()
        observeMessageDeletion()
    }

    #if DEBUG
        private init(probeMessageID: Int64) {
            tdlib = .shared
            chatID = 0
            messageID = probeMessageID
            allowsPictureInPicture = true
            super.init()
            configurePictureInPicture()
            observeMessageDeletion()
        }
    #endif

    // MARK: Internal

    let messageID: Int64
    let chatID: Int64
    let tdlib: TDLib
    weak var galleryController: MediaGalleryViewController?
    private(set) var isDeleted = false

    var isPictureInPictureRetained: Bool {
        isPictureInPictureStartRequested
            || isPictureInPictureActive
            || pictureInPictureController?.isPictureInPictureActive == true
    }

    #if DEBUG
        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-gallery-owner") else { return }
            Task { @MainActor in runDebugProbe() }
        }
    #endif

    func attach(to container: UIView) {
        guard !isInvalidated else { return }
        if mediaView.superview !== container {
            mediaView.removeFromSuperview()
            mediaView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(mediaView)
            NSLayoutConstraint.activate([
                mediaView.topAnchor.constraint(equalTo: container.topAnchor),
                mediaView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                mediaView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                mediaView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        isPlaybackVisible = false
        applyEffectivePlaybackVisibility()
        updatePictureInPictureControl()
    }

    func detach(from container: UIView) {
        guard mediaView.superview === container else { return }
        isPlaybackVisible = false
        applyEffectivePlaybackVisibility()
        mediaView.removeFromSuperview()
        updatePictureInPictureControl()
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        guard !isInvalidated else { return }
        self.isPlaybackVisible = isVisible
        applyEffectivePlaybackVisibility()
        updatePictureInPictureControl()
        if !isVisible, !isPictureInPictureRetained {
            releasePictureInPictureAudioSession()
        }
    }

    func performPlaybackCommand(_ command: GalleryPlaybackCommand) {
        guard !isInvalidated else { return }
        mediaView.performPlaybackCommand(command)
    }

    func detachFromGallery() {
        isPlaybackVisible = false
        applyEffectivePlaybackVisibility()
        mediaView.removeFromSuperview()
        updatePictureInPictureControl()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        if isPictureInPictureStartRequested {
            pendingInvalidationAfterPictureInPicture = true
            cancelPendingPictureInPictureStart(rejectLateStart: true)
            return
        }
        if isPictureInPictureActive || pictureInPictureController?.isPictureInPictureActive == true {
            pendingInvalidationAfterPictureInPicture = true
            requestPictureInPictureStop()
            return
        }
        finishInvalidation()
    }

    func pictureInPictureControllerWillStartPictureInPicture(_: AVPictureInPictureController) {
        cancelPictureInPictureStartTimeout()
        if rejectsLatePictureInPictureStart {
            isPictureInPictureStartRequested = false
            requestPictureInPictureStop()
            return
        }
        isPictureInPictureStartRequested = false
        isPictureInPictureActive = true
        mediaView.setPictureInPictureActive(true)
        applyEffectivePlaybackVisibility()
        updatePictureInPictureControl()
    }

    func pictureInPictureController(
        _: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Swift.Error,
    ) {
        cancelPictureInPictureStartTimeout()
        cancelPictureInPictureStopTimeout()
        rejectsLatePictureInPictureStart = false
        log("Gallery Picture in Picture failed: \(error.localizedDescription)")
        isPictureInPictureStartRequested = false
        isPictureInPictureActive = false
        mediaView.setPictureInPictureActive(false)
        releasePictureInPictureAudioSession()
        updatePictureInPictureControl()
        GalleryPictureInPictureCoordinator.shared.didFail(owner: self)
        if pendingInvalidationAfterPictureInPicture {
            finishInvalidation()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        cancelPictureInPictureStartTimeout()
        cancelPictureInPictureStopTimeout()
        completePictureInPictureStop()
    }

    private func completePictureInPictureStop() {
        rejectsLatePictureInPictureStart = false
        isPictureInPictureStartRequested = false
        isPictureInPictureActive = false
        mediaView.setPictureInPictureActive(false)
        applyEffectivePlaybackVisibility()
        releasePictureInPictureAudioSession(
            keepForGalleryPlayback: isPlaybackVisible && mediaView.isPlaybackRequested,
        )
        updatePictureInPictureControl()
        GalleryPictureInPictureCoordinator.shared.didStop(owner: self)
        if pendingInvalidationAfterPictureInPicture {
            finishInvalidation()
        }
    }

    func pictureInPictureController(
        _: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void,
    ) {
        GalleryPictureInPictureCoordinator.shared.restore(
            owner: self,
            completion: completionHandler,
        )
    }

    // MARK: Private

    private let mediaView = GalleryFilePlayerView()
    private let allowsPictureInPicture: Bool
    private var pictureInPictureController: AVPictureInPictureController?
    private var pictureInPicturePossibleCancellable: AnyCancellable?
    private var isInvalidated = false
    private var isPlaybackVisible = false
    private var isPictureInPictureStartRequested = false
    private var isPictureInPictureActive = false
    private var pendingInvalidationAfterPictureInPicture = false
    private var pictureInPictureAudioSessionToken: UUID?
    private var pictureInPictureStartTimeout: DispatchWorkItem?
    private var pictureInPictureStopTimeout: DispatchWorkItem?
    private var rejectsLatePictureInPictureStart = false
    private var mediaTakeoverCancellable: AnyCancellable?
    private var tdUpdateCancellables = Set<AnyCancellable>()

    private func configurePictureInPicture() {
        mediaView.onPictureInPictureToggle = { [weak self] in self?.togglePictureInPicture() }
        mediaView.onPictureInPictureEligibilityChanged = { [weak self] in
            self?.updatePictureInPictureControl()
        }
        mediaView.onPlaybackIntentChanged = { [weak self] in
            guard let self,
                  !isPictureInPictureRetained,
                  !mediaView.isPlaybackRequested
            else { return }
            releasePictureInPictureAudioSession()
        }
        mediaTakeoverCancellable = Media.shared.$savedMediaPath
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                guard let self,
                      !path.isEmpty,
                      pictureInPictureAudioSessionToken != nil
                else { return }
                if let pictureInPictureAudioSessionToken {
                    GalleryPlaybackAudioSessionCoordinator.shared.relinquish(
                        token: pictureInPictureAudioSessionToken,
                    )
                    self.pictureInPictureAudioSessionToken = nil
                }
                mediaView.pauseForAudioTakeover()
            }
        guard allowsPictureInPicture,
              AVPictureInPictureController.isPictureInPictureSupported()
        else {
            updatePictureInPictureControl()
            return
        }
        guard let controller = AVPictureInPictureController(
            playerLayer: mediaView.pictureInPicturePlayerLayer,
        ) else {
            updatePictureInPictureControl()
            return
        }
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        pictureInPictureController = controller
        pictureInPicturePossibleCancellable = controller.publisher(
            for: \.isPictureInPicturePossible,
            options: [.initial, .new],
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.updatePictureInPictureControl() }
        updatePictureInPictureControl()
    }

    private func observeMessageDeletion() {
        tdlib.deleteMessageUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self,
                      !update.fromCache,
                      update.isPermanent,
                      update.chatId == chatID,
                      update.messageIds.contains(messageID)
                else { return }
                handlePermanentDeletion()
            }
            .store(in: &tdUpdateCancellables)
    }

    private func handlePermanentDeletion() {
        guard !isDeleted else { return }
        isDeleted = true
        GalleryPictureInPictureCoordinator.shared.messageWasDeleted(owner: self)
        galleryController?.playbackOwnerWasDeleted(self)
        if isPictureInPictureStartRequested {
            pendingInvalidationAfterPictureInPicture = true
            cancelPendingPictureInPictureStart(rejectLateStart: true)
        } else if isPictureInPictureActive
            || pictureInPictureController?.isPictureInPictureActive == true
        {
            pendingInvalidationAfterPictureInPicture = true
            requestPictureInPictureStop()
        } else {
            finishInvalidation()
        }
    }

    private func togglePictureInPicture() {
        guard let pictureInPictureController else { return }
        if isPictureInPictureStartRequested {
            cancelPendingPictureInPictureStart(rejectLateStart: true)
            return
        }
        if isPictureInPictureActive || pictureInPictureController.isPictureInPictureActive {
            requestPictureInPictureStop()
            return
        }
        guard isPlaybackVisible,
              mediaView.isPictureInPictureReady,
              pictureInPictureController.isPictureInPicturePossible,
              galleryController?.preparePictureInPicture(for: self) == true
        else { return }
        guard activatePictureInPictureAudioSession() else {
            GalleryPictureInPictureCoordinator.shared.didFail(owner: self)
            return
        }
        rejectsLatePictureInPictureStart = false
        isPictureInPictureStartRequested = true
        applyEffectivePlaybackVisibility()
        updatePictureInPictureControl()
        pictureInPictureController.startPictureInPicture()
        schedulePictureInPictureStartTimeout()
    }

    private func applyEffectivePlaybackVisibility() {
        mediaView.setPlaybackVisible(isPlaybackVisible || isPictureInPictureRetained)
    }

    private func updatePictureInPictureControl() {
        let isPossible = pictureInPictureController?.isPictureInPicturePossible == true
        let isReady = mediaView.isPictureInPictureReady
        let isVisible = allowsPictureInPicture
            && !isDeleted
            && isPlaybackVisible
            && !rejectsLatePictureInPictureStart
            && (isPictureInPictureRetained || isPossible && isReady)
        mediaView.setPictureInPictureControl(
            visible: isVisible,
            enabled: isPictureInPictureActive || !isPictureInPictureStartRequested && isPossible && isReady,
            active: isPictureInPictureRetained,
        )
    }

    private func activatePictureInPictureAudioSession() -> Bool {
        if pictureInPictureAudioSessionToken != nil {
            return true
        }
        pictureInPictureAudioSessionToken = GalleryPlaybackAudioSessionCoordinator.shared.acquire(for: self)
        return pictureInPictureAudioSessionToken != nil
    }

    private func releasePictureInPictureAudioSession(keepForGalleryPlayback: Bool = false) {
        guard let pictureInPictureAudioSessionToken else { return }
        GalleryPlaybackAudioSessionCoordinator.shared.release(
            token: pictureInPictureAudioSessionToken,
            keepActive: keepForGalleryPlayback,
        )
        if !keepForGalleryPlayback {
            self.pictureInPictureAudioSessionToken = nil
        }
    }

    private func schedulePictureInPictureStartTimeout() {
        cancelPictureInPictureStartTimeout()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, isPictureInPictureStartRequested else { return }
            if let pictureInPictureController,
               pictureInPictureController.isPictureInPictureActive
            {
                pictureInPictureControllerWillStartPictureInPicture(pictureInPictureController)
                return
            }
            cancelPendingPictureInPictureStart(rejectLateStart: true)
        }
        pictureInPictureStartTimeout = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func cancelPictureInPictureStartTimeout() {
        pictureInPictureStartTimeout?.cancel()
        pictureInPictureStartTimeout = nil
    }

    private func requestPictureInPictureStop() {
        pictureInPictureController?.stopPictureInPicture()
        schedulePictureInPictureStopTimeout()
    }

    private func schedulePictureInPictureStopTimeout() {
        cancelPictureInPictureStopTimeout()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard isPictureInPictureActive
                || pictureInPictureController?.isPictureInPictureActive == true
                || pendingInvalidationAfterPictureInPicture
            else { return }
            pictureInPictureController?.stopPictureInPicture()
            if pictureInPictureController?.isPictureInPictureActive == true {
                schedulePictureInPictureStopTimeout()
                return
            }
            completePictureInPictureStop()
        }
        pictureInPictureStopTimeout = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func cancelPictureInPictureStopTimeout() {
        pictureInPictureStopTimeout?.cancel()
        pictureInPictureStopTimeout = nil
    }

    private func cancelPendingPictureInPictureStart(rejectLateStart: Bool) {
        guard isPictureInPictureStartRequested else { return }
        cancelPictureInPictureStartTimeout()
        isPictureInPictureStartRequested = false
        isPictureInPictureActive = false
        rejectsLatePictureInPictureStart = rejectLateStart
        pictureInPictureController?.stopPictureInPicture()
        releasePictureInPictureAudioSession()
        updatePictureInPictureControl()
        GalleryPictureInPictureCoordinator.shared.didFail(owner: self)
        if pendingInvalidationAfterPictureInPicture {
            finishInvalidation()
        }
    }

    private func finishInvalidation() {
        guard !isInvalidated else { return }
        isInvalidated = true
        isPlaybackVisible = false
        pendingInvalidationAfterPictureInPicture = false
        rejectsLatePictureInPictureStart = false
        cancelPictureInPictureStartTimeout()
        cancelPictureInPictureStopTimeout()
        mediaTakeoverCancellable?.cancel()
        mediaTakeoverCancellable = nil
        tdUpdateCancellables.removeAll()
        pictureInPicturePossibleCancellable?.cancel()
        pictureInPicturePossibleCancellable = nil
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil
        releasePictureInPictureAudioSession()
        mediaView.removeFromSuperview()
        mediaView.prepareForReuse()
    }

    #if DEBUG
        private static func runDebugProbe() {
            let result: String
            let owner = GalleryVideoPlaybackOwner(probeMessageID: 9001)
            let firstContainer = UIView()
            let secondContainer = UIView()
            let viewIdentifier = ObjectIdentifier(owner.mediaView)

            owner.attach(to: firstContainer)
            let startsPaused = !owner.isPlaybackVisible && owner.mediaView.superview === firstContainer
            owner.setPlaybackVisible(true)
            let becameVisible = owner.isPlaybackVisible
            owner.detach(from: firstContainer)
            let detachedWithoutInvalidation = !owner.isInvalidated
                && !owner.isPlaybackVisible
                && owner.mediaView.superview == nil
            owner.attach(to: secondContainer)
            let reusedExactView = ObjectIdentifier(owner.mediaView) == viewIdentifier
                && owner.mediaView.superview === secondContainer
            let readinessGated = owner.mediaView.pictureInPictureControlIsHidden
            owner.performPlaybackCommand(.jump(-15))
            owner.performPlaybackCommand(.jump(15))
            owner.performPlaybackCommand(.togglePlayback)
            let commandRouting = owner.mediaView.debugPlaybackCommandProbePassed
            let accessibleControls = owner.mediaView.debugPlaybackControlsLayoutProbePassed
            let autoHidePolicy = owner.mediaView.debugControlsAutoHidePolicyProbePassed
            owner.invalidate()
            let invalidatedCleanly = owner.isInvalidated
                && !owner.isPlaybackVisible
                && owner.mediaView.superview == nil

            let transferredOwner = GalleryVideoPlaybackOwner(probeMessageID: 9002)
            let probeGallery = MediaGalleryViewController(messages: [], selection: 0)
            let coordinator = GalleryPictureInPictureCoordinator.shared
            let preparedTransfer = coordinator.prepare(
                owner: transferredOwner,
                gallery: probeGallery,
                messages: [],
            )
            coordinator.galleryWillDismiss(probeGallery)
            let retainedAcrossDismissal = preparedTransfer && coordinator.isRetaining(transferredOwner)
            coordinator.didFail(owner: transferredOwner)
            let transferCleanedUp = transferredOwner.isInvalidated && coordinator.activeOwner == nil

            let deletedOwner = GalleryVideoPlaybackOwner(probeMessageID: 9003)
            deletedOwner.handlePermanentDeletion()
            let deletionRevoked = deletedOwner.isDeleted && deletedOwner.isInvalidated

            if startsPaused,
               becameVisible,
               detachedWithoutInvalidation,
               reusedExactView,
               readinessGated,
               commandRouting,
               accessibleControls,
               autoHidePolicy,
               invalidatedCleanly,
               retainedAcrossDismissal,
               transferCleanedUp,
               deletionRevoked
            {
                result = "Gallery playback owner probe: same-view=true, detach-retains-session=true, "
                    + "central-visibility=true, transfer-retains=true, delete-revokes=true, "
                    + "commands=back15+forward15+toggle, controls=two-row+44pt+auto-hide4s, "
                    + "pip-supported=\(AVPictureInPictureController.isPictureInPictureSupported()), "
                    + "readiness-gated=true, invalidate=true"
            } else {
                result = "Gallery playback owner probe failed: startsPaused=\(startsPaused), "
                    + "becameVisible=\(becameVisible), detached=\(detachedWithoutInvalidation), "
                    + "reused=\(reusedExactView), readinessGated=\(readinessGated), "
                    + "commands=\(commandRouting), "
                    + "accessibleControls=\(accessibleControls), "
                    + "autoHide=\(autoHidePolicy), "
                    + "invalidated=\(invalidatedCleanly), transfer=\(retainedAcrossDismissal), "
                    + "transferCleanup=\(transferCleanedUp), deletion=\(deletionRevoked)"
                assertionFailure(result)
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            if let documentsURL = documents.first {
                try? Data(result.utf8).write(
                    to: documentsURL.appendingPathComponent("gallery-playback-owner-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    #endif
}

// MARK: - GalleryPlaybackAudioSessionCoordinator

@MainActor final class GalleryPlaybackAudioSessionCoordinator {
    // MARK: Internal

    static let shared = GalleryPlaybackAudioSessionCoordinator()

    func acquire(for owner: GalleryVideoPlaybackOwner) -> UUID? {
        if let ownership, ownership.owner != nil {
            return ownership.owner === owner ? ownership.token : nil
        }
        ownership = nil
        let audioSession = AVAudioSession.sharedInstance()
        let snapshot = Snapshot(
            category: audioSession.category,
            mode: audioSession.mode,
            options: audioSession.categoryOptions,
        )
        do {
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                policy: .default,
                options: [.allowAirPlay, .allowBluetoothA2DP],
            )
            try audioSession.setActive(true)
        } catch {
            try? audioSession.setCategory(
                snapshot.category,
                mode: snapshot.mode,
                options: snapshot.options,
            )
            log("Gallery Picture in Picture audio session failed: \(error.localizedDescription)")
            return nil
        }
        Media.shared.stop()
        let token = UUID()
        ownership = Ownership(owner: owner, snapshot: snapshot, token: token)
        return token
    }

    func release(token: UUID, keepActive: Bool) {
        guard let ownership, ownership.token == token else { return }
        if keepActive {
            return
        }
        self.ownership = nil
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.category == .playback, audioSession.mode == .moviePlayback else {
            return
        }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        try? audioSession.setCategory(
            ownership.snapshot.category,
            mode: ownership.snapshot.mode,
            options: ownership.snapshot.options,
        )
    }

    func relinquish(token: UUID) {
        guard ownership?.token == token else { return }
        ownership = nil
    }

    // MARK: Private

    private struct Snapshot {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    private struct Ownership {
        weak var owner: GalleryVideoPlaybackOwner?
        let snapshot: Snapshot
        let token: UUID
    }

    private var ownership: Ownership?

    private init() {}
}

// MARK: - GalleryPictureInPictureCoordinator

@MainActor final class GalleryPictureInPictureCoordinator {
    // MARK: Internal

    static let shared = GalleryPictureInPictureCoordinator()

    private(set) var activeOwner: GalleryVideoPlaybackOwner?

    func prepare(
        owner: GalleryVideoPlaybackOwner,
        gallery: MediaGalleryViewController,
        messages: [Message],
    ) -> Bool {
        guard !owner.isDeleted else { return false }
        if let activeOwner, activeOwner !== owner {
            return false
        }
        activeOwner = owner
        galleryController = gallery
        presentingViewController = gallery.presentingViewController
        restorationMessages = messages
        return true
    }

    func galleryWillDismiss(_ gallery: MediaGalleryViewController) {
        guard galleryController === gallery else { return }
        galleryController = nil
        activeOwner?.galleryController = nil
    }

    func isRetaining(_ owner: GalleryVideoPlaybackOwner) -> Bool {
        activeOwner === owner
    }

    func restore(
        owner: GalleryVideoPlaybackOwner,
        completion: @escaping (Bool) -> Void,
    ) {
        guard activeOwner === owner,
              !owner.isDeleted,
              restorationMessages.contains(where: {
                  $0.chatId == owner.chatID && $0.id == owner.messageID
              })
        else {
            completion(false)
            return
        }
        if let galleryController,
           !galleryController.isBeingDismissed,
           galleryController.viewIfLoaded?.window != nil
        {
            galleryController.restorePictureInPicture(owner: owner, completion: completion)
            return
        }
        guard let presentingViewController,
              presentingViewController.viewIfLoaded?.window != nil,
              !restorationMessages.isEmpty
        else {
            completion(false)
            return
        }
        presentRestoredGallery(
            owner: owner,
            presenter: presentingViewController,
            retriesRemaining: 20,
            completion: completion,
        )
    }

    func didFail(owner: GalleryVideoPlaybackOwner) {
        finish(owner: owner)
    }

    func didStop(owner: GalleryVideoPlaybackOwner) {
        finish(owner: owner)
    }

    func messageWasDeleted(owner: GalleryVideoPlaybackOwner) {
        restorationMessages.removeAll {
            $0.chatId == owner.chatID && $0.id == owner.messageID
        }
    }

    // MARK: Private

    private weak var galleryController: MediaGalleryViewController?
    private weak var presentingViewController: UIViewController?
    private var restorationMessages = [Message]()

    private init() {}

    private func presentRestoredGallery(
        owner: GalleryVideoPlaybackOwner,
        presenter: UIViewController,
        retriesRemaining: Int,
        completion: @escaping (Bool) -> Void,
    ) {
        guard activeOwner === owner else {
            completion(false)
            return
        }
        guard !owner.isDeleted else {
            completion(false)
            return
        }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed else {
            completion(false)
            return
        }
        if presenter.presentedViewController != nil {
            guard retriesRemaining > 0 else {
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak owner, weak presenter] in
                guard let self, let owner, let presenter else {
                    completion(false)
                    return
                }
                self.presentRestoredGallery(
                    owner: owner,
                    presenter: presenter,
                    retriesRemaining: retriesRemaining - 1,
                    completion: completion,
                )
            }
            return
        }
        let gallery = MediaGalleryViewController(
            messages: restorationMessages,
            selection: owner.messageID,
            tdlib: owner.tdlib,
            transferredPlaybackOwner: owner,
        )
        galleryController = gallery
        owner.galleryController = gallery
        presenter.present(gallery, animated: true) { [weak self, weak gallery, weak owner] in
            guard let self,
                  let gallery,
                  let owner,
                  self.activeOwner === owner
            else {
                completion(false)
                return
            }
            self.galleryController = gallery
            gallery.restorePictureInPicture(owner: owner, completion: completion)
        }
    }

    private func finish(owner: GalleryVideoPlaybackOwner) {
        guard activeOwner === owner else { return }
        let gallery = galleryController
        activeOwner = nil
        galleryController = nil
        presentingViewController = nil
        restorationMessages.removeAll()
        if let gallery, !gallery.isBeingDismissed {
            owner.galleryController = gallery
            gallery.pictureInPictureDidFinish(for: owner)
        } else {
            owner.galleryController = nil
            owner.invalidate()
        }
    }
}

final class MediaGalleryCell: UICollectionViewCell {
    // MARK: Internal

    static let reuseIdentifier = "MediaGalleryCell"

    // MARK: Private

    private var contentMediaView: (UIView & GalleryMediaView)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        videoPlaybackOwner?.detach(from: contentView)
        videoPlaybackOwner = nil
        contentMediaView?.prepareForReuse()
        contentMediaView?.removeFromSuperview()
        contentMediaView = nil
    }

    private var contentMediaView: (UIView & GalleryMediaView)?

    func configure(message: Message, videoPlaybackOwner: GalleryVideoPlaybackOwner? = nil) {
        prepareForReuse()
        if let videoPlaybackOwner {
            self.videoPlaybackOwner = videoPlaybackOwner
            videoPlaybackOwner.attach(to: contentView)
            return
        }
        let view: (UIView & GalleryMediaView)
        switch message.content {
        case .messagePhoto(let photo):
            let imageView = ZoomableGalleryImageView()
            imageView.configure(photo: photo.photo)
            view = imageView
        case .messageAnimation(let animation):
            if telegramAnimationUsesFFmpeg(animation.animation) {
                let animationView = FFmpegAnimatedVideoView(frame: .zero)
                animationView.configure(
                    file: animation.animation.animation,
                    thumbnail: animation.animation.thumbnail,
                    displaySize: nil,
                    onTap: nil,
                )
                view = animationView
            } else {
                let player = GalleryFilePlayerView()
                player.configure(
                    file: animation.animation.animation,
                    thumbnail: animation.animation.thumbnail,
                    minithumbnail: animation.animation.minithumbnail,
                    canPlay: true,
                    loops: true,
                )
                view = player
            }
        case .messageVideo:
            view = ZoomableGalleryImageView()
        case .messageSticker(let sticker):
            if sticker.sticker.format == .stickerFormatTgs {
                let stickerView = TGSStickerView(frame: .zero)
                stickerView.configure(
                    file: sticker.sticker.sticker,
                    thumbnail: sticker.sticker.thumbnail,
                    displaySize: nil,
                    onTap: nil,
                )
                view = stickerView
            } else if sticker.sticker.format == .stickerFormatWebp {
                let stickerView = AnimatedWebPView(frame: .zero)
                stickerView.configure(
                    file: sticker.sticker.sticker,
                    thumbnail: sticker.sticker.thumbnail,
                    displaySize: nil,
                    onTap: nil,
                )
                view = stickerView
            } else {
                let stickerView = FFmpegAnimatedVideoView(frame: .zero)
                stickerView.configure(
                    file: sticker.sticker.sticker,
                    thumbnail: sticker.sticker.thumbnail,
                    displaySize: nil,
                    onTap: nil,
                )
                view = stickerView
            }
        default:
            view = ZoomableGalleryImageView()
        }
        contentMediaView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        view.setPlaybackVisible(false)
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        if let videoPlaybackOwner {
            videoPlaybackOwner.setPlaybackVisible(isVisible)
        } else {
            contentMediaView?.setPlaybackVisible(isVisible)
        }
    }

    func performPlaybackCommand(_ command: GalleryPlaybackCommand) {
        if let videoPlaybackOwner {
            videoPlaybackOwner.performPlaybackCommand(command)
        } else {
            contentMediaView?.performPlaybackCommand(command)
        }
    }

    private weak var videoPlaybackOwner: GalleryVideoPlaybackOwner?
}

// MARK: - GalleryMediaView

protocol GalleryMediaView: AnyObject {
    func performPlaybackCommand(_ command: GalleryPlaybackCommand)
    func prepareForReuse()
    func setPlaybackVisible(_ isVisible: Bool)
}

extension GalleryMediaView {
    func performPlaybackCommand(_: GalleryPlaybackCommand) {}
    func setPlaybackVisible(_: Bool) {}
}

extension TGSStickerView: GalleryMediaView {}
extension AnimatedWebPView: GalleryMediaView {}
extension FFmpegAnimatedVideoView: GalleryMediaView {}

final class ZoomableGalleryImageView: UIScrollView, UIScrollViewDelegate, GalleryMediaView {
    // MARK: Private

    private let imageView = TDImageLoadingView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
        ])
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    func configure(photo: Photo) {
        imageView.load(photo: photo, preferredSize: .yBox)
    }

    func prepareForReuse() {
        setZoomScale(1, animated: false)
        imageView.cancel()
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / maximumZoomScale, height: bounds.height / maximumZoomScale)
            zoom(to: CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height,
            ), animated: true)
        }
    }
}

// MARK: - GalleryFilePlayerView

final class GalleryFilePlayerView: UIView, GalleryMediaView, UIGestureRecognizerDelegate {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.contentMode = .scaleAspectFit
        videoSurface.translatesAutoresizingMaskIntoConstraints = false
        videoSurface.backgroundColor = .black
        player.attach(to: videoSurface.playerLayer)
        self.displayCancellable = videoSurface.playerLayer
            .publisher(for: \.isReadyForDisplay, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshSurfaceReady() }
            }
        spinner.translatesAutoresizingMaskIntoConstraints = false
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Retry", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retryButton.isHidden = true
        retryButton.accessibilityHint = "Attempts to load this video again"
        retryButton.addTarget(self, action: #selector(retryPlayback), for: .touchUpInside)
        configurePlaybackControls()
        let controlsTapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleControlsVisibility))
        controlsTapGesture.cancelsTouchesInView = false
        controlsTapGesture.delegate = self
        addGestureRecognizer(controlsTapGesture)
        addSubview(preview)
        addSubview(videoSurface)
        addSubview(spinner)
        addSubview(retryButton)
        addSubview(controlsView)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: topAnchor),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: bottomAnchor),
            videoSurface.topAnchor.constraint(equalTo: topAnchor),
            videoSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            retryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            controlsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlsView.heightAnchor.constraint(equalToConstant: 136),
            controlsStack.leadingAnchor.constraint(equalTo: controlsView.contentView.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: controlsView.contentView.trailingAnchor, constant: -12),
            controlsStack.topAnchor.constraint(equalTo: controlsView.contentView.topAnchor, constant: 8),
            controlsStack.bottomAnchor.constraint(equalTo: controlsView.contentView.bottomAnchor, constant: -8),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
            networkStatusLabel.heightAnchor.constraint(equalToConstant: 20),
            scrubberStack.heightAnchor.constraint(equalToConstant: 36),
            jumpBackwardButton.widthAnchor.constraint(equalToConstant: 44),
            jumpBackwardButton.heightAnchor.constraint(equalToConstant: 44),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            jumpForwardButton.widthAnchor.constraint(equalToConstant: 44),
            jumpForwardButton.heightAnchor.constraint(equalToConstant: 44),
            muteButton.widthAnchor.constraint(equalToConstant: 44),
            muteButton.heightAnchor.constraint(equalToConstant: 44),
            rateButton.widthAnchor.constraint(equalToConstant: 44),
            rateButton.heightAnchor.constraint(equalToConstant: 44),
            pictureInPictureButton.widthAnchor.constraint(equalToConstant: 44),
            pictureInPictureButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    var pictureInPicturePlayerLayer: AVPlayerLayer {
        videoSurface.playerLayer
    }

    var isPictureInPictureReady: Bool {
        guard !loopsPlayback, player.hasItem, isSurfaceReady else { return false }
        return switch currentPlaybackState {
        case .buffering, .ended, .paused, .playing:
            true
        case .failed, .idle, .preparing:
            false
        }
    }

    var isPlaybackRequested: Bool {
        player.isPlaybackRequested
    }

    var onPictureInPictureToggle: (() -> Void)?
    var onPictureInPictureEligibilityChanged: (() -> Void)?
    var onPlaybackIntentChanged: (() -> Void)?

    #if DEBUG
        var pictureInPictureControlIsHidden: Bool {
            pictureInPictureButton.isHidden
        }

        var debugPlaybackCommandProbePassed: Bool {
            let commandsPassed = debugPlaybackCommands == [
                .jump(-15),
                .jump(15),
                .togglePlayback,
            ]
            let backward = Self.resolveJump(current: 3, duration: 20, interval: -15)
            let pastEnd = Self.resolveJump(current: 9, duration: 20, interval: 15)
            return commandsPassed
                && backward.time == 0
                && !backward.shouldPauseAtStart
                && pastEnd.time == 0
                && pastEnd.shouldPauseAtStart
        }

        var debugPlaybackControlsLayoutProbePassed: Bool {
            let transportButtons = [
                jumpBackwardButton,
                playButton,
                jumpForwardButton,
                muteButton,
                rateButton,
                pictureInPictureButton,
            ]
            let fixedTransportWidth = CGFloat(transportButtons.count * 44)
                + CGFloat((transportStack.arrangedSubviews.count - 1) * 4)
            seekSlider.bufferedRanges = [0...0.25, 0.5...0.75]
            seekSlider.layoutIfNeeded()
            return controlsStack.axis == .vertical
                && controlsStack.arrangedSubviews.first === networkStatusLabel
                && scrubberStack.arrangedSubviews == [timeLabel, seekSlider]
                && transportButtons.allSatisfy { button in
                    button.constraints.contains { $0.firstAttribute == .width && $0.constant == 44 }
                        && button.constraints.contains { $0.firstAttribute == .height && $0.constant == 44 }
                }
                && fixedTransportWidth <= 296
                && seekSlider.debugBufferedSegmentCount == 2
        }

        var debugControlsAutoHidePolicyProbePassed: Bool {
            Self.controlsAutoHideDelay == 4
                && Self.shouldAutoHideControls(
                    state: .playing,
                    isSeeking: false,
                    isPlaybackVisible: true,
                    isPictureInPictureActive: false,
                    isVoiceOverRunning: false,
                )
                && !Self.shouldAutoHideControls(
                    state: .paused,
                    isSeeking: false,
                    isPlaybackVisible: true,
                    isPictureInPictureActive: false,
                    isVoiceOverRunning: false,
                )
                && !Self.shouldAutoHideControls(
                    state: .playing,
                    isSeeking: true,
                    isPlaybackVisible: true,
                    isPictureInPictureActive: false,
                    isVoiceOverRunning: false,
                )
                && !Self.shouldAutoHideControls(
                    state: .playing,
                    isSeeking: false,
                    isPlaybackVisible: true,
                    isPictureInPictureActive: false,
                    isVoiceOverRunning: true,
                )
        }
    #endif

    func configure(
        file: File,
        thumbnail: Thumbnail?,
        minithumbnail: Minithumbnail?,
        canPlay: Bool,
        loops: Bool,
        mimeType: String? = nil,
        fileName: String? = nil,
        supportsStreaming: Bool = false,
        isSecret: Bool = false,
        startTimestamp: TimeInterval = 0,
        vodRanges: TDLibVODRangeCoordinator = TDLib.shared.vodRanges,
    ) {
        prepareForReuse()
        fileID = file.id
        sourceFile = file
        startPlaybackTimestamp = startTimestamp
        self.vodRanges = vodRanges
        loopsPlayback = loops
        if supportsStreaming,
           !isSecret,
           let mimeType,
           let fileName
        {
            vodConfiguration = VODConfiguration(
                fileName: fileName,
                mimeType: mimeType,
                startTimestamp: startTimestamp,
            )
        }
        videoSurface.isHidden = true
        if let thumbnail {
            preview.load(file: thumbnail.file, placeholderData: minithumbnail?.data)
        } else {
            preview.loadPlaceholder(data: minithumbnail?.data)
        }
        guard canPlay, UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true else { return }
        spinner.startAnimating()
        retryButton.isHidden = true
        controlsAreVisible = !loops
        controlsView.alpha = 1
        controlsView.isHidden = loops
        isUserPaused = false
        isMuted = false
        playbackRate = 1
        isSeeking = false
        resumeAfterSeeking = false
        currentPlaybackTime = 0
        playbackDuration = 0
        seekSlider.value = 0
        seekSlider.isEnabled = false
        updatePlaybackTime(0)
        updateControlIcons()
        configureVoiceOverObservation()
        playbackCancellable = player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state: state) }
        timeCancellable = player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.updatePlaybackTime(time) }
        durationCancellable = player.durationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in self?.updatePlaybackDuration(duration) }
        bufferedRangesCancellable = player.bufferedRangesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ranges in self?.updateBufferedRanges(ranges) }
        streamingStatusCancellable = player.streamingStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.renderStreamingStatus(status) }
        if file.local.isDownloadingCompleted {
            update(file: file)
        } else if supportsStreaming,
                  !isSecret,
                  let mimeType,
                  let fileName
        {
            startVOD(
                file: file,
                mimeType: mimeType,
                fileName: fileName,
                startTimestamp: startTimestamp,
            )
        } else {
            startLegacyDownload(file: file)
        }
    }

    func prepareForReuse() {
        cancelControlsAutoHide()
        controlsView.layer.removeAllAnimations()
        setPictureInPictureActive(false)
        cancelControlsAutoHide()
        onPictureInPictureToggle = nil
        onPictureInPictureEligibilityChanged = nil
        onPlaybackIntentChanged = nil
        loadIdentifier = nil
        sourceFile = nil
        usesLegacyDownload = false
        usesVOD = false
        player.stop()
        task?.cancel()
        task = nil
        playbackCancellable?.cancel()
        playbackCancellable = nil
        timeCancellable?.cancel()
        timeCancellable = nil
        durationCancellable?.cancel()
        durationCancellable = nil
        bufferedRangesCancellable?.cancel()
        bufferedRangesCancellable = nil
        streamingStatusCancellable?.cancel()
        streamingStatusCancellable = nil
        voiceOverCancellable?.cancel()
        voiceOverCancellable = nil
        preview.cancel()
        spinner.stopAnimating()
        retryButton.isHidden = true
        controlsView.isHidden = true
        controlsView.alpha = 1
        controlsAreVisible = false
        videoSurface.playerLayer.player = nil
        videoSurface.isHidden = true
        fileID = nil
        isPlaybackVisible = false
        isSurfaceReady = false
        loopsPlayback = false
        loadedPath = nil
        vodConfiguration = nil
        retryMode = nil
        retryStatusText = nil
        currentStreamingStatus = .idle
        startPlaybackTimestamp = 0
        surfaceItemIdentifier = nil
        currentPlaybackState = .idle
        isSeeking = false
        resumeAfterSeeking = false
        isUserPaused = false
        isMuted = false
        playbackRate = 1
        currentPlaybackTime = 0
        playbackDuration = 0
        bufferedRanges = []
        seekSlider.value = 0
        seekSlider.bufferedRanges = []
        seekSlider.isEnabled = false
        updatePlaybackTime(0)
        updateControlIcons()
        renderStreamingStatus(.idle)
        updatePictureInPictureEligibility()
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        if !isVisible, isSeeking {
            isSeeking = false
            resumeAfterSeeking = false
            seekSlider.value = Float(min(playbackDuration, currentPlaybackTime))
            updateTimeLabel(current: currentPlaybackTime)
        }
        isPlaybackVisible = isVisible
        if !isVisible {
            cancelControlsAutoHide()
        }
        if isPictureInPictureActive {
            return
        }
        if isVisible, !isUserPaused {
            player.play()
        } else {
            player.pause()
        }
    }

    func setPictureInPictureActive(_ isActive: Bool) {
        guard isPictureInPictureActive != isActive else { return }
        isPictureInPictureActive = isActive
        if isActive {
            cancelControlsAutoHide()
        }
        player.setExternalPlaybackControlActive(isActive)
        if !isActive {
            isUserPaused = !player.isPlaybackRequested
            if isPlaybackVisible, !isUserPaused {
                player.play()
            } else if !isPlaybackVisible {
                player.pause()
            }
            scheduleControlsAutoHideIfNeeded()
        }
        updateControlIcons()
        onPlaybackIntentChanged?()
    }

    func setPictureInPictureControl(visible: Bool, enabled: Bool, active: Bool) {
        pictureInPictureButton.isHidden = !visible
        pictureInPictureButton.isEnabled = enabled
        pictureInPictureButton.alpha = enabled ? 1 : 0.45
        pictureInPictureButton.setImage(
            UIImage(systemName: active ? "pip.exit" : "pip.enter"),
            for: .normal,
        )
        pictureInPictureButton.accessibilityLabel = active
            ? "Stop Picture in Picture"
            : "Start Picture in Picture"
    }

    func performPlaybackCommand(_ command: GalleryPlaybackCommand) {
        #if DEBUG
            debugPlaybackCommands.append(command)
        #endif
        switch command {
        case .jump(let interval):
            guard canSeekPlayback else { return }
            jumpPlayback(by: interval)
        case .togglePictureInPicture:
            togglePictureInPicture()
        case .togglePlayback:
            guard currentPlaybackState != .failed else { return }
            togglePlayback()
        }
    }

    func pauseForAudioTakeover() {
        isUserPaused = true
        player.pause()
        updateControlIcons()
        onPlaybackIntentChanged?()
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !loopsPlayback else { return false }
        if let touchedView = touch.view,
           touchedView.isDescendant(of: controlsView) || touchedView.isDescendant(of: retryButton)
        {
            return false
        }
        return true
    }

    // MARK: Private

    private struct VODConfiguration {
        let fileName: String
        let mimeType: String
        var startTimestamp: TimeInterval
    }

    private enum RetryMode {
        case fullDownload
        case vod
    }

    private let preview = TDImageLoadingView()
    private let videoSurface = LocalVideoSurfaceView(frame: .zero)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private let controlsView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let controlsStack = UIStackView()
    private let scrubberStack = UIStackView()
    private let transportStack = UIStackView()
    private let transportSpacer = UIView()
    private let networkStatusLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let jumpBackwardButton = UIButton(type: .system)
    private let jumpForwardButton = UIButton(type: .system)
    private let timeLabel = UILabel()
    private let seekSlider = GalleryBufferedSlider()
    private let muteButton = UIButton(type: .system)
    private let rateButton = UIButton(type: .system)
    private let pictureInPictureButton = UIButton(type: .system)
    private let player = LocalMediaPlayer()
    private var fileID: Int?
    private var task: Task<Void, Never>?
    private var playbackCancellable: AnyCancellable?
    private var timeCancellable: AnyCancellable?
    private var durationCancellable: AnyCancellable?
    private var bufferedRangesCancellable: AnyCancellable?
    private var streamingStatusCancellable: AnyCancellable?
    private var voiceOverCancellable: AnyCancellable?
    private var displayCancellable: AnyCancellable?
    private var isPlaybackVisible = false
    private var isSurfaceReady = false
    private var loopsPlayback = false
    private var loadedPath: String?
    private var loadIdentifier: UUID?
    private var sourceFile: File?
    private var startPlaybackTimestamp = TimeInterval.zero
    private var surfaceItemIdentifier: ObjectIdentifier?
    private var usesLegacyDownload = false
    private var usesVOD = false
    private var currentPlaybackState = LocalMediaPlayer.State.idle
    private var isSeeking = false
    private var resumeAfterSeeking = false
    private var isUserPaused = false
    private var isMuted = false
    private var playbackRate: Float = 1
    private var currentPlaybackTime = TimeInterval.zero
    private var playbackDuration = TimeInterval.zero
    private var bufferedRanges = [LocalMediaPlayer.BufferedRange]()
    private var currentStreamingStatus = TDLibVODResourceLoaderStatus.idle
    private var isPictureInPictureActive = false
    private var vodRanges = TDLib.shared.vodRanges
    private var controlsAreVisible = false
    private var controlsAutoHideWorkItem: DispatchWorkItem?
    private var vodConfiguration: VODConfiguration?
    private var retryMode: RetryMode?
    private var retryStatusText: String?
    #if DEBUG
        private var debugPlaybackCommands = [GalleryPlaybackCommand]()
    #endif

    private var canSeekPlayback: Bool {
        playbackDuration > 0 && currentPlaybackState != .failed
    }

    private func configurePlaybackControls() {
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.isHidden = true
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.axis = .vertical
        controlsStack.alignment = .fill
        controlsStack.spacing = 4
        controlsView.contentView.addSubview(controlsStack)
        scrubberStack.axis = .horizontal
        scrubberStack.alignment = .center
        scrubberStack.spacing = 8
        transportStack.axis = .horizontal
        transportStack.alignment = .center
        transportStack.spacing = 4
        transportSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        transportSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        networkStatusLabel.font = .preferredFont(forTextStyle: .caption2)
        networkStatusLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        networkStatusLabel.textAlignment = .center
        networkStatusLabel.adjustsFontForContentSizeCategory = true
        networkStatusLabel.adjustsFontSizeToFitWidth = true
        networkStatusLabel.minimumScaleFactor = 0.7
        networkStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        networkStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        playButton.tintColor = .white
        playButton.accessibilityLabel = "Play"
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        jumpBackwardButton.tintColor = .white
        jumpBackwardButton.setImage(UIImage(systemName: "gobackward.15"), for: .normal)
        jumpBackwardButton.accessibilityLabel = "Back 15 seconds"
        jumpBackwardButton.addTarget(self, action: #selector(jumpPlaybackBackward), for: .touchUpInside)
        jumpForwardButton.tintColor = .white
        jumpForwardButton.setImage(UIImage(systemName: "goforward.15"), for: .normal)
        jumpForwardButton.accessibilityLabel = "Forward 15 seconds"
        jumpForwardButton.addTarget(self, action: #selector(jumpPlaybackForward), for: .touchUpInside)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        timeLabel.text = "0:00 / 0:00"
        seekSlider.minimumValue = 0
        seekSlider.maximumValue = 1
        seekSlider.minimumTrackTintColor = .white
        seekSlider.maximumTrackTintColor = .clear
        seekSlider.isEnabled = false
        seekSlider.accessibilityLabel = "Video position"
        seekSlider.accessibilityHint = "Swipe up or down to seek"
        seekSlider.addTarget(self, action: #selector(beginSeeking), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(seekValueChanged), for: .valueChanged)
        seekSlider.addTarget(
            self,
            action: #selector(endSeeking),
            for: [.touchUpInside, .touchUpOutside, .touchCancel],
        )
        muteButton.tintColor = .white
        muteButton.accessibilityLabel = "Mute"
        muteButton.addTarget(self, action: #selector(toggleMuted), for: .touchUpInside)
        rateButton.setTitle("1×", for: .normal)
        rateButton.setTitleColor(.white, for: .normal)
        rateButton.accessibilityLabel = "Playback speed"
        rateButton.accessibilityHint = "Cycles through available playback speeds"
        rateButton.addTarget(self, action: #selector(cyclePlaybackRate), for: .touchUpInside)
        pictureInPictureButton.tintColor = .white
        pictureInPictureButton.isHidden = true
        pictureInPictureButton.accessibilityLabel = "Start Picture in Picture"
        pictureInPictureButton.addTarget(
            self,
            action: #selector(togglePictureInPicture),
            for: .touchUpInside,
        )

        scrubberStack.addArrangedSubview(timeLabel)
        scrubberStack.addArrangedSubview(seekSlider)
        transportStack.addArrangedSubview(jumpBackwardButton)
        transportStack.addArrangedSubview(playButton)
        transportStack.addArrangedSubview(jumpForwardButton)
        transportStack.addArrangedSubview(transportSpacer)
        transportStack.addArrangedSubview(muteButton)
        transportStack.addArrangedSubview(rateButton)
        transportStack.addArrangedSubview(pictureInPictureButton)
        controlsStack.addArrangedSubview(networkStatusLabel)
        controlsStack.addArrangedSubview(scrubberStack)
        controlsStack.addArrangedSubview(transportStack)
        updateControlIcons()
    }

    private func startVOD(
        file: File,
        mimeType: String,
        fileName: String,
        startTimestamp: TimeInterval,
    ) {
        usesVOD = true
        retryMode = nil
        retryStatusText = nil
        renderStreamingStatus(.loading)
        let identifier = UUID()
        loadIdentifier = identifier
        let rangeCoordinator = vodRanges
        task = Task { [weak self] in
            let lease = await rangeCoordinator.acquire(file: file)
            guard !Task.isCancelled else {
                await lease.invalidate()
                return
            }
            guard let session = TDLibVODResourceLoaderSession(
                lease: lease,
                mimeType: mimeType,
                fileName: fileName,
            ) else {
                await lease.invalidate()
                await MainActor.run {
                    guard let self,
                          self.loadIdentifier == identifier,
                          self.fileID == file.id
                    else { return }
                    self.task = nil
                    self.usesVOD = false
                    self.startLegacyDownload(file: file)
                }
                return
            }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      self.loadIdentifier == identifier,
                      self.fileID == file.id
                else {
                    session.invalidate()
                    return
                }
                self.task = nil
                self.prepareSurfaceForNewItem()
                self.player.load(
                    vodSession: session,
                    autoplay: self.isPlaybackVisible && !self.isUserPaused,
                    loops: self.loopsPlayback,
                    initialTime: startTimestamp,
                )
                self.player.setMuted(self.isMuted)
                self.player.setRate(self.playbackRate)
                self.bindSurfaceToCurrentItem()
            }
        }
    }

    private func startLegacyDownload(file: File) {
        guard file.id == fileID, !usesLegacyDownload else { return }
        spinner.startAnimating()
        retryButton.isHidden = true
        usesLegacyDownload = true
        usesVOD = false
        retryMode = nil
        retryStatusText = nil
        renderStreamingStatus(.loading)
        let identifier = UUID()
        loadIdentifier = identifier
        task?.cancel()
        let rangeCoordinator = vodRanges
        task = Task { [weak self] in
            let lease = await rangeCoordinator.acquire(
                file: file,
                requiresFullDownload: true,
            )
            let downloaded: File
            do {
                downloaded = try await lease.source.completedFile()
            } catch {
                let statusText = (error as? TDLibVODRangeError) == .offline
                    ? "Offline"
                    : "Couldn't load video"
                await lease.invalidate()
                await MainActor.run {
                    guard let self,
                          !Task.isCancelled,
                          self.fileID == file.id,
                          self.loadIdentifier == identifier,
                          self.usesLegacyDownload
                    else { return }
                    self.task = nil
                    self.usesLegacyDownload = false
                    self.showRetryState(statusText: statusText, retryMode: .fullDownload)
                }
                return
            }
            await lease.invalidate()
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard self.fileID == file.id,
                      self.loadIdentifier == identifier,
                      self.usesLegacyDownload
                else { return }
                self.task = nil
                self.usesLegacyDownload = false
                self.renderStreamingStatus(.idle)
                self.update(file: downloaded)
            }
        }
    }

    private func prepareSurfaceForNewItem() {
        surfaceItemIdentifier = nil
        isSurfaceReady = false
        videoSurface.playerLayer.player = nil
        videoSurface.isHidden = true
    }

    private func bindSurfaceToCurrentItem() {
        player.attach(to: videoSurface.playerLayer)
        surfaceItemIdentifier = player.currentItemIdentifier
        isSurfaceReady = false
        videoSurface.isHidden = true
        DispatchQueue.main.async { [weak self] in self?.refreshSurfaceReady() }
        updatePictureInPictureEligibility()
    }

    private func refreshSurfaceReady() {
        guard let surfaceItemIdentifier,
              player.currentItemIdentifier == surfaceItemIdentifier
        else { return }
        isSurfaceReady = videoSurface.playerLayer.isReadyForDisplay
        switch currentPlaybackState {
        case .ended, .paused, .playing:
            if isSurfaceReady {
                spinner.stopAnimating()
                videoSurface.isHidden = false
            } else {
                spinner.startAnimating()
                videoSurface.isHidden = true
            }
        default:
            videoSurface.isHidden = true
        }
        updatePictureInPictureEligibility()
    }

    private func update(file: File) {
        guard file.id == fileID,
              file.local.isDownloadingCompleted,
              loadedPath != file.local.path
        else { return }
        loadedPath = file.local.path
        prepareSurfaceForNewItem()
        player.load(
            url: URL(fileURLWithPath: file.local.path),
            autoplay: isPlaybackVisible && !isUserPaused,
            loops: loopsPlayback,
            initialTime: startPlaybackTimestamp,
        )
        player.setMuted(isMuted)
        player.setRate(playbackRate)
        bindSurfaceToCurrentItem()
    }

    private func render(state: LocalMediaPlayer.State) {
        currentPlaybackState = state
        switch state {
        case .idle:
            spinner.stopAnimating()
            videoSurface.isHidden = true
        case .buffering, .preparing:
            spinner.startAnimating()
        case .ended, .paused, .playing:
            if isSurfaceReady {
                spinner.stopAnimating()
                videoSurface.isHidden = false
            } else {
                spinner.startAnimating()
                videoSurface.isHidden = true
            }
        case .failed:
            spinner.stopAnimating()
            videoSurface.isHidden = true
            if usesVOD, let sourceFile {
                if currentStreamingStatus == .offline || currentStreamingStatus == .retrying {
                    vodConfiguration?.startTimestamp = currentPlaybackTime
                    usesVOD = false
                    prepareSurfaceForNewItem()
                    player.stop()
                    let statusText = currentStreamingStatus == .offline ? "Offline" : "Stream timed out"
                    showRetryState(statusText: statusText, retryMode: .vod)
                } else {
                    startPlaybackTimestamp = currentPlaybackTime
                    vodConfiguration?.startTimestamp = currentPlaybackTime
                    usesVOD = false
                    prepareSurfaceForNewItem()
                    player.stop()
                    startLegacyDownload(file: sourceFile)
                }
            } else if usesLegacyDownload || sourceFile != nil {
                usesLegacyDownload = false
                showRetryState(statusText: "Couldn't load video", retryMode: .fullDownload)
            }
        }
        updateControlIcons()
        onPlaybackIntentChanged?()
        updatePictureInPictureEligibility()
        renderStreamingStatus(currentStreamingStatus)
        switch state {
        case .playing:
            scheduleControlsAutoHideIfNeeded()
        case .buffering, .ended, .failed, .paused, .preparing:
            cancelControlsAutoHide()
            setControlsVisible(true, animated: true)
        case .idle:
            cancelControlsAutoHide()
        }
    }

    private func showRetryState(statusText: String, retryMode: RetryMode) {
        currentPlaybackState = .failed
        self.retryMode = retryMode
        retryStatusText = statusText
        spinner.stopAnimating()
        videoSurface.isHidden = true
        retryButton.isHidden = false
        updateControlIcons()
        renderStreamingStatus(currentStreamingStatus)
    }

    @objc private func togglePlayback() {
        guard currentPlaybackState != .failed else { return }
        revealControlsAndReschedule()
        let playbackWasRequested = isSeeking ? resumeAfterSeeking : player.isPlaybackRequested
        if playbackWasRequested {
            isUserPaused = true
            resumeAfterSeeking = false
            player.pause()
        } else {
            isUserPaused = false
            if isSeeking {
                resumeAfterSeeking = true
            } else if isPlaybackVisible {
                player.play()
            }
        }
        updateControlIcons()
    }

    @objc private func jumpPlaybackBackward() {
        jumpPlayback(by: -15)
    }

    @objc private func jumpPlaybackForward() {
        jumpPlayback(by: 15)
    }

    @objc private func beginSeeking() {
        guard seekSlider.isEnabled else { return }
        setControlsVisible(true, animated: false)
        cancelControlsAutoHide()
        isSeeking = true
        resumeAfterSeeking = !isUserPaused && player.isPlaybackRequested
        player.pause()
        updateControlIcons()
    }

    @objc private func seekValueChanged() {
        let time = TimeInterval(seekSlider.value)
        guard isSeeking else {
            let shouldResume = !isUserPaused && player.isPlaybackRequested
            player.pause()
            commitSeek(to: time, shouldResume: shouldResume)
            return
        }
        updateTimeLabel(current: time)
    }

    @objc private func endSeeking() {
        guard isSeeking else { return }
        let target = TimeInterval(seekSlider.value)
        let shouldResume = resumeAfterSeeking && !isUserPaused
        isSeeking = false
        resumeAfterSeeking = false
        commitSeek(to: target, shouldResume: shouldResume)
        scheduleControlsAutoHideIfNeeded()
    }

    @objc private func toggleMuted() {
        revealControlsAndReschedule()
        isMuted.toggle()
        player.setMuted(isMuted)
        updateControlIcons()
    }

    @objc private func cyclePlaybackRate() {
        revealControlsAndReschedule()
        playbackRate =
            switch playbackRate {
            case ..<1:
                1
            case ..<1.5:
                1.5
            case ..<2:
                2
            default:
                0.5
            }
        player.setRate(playbackRate)
        updateControlIcons()
    }

    @objc private func togglePictureInPicture() {
        revealControlsAndReschedule()
        onPictureInPictureToggle?()
    }

    @objc private func toggleControlsVisibility() {
        guard !loopsPlayback else { return }
        if UIAccessibility.isVoiceOverRunning {
            setControlsVisible(true, animated: false)
            cancelControlsAutoHide()
            return
        }
        setControlsVisible(!controlsAreVisible, animated: true)
        if controlsAreVisible {
            scheduleControlsAutoHideIfNeeded()
        }
    }

    private func updateControlIcons() {
        let playbackRequested = isSeeking ? resumeAfterSeeking : player.isPlaybackRequested
        let showsPause = playbackRequested && currentPlaybackState != .ended && currentPlaybackState != .failed
        playButton.setImage(UIImage(systemName: showsPause ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = showsPause ? "Pause" : "Play"
        playButton.isEnabled = currentPlaybackState != .failed
        let canSeek = canSeekPlayback
        seekSlider.isEnabled = canSeek
        jumpBackwardButton.isEnabled = canSeek
        jumpForwardButton.isEnabled = canSeek
        jumpBackwardButton.alpha = canSeek ? 1 : 0.45
        jumpForwardButton.alpha = canSeek ? 1 : 0.45

        muteButton.setImage(
            UIImage(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"),
            for: .normal,
        )
        muteButton.accessibilityLabel = isMuted ? "Unmute" : "Mute"
        muteButton.accessibilityValue = isMuted ? "Muted" : "Sound on"

        let rateTitle =
            switch playbackRate {
            case 0.5: "0.5×"
            case 1.5: "1.5×"
            case 2: "2×"
            default: "1×"
            }
        rateButton.setTitle(rateTitle, for: .normal)
        rateButton.accessibilityValue = rateTitle
    }

    private func revealControlsAndReschedule() {
        setControlsVisible(true, animated: true)
        scheduleControlsAutoHideIfNeeded()
    }

    private func configureVoiceOverObservation() {
        voiceOverCancellable?.cancel()
        voiceOverCancellable = NotificationCenter.default
            .publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if UIAccessibility.isVoiceOverRunning {
                    cancelControlsAutoHide()
                    setControlsVisible(true, animated: false)
                } else {
                    scheduleControlsAutoHideIfNeeded()
                }
            }
    }

    private func setControlsVisible(_ isVisible: Bool, animated: Bool) {
        guard !loopsPlayback else {
            controlsAreVisible = false
            controlsView.isHidden = true
            return
        }
        controlsAreVisible = isVisible
        if !isVisible {
            cancelControlsAutoHide()
        }
        if isVisible {
            controlsView.isHidden = false
        }
        let changes = { self.controlsView.alpha = isVisible ? 1 : 0 }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, controlsAreVisible == isVisible else { return }
            controlsView.isHidden = !isVisible
        }
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: changes,
                completion: completion,
            )
        } else {
            changes()
            completion(true)
        }
    }

    private func scheduleControlsAutoHideIfNeeded() {
        cancelControlsAutoHide()
        guard !hasBlockingStreamingStatus,
              controlsAreVisible,
              Self.shouldAutoHideControls(
                  state: currentPlaybackState,
                  isSeeking: isSeeking,
                  isPlaybackVisible: isPlaybackVisible,
                  isPictureInPictureActive: isPictureInPictureActive,
                  isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
              )
        else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !hasBlockingStreamingStatus,
                  Self.shouldAutoHideControls(
                      state: currentPlaybackState,
                      isSeeking: isSeeking,
                      isPlaybackVisible: isPlaybackVisible,
                      isPictureInPictureActive: isPictureInPictureActive,
                      isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
                  )
            else { return }
            setControlsVisible(false, animated: true)
        }
        controlsAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.controlsAutoHideDelay,
            execute: workItem,
        )
    }

    private func cancelControlsAutoHide() {
        controlsAutoHideWorkItem?.cancel()
        controlsAutoHideWorkItem = nil
    }

    private static let controlsAutoHideDelay = TimeInterval(4)

    private static func shouldAutoHideControls(
        state: LocalMediaPlayer.State,
        isSeeking: Bool,
        isPlaybackVisible: Bool,
        isPictureInPictureActive: Bool,
        isVoiceOverRunning: Bool,
    ) -> Bool {
        state == .playing
            && !isSeeking
            && isPlaybackVisible
            && !isPictureInPictureActive
            && !isVoiceOverRunning
    }

    private var hasBlockingStreamingStatus: Bool {
        usesLegacyDownload
            || retryStatusText != nil
            || currentStreamingStatus == .failed
            || currentStreamingStatus == .offline
            || currentStreamingStatus == .retrying
    }

    private func commitSeek(to target: TimeInterval, shouldResume: Bool) {
        currentPlaybackTime = target
        if shouldResume, isPlaybackVisible {
            player.play(from: target)
        } else {
            player.seek(to: target)
            player.pause()
        }
        updateTimeLabel(current: target)
        updateControlIcons()
    }

    private func jumpPlayback(by interval: TimeInterval) {
        guard canSeekPlayback else { return }
        revealControlsAndReschedule()
        let resolution = Self.resolveJump(
            current: currentPlaybackTime,
            duration: playbackDuration,
            interval: interval,
        )
        if resolution.shouldPauseAtStart {
            isUserPaused = true
            currentPlaybackTime = 0
            player.seek(to: 0, tolerance: 0)
            player.pause()
            seekSlider.value = 0
            updateTimeLabel(current: 0)
            updateControlIcons()
            onPlaybackIntentChanged?()
            return
        }
        let shouldResume = !isUserPaused && player.isPlaybackRequested
        player.pause()
        commitSeek(to: resolution.time, shouldResume: shouldResume)
    }

    private static func resolveJump(
        current: TimeInterval,
        duration: TimeInterval,
        interval: TimeInterval,
    ) -> (time: TimeInterval, shouldPauseAtStart: Bool) {
        let target = max(0, current + interval)
        if interval > 0, duration > 0, target >= duration {
            return (0, true)
        }
        return (target, false)
    }

    private func updatePictureInPictureEligibility() {
        onPictureInPictureEligibilityChanged?()
    }

    private func updatePlaybackTime(_ time: TimeInterval) {
        guard time.isFinite else { return }
        currentPlaybackTime = max(0, time)
        guard !isSeeking else { return }
        seekSlider.value = Float(min(playbackDuration, currentPlaybackTime))
        updateTimeLabel(current: currentPlaybackTime)
    }

    private func updatePlaybackDuration(_ duration: TimeInterval) {
        playbackDuration = duration.isFinite ? max(0, duration) : 0
        seekSlider.maximumValue = Float(max(1, playbackDuration))
        seekSlider.isEnabled = playbackDuration > 0
        if !isSeeking {
            seekSlider.value = Float(min(playbackDuration, currentPlaybackTime))
            updateTimeLabel(current: currentPlaybackTime)
        }
        refreshBufferedSliderRanges()
        updateControlIcons()
    }

    private func updateBufferedRanges(_ ranges: [LocalMediaPlayer.BufferedRange]) {
        bufferedRanges = ranges
        refreshBufferedSliderRanges()
    }

    private func renderStreamingStatus(_ status: TDLibVODResourceLoaderStatus) {
        let wasBlockingStreamingStatus = hasBlockingStreamingStatus
        currentStreamingStatus = status
        let text =
            if let retryStatusText {
                retryStatusText
            } else if usesLegacyDownload {
                "Downloading…"
            } else {
                switch status {
                case .offline:
                    "Offline"
                case .retrying:
                    "Retrying…"
                case .failed:
                    "Couldn't stream"
                case .loading:
                    if currentPlaybackState == .buffering || currentPlaybackState == .preparing {
                        "Buffering…"
                    } else {
                        ""
                    }
                case .idle, .ready:
                    currentPlaybackState == .buffering ? "Buffering…" : ""
                }
            }
        networkStatusLabel.text = text
        networkStatusLabel.accessibilityLabel = text.isEmpty ? nil : "Video status"
        networkStatusLabel.accessibilityValue = text.isEmpty ? nil : text
        networkStatusLabel.accessibilityElementsHidden = text.isEmpty
        if hasBlockingStreamingStatus || currentPlaybackState == .buffering {
            cancelControlsAutoHide()
            setControlsVisible(true, animated: true)
        } else if wasBlockingStreamingStatus {
            scheduleControlsAutoHideIfNeeded()
        }
    }

    private func refreshBufferedSliderRanges() {
        guard playbackDuration > 0 else {
            seekSlider.bufferedRanges = []
            return
        }
        let duration = Float(playbackDuration)
        seekSlider.bufferedRanges = bufferedRanges.compactMap { range in
            let lowerBound = min(1, max(0, Float(range.start) / duration))
            let upperBound = min(1, max(0, Float(range.end) / duration))
            guard upperBound > lowerBound else { return nil }
            return lowerBound...upperBound
        }
    }

    private func updateTimeLabel(current: TimeInterval) {
        let boundedCurrent = playbackDuration > 0
            ? min(playbackDuration, max(0, current))
            : max(0, current)
        let elapsed = formatPlaybackTime(boundedCurrent)
        let duration = formatPlaybackTime(playbackDuration)
        timeLabel.text = "\(elapsed) / \(duration)"
        seekSlider.accessibilityValue = "\(elapsed) of \(duration)"
    }

    private func formatPlaybackTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    @objc private func retryPlayback() {
        guard let sourceFile else { return }
        let retryMode = retryMode
        self.retryMode = nil
        retryStatusText = nil
        retryButton.isHidden = true
        loadedPath = nil
        switch retryMode {
        case .vod:
            guard let vodConfiguration else {
                startLegacyDownload(file: sourceFile)
                return
            }
            spinner.startAnimating()
            startVOD(
                file: sourceFile,
                mimeType: vodConfiguration.mimeType,
                fileName: vodConfiguration.fileName,
                startTimestamp: vodConfiguration.startTimestamp,
            )
        case .fullDownload, nil:
            startLegacyDownload(file: sourceFile)
        }
    }
}

// MARK: - GalleryBufferedSlider

final class GalleryBufferedSlider: UISlider {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundTrackLayer.backgroundColor = UIColor.white.withAlphaComponent(0.2).cgColor
        backgroundTrackLayer.cornerRadius = 2.5
        layer.insertSublayer(backgroundTrackLayer, at: 0)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    var bufferedRanges = [ClosedRange<Float>]() {
        didSet {
            setNeedsLayout()
        }
    }

    #if DEBUG
        var debugBufferedSegmentCount: Int {
            bufferedTrackLayers.count
        }
    #endif

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let rect = super.trackRect(forBounds: bounds)
        return CGRect(x: rect.minX, y: rect.midY - 2.5, width: rect.width, height: 5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let track = trackRect(forBounds: bounds)
        while bufferedTrackLayers.count < bufferedRanges.count {
            let bufferedLayer = CALayer()
            bufferedLayer.backgroundColor = UIColor.white.withAlphaComponent(0.45).cgColor
            bufferedLayer.cornerRadius = 2.5
            layer.insertSublayer(bufferedLayer, above: backgroundTrackLayer)
            bufferedTrackLayers.append(bufferedLayer)
        }
        while bufferedTrackLayers.count > bufferedRanges.count {
            bufferedTrackLayers.removeLast().removeFromSuperlayer()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundTrackLayer.frame = track
        for (range, bufferedLayer) in zip(bufferedRanges, bufferedTrackLayers) {
            let lowerBound = CGFloat(min(1, max(0, range.lowerBound)))
            let upperBound = CGFloat(min(1, max(0, range.upperBound)))
            bufferedLayer.frame = CGRect(
                x: track.minX + track.width * lowerBound,
                y: track.minY,
                width: track.width * max(0, upperBound - lowerBound),
                height: track.height,
            )
        }
        CATransaction.commit()
    }

    // MARK: Private

    private let backgroundTrackLayer = CALayer()
    private var bufferedTrackLayers = [CALayer]()
}
