// PollMediaViews.swift

import MapKit
import TDLibKit
import UIKit

// MARK: - PollMediaStill

/// The still image Telegram's poll draws for its media (ChatMessagePollOptionNode's TransformImageNode signals): a
/// photo, a video's cover or thumbnail, an animation's or a file's thumbnail, or a link's preview photo.
struct PollMediaStill {
    /// The media's size in pixels, whose aspect a large preview keeps; zero when unknown.
    let pixelSize: CGSize

    private let photo: Photo?
    private let file: File?
    private let minithumbnail: Data?

    init?(_ media: TDNativePollMedia) {
        switch media {
        case .pollMediaPhoto(let value):
            self.init(photo: value.photo)
        case .pollMediaVideo(let value):
            let size = CGSize(width: value.video.width, height: value.video.height)
            if let cover = value.cover {
                self.init(photo: cover, pixelSize: size)
            } else {
                self.init(
                    file: Self.imageFile(value.video.thumbnail),
                    minithumbnail: value.video.minithumbnail?.data,
                    pixelSize: size,
                )
            }
        case .pollMediaAnimation(let value):
            self.init(
                file: Self.imageFile(value.animation.thumbnail),
                minithumbnail: value.animation.minithumbnail?.data,
                pixelSize: CGSize(width: value.animation.width, height: value.animation.height),
            )
        case .pollMediaDocument(let value):
            self.init(
                file: Self.imageFile(value.document.thumbnail),
                minithumbnail: value.document.minithumbnail?.data,
                pixelSize: Self.size(of: value.document.thumbnail),
            )
        case .pollMediaAudio(let value):
            self.init(
                file: Self.imageFile(value.audio.albumCoverThumbnail),
                minithumbnail: value.audio.albumCoverMinithumbnail?.data,
                pixelSize: Self.size(of: value.audio.albumCoverThumbnail),
            )
        case .pollMediaLink(let value):
            // ChatMessagePollOptionNode draws a link's preview image (the web page's `content.image`).
            guard let preview = value.linkPreview,
                  let thumbnail = MessageLinkPreviewView.thumbnail(preview.type) else { return nil }
            self.init(file: thumbnail.file, minithumbnail: thumbnail.placeholder, pixelSize: thumbnail.size)
        case .pollMediaLocation, .pollMediaSticker, .pollMediaVenue:
            return nil
        }
    }

    private init(photo: Photo, pixelSize: CGSize? = nil) {
        let largest = photo.sizes.max { $0.width * $0.height < $1.width * $1.height }
        self.photo = photo
        self.file = nil
        self.minithumbnail = photo.minithumbnail?.data
        self.pixelSize = pixelSize ?? largest.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    private init?(file: File?, minithumbnail: Data?, pixelSize: CGSize) {
        guard file != nil || minithumbnail != nil else { return nil }
        self.photo = nil
        self.file = file
        self.minithumbnail = minithumbnail
        self.pixelSize = pixelSize
    }

    /// A thumbnail the image pipeline decodes; an MPEG-4 or a TGS thumbnail isn't one.
    private static func imageFile(_ thumbnail: TDNativeThumbnail?) -> File? {
        guard let thumbnail else { return nil }
        return switch thumbnail.format {
        case .thumbnailFormatGif, .thumbnailFormatJpeg, .thumbnailFormatPng, .thumbnailFormatWebp: thumbnail.file
        default: nil
        }
    }

    private static func size(of thumbnail: TDNativeThumbnail?) -> CGSize {
        thumbnail.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    @MainActor func load(into view: TDImageLoadingView, maximumPixelSize: Int, client: TDLibClient) {
        if let photo {
            view.load(
                photo: photo,
                preferredSize: maximumPixelSize > 320 ? .xBox : .mBox,
                maximumPixelSize: maximumPixelSize,
                client: client,
            )
        } else if let file {
            view.load(file: file, placeholderData: minithumbnail, maximumPixelSize: maximumPixelSize, client: client)
        } else {
            view.loadPlaceholder(data: minithumbnail, maximumPixelSize: maximumPixelSize, client: client)
        }
    }
}

// MARK: - PollMapSnapshotView

/// A place's map as a still image (Telegram's MapSnapshotMediaResource).
final class PollMapSnapshotView: UIImageView {
    private var snapshotter: MKMapSnapshotter?
    private var generation = UUID()

    func load(_ location: Location, size: CGSize, meters: CLLocationDistance) {
        cancel()
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
        options.size = size
        options.scale = max(1, Utils.screen.scale)
        options.traitCollection = traitCollection
        let snapshotter = MKMapSnapshotter(options: options)
        let requestGeneration = generation
        self.snapshotter = snapshotter
        snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { [weak self] snapshot, _ in
            guard let image = snapshot?.image else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == requestGeneration else { return }
                self.image = image
                self.snapshotter = nil
            }
        }
    }

    func cancel() {
        generation = UUID()
        snapshotter?.cancel()
        snapshotter = nil
        image = nil
    }
}

// MARK: - PollMediaThumbnailView

/// ChatMessagePollOptionNode's answer media: a 40-point thumbnail with 10-point corners at the answer's trailing edge.
/// A sticker is drawn whole and fitted, a video carries the play button, a link shows its icon over the dimmed preview
/// photo or, without one, on the accent color, and a place shows its map.
final class PollMediaThumbnailView: UIControl {
    static let size = CGSize(width: 40, height: 40)

    override var isHighlighted: Bool {
        didSet { imageView.alpha = isHighlighted ? 0.6 : 1 }
    }

    var onTap: ((TDNativePollMedia) -> Void)?

    private let imageView = TDImageLoadingView()
    private let mapView = PollMapSnapshotView()
    private let overlayView = UIView()
    private let iconView = UIImageView()
    private var stickerView: CustomEmojiInlineView?
    private var media: TDNativePollMedia?
    private var playbackVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        mapView.contentMode = .scaleAspectFill
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        iconView.contentMode = .center
        for view in [imageView, mapView, overlayView, iconView] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isUserInteractionEnabled = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        prepareForReuse()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A sticker's size fitted into the thumbnail, as `dimensions.aspectFitted(mediaFrame.size)`.
    private static func fittedSize(width: Int, height: Int) -> CGSize {
        guard width > 0, height > 0 else { return size }
        let scale = min(size.width / CGFloat(width), size.height / CGFloat(height))
        return CGSize(width: floor(CGFloat(width) * scale), height: floor(CGFloat(height) * scale))
    }

    func configure(media: TDNativePollMedia, client: TDLibClient) {
        prepareForReuse()
        self.media = media
        switch media {
        case .pollMediaSticker(let value):
            backgroundColor = .clear
            clipsToBounds = false
            let stickerView = CustomEmojiInlineView()
            stickerView.translatesAutoresizingMaskIntoConstraints = false
            stickerView.isUserInteractionEnabled = false
            addSubview(stickerView)
            let fitted = Self.fittedSize(width: value.sticker.width, height: value.sticker.height)
            NSLayoutConstraint.activate([
                stickerView.centerXAnchor.constraint(equalTo: centerXAnchor),
                stickerView.centerYAnchor.constraint(equalTo: centerYAnchor),
                stickerView.widthAnchor.constraint(equalToConstant: fitted.width),
                stickerView.heightAnchor.constraint(equalToConstant: fitted.height),
            ])
            stickerView.configure(sticker: value.sticker, client: client)
            stickerView.setPlaybackVisible(playbackVisible)
            self.stickerView = stickerView
        case .pollMediaLocation(let value):
            mapView.load(value.location, size: Self.size, meters: 500)
        case .pollMediaVenue(let value):
            mapView.load(value.venue.location, size: Self.size, meters: 500)
        case .pollMediaLink:
            let link = UIImage(
                systemName: "link",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
            )
            iconView.image = link
            iconView.isHidden = false
            if let still = PollMediaStill(media) {
                still.load(into: imageView, maximumPixelSize: 160, client: client)
                overlayView.isHidden = false
                iconView.tintColor = .white
            } else {
                backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
                iconView.tintColor = .systemBlue
            }
        default:
            PollMediaStill(media)?.load(into: imageView, maximumPixelSize: 160, client: client)
            if case .pollMediaVideo = media {
                iconView.image = UIImage(
                    systemName: "play.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold),
                )
                iconView.tintColor = .white
                iconView.isHidden = false
            }
        }
    }

    func prepareForReuse() {
        media = nil
        imageView.cancel()
        imageView.image = nil
        mapView.cancel()
        stickerView?.prepareForReuse()
        stickerView?.removeFromSuperview()
        stickerView = nil
        overlayView.isHidden = true
        iconView.isHidden = true
        iconView.image = nil
        backgroundColor = .tertiarySystemFill
        clipsToBounds = true
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        stickerView?.setPlaybackVisible(isVisible)
    }

    @objc private func tapped() {
        guard let media else { return }
        onTap?(media)
    }
}

// MARK: - PollMediaPreviewView

/// A poll's own media above its question, and a quiz explanation's media, as Telegram's media bubble draws them
/// (ChatMessageMediaBubbleContentNode, ChatMessageAttachedContentNode): a photo, video or GIF at its aspect within the
/// bubble's width, with the play button on a video, or a sticker on its own.
final class PollMediaPreviewView: UIControl, MessageSupplementView {
    private static let maximumHeight: CGFloat = 320
    private static let minimumHeight: CGFloat = 100
    private static let stickerSide: CGFloat = 140

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.8 : 1 }
    }

    private let media: TDNativePollMedia
    private let onTap: (TDNativePollMedia) -> Void
    private let imageView = TDImageLoadingView()
    private let playView = UIImageView()
    private var animationView: InlineAnimationMediaView?
    private var stickerView: CustomEmojiInlineView?

    /// Nil for media this preview doesn't draw: a file, a place or a link.
    init?(media: TDNativePollMedia, client: TDLibClient, onTap: @escaping (TDNativePollMedia) -> Void) {
        switch media {
        case .pollMediaAnimation, .pollMediaPhoto, .pollMediaSticker, .pollMediaVideo:
            break
        default:
            return nil
        }
        self.media = media
        self.onTap = onTap
        super.init(frame: .zero)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = [.image, .button]
        if case .pollMediaSticker(let value) = media {
            configureSticker(value.sticker, client: client)
        } else {
            configureVisualMedia(client: client)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        imageView.cancel()
        animationView?.prepareForReuse()
        stickerView?.prepareForReuse()
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        animationView?.setPlaybackVisible(isVisible)
        stickerView?.setPlaybackVisible(isVisible)
    }

    private func configureSticker(_ sticker: Sticker, client: TDLibClient) {
        let stickerView = CustomEmojiInlineView()
        stickerView.translatesAutoresizingMaskIntoConstraints = false
        stickerView.isUserInteractionEnabled = false
        addSubview(stickerView)
        let aspect = sticker.width > 0 && sticker.height > 0 ? CGFloat(sticker.height) / CGFloat(sticker.width) : 1
        let width = aspect > 1 ? Self.stickerSide / aspect : Self.stickerSide
        NSLayoutConstraint.activate([
            stickerView.topAnchor.constraint(equalTo: topAnchor),
            stickerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stickerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stickerView.widthAnchor.constraint(equalToConstant: floor(width)),
            stickerView.heightAnchor.constraint(equalToConstant: floor(width * aspect)),
        ])
        stickerView.configure(sticker: sticker, client: client)
        self.stickerView = stickerView
        accessibilityLabel = sticker.emoji
    }

    private func configureVisualMedia(client: TDLibClient) {
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true
        let still = PollMediaStill(media)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        pinToEdges(imageView)
        still?.load(into: imageView, maximumPixelSize: 960, client: client)

        switch media {
        case .pollMediaAnimation(let value) where !telegramAnimationUsesFFmpeg(value.animation):
            // The media bubble plays a GIF in place.
            let animationView = InlineAnimationMediaView()
            animationView.translatesAutoresizingMaskIntoConstraints = false
            animationView.fillsBounds = true
            addSubview(animationView)
            pinToEdges(animationView)
            animationView.configure(animation: value.animation, displaySize: nil, client: client)
            self.animationView = animationView
            accessibilityLabel = L10n.telegram("Message.Animation")
        case .pollMediaAnimation:
            accessibilityLabel = L10n.telegram("Message.Animation")
        case .pollMediaVideo:
            playView.translatesAutoresizingMaskIntoConstraints = false
            playView.image = UIImage(
                systemName: "play.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold),
            )
            playView.contentMode = .center
            playView.tintColor = .white
            playView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            playView.layer.cornerRadius = 25
            playView.clipsToBounds = true
            playView.isUserInteractionEnabled = false
            addSubview(playView)
            NSLayoutConstraint.activate([
                playView.centerXAnchor.constraint(equalTo: centerXAnchor),
                playView.centerYAnchor.constraint(equalTo: centerYAnchor),
                playView.widthAnchor.constraint(equalToConstant: 50),
                playView.heightAnchor.constraint(equalToConstant: 50),
            ])
            accessibilityLabel = L10n.betterTG("Accessibility.PlayVideo")
        default:
            accessibilityLabel = L10n.betterTG("Accessibility.OpenPhoto")
        }

        let size = still?.pixelSize ?? .zero
        let aspect = size.width > 0 && size.height > 0 ? min(2, max(0.3, size.height / size.width)) : 0.75
        let aspectHeight = heightAnchor.constraint(equalTo: widthAnchor, multiplier: aspect)
        aspectHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            aspectHeight,
            heightAnchor.constraint(lessThanOrEqualToConstant: Self.maximumHeight),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight),
        ])
    }

    private func pinToEdges(_ view: UIView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func tapped() {
        onTap(media)
    }
}
