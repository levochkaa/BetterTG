// MessageContentView.swift

import Combine
import ImageIO
import TDLibKitDynamic
import UIKit

// MARK: - MessageMediaView

final class MessageMediaView: UIView {
    // MARK: Private

    private var contentView: UIView?

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
            case .messageVideoNote(let video):
                let videoNoteView = VideoNotePlaybackView()
                videoNoteView.configure(
                    videoNote: video.videoNote,
                    isSecret: video.isSecret,
                    chatID: message.message.chatId,
                    messageID: message.id,
                )
                view = videoNoteView
            case .messageAnimation(let animation):
                if telegramAnimationUsesFFmpeg(animation.animation) {
                    let animationView = FFmpegAnimatedVideoView()
                    animationView.configure(
                        file: animation.animation.animation,
                        thumbnail: animation.animation.thumbnail,
                        displaySize: telegramMediaDisplaySize(source: CGSize(
                            width: animation.animation.width,
                            height: animation.animation.height,
                        )),
                        onTap: { onTap([message.message], message.id) },
                    )
                    view = animationView
                } else {
                    let fileView = FileMediaPreviewView()
                    fileView.configure(
                        file: animation.animation.animation,
                        thumbnail: animation.animation.thumbnail,
                        minithumbnail: animation.animation.minithumbnail,
                        size: CGSize(width: animation.animation.width, height: animation.animation.height),
                        showsPlayIcon: true,
                    ) { onTap([message.message], message.id) }
                    view = fileView
                }
            case .messageSticker(let sticker):
                if sticker.sticker.format == .stickerFormatTgs {
                    let stickerView = TGSStickerView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: telegramMediaDisplaySize(source: CGSize(
                            width: sticker.sticker.width,
                            height: sticker.sticker.height,
                        )),
                        onTap: { onTap([message.message], message.id) },
                    )
                    view = stickerView
                } else if sticker.sticker.format == .stickerFormatWebp {
                    let stickerView = AnimatedWebPView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: telegramMediaDisplaySize(source: CGSize(
                            width: sticker.sticker.width,
                            height: sticker.sticker.height,
                        )),
                        onTap: { onTap([message.message], message.id) },
                    )
                    view = stickerView
                } else if sticker.sticker.format == .stickerFormatWebm {
                    let stickerView = FFmpegAnimatedVideoView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: telegramMediaDisplaySize(source: CGSize(
                            width: sticker.sticker.width,
                            height: sticker.sticker.height,
                        )),
                        onTap: { onTap([message.message], message.id) },
                    )
                    view = stickerView
                } else {
                    let fileView = FileMediaPreviewView()
                    fileView.configure(
                        file: sticker.sticker.sticker,
                        thumbnail: sticker.sticker.thumbnail,
                        minithumbnail: nil,
                        size: CGSize(width: sticker.sticker.width, height: sticker.sticker.height),
                        showsPlayIcon: sticker.sticker.format != .stickerFormatWebp,
                    ) { onTap([message.message], message.id) }
                    view = fileView
                }
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
        (view as? ReusableMediaView)?.setPlaybackVisible(window != nil)
        return true
    }

    func prepareForReuse() {
        (contentView as? ReusableMediaView)?.prepareForReuse()
        contentView?.removeFromSuperview()
        contentView = nil
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        (contentView as? ReusableMediaView)?.setPlaybackVisible(isVisible)
    }

    // MARK: Private

    private var contentView: UIView?
}

// MARK: - ReusableMediaView

protocol ReusableMediaView where Self: UIView {
    func prepareForReuse()
    func setPlaybackVisible(_ isVisible: Bool)
}

extension ReusableMediaView {
    func setPlaybackVisible(_: Bool) {}
}

extension TGSStickerView: ReusableMediaView {}
extension AnimatedWebPView: ReusableMediaView {}
extension FFmpegAnimatedVideoView: ReusableMediaView {}

// MARK: - SinglePhotoView

final class SinglePhotoView: UIControl, ReusableMediaView {
    // MARK: Private

    private let imageView = TDImageLoadingView()
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 280)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 220)
    private var onTap: (() -> Void)?

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
            heightConstraint,
            widthConstraint,
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    func configure(photo: Photo, onTap: @escaping () -> Void) {
        self.onTap = onTap
        let displaySize = telegramMediaDisplaySize(source: telegramPhotoSize(photo))
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        imageView.load(photo: photo, preferredSize: .yBox)
    }

    func prepareForReuse() {
        imageView.cancel()
        onTap = nil
    }

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - AlbumMediaView

final class AlbumMediaView: UIView, ReusableMediaView {
    // MARK: Private

    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 280)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 240)
    private var tiles = [AlbumMediaTileView]()
    private var itemFrames = [CGRect]()
    private var messages = [Message]()
    private var onTap: (([Message], Int64) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 13
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        for (tile, frame) in zip(tiles, itemFrames) {
            tile.frame = frame
        }
    }

    func configure(messages: [Message], onTap: @escaping ([Message], Int64) -> Void) {
        prepareForReuse()
        self.messages = messages
        self.onTap = onTap
        let itemSizes = messages.map(telegramMessageMediaSize)
        let (layout, size) = telegramMessageBubbleMosaicLayout(
            maxSize: CGSize(width: 280, height: 320),
            itemSizes: itemSizes,
        )
        itemFrames = layout.map(\.0)
        widthConstraint.constant = size.width
        heightConstraint.constant = size.height
        for (index, message) in messages.enumerated() {
            let tile = AlbumMediaTileView()
            tile.tag = index
            tile.addTarget(self, action: #selector(tileTapped(_:)), for: .touchUpInside)
            tile.configure(message: message)
            if layout.indices.contains(index) {
                tile.apply(position: layout[index].1)
            }
            addSubview(tile)
            tiles.append(tile)
        }
        setNeedsLayout()
    }

    func prepareForReuse() {
        for tile in tiles {
            tile.prepareForReuse()
            tile.removeFromSuperview()
        }
        tiles.removeAll()
        itemFrames.removeAll()
        messages.removeAll()
        onTap = nil
    }

    @objc private func tileTapped(_ sender: UIControl) {
        let index = sender.tag
        guard messages.indices.contains(index) else { return }
        onTap?(messages, messages[index].id)
    }
}

// MARK: - AlbumMediaTileView

private final class AlbumMediaTileView: UIControl, ReusableMediaView {
    // MARK: Private

    private let imageView = TDImageLoadingView()
    private let playIcon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFill
        playIcon.image = UIImage(systemName: "play.circle.fill")
        playIcon.tintColor = .white
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30)
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        addSubview(playIcon)
        NSLayoutConstraint.activate([
            playIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    func configure(message: Message) {
        switch message.content {
        case .messagePhoto(let photo):
            playIcon.isHidden = true
            imageView.load(photo: photo.photo, preferredSize: .yBox)
        case .messageVideo(let video):
            playIcon.isHidden = false
            if let thumbnail = video.video.thumbnail {
                imageView.load(file: thumbnail.file, placeholderData: video.video.minithumbnail?.data)
            } else {
                imageView.load(file: video.video.video, placeholderData: video.video.minithumbnail?.data)
            }
        case .messageAnimation(let animation):
            playIcon.isHidden = false
            if let thumbnail = animation.animation.thumbnail {
                imageView.load(file: thumbnail.file, placeholderData: animation.animation.minithumbnail?.data)
            } else {
                imageView.load(
                    file: animation.animation.animation,
                    placeholderData: animation.animation.minithumbnail?.data,
                )
            }
        default:
            playIcon.isHidden = true
        }
    }

    func apply(position: TelegramMosaicItemPosition) {
        var corners = CACornerMask()
        if position.contains([.top, .left]) {
            corners.insert(.layerMinXMinYCorner)
        }
        if position.contains([.top, .right]) {
            corners.insert(.layerMaxXMinYCorner)
        }
        if position.contains([.bottom, .left]) {
            corners.insert(.layerMinXMaxYCorner)
        }
        if position.contains([.bottom, .right]) {
            corners.insert(.layerMaxXMaxYCorner)
        }
        layer.cornerRadius = corners.isEmpty ? 0 : 13
        layer.maskedCorners = corners
    }

    func prepareForReuse() {
        imageView.cancel()
    }
}

// MARK: - FileMediaPreviewView

final class FileMediaPreviewView: UIControl, ReusableMediaView {
    // MARK: Private

    private let imageView = TDImageLoadingView()
    private let playIcon = UIImageView()
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 280)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 220)
    private var onTap: (() -> Void)?

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
            heightConstraint,
            widthConstraint,
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
        size: CGSize,
        showsPlayIcon: Bool,
        onTap: @escaping () -> Void,
    ) {
        self.onTap = onTap
        let displaySize = telegramMediaDisplaySize(source: size)
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
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

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - TDImageLoadingView

final class TDImageLoadingView: UIImageView {
    // MARK: Private

    private struct RequestIdentity: Equatable {
        let accountID: UUID?
        let clientID: Int32
        let fileID: Int
        let generation: UUID

        var cacheKey: NSString {
            let accountNamespace = accountID?.uuidString ?? "unknown-account"
            return "\(accountNamespace):\(clientID):\(fileID)" as NSString
        }
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    // MARK: Internal

    private(set) var loadedPath: String?

    private var representedRequest: RequestIdentity?
    private var representedClient: TDLibClient?
    private var downloadTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private var maximumPixelSize = 1280

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
        let client = td
        let request = RequestIdentity(
            accountID: TDLib.shared.activeAccountID,
            clientID: client.id,
            fileID: file.id,
            generation: UUID(),
        )
        self.maximumPixelSize = maximumPixelSize
        representedRequest = request
        representedClient = client
        image = placeholderData.flatMap(UIImage.init(data:))
        if let cached = Self.cache.object(forKey: request.cacheKey) {
            image = cached
            return
        }
        update(file: file, for: request)
        cancellable = nc.publisher(for: .updateFile)
            .receive(on: DispatchQueue.main)
            .filter { $0.file.id == file.id }
            .sink { [weak self] update in self?.update(file: update.file, for: request) }
        downloadTask = Task { [weak self] in
            let downloaded = try? await client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            )
            guard let self, let downloaded else { return }
            await MainActor.run { self.update(file: downloaded, for: request) }
        }
    }

    func cancel() {
        let request = representedRequest
        let client = representedClient
        representedRequest = nil
        representedClient = nil
        downloadTask?.cancel()
        downloadTask = nil
        cancellable?.cancel()
        cancellable = nil
        loadedPath = nil
        if let request, let client {
            Task { try? await client.cancelDownloadFile(fileId: request.fileID, onlyIfPending: true) }
        }
    }

    private func update(file: File, for request: RequestIdentity) {
        guard representedRequest == request,
              TDLib.shared.activeClient.id == request.clientID,
              file.id == request.fileID,
              file.local.isDownloadingCompleted
        else { return }
        let path = file.local.path
        let maximumPixelSize = maximumPixelSize
        loadedPath = path
        Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) {
                downsampledImage(at: path, maximumPixelSize: maximumPixelSize)
            }.value
            await MainActor.run {
                guard let self,
                      self.representedRequest == request,
                      TDLib.shared.activeClient.id == request.clientID,
                      let decoded
                else { return }
                let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale * 4)
                Self.cache.setObject(decoded, forKey: request.cacheKey, cost: cost)
                self.image = decoded
            }
        }
    }
}

// MARK: - TDMediaPrefetcher

enum TDMediaPrefetcher {
    private enum DecodeKind {
        case none
        case tgs
        case webP
        case ffmpegVideo
    }

    static func prefetch(message: Message) async {
        let files: [(id: Int, decodeKind: DecodeKind)] =
            switch message.content {
            case .messagePhoto(let photo):
                photo.photo.sizes.getSize(.yBox).map { [($0.photo.id, .none)] } ?? []
            case .messageVoiceNote(let voice):
                [(voice.voiceNote.voice.id, .none)]
            case .messageVideoNote(let video):
                [video.videoNote.thumbnail?.file.id].compactMap(\.self).map { ($0, .none) }
                    + [(video.videoNote.video.id, .none)]
            case .messageAnimation(let animation):
                if telegramAnimationUsesFFmpeg(animation.animation) {
                    [animation.animation.thumbnail?.file.id].compactMap(\.self).map { ($0, .none) }
                        + [(animation.animation.animation.id, .ffmpegVideo)]
                } else {
                    [(animation.animation.thumbnail?.file.id ?? animation.animation.animation.id, .none)]
                }
            case .messageSticker(let sticker):
                [sticker.sticker.thumbnail?.file.id].compactMap(\.self).map { ($0, .none) }
                    + [(sticker.sticker.sticker.id, decodeKind(for: sticker.sticker.format))]
            case .messageVideo(let video):
                [(video.video.thumbnail?.file.id ?? video.video.video.id, .none)]
            default:
                []
            }
        for file in files where !Task.isCancelled {
            let downloaded = await withTaskCancellationHandler {
                try? await td.downloadFile(
                    fileId: file.id,
                    limit: 0,
                    offset: 0,
                    priority: 1,
                    synchronous: true,
                )
            } onCancel: {
                Task { try? await td.cancelDownloadFile(fileId: file.id, onlyIfPending: true) }
            }
            guard let downloaded,
                  downloaded.local.isDownloadingCompleted,
                  !downloaded.local.path.isEmpty
            else { continue }
            switch file.decodeKind {
            case .none:
                break
            case .tgs:
                _ = await TGSAnimationRepository.animation(at: downloaded.local.path)
            case .webP:
                _ = await AnimatedWebPRepository.asset(at: downloaded.local.path)
            case .ffmpegVideo:
                _ = await FFmpegVideoRepository.asset(at: downloaded.local.path)
            }
        }
    }

    private static func decodeKind(for format: StickerFormat) -> DecodeKind {
        switch format {
        case .stickerFormatTgs:
            .tgs
        case .stickerFormatWebp:
            .webP
        case .stickerFormatWebm:
            .ffmpegVideo
        }
    }
}

private func telegramPhotoSize(_ photo: Photo) -> CGSize {
    guard let size = photo.sizes.max(by: { lhs, rhs in
        lhs.width * lhs.height < rhs.width * rhs.height
    }) else { return CGSize(width: 1, height: 1) }
    return CGSize(width: max(size.width, 1), height: max(size.height, 1))
}

private func telegramMessageMediaSize(_ message: Message) -> CGSize {
    switch message.content {
    case .messagePhoto(let photo):
        telegramPhotoSize(photo.photo)
    case .messageVideo(let video):
        CGSize(width: max(video.video.width, 1), height: max(video.video.height, 1))
    case .messageVideoNote(let video):
        CGSize(width: max(video.videoNote.length, 1), height: max(video.videoNote.length, 1))
    case .messageAnimation(let animation):
        CGSize(width: max(animation.animation.width, 1), height: max(animation.animation.height, 1))
    case .messageSticker(let sticker):
        CGSize(width: max(sticker.sticker.width, 1), height: max(sticker.sticker.height, 1))
    default:
        CGSize(width: 1, height: 1)
    }
}

private func telegramMediaDisplaySize(source: CGSize) -> CGSize {
    let aspectRatio = max(source.width / max(source.height, 1), 0.01)
    let width: CGFloat = 280
    let height = min(320, max(140, round(width / aspectRatio)))
    return CGSize(width: width, height: height)
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
