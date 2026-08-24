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
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        selectedIndex = Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))
        updateCounter()
    }

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
        selectedIndex = Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))
        updateCounter()
    }

    func collectionView(
        _: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt _: IndexPath,
    ) {
        (cell as? MediaGalleryCell)?.setPlaybackVisible(true)
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

    @objc private func close() {
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
        cell.configure(message: messages[indexPath.item])
        return cell
    }
}

// MARK: - MediaGalleryCell

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
        contentMediaView?.prepareForReuse()
        contentMediaView?.removeFromSuperview()
        contentMediaView = nil
    }

    func configure(message: Message) {
        prepareForReuse()
        let view: UIView & GalleryMediaView
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
        case .messageVideo(let video):
            let player = GalleryFilePlayerView()
            player.configure(
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
            view = player
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
        view.setPlaybackVisible(window != nil)
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        contentMediaView?.setPlaybackVisible(isVisible)
    }
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
        addSubview(preview)
        addSubview(videoSurface)
        addSubview(spinner)
        addSubview(retryButton)
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
            preview.load(file: file, placeholderData: minithumbnail?.data)
        }
        guard canPlay, UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true else { return }
        spinner.startAnimating()
        retryButton.isHidden = true
        playbackCancellable = player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state: state) }
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
        preview.cancel()
        spinner.stopAnimating()
        retryButton.isHidden = true
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
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        isPlaybackVisible = isVisible
        if isVisible {
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
    private let player = LocalMediaPlayer()
    private var fileID: Int?
    private var task: Task<Void, Never>?
    private var playbackCancellable: AnyCancellable?
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
                    autoplay: self.isPlaybackVisible,
                    loops: self.loopsPlayback,
                    initialTime: startTimestamp,
                )
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
            autoplay: isPlaybackVisible,
            loops: loopsPlayback,
            initialTime: startPlaybackTimestamp,
        )
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
    }

    private func showRetryState() {
        currentPlaybackState = .failed
        spinner.stopAnimating()
        videoSurface.isHidden = true
        retryButton.isHidden = false
    }

    @objc private func retryPlayback() {
        guard let sourceFile else { return }
        retryButton.isHidden = true
        loadedPath = nil
        startLegacyDownload(file: sourceFile)
    }
}
