// StoryViewerCube.swift

import TDLibKit
import UIKit

// MARK: - StoryCubeGeometry

/// The cube StoryContainerScreen turns between posters. Each poster's set is a face half a width in front of the
/// cube's center (faceTransform); a face at rotation `t` (0 in front, -1 for the previous poster, 1 for the next)
/// turns by `t·(π/2 + sideAngle)` under a 500 pt perspective, where sideAngle keeps the faces' edges together and
/// leaves a 40 pt gap at a whole turn in a compact width. A face's black gradient deepens as it turns away.
enum StoryCubeGeometry {
    static let perspective = CGFloat(500)
    /// commitHorizontalPan turns the cube past this fraction of the width, or on a faster flick.
    static let commitFraction = CGFloat(0.3)
    static let commitVelocity = CGFloat(100)
    /// The turn's spring transition (ComponentTransition .curve(duration: 0.4, curve: .spring)).
    static let turnDuration = 0.4

    /// Telegram leaves no gap in a regular width, where the story is a card.
    static func sideDistance(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 0 : 40
    }

    static func sideAngle(width: CGFloat, sideDistance: CGFloat) -> CGFloat {
        let squaredPerspective = perspective * perspective
        let d = -squaredPerspective * sideDistance * sideDistance
        let e = squaredPerspective * width * width
        let f = sideDistance * sideDistance * width * width
        let cubedWidth = width * width * width
        let c = (d + e + f + sideDistance * cubedWidth + 0.25 * cubedWidth * width).squareRoot()
        let a = 2 * perspective * width - 2 * c
        let b = -2 * perspective * sideDistance + 2 * sideDistance * width + width * width
        return 2 * atan(a / b)
    }

    static func faceTransform(width: CGFloat) -> CATransform3D {
        CATransform3DMakeTranslation(0, 0, width / 2)
    }

    /// calculateCubeTransform: the turn of a face set at `rotation`, about the cube's center.
    static func cubeTransform(rotation: CGFloat, sideAngle: CGFloat, width: CGFloat) -> CATransform3D {
        let absT = abs(rotation)
        let angle = rotation * (CGFloat.pi / 2 + sideAngle)
        let squareRootOfTwo = CGFloat(1.4142135623731)
        let quarterPi = CGFloat(0.785398163397448)
        let distanceA = -squareRootOfTwo * absT * cos(sideAngle + quarterPi)
        let distanceB = sin(sideAngle * absT + CGFloat.pi / 2 * absT + quarterPi)
        let cubeDistance = width / 2 * (distanceA + absT + squareRootOfTwo * distanceB - 1)
        let backDistance = width / 2 + width * tan(sideAngle) / 2 - width / (2 * cos(sideAngle))
        var perspectiveTransform = CATransform3DIdentity
        perspectiveTransform.m34 = -1 / perspective
        var transform = CATransform3DTranslate(perspectiveTransform, 0, 0, -width / 2)
        transform = CATransform3DTranslate(transform, 0, 0, -cubeDistance + backDistance)
        transform = CATransform3DConcat(CATransform3DMakeRotation(angle, 0, 1, 0), transform)
        return CATransform3DTranslate(transform, 0, 0, -backDistance)
    }

    /// A face's whole transform: its place on the cube, then the cube's turn.
    static func transform(rotation: CGFloat, sideAngle: CGFloat, width: CGFloat) -> CATransform3D {
        guard abs(rotation) > 0.0001 else { return CATransform3DIdentity }
        return CATransform3DConcat(
            faceTransform(width: width),
            cubeTransform(rotation: rotation, sideAngle: sideAngle, width: width),
        )
    }

    /// updateHorizontalPan's rubber banding when no poster lies in the drag's direction.
    static func rubberBand(_ offset: CGFloat) -> CGFloat {
        let range = CGFloat(600)
        let coefficient = CGFloat(0.4)
        return (1 - 1 / (offset * coefficient / range + 1)) * range
    }

    static func tintAlpha(rotation: CGFloat) -> CGFloat {
        min(1, abs(rotation * 1.3))
    }

    /// Telegram's `.spring` curve (listViewAnimationCurveSystem): the iOS 26 spring (mass 1, stiffness 555.027,
    /// damping 47.118, critically damped) sampled across its 0.5 s duration, whatever the transition's length.
    static func springProgress(_ fraction: Double) -> Double {
        guard fraction < 1 else { return 1 }
        let omega = Double(555.027).squareRoot()
        let time = max(0, fraction) * 0.5
        return 1 - (1 + omega * time) * exp(-omega * time)
    }
}

// MARK: - StoryCubeFaceView

/// One poster's face of the cube (StoryContainerScreen.ItemSetView): full screen, turned about the cube's center, and
/// hidden from behind. Telegram's tint, black at 1, 0.8 and 0.5 alpha across the face and darkest on its far edge,
/// covers it as it turns away.
final class StoryCubeFaceView: UIView {
    let contentHost = UIView()

    private let tintView = StoryCubeTintView()

    var hasContent: Bool {
        !contentHost.subviews.isEmpty
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.isDoubleSided = false
        contentHost.layer.isDoubleSided = false
        addSubview(contentHost)
        addSubview(tintView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentHost.frame = bounds
        tintView.frame = bounds
    }

    /// Replaces what the face shows: a neighbouring poster's preview or the story left behind by a turn.
    func setContent(_ content: UIView?, frame: CGRect) {
        if let content, content.superview === contentHost, contentHost.subviews.count == 1 {
            content.frame = frame
            return
        }
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        guard let content else { return }
        content.frame = frame
        contentHost.addSubview(content)
    }

    func layoutContent(frame: CGRect) {
        contentHost.subviews.forEach { $0.frame = frame }
    }

    /// Places the face at `rotation`; Reduce Motion slides the faces side by side instead of turning them.
    func setRotation(_ rotation: CGFloat, sideAngle: CGFloat, reducesMotion: Bool) {
        let width = bounds.width
        if reducesMotion {
            transform3D = abs(rotation) > 0.0001
                ? CATransform3DMakeTranslation(rotation * width, 0, 0)
                : CATransform3DIdentity
            tintView.alpha = 0
            return
        }
        transform3D = StoryCubeGeometry.transform(rotation: rotation, sideAngle: sideAngle, width: width)
        if rotation != 0 { tintView.setDarkEdge(onLeft: rotation < 0) }
        tintView.alpha = StoryCubeGeometry.tintAlpha(rotation: rotation)
    }
}

// MARK: - StoryCubeTintView

private final class StoryCubeTintView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        layer.isDoubleSided = false
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.type = .axial
        gradient.colors = [
            UIColor.black.withAlphaComponent(1).cgColor,
            UIColor.black.withAlphaComponent(0.8).cgColor,
            UIColor.black.withAlphaComponent(0.5).cgColor,
        ]
        setDarkEdge(onLeft: true)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A face turning left darkens from its left edge; one turning right, from its right edge.
    func setDarkEdge(onLeft: Bool) {
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.startPoint = CGPoint(x: onLeft ? 0 : 1, y: 0)
        gradient.endPoint = CGPoint(x: onLeft ? 1 : 0, y: 0)
    }
}

// MARK: - StoryCubePreviewView

/// A neighbouring poster's story as its cube face shows it during a turn: the story's photo or video frame under the
/// header and progress strip, laid out like the viewer's own story.
final class StoryCubePreviewView: UIView {
    private struct Represented: Equatable {
        let neighbor: StoryViewerState.Neighbor
        let hasChat: Bool
        let storyDate: Int?
    }

    private let imageView = TDImageLoadingView()
    private let topShade = StoryShadeView(fromTop: true)
    private let progressStrip = StoryProgressStripView()
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeGlyph = UIImageView()
    private let moreGlyph = UIImageView()
    private var represented: Represented?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0.1, alpha: 1)
        clipsToBounds = true
        layer.cornerRadius = StoryChromeLayout.cornerRadius
        layer.cornerCurve = .continuous

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        addSubview(topShade)
        addSubview(progressStrip)

        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        avatarView.layer.cornerRadius = StoryChromeLayout.avatarFrame.height / 2
        avatarView.clipsToBounds = true
        addSubview(avatarView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .white
        addSubview(titleLabel)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        addSubview(subtitleLabel)

        closeGlyph.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        )
        closeGlyph.tintColor = .white
        closeGlyph.contentMode = .center
        addSubview(closeGlyph)

        moreGlyph.image = StoryChromeLayout.moreImage
        moreGlyph.tintColor = .white
        moreGlyph.contentMode = .center
        moreGlyph.isHidden = true
        addSubview(moreGlyph)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        topShade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 96)
        progressStrip.frame = StoryChromeLayout.progressFrame(in: bounds)
        avatarView.frame = StoryChromeLayout.avatarFrame
        closeGlyph.frame = StoryChromeLayout.closeFrame(in: bounds)
        moreGlyph.frame = StoryChromeLayout.moreFrame(in: bounds)
        let text = StoryChromeLayout.textFrames(
            in: bounds,
            trailingLimit: StoryChromeLayout.textTrailingLimit(in: bounds, showsMore: !moreGlyph.isHidden),
        )
        titleLabel.frame = text.title
        subtitleLabel.frame = text.subtitle
    }

    /// Shows `neighbor`'s story from what the viewer's session has cached; a later call with more of it loaded fills
    /// the rest in.
    func configure(
        neighbor: StoryViewerState.Neighbor,
        chat: Chat?,
        story: Story?,
        accountUserID: Int64?,
        client: TDLibClient,
    ) {
        let next = Represented(neighbor: neighbor, hasChat: chat != nil, storyDate: story?.date)
        guard next != represented else { return }
        let previous = represented
        represented = next
        progressStrip.configure(count: neighbor.storyCount, index: neighbor.storyIndex)
        if let chat {
            titleLabel.text = chat.title
            avatarView.configure(
                file: chat.photo?.small,
                minithumbnail: chat.photo?.minithumbnail,
                placeholder: TelegramAvatarPlaceholder(
                    peerID: chat.id,
                    accentColorID: chat.accentColorId,
                    upgradedGiftColors: chat.upgradedGiftColors,
                    letters: chat.title.telegramAvatarFirstLetter.map { [$0] } ?? [],
                    isDeleted: false,
                ),
                client: client,
            )
        } else {
            titleLabel.text = nil
            avatarView.prepareForReuse()
        }
        subtitleLabel.text = story.map { StoryTimestamp.string(date: $0.date) }
        moreGlyph.isHidden = !StoryMoreMenu.showsButton(for: story, accountUserID: accountUserID)
        setNeedsLayout()
        guard previous?.neighbor != neighbor || previous?.storyDate != story?.date else { return }
        loadMedia(of: story, client: client)
    }

    private func loadMedia(of story: Story?, client: TDLibClient) {
        let origin = TDImageOrigin.captured(client: client)
        switch story?.content {
        case .storyContentPhoto(let content):
            if let file = StoryMedia.photoFile(content.photo) {
                // The viewer loads the same file at the same size, so its image is cached once the cube turns.
                imageView.load(
                    file: file,
                    placeholderData: content.photo.minithumbnail?.data,
                    maximumPixelSize: 2560,
                    origin: origin,
                )
            } else {
                imageView.loadPlaceholder(data: content.photo.minithumbnail?.data, origin: origin)
            }
        case .storyContentVideo(let content):
            if let thumbnail = content.video.thumbnail {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: content.video.minithumbnail?.data,
                    maximumPixelSize: 1280,
                    origin: origin,
                )
            } else {
                imageView.loadPlaceholder(
                    data: content.video.minithumbnail?.data,
                    maximumPixelSize: 1280,
                    origin: origin,
                )
            }
        case nil,
             .storyContentLive,
             .storyContentUnsupported:
            imageView.cancel()
            imageView.image = nil
        }
    }
}
