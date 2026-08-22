// MessageContentView.swift

import Combine
import ImageIO
import TDLibKit
import UIKit

// MARK: - MessageMediaView

final class MessageMediaView: UIView {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 13
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    @discardableResult func configure(
        message: CustomMessage,
        onTap: @escaping ([Message], Int64) -> Void,
    ) -> Bool {
        prepareForReuse()
        let view: UIView?
        if !message.album.isEmpty {
            let albumView = AlbumMediaView()
            albumView.configure(messages: message.album, onTap: onTap)
            view = albumView
        } else {
            switch message.message.content {
            case .messagePhoto(let photo):
                let photoView = SinglePhotoView()
                photoView.configure(photo: photo.photo) { onTap([message.message], message.id) }
                view = photoView
            case .messageVoiceNote(let voice):
                let voiceView = VoiceNotePlaybackView()
                voiceView.configure(voiceNote: voice.voiceNote)
                view = voiceView
            case .messageAnimation(let animation):
                let fileView = FileMediaPreviewView()
                fileView.configure(
                    file: animation.animation.animation,
                    thumbnail: animation.animation.thumbnail,
                    minithumbnail: animation.animation.minithumbnail,
                    size: CGSize(width: animation.animation.width, height: animation.animation.height),
                    showsPlayIcon: true,
                ) { onTap([message.message], message.id) }
                view = fileView
            case .messageSticker(let sticker):
                let fileView = FileMediaPreviewView()
                fileView.configure(
                    file: sticker.sticker.sticker,
                    thumbnail: sticker.sticker.thumbnail,
                    minithumbnail: nil,
                    size: CGSize(width: sticker.sticker.width, height: sticker.sticker.height),
                    showsPlayIcon: sticker.sticker.format != .stickerFormatWebp,
                ) { onTap([message.message], message.id) }
                view = fileView
            case .messageVideo(let video):
                let fileView = FileMediaPreviewView()
                fileView.configure(
                    file: video.video.video,
                    thumbnail: video.video.thumbnail,
                    minithumbnail: video.video.minithumbnail,
                    size: CGSize(width: video.video.width, height: video.video.height),
                    showsPlayIcon: true,
                ) { onTap([message.message], message.id) }
                view = fileView
            default:
                view = nil
            }
        }
        guard let view else { return false }
        contentView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        return true
    }

    func prepareForReuse() {
        (contentView as? ReusableMediaView)?.prepareForReuse()
        contentView?.removeFromSuperview()
        contentView = nil
    }

    // MARK: Private

    private var contentView: UIView?
}

// MARK: - ReusableMediaView

protocol ReusableMediaView where Self: UIView {
    func prepareForReuse()
}

// MARK: - SinglePhotoView

final class SinglePhotoView: UIControl, ReusableMediaView {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 220),
            widthAnchor.constraint(equalToConstant: 280),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    func configure(photo: Photo, onTap: @escaping () -> Void) {
        self.onTap = onTap
        imageView.load(photo: photo, preferredSize: .yBox)
    }

    func prepareForReuse() {
        imageView.cancel()
        onTap = nil
    }

    // MARK: Private

    private let imageView = TDImageLoadingView()
    private var onTap: (() -> Void)?

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - AlbumMediaView

final class AlbumMediaView: UIView, ReusableMediaView {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        heightAnchor.constraint(equalToConstant: 240).isActive = true
        widthAnchor.constraint(equalToConstant: 280).isActive = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        let spacing = CGFloat(1)
        let count = imageViews.count
        guard count > 0 else { return }
        if count == 1 {
            imageViews[0].frame = bounds
            return
        }
        if count == 2 {
            let width = (bounds.width - spacing) / 2
            imageViews[0].frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            imageViews[1].frame = CGRect(x: width + spacing, y: 0, width: width, height: bounds.height)
            return
        }
        let columns = 2
        let rows = Int(ceil(Double(count) / Double(columns)))
        let itemWidth = (bounds.width - spacing) / CGFloat(columns)
        let itemHeight = (bounds.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        for (index, imageView) in imageViews.enumerated() {
            let row = index / columns
            let column = index % columns
            imageView.frame = CGRect(
                x: CGFloat(column) * (itemWidth + spacing),
                y: CGFloat(row) * (itemHeight + spacing),
                width: itemWidth,
                height: itemHeight,
            )
        }
    }

    func configure(messages: [Message], onTap: @escaping ([Message], Int64) -> Void) {
        prepareForReuse()
        self.messages = messages
        self.onTap = onTap
        for (index, message) in messages.enumerated() {
            guard case .messagePhoto(let photo) = message.content else { continue }
            let imageView = TDImageLoadingView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.tag = index
            imageView.isUserInteractionEnabled = true
            imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(imageTapped(_:))))
            imageView.load(photo: photo.photo, preferredSize: .yBox)
            addSubview(imageView)
            imageViews.append(imageView)
        }
        setNeedsLayout()
    }

    func prepareForReuse() {
        for imageView in imageViews {
            imageView.cancel()
            imageView.removeFromSuperview()
        }
        imageViews.removeAll()
        messages.removeAll()
        onTap = nil
    }

    // MARK: Private

    private var imageViews = [TDImageLoadingView]()
    private var messages = [Message]()
    private var onTap: (([Message], Int64) -> Void)?

    @objc private func imageTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag, messages.indices.contains(index) else { return }
        onTap?(messages, messages[index].id)
    }
}

// MARK: - FileMediaPreviewView

final class FileMediaPreviewView: UIControl, ReusableMediaView {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playIcon.image = UIImage(systemName: "play.circle.fill")
        playIcon.tintColor = .white
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 46)
        addSubview(imageView)
        addSubview(playIcon)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 220),
            widthAnchor.constraint(equalToConstant: 280),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    func configure(
        file: File,
        thumbnail: Thumbnail?,
        minithumbnail: Minithumbnail?,
        size _: CGSize,
        showsPlayIcon: Bool,
        onTap: @escaping () -> Void,
    ) {
        self.onTap = onTap
        playIcon.isHidden = !showsPlayIcon
        if let thumbnail {
            imageView.load(file: thumbnail.file, placeholderData: minithumbnail?.data)
        } else {
            imageView.load(file: file, placeholderData: minithumbnail?.data)
        }
    }

    func prepareForReuse() {
        imageView.cancel()
        onTap = nil
    }

    // MARK: Private

    private let imageView = TDImageLoadingView()
    private let playIcon = UIImageView()
    private var onTap: (() -> Void)?

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - TDImageLoadingView

final class TDImageLoadingView: UIImageView {
    // MARK: Internal

    private(set) var loadedPath: String?

    func load(photo: Photo, preferredSize: PhotoSizeType) {
        let placeholderData = photo.minithumbnail?.data
        guard let size = photo.sizes.getSize(preferredSize) ?? photo.sizes.first else {
            image = placeholderData.flatMap(UIImage.init(data:))
            return
        }
        load(file: size.photo, placeholderData: placeholderData)
    }

    func load(file: File, placeholderData: Data? = nil, maximumPixelSize: Int = 1280) {
        cancel()
        self.maximumPixelSize = maximumPixelSize
        representedFileID = file.id
        image = placeholderData.flatMap(UIImage.init(data:))
        if let cached = Self.cache.object(forKey: NSNumber(value: file.id)) {
            image = cached
            return
        }
        update(file: file)
        cancellable = nc.publisher(for: .updateFile)
            .receive(on: DispatchQueue.main)
            .filter { $0.file.id == file.id }
            .sink { [weak self] update in self?.update(file: update.file) }
        downloadTask = Task { [weak self] in
            let downloaded = try? await td.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            )
            guard let self, let downloaded else { return }
            await MainActor.run { self.update(file: downloaded) }
        }
    }

    func cancel() {
        let fileID = representedFileID
        representedFileID = nil
        downloadTask?.cancel()
        downloadTask = nil
        cancellable?.cancel()
        cancellable = nil
        loadedPath = nil
        if let fileID {
            Task { try? await td.cancelDownloadFile(fileId: fileID, onlyIfPending: true) }
        }
    }

    // MARK: Private

    private static let cache: NSCache<NSNumber, UIImage> = {
        let cache = NSCache<NSNumber, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    private var representedFileID: Int?
    private var downloadTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private var maximumPixelSize = 1280

    private func update(file: File) {
        guard representedFileID == file.id, file.local.isDownloadingCompleted else { return }
        let path = file.local.path
        let maximumPixelSize = maximumPixelSize
        loadedPath = path
        Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) {
                downsampledImage(at: path, maximumPixelSize: maximumPixelSize)
            }.value
            await MainActor.run {
                guard let self, self.representedFileID == file.id, let decoded else { return }
                let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale * 4)
                Self.cache.setObject(decoded, forKey: NSNumber(value: file.id), cost: cost)
                self.image = decoded
            }
        }
    }
}

// MARK: - TDMediaPrefetcher

enum TDMediaPrefetcher {
    static func prefetch(message: Message) async {
        let fileIDs: [Int] =
            switch message.content {
            case .messagePhoto(let photo):
                photo.photo.sizes.getSize(.yBox).map { [$0.photo.id] } ?? []
            case .messageVoiceNote(let voice):
                [voice.voiceNote.voice.id]
            case .messageAnimation(let animation):
                [animation.animation.thumbnail?.file.id ?? animation.animation.animation.id]
            case .messageSticker(let sticker):
                [sticker.sticker.thumbnail?.file.id ?? sticker.sticker.sticker.id]
            case .messageVideo(let video):
                [video.video.thumbnail?.file.id ?? video.video.video.id]
            default:
                []
            }
        for fileID in fileIDs where !Task.isCancelled {
            await withTaskCancellationHandler {
                _ = try? await td.downloadFile(
                    fileId: fileID,
                    limit: 0,
                    offset: 0,
                    priority: 1,
                    synchronous: false,
                )
            } onCancel: {
                Task { try? await td.cancelDownloadFile(fileId: fileID, onlyIfPending: true) }
            }
        }
    }
}

private func downsampledImage(at path: String, maximumPixelSize: Int) -> UIImage? {
    guard FileManager.default.fileExists(atPath: path),
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
              kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: cgImage)
}
