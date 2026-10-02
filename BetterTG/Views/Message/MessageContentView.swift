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
        client: TDLibClient,
        videoPlaybackOwners: [Int64: GalleryVideoPlaybackOwner] = [:],
        onTap: @escaping ([Message], Int64) -> Void,
    ) -> Bool {
        prepareForReuse()
        let view: UIView?
        let visualAlbum = message.album.filter { message in
            switch message.content {
            case .messageAnimation, .messagePhoto, .messageSticker, .messageVideo:
                true
            default:
                false
            }
        }
        if !visualAlbum.isEmpty {
            let albumView = AlbumMediaView()
            albumView.configure(
                messages: visualAlbum,
                client: client,
                videoPlaybackOwners: videoPlaybackOwners,
                onTap: onTap,
            )
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
                if let owner = videoPlaybackOwners[message.id], owner.matches(message: message.message) {
                    let inlineView = InlineVideoMediaView()
                    inlineView.configure(
                        owner: owner,
                        size: CGSize(width: animation.animation.width, height: animation.animation.height),
                    ) { onTap([message.message], message.id) }
                    view = inlineView
                } else if telegramAnimationUsesFFmpeg(animation.animation), !animation.isSecret, !animation.hasSpoiler {
                    let animationView = FFmpegAnimatedVideoView()
                    animationView.configure(
                        file: animation.animation.animation,
                        client: client,
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
                        thumbnail: animation.isSecret || animation.hasSpoiler ? nil : animation.animation.thumbnail,
                        minithumbnail: animation.animation.minithumbnail,
                        size: CGSize(width: animation.animation.width, height: animation.animation.height),
                        showsPlayIcon: true,
                        usesFileAsThumbnailFallback: false,
                        client: client,
                    ) { onTap([message.message], message.id) }
                    view = fileView
                }
            case .messageSticker(let sticker):
                if sticker.sticker.format == .stickerFormatTgs {
                    let stickerView = TGSStickerView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        client: client,
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
                        client: client,
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
                        client: client,
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
                if let videoPlaybackOwner = videoPlaybackOwners[message.id] {
                    let inlineView = InlineVideoMediaView()
                    inlineView.configure(
                        owner: videoPlaybackOwner,
                        size: CGSize(width: video.video.width, height: video.video.height),
                    ) { onTap([message.message], message.id) }
                    view = inlineView
                } else {
                    let fileView = FileMediaPreviewView()
                    fileView.configure(
                        file: video.video.video,
                        thumbnail: video.video.thumbnail,
                        minithumbnail: video.video.minithumbnail,
                        size: CGSize(width: video.video.width, height: video.video.height),
                        showsPlayIcon: true,
                        usesFileAsThumbnailFallback: false,
                    ) { onTap([message.message], message.id) }
                    view = fileView
                }
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
        (view as? ReusableMediaView)?.setPlaybackVisible(window != nil && !(view is InlineVideoMediaView))
        return true
    }

    func prepareForReuse() {
        (contentView as? ReusableMediaView)?.prepareForReuse()
        contentView?.removeFromSuperview()
        contentView = nil
    }

    func setPlaybackVisible(_ isVisible: Bool, allowsInlineVideoPlayback: Bool = true) {
        let playbackVisible = contentView is InlineVideoMediaView
            ? isVisible && allowsInlineVideoPlayback
            : isVisible
        (contentView as? ReusableMediaView)?.setPlaybackVisible(playbackVisible)
    }

    @discardableResult func restoreInlineVideoPlaybackOwner(_ owner: GalleryVideoPlaybackOwner) -> Bool {
        if let inlineView = contentView as? InlineVideoMediaView {
            return inlineView.reattach(owner: owner)
        }
        if let albumView = contentView as? AlbumMediaView {
            return albumView.restoreInlineVideoPlaybackOwner(owner)
        }
        return false
    }

    func galleryTransitionSourceView(for messageID: Int64) -> UIView? {
        if let albumView = contentView as? AlbumMediaView {
            return albumView.transitionSourceView(for: messageID)
        }
        return self
    }

    func makeGalleryTransitionSnapshot(for messageID: Int64) -> UIView? {
        switch contentView {
        case let albumView as AlbumMediaView:
            albumView.transitionSnapshot(for: messageID)
        case let photoView as SinglePhotoView:
            photoView.makeTransitionSnapshot()
        case let fileView as FileMediaPreviewView:
            fileView.makeTransitionSnapshot()
        case let videoView as InlineVideoMediaView:
            videoView.makeTransitionSnapshot()
        default:
            contentView?.snapshotView(afterScreenUpdates: false)
        }
    }

    func inlineVideoPlaybackCandidates(in coordinateSpace: UIView) -> [(Int64, CGRect)] {
        if let albumView = contentView as? AlbumMediaView {
            return albumView.inlineVideoPlaybackCandidates(in: coordinateSpace)
        }
        guard let inlineView = contentView as? InlineVideoMediaView,
              let messageID = inlineView.messageID
        else { return [] }
        return [(messageID, convert(bounds, to: coordinateSpace))]
    }
}

// MARK: - ReusableMediaView

protocol ReusableMediaView where Self: UIView {
    func prepareForReuse()
    func setPlaybackVisible(_ isVisible: Bool)
}

extension ReusableMediaView {
    func setPlaybackVisible(_: Bool) {}
}

// MARK: - TGSStickerView + ReusableMediaView

extension TGSStickerView: ReusableMediaView {}

// MARK: - AnimatedWebPView + ReusableMediaView

extension AnimatedWebPView: ReusableMediaView {}

// MARK: - FFmpegAnimatedVideoView + ReusableMediaView

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

    func makeTransitionSnapshot() -> UIView? {
        imageView.makeImageSnapshot(contentMode: imageView.contentMode)
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

    #if DEBUG
        static func runDebugTransitionProbe(in container: UIView) -> (exactSource: Bool, singleCandidate: Bool) {
            let album = AlbumMediaView(frame: CGRect(x: 40, y: 300, width: 280, height: 160))
            let first = AlbumMediaTileView(frame: CGRect(x: 0, y: 0, width: 138, height: 160))
            first.configureDebug(messageID: 70, hasVideoPlaybackOwner: false)
            first.apply(position: [.top, .bottom, .left])
            let second = AlbumMediaTileView(frame: CGRect(x: 142, y: 0, width: 138, height: 160))
            second.configureDebug(messageID: 71, hasVideoPlaybackOwner: true)
            second.apply(position: [.top, .bottom, .right])
            album.tiles = [first, second]
            album.itemFrames = [first.frame, second.frame]
            album.addSubview(first)
            album.addSubview(second)
            container.addSubview(album)
            album.layoutIfNeeded()
            let exactSource = album.transitionSourceView(for: 71) === second
                && second.layer.maskedCorners == [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            let candidates = album.inlineVideoPlaybackCandidates(in: container)
            let singleCandidate = candidates.count == 1
                && candidates.first?.0 == 71
                && candidates.first?.1.equalTo(second.convert(second.bounds, to: container)) == true
            album.removeFromSuperview()
            return (exactSource, singleCandidate)
        }
    #endif

    func configure(
        messages: [Message],
        client: TDLibClient,
        videoPlaybackOwners: [Int64: GalleryVideoPlaybackOwner],
        onTap: @escaping ([Message], Int64) -> Void,
    ) {
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
            tile.configure(
                message: message,
                client: client,
                videoPlaybackOwner: videoPlaybackOwners[message.id],
                onTap: { onTap(messages, message.id) },
            )
            if layout.indices.contains(index) {
                tile.apply(position: layout[index].1)
            }
            addSubview(tile)
            tiles.append(tile)
        }
        setNeedsLayout()
    }

    @discardableResult func restoreInlineVideoPlaybackOwner(_ owner: GalleryVideoPlaybackOwner) -> Bool {
        guard let tile = tiles.first(where: { $0.messageID == owner.messageID }) else { return false }
        return tile.restoreInlineVideoPlaybackOwner(owner)
    }

    func transitionSourceView(for messageID: Int64) -> UIView? {
        tiles.first(where: { $0.messageID == messageID })
    }

    func transitionSnapshot(for messageID: Int64) -> UIView? {
        tiles.first(where: { $0.messageID == messageID })?.makeTransitionSnapshot()
    }

    func inlineVideoPlaybackCandidates(in coordinateSpace: UIView) -> [(Int64, CGRect)] {
        tiles.compactMap { tile in
            guard tile.hasVideoPlaybackOwner, let messageID = tile.messageID else { return nil }
            return (messageID, tile.convert(tile.bounds, to: coordinateSpace))
        }
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

    func setPlaybackVisible(_ isVisible: Bool) {
        guard !isVisible else { return }
        tiles.forEach { $0.setPlaybackVisible(false) }
    }
}

// MARK: - AlbumMediaTileView

private final class AlbumMediaTileView: UIControl, ReusableMediaView, UIGestureRecognizerDelegate {
    private(set) var messageID: Int64?

    private let imageView = TDImageLoadingView()
    private let playIcon = UIImageView()
    private weak var videoPlaybackOwner: GalleryVideoPlaybackOwner?
    private var videoPlaybackAttachmentToken: VideoPlaybackAttachmentToken?
    private var onTap: (() -> Void)?

    #if DEBUG
        private var debugHasVideoPlaybackOwner = false

        func configureDebug(messageID: Int64, hasVideoPlaybackOwner: Bool) {
            self.messageID = messageID
            debugHasVideoPlaybackOwner = hasVideoPlaybackOwner
        }
    #endif

    var hasVideoPlaybackOwner: Bool {
        #if DEBUG
            videoPlaybackOwner != nil || debugHasVideoPlaybackOwner
        #else
            videoPlaybackOwner != nil
        #endif
    }

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
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
        NSLayoutConstraint.activate([
            playIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        guard let onTap else { return false }
        onTap()
        return true
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        guard !isVisible,
              let videoPlaybackOwner,
              let videoPlaybackAttachmentToken
        else { return }
        videoPlaybackOwner.setPlaybackVisible(false, attachment: videoPlaybackAttachmentToken)
    }

    func configure(
        message: Message,
        client: TDLibClient,
        videoPlaybackOwner: GalleryVideoPlaybackOwner?,
        onTap: @escaping () -> Void,
    ) {
        prepareForReuse()
        messageID = message.id
        self.onTap = onTap
        if let videoPlaybackOwner, videoPlaybackOwner.matches(message: message) {
            self.videoPlaybackOwner = videoPlaybackOwner
            imageView.isHidden = true
            playIcon.isHidden = true
            videoPlaybackAttachmentToken = videoPlaybackOwner.attach(to: self, context: .inline)
            accessibilityLabel = videoPlaybackOwner.isAnimation ? "Open animation" : "Open video"
            accessibilityTraits = videoPlaybackOwner.isAnimation ? .button : [.button, .playsSound]
            return
        }
        imageView.isHidden = false
        accessibilityLabel = "Open media"
        accessibilityTraits = .button
        switch message.content {
        case .messagePhoto(let photo):
            playIcon.isHidden = true
            imageView.load(photo: photo.photo, preferredSize: .yBox)
        case .messageVideo(let video):
            playIcon.isHidden = false
            if let thumbnail = video.video.thumbnail {
                imageView.load(file: thumbnail.file, placeholderData: video.video.minithumbnail?.data)
            } else {
                imageView.loadPlaceholder(data: video.video.minithumbnail?.data)
            }
        case .messageAnimation(let animation):
            playIcon.isHidden = false
            if !animation.isSecret, !animation.hasSpoiler, let thumbnail = animation.animation.thumbnail {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: animation.animation.minithumbnail?.data,
                    client: client,
                )
            } else {
                imageView.loadPlaceholder(data: animation.animation.minithumbnail?.data)
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
        if let videoPlaybackAttachmentToken {
            videoPlaybackOwner?.detach(attachment: videoPlaybackAttachmentToken)
        }
        videoPlaybackAttachmentToken = nil
        videoPlaybackOwner = nil
        imageView.cancel()
        imageView.isHidden = false
        onTap = nil
        messageID = nil
        #if DEBUG
            debugHasVideoPlaybackOwner = false
        #endif
    }

    @discardableResult func restoreInlineVideoPlaybackOwner(_ owner: GalleryVideoPlaybackOwner) -> Bool {
        guard messageID == owner.messageID else { return false }
        videoPlaybackOwner = owner
        imageView.isHidden = true
        playIcon.isHidden = true
        videoPlaybackAttachmentToken = owner.attach(to: self, context: .inline)
        return videoPlaybackAttachmentToken != nil
    }

    func makeTransitionSnapshot() -> UIView? {
        videoPlaybackOwner?.makeTransitionSnapshot(contentMode: .scaleAspectFill)
            ?? imageView.makeImageSnapshot(contentMode: .scaleAspectFill)
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let view = touchedView, view !== self {
            if view is UIControl {
                return false
            }
            touchedView = view.superview
        }
        return true
    }

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - InlineVideoMediaView

private final class InlineVideoMediaView: UIControl, ReusableMediaView, UIGestureRecognizerDelegate {
    private(set) var messageID: Int64?

    // MARK: Private

    private weak var owner: GalleryVideoPlaybackOwner?
    private var attachmentToken: VideoPlaybackAttachmentToken?
    private var onTap: (() -> Void)?
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 280)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 220)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        accessibilityTraits = [.button, .playsSound]
        accessibilityLabel = "Open video"
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        guard let onTap else { return false }
        onTap()
        return true
    }

    // MARK: Internal

    func configure(
        owner: GalleryVideoPlaybackOwner,
        size: CGSize,
        onTap: @escaping () -> Void,
    ) {
        prepareForReuse()
        messageID = owner.messageID
        self.owner = owner
        accessibilityLabel = owner.isAnimation ? "Open animation" : "Open video"
        accessibilityTraits = owner.isAnimation ? .button : [.button, .playsSound]
        self.onTap = onTap
        let displaySize = telegramMediaDisplaySize(source: size)
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        attachmentToken = owner.attach(to: self, context: .inline)
    }

    func prepareForReuse() {
        if let attachmentToken {
            owner?.detach(attachment: attachmentToken)
        }
        attachmentToken = nil
        owner = nil
        onTap = nil
        messageID = nil
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        guard let owner, let attachmentToken else { return }
        owner.setPlaybackVisible(isVisible, attachment: attachmentToken)
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let view = touchedView, view !== self {
            if view is UIControl {
                return false
            }
            touchedView = view.superview
        }
        return true
    }

    @discardableResult func reattach(owner: GalleryVideoPlaybackOwner) -> Bool {
        guard messageID == owner.messageID else { return false }
        self.owner = owner
        attachmentToken = owner.attach(to: self, context: .inline)
        return attachmentToken != nil
    }

    func makeTransitionSnapshot() -> UIView? {
        owner?.makeTransitionSnapshot(contentMode: .scaleAspectFill)
            ?? snapshotView(afterScreenUpdates: false)
    }

    @objc private func tapped() {
        onTap?()
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
        usesFileAsThumbnailFallback: Bool = true,
        client: TDLibClient? = nil,
        onTap: @escaping () -> Void,
    ) {
        self.onTap = onTap
        let displaySize = telegramMediaDisplaySize(source: size)
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        playIcon.isHidden = !showsPlayIcon
        if let client, let thumbnail {
            imageView.load(file: thumbnail.file, placeholderData: minithumbnail?.data, client: client)
        } else if let thumbnail {
            imageView.load(file: thumbnail.file, placeholderData: minithumbnail?.data)
        } else if usesFileAsThumbnailFallback {
            imageView.load(file: file, placeholderData: minithumbnail?.data)
        } else {
            imageView.loadPlaceholder(data: minithumbnail?.data)
        }
    }

    func prepareForReuse() {
        imageView.cancel()
        onTap = nil
    }

    func makeTransitionSnapshot() -> UIView? {
        imageView.makeImageSnapshot(contentMode: imageView.contentMode)
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
    private var cancelsTransportOnCancel = true
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
        cancelsTransportOnCancel = true
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

    func load(
        file: File,
        placeholderData: Data? = nil,
        client: TDLibClient,
    ) {
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id else {
            loadPlaceholder(data: placeholderData)
            return
        }
        load(file: file, placeholderData: placeholderData, accountID: source.accountID, client: client)
    }

    func load(
        file: File,
        placeholderData: Data? = nil,
        maximumPixelSize: Int = 1280,
        accountID: UUID,
        client: TDLibClient,
    ) {
        cancel()
        let request = RequestIdentity(
            accountID: accountID,
            clientID: client.id,
            fileID: file.id,
            generation: UUID(),
        )
        self.maximumPixelSize = maximumPixelSize
        representedRequest = request
        representedClient = client
        cancelsTransportOnCancel = false
        image = placeholderData.flatMap(UIImage.init(data:))
        if let cached = Self.cache.object(forKey: request.cacheKey) {
            image = cached
            return
        }
        update(file: file, for: request)
        downloadTask = Task { [weak self] in
            let downloaded = try? await client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: true,
            )
            guard let self,
                  !Task.isCancelled,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id,
                  let downloaded
            else { return }
            update(file: downloaded, for: request)
        }
    }

    func loadPlaceholder(data: Data?) {
        cancel()
        image = data.flatMap(UIImage.init(data:))
    }

    func makeImageSnapshot(contentMode: UIView.ContentMode) -> UIView? {
        guard let image else { return snapshotView(afterScreenUpdates: false) }
        let snapshot = UIImageView(image: image)
        snapshot.contentMode = contentMode
        snapshot.clipsToBounds = true
        return snapshot
    }

    func cancel() {
        let request = representedRequest
        let client = representedClient
        let cancelsTransportOnCancel = cancelsTransportOnCancel
        representedRequest = nil
        representedClient = nil
        self.cancelsTransportOnCancel = true
        downloadTask?.cancel()
        downloadTask = nil
        cancellable?.cancel()
        cancellable = nil
        loadedPath = nil
        if cancelsTransportOnCancel, let request, let client {
            Task { try? await client.cancelDownloadFile(fileId: request.fileID, onlyIfPending: true) }
        }
    }

    private func update(file: File, for request: RequestIdentity) {
        guard representedRequest == request,
              TDLib.shared.activeAccountID == request.accountID,
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
                      TDLib.shared.activeAccountID == request.accountID,
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

    @MainActor static func prefetch(message: Message, client: TDLibClient) async {
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id else { return }
        let files: [(file: File, decodeKind: DecodeKind)] =
            switch message.content {
            case .messagePhoto(let photo):
                photo.photo.sizes.getSize(.yBox).map { [($0.photo, .none)] } ?? []
            case .messageAudio(let audio):
                [audio.audio.albumCoverThumbnail?.file]
                    .compactMap(\.self)
                    .map { ($0, .none) }
            case .messageDocument(let document):
                [document.document.thumbnail?.file]
                    .compactMap(\.self)
                    .map { ($0, .none) }
            case .messageVoiceNote(let voice):
                [(voice.voiceNote.voice, .none)]
            case .messageVideoNote(let video):
                [video.videoNote.thumbnail?.file].compactMap(\.self).map { ($0, .none) }
                    + [(video.videoNote.video, .none)]
            case .messageAnimation(let animation):
                if animation.isSecret || animation.hasSpoiler {
                    []
                } else if telegramAnimationUsesFFmpeg(animation.animation) {
                    [animation.animation.thumbnail?.file].compactMap(\.self).map { ($0, .none) }
                        + [(animation.animation.animation, .ffmpegVideo)]
                } else {
                    [animation.animation.thumbnail?.file].compactMap(\.self).map { ($0, .none) }
                }
            case .messageSticker(let sticker):
                [sticker.sticker.thumbnail?.file].compactMap(\.self).map { ($0, .none) }
                    + [(sticker.sticker.sticker, decodeKind(for: sticker.sticker.format))]
            case .messageAnimatedEmoji(let emoji):
                stickerFiles(emoji.animatedEmoji.sticker)
            case .messageDice(let dice):
                dice.value == 0 ? stickerFiles(regularSticker(dice.initialState)) : []
            case .messageVideo(let video):
                [video.video.thumbnail?.file].compactMap(\.self).map { ($0, .none) }
            default:
                []
            }
        for file in files {
            guard !Task.isCancelled, TDLib.shared.activeUpdateSource == source else { return }
            let downloaded: File?
            switch file.decodeKind {
            case .ffmpegVideo, .tgs, .webP:
                guard let request = AnimatedFileDownload(fileID: file.file.id, client: client) else { return }
                downloaded = await request.completedFile(file: file.file)
            case .none:
                downloaded = await withTaskCancellationHandler {
                    try? await client.downloadFile(
                        fileId: file.file.id,
                        limit: 0,
                        offset: 0,
                        priority: 1,
                        synchronous: true,
                    )
                } onCancel: {
                    Task { try? await client.cancelDownloadFile(fileId: file.file.id, onlyIfPending: true) }
                }
            }
            guard !Task.isCancelled, TDLib.shared.activeUpdateSource == source else { return }
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

    private static func stickerFiles(_ sticker: Sticker?) -> [(file: File, decodeKind: DecodeKind)] {
        guard let sticker else { return [] }
        return [sticker.thumbnail?.file].compactMap(\.self).map { ($0, .none) }
            + [(sticker.sticker, decodeKind(for: sticker.format))]
    }

    private static func regularSticker(_ dice: DiceStickers?) -> Sticker? {
        guard let dice, case .diceStickersRegular(let regular) = dice else { return nil }
        return regular.sticker
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
