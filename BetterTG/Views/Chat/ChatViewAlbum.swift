// ChatViewAlbum.swift

import Combine
import MobileVLCKit
import TDLibKit
import UIKit

final class MediaGalleryViewController: UIViewController, UICollectionViewDelegate {
    init(messages: [Message], selection: Int64) {
        self.messages = messages.filter { message in
            switch message.content {
            case .messagePhoto, .messageAnimation, .messageSticker, .messageVideo:
                true
            default:
                false
            }
        }
        selectedIndex = self.messages.firstIndex(where: { $0.id == selection }) ?? 0
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

    private let messages: [Message]
    private var selectedIndex: Int
    private var didSetInitialPosition = false
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
        selectedIndex = Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))
        updateCounter()
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
        let path: String? = switch message.content {
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

extension MediaGalleryViewController: UICollectionViewDataSource {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        messages.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MediaGalleryCell.reuseIdentifier,
            for: indexPath,
        ) as? MediaGalleryCell else { return UICollectionViewCell() }
        cell.configure(message: messages[indexPath.item])
        return cell
    }
}

final class MediaGalleryCell: UICollectionViewCell {
    static let reuseIdentifier = "MediaGalleryCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentMediaView?.prepareForReuse()
        contentMediaView?.removeFromSuperview()
        contentMediaView = nil
    }

    private var contentMediaView: (UIView & GalleryMediaView)?

    func configure(message: Message) {
        prepareForReuse()
        let view: (UIView & GalleryMediaView)
        switch message.content {
        case .messagePhoto(let photo):
            let imageView = ZoomableGalleryImageView()
            imageView.configure(photo: photo.photo)
            view = imageView
        case .messageAnimation(let animation):
            let player = GalleryFilePlayerView()
            player.configure(
                file: animation.animation.animation,
                thumbnail: animation.animation.thumbnail,
                minithumbnail: animation.animation.minithumbnail,
                canPlay: true,
            )
            view = player
        case .messageVideo(let video):
            let player = GalleryFilePlayerView()
            player.configure(
                file: video.video.video,
                thumbnail: video.video.thumbnail,
                minithumbnail: video.video.minithumbnail,
                canPlay: true,
            )
            view = player
        case .messageSticker(let sticker):
            let player = GalleryFilePlayerView()
            player.configure(
                file: sticker.sticker.sticker,
                thumbnail: sticker.sticker.thumbnail,
                minithumbnail: nil,
                canPlay: sticker.sticker.format == .stickerFormatWebm,
            )
            view = player
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
    }
}

protocol GalleryMediaView: AnyObject {
    func prepareForReuse()
}

final class ZoomableGalleryImageView: UIScrollView, UIScrollViewDelegate, GalleryMediaView {
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let imageView = TDImageLoadingView()

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

final class GalleryFilePlayerView: UIView, GalleryMediaView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.contentMode = .scaleAspectFit
        videoSurface.translatesAutoresizingMaskIntoConstraints = false
        videoSurface.backgroundColor = .black
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)
        addSubview(videoSurface)
        addSubview(spinner)
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
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let preview = TDImageLoadingView()
    private let videoSurface = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let player = VLCMediaPlayer()
    private var fileID: Int?
    private var task: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    func configure(file: File, thumbnail: Thumbnail?, minithumbnail: Minithumbnail?, canPlay: Bool) {
        prepareForReuse()
        fileID = file.id
        videoSurface.isHidden = true
        if let thumbnail {
            preview.load(file: thumbnail.file, placeholderData: minithumbnail?.data)
        } else {
            preview.load(file: file, placeholderData: minithumbnail?.data)
        }
        guard canPlay, UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true else { return }
        spinner.startAnimating()
        update(file: file)
        cancellable = nc.publisher(for: .updateFile)
            .receive(on: DispatchQueue.main)
            .filter { $0.file.id == file.id }
            .sink { [weak self] in self?.update(file: $0.file) }
        task = Task { [weak self] in
            let downloaded = try? await td.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 2,
                synchronous: false,
            )
            guard let self, let downloaded else { return }
            await MainActor.run { self.update(file: downloaded) }
        }
    }

    func prepareForReuse() {
        player.stop()
        player.media = nil
        task?.cancel()
        task = nil
        cancellable?.cancel()
        cancellable = nil
        preview.cancel()
        spinner.stopAnimating()
        videoSurface.isHidden = true
        if let fileID {
            Task { try? await td.cancelDownloadFile(fileId: fileID, onlyIfPending: true) }
        }
        fileID = nil
    }

    private func update(file: File) {
        guard file.id == fileID, file.local.isDownloadingCompleted else { return }
        spinner.stopAnimating()
        videoSurface.isHidden = false
        player.drawable = videoSurface
        player.media = VLCMedia(path: file.local.path)
        player.play()
    }
}
