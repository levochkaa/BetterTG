// MessageContentView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MessageMediaView

final class MessageMediaView: UIView {
    private(set) var transitionGeneration = UUID()

    // MARK: Private

    private var contentView: UIView?
    private var revealPermits = [Int64: MediaRevealPermit]()
    private var revealSubscription: AnyCancellable?

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
        mediaRevealSession: MediaRevealSession? = nil,
        videoPlaybackOwners: [Int64: GalleryVideoPlaybackOwner] = [:],
        onTap: @escaping ([Message], Int64) -> Void,
    ) -> Bool {
        prepareForReuse()
        revealPermits = Dictionary(uniqueKeysWithValues: message.sourceMessages.compactMap { source in
            mediaRevealSession?.permit(for: source).map { (source.id, $0) }
        })
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
                revealPermits: revealPermits,
                videoPlaybackOwners: videoPlaybackOwners,
                onTap: onTap,
            )
            view = albumView
        } else if !MediaRevealPermit.allows(message.message, permit: revealPermits[message.id], requiresPermit: true) {
            view = MediaConcealmentView(
                message: message.message,
                size: telegramMediaDisplaySize(source: telegramMessageMediaSize(message.message)),
                onTap: { onTap([message.message], message.id) },
            )
        } else {
            switch message.message.content {
            case .messagePhoto(let photo):
                let photoView = SinglePhotoView()
                photoView.configure(photo: photo.photo, client: client) { onTap([message.message], message.id) }
                view = photoView
            case .messageVoiceNote(let voice):
                let voiceView = VoiceNotePlaybackView()
                voiceView.configure(voiceNote: voice.voiceNote)
                view = voiceView
            case .messageVideoNote:
                let videoNoteView = VideoNotePlaybackView()
                videoNoteView.configure(
                    message: message.message, client: client, context: mediaRevealSession?.context,
                )
                view = videoNoteView
            case .messageAnimation(let animation):
                if telegramAnimationUsesFFmpeg(animation.animation) {
                    let animationView = FFmpegAnimatedVideoView()
                    animationView.configure(
                        file: animation.animation.animation,
                        thumbnail: animation.animation.thumbnail,
                        displaySize: telegramMediaDisplaySize(source: CGSize(
                            width: CGFloat(animation.animation.width),
                            height: CGFloat(animation.animation.height),
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
                        size: CGSize(
                            width: CGFloat(animation.animation.width),
                            height: CGFloat(animation.animation.height),
                        ),
                        showsPlayIcon: true,
                    ) { onTap([message.message], message.id) }
                    view = fileView
                }
            case .messageSticker(let sticker):
                if sticker.sticker.format.typeID == TDNativeStickerFormatTgs.typeID {
                    let stickerView = TGSStickerView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: telegramMediaDisplaySize(source: CGSize(
                            width: CGFloat(sticker.sticker.width),
                            height: CGFloat(sticker.sticker.height),
                        )),
                        onTap: { onTap([message.message], message.id) },
                    )
                    view = stickerView
                } else if sticker.sticker.format.typeID == TDNativeStickerFormatWebp.typeID {
                    let stickerView = AnimatedWebPView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: telegramMediaDisplaySize(source: CGSize(
                            width: CGFloat(sticker.sticker.width),
                            height: CGFloat(sticker.sticker.height),
                        )),
                        onTap: { onTap([message.message], message.id) },
                    )
                    view = stickerView
                } else if sticker.sticker.format.typeID == TDNativeStickerFormatWebm.typeID {
                    let stickerView = FFmpegAnimatedVideoView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: telegramMediaDisplaySize(source: CGSize(
                            width: CGFloat(sticker.sticker.width),
                            height: CGFloat(sticker.sticker.height),
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
                        size: CGSize(width: CGFloat(sticker.sticker.width), height: CGFloat(sticker.sticker.height)),
                        showsPlayIcon: sticker.sticker.format.typeID != TDNativeStickerFormatWebp.typeID,
                    ) { onTap([message.message], message.id) }
                    view = fileView
                }
            case .messageVideo(let video):
                if let videoPlaybackOwner = videoPlaybackOwners[message.id] {
                    let inlineView = InlineVideoMediaView()
                    inlineView.configure(
                        owner: videoPlaybackOwner,
                        size: CGSize(width: CGFloat(video.video.width), height: CGFloat(video.video.height)),
                    ) { onTap([message.message], message.id) }
                    view = inlineView
                } else {
                    let fileView = FileMediaPreviewView()
                    fileView.configure(
                        file: video.video.video,
                        thumbnail: video.video.thumbnail,
                        minithumbnail: video.video.minithumbnail,
                        size: CGSize(width: CGFloat(video.video.width), height: CGFloat(video.video.height)),
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
        let representedIDs = Set(message.sourceMessages.map(\.id))
        revealSubscription = mediaRevealSession?.revisionsChanged.sink { [weak self] changed in
            guard !changed.ids.isDisjoint(with: representedIDs) else { return }
            self?.configure(
                message: message,
                client: client,
                mediaRevealSession: mediaRevealSession,
                videoPlaybackOwners: videoPlaybackOwners,
                onTap: onTap,
            )
        }
        return true
    }

    func prepareForReuse() {
        transitionGeneration = UUID()
        revealSubscription = nil
        (contentView as? ReusableMediaView)?.prepareForReuse()
        contentView?.removeFromSuperview()
        contentView = nil
        revealPermits.removeAll()
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
        guard transitionIsCurrent(for: messageID) else { return nil }
        return switch contentView {
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

    func transitionIsCurrent(for messageID: Int64) -> Bool {
        revealPermits[messageID]?.isCurrent ?? true
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

    func configure(photo: Photo, client: TDLibClient, onTap: @escaping () -> Void) {
        self.onTap = onTap
        let displaySize = telegramMediaDisplaySize(source: telegramPhotoSize(photo))
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        imageView.load(photo: photo, preferredSize: .yBox, client: client)
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
        revealPermits: [Int64: MediaRevealPermit] = [:],
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
                revealPermit: revealPermits[message.id],
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
    private var cover: MediaConcealmentView?
    private var revealPermit: MediaRevealPermit?

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
        revealPermit: MediaRevealPermit? = nil,
        videoPlaybackOwner: GalleryVideoPlaybackOwner?,
        onTap: @escaping () -> Void,
    ) {
        prepareForReuse()
        messageID = message.id
        self.onTap = onTap
        self.revealPermit = revealPermit
        if !MediaRevealPermit.allows(message, permit: revealPermit, requiresPermit: true) {
            imageView.isHidden = true
            playIcon.isHidden = true
            let cover = MediaConcealmentView(message: message, onTap: onTap)
            cover.frame = bounds
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(cover)
            self.cover = cover
            accessibilityLabel = cover.accessibilityLabel
            accessibilityTraits = .button
            return
        }
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
            imageView.load(photo: photo.photo, preferredSize: .yBox, client: client)
        case .messageVideo(let video):
            playIcon.isHidden = false
            if let thumbnail = video.video.thumbnail {
                imageView.load(file: thumbnail.file, placeholderData: video.video.minithumbnail?.data, client: client)
            } else {
                imageView.loadPlaceholder(data: video.video.minithumbnail?.data, client: client)
            }
        case .messageAnimation(let animation):
            playIcon.isHidden = false
            if let thumbnail = animation.animation.thumbnail {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: animation.animation.minithumbnail?.data,
                    client: client,
                )
            } else {
                imageView.loadPlaceholder(data: animation.animation.minithumbnail?.data, client: client)
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
        cover?.prepareForReuse()
        cover?.removeFromSuperview()
        cover = nil
        revealPermit = nil
        imageView.cancel()
        imageView.isHidden = false
        onTap = nil
        messageID = nil
        #if DEBUG
            debugHasVideoPlaybackOwner = false
        #endif
    }

    @discardableResult func restoreInlineVideoPlaybackOwner(_ owner: GalleryVideoPlaybackOwner) -> Bool {
        guard messageID == owner.messageID, cover == nil, revealPermit?.allowsPixels != false else { return false }
        videoPlaybackOwner = owner
        imageView.isHidden = true
        playIcon.isHidden = true
        videoPlaybackAttachmentToken = owner.attach(to: self, context: .inline)
        return videoPlaybackAttachmentToken != nil
    }

    func makeTransitionSnapshot() -> UIView? {
        guard revealPermit?.isCurrent != false else { return nil }
        if let cover { return cover.snapshotView(afterScreenUpdates: false) }
        return videoPlaybackOwner?.makeTransitionSnapshot(contentMode: .scaleAspectFill)
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
        client: TDLibClient,
        onTap: @escaping () -> Void,
    ) {
        self.onTap = onTap
        let displaySize = telegramMediaDisplaySize(source: size)
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        playIcon.isHidden = !showsPlayIcon
        if let thumbnail {
            imageView.load(file: thumbnail.file, placeholderData: minithumbnail?.data, client: client)
        } else if usesFileAsThumbnailFallback {
            imageView.load(file: file, placeholderData: minithumbnail?.data, client: client)
        } else {
            imageView.loadPlaceholder(data: minithumbnail?.data, client: client)
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
        let accountID: UUID
        let clientID: Int32
        let fileID: Int
        let maximumPixelSize: Int
        let generation: UUID

        var thumbnailKey: TDImageThumbnailKey {
            TDImageThumbnailKey(
                accountID: accountID,
                clientID: clientID,
                fileID: fileID,
                maximumPixelSize: maximumPixelSize,
            )
        }
    }

    // MARK: Internal

    private(set) var loadedPath: String?

    #if DEBUG
        var debugDecode: ((String, Int) async -> UIImage?)?
    #endif

    private var representedRequest: RequestIdentity?
    private var renderGeneration = UUID()
    private var hasFullImage = false
    private var downloadTask: Task<Void, Never>?
    private var decodeTask: Task<Void, Never>?
    private var placeholderTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    func load(
        photo: Photo,
        preferredSize: PhotoSizeType,
        maximumPixelSize: Int = 960,
    ) {
        let placeholderData = photo.minithumbnail?.data
        guard let size = photo.sizes.getSize(preferredSize) ?? photo.sizes.first else {
            loadPlaceholder(data: placeholderData, maximumPixelSize: maximumPixelSize)
            return
        }
        load(file: size.photo, placeholderData: placeholderData, maximumPixelSize: maximumPixelSize)
    }

    func load(file: File, placeholderData: Data? = nil, maximumPixelSize: Int = 960) {
        cancel()
        image = nil
        guard let origin, admit(origin) else { return }
        let request = RequestIdentity(
            accountID: origin.source.accountID,
            clientID: origin.source.clientID,
            fileID: file.id,
            maximumPixelSize: maximumPixelSize,
            generation: UUID(),
        )
        representedRequest = request
        renderGeneration = request.generation
        image = nil
        hasFullImage = false
        if let cached = TDImageThumbnailPipeline.shared.cachedImage(for: request.thumbnailKey.cacheKey) {
            apply(cached, asFullImageFor: request)
            return
        }
        preparePlaceholder(placeholderData, for: request)
        update(file: file, for: request)
        if file.local.isDownloadingCompleted, !file.local.path.isEmpty {
            return
        }
        cancellable = nc.publisher(for: .updateFile)
            .filter { $0.file.id == file.id }
            .receive(on: DispatchQueue.main)
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

    func loadPlaceholder(data: Data?, maximumPixelSize: Int = 960) {
        cancel()
        image = nil
        guard let data else { return }
        let generation = renderGeneration
        placeholderTask = Task { [weak self] in
            let prepared = await TDImageThumbnailPipeline.shared.standalonePlaceholderImage(
                data: data,
                maximumPixelSize: maximumPixelSize,
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.renderGeneration == generation, let prepared else { return }
                self.image = UIImage(cgImage: prepared.image)
            }
        }
    }

    func makeImageSnapshot(contentMode: UIView.ContentMode) -> UIView? {
        guard let image else { return snapshotView(afterScreenUpdates: false) }
        let snapshot = UIImageView(image: image)
        snapshot.contentMode = contentMode
        snapshot.clipsToBounds = true
        return snapshot
    }

    func cancel() {
        renderGeneration = UUID()
        representedRequest = nil
        hasFullImage = false
        downloadTask?.cancel()
        downloadTask = nil
        decodeTask?.cancel()
        decodeTask = nil
        placeholderTask?.cancel()
        placeholderTask = nil
        cancellable?.cancel()
        cancellable = nil
        loadedPath = nil
    }

    private func update(file: File, for request: RequestIdentity) {
        guard representedRequest == request,
              representedOrigin?.isCurrent == true,
              file.id == request.fileID,
              file.local.isDownloadingCompleted, !file.local.path.isEmpty,
              loadedPath != file.local.path
        else { return }
        let path = file.local.path
        guard !path.isEmpty else { return }
        loadedPath = path
        decodeTask?.cancel()
        decodeTask = Task { [weak self] in
            let prepared = await TDImageThumbnailPipeline.shared.image(at: path, key: request.thumbnailKey)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.representedRequest == request,
                      TDLib.shared.activeClient.id == request.clientID,
                      let prepared
                else { return }
                self.apply(prepared, asFullImageFor: request)
            }
        }
    }

    private func preparePlaceholder(_ data: Data?, for request: RequestIdentity) {
        guard let data else { return }
        if let cached = TDImageThumbnailPipeline.shared.cachedImage(
            for: request.thumbnailKey.placeholderCacheKey(data: data),
        ) {
            image = UIImage(cgImage: cached.image)
            return
        }
        placeholderTask = Task { [weak self] in
            let prepared = await TDImageThumbnailPipeline.shared.placeholderImage(
                data: data,
                key: request.thumbnailKey,
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.representedRequest == request,
                      !self.hasFullImage,
                      let prepared
                else { return }
                self.image = UIImage(cgImage: prepared.image)
            }
        }
    }

    private func apply(_ prepared: PreparedCGImage, asFullImageFor request: RequestIdentity) {
        guard representedRequest == request else { return }
        hasFullImage = true
        placeholderTask?.cancel()
        placeholderTask = nil
        image = UIImage(cgImage: prepared.image)
    }
}

// MARK: - TDMediaPrefetcher

enum TDMediaPrefetcher {
    private enum DecodeKind {
        case none
        case unpooledMedia
        case tgs
        case webP
        case ffmpegVideo
    }

    @MainActor static func prefetch(
        message: Message,
        client: TDLibClient,
        revealPermit: MediaRevealPermit? = nil,
    ) async {
        guard MediaRevealPermit.allows(message, permit: revealPermit, requiresPermit: true) else { return }
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id else { return }
        let files: [(file: File, decodeKind: DecodeKind)] =
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
                [video.video.thumbnail?.file.id].compactMap(\.self).map { ($0, .none) }
            default:
                []
            }
        let client = td
        let accountID = TDLib.shared.activeAccountID
        for file in files where !Task.isCancelled {
            let downloaded = await withTaskCancellationHandler {
                try? await client.downloadFile(
                    fileId: file.id,
                    limit: 0,
                    offset: 0,
                    priority: 1,
                    synchronous: true,
                )
            } onCancel: {
                Task { try? await client.cancelDownloadFile(fileId: file.id, onlyIfPending: true) }
            }
            guard let downloaded,
                  downloaded.local.isDownloadingCompleted,
                  !downloaded.local.path.isEmpty,
                  !Task.isCancelled
            else { continue }
            switch file.decodeKind {
            case .none:
                let key = TDImageThumbnailKey(
                    accountID: accountID,
                    clientID: client.id,
                    fileID: file.id,
                    maximumPixelSize: 960,
                )
                _ = await TDImageThumbnailPipeline.shared.image(at: downloaded.local.path, key: key)
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
    return CGSize(width: CGFloat(max(size.width, 1)), height: CGFloat(max(size.height, 1)))
}

private func telegramMessageMediaSize(_ message: Message) -> CGSize {
    switch message.content {
    case .messagePhoto(let photo):
        telegramPhotoSize(photo.photo)
    case .messageVideo(let video):
        CGSize(width: CGFloat(max(video.video.width, 1)), height: CGFloat(max(video.video.height, 1)))
    case .messageVideoNote(let video):
        CGSize(width: CGFloat(max(video.videoNote.length, 1)), height: CGFloat(max(video.videoNote.length, 1)))
    case .messageAnimation(let animation):
        CGSize(width: CGFloat(max(animation.animation.width, 1)), height: CGFloat(max(animation.animation.height, 1)))
    case .messageSticker(let sticker):
        CGSize(width: CGFloat(max(sticker.sticker.width, 1)), height: CGFloat(max(sticker.sticker.height, 1)))
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
