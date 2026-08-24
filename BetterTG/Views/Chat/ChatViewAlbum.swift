// ChatViewAlbum.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MediaGalleryViewController

final class MediaGalleryViewController: UIViewController, UICollectionViewDelegate {
    // MARK: Private

    private let messages: [Message]
    private var selectedIndex: Int
    private var didSetInitialPosition = false
    private let toolbar = UIToolbar()
    private let counterLabel = UILabel()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())

    init(messages: [Message], selection: Int64) {
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            invalidatePlaybackOwners()
        }
    }

    private let messages: [Message]
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
        (cell as? MediaGalleryCell)?.setPlaybackVisible(indexPath.item == selectedIndex)
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
                .setPlaybackVisible(true)
            prunePlaybackOwners(around: selectedIndex)
            return
        }
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? MediaGalleryCell }?
            .setPlaybackVisible(false)
        selectedIndex = updatedIndex
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? MediaGalleryCell }?
            .setPlaybackVisible(true)
        updateCounter()
        prunePlaybackOwners(around: selectedIndex)
    }

    private func playbackOwner(for message: Message) -> GalleryVideoPlaybackOwner? {
        guard case .messageVideo = message.content else { return nil }
        if let owner = videoPlaybackOwners[message.id] {
            return owner
        }
        guard let owner = GalleryVideoPlaybackOwner(message: message) else { return nil }
        videoPlaybackOwners[message.id] = owner
        return owner
    }

    private func invalidatePlaybackOwners() {
        videoPlaybackOwners.values.forEach { $0.invalidate() }
        videoPlaybackOwners.removeAll()
    }

    private func prunePlaybackOwners(around index: Int) {
        guard messages.indices.contains(index) else { return }
        let lowerBound = max(messages.startIndex, index - 1)
        let upperBound = min(messages.index(before: messages.endIndex), index + 1)
        let retainedMessageIDs = Set(messages[lowerBound ... upperBound].compactMap { message -> Int64? in
            guard case .messageVideo = message.content else { return nil }
            return message.id
        })
        let evictedMessageIDs = videoPlaybackOwners.keys.filter { !retainedMessageIDs.contains($0) }
        for messageID in evictedMessageIDs {
            videoPlaybackOwners.removeValue(forKey: messageID)?.invalidate()
        }
    }

    @objc private func close() {
        invalidatePlaybackOwners()
        dismiss(animated: true)
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

@MainActor final class GalleryVideoPlaybackOwner {
    // MARK: Lifecycle

    init?(message: Message) {
        guard case .messageVideo(let video) = message.content else { return nil }
        messageID = message.id
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
        )
    }

    #if DEBUG
        private init(probeMessageID: Int64) {
            messageID = probeMessageID
        }
    #endif

    // MARK: Internal

    let messageID: Int64

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
        mediaView.setPlaybackVisible(false)
    }

    func detach(from container: UIView) {
        guard mediaView.superview === container else { return }
        isPlaybackVisible = false
        mediaView.setPlaybackVisible(false)
        mediaView.removeFromSuperview()
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        guard !isInvalidated else { return }
        self.isPlaybackVisible = isVisible
        mediaView.setPlaybackVisible(isVisible)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        isPlaybackVisible = false
        mediaView.removeFromSuperview()
        mediaView.prepareForReuse()
    }

    // MARK: Private

    private let mediaView = GalleryFilePlayerView()
    private var isInvalidated = false
    private var isPlaybackVisible = false

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
            owner.invalidate()
            let invalidatedCleanly = owner.isInvalidated
                && !owner.isPlaybackVisible
                && owner.mediaView.superview == nil

            if startsPaused, becameVisible, detachedWithoutInvalidation, reusedExactView, invalidatedCleanly {
                result = "Gallery playback owner probe: same-view=true, detach-retains-session=true, "
                    + "central-visibility=true, invalidate=true"
            } else {
                result = "Gallery playback owner probe failed: startsPaused=\(startsPaused), "
                    + "becameVisible=\(becameVisible), detached=\(detachedWithoutInvalidation), "
                    + "reused=\(reusedExactView), invalidated=\(invalidatedCleanly)"
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

    private weak var videoPlaybackOwner: GalleryVideoPlaybackOwner?
}

// MARK: - GalleryMediaView

protocol GalleryMediaView: AnyObject {
    func prepareForReuse()
    func setPlaybackVisible(_ isVisible: Bool)
}

extension GalleryMediaView {
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

final class GalleryFilePlayerView: UIView, GalleryMediaView {
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
            controlsView.heightAnchor.constraint(equalToConstant: 64),
            controlsStack.leadingAnchor.constraint(equalTo: controlsView.contentView.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: controlsView.contentView.trailingAnchor, constant: -12),
            controlsStack.topAnchor.constraint(equalTo: controlsView.contentView.topAnchor, constant: 8),
            controlsStack.bottomAnchor.constraint(equalTo: controlsView.contentView.bottomAnchor, constant: -8),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

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
    ) {
        prepareForReuse()
        fileID = file.id
        sourceFile = file
        startPlaybackTimestamp = startTimestamp
        loopsPlayback = loops
        videoSurface.isHidden = true
        if let thumbnail {
            preview.load(file: thumbnail.file, placeholderData: minithumbnail?.data)
        } else {
            preview.loadPlaceholder(data: minithumbnail?.data)
        }
        guard canPlay, UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true else { return }
        spinner.startAnimating()
        retryButton.isHidden = true
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
        playbackCancellable = player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state: state) }
        timeCancellable = player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.updatePlaybackTime(time) }
        durationCancellable = player.durationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in self?.updatePlaybackDuration(duration) }
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
        preview.cancel()
        spinner.stopAnimating()
        retryButton.isHidden = true
        controlsView.isHidden = true
        videoSurface.playerLayer.player = nil
        videoSurface.isHidden = true
        fileID = nil
        isPlaybackVisible = false
        isSurfaceReady = false
        loopsPlayback = false
        loadedPath = nil
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
        seekSlider.value = 0
        seekSlider.isEnabled = false
        updatePlaybackTime(0)
        updateControlIcons()
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        if !isVisible, isSeeking {
            isSeeking = false
            resumeAfterSeeking = false
            seekSlider.value = Float(min(playbackDuration, currentPlaybackTime))
            updateTimeLabel(current: currentPlaybackTime)
        }
        isPlaybackVisible = isVisible
        if isVisible, !isUserPaused {
            player.play()
        } else {
            player.pause()
        }
    }

    // MARK: Private

    private let preview = TDImageLoadingView()
    private let videoSurface = LocalVideoSurfaceView(frame: .zero)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private let controlsView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let controlsStack = UIStackView()
    private let playButton = UIButton(type: .system)
    private let timeLabel = UILabel()
    private let seekSlider = UISlider()
    private let muteButton = UIButton(type: .system)
    private let rateButton = UIButton(type: .system)
    private let player = LocalMediaPlayer()
    private var fileID: Int?
    private var task: Task<Void, Never>?
    private var playbackCancellable: AnyCancellable?
    private var timeCancellable: AnyCancellable?
    private var durationCancellable: AnyCancellable?
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

    private func configurePlaybackControls() {
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.isHidden = true
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.axis = .horizontal
        controlsStack.alignment = .center
        controlsStack.spacing = 10
        controlsView.contentView.addSubview(controlsStack)

        playButton.tintColor = .white
        playButton.accessibilityLabel = "Play"
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        timeLabel.text = "0:00 / 0:00"
        seekSlider.minimumValue = 0
        seekSlider.maximumValue = 1
        seekSlider.minimumTrackTintColor = .white
        seekSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.35)
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

        controlsStack.addArrangedSubview(playButton)
        controlsStack.addArrangedSubview(timeLabel)
        controlsStack.addArrangedSubview(seekSlider)
        controlsStack.addArrangedSubview(muteButton)
        controlsStack.addArrangedSubview(rateButton)
        updateControlIcons()
    }

    private func startVOD(
        file: File,
        mimeType: String,
        fileName: String,
        startTimestamp: TimeInterval,
    ) {
        usesVOD = true
        let identifier = UUID()
        loadIdentifier = identifier
        task = Task { [weak self] in
            let lease = await TDLib.shared.vodRanges.acquire(file: file)
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
        let identifier = UUID()
        loadIdentifier = identifier
        task?.cancel()
        task = Task { [weak self] in
            let lease = await TDLib.shared.vodRanges.acquire(
                file: file,
                requiresFullDownload: true,
            )
            let downloaded: File
            do {
                downloaded = try await lease.source.completedFile()
            } catch {
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
                    self.showRetryState()
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
                usesVOD = false
                prepareSurfaceForNewItem()
                player.stop()
                startLegacyDownload(file: sourceFile)
            } else if usesLegacyDownload || sourceFile != nil {
                usesLegacyDownload = false
                showRetryState()
            }
        }
        updateControlIcons()
    }

    private func showRetryState() {
        currentPlaybackState = .failed
        spinner.stopAnimating()
        videoSurface.isHidden = true
        retryButton.isHidden = false
        updateControlIcons()
    }

    @objc private func togglePlayback() {
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

    @objc private func beginSeeking() {
        guard seekSlider.isEnabled else { return }
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
    }

    @objc private func toggleMuted() {
        isMuted.toggle()
        player.setMuted(isMuted)
        updateControlIcons()
    }

    @objc private func cyclePlaybackRate() {
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

    private func updateControlIcons() {
        let playbackRequested = isSeeking ? resumeAfterSeeking : player.isPlaybackRequested
        let showsPause = playbackRequested && currentPlaybackState != .ended && currentPlaybackState != .failed
        playButton.setImage(UIImage(systemName: showsPause ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = showsPause ? "Pause" : "Play"
        playButton.isEnabled = currentPlaybackState != .failed

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
        retryButton.isHidden = true
        loadedPath = nil
        startLegacyDownload(file: sourceFile)
    }
}
