// GalleryLivePhotoView.swift

import PhotosUI
import TDLibKit
import UIKit

final class GalleryLivePhotoView: UIView, GalleryMediaView, UIScrollViewDelegate, PHLivePhotoViewDelegate {
    private let scroll = UIScrollView()
    private let mediaContainer = UIView()
    private let preview = TDImageLoadingView()
    private let liveView = PHLivePhotoView()
    private let liveButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var task: Task<Void, Never>?
    private var resources: LivePhotoResources?
    private var requestID: PHLivePhotoRequestID?
    private var playbackVisible = false
    private var didPlayHint = false
    private var generation = UUID()
    private var retry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.delegate = self
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        pin(scroll, to: self)
        mediaContainer.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(mediaContainer)
        NSLayoutConstraint.activate([
            mediaContainer.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            mediaContainer.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            mediaContainer.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            mediaContainer.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            mediaContainer.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            mediaContainer.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        preview.contentMode = .scaleAspectFit
        preview.isUserInteractionEnabled = false
        pin(preview, to: mediaContainer)
        liveView.contentMode = .scaleAspectFit
        liveView.delegate = self
        liveView.isHidden = true
        pin(liveView, to: mediaContainer)
        liveButton.setImage(UIImage(systemName: "livephoto"), for: .normal)
        liveButton.setTitle(" LIVE", for: .normal)
        liveButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        liveButton.tintColor = .white
        liveButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        liveButton.layer.cornerRadius = 14
        liveButton.accessibilityLabel = "Play Live Photo"
        liveButton.accessibilityIdentifier = "gallery-live-photo-play"
        liveButton.addTarget(self, action: #selector(play), for: .touchUpInside)
        addSubview(liveButton)
        spinner.color = .white
        addSubview(spinner)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        liveButton.frame = CGRect(
            x: max(16, safeAreaInsets.left + 8),
            y: safeAreaInsets.top + 52,
            width: 86,
            height: 30,
        )
        spinner.center = CGPoint(x: liveButton.frame.maxX + 18, y: liveButton.center.y)
    }

    func configure(_ content: MessagePhoto) {
        prepareForReuse()
        preview.load(photo: content.photo, preferredSize: .yBox, maximumPixelSize: 2048)
        guard let video = content.video, !content.isSecret,
              let size = content.photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return }
        let client = TDLib.shared.activeClient
        let currentGeneration = generation
        retry = { [weak self] in self?.load(
            photo: size.photo,
            video: video.video,
            client: client,
            generation: currentGeneration,
        ) }
        retry?()
    }

    func prepareForReuse() {
        generation = UUID()
        task?.cancel()
        task = nil
        if let requestID { PHLivePhoto.cancelRequest(withRequestID: requestID) }
        requestID = nil
        liveView.stopPlayback()
        liveView.livePhoto = nil
        liveView.isHidden = true
        resources?.cleanup()
        resources = nil
        preview.cancel()
        scroll.setZoomScale(1, animated: false)
        didPlayHint = false
        playbackVisible = false
        retry = nil
    }

    func makeTransitionSnapshot() -> UIView? { preview.makeImageSnapshot(contentMode: .scaleAspectFit) }
    func viewForZooming(in _: UIScrollView) -> UIView? { mediaContainer }

    func setPlaybackVisible(_ visible: Bool) {
        playbackVisible = visible
        if visible { playHintIfNeeded() } else { liveView.stopPlayback() }
    }

    func setGalleryChromeVisible(_ visible: Bool, animated: Bool) {
        let update = { self.liveButton.alpha = visible ? 1.0 : 0.0 }
        if animated { UIView.animate(withDuration: 0.2, animations: update) } else { update() }
    }

    func canBeginInteractiveDismissal(at point: CGPoint) -> Bool {
        scroll.zoomScale <= 1.001 && !scroll.isZooming && !scroll.isDecelerating && !liveButton.frame.contains(point)
    }

    func setInteractiveDismissalActive(_ active: Bool) {
        scroll.panGestureRecognizer.isEnabled = !active
        scroll.pinchGestureRecognizer?.isEnabled = !active
        if active { liveView.stopPlayback() }
    }

    func performPlaybackCommand(_ command: GalleryPlaybackCommand) { if command == .togglePlayback { play() } }

    private func load(photo: File, video: File, client: TDLibClient, generation: UUID) {
        guard self.generation == generation, TDLib.shared.activeClient.id == client.id else { return }
        task?.cancel()
        if let requestID { PHLivePhoto.cancelRequest(withRequestID: requestID) }
        requestID = nil
        resources?.cleanup()
        resources = nil
        spinner.startAnimating()
        liveButton.isEnabled = false
        task = Task { [weak self] in
            do {
                async let imageRequest = client.downloadFile(
                    fileId: photo.id,
                    limit: 0,
                    offset: 0,
                    priority: 16,
                    synchronous: true,
                )
                async let videoRequest = client.downloadFile(
                    fileId: video.id,
                    limit: 0,
                    offset: 0,
                    priority: 16,
                    synchronous: true,
                )
                let (image, video) = try await (imageRequest, videoRequest)
                try Task.checkCancellation()
                guard image.local.isDownloadingCompleted,
                      video.local.isDownloadingCompleted else { throw CocoaError(.fileReadUnknown) }
                let pair = try await LivePhotoResources.prepare(
                    photo: URL(fileURLWithPath: image.local.path),
                    video: URL(fileURLWithPath: video.local.path),
                )
                guard let self, !Task.isCancelled, self.generation == generation,
                      TDLib.shared.activeClient.id == client.id
                else {
                    pair.cleanup()
                    return
                }
                resources = pair
                requestID = PHLivePhoto.request(
                    withResourceFileURLs: [pair.photo, pair.video],
                    placeholderImage: preview.image,
                    targetSize: bounds.size,
                    contentMode: .aspectFit,
                ) { [weak self] livePhoto, info in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == generation,
                              TDLib.shared.activeClient.id == client.id else { return }
                        if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                        spinner.stopAnimating()
                        liveButton.isEnabled = true
                        guard let livePhoto else {
                            liveButton.setTitle(" Retry", for: .normal)
                            return
                        }
                        liveView.livePhoto = livePhoto
                        liveView.isHidden = false
                        liveButton.setTitle(" LIVE", for: .normal)
                        playHintIfNeeded()
                    }
                }
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                spinner.stopAnimating()
                liveButton.isEnabled = true
                liveButton.setTitle(" Retry", for: .normal)
            }
        }
    }

    private func playHintIfNeeded() {
        guard playbackVisible, !didPlayHint, liveView.livePhoto != nil else { return }
        didPlayHint = true
        liveView.startPlayback(with: .hint)
    }

    @objc private func play() {
        if liveView.livePhoto != nil { liveView.startPlayback(with: .full) } else { retry?() }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: true) }
        else {
            let point = gesture.location(in: mediaContainer)
            let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
            scroll.zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height,
                ),
                animated: true,
            )
        }
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }
}
