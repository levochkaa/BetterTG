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
    private var maximumWidth = CGFloat.zero
    private var reconfigureForWidth: ((CGFloat) -> Void)?

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
        maximumWidth: CGFloat,
        mediaRevealSession: MediaRevealSession? = nil,
        videoPlaybackOwners: [Int64: GalleryVideoPlaybackOwner] = [:],
        onCancelSending: ((Int64) -> Void)? = nil,
        onTap: @escaping ([Message], Int64) -> Void,
    ) -> Bool {
        self.maximumWidth = maximumWidth
        if case .messageVideoNote = message.message.content,
           let existing = contentView as? VideoNotePlaybackView
        {
            reconfigureForWidth = nil
            existing.configure(message: message.message, client: client, context: mediaRevealSession?.context)
            return true
        }
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
        // Telegram lays out a mosaic only for two or more items (`ChatMessageBubbleItemNode.mosaicRange`); a group
        // left with one item, such as an album whose other upload was cancelled, is an ordinary single media.
        let item = visualAlbum.count == 1 ? visualAlbum[0] : message.message
        let displaySize = TelegramMediaLayout.displaySize(
            pixelSize: telegramMessageMediaSize(item),
            kind: telegramMediaKind(item),
            maximumWidth: maximumWidth,
        )
        if visualAlbum.count > 1 {
            let albumView = AlbumMediaView()
            albumView.configure(
                messages: visualAlbum,
                client: client,
                maximumWidth: maximumWidth,
                revealPermits: revealPermits,
                videoPlaybackOwners: videoPlaybackOwners,
                onCancelSending: onCancelSending,
                onTap: onTap,
            )
            view = albumView
        } else if case .messageVoiceNote = item.content {
            // A voice note has no pixels to cover. Its view plays a self-destructing note only through the play-once
            // overlay, which needs the route's current permit.
            let voiceView = VoiceNotePlaybackView()
            voiceView.configure(
                message: item,
                client: client,
                context: mediaRevealSession?.context,
                permit: revealPermits[item.id],
            )
            view = voiceView
        } else if !MediaRevealPermit.allows(item, permit: revealPermits[item.id], requiresPermit: true) {
            view = MediaConcealmentView(
                message: item,
                size: displaySize,
                clientID: client.id,
                onTap: { onTap([item], item.id) },
            )
        } else {
            switch item.content {
            case .messagePhoto(let photo):
                let photoView = SinglePhotoView()
                photoView.configure(
                    photo: photo.photo,
                    message: item,
                    isLivePhoto: photo.video != nil,
                    displaySize: displaySize,
                    client: client,
                ) { onTap([item], item.id) }
                if let onCancelSending {
                    let messageID = item.id
                    photoView.showUploadProgress(for: item, client: client) { onCancelSending(messageID) }
                }
                view = photoView
            case .messageVideoNote:
                let videoNoteView = VideoNotePlaybackView()
                videoNoteView.configure(
                    message: item, client: client, context: mediaRevealSession?.context,
                )
                view = videoNoteView
            case .messageAnimation(let animation):
                // As with other sending media (F41), a tap on a GIF that is still sending does nothing.
                let openGallery: (() -> Void)? = item.sendingState == nil ? { onTap([item], item.id) } : nil
                if let owner = videoPlaybackOwners[item.id], owner.matches(message: item) {
                    let inlineView = InlineVideoMediaView()
                    inlineView.configure(owner: owner, displaySize: displaySize) { onTap([item], item.id) }
                    view = inlineView
                } else if telegramAnimationUsesFFmpeg(animation.animation) {
                    let animationView = FFmpegAnimatedVideoView()
                    animationView.configure(
                        file: animation.animation.animation,
                        client: client,
                        thumbnail: animation.animation.thumbnail,
                        displaySize: displaySize,
                        onTap: openGallery,
                    )
                    animationView.accessibilityLabel = L10n.telegram("Message.Animation")
                    view = animationView
                } else {
                    let animationView = InlineAnimationMediaView()
                    animationView.configure(
                        animation: animation.animation,
                        displaySize: displaySize,
                        client: client,
                        onTap: openGallery,
                    )
                    view = animationView
                }
            case .messageSticker(let sticker):
                // TDLibKit's generated instance `typeID` reports WebM for every sticker format, so match the case.
                switch sticker.sticker.format {
                case .stickerFormatTgs:
                    let stickerView = TGSStickerView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        client: client,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: displaySize,
                        onTap: { onTap([item], item.id) },
                    )
                    view = stickerView
                case .stickerFormatWebp:
                    let stickerView = AnimatedWebPView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        client: client,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: displaySize,
                        onTap: { onTap([item], item.id) },
                    )
                    view = stickerView
                case .stickerFormatWebm:
                    let stickerView = FFmpegAnimatedVideoView()
                    stickerView.configure(
                        file: sticker.sticker.sticker,
                        client: client,
                        thumbnail: sticker.sticker.thumbnail,
                        displaySize: displaySize,
                        onTap: { onTap([item], item.id) },
                    )
                    view = stickerView
                }
            case .messageVideo(let video):
                if let videoPlaybackOwner = videoPlaybackOwners[item.id],
                   videoPlaybackOwner.matches(message: item)
                {
                    let inlineView = InlineVideoMediaView()
                    inlineView.configure(owner: videoPlaybackOwner, displaySize: displaySize) {
                        onTap([item], item.id)
                    }
                    if let onCancelSending {
                        let messageID = item.id
                        inlineView.showUploadProgress(for: item, client: client) { onCancelSending(messageID) }
                    }
                    view = inlineView
                } else {
                    let fileView = FileMediaPreviewView()
                    fileView.configure(
                        file: video.video.video,
                        thumbnail: video.video.thumbnail,
                        minithumbnail: video.video.minithumbnail,
                        displaySize: displaySize,
                        showsPlayIcon: true,
                        usesFileAsThumbnailFallback: false,
                        client: client,
                    ) { onTap([item], item.id) }
                    fileView.showSentVideoPoster(for: item)
                    if let onCancelSending {
                        let messageID = item.id
                        fileView.showUploadProgress(for: item, client: client) { onCancelSending(messageID) }
                    }
                    view = fileView
                }
            default:
                view = nil
            }
        }
        guard let view else { return false }
        contentView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        // Below the owner's overlays (the media time label and highlight), which a reconfigure from here keeps.
        insertSubview(view, at: 0)
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
            // A finished upload changes the photo's files, which is a new revision; keep the disc so it can fade out.
            self?.configure(
                message: message,
                client: client,
                maximumWidth: maximumWidth,
                mediaRevealSession: mediaRevealSession,
                videoPlaybackOwners: videoPlaybackOwners,
                onCancelSending: onCancelSending,
                onTap: onTap,
            )
        }
        reconfigureForWidth = { [weak self] width in
            self?.configure(
                message: message,
                client: client,
                maximumWidth: width,
                mediaRevealSession: mediaRevealSession,
                videoPlaybackOwners: videoPlaybackOwners,
                onCancelSending: onCancelSending,
                onTap: onTap,
            )
        }
        return true
    }

    /// Media sizes follow the bubble's widest allowed width, so a cell that changed width lays its media out again.
    func updateMaximumWidth(_ width: CGFloat) {
        guard abs(width - maximumWidth) > 0.5 else { return }
        maximumWidth = width
        reconfigureForWidth?(width)
    }

    func prepareForReuse() {
        alpha = 1
        transitionGeneration = UUID()
        revealSubscription = nil
        reconfigureForWidth = nil
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

    func setBubbleCorners(_ corners: CACornerMask) {
        layer.cornerRadius = corners.isEmpty ? 0 : 13
        layer.maskedCorners = corners
        (contentView as? AlbumMediaView)?.setBubbleCorners(corners)
    }

    func galleryTransitionSourceView(for messageID: Int64) -> UIView? {
        if let albumView = contentView as? AlbumMediaView {
            return albumView.transitionSourceView(for: messageID)
        }
        return self
    }

    /// The photo or video of an album under `point` (in `coordinateSpace`); nil outside an album.
    func albumItemMessageID(at point: CGPoint, in coordinateSpace: UIView) -> Int64? {
        (contentView as? AlbumMediaView)?.messageID(at: point, in: coordinateSpace)
    }

    /// The album's tiles by message, in `coordinateSpace`; nil when the media isn't a mosaic.
    func albumTileFrames(in coordinateSpace: UIView) -> [Int64: CGRect]? {
        (contentView as? AlbumMediaView)?.tileFrames(in: coordinateSpace)
    }

    func albumTileSnapshot(for messageID: Int64) -> UIView? {
        (contentView as? AlbumMediaView)?.tileSnapshot(for: messageID)
    }

    /// Moves the mosaic's tiles from `frames` (in `coordinateSpace`) to their places; false when the media
    /// isn't a mosaic now.
    func animateAlbumTiles(from frames: [Int64: CGRect], in coordinateSpace: UIView) -> Bool {
        guard let albumView = contentView as? AlbumMediaView else { return false }
        // Tiles travel outside the new bounds; each keeps its own corners.
        clipsToBounds = false
        albumView.animateTiles(from: frames, in: coordinateSpace) { [weak self, weak albumView] in
            guard let self, let albumView, contentView === albumView else { return }
            clipsToBounds = true
        }
        return true
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
    private let livePhotoBadge = LivePhotoBadgeView()
    private let uploadProgress = MediaUploadProgressView()
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 280)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 220)
    private var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        addSubview(livePhotoBadge)
        addSubview(uploadProgress)
        livePhotoBadge.frame = CGRect(x: 8, y: 8, width: 21, height: 21)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            uploadProgress.centerXAnchor.constraint(equalTo: centerXAnchor),
            uploadProgress.centerYAnchor.constraint(equalTo: centerYAnchor),
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
        photo: Photo,
        message: Message? = nil,
        isLivePhoto: Bool = false,
        displaySize: CGSize,
        client: TDLibClient,
        onTap: @escaping () -> Void,
    ) {
        self.onTap = onTap
        livePhotoBadge.isHidden = !isLivePhoto
        accessibilityLabel = isLivePhoto
            ? L10n.betterTG("Accessibility.OpenLivePhoto")
            : L10n.betterTG("Accessibility.OpenPhoto")
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        if let local = telegramLocalPhotoFile(for: message, photo: photo, preferred: .yBox) {
            imageView.load(
                file: local,
                placeholderData: photo.minithumbnail?.data,
                maximumPixelSize: 960,
                client: client,
            )
        } else {
            imageView.load(photo: photo, preferredSize: .yBox, client: client)
        }
    }

    func showUploadProgress(for message: Message, client: TDLibClient, onCancel: @escaping () -> Void) {
        uploadProgress.configure(message: message, client: client, onCancel: onCancel)
    }

    func prepareForReuse() {
        imageView.cancel()
        uploadProgress.reset()
        onTap = nil
    }

    func makeTransitionSnapshot() -> UIView? {
        imageView.makeImageSnapshot(contentMode: imageView.contentMode)
    }

    @objc private func tapped() {
        // While the photo uploads only the disc reacts (ChatMessageInteractiveMediaNode.imageTap).
        guard !uploadProgress.isActive else { return }
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
        maximumWidth: CGFloat,
        revealPermits: [Int64: MediaRevealPermit] = [:],
        videoPlaybackOwners: [Int64: GalleryVideoPlaybackOwner],
        onCancelSending: ((Int64) -> Void)? = nil,
        onTap: @escaping ([Message], Int64) -> Void,
    ) {
        prepareForReuse()
        // Telegram lays an album out in send order, first picked item first. The pending ID keeps that order while
        // TDLib replaces members with server IDs one by one.
        let messages = messages.sorted {
            MediaUploadProgressRegistry.sendOrderID(of: $0) < MediaUploadProgressRegistry.sendOrderID(of: $1)
        }
        self.messages = messages
        self.onTap = onTap
        let itemSizes = messages.map(telegramMessageMediaSize)
        let (layout, size) = telegramMessageBubbleMosaicLayout(
            maxSize: TelegramMediaLayout.albumMaximumSize(maximumWidth: maximumWidth),
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
            if let onCancelSending {
                let messageID = message.id
                tile.showUploadProgress(for: message, client: client) { onCancelSending(messageID) }
            }
            if layout.indices.contains(index) {
                tile.apply(position: layout[index].1)
            }
            addSubview(tile)
            tiles.append(tile)
            // Place the new tile now: a reconfigured row lays out inside the timeline's batch animation, which would
            // otherwise grow every tile and its upload disc from the album's corner.
            if itemFrames.indices.contains(index) {
                UIView.performWithoutAnimation {
                    tile.frame = itemFrames[index]
                    tile.layoutIfNeeded()
                }
            }
        }
        setNeedsLayout()
    }

    func setBubbleCorners(_ corners: CACornerMask) {
        layer.cornerRadius = corners.isEmpty ? 0 : 13
        layer.maskedCorners = corners
        for tile in tiles {
            let tileCorners = tile.layer.maskedCorners.intersection(corners)
            tile.layer.maskedCorners = tileCorners
            tile.layer.cornerRadius = tileCorners.isEmpty ? 0 : 13
        }
    }

    @discardableResult func restoreInlineVideoPlaybackOwner(_ owner: GalleryVideoPlaybackOwner) -> Bool {
        guard let tile = tiles.first(where: { $0.messageID == owner.messageID }) else { return false }
        return tile.restoreInlineVideoPlaybackOwner(owner)
    }

    func transitionSourceView(for messageID: Int64) -> UIView? {
        tiles.first(where: { $0.messageID == messageID })
    }

    func tileFrames(in coordinateSpace: UIView) -> [Int64: CGRect] {
        var frames = [Int64: CGRect]()
        for tile in tiles {
            guard let messageID = tile.messageID else { continue }
            frames[messageID] = tile.convert(tile.bounds, to: coordinateSpace)
        }
        return frames
    }

    func tileSnapshot(for messageID: Int64) -> UIView? {
        tiles.first(where: { $0.messageID == messageID })?.snapshotView(afterScreenUpdates: false)
    }

    /// ChatMessageBubbleItemNode lays a group out again in its bubble: every remaining media node moves from its
    /// frame to the new one on the list's 0.4 s transition, and a new one fades in over 0.25 s
    /// (ChatMessageMediaBubbleContentNode.animateInsertionIntoBubble).
    func animateTiles(
        from frames: [Int64: CGRect],
        in coordinateSpace: UIView,
        completion: @escaping () -> Void,
    ) {
        layoutIfNeeded()
        var moving = [(AlbumMediaTileView, CGRect)]()
        for (index, tile) in tiles.enumerated() where itemFrames.indices.contains(index) {
            guard let messageID = tile.messageID, let frame = frames[messageID] else {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.25
                tile.layer.add(fade, forKey: "album.tileInsertion")
                continue
            }
            moving.append((tile, itemFrames[index]))
            UIView.performWithoutAnimation {
                tile.frame = coordinateSpace.convert(frame, to: self)
                tile.layoutIfNeeded()
            }
        }
        clipsToBounds = false
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction],
        ) {
            for (tile, frame) in moving {
                tile.frame = frame
                tile.layoutIfNeeded()
            }
        } completion: { [weak self] _ in
            self?.clipsToBounds = true
            completion()
        }
    }

    func messageID(at point: CGPoint, in coordinateSpace: UIView) -> Int64? {
        tiles.first { $0.convert($0.bounds, to: coordinateSpace).contains(point) }?.messageID
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
    private let livePhotoBadge = LivePhotoBadgeView()
    private let uploadProgress = MediaUploadProgressView()
    private var showsPlayIcon = false
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
        addSubview(livePhotoBadge)
        addSubview(uploadProgress)
        livePhotoBadge.frame = CGRect(x: 8, y: 8, width: 21, height: 21)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
        NSLayoutConstraint.activate([
            playIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            uploadProgress.centerXAnchor.constraint(equalTo: centerXAnchor),
            uploadProgress.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        uploadProgress.showsUploadedCheck = true
        uploadProgress.onActiveChange = { [weak self] active in
            guard let self else { return }
            playIcon.isHidden = active || !showsPlayIcon
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // RadialStatusNode is 50 pt in media bubbles and 32 pt where the media is small.
        uploadProgress.diameter = min(bounds.width, bounds.height) < 90 ? 32 : 50
    }

    override func accessibilityActivate() -> Bool {
        guard let onTap, !uploadProgress.isActive else { return false }
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
            bringSubviewToFront(uploadProgress)
            accessibilityLabel = videoPlaybackOwner.isAnimation
                ? L10n.betterTG("Accessibility.OpenAnimation")
                : L10n.betterTG("Accessibility.OpenVideo")
            accessibilityTraits = videoPlaybackOwner.isAnimation ? .button : [.button, .playsSound]
            return
        }
        imageView.isHidden = false
        accessibilityLabel = L10n.betterTG("Accessibility.OpenMedia")
        accessibilityTraits = .button
        switch message.content {
        case .messagePhoto(let photo):
            playIcon.isHidden = true
            livePhotoBadge.isHidden = photo.video == nil
            if let local = telegramLocalPhotoFile(for: message, photo: photo.photo, preferred: .yBox) {
                imageView.load(
                    file: local,
                    placeholderData: photo.photo.minithumbnail?.data,
                    maximumPixelSize: 960,
                    client: client,
                )
            } else {
                imageView.load(photo: photo.photo, preferredSize: .yBox, client: client)
            }
        case .messageVideo(let video):
            // A video this session sends keeps the frame it was picked with until inline playback takes the tile.
            // TDLib swaps its thumbnail when an album item uploads before the others and again once it is sent;
            // Telegram keeps the same media node, and its autoplaying bubble has no play icon.
            let poster = MediaUploadProgressRegistry.sentVideoPoster(
                for: MediaUploadProgressRegistry.Key(chatID: message.chatId, messageID: message.id),
            )
            playIcon.isHidden = poster != nil
            if let poster {
                imageView.image = poster
            } else if let thumbnail = video.video.thumbnail {
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
        showsPlayIcon = !playIcon.isHidden
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
        uploadProgress.reset()
        showsPlayIcon = false
        onTap = nil
        livePhotoBadge.isHidden = true
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
        bringSubviewToFront(uploadProgress)
        return videoPlaybackAttachmentToken != nil
    }

    func showUploadProgress(for message: Message, client: TDLibClient, onCancel: @escaping () -> Void) {
        // Over inline playback the disc only finishes the fade its pending tile began.
        guard cover == nil else { return }
        uploadProgress.configure(message: message, client: client, onCancel: onCancel)
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
        guard !uploadProgress.isActive else { return }
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
    /// Finishes the fade of the upload disc when TDLib replaces a sent video's pending bubble.
    private let uploadProgress = MediaUploadProgressView()
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 280)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 220)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
        addSubview(uploadProgress)
        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            uploadProgress.centerXAnchor.constraint(equalTo: centerXAnchor),
            uploadProgress.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        accessibilityTraits = [.button, .playsSound]
        accessibilityLabel = L10n.betterTG("Accessibility.OpenVideo")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        guard let onTap, !uploadProgress.isActive else { return false }
        onTap()
        return true
    }

    // MARK: Internal

    func configure(
        owner: GalleryVideoPlaybackOwner,
        displaySize: CGSize,
        onTap: @escaping () -> Void,
    ) {
        prepareForReuse()
        messageID = owner.messageID
        self.owner = owner
        accessibilityLabel = owner.isAnimation
            ? L10n.betterTG("Accessibility.OpenAnimation")
            : L10n.betterTG("Accessibility.OpenVideo")
        accessibilityTraits = owner.isAnimation ? .button : [.button, .playsSound]
        self.onTap = onTap
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        attachmentToken = owner.attach(to: self, context: .inline)
        bringSubviewToFront(uploadProgress)
    }

    func prepareForReuse() {
        if let attachmentToken {
            owner?.detach(attachment: attachmentToken)
        }
        attachmentToken = nil
        owner = nil
        onTap = nil
        messageID = nil
        uploadProgress.reset()
    }

    /// A sending video plays inline from its local file; its disc cancels the send as the other media's do.
    func showUploadProgress(for message: Message, client: TDLibClient, onCancel: @escaping () -> Void) {
        uploadProgress.configure(message: message, client: client, onCancel: onCancel)
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
        bringSubviewToFront(uploadProgress)
        return attachmentToken != nil
    }

    func makeTransitionSnapshot() -> UIView? {
        owner?.makeTransitionSnapshot(contentMode: .scaleAspectFill)
            ?? snapshotView(afterScreenUpdates: false)
    }

    @objc private func tapped() {
        // While the video uploads only the disc reacts (ChatMessageInteractiveMediaNode.imageTap).
        guard !uploadProgress.isActive else { return }
        onTap?()
    }
}

// MARK: - FileMediaPreviewView

final class FileMediaPreviewView: UIControl, ReusableMediaView {
    // MARK: Private

    private let imageView = TDImageLoadingView()
    private let playIcon = UIImageView()
    private let uploadProgress = MediaUploadProgressView()
    private var showsPlayIcon = false
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
        addSubview(uploadProgress)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            uploadProgress.centerXAnchor.constraint(equalTo: centerXAnchor),
            uploadProgress.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightConstraint,
            widthConstraint,
        ])
        uploadProgress.onActiveChange = { [weak self] active in
            guard let self else { return }
            playIcon.isHidden = active || !showsPlayIcon
        }
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
        displaySize: CGSize,
        showsPlayIcon: Bool,
        usesFileAsThumbnailFallback: Bool = true,
        client: TDLibClient,
        onTap: @escaping () -> Void,
    ) {
        self.onTap = onTap
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        self.showsPlayIcon = showsPlayIcon
        playIcon.isHidden = !showsPlayIcon
        if let thumbnail {
            imageView.load(file: thumbnail.file, placeholderData: minithumbnail?.data, client: client)
        } else if usesFileAsThumbnailFallback {
            imageView.load(file: file, placeholderData: minithumbnail?.data, client: client)
        } else {
            imageView.loadPlaceholder(data: minithumbnail?.data, client: client)
        }
    }

    func showUploadProgress(for message: Message, client: TDLibClient, onCancel: @escaping () -> Void) {
        uploadProgress.configure(message: message, client: client, onCancel: onCancel)
    }

    /// A video this session just sent keeps its pending frame, without a play icon, until inline playback takes
    /// the bubble; Telegram's autoplaying bubble has none.
    func showSentVideoPoster(for message: Message) {
        guard message.sendingState == nil,
              let poster = MediaUploadProgressRegistry.sentVideoPoster(
                  for: MediaUploadProgressRegistry.Key(chatID: message.chatId, messageID: message.id),
              )
        else { return }
        imageView.cancel()
        imageView.image = poster
        showsPlayIcon = false
        playIcon.isHidden = true
    }

    func prepareForReuse() {
        imageView.cancel()
        uploadProgress.reset()
        onTap = nil
    }

    func makeTransitionSnapshot() -> UIView? {
        imageView.makeImageSnapshot(contentMode: imageView.contentMode)
    }

    @objc private func tapped() {
        guard !uploadProgress.isActive else { return }
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
        let contentID: String
        let maximumPixelSize: Int
        let generation: UUID

        var thumbnailKey: TDImageThumbnailKey {
            TDImageThumbnailKey(
                accountID: accountID,
                clientID: clientID,
                fileID: fileID,
                maximumPixelSize: maximumPixelSize,
                contentID: contentID,
            )
        }
    }

    // MARK: Internal

    private(set) var loadedPath: String?
    /// Runs each time the full image (not its placeholder) is shown, as the story viewer starts a photo's clock then.
    var onFullImage: (() -> Void)?

    #if DEBUG
        var debugDecode: ((String, Int) async -> UIImage?)?
    #endif

    private var representedRequest: RequestIdentity?
    private var representedOrigin: TDImageOrigin?
    private var fileRequest: AnimatedFileDownload?
    private var renderGeneration = UUID()
    private var hasFullImage = false
    private var imageTransitionDuration: TimeInterval = 0
    private var decodeTask: Task<Void, Never>?
    private var placeholderTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    static func fileUpdates(
        source: TdUpdateSource,
        fileID: Int,
        center: NotificationCenter = nc,
        currentSource: @escaping () -> TdUpdateSource? = { TDLib.shared.activeUpdateSource },
    ) -> AnyPublisher<File, Never> {
        center.publisher(for: TdNotification<UpdateFile>.updateFile.name)
            .compactMap { TdScopedUpdate<UpdateFile>(notification: $0) }
            .receive(on: DispatchQueue.main)
            .filter { $0.source == source && currentSource() == source && $0.value.file.id == fileID }
            .map(\.value.file)
            .eraseToAnyPublisher()
    }

    private static func decodeImage(at path: String, key: TDImageThumbnailKey) async -> UIImage? {
        await TDImageThumbnailPipeline.shared.image(at: path, key: key).map { UIImage(cgImage: $0.image) }
    }

    func load(
        photo: Photo,
        preferredSize: PhotoSizeType,
        maximumPixelSize: Int = 960,
        client: TDLibClient,
        preservingImage: Bool = false,
    ) {
        load(
            photo: photo,
            preferredSize: preferredSize,
            maximumPixelSize: maximumPixelSize,
            origin: .captured(client: client),
            preservingImage: preservingImage,
        )
    }

    func load(
        photo: Photo,
        preferredSize: PhotoSizeType,
        maximumPixelSize: Int = 960,
        origin: TDImageOrigin?,
        preservingImage: Bool = false,
    ) {
        let placeholderData = photo.minithumbnail?.data
        guard let size = photo.sizes.getSize(preferredSize) ?? photo.sizes.first else {
            loadPlaceholder(data: placeholderData, maximumPixelSize: maximumPixelSize, origin: origin)
            return
        }
        load(
            file: size.photo,
            placeholderData: placeholderData,
            maximumPixelSize: maximumPixelSize,
            origin: origin,
            preservingImage: preservingImage,
        )
    }

    func load(
        file: File,
        placeholderData: Data? = nil,
        maximumPixelSize: Int = 1280,
        accountID: UUID? = nil,
        client: TDLibClient,
        preservingImage: Bool = false,
        transitionDuration: TimeInterval = 0,
    ) {
        load(
            file: file,
            placeholderData: placeholderData,
            maximumPixelSize: maximumPixelSize,
            origin: .captured(client: client, accountID: accountID),
            preservingImage: preservingImage,
            transitionDuration: transitionDuration,
        )
    }

    /// `preservingImage` keeps the current image until the new one decodes; `transitionDuration` cross-fades it.
    func load(
        file: File,
        placeholderData: Data? = nil,
        maximumPixelSize: Int = 960,
        origin: TDImageOrigin?,
        preservingImage: Bool = false,
        transitionDuration: TimeInterval = 0,
    ) {
        cancel()
        imageTransitionDuration = transitionDuration
        if !preservingImage { image = nil }
        guard let origin, admit(origin) else { return }
        let request = RequestIdentity(
            accountID: origin.source.accountID,
            clientID: origin.source.clientID,
            fileID: file.id,
            contentID: file.remote.uniqueId,
            maximumPixelSize: maximumPixelSize,
            generation: UUID(),
        )
        representedRequest = request
        renderGeneration = request.generation
        hasFullImage = false
        if let cached = TDImageThumbnailPipeline.shared.cachedImage(for: request.thumbnailKey.cacheKey) {
            apply(UIImage(cgImage: cached.image), asFullImageFor: request)
            return
        }
        if !preservingImage {
            if let preview = MediaUploadProgressRegistry.sentPreview(forPath: file.local.path) {
                image = preview
            } else {
                preparePlaceholder(placeholderData, for: request)
            }
        }
        let download = origin.request(fileID: file.id)
        fileRequest = download
        download.start(
            file: file,
            onFile: { [weak self] in self?.update(file: $0, for: request) },
            onInvalidated: { [weak self] in self?.originDidChange(to: TDLib.shared.activeUpdateSource) },
        )
    }

    func loadPlaceholder(data: Data?, maximumPixelSize: Int = 960, client: TDLibClient) {
        loadPlaceholder(data: data, maximumPixelSize: maximumPixelSize, origin: .captured(client: client))
    }

    func loadPlaceholder(data: Data?, maximumPixelSize: Int = 960, origin: TDImageOrigin?) {
        cancel()
        image = nil
        guard let origin, admit(origin), let data else { return }
        let generation = renderGeneration
        placeholderTask = Task { [weak self] in
            let prepared = await TDImageThumbnailPipeline.shared.standalonePlaceholderImage(
                data: data,
                maximumPixelSize: maximumPixelSize,
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.renderGeneration == generation,
                      self.representedOrigin?.isCurrent == true,
                      let prepared
                else { return }
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
        imageTransitionDuration = 0
        renderGeneration = UUID()
        representedRequest = nil
        representedOrigin = nil
        hasFullImage = false
        fileRequest?.cancel()
        fileRequest = nil
        decodeTask?.cancel()
        decodeTask = nil
        placeholderTask?.cancel()
        placeholderTask = nil
        cancellable?.cancel()
        cancellable = nil
        loadedPath = nil
    }

    private func admit(_ origin: TDImageOrigin) -> Bool {
        guard origin.isCurrent else { return false }
        representedOrigin = origin
        cancellable = origin.changes.receive(on: DispatchQueue.main).sink { [weak self] source in
            guard let self, representedOrigin?.isCurrent != true else { return }
            originDidChange(to: source)
        }
        return true
    }

    /// Returning from the background renews the same account's client: keep the pixels until the owner loads them
    /// through the new client. Another account never sees them.
    private func originDidChange(to source: TdUpdateSource?) {
        if let source, source.accountID == representedOrigin?.source.accountID { cancel() } else { invalidate() }
    }

    private func invalidate() {
        cancel()
        image = nil
    }

    private func update(file: File, for request: RequestIdentity) {
        guard representedRequest == request,
              representedOrigin?.isCurrent == true,
              file.id == request.fileID,
              file.local.isDownloadingCompleted, !file.local.path.isEmpty,
              loadedPath != file.local.path
        else { return }
        let path = file.local.path
        let key = request.thumbnailKey
        loadedPath = path
        decodeTask?.cancel()
        #if DEBUG
            let debugDecode = debugDecode
        #endif
        decodeTask = Task { [weak self] in
            #if DEBUG
                let decoded =
 if let debugDecode {
                    await debugDecode(path, key.maximumPixelSize)
                } else {
                    await Self.decodeImage(at: path, key: key)
                }
            #else
                let decoded = await Self.decodeImage(at: path, key: key)
            #endif
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.representedRequest == request,
                      self.representedOrigin?.isCurrent == true,
                      let decoded
                else { return }
                self.apply(decoded, asFullImageFor: request)
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
                      self.representedOrigin?.isCurrent == true,
                      !self.hasFullImage,
                      let prepared
                else { return }
                self.image = UIImage(cgImage: prepared.image)
            }
        }
    }

    private func apply(_ decoded: UIImage, asFullImageFor request: RequestIdentity) {
        guard representedRequest == request else { return }
        hasFullImage = true
        placeholderTask?.cancel()
        placeholderTask = nil
        if imageTransitionDuration > 0, image != nil {
            UIView.transition(
                with: self,
                duration: imageTransitionDuration,
                options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState],
            ) {
                self.image = decoded
            }
        } else {
            image = decoded
        }
        onFullImage?()
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

    /// The voice or video-note files a prefetch starts outside the shared demand and doesn't wait for.
    static func playbackFileIDs(in message: Message) -> [Int] {
        // A self-destructing voice note is loaded only by the play-once overlay that consumes it.
        guard message.selfDestructType == nil else { return [] }
        let file: File? =
            switch message.content {
            case .messageVoiceNote(let voice): voice.voiceNote.voice
            case .messageVideoNote(let video): video.videoNote.video
            default: nil
            }
        guard let file, !file.local.isDownloadingCompleted else { return [] }
        return [file.id]
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
                [(voice.voiceNote.voice, .unpooledMedia)]
            case .messageVideoNote(let video):
                [video.videoNote.thumbnail?.file].compactMap(\.self).map { ($0, .none) }
                    + [(video.videoNote.video, .unpooledMedia)]
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
                MessageContentPresentation.diceStickers(dice.value == 0 ? dice.initialState : dice.finalState)
                    .flatMap { stickerFiles($0) }
            case .messageVideo(let video):
                [video.video.thumbnail?.file].compactMap(\.self).map { ($0, .none) }
            default:
                []
            }
        for file in files {
            guard !Task.isCancelled, TDLib.shared.activeUpdateSource == source,
                  MediaRevealPermit.allows(message, permit: revealPermit, requiresPermit: true) else { return }
            let downloaded: File?
            switch file.decodeKind {
            case .none:
                guard let origin = TDImageOrigin.captured(client: client) else { return }
                downloaded = await origin.request(fileID: file.file.id).completedFile(file: file.file)
            case .ffmpegVideo, .tgs, .webP:
                guard let request = AnimatedFileDownload(fileID: file.file.id, client: client) else { return }
                downloaded = await request.completedFile(file: file.file)
            case .unpooledMedia:
                // Playback does not share this demand yet. Start prefetch without waiting for completion; ChatView
                // cancels the pending download if the row leaves the prefetch range unseen.
                downloaded = try? await client.downloadFile(
                    fileId: file.file.id,
                    limit: 0,
                    offset: 0,
                    priority: 1,
                    synchronous: false,
                )
            }
            guard !Task.isCancelled, TDLib.shared.activeUpdateSource == source,
                  MediaRevealPermit.allows(message, permit: revealPermit, requiresPermit: true) else { return }
            guard let downloaded,
                  downloaded.local.isDownloadingCompleted,
                  !downloaded.local.path.isEmpty
            else { continue }
            switch file.decodeKind {
            case .none:
                let key = TDImageThumbnailKey(
                    accountID: source.accountID,
                    clientID: source.clientID,
                    fileID: downloaded.id,
                    maximumPixelSize: 960,
                    contentID: downloaded.remote.uniqueId,
                )
                _ = await TDImageThumbnailPipeline.shared.image(at: downloaded.local.path, key: key)
            case .unpooledMedia:
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

private func telegramMediaKind(_ message: Message) -> TelegramMediaLayout.Kind {
    switch message.content {
    case .messageVideo: .video
    case .messageAnimation: .animation
    case .messageSticker: .sticker
    default: .image
    }
}
