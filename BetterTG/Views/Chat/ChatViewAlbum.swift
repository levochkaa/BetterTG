// ChatViewAlbum.swift

import AVKit
import Combine
import ImageIO
import Photos
import TDLibKitDynamic
import UIKit
import UniformTypeIdentifiers

// MARK: - GalleryPlaybackCommand

enum GalleryPlaybackCommand: Equatable {
    case jump(TimeInterval)
    case togglePictureInPicture
    case togglePlayback
}

// MARK: - VideoPlaybackAttachmentContext

enum VideoPlaybackAttachmentContext: Equatable {
    case fullscreen
    case inline
}

// MARK: - GalleryPictureInPictureSourceKind

enum GalleryPictureInPictureSourceKind: Equatable {
    case playerLayer
    case sampleBufferDisplayLayer
}

// MARK: - GalleryPictureInPictureSourceIdentity

struct GalleryPictureInPictureSourceIdentity: Equatable {
    let kind: GalleryPictureInPictureSourceKind
    let layerIdentifier: ObjectIdentifier
}

// MARK: - VideoPlaybackAttachmentToken

struct VideoPlaybackAttachmentToken: Hashable {
    fileprivate let id = UUID()
}

// MARK: - MediaGalleryTransitionTarget

@MainActor final class MediaGalleryTransitionTarget {
    let messageID: Int64
    let frameInWindow: CGRect
    let cornerRadius: CGFloat
    let maskedCorners: CACornerMask
    let snapshotView: UIView?

    private weak var sourceView: UIView?
    private weak var coordinateWindow: UIWindow?
    private let validation: () -> Bool

    var validatedSourceView: UIView? {
        validation() ? sourceView : nil
    }

    init?(
        messageID: Int64,
        sourceView: UIView,
        capturesSnapshot: Bool = true,
        snapshotFactory: (() -> UIView?)? = nil,
        validation: @escaping () -> Bool = { true },
    ) {
        sourceView.layoutIfNeeded()
        guard let window = sourceView.window else { return nil }
        let fullFrameInWindow = sourceView.convert(sourceView.bounds, to: window)
        var frameInWindow = fullFrameInWindow
        var ancestor = sourceView.superview
        while let current = ancestor {
            if current.clipsToBounds {
                frameInWindow = frameInWindow.intersection(current.convert(current.bounds, to: window))
            }
            ancestor = current.superview
        }
        frameInWindow = frameInWindow.intersection(window.bounds)
        guard frameInWindow.width > 0, frameInWindow.height > 0 else { return nil }
        self.messageID = messageID
        self.sourceView = sourceView
        self.coordinateWindow = window
        self.frameInWindow = frameInWindow
        self.cornerRadius = sourceView.layer.cornerRadius
        self.maskedCorners = sourceView.layer.maskedCorners
        self.validation = validation
        if capturesSnapshot {
            let cropRect = sourceView.convert(frameInWindow, from: window).intersection(sourceView.bounds)
            if let customSnapshot = snapshotFactory?() {
                customSnapshot.frame = sourceView.bounds
                customSnapshot.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: cropRect.size).image { context in
                    context.cgContext.translateBy(x: -cropRect.minX, y: -cropRect.minY)
                    customSnapshot.layer.render(in: context.cgContext)
                }
                let imageView = UIImageView(image: image)
                imageView.contentMode = .scaleToFill
                imageView.clipsToBounds = true
                self.snapshotView = imageView
            } else {
                self.snapshotView = sourceView.resizableSnapshotView(
                    from: cropRect,
                    afterScreenUpdates: false,
                    withCapInsets: .zero,
                )
                    ?? sourceView.snapshotView(afterScreenUpdates: false)
            }
        } else {
            self.snapshotView = nil
        }
    }

    func frame(in coordinateSpace: UIView) -> CGRect? {
        guard let coordinateWindow else { return nil }
        return coordinateSpace.convert(frameInWindow, from: coordinateWindow)
    }
}

#if DEBUG
    extension MediaGalleryTransitionTarget {
        static func runDebugProbeIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-gallery-transition") else { return }
            let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            root.isHidden = true
            window.addSubview(root)
            defer { root.removeFromSuperview() }
            let clip = UIView(frame: CGRect(x: 20, y: 100, width: 300, height: 160))
            clip.clipsToBounds = true
            let source = UIView(frame: CGRect(x: -20, y: 10, width: 280, height: 180))
            source.backgroundColor = .systemBlue
            source.layer.cornerRadius = 13
            source.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            root.addSubview(clip)
            clip.addSubview(source)
            window.layoutIfNeeded()
            root.layoutIfNeeded()
            var generationIsValid = true
            let initial = MediaGalleryTransitionTarget(
                messageID: 7,
                sourceView: source,
                capturesSnapshot: false,
                validation: { generationIsValid },
            )
            let expectedInitialFrame = CGRect(x: 20, y: 110, width: 260, height: 150)
            let exactSource = initial?.frameInWindow.equalTo(expectedInitialFrame) == true
            let clippedSource = initial?.frameInWindow != source.convert(source.bounds, to: nil)
                && initial?.maskedCorners == source.layer.maskedCorners
            let destination = AVMakeRect(
                aspectRatio: CGSize(width: 16, height: 9),
                insideRect: CGRect(x: 0, y: 0, width: 390, height: 700),
            )
            let aspectFitDestination = abs(destination.width - 390) < 0.01
                && abs(destination.height - 219.375) < 0.01
                && abs(destination.minY - 240.3125) < 0.01
            let snapshotBeforeHide = !source.isHidden
            let rasterized = MediaGalleryTransitionTarget(
                messageID: 8,
                sourceView: source,
                snapshotFactory: {
                    let content = UIView(frame: source.bounds)
                    content.backgroundColor = .systemGreen
                    return content
                },
            )?.snapshotView is UIImageView
            source.frame.origin.x = 15
            let fresh = MediaGalleryTransitionTarget(
                messageID: 7,
                sourceView: source,
                capturesSnapshot: false,
            )
            let freshDismissTarget = fresh?.frameInWindow != initial?.frameInWindow
            generationIsValid = false
            let staleSourceRejected = initial?.validatedSourceView == nil
            let albumProof = AlbumMediaView.runDebugTransitionProbe(in: root)

            var cancelCommitCount = 0
            var cancelCleanupCount = 0
            let cancelGate = MediaGalleryTransitionCompletionGate()
            cancelGate.finish(
                completed: false,
                commit: { cancelCommitCount += 1 },
                cleanup: { cancelCleanupCount += 1 },
            )
            cancelGate.finish(
                completed: true,
                commit: { cancelCommitCount += 1 },
                cleanup: { cancelCleanupCount += 1 },
            )
            let cancelSkipsCommit = cancelCommitCount == 0 && cancelCleanupCount == 1
            var completedCommitCount = 0
            var completedCleanupCount = 0
            let completedGate = MediaGalleryTransitionCompletionGate()
            completedGate.finish(
                completed: true,
                commit: { completedCommitCount += 1 },
                cleanup: { completedCleanupCount += 1 },
            )
            completedGate.finish(
                completed: true,
                commit: { completedCommitCount += 1 },
                cleanup: { completedCleanupCount += 1 },
            )
            let completionOnce = completedCommitCount == 1 && completedCleanupCount == 1
            let passed = exactSource
                && clippedSource
                && aspectFitDestination
                && snapshotBeforeHide
                && rasterized
                && freshDismissTarget
                && staleSourceRejected
                && albumProof.exactSource
                && albumProof.singleCandidate
                && cancelSkipsCommit
                && completionOnce
            let result = "Gallery transition probe: exact-source=\(exactSource), clipped-source=\(clippedSource), "
                + "aspect-fit-destination=\(aspectFitDestination), snapshot-before-hide=\(snapshotBeforeHide), "
                + "rasterized-snapshot=\(rasterized), "
                + "fresh-dismiss-target=\(freshDismissTarget), stale-source-rejected=\(staleSourceRejected), "
                + "album-tile-source=\(albumProof.exactSource), "
                + "album-single-candidate=\(albumProof.singleCandidate), "
                + "cancel-skips-commit=\(cancelSkipsCommit), completion-once=\(completionOnce), "
                + "initial-frame=\(String(describing: initial?.frameInWindow)), "
                + "fresh-frame=\(String(describing: fresh?.frameInWindow))"
            if !passed {
                assertionFailure(result)
            }
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documentsURL.appendingPathComponent("gallery-transition-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }
#endif

// MARK: - GalleryCaptionTextView

private final class GalleryCaptionTextView: UITextView, UITextViewDelegate {
    private struct EntityAction {
        let accessibilityLabel: String
        let range: NSRange
        let requiresConfirmation: Bool
        let url: URL
    }

    override var canBecomeFirstResponder: Bool { false }

    var onBackgroundTap: (() -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var onOpenURL: ((URL, Bool) -> Void)?
    var onRevealSpoilers: (() -> Void)?

    private var entityActions = [EntityAction]()
    private var spoilerRanges = [NSRange]()
    private var spoilersAreRevealed = false
    private var representedMessageID: Int64?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = .clear
        delegate = self
        isEditable = false
        isSelectable = false
        isScrollEnabled = true
        alwaysBounceVertical = false
        showsVerticalScrollIndicator = true
        scrollsToTop = false
        textContainerInset = .zero
        self.textContainer.lineFragmentPadding = 0
        self.textContainer.lineBreakMode = .byWordWrapping
        adjustsFontForContentSizeCategory = true
        accessibilityTraits = .staticText
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(captionTapped(_:))))
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func entityAction(_ entity: TextEntity, text: String) -> (URL, String, Bool)? {
        let range = NSRange(location: entity.offset, length: entity.length)
        guard let stringRange = Range(range, in: text) else { return nil }
        let raw = String(text[stringRange])
        switch entity.type {
        case .textEntityTypeEmailAddress:
            return URL(string: "mailto://\(raw)").map { ($0, "Email \(raw)", false) }
        case .textEntityTypeMention:
            return getUrl(from: "t.me/\(raw.trimmingCharacters(in: CharacterSet(charactersIn: "@")))")
                .map { ($0, "Open \(raw)", false) }
        case .textEntityTypePhoneNumber:
            return URL(string: "tel://\(raw)").map { ($0, "Call \(raw)", false) }
        case .textEntityTypeTextUrl(let textURL):
            guard let url = getUrl(from: textURL.url) else { return nil }
            let displayedURL = getUrl(from: raw)
            let matchesDisplayedDestination = displayedURL.map(Self.normalizedURLString) == Self
                .normalizedURLString(url)
            return (url, "Open link to \(url.host ?? url.absoluteString)", !matchesDisplayedDestination)
        case .textEntityTypeUrl:
            return getUrl(from: raw).map { ($0, "Open link \(raw)", false) }
        default:
            return nil
        }
    }

    private static func normalizedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80)
        {
            components.port = nil
        }
        if components.host != nil, components.percentEncodedPath.isEmpty {
            components.percentEncodedPath = "/"
        }
        return components.string ?? url.absoluteString
    }

    private static func accessibilityText(
        _ formattedText: FormattedText,
        spoilerRanges: [NSRange],
        revealed: Bool,
    ) -> String {
        guard !revealed, !spoilerRanges.isEmpty else { return formattedText.text }
        let redacted = NSMutableString(string: formattedText.text)
        for range in spoilerRanges.sorted(by: { $0.location > $1.location }) {
            redacted.replaceCharacters(in: range, with: "Spoiler")
        }
        return String(redacted)
    }

    func configure(messageID: Int64, formattedText: FormattedText, spoilersRevealed: Bool) {
        let resetsScrollPosition = representedMessageID != messageID
        representedMessageID = messageID
        spoilersAreRevealed = spoilersRevealed
        let caption = NSMutableAttributedString(
            attributedString: NSAttributedString(getAttributedString(from: formattedText, .white)),
        )
        let fontMetrics = UIFontMetrics(forTextStyle: .body)
        caption.enumerateAttribute(.font, in: NSRange(location: 0, length: caption.length)) { value, range, _ in
            guard let font = value as? UIFont else { return }
            caption.addAttribute(.font, value: fontMetrics.scaledFont(for: font), range: range)
        }
        spoilerRanges = formattedText.entities.compactMap { entity -> NSRange? in
            guard case .textEntityTypeSpoiler = entity.type else { return nil }
            let range = NSRange(location: entity.offset, length: entity.length)
            return NSMaxRange(range) <= caption.length ? range : nil
        }
        let spoilerColor = UIColor.systemGray
        for range in spoilerRanges {
            caption.addAttributes(
                spoilersRevealed
                    ? [.backgroundColor: UIColor.clear, .foregroundColor: UIColor.white]
                    : [.backgroundColor: spoilerColor, .foregroundColor: spoilerColor],
                range: range,
            )
        }
        entityActions = formattedText.entities.compactMap { entity in
            let range = NSRange(location: entity.offset, length: entity.length)
            guard NSMaxRange(range) <= caption.length,
                  let action = Self.entityAction(entity, text: formattedText.text)
            else { return nil }
            return EntityAction(
                accessibilityLabel: action.1,
                range: range,
                requiresConfirmation: action.2,
                url: action.0,
            )
        }
        attributedText = caption
        accessibilityLabel = "Caption, \(Self.accessibilityText(formattedText, spoilerRanges: spoilerRanges, revealed: spoilersRevealed))"
        var customActions = [UIAccessibilityCustomAction]()
        if !spoilersRevealed, !spoilerRanges.isEmpty {
            customActions.append(UIAccessibilityCustomAction(
                name: "Reveal spoiler",
                target: self,
                selector: #selector(revealSpoilers),
            ))
        }
        for action in entityActions where spoilersRevealed || !spoilerRanges.contains(where: {
            NSIntersectionRange($0, action.range).length > 0
        }) {
            customActions.append(UIAccessibilityCustomAction(name: action.accessibilityLabel) { [weak self] _ in
                guard let self else { return false }
                onOpenURL?(action.url, action.requiresConfirmation)
                return true
            })
        }
        accessibilityCustomActions = customActions.isEmpty ? nil : customActions
        if resetsScrollPosition {
            setContentOffset(.zero, animated: false)
            onInteractionChanged?(false)
        }
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        onInteractionChanged?(true)
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            onInteractionChanged?(contentOffset.y > 1)
        }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        onInteractionChanged?(contentOffset.y > 1)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.selectedTextRange = nil
    }

    @objc private func revealSpoilers() -> Bool {
        guard !spoilersAreRevealed, !spoilerRanges.isEmpty else { return false }
        onRevealSpoilers?()
        return true
    }

    @objc private func captionTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended,
              let characterIndex = characterIndex(at: gesture.location(in: self))
        else {
            onBackgroundTap?()
            return
        }
        if !spoilersAreRevealed,
           spoilerRanges.contains(where: { NSLocationInRange(characterIndex, $0) })
        {
            _ = revealSpoilers()
            return
        }
        if let action = entityActions.first(where: { NSLocationInRange(characterIndex, $0.range) }) {
            onOpenURL?(action.url, action.requiresConfirmation)
            return
        }
        onBackgroundTap?()
    }

    private func characterIndex(at location: CGPoint) -> Int? {
        var point = CGPoint(
            x: location.x - textContainerInset.left + contentOffset.x,
            y: location.y - textContainerInset.top + contentOffset.y,
        )
        point.x -= textContainer.lineFragmentPadding
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer,
        )
        guard glyphRect.insetBy(dx: -3, dy: -3).contains(point) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

// MARK: - MediaGalleryTopicIdentity

private enum MediaGalleryTopicIdentity: Equatable {
    case directMessages(Int64)
    case forum(Int)
    case savedMessages(Int64)
    case thread(Int64)

    init(_ topic: MessageTopic) {
        self =
            switch topic {
            case .messageTopicDirectMessages(let topic):
                .directMessages(topic.directMessagesChatTopicId)
            case .messageTopicForum(let topic):
                .forum(topic.forumTopicId)
            case .messageTopicSavedMessages(let topic):
                .savedMessages(topic.savedMessagesTopicId)
            case .messageTopicThread(let topic):
                .thread(topic.messageThreadId)
            }
    }
}

// MARK: - MediaGalleryMessageIdentity

private struct MediaGalleryMessageIdentity: Equatable {
    let chatID: Int64
    let messageID: Int64
    let topic: MediaGalleryTopicIdentity?

    init(_ message: Message) {
        self.chatID = message.chatId
        self.messageID = message.id
        self.topic = message.topicId.map(MediaGalleryTopicIdentity.init)
    }
}

// MARK: - MediaGalleryOpenInChatError

private enum MediaGalleryOpenInChatError: LocalizedError {
    case contextChanged
    case messageUnavailable

    var errorDescription: String? {
        switch self {
        case .contextChanged:
            "The active Telegram account changed."
        case .messageUnavailable:
            "This message is no longer available in the original chat."
        }
    }
}

// MARK: - MediaGallerySaveKind

private enum MediaGallerySaveKind: Equatable {
    case photo
    case video
}

// MARK: - MediaGalleryExportAction

private enum MediaGalleryExportAction: Equatable {
    case saveToPhotos
    case share
}

// MARK: - MediaGalleryActionButton

private enum MediaGalleryActionButton: Equatable {
    case more
    case share
}

// MARK: - MediaGalleryExportAsset

private struct MediaGalleryExportAsset {
    let completedLocalPath: String?
    let creationDate: Foundation.Date
    let fileID: Int
    let isLivePhoto: Bool
    let isSecretMedia: Bool
    let mimeType: String
    let originalFilename: String
    let photosKind: MediaGallerySaveKind?
    let requiresWebPStillConversion: Bool
    let saveActionTitle: String?
    let saveSuccessText: String?
    let shareFileExtension: String?

    init?(_ message: Message) {
        let file: File
        switch message.content {
        case .messageAnimation(let content):
            file = content.animation.animation
            self.isLivePhoto = false
            self.isSecretMedia = content.isSecret
            self.mimeType = content.animation.mimeType.lowercased()
            let filename = URL(filePath: content.animation.fileName).lastPathComponent
            let fallbackExtension = mimeType == "image/gif" ? "gif" : "mp4"
            self.originalFilename = filename.isEmpty
                ? "bettertg-animation-\(message.id).\(fallbackExtension)"
                : filename
            switch mimeType {
            case "image/gif":
                self.shareFileExtension = "gif"
                self.photosKind = .photo
                self.saveActionTitle = "Save GIF"
                self.saveSuccessText = "GIF saved"
            case "video/mp4":
                self.shareFileExtension = "mp4"
                self.photosKind = .video
                self.saveActionTitle = "Save Animation"
                self.saveSuccessText = "Animation saved"
            default:
                self.shareFileExtension = nil
                self.photosKind = nil
                self.saveActionTitle = nil
                self.saveSuccessText = nil
            }
            self.requiresWebPStillConversion = false
        case .messagePhoto(let content):
            guard let size = content.photo.sizes.max(by: { lhs, rhs in
                let lhsPixels = Int64(lhs.width) * Int64(lhs.height)
                let rhsPixels = Int64(rhs.width) * Int64(rhs.height)
                if lhsPixels == rhsPixels {
                    return max(lhs.photo.size, lhs.photo.expectedSize) < max(rhs.photo.size, rhs.photo.expectedSize)
                }
                return lhsPixels < rhsPixels
            }) else { return nil }
            file = size.photo
            self.isLivePhoto = content.video != nil
            self.isSecretMedia = content.isSecret
            self.mimeType = "image/jpeg"
            self.originalFilename = "bettertg-photo-\(message.id).jpg"
            self.photosKind = .photo
            self.requiresWebPStillConversion = false
            self.saveActionTitle = content.video == nil ? "Save Photo" : "Save Still Photo"
            self.saveSuccessText = content.video == nil ? "Photo saved" : "Still photo saved"
            self.shareFileExtension = nil
        case .messageSticker(let content):
            file = content.sticker.sticker
            self.isLivePhoto = false
            self.isSecretMedia = false
            let fileExtension: String
            switch content.sticker.format {
            case .stickerFormatTgs:
                fileExtension = "tgs"
                self.shareFileExtension = "tgs"
                self.mimeType = "application/x-tgsticker"
                self.photosKind = nil
                self.requiresWebPStillConversion = false
                self.saveActionTitle = nil
                self.saveSuccessText = nil
            case .stickerFormatWebm:
                fileExtension = "webm"
                self.shareFileExtension = "webm"
                self.mimeType = "video/webm"
                self.photosKind = nil
                self.requiresWebPStillConversion = false
                self.saveActionTitle = nil
                self.saveSuccessText = nil
            case .stickerFormatWebp:
                fileExtension = "webp"
                self.shareFileExtension = "webp"
                self.mimeType = "image/webp"
                self.photosKind = .photo
                self.requiresWebPStillConversion = true
                self.saveActionTitle = "Save Sticker Frame"
                self.saveSuccessText = "Sticker frame saved"
            }
            self.originalFilename = "bettertg-sticker-\(message.id).\(fileExtension)"
        case .messageVideo(let content):
            file = content.video.video
            self.isLivePhoto = false
            self.isSecretMedia = content.isSecret
            self.mimeType = content.video.mimeType.lowercased()
            let filename = URL(filePath: content.video.fileName).lastPathComponent
            self.originalFilename = filename.isEmpty ? "bettertg-video-\(message.id).mp4" : filename
            self.photosKind = .video
            self.requiresWebPStillConversion = false
            self.saveActionTitle = "Save Video"
            self.saveSuccessText = "Video saved"
            switch mimeType {
            case "video/mp4": self.shareFileExtension = "mp4"
            case "video/quicktime": self.shareFileExtension = "mov"
            case "video/webm": self.shareFileExtension = "webm"
            case "video/x-m4v": self.shareFileExtension = "m4v"
            default: self.shareFileExtension = nil
            }
        default:
            return nil
        }
        self.fileID = file.id
        self.completedLocalPath = file.local.isDownloadingCompleted && !file.local.path.isEmpty
            ? file.local.path
            : nil
        self.creationDate = Foundation.Date(timeIntervalSince1970: TimeInterval(message.date))
    }
}

// MARK: - MediaGallerySaveError

private enum MediaGallerySaveError: LocalizedError {
    case contextChanged
    case downloadFailed
    case messageUnavailable
    case photosAccessDenied
    case protectedContent
    case unsupportedVideo

    var errorDescription: String? {
        switch self {
        case .contextChanged:
            "The active Telegram account or selected item changed."
        case .downloadFailed:
            "The original media couldn't be downloaded."
        case .messageUnavailable:
            "This media is no longer available in the original chat."
        case .photosAccessDenied:
            "Allow BetterTG to add media to Photos in Settings."
        case .protectedContent:
            "Telegram doesn't allow this media to be exported."
        case .unsupportedVideo:
            "This video format can't be added to Photos."
        }
    }

    var shouldOfferSettings: Bool {
        if case .photosAccessDenied = self {
            true
        } else {
            false
        }
    }
}

// MARK: - MediaGalleryDeleteError

private enum MediaGalleryDeleteError: LocalizedError {
    case accountChanged
    case noPermission
    case notConfirmed
    case unavailable

    var errorDescription: String? {
        switch self {
        case .accountChanged:
            "The active Telegram account or selected item changed."
        case .noPermission:
            "These messages can no longer be deleted together."
        case .notConfirmed:
            "Telegram didn't confirm deletion. Check whether the media remains before trying again."
        case .unavailable:
            "The selected media is no longer available in the original chat."
        }
    }
}

// MARK: - MediaGalleryDeleteCapabilities

private struct MediaGalleryDeleteCapabilities {
    let canDeleteForAllUsers: Bool
    let canDeleteOnlyForSelf: Bool
}

// MARK: - MediaGalleryTemporaryFileLease

private final class MediaGalleryTemporaryFileLease: @unchecked Sendable {
    let fileURL: URL

    private let directoryURL: URL
    private let lock = NSLock()
    private var cleanedUp = false

    init(directoryURL: URL, fileURL: URL) {
        self.directoryURL = directoryURL
        self.fileURL = fileURL
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        lock.lock()
        guard !cleanedUp else {
            lock.unlock()
            return
        }
        cleanedUp = true
        lock.unlock()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

// MARK: - MediaGalleryViewController

final class MediaGalleryViewController: UIViewController, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    override var canBecomeFirstResponder: Bool {
        true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        !chromeIsVisible
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            makeKeyCommand(
                input: " ",
                modifierFlags: [],
                action: #selector(toggleSelectedPlayback),
                discoverabilityTitle: "Play or Pause",
            ),
            makeKeyCommand(
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [.shift],
                action: #selector(jumpSelectedPlaybackBackward),
                discoverabilityTitle: "Back 5 Seconds",
            ),
            makeKeyCommand(
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [.shift],
                action: #selector(jumpSelectedPlaybackForward),
                discoverabilityTitle: "Forward 5 Seconds",
            ),
            makeKeyCommand(
                input: "p",
                modifierFlags: [.command],
                action: #selector(toggleSelectedPictureInPicture),
                discoverabilityTitle: "Picture in Picture",
            ),
        ]
    }

    var onRequestMoreMessages: (() -> Void)?
    var contextIsCurrent: (() -> Bool)?
    var onOpenMessageID: ((Int64) -> Void)? {
        didSet {
            if isViewLoaded {
                updateMoreMenu()
            }
        }
    }

    fileprivate let transitionSource: MediaGalleryTransitionTarget?
    fileprivate let transitionSourceProvider: ((Int64) -> MediaGalleryTransitionTarget?)?

    private var messages: [Message]
    private var totalMessageCount: Int?
    private let tdlib: TDLib
    private let actionAccountID: UUID?
    private let actionClient: TDLibClient?
    private let actionChatID: Int64?
    private let actionClientID: Int32?
    private let actionSourceLocation: ChatLocation?
    private let requiredActionTopic: MediaGalleryTopicIdentity?
    private let actionRequiresTopicMatch: Bool
    private var selectedIndex: Int
    private var didSetInitialPosition = false
    private var videoPlaybackOwners = [Int64: GalleryVideoPlaybackOwner]()
    private var mediaTransitionController: MediaGalleryTransitionController?
    private var shouldReleasePlaybackOwnersAfterDisappearance = false
    private var didReleasePlaybackOwners = false
    private var paginationRequestedMessageCount: Int?
    private var messageUpdateInProgress = false
    private var pendingMessageUpdate: [Message]?
    private var pendingDeletedPlaybackOwners = [Int64: GalleryVideoPlaybackOwner]()
    private var pendingDeletedMessageIDsByChat = [Int64: Set<Int64>]()
    private var contextWasInvalidated = false
    private var contextInvalidationCompletion: (() -> Void)?
    private var forcedDismissalSnapshot: UIView?
    private var forcesFadeDismissal = false
    private var chromeIsVisible = true
    private var interactiveDismissalProgress = CGFloat.zero
    private var interactiveDismissalChromeWasVisible = true
    private var revealedCaptionSpoilerMessageIDs = Set<Int64>()
    private var captionInteractionIsActive = false
    private let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let captionView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let captionTextView = GalleryCaptionTextView()
    private var captionHeightConstraint: NSLayoutConstraint!
    private let closeButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let moreActivityIndicator = UIActivityIndicatorView(style: .medium)
    private let shareButton = UIButton(type: .system)
    private let shareActivityIndicator = UIActivityIndicatorView(style: .medium)
    private let counterLabel = UILabel()
    private var activeShareLease: MediaGalleryTemporaryFileLease?
    private var actionStatusText: String?
    private var deleteTask: Task<Void, Never>?
    private var deleteGeneration: UUID?
    private var exportTask: Task<Void, Never>?
    private var exportGeneration: UUID?
    private var forwardTask: Task<Void, Never>?
    private var forwardGeneration: UUID?
    private var openInChatTask: Task<Void, Never>?
    private var openInChatDismissalGeneration: UUID?
    private var openInChatGeneration: UUID?
    private var statusResetTask: Task<Void, Never>?
    private var deleteMessagesCancellable: AnyCancellable?
    private var voiceOverCancellable: AnyCancellable?
    private var contentSizeCancellable: AnyCancellable?
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var chromeTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(toggleChromeVisibility))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var interactiveDismissPanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleInteractiveDismissPan(_:)))
        gesture.maximumNumberOfTouches = 1
        gesture.cancelsTouchesInView = true
        gesture.delegate = self
        return gesture
    }()

    fileprivate var selectedMessageID: Int64? {
        messages.indices.contains(selectedIndex) ? messages[selectedIndex].id : nil
    }

    fileprivate var isSelectedPictureInPictureRetained: Bool {
        guard let selectedMessageID,
              let owner = videoPlaybackOwners[selectedMessageID]
        else { return false }
        return owner.isPictureInPictureRetained
    }

    private var hasCurrentContext: Bool {
        !contextWasInvalidated && (contextIsCurrent?() ?? true)
    }

    private var canBeginInteractiveDismissal: Bool {
        guard hasCurrentContext,
              !didReleasePlaybackOwners,
              openInChatTask == nil,
              deleteTask == nil,
              exportTask == nil,
              forwardTask == nil,
              !isBeingDismissed,
              presentedViewController == nil,
              transitionCoordinator == nil,
              mediaTransitionController?.isInteractiveDismissalInProgress != true,
              !messageUpdateInProgress,
              !captionInteractionIsActive,
              !isSelectedPictureInPictureRetained,
              messages.indices.contains(selectedIndex),
              collectionView.bounds.width > 0
        else { return false }
        let expectedOffset = CGFloat(selectedIndex) * collectionView.bounds.width
        return abs(collectionView.contentOffset.x - expectedOffset) < 2
    }

    init(
        messages: [Message],
        selection: Int64,
        totalMessageCount: Int? = nil,
        tdlib: TDLib = .shared,
        actionClient: TDLibClient? = nil,
        sourceLocation: ChatLocation? = nil,
        transferredPlaybackOwner: GalleryVideoPlaybackOwner? = nil,
        transferredPlaybackOwners: [GalleryVideoPlaybackOwner] = [],
        transitionSource: MediaGalleryTransitionTarget? = nil,
        transitionSourceProvider: ((Int64) -> MediaGalleryTransitionTarget?)? = nil,
    ) {
        self.tdlib = tdlib
        self.actionAccountID = sourceLocation?.accountID
        self.actionClient = actionClient
        self.actionChatID = sourceLocation?.chatID
        self.actionClientID = sourceLocation?.clientID
        self.actionSourceLocation = sourceLocation
        self.requiredActionTopic = sourceLocation?.topic.map(MediaGalleryTopicIdentity.init)
        self.actionRequiresTopicMatch = sourceLocation?.topic != nil
        self.transitionSource = transitionSource
        self.transitionSourceProvider = transitionSourceProvider
        let galleryMessages = messages.filter { message in
            switch message.content {
            case .messageAnimation, .messagePhoto, .messageSticker, .messageVideo:
                true
            default:
                false
            }
        }
        self.messages = galleryMessages
        self.totalMessageCount = totalMessageCount.map { max($0, galleryMessages.count) }
        self.selectedIndex = galleryMessages.firstIndex(where: { $0.id == selection }) ?? 0
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalPresentationCapturesStatusBarAppearance = true
        let transitionController = MediaGalleryTransitionController()
        self.mediaTransitionController = transitionController
        transitioningDelegate = transitionController
        let transferredOwners = transferredPlaybackOwners + [transferredPlaybackOwner].compactMap(\.self)
        for owner in transferredOwners where owner.tdlib === tdlib {
            guard self.messages.contains(where: { $0.id == owner.messageID }) else { continue }
            videoPlaybackOwners[owner.messageID] = owner
            owner.galleryController = self
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        openInChatTask?.cancel()
        exportTask?.cancel()
        deleteTask?.cancel()
        forwardTask?.cancel()
        statusResetTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityViewIsModal = true
        configureCollectionView()
        configureToolbar()
        configureCaption()
        observePermanentMessageDeletes()
        observeVoiceOver()
        observeContentSizeCategory()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
           layout.itemSize != collectionView.bounds.size
        {
            layout.itemSize = collectionView.bounds.size
            layout.invalidateLayout()
        }
        updateCaptionHeight()
        guard !didSetInitialPosition, messages.indices.contains(selectedIndex) else { return }
        didSetInitialPosition = true
        collectionView.scrollToItem(
            at: IndexPath(item: selectedIndex, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        updateCounter()
        prunePlaybackOwners(around: selectedIndex)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        if messages.indices.contains(selectedIndex) {
            collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
                .flatMap { $0 as? MediaGalleryCell }?
                .setPlaybackVisible(shouldPlayItem(at: selectedIndex))
        }
        bindSelectedCellChrome()
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            cancelExport()
            cancelForward()
            cancelDelete()
            if openInChatDismissalGeneration == nil {
                cancelOpenInChat()
            }
            shouldReleasePlaybackOwnersAfterDisappearance = true
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if shouldReleasePlaybackOwnersAfterDisappearance {
            releasePlaybackOwnersForDismissal()
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator,
    ) {
        let selectedMessageID = selectedMessageID
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self,
                  let selectedMessageID,
                  let selectedIndex = messages.firstIndex(where: { $0.id == selectedMessageID })
            else { return }
            self.selectedIndex = selectedIndex
            view.layoutIfNeeded()
            collectionView.scrollToItem(
                at: IndexPath(item: selectedIndex, section: 0),
                at: .centeredHorizontally,
                animated: false,
            )
            collectionView.layoutIfNeeded()
            updateCounter()
            bindSelectedCellChrome()
            prunePlaybackOwners(around: selectedIndex)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateSelection(from: scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateSelection(from: scrollView)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateSelection(from: scrollView)
    }

    func collectionView(
        _: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath,
    ) {
        let cell = cell as? MediaGalleryCell
        cell?.setPlaybackVisible(shouldPlayItem(at: indexPath.item))
        if indexPath.item == selectedIndex {
            bindGalleryChrome(to: cell)
        }
        requestMoreMessagesIfNeeded(near: indexPath.item)
    }

    func collectionView(
        _: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath,
    ) {
        let cell = cell as? MediaGalleryCell
        if indexPath.item == selectedIndex, captionInteractionIsActive {
            captionInteractionIsActive = false
            cell?.setGalleryChromeInteractionActive(false)
        }
        cell?.unbindGalleryChrome()
        cell?.setPlaybackVisible(false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let view = touchedView {
            if view is UIControl {
                return false
            }
            if view === collectionView {
                break
            }
            touchedView = view.superview
        }
        if gestureRecognizer === interactiveDismissPanGesture {
            guard !UIAccessibility.isVoiceOverRunning,
                  let cell = visibleSelectedGalleryCell()
            else { return false }
            return cell.canBeginInteractiveDismissal(at: touch.location(in: cell.contentView))
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactiveDismissPanGesture else { return true }
        let velocity = interactiveDismissPanGesture.velocity(in: view)
        guard velocity.y > 0,
              abs(velocity.y) > abs(velocity.x) * 1.2,
              canBeginInteractiveDismissal,
              let cell = visibleSelectedGalleryCell()
        else { return false }
        return cell.canBeginInteractiveDismissal(
            at: interactiveDismissPanGesture.location(in: cell.contentView),
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        guard gestureRecognizer === chromeTapGesture,
              let otherTap = otherGestureRecognizer as? UITapGestureRecognizer
        else { return false }
        return otherTap.numberOfTapsRequired > 1
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        let otherGesture = gestureRecognizer === interactiveDismissPanGesture
            ? otherGestureRecognizer
            : (otherGestureRecognizer === interactiveDismissPanGesture ? gestureRecognizer : nil)
        guard otherGesture is UIPanGestureRecognizer else { return false }
        return otherGesture?.view is UIScrollView
    }

    func preparePictureInPicture(for owner: GalleryVideoPlaybackOwner) -> Bool {
        guard hasCurrentContext else { return false }
        return GalleryPictureInPictureCoordinator.shared.prepare(
            owner: owner,
            gallery: self,
            messages: messages,
        )
    }

    func playbackOwnerWasDeleted(_ owner: GalleryVideoPlaybackOwner) {
        guard hasCurrentContext, !didReleasePlaybackOwners else { return }
        pendingDeletedPlaybackOwners[owner.messageID] = owner
        pendingDeletedMessageIDsByChat[owner.chatID, default: []].insert(owner.messageID)
        drainPendingMessageUpdates()
    }

    func restorePictureInPicture(
        owner: GalleryVideoPlaybackOwner,
        completion: @escaping (Bool) -> Void,
    ) {
        guard hasCurrentContext else {
            completion(false)
            return
        }
        guard let index = messages.firstIndex(where: { $0.id == owner.messageID }) else {
            completion(false)
            return
        }
        videoPlaybackOwners[owner.messageID] = owner
        owner.galleryController = self
        selectedIndex = index
        loadViewIfNeeded()
        view.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        collectionView.layoutIfNeeded()
        guard let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? MediaGalleryCell else {
            completion(false)
            return
        }
        cell.configure(message: messages[index], videoPlaybackOwner: owner)
        cell.setPlaybackVisible(true)
        updateCounter()
        bindSelectedCellChrome()
        prunePlaybackOwners(around: index)
        completion(true)
    }

    func pictureInPictureDidFinish(for _: GalleryVideoPlaybackOwner) {
        if messages.indices.contains(selectedIndex) {
            collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
                .flatMap { $0 as? MediaGalleryCell }?
                .setPlaybackVisible(true)
            prunePlaybackOwners(around: selectedIndex)
        }
    }

    func updateMessages(_ updatedMessages: [Message]) {
        guard hasCurrentContext, !didReleasePlaybackOwners else { return }
        if messageUpdateInProgress || mediaTransitionController?.isInteractiveDismissalInProgress == true {
            pendingMessageUpdate = updatedMessages
            return
        }
        guard !isBeingDismissed else { return }
        let updatedMessages = updatedMessages.filter { message in
            switch message.content {
            case .messageAnimation, .messagePhoto, .messageSticker, .messageVideo:
                true
            default:
                false
            }
        }
        let previousIDs = messages.map(\.id)
        let updatedIDs = updatedMessages.map(\.id)
        if previousIDs == updatedIDs {
            if exportTask != nil || forwardTask != nil || deleteTask != nil,
               let selectedMessageID,
               let previous = messages.first(where: { $0.id == selectedMessageID }),
               let updated = updatedMessages.first(where: { $0.id == selectedMessageID }),
               previous != updated
            {
                cancelExport()
                cancelForward()
                cancelDelete()
            }
            messages = updatedMessages
            if isViewLoaded {
                updateCounter()
            }
            return
        }
        let selectedMessageID = selectedMessageID
        if let selectedMessageID, !updatedIDs.contains(selectedMessageID) {
            cancelExport()
            cancelForward()
            cancelDelete()
            cancelOpenInChat()
            forcedDismissalSnapshot = forcedDismissalSnapshot ?? selectedGalleryCell()?.makeTransitionSnapshot()
            forcesFadeDismissal = true
            shouldReleasePlaybackOwnersAfterDisappearance = true
            dismiss(animated: true)
            return
        }
        let appendsOnly = updatedIDs.count > previousIDs.count
            && updatedIDs.starts(with: previousIDs)
        let previousCount = messages.count
        messages = updatedMessages
        if let totalMessageCount, messages.count > totalMessageCount {
            self.totalMessageCount = messages.count
        }
        selectedIndex =
            if let selectedMessageID,
            let preservedIndex = messages.firstIndex(where: { $0.id == selectedMessageID }) {
                preservedIndex
            } else {
                min(selectedIndex, max(0, messages.count - 1))
            }
        if messages.count > previousCount {
            paginationRequestedMessageCount = nil
        }
        guard isViewLoaded else { return }
        let finishUpdate = { [weak self] in
            guard let self else { return }
            updateCounter()
            guard didSetInitialPosition, messages.indices.contains(selectedIndex) else { return }
            collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
                .flatMap { $0 as? MediaGalleryCell }?
                .setPlaybackVisible(shouldPlayItem(at: selectedIndex))
            bindSelectedCellChrome()
            prunePlaybackOwners(around: selectedIndex)
        }
        if appendsOnly {
            let indexPaths = (previousCount..<messages.count).map { IndexPath(item: $0, section: 0) }
            messageUpdateInProgress = true
            collectionView.performBatchUpdates {
                collectionView.insertItems(at: indexPaths)
            } completion: { [weak self] _ in
                guard let self else { return }
                messageUpdateInProgress = false
                guard hasCurrentContext, !didReleasePlaybackOwners else { return }
                finishUpdate()
                drainPendingMessageUpdates()
                requestMoreMessagesIfNeeded(near: selectedIndex)
            }
        } else {
            collectionView.reloadData()
            if didSetInitialPosition, messages.indices.contains(selectedIndex) {
                collectionView.layoutIfNeeded()
                collectionView.scrollToItem(
                    at: IndexPath(item: selectedIndex, section: 0),
                    at: .centeredHorizontally,
                    animated: false,
                )
            }
            finishUpdate()
        }
    }

    func allowMoreMessagesRetry() {
        paginationRequestedMessageCount = nil
    }

    func updateTotalMessageCount(_ count: Int?) {
        totalMessageCount = count.map { max($0, messages.count) }
        if isViewLoaded {
            updateCounter()
        }
    }

    func invalidateForContextChange(completion: @escaping () -> Void) {
        cancelExport()
        cancelForward()
        cancelDelete()
        cancelOpenInChat()
        contextWasInvalidated = true
        contextInvalidationCompletion = completion
        onRequestMoreMessages = nil
        paginationRequestedMessageCount = messages.count
        pendingMessageUpdate = nil
        pendingDeletedPlaybackOwners = [:]
        pendingDeletedMessageIDsByChat = [:]
        forcesFadeDismissal = true
        shouldReleasePlaybackOwnersAfterDisappearance = true
        if mediaTransitionController?.isInteractiveDismissalInProgress == true {
            mediaTransitionController?.finishInteractiveDismissal()
            return
        }
        releasePlaybackOwnersForDismissal()
        let completion = takeContextInvalidationCompletion()
        dismiss(animated: false, completion: completion)
    }

    fileprivate func transitionContentFrame(in coordinateSpace: UIView) -> CGRect? {
        selectedGalleryCell()?.transitionContentFrame(in: coordinateSpace)
    }

    fileprivate func makeTransitionSnapshot() -> UIView? {
        guard hasCurrentContext else { return forcedDismissalSnapshot }
        return forcedDismissalSnapshot ?? selectedGalleryCell()?.makeTransitionSnapshot()
    }

    fileprivate func currentTransitionTarget() -> MediaGalleryTransitionTarget? {
        guard !forcesFadeDismissal else { return nil }
        guard let selectedMessageID else { return nil }
        return transitionSourceProvider?(selectedMessageID)
    }

    fileprivate func preparePlaybackOwnersForDismissalTransition() {
        shouldReleasePlaybackOwnersAfterDisappearance = true
        releasePlaybackOwnersForDismissal()
    }

    fileprivate func presentationTransitionDidCancel() {
        releasePlaybackOwnersForDismissal()
    }

    private func observePermanentMessageDeletes() {
        deleteMessagesCancellable = tdlib.deleteMessageUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.handlePermanentMessageDeletes(update)
            }
    }

    private func handlePermanentMessageDeletes(_ update: UpdateDeleteMessages) {
        guard hasCurrentContext,
              !update.fromCache,
              update.isPermanent
        else { return }
        let deletedIDs = Set(update.messageIds)
        let hasMatchingMessage = messages.contains { message in
            message.chatId == update.chatId && deletedIDs.contains(message.id)
        } || pendingMessageUpdate?.contains(where: { message in
            message.chatId == update.chatId && deletedIDs.contains(message.id)
        }) == true
        guard hasMatchingMessage else { return }
        pendingDeletedMessageIDsByChat[update.chatId, default: []].formUnion(deletedIDs)
        drainPendingMessageUpdates()
    }

    private func makeKeyCommand(
        input: String,
        modifierFlags: UIKeyModifierFlags,
        action: Selector,
        discoverabilityTitle: String,
    ) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        command.discoverabilityTitle = discoverabilityTitle
        return command
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
        collectionView.addGestureRecognizer(chromeTapGesture)
        collectionView.addGestureRecognizer(interactiveDismissPanGesture)
        collectionView.register(MediaGalleryCell.self, forCellWithReuseIdentifier: MediaGalleryCell.reuseIdentifier)
        view.addSubview(collectionView)
    }

    private func configureToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.accessibilityIdentifier = "gallery-footer"
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: symbolConfiguration), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "Close"
        closeButton.accessibilityIdentifier = "gallery-close"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        toolbar.contentView.addSubview(closeButton)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.setImage(
            UIImage(systemName: "square.and.arrow.up", withConfiguration: symbolConfiguration),
            for: .normal,
        )
        shareButton.tintColor = .white
        shareButton.accessibilityLabel = "Share"
        shareButton.accessibilityIdentifier = "gallery-share"
        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        toolbar.contentView.addSubview(shareButton)
        shareActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
        shareActivityIndicator.color = .white
        shareActivityIndicator.hidesWhenStopped = true
        shareActivityIndicator.isUserInteractionEnabled = false
        toolbar.contentView.addSubview(shareActivityIndicator)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.setImage(
            UIImage(systemName: "ellipsis", withConfiguration: symbolConfiguration),
            for: .normal,
        )
        moreButton.tintColor = .white
        moreButton.accessibilityLabel = "More actions"
        moreButton.accessibilityIdentifier = "gallery-more-actions"
        moreButton.showsMenuAsPrimaryAction = true
        toolbar.contentView.addSubview(moreButton)
        moreActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
        moreActivityIndicator.color = .white
        moreActivityIndicator.hidesWhenStopped = true
        moreActivityIndicator.isUserInteractionEnabled = false
        toolbar.contentView.addSubview(moreActivityIndicator)
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        counterLabel.textColor = .white
        counterLabel.font = .preferredFont(forTextStyle: .subheadline)
        counterLabel.adjustsFontForContentSizeCategory = true
        counterLabel.adjustsFontSizeToFitWidth = true
        counterLabel.minimumScaleFactor = 0.75
        counterLabel.textAlignment = .center
        counterLabel.accessibilityIdentifier = "gallery-counter"
        counterLabel.accessibilityTraits = [.staticText, .updatesFrequently]
        toolbar.contentView.addSubview(counterLabel)
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            closeButton.topAnchor.constraint(equalTo: toolbar.contentView.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 52),
            closeButton.heightAnchor.constraint(equalToConstant: 50),
            shareButton.topAnchor.constraint(equalTo: toolbar.contentView.topAnchor),
            shareButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            shareButton.widthAnchor.constraint(equalToConstant: 52),
            shareButton.heightAnchor.constraint(equalToConstant: 50),
            shareActivityIndicator.centerXAnchor.constraint(equalTo: shareButton.centerXAnchor),
            shareActivityIndicator.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor),
            moreButton.topAnchor.constraint(equalTo: toolbar.contentView.topAnchor),
            moreButton.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 52),
            moreButton.heightAnchor.constraint(equalToConstant: 50),
            moreActivityIndicator.centerXAnchor.constraint(equalTo: moreButton.centerXAnchor),
            moreActivityIndicator.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),
            counterLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 8),
            counterLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -8),
            counterLabel.centerXAnchor.constraint(equalTo: toolbar.contentView.centerXAnchor),
            counterLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
        ])
        updateMoreMenu()
    }

    private func configureCaption() {
        captionView.translatesAutoresizingMaskIntoConstraints = false
        captionView.accessibilityIdentifier = "gallery-caption"
        captionView.isHidden = true
        captionTextView.translatesAutoresizingMaskIntoConstraints = false
        captionTextView.onBackgroundTap = { [weak self] in
            self?.toggleChromeVisibility()
        }
        captionTextView.onInteractionChanged = { [weak self] isInteracting in
            self?.setCaptionInteractionActive(isInteracting)
        }
        captionTextView.onOpenURL = { [weak self] url, requiresConfirmation in
            self?.openCaptionURL(url, requiresConfirmation: requiresConfirmation)
        }
        captionTextView.onRevealSpoilers = { [weak self] in
            self?.revealSelectedCaptionSpoilers()
        }
        captionView.contentView.addSubview(captionTextView)
        view.addSubview(captionView)
        captionHeightConstraint = captionView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            captionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            captionView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            captionHeightConstraint,
            captionTextView.topAnchor.constraint(equalTo: captionView.contentView.topAnchor, constant: 8),
            captionTextView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            captionTextView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            captionTextView.bottomAnchor.constraint(equalTo: captionView.contentView.bottomAnchor, constant: -8),
        ])
    }

    private func updateCounter() {
        let count = max(messages.count, totalMessageCount ?? messages.count)
        counterLabel.text = actionStatusText ?? (count > 1 ? "\(selectedIndex + 1) of \(count)" : "")
        updateMoreMenu()
        updateCaption()
    }

    private func updateCaption() {
        guard messages.indices.contains(selectedIndex),
              let formattedText = MessageContentPresentation.make(messages[selectedIndex]).formattedText,
              !formattedText.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            setCaptionInteractionActive(false)
            captionView.isHidden = true
            captionHeightConstraint.constant = 0
            updateSelectedMediaChromeBottomInset()
            return
        }
        let messageID = messages[selectedIndex].id
        captionTextView.configure(
            messageID: messageID,
            formattedText: formattedText,
            spoilersRevealed: revealedCaptionSpoilerMessageIDs.contains(messageID),
        )
        captionView.isHidden = false
        captionView.alpha = chromeIsVisible ? 1 : 0
        captionView.accessibilityElementsHidden = !chromeIsVisible
        updateCaptionHeight()
    }

    private func updateCaptionHeight() {
        guard !captionView.isHidden, view.bounds.width > 0 else {
            captionHeightConstraint.constant = 0
            updateSelectedMediaChromeBottomInset()
            return
        }
        let width = max(1, view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 24)
        let measuredHeight = captionTextView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude),
        )
        .height + 16
        let maximumHeight = traitCollection.verticalSizeClass == .compact
            ? min(96, view.bounds.height * 0.24)
            : min(220, max(96, view.bounds.height * 0.32))
        let height = min(maximumHeight, max(44, ceil(measuredHeight)))
        captionHeightConstraint.constant = height
        let canScroll = measuredHeight > height + 0.5
        captionTextView.isScrollEnabled = canScroll
        if !canScroll {
            captionTextView.setContentOffset(.zero, animated: false)
        }
        if captionInteractionIsActive,
           !captionTextView.isDragging,
           !captionTextView.isDecelerating,
           !canScroll || captionTextView.contentOffset.y <= 1
        {
            setCaptionInteractionActive(false)
        }
        updateSelectedMediaChromeBottomInset()
    }

    private func updateSelectedMediaChromeBottomInset() {
        let captionHeight = captionView.isHidden ? 0 : captionHeightConstraint.constant
        visibleSelectedGalleryCell()?.setGalleryChromeBottomInset(50 + captionHeight)
    }

    private func setCaptionInteractionActive(_ isActive: Bool) {
        guard captionInteractionIsActive != isActive else { return }
        captionInteractionIsActive = isActive
        if isActive {
            setChromeVisible(true, animated: false)
        }
        visibleSelectedGalleryCell()?.setGalleryChromeInteractionActive(isActive)
    }

    private func revealSelectedCaptionSpoilers() {
        guard messages.indices.contains(selectedIndex) else { return }
        revealedCaptionSpoilerMessageIDs.insert(messages[selectedIndex].id)
        updateCaption()
        UIAccessibility.post(notification: .layoutChanged, argument: captionTextView)
    }

    private func observeVoiceOver() {
        voiceOverCancellable = NotificationCenter.default
            .publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard UIAccessibility.isVoiceOverRunning else { return }
                self?.setChromeVisible(true, animated: false)
            }
    }

    private func observeContentSizeCategory() {
        contentSizeCancellable = NotificationCenter.default
            .publisher(for: UIContentSizeCategory.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCaption()
            }
    }

    private func openCaptionURL(_ url: URL, requiresConfirmation: Bool) {
        guard hasCurrentContext else { return }
        guard requiresConfirmation else {
            UIApplication.shared.open(url)
            return
        }
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Open Link?",
            message: url.absoluteString,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    private func setChromeVisible(_ visible: Bool, animated: Bool) {
        guard chromeIsVisible != visible else { return }
        chromeIsVisible = visible
        toolbar.isUserInteractionEnabled = visible
        toolbar.accessibilityElementsHidden = !visible
        captionView.isUserInteractionEnabled = visible
        captionView.accessibilityElementsHidden = !visible
        selectedGalleryCell()?.setGalleryChromeVisible(visible, animated: animated)
        let updates = {
            self.toolbar.alpha = visible ? 1 : 0
            self.captionView.alpha = visible ? 1 : 0
        }
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
                animations: updates,
            )
        } else {
            updates()
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    private func updateSelection(from scrollView: UIScrollView) {
        guard !messages.isEmpty else { return }
        let updatedIndex = min(
            messages.count - 1,
            max(0, Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))),
        )
        requestMoreMessagesIfNeeded(near: updatedIndex)
        guard updatedIndex != selectedIndex else {
            collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
                .flatMap { $0 as? MediaGalleryCell }?
                .setPlaybackVisible(shouldPlayItem(at: selectedIndex))
            bindSelectedCellChrome()
            prunePlaybackOwners(around: selectedIndex)
            return
        }
        cancelExport()
        cancelForward()
        cancelDelete()
        cancelOpenInChat()
        clearActionStatus()
        if let previousCell = collectionView.cellForItem(
            at: IndexPath(item: selectedIndex, section: 0),
        ) as? MediaGalleryCell {
            setCaptionInteractionActive(false)
            previousCell.unbindGalleryChrome()
            previousCell.setPlaybackVisible(false)
        }
        selectedIndex = updatedIndex
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? MediaGalleryCell }?
            .setPlaybackVisible(shouldPlayItem(at: selectedIndex))
        bindSelectedCellChrome()
        updateCounter()
        prunePlaybackOwners(around: selectedIndex)
    }

    private func requestMoreMessagesIfNeeded(near index: Int) {
        guard hasCurrentContext,
              !isBeingDismissed,
              !didReleasePlaybackOwners,
              !messageUpdateInProgress,
              index >= max(0, messages.count - 3),
              paginationRequestedMessageCount != messages.count,
              let onRequestMoreMessages
        else { return }
        paginationRequestedMessageCount = messages.count
        onRequestMoreMessages()
    }

    private func drainPendingMessageUpdates() {
        guard hasCurrentContext,
              !didReleasePlaybackOwners,
              !messageUpdateInProgress,
              mediaTransitionController?.isInteractiveDismissalInProgress != true
        else { return }
        for owner in pendingDeletedPlaybackOwners.values {
            pendingDeletedMessageIDsByChat[owner.chatID, default: []].insert(owner.messageID)
        }
        pendingDeletedPlaybackOwners = [:]
        let deletedIDsByChat = pendingDeletedMessageIDsByChat
        pendingDeletedMessageIDsByChat = [:]
        let baseMessages = pendingMessageUpdate ?? messages
        pendingMessageUpdate = nil
        guard !deletedIDsByChat.isEmpty else {
            if baseMessages != messages {
                updateMessages(baseMessages)
            }
            return
        }
        let isDeleted: (Message) -> Bool = { message in
            deletedIDsByChat[message.chatId]?.contains(message.id) == true
        }
        let deletedCurrentMessages = messages.filter(isDeleted)
        let selectedWasDeleted = messages.indices.contains(selectedIndex) && isDeleted(messages[selectedIndex])
        let snapshot = selectedWasDeleted ? selectedGalleryCell()?.makeTransitionSnapshot() : nil
        for message in deletedCurrentMessages {
            if let owner = videoPlaybackOwners.removeValue(forKey: message.id) {
                owner.confirmPermanentDeletionFromGallery()
                owner.galleryController = nil
            }
        }
        if let totalMessageCount, !deletedCurrentMessages.isEmpty {
            self.totalMessageCount = max(
                messages.count - deletedCurrentMessages.count,
                totalMessageCount - deletedCurrentMessages.count,
            )
        }
        if selectedWasDeleted {
            forcedDismissalSnapshot = forcedDismissalSnapshot ?? snapshot
        }
        let filteredMessages = baseMessages.filter { !isDeleted($0) }
        if filteredMessages != messages || selectedWasDeleted {
            updateMessages(filteredMessages)
        }
    }

    private func playbackOwner(for message: Message) -> GalleryVideoPlaybackOwner? {
        guard hasCurrentContext,
              !didReleasePlaybackOwners,
              case .messageVideo = message.content
        else { return nil }
        if let owner = videoPlaybackOwners[message.id] {
            owner.galleryController = self
            return owner
        }
        guard let owner = GalleryVideoPlaybackOwner(message: message, tdlib: tdlib) else { return nil }
        owner.galleryController = self
        videoPlaybackOwners[message.id] = owner
        return owner
    }

    private func releasePlaybackOwnersForDismissal() {
        guard !didReleasePlaybackOwners else { return }
        didReleasePlaybackOwners = true
        collectionView.visibleCells
            .compactMap { $0 as? MediaGalleryCell }
            .forEach { $0.unbindGalleryChrome() }
        let pictureInPictureCoordinator = GalleryPictureInPictureCoordinator.shared
        pictureInPictureCoordinator.galleryWillDismiss(self)
        for owner in videoPlaybackOwners.values {
            if pictureInPictureCoordinator.isRetaining(owner) {
                owner.detachFromGallery()
            } else if owner.returnToInlineIfAvailable() {
                continue
            } else {
                owner.invalidate()
            }
        }
        videoPlaybackOwners.removeAll()
    }

    private func shouldPlayItem(at index: Int) -> Bool {
        guard index == selectedIndex, messages.indices.contains(index) else { return false }
        guard let activeOwner = GalleryPictureInPictureCoordinator.shared.activeOwner else { return true }
        return activeOwner.messageID == messages[index].id
    }

    private func prunePlaybackOwners(around index: Int) {
        guard messages.indices.contains(index) else { return }
        let lowerBound = max(messages.startIndex, index - 1)
        let upperBound = min(messages.index(before: messages.endIndex), index + 1)
        let retainedMessageIDs = Set(messages[lowerBound...upperBound].compactMap { message -> Int64? in
            guard case .messageVideo = message.content else { return nil }
            return message.id
        })
        let evictedMessageIDs = videoPlaybackOwners.compactMap { messageID, owner in
            !retainedMessageIDs.contains(messageID)
                && !owner.isPictureInPictureRetained
                && !owner.isBorrowedFromInline
                ? messageID
                : nil
        }
        for messageID in evictedMessageIDs {
            videoPlaybackOwners.removeValue(forKey: messageID)?.invalidate()
        }
    }

    @objc private func close() {
        cancelExport()
        cancelForward()
        cancelDelete()
        cancelOpenInChat()
        dismiss(animated: true)
    }

    @objc private func toggleChromeVisibility() {
        guard !UIAccessibility.isVoiceOverRunning else {
            setChromeVisible(true, animated: false)
            return
        }
        setChromeVisible(!chromeIsVisible, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func handleInteractiveDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard let mediaTransitionController else { return }
        switch gesture.state {
        case .began:
            guard canBeginInteractiveDismissal,
                  let cell = visibleSelectedGalleryCell()
            else { return }
            interactiveDismissalProgress = 0
            interactiveDismissalChromeWasVisible = chromeIsVisible
            cell.setInteractiveDismissalActive(true)
            collectionView.panGestureRecognizer.isEnabled = false
            setChromeVisible(false, animated: !UIAccessibility.isReduceMotionEnabled)
            let began = mediaTransitionController.beginInteractiveDismissal(from: self) { [weak self] completed in
                self?.interactiveDismissalEnded(completed: completed)
            }
            if !began {
                interactiveDismissalEnded(completed: false)
            }
        case .changed:
            let translation = gesture.translation(in: view)
            interactiveDismissalProgress = min(1, max(0, translation.y / max(view.bounds.height * 0.6, 1)))
            mediaTransitionController.updateInteractiveDismissal(interactiveDismissalProgress)
        case .ended:
            let velocity = gesture.velocity(in: view)
            if interactiveDismissalProgress >= 0.28 || velocity.y >= 900 {
                mediaTransitionController.finishInteractiveDismissal()
            } else {
                mediaTransitionController.cancelInteractiveDismissal()
            }
        case .cancelled, .failed:
            mediaTransitionController.cancelInteractiveDismissal()
        case .possible:
            break
        @unknown default:
            mediaTransitionController.cancelInteractiveDismissal()
        }
    }

    private func interactiveDismissalEnded(completed: Bool) {
        visibleSelectedGalleryCell()?.setInteractiveDismissalActive(false)
        collectionView.panGestureRecognizer.isEnabled = true
        interactiveDismissalProgress = 0
        if contextWasInvalidated {
            if completed {
                takeContextInvalidationCompletion()?()
            } else {
                releasePlaybackOwnersForDismissal()
                let completion = takeContextInvalidationCompletion()
                dismiss(animated: false, completion: completion)
            }
            return
        }
        guard !completed, hasCurrentContext else { return }
        view.accessibilityViewIsModal = true
        shouldReleasePlaybackOwnersAfterDisappearance = false
        setChromeVisible(
            interactiveDismissalChromeWasVisible,
            animated: !UIAccessibility.isReduceMotionEnabled,
        )
        bindSelectedCellChrome()
        drainPendingMessageUpdates()
    }

    private func takeContextInvalidationCompletion() -> (() -> Void)? {
        let completion = contextInvalidationCompletion
        contextInvalidationCompletion = nil
        return completion
    }

    private func bindSelectedCellChrome() {
        guard messages.indices.contains(selectedIndex) else { return }
        let cell = collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0)) as? MediaGalleryCell
        bindGalleryChrome(to: cell)
    }

    private func bindGalleryChrome(to cell: MediaGalleryCell?) {
        cell?.bindGalleryChrome(isVisible: chromeIsVisible) { [weak self] visible in
            self?.setChromeVisible(visible, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        cell?.setGalleryChromeBottomInset(50 + (captionView.isHidden ? 0 : captionHeightConstraint.constant))
        cell?.setGalleryChromeInteractionActive(captionInteractionIsActive)
    }

    @objc private func toggleSelectedPlayback() {
        performOnSelectedItem(.togglePlayback)
    }

    @objc private func jumpSelectedPlaybackBackward() {
        performOnSelectedItem(.jump(-5))
    }

    @objc private func jumpSelectedPlaybackForward() {
        performOnSelectedItem(.jump(5))
    }

    @objc private func toggleSelectedPictureInPicture() {
        performOnSelectedItem(.togglePictureInPicture)
    }

    private func performOnSelectedItem(_ command: GalleryPlaybackCommand) {
        guard hasCurrentContext, !didReleasePlaybackOwners else { return }
        if command == .togglePictureInPicture,
           let activeOwner = GalleryPictureInPictureCoordinator.shared.activeOwner
        {
            activeOwner.performPlaybackCommand(command)
            return
        }
        guard messages.indices.contains(selectedIndex) else { return }
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        (collectionView.cellForItem(at: indexPath) as? MediaGalleryCell)?
            .performPlaybackCommand(command)
    }

    @objc private func share() {
        guard presentedViewController == nil,
              messages.indices.contains(selectedIndex),
              let asset = MediaGalleryExportAsset(messages[selectedIndex])
        else { return }
        guard asset.isLivePhoto else {
            exportSelectedMedia(.share)
            return
        }
        let alert = UIAlertController(
            title: "Share Still Photo?",
            message: "The motion part of this Live Photo won't be included.",
            preferredStyle: .actionSheet,
        )
        alert.addAction(UIAlertAction(title: "Share Still Photo", style: .default) { [weak self, weak alert] _ in
            alert?.dismiss(animated: true) { [weak self] in
                self?.exportSelectedMedia(.share)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = shareButton
        alert.popoverPresentationController?.sourceRect = shareButton.bounds
        present(alert, animated: true)
    }

    private func updateMoreMenu() {
        let hasActionContext = actionAccountID != nil
            && actionClient != nil
            && actionChatID != nil
            && actionClientID != nil
            && messages.indices.contains(selectedIndex)
        shareButton.isHidden = !hasActionContext
        let selectedAsset = messages.indices.contains(selectedIndex)
            ? MediaGalleryExportAsset(messages[selectedIndex])
            : nil
        shareButton.accessibilityLabel = selectedAsset?.isLivePhoto == true ? "Share Still Photo" : "Share"
        let canOpen = hasActionContext && onOpenMessageID != nil
        let canForward = hasActionContext && actionSourceLocation != nil
        let selectedMessage = messages.indices.contains(selectedIndex) ? messages[selectedIndex] : nil
        let canDelete = hasActionContext
            && actionSourceLocation != nil
            && selectedMessage?.selfDestructType == nil
            && selectedMessage?.selfDestructIn == 0
            && selectedAsset?.isSecretMedia == false
        let saveAsset = hasActionContext ? MediaGalleryExportAsset(messages[selectedIndex]) : nil
        let canSave = saveAsset?.photosKind != nil
        moreButton.isHidden = !canOpen && !canForward && !canSave && !canDelete
        guard canOpen || canForward || canSave || canDelete else {
            moreButton.menu = nil
            return
        }
        var actions = [UIAction]()
        if canOpen {
            actions.append(UIAction(
                title: "Open in Chat",
                image: UIImage(systemName: "bubble.left.and.text.bubble.right"),
            ) { [weak self] _ in
                self?.openSelectedMessageInChat()
            })
        }
        if canForward {
            actions.append(UIAction(
                title: "Forward",
                image: UIImage(systemName: "arrowshape.turn.up.right"),
            ) { [weak self] _ in
                self?.forwardSelectedMedia()
            })
        }
        if let saveAsset, saveAsset.photosKind != nil, let title = saveAsset.saveActionTitle {
            actions.append(UIAction(
                title: title,
                image: UIImage(systemName: "square.and.arrow.down"),
            ) { [weak self] _ in
                self?.exportSelectedMedia(.saveToPhotos)
            })
        }
        if canDelete {
            actions.append(UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { [weak self] _ in
                self?.deleteSelectedMedia()
            })
        }
        moreButton.menu = UIMenu(children: actions)
    }

    private func openSelectedMessageInChat() {
        guard openInChatTask == nil,
              deleteTask == nil,
              exportTask == nil,
              forwardTask == nil,
              presentedViewController == nil,
              hasCurrentContext,
              messages.indices.contains(selectedIndex),
              let accountID = actionAccountID,
              let client = actionClient,
              let chatID = actionChatID,
              let clientID = actionClientID,
              client.id == clientID,
              let onOpenMessageID
        else { return }
        let selectedIdentity = MediaGalleryMessageIdentity(messages[selectedIndex])
        guard selectedIdentity.chatID == chatID else { return }
        let generation = UUID()
        openInChatGeneration = generation
        setActionBusy(true, source: .more)
        UIAccessibility.post(notification: .announcement, argument: "Opening message")
        openInChatTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await client.getMessage(
                    chatId: selectedIdentity.chatID,
                    messageId: selectedIdentity.messageID,
                )
                try Task.checkCancellation()
                let resolvedIdentity = MediaGalleryMessageIdentity(resolved)
                guard openInChatGeneration == generation,
                      hasCurrentContext,
                      !isBeingDismissed,
                      selectedMessageID == selectedIdentity.messageID,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == clientID
                else { throw MediaGalleryOpenInChatError.contextChanged }
                guard resolvedIdentity.chatID == selectedIdentity.chatID,
                      resolvedIdentity.messageID == selectedIdentity.messageID,
                      !actionRequiresTopicMatch || resolvedIdentity.topic == requiredActionTopic
                else { throw MediaGalleryOpenInChatError.messageUnavailable }
                openInChatTask = nil
                setActionBusy(false)
                openInChatDismissalGeneration = generation
                forcesFadeDismissal = true
                dismiss(animated: true) { [weak self] in
                    guard let self,
                          openInChatGeneration == generation,
                          openInChatDismissalGeneration == generation,
                          hasCurrentContext,
                          TDLib.shared.activeAccountID == accountID,
                          TDLib.shared.activeClient.id == clientID
                    else {
                        self?.finishOpenInChat(generation: generation)
                        return
                    }
                    openInChatGeneration = nil
                    openInChatDismissalGeneration = nil
                    onOpenMessageID(resolvedIdentity.messageID)
                }
            } catch is CancellationError {
                finishOpenInChat(generation: generation)
            } catch {
                guard openInChatGeneration == generation,
                      hasCurrentContext,
                      !isBeingDismissed
                else { return }
                finishOpenInChat(generation: generation)
                let displayedError = error is MediaGalleryOpenInChatError
                    ? error
                    : MediaGalleryOpenInChatError.messageUnavailable
                presentOpenInChatError(displayedError.localizedDescription)
            }
        }
    }

    private func forwardSelectedMedia() {
        guard forwardTask == nil,
              deleteTask == nil,
              exportTask == nil,
              openInChatTask == nil,
              openInChatDismissalGeneration == nil,
              presentedViewController == nil,
              hasCurrentContext,
              messages.indices.contains(selectedIndex),
              let accountID = actionAccountID,
              let client = actionClient,
              let clientID = actionClientID,
              let sourceLocation = actionSourceLocation,
              sourceLocation.accountID == accountID,
              sourceLocation.clientID == clientID,
              client.id == clientID
        else { return }
        let selectedIdentity = MediaGalleryMessageIdentity(messages[selectedIndex])
        guard selectedIdentity.chatID == sourceLocation.chatID else { return }
        let generation = UUID()
        forwardGeneration = generation
        setActionBusy(true, source: .more)
        UIAccessibility.post(notification: .announcement, argument: "Preparing media to forward")
        forwardTask = Task { [weak self] in
            guard let self else { return }
            do {
                let selectedMessage = try await client.getMessage(
                    chatId: selectedIdentity.chatID,
                    messageId: selectedIdentity.messageID,
                )
                try Task.checkCancellation()
                let resolvedIdentity = MediaGalleryMessageIdentity(selectedMessage)
                try validateForwardContext(
                    accountID: accountID,
                    clientID: clientID,
                    generation: generation,
                    selectedIdentity: selectedIdentity,
                    resolvedIdentity: resolvedIdentity,
                )
                guard sourceLocation.matches(message: selectedMessage) else {
                    throw MessageForwardingError.sourceMismatch
                }
                let albumMessageIDs = try await resolvedAlbumMessageIDs(
                    selectedMessage: selectedMessage,
                    sourceLocation: sourceLocation,
                    client: client,
                )
                try Task.checkCancellation()
                try validateForwardContext(
                    accountID: accountID,
                    clientID: clientID,
                    generation: generation,
                    selectedIdentity: selectedIdentity,
                    resolvedIdentity: resolvedIdentity,
                )
                finishForward(generation: generation)
                if albumMessageIDs.count > 1 {
                    presentForwardChoice(
                        selectedMessageID: selectedMessage.id,
                        albumMessageIDs: albumMessageIDs,
                        sourceLocation: sourceLocation,
                        client: client,
                        accountID: accountID,
                    )
                } else {
                    presentForwardPicker(
                        messageIDs: [selectedMessage.id],
                        sourceLocation: sourceLocation,
                        client: client,
                        accountID: accountID,
                    )
                }
            } catch is CancellationError {
                finishForward(generation: generation)
            } catch {
                guard forwardGeneration == generation,
                      hasCurrentContext,
                      !isBeingDismissed
                else { return }
                finishForward(generation: generation)
                presentForwardError(error)
            }
        }
    }

    private func validateForwardContext(
        accountID: UUID,
        clientID: Int32,
        generation: UUID,
        selectedIdentity: MediaGalleryMessageIdentity,
        resolvedIdentity: MediaGalleryMessageIdentity,
    ) throws {
        guard forwardGeneration == generation,
              hasCurrentContext,
              !isBeingDismissed,
              selectedMessageID == selectedIdentity.messageID,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == clientID
        else { throw MessageForwardingError.accountChanged }
        guard resolvedIdentity == selectedIdentity || !actionRequiresTopicMatch,
              resolvedIdentity.chatID == selectedIdentity.chatID,
              resolvedIdentity.messageID == selectedIdentity.messageID,
              !actionRequiresTopicMatch || resolvedIdentity.topic == requiredActionTopic
        else { throw MessageForwardingError.sourceMismatch }
    }

    private func resolvedAlbumMessageIDs(
        selectedMessage: Message,
        sourceLocation: ChatLocation,
        client: TDLibClient,
    ) async throws -> [Int64] {
        guard selectedMessage.mediaAlbumId != 0 else { return [selectedMessage.id] }
        let windows = [(limit: 20, offset: -9), (limit: 40, offset: -19), (limit: 100, offset: -49)]
        for window in windows {
            let history: [Message]
            do {
                history = try await forwardHistoryWindow(
                    sourceLocation: sourceLocation,
                    fromMessageID: selectedMessage.id,
                    limit: window.limit,
                    offset: window.offset,
                    client: client,
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            try Task.checkCancellation()
            guard let selectedIndex = history.firstIndex(where: { $0.id == selectedMessage.id }) else { continue }
            var lowerBound = selectedIndex
            while lowerBound > history.startIndex {
                let candidateIndex = history.index(before: lowerBound)
                guard history[candidateIndex].mediaAlbumId == selectedMessage.mediaAlbumId else { break }
                lowerBound = candidateIndex
            }
            var upperBound = selectedIndex
            while upperBound < history.index(before: history.endIndex) {
                let candidateIndex = history.index(after: upperBound)
                guard history[candidateIndex].mediaAlbumId == selectedMessage.mediaAlbumId else { break }
                upperBound = candidateIndex
            }
            let group = Array(history[lowerBound...upperBound])
            guard group.allSatisfy({ sourceLocation.matches(message: $0) }) else { continue }
            let hasNewerBoundary = lowerBound > history.startIndex
            let hasOlderBoundary = upperBound < history.index(before: history.endIndex)
            guard group.count == 10 || hasNewerBoundary && hasOlderBoundary else { continue }
            let messageIDs = Array(Set(group.map(\.id))).sorted()
            guard messageIDs.contains(selectedMessage.id), messageIDs.count <= 10 else { continue }
            return messageIDs
        }
        return [selectedMessage.id]
    }

    private func forwardHistoryWindow(
        sourceLocation: ChatLocation,
        fromMessageID: Int64,
        limit: Int,
        offset: Int,
        client: TDLibClient,
    ) async throws -> [Message] {
        let loaded: [Message] =
            switch sourceLocation.topic {
            case .messageTopicDirectMessages(let topic):
                try await client.getDirectMessagesChatTopicHistory(
                    chatId: sourceLocation.chatID,
                    fromMessageId: fromMessageID,
                    limit: limit,
                    offset: offset,
                    topicId: topic.directMessagesChatTopicId,
                )
                .messages ?? []
            case .messageTopicForum(let topic):
                try await client.getForumTopicHistory(
                    chatId: sourceLocation.chatID,
                    forumTopicId: topic.forumTopicId,
                    fromMessageId: fromMessageID,
                    limit: limit,
                    offset: offset,
                )
                .messages ?? []
            case .messageTopicSavedMessages(let topic):
                try await client.getSavedMessagesTopicHistory(
                    fromMessageId: fromMessageID,
                    limit: limit,
                    offset: offset,
                    savedMessagesTopicId: topic.savedMessagesTopicId,
                )
                .messages ?? []
            case .messageTopicThread(let topic):
                try await client.getMessageThreadHistory(
                    chatId: sourceLocation.chatID,
                    fromMessageId: fromMessageID,
                    limit: limit,
                    messageId: topic.messageThreadId,
                    offset: offset,
                )
                .messages ?? []
            case nil:
                try await client.getChatHistory(
                    chatId: sourceLocation.chatID,
                    fromMessageId: fromMessageID,
                    limit: limit,
                    offset: offset,
                    onlyLocal: false,
                )
                .messages ?? []
            }
        return loaded.filter { sourceLocation.matches(message: $0) }
    }

    private func presentForwardChoice(
        selectedMessageID: Int64,
        albumMessageIDs: [Int64],
        sourceLocation: ChatLocation,
        client: TDLibClient,
        accountID: UUID,
    ) {
        guard hasCurrentContext,
              presentedViewController == nil,
              self.selectedMessageID == selectedMessageID,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { return }
        let alert = UIAlertController(
            title: "Forward Media",
            message: "Choose whether to forward only this item or all \(albumMessageIDs.count) items in the album.",
            preferredStyle: .actionSheet,
        )
        alert.addAction(UIAlertAction(title: "This Item", style: .destructive) { [weak self, weak alert] _ in
            alert?.dismiss(animated: true) { [weak self] in
                self?.presentForwardPicker(
                    messageIDs: [selectedMessageID],
                    sourceLocation: sourceLocation,
                    client: client,
                    accountID: accountID,
                )
            }
        })
        alert.addAction(UIAlertAction(title: "All \(albumMessageIDs.count) Items", style: .destructive) { [
            weak self,
            weak alert,
        ] _ in
            alert?.dismiss(animated: true) { [weak self] in
                self?.presentForwardPicker(
                    messageIDs: albumMessageIDs,
                    sourceLocation: sourceLocation,
                    client: client,
                    accountID: accountID,
                )
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = moreButton
        alert.popoverPresentationController?.sourceRect = moreButton.bounds
        present(alert, animated: true)
    }

    private func presentForwardPicker(
        messageIDs: [Int64],
        sourceLocation: ChatLocation,
        client: TDLibClient,
        accountID: UUID,
    ) {
        guard hasCurrentContext,
              presentedViewController == nil,
              messageIDs.contains(selectedMessageID ?? 0),
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { return }
        do {
            let request = try MessageForwardRequest(
                sourceLocation: sourceLocation,
                messageIDs: messageIDs,
            )
            var seenChatIDs = Set<Int64>()
            let seedChats = RootVM.shared
                .allFolders
                .flatMap(\.chats)
                .map(\.chat)
                .filter { seenChatIDs.insert($0.id).inserted }
            visibleSelectedGalleryCell()?.setPlaybackVisible(false)
            let picker = ForwardMessagesViewController(
                request: request,
                client: client,
                accountID: accountID,
                seedChats: seedChats,
            )
            picker.onFinished = { [weak self] destinationCount in
                self?.showActionStatus(
                    destinationCount == 1 ? "Forwarded to 1 chat" : "Forwarded to \(destinationCount) chats",
                )
            }
            let navigationController = UINavigationController(rootViewController: picker)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        } catch {
            presentForwardError(error)
        }
    }

    private func cancelForward() {
        forwardGeneration = nil
        forwardTask?.cancel()
        forwardTask = nil
        if exportTask == nil,
           deleteTask == nil,
           openInChatTask == nil,
           openInChatDismissalGeneration == nil,
           isViewLoaded
        {
            setActionBusy(false)
        }
    }

    private func finishForward(generation: UUID) {
        guard forwardGeneration == generation else { return }
        forwardGeneration = nil
        forwardTask = nil
        setActionBusy(false)
    }

    private func presentForwardError(_ error: Swift.Error) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? "The selected media couldn't be prepared for forwarding."
        UIAccessibility.post(notification: .announcement, argument: message)
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Can't Forward", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func deleteSelectedMedia() {
        guard deleteTask == nil,
              exportTask == nil,
              forwardTask == nil,
              openInChatTask == nil,
              openInChatDismissalGeneration == nil,
              presentedViewController == nil,
              hasCurrentContext,
              messages.indices.contains(selectedIndex),
              let accountID = actionAccountID,
              let client = actionClient,
              let clientID = actionClientID,
              let sourceLocation = actionSourceLocation,
              sourceLocation.accountID == accountID,
              sourceLocation.clientID == clientID,
              client.id == clientID
        else { return }
        let selectedIdentity = MediaGalleryMessageIdentity(messages[selectedIndex])
        guard selectedIdentity.chatID == sourceLocation.chatID else { return }
        let generation = UUID()
        deleteGeneration = generation
        setActionBusy(true, source: .more)
        UIAccessibility.post(notification: .announcement, argument: "Checking media deletion options")
        deleteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let selectedMessage = try await client.getMessage(
                    chatId: selectedIdentity.chatID,
                    messageId: selectedIdentity.messageID,
                )
                try Task.checkCancellation()
                try validateDeleteContext(
                    accountID: accountID,
                    clientID: clientID,
                    generation: generation,
                    selectedIdentity: selectedIdentity,
                    resolvedIdentity: MediaGalleryMessageIdentity(selectedMessage),
                )
                guard sourceLocation.matches(message: selectedMessage) else {
                    throw MediaGalleryDeleteError.unavailable
                }
                let albumMessageIDs = try await resolvedAlbumMessageIDs(
                    selectedMessage: selectedMessage,
                    sourceLocation: sourceLocation,
                    client: client,
                )
                try Task.checkCancellation()
                try validateDeleteContext(
                    accountID: accountID,
                    clientID: clientID,
                    generation: generation,
                    selectedIdentity: selectedIdentity,
                    resolvedIdentity: MediaGalleryMessageIdentity(selectedMessage),
                )
                finishDelete(generation: generation)
                if albumMessageIDs.count > 1 {
                    presentDeleteScopeChoice(
                        selectedMessageID: selectedMessage.id,
                        albumMessageIDs: albumMessageIDs,
                        sourceLocation: sourceLocation,
                        client: client,
                        accountID: accountID,
                    )
                } else {
                    prepareDeleteConfirmation(
                        messageIDs: [selectedMessage.id],
                        sourceLocation: sourceLocation,
                        client: client,
                        accountID: accountID,
                    )
                }
            } catch is CancellationError {
                finishDelete(generation: generation)
            } catch {
                guard deleteGeneration == generation,
                      hasCurrentContext,
                      !isBeingDismissed
                else { return }
                finishDelete(generation: generation)
                presentDeleteError(error)
            }
        }
    }

    private func presentDeleteScopeChoice(
        selectedMessageID: Int64,
        albumMessageIDs: [Int64],
        sourceLocation: ChatLocation,
        client: TDLibClient,
        accountID: UUID,
    ) {
        guard hasCurrentContext,
              presentedViewController == nil,
              self.selectedMessageID == selectedMessageID,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { return }
        let alert = UIAlertController(
            title: "Delete Media",
            message: "Choose whether to delete only this item or all \(albumMessageIDs.count) items in the album.",
            preferredStyle: .actionSheet,
        )
        alert.addAction(UIAlertAction(title: "This Item", style: .default) { [weak self, weak alert] _ in
            alert?.dismiss(animated: true) { [weak self] in
                self?.prepareDeleteConfirmation(
                    messageIDs: [selectedMessageID],
                    sourceLocation: sourceLocation,
                    client: client,
                    accountID: accountID,
                )
            }
        })
        alert.addAction(UIAlertAction(title: "All \(albumMessageIDs.count) Items", style: .default) { [
            weak self,
            weak alert,
        ] _ in
            alert?.dismiss(animated: true) { [weak self] in
                self?.prepareDeleteConfirmation(
                    messageIDs: albumMessageIDs,
                    sourceLocation: sourceLocation,
                    client: client,
                    accountID: accountID,
                )
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = moreButton
        alert.popoverPresentationController?.sourceRect = moreButton.bounds
        present(alert, animated: true)
    }

    private func prepareDeleteConfirmation(
        messageIDs: [Int64],
        sourceLocation: ChatLocation,
        client: TDLibClient,
        accountID: UUID,
    ) {
        guard deleteTask == nil,
              exportTask == nil,
              forwardTask == nil,
              openInChatTask == nil,
              openInChatDismissalGeneration == nil,
              presentedViewController == nil,
              hasCurrentContext,
              let selectedMessageID,
              messageIDs.contains(selectedMessageID),
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { return }
        let generation = UUID()
        deleteGeneration = generation
        setActionBusy(true, source: .more)
        deleteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let capabilities = try await deleteCapabilities(
                    messageIDs: messageIDs,
                    sourceLocation: sourceLocation,
                    client: client,
                    accountID: accountID,
                    generation: generation,
                    selectedMessageID: selectedMessageID,
                )
                try Task.checkCancellation()
                finishDelete(generation: generation)
                presentDeleteConfirmation(
                    messageIDs: messageIDs,
                    capabilities: capabilities,
                    sourceLocation: sourceLocation,
                    client: client,
                    accountID: accountID,
                )
            } catch is CancellationError {
                finishDelete(generation: generation)
            } catch {
                guard deleteGeneration == generation,
                      hasCurrentContext,
                      !isBeingDismissed
                else { return }
                finishDelete(generation: generation)
                presentDeleteError(error)
            }
        }
    }

    private func deleteCapabilities(
        messageIDs: [Int64],
        sourceLocation: ChatLocation,
        client: TDLibClient,
        accountID: UUID,
        generation: UUID,
        selectedMessageID: Int64,
    ) async throws -> MediaGalleryDeleteCapabilities {
        var canDeleteOnlyForSelf = true
        var canDeleteForAllUsers = true
        for messageID in messageIDs {
            try Task.checkCancellation()
            async let messageRequest = client.getMessage(
                chatId: sourceLocation.chatID,
                messageId: messageID,
            )
            async let propertiesRequest = client.getMessageProperties(
                chatId: sourceLocation.chatID,
                messageId: messageID,
            )
            let (message, properties) = try await (messageRequest, propertiesRequest)
            guard deleteGeneration == generation,
                  hasCurrentContext,
                  self.selectedMessageID == selectedMessageID,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { throw MediaGalleryDeleteError.accountChanged }
            guard message.chatId == sourceLocation.chatID,
                  message.id == messageID,
                  sourceLocation.matches(message: message)
            else { throw MediaGalleryDeleteError.unavailable }
            guard
                message.selfDestructType == nil,
                message.selfDestructIn == 0,
                !isSecretGalleryMedia(message)
            else { throw MediaGalleryDeleteError.noPermission }
            canDeleteOnlyForSelf = canDeleteOnlyForSelf && properties.canBeDeletedOnlyForSelf
            canDeleteForAllUsers = canDeleteForAllUsers && properties.canBeDeletedForAllUsers
        }
        guard canDeleteOnlyForSelf || canDeleteForAllUsers else {
            throw MediaGalleryDeleteError.noPermission
        }
        return MediaGalleryDeleteCapabilities(
            canDeleteForAllUsers: canDeleteForAllUsers,
            canDeleteOnlyForSelf: canDeleteOnlyForSelf,
        )
    }

    private func isSecretGalleryMedia(_ message: Message) -> Bool {
        switch message.content {
        case .messageAnimation(let content): content.isSecret
        case .messagePhoto(let content): content.isSecret
        case .messageVideo(let content): content.isSecret
        default: false
        }
    }

    private func presentDeleteConfirmation(
        messageIDs: [Int64],
        capabilities: MediaGalleryDeleteCapabilities,
        sourceLocation: ChatLocation,
        client: TDLibClient,
        accountID: UUID,
    ) {
        guard hasCurrentContext,
              presentedViewController == nil,
              let selectedMessageID,
              messageIDs.contains(selectedMessageID),
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { return }
        let count = messageIDs.count
        let alert = UIAlertController(
            title: count == 1 ? "Delete Message?" : "Delete \(count) Messages?",
            message: nil,
            preferredStyle: .actionSheet,
        )
        if capabilities.canDeleteOnlyForSelf {
            alert.addAction(UIAlertAction(title: "Delete for Me", style: .destructive) { [weak self, weak alert] _ in
                alert?.dismiss(animated: true) { [weak self] in
                    self?.performDelete(
                        messageIDs: messageIDs,
                        revoke: false,
                        sourceLocation: sourceLocation,
                        client: client,
                        accountID: accountID,
                    )
                }
            })
        }
        if capabilities.canDeleteForAllUsers {
            alert.addAction(UIAlertAction(title: "Delete for Everyone", style: .destructive) { [
                weak self,
                weak alert,
            ] _ in
                alert?.dismiss(animated: true) { [weak self] in
                    self?.performDelete(
                        messageIDs: messageIDs,
                        revoke: true,
                        sourceLocation: sourceLocation,
                        client: client,
                        accountID: accountID,
                    )
                }
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = moreButton
        alert.popoverPresentationController?.sourceRect = moreButton.bounds
        present(alert, animated: true)
    }

    private func performDelete(
        messageIDs: [Int64],
        revoke: Bool,
        sourceLocation: ChatLocation,
        client: TDLibClient,
        accountID: UUID,
    ) {
        guard deleteTask == nil,
              exportTask == nil,
              forwardTask == nil,
              openInChatTask == nil,
              openInChatDismissalGeneration == nil,
              presentedViewController == nil,
              hasCurrentContext,
              let selectedMessageID,
              messageIDs.contains(selectedMessageID),
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { return }
        let generation = UUID()
        deleteGeneration = generation
        setActionBusy(true, source: .more)
        deleteTask = Task { [weak self] in
            guard let self else { return }
            var mutationStarted = false
            do {
                let capabilities = try await deleteCapabilities(
                    messageIDs: messageIDs,
                    sourceLocation: sourceLocation,
                    client: client,
                    accountID: accountID,
                    generation: generation,
                    selectedMessageID: selectedMessageID,
                )
                guard revoke ? capabilities.canDeleteForAllUsers : capabilities.canDeleteOnlyForSelf else {
                    throw MediaGalleryDeleteError.noPermission
                }
                try Task.checkCancellation()
                guard deleteGeneration == generation,
                      hasCurrentContext,
                      self.selectedMessageID == selectedMessageID,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { throw MediaGalleryDeleteError.accountChanged }
                let deletionSnapshot = selectedGalleryCell()?.makeTransitionSnapshot()
                mutationStarted = true
                _ = try await client.deleteMessages(
                    chatId: sourceLocation.chatID,
                    messageIds: messageIDs,
                    revoke: revoke,
                )
                for messageID in messageIDs {
                    if let owner = videoPlaybackOwners.removeValue(forKey: messageID) {
                        owner.confirmPermanentDeletionFromGallery()
                        owner.galleryController = nil
                    }
                }
                try Task.checkCancellation()
                guard deleteGeneration == generation,
                      hasCurrentContext,
                      !isBeingDismissed
                else { return }
                finishDelete(generation: generation)
                forcedDismissalSnapshot = deletionSnapshot
                forcesFadeDismissal = true
                shouldReleasePlaybackOwnersAfterDisappearance = true
                dismiss(animated: true)
            } catch is CancellationError {
                finishDelete(generation: generation)
            } catch {
                guard deleteGeneration == generation,
                      hasCurrentContext,
                      !isBeingDismissed
                else { return }
                finishDelete(generation: generation)
                if error is MediaGalleryDeleteError {
                    presentDeleteError(error)
                } else if mutationStarted {
                    presentDeleteError(MediaGalleryDeleteError.notConfirmed)
                } else {
                    presentDeleteError(MediaGalleryDeleteError.unavailable)
                }
            }
        }
    }

    private func validateDeleteContext(
        accountID: UUID,
        clientID: Int32,
        generation: UUID,
        selectedIdentity: MediaGalleryMessageIdentity,
        resolvedIdentity: MediaGalleryMessageIdentity,
    ) throws {
        guard deleteGeneration == generation,
              hasCurrentContext,
              !isBeingDismissed,
              selectedMessageID == selectedIdentity.messageID,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == clientID
        else { throw MediaGalleryDeleteError.accountChanged }
        guard resolvedIdentity.chatID == selectedIdentity.chatID,
              resolvedIdentity.messageID == selectedIdentity.messageID,
              !actionRequiresTopicMatch || resolvedIdentity.topic == requiredActionTopic
        else { throw MediaGalleryDeleteError.unavailable }
    }

    private func cancelDelete() {
        deleteGeneration = nil
        deleteTask?.cancel()
        deleteTask = nil
        if exportTask == nil,
           forwardTask == nil,
           openInChatTask == nil,
           openInChatDismissalGeneration == nil,
           isViewLoaded
        {
            setActionBusy(false)
        }
    }

    private func finishDelete(generation: UUID) {
        guard deleteGeneration == generation else { return }
        deleteGeneration = nil
        deleteTask = nil
        setActionBusy(false)
    }

    private func presentDeleteError(_ error: Swift.Error) {
        let message = error.localizedDescription
        UIAccessibility.post(notification: .announcement, argument: message)
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Can't Delete", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func exportSelectedMedia(_ action: MediaGalleryExportAction) {
        guard exportTask == nil,
              deleteTask == nil,
              openInChatTask == nil,
              openInChatDismissalGeneration == nil,
              forwardTask == nil,
              presentedViewController == nil,
              hasCurrentContext,
              messages.indices.contains(selectedIndex),
              let accountID = actionAccountID,
              let client = actionClient,
              let chatID = actionChatID,
              let clientID = actionClientID,
              client.id == clientID,
              let selectedAsset = MediaGalleryExportAsset(messages[selectedIndex]),
              action == .share || selectedAsset.photosKind != nil
        else { return }
        let selectedIdentity = MediaGalleryMessageIdentity(messages[selectedIndex])
        guard selectedIdentity.chatID == chatID else { return }
        let generation = UUID()
        exportGeneration = generation
        setActionBusy(true, source: action == .share ? .share : .more)
        UIAccessibility.post(
            notification: .announcement,
            argument: action == .share ? "Preparing media to share" : "Preparing media to save",
        )
        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let messageRequest = client.getMessage(
                    chatId: selectedIdentity.chatID,
                    messageId: selectedIdentity.messageID,
                )
                async let propertiesRequest = client.getMessageProperties(
                    chatId: selectedIdentity.chatID,
                    messageId: selectedIdentity.messageID,
                )
                let (resolved, properties) = try await (messageRequest, propertiesRequest)
                try Task.checkCancellation()
                let resolvedIdentity = MediaGalleryMessageIdentity(resolved)
                try validateExportContext(
                    accountID: accountID,
                    clientID: clientID,
                    generation: generation,
                    selectedIdentity: selectedIdentity,
                    resolvedIdentity: resolvedIdentity,
                )
                try validateExportPermission(message: resolved, properties: properties)
                guard let asset = MediaGalleryExportAsset(resolved) else {
                    throw MediaGallerySaveError.messageUnavailable
                }
                guard action == .share || asset.photosKind != nil else {
                    throw MediaGallerySaveError.messageUnavailable
                }
                let localURL = try await resolvedExportURL(for: asset, client: client)
                try Task.checkCancellation()
                try validateExportContext(
                    accountID: accountID,
                    clientID: clientID,
                    generation: generation,
                    selectedIdentity: selectedIdentity,
                    resolvedIdentity: resolvedIdentity,
                )
                if action == .saveToPhotos {
                    var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                    if authorization == .notDetermined {
                        authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                    }
                    guard authorization == .authorized || authorization == .limited else {
                        throw MediaGallerySaveError.photosAccessDenied
                    }
                }
                try Task.checkCancellation()
                let (latestMessage, latestProperties) = try await (
                    client.getMessage(
                        chatId: selectedIdentity.chatID,
                        messageId: selectedIdentity.messageID,
                    ),
                    client.getMessageProperties(
                        chatId: selectedIdentity.chatID,
                        messageId: selectedIdentity.messageID,
                    ),
                )
                try Task.checkCancellation()
                let latestIdentity = MediaGalleryMessageIdentity(latestMessage)
                try validateExportContext(
                    accountID: accountID,
                    clientID: clientID,
                    generation: generation,
                    selectedIdentity: selectedIdentity,
                    resolvedIdentity: latestIdentity,
                )
                try validateExportPermission(message: latestMessage, properties: latestProperties)
                guard let latestAsset = MediaGalleryExportAsset(latestMessage),
                      latestAsset.fileID == asset.fileID
                else { throw MediaGallerySaveError.messageUnavailable }
                var completedShareLease: MediaGalleryTemporaryFileLease?
                if action == .saveToPhotos {
                    let convertedLease = latestAsset.requiresWebPStillConversion
                        ? try await preparedWebPStillLease(sourceURL: localURL)
                        : nil
                    let photosURL = convertedLease?.fileURL ?? localURL
                    let filename = try await validatedPhotosFilename(for: latestAsset, localURL: photosURL)
                    try Task.checkCancellation()
                    let (commitMessage, commitProperties) = try await (
                        client.getMessage(
                            chatId: selectedIdentity.chatID,
                            messageId: selectedIdentity.messageID,
                        ),
                        client.getMessageProperties(
                            chatId: selectedIdentity.chatID,
                            messageId: selectedIdentity.messageID,
                        ),
                    )
                    try Task.checkCancellation()
                    let commitIdentity = MediaGalleryMessageIdentity(commitMessage)
                    try validateExportContext(
                        accountID: accountID,
                        clientID: clientID,
                        generation: generation,
                        selectedIdentity: selectedIdentity,
                        resolvedIdentity: commitIdentity,
                    )
                    try validateExportPermission(message: commitMessage, properties: commitProperties)
                    guard let commitAsset = MediaGalleryExportAsset(commitMessage),
                          commitAsset.fileID == latestAsset.fileID
                    else { throw MediaGallerySaveError.messageUnavailable }
                    try await saveToPhotos(asset: commitAsset, localURL: photosURL, filename: filename)
                    convertedLease?.cleanup()
                } else {
                    let shareLease = try await preparedShareLease(asset: latestAsset, sourceURL: localURL)
                    try Task.checkCancellation()
                    let (commitMessage, commitProperties) = try await (
                        client.getMessage(
                            chatId: selectedIdentity.chatID,
                            messageId: selectedIdentity.messageID,
                        ),
                        client.getMessageProperties(
                            chatId: selectedIdentity.chatID,
                            messageId: selectedIdentity.messageID,
                        ),
                    )
                    try Task.checkCancellation()
                    let commitIdentity = MediaGalleryMessageIdentity(commitMessage)
                    try validateExportContext(
                        accountID: accountID,
                        clientID: clientID,
                        generation: generation,
                        selectedIdentity: selectedIdentity,
                        resolvedIdentity: commitIdentity,
                    )
                    try validateExportPermission(message: commitMessage, properties: commitProperties)
                    guard let commitAsset = MediaGalleryExportAsset(commitMessage),
                          commitAsset.fileID == latestAsset.fileID
                    else { throw MediaGallerySaveError.messageUnavailable }
                    completedShareLease = shareLease
                }
                try Task.checkCancellation()
                guard exportGeneration == generation, hasCurrentContext else {
                    throw MediaGallerySaveError.contextChanged
                }
                finishExport(generation: generation)
                if let completedShareLease {
                    presentShareSheet(completedShareLease)
                } else if let saveSuccessText = latestAsset.saveSuccessText {
                    showActionStatus(saveSuccessText)
                }
            } catch is CancellationError {
                finishExport(generation: generation)
            } catch {
                guard exportGeneration == generation,
                      hasCurrentContext,
                      !isBeingDismissed
                else { return }
                finishExport(generation: generation)
                let displayedError = error is MediaGallerySaveError
                    ? error
                    : MediaGallerySaveError.downloadFailed
                presentExportError(displayedError, action: action)
            }
        }
    }

    private func validateExportContext(
        accountID: UUID,
        clientID: Int32,
        generation: UUID,
        selectedIdentity: MediaGalleryMessageIdentity,
        resolvedIdentity: MediaGalleryMessageIdentity,
    ) throws {
        guard exportGeneration == generation,
              hasCurrentContext,
              !isBeingDismissed,
              selectedMessageID == selectedIdentity.messageID,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == clientID
        else { throw MediaGallerySaveError.contextChanged }
        guard resolvedIdentity.chatID == selectedIdentity.chatID,
              resolvedIdentity.messageID == selectedIdentity.messageID,
              !actionRequiresTopicMatch || resolvedIdentity.topic == requiredActionTopic
        else { throw MediaGallerySaveError.messageUnavailable }
    }

    private func validateExportPermission(
        message: Message,
        properties: MessageProperties,
    ) throws {
        if case .messagePaidMedia = message.content {
            throw MediaGallerySaveError.protectedContent
        }
        guard properties.canBeSaved,
              !properties.hasProtectedContentByCurrentUser,
              !properties.hasProtectedContentByOtherUser,
              message.selfDestructType == nil,
              message.selfDestructIn == 0,
              let asset = MediaGalleryExportAsset(message),
              !asset.isSecretMedia
        else { throw MediaGallerySaveError.protectedContent }
    }

    private func resolvedExportURL(
        for asset: MediaGalleryExportAsset,
        client: TDLibClient,
    ) async throws -> URL {
        if let path = asset.completedLocalPath,
           FileManager.default.fileExists(atPath: path)
        {
            return URL(filePath: path)
        }
        let downloaded = try await client.downloadFile(
            fileId: asset.fileID,
            limit: 0,
            offset: 0,
            priority: 16,
            synchronous: true,
        )
        try Task.checkCancellation()
        guard downloaded.id == asset.fileID,
              downloaded.local.isDownloadingCompleted,
              !downloaded.local.path.isEmpty,
              FileManager.default.fileExists(atPath: downloaded.local.path)
        else { throw MediaGallerySaveError.downloadFailed }
        return URL(filePath: downloaded.local.path)
    }

    private func preparedShareLease(
        asset: MediaGalleryExportAsset,
        sourceURL: URL,
    ) async throws -> MediaGalleryTemporaryFileLease {
        let fileExtension = await validatedShareFileExtension(for: asset, sourceURL: sourceURL)
        let filename = sanitizedExportFilename(
            asset.originalFilename,
            fallbackStem: "bettertg-media",
            fileExtension: fileExtension,
        )
        let directoryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-share-\(UUID().uuidString)", isDirectory: true)
        let destinationURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                do {
                    try fileManager.linkItem(at: sourceURL, to: destinationURL)
                } catch {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
                return MediaGalleryTemporaryFileLease(
                    directoryURL: directoryURL,
                    fileURL: destinationURL,
                )
            } catch {
                try? fileManager.removeItem(at: directoryURL)
                throw MediaGallerySaveError.downloadFailed
            }
        }.value
    }

    private func validatedShareFileExtension(
        for asset: MediaGalleryExportAsset,
        sourceURL: URL,
    ) async -> String {
        if let shareFileExtension = asset.shareFileExtension {
            return shareFileExtension
        }
        if let imageExtension = await Task.detached(priority: .userInitiated, operation: { () -> String? in
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  let typeIdentifier = CGImageSourceGetType(source),
                  let type = UTType(typeIdentifier as String),
                  type.conforms(to: .image),
                  let preferredExtension = type.preferredFilenameExtension
            else { return nil }
            return preferredExtension == "jpeg" ? "jpg" : preferredExtension
        })
        .value {
            return imageExtension
        }
        if let type = UTType(mimeType: asset.mimeType),
           let preferredExtension = type.preferredFilenameExtension
        {
            return preferredExtension == "jpeg" ? "jpg" : preferredExtension
        }
        return "bin"
    }

    private func preparedWebPStillLease(
        sourceURL: URL,
    ) async throws -> MediaGalleryTemporaryFileLease {
        guard let pngData = await AnimatedWebPRepository.firstFramePNGData(at: sourceURL.path) else {
            throw MediaGallerySaveError.messageUnavailable
        }
        try Task.checkCancellation()
        let directoryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-sticker-export-\(UUID().uuidString)", isDirectory: true)
        let destinationURL = directoryURL.appendingPathComponent("bettertg-sticker-frame.png")
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try pngData.write(to: destinationURL, options: .atomic)
                return MediaGalleryTemporaryFileLease(
                    directoryURL: directoryURL,
                    fileURL: destinationURL,
                )
            } catch {
                try? fileManager.removeItem(at: directoryURL)
                throw MediaGallerySaveError.downloadFailed
            }
        }.value
    }

    private func validatedPhotosFilename(
        for asset: MediaGalleryExportAsset,
        localURL: URL,
    ) async throws -> String {
        switch asset.photosKind {
        case .photo:
            let fileExtension = try await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(localURL as CFURL, nil),
                      CGImageSourceGetCount(source) > 0,
                      let typeIdentifier = CGImageSourceGetType(source),
                      let type = UTType(typeIdentifier as String),
                      type.conforms(to: .image),
                      let preferredExtension = type.preferredFilenameExtension
                else { throw MediaGallerySaveError.messageUnavailable }
                return preferredExtension == "jpeg" ? "jpg" : preferredExtension
            }.value
            return sanitizedExportFilename(
                asset.originalFilename,
                fallbackStem: "bettertg-photo",
                fileExtension: fileExtension,
            )
        case .video:
            let supportedMimeTypes: Set = ["video/mp4", "video/quicktime", "video/x-m4v"]
            let supportedExtensions: Set = ["m4v", "mov", "mp4"]
            let originalExtension = URL(filePath: asset.originalFilename).pathExtension.lowercased()
            guard supportedMimeTypes.contains(asset.mimeType)
                || asset.mimeType.isEmpty && supportedExtensions.contains(originalExtension)
            else { throw MediaGallerySaveError.unsupportedVideo }
            let videoAsset = AVURLAsset(url: localURL)
            let isPlayable = try await videoAsset.load(.isPlayable)
            let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            guard isPlayable, !videoTracks.isEmpty else { throw MediaGallerySaveError.unsupportedVideo }
            let fileExtension =
                switch asset.mimeType {
                case "video/quicktime": "mov"
                case "video/x-m4v": "m4v"
                default: supportedExtensions.contains(originalExtension) ? originalExtension : "mp4"
                }
            return sanitizedExportFilename(
                asset.originalFilename,
                fallbackStem: "bettertg-video",
                fileExtension: fileExtension,
            )
        case nil:
            throw MediaGallerySaveError.messageUnavailable
        }
    }

    private func sanitizedExportFilename(
        _ filename: String,
        fallbackStem: String,
        fileExtension: String,
    ) -> String {
        let normalized = filename.replacingOccurrences(of: "\\", with: "/")
        let lastComponent = URL(filePath: normalized).lastPathComponent
        let rawStem = URL(filePath: lastComponent).deletingPathExtension().lastPathComponent
        let sanitized = rawStem.filter { character in
            character.unicodeScalars.allSatisfy { scalar in
                !CharacterSet.controlCharacters.contains(scalar)
                    && scalar != "/"
                    && scalar != "\\"
                    && scalar != ":"
            }
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = sanitized.isEmpty ? fallbackStem : String(sanitized.prefix(96))
        return "\(stem).\(fileExtension.lowercased())"
    }

    private func saveToPhotos(
        asset: MediaGalleryExportAsset,
        localURL: URL,
        filename: String,
    ) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            options.shouldMoveFile = false
            request.addResource(
                with: asset.photosKind == .photo ? .photo : .video,
                fileURL: localURL,
                options: options,
            )
            request.creationDate = asset.creationDate
        }
    }

    private func presentShareSheet(_ lease: MediaGalleryTemporaryFileLease) {
        guard hasCurrentContext, presentedViewController == nil else { return }
        activeShareLease?.cleanup()
        activeShareLease = lease
        let activity = UIActivityViewController(activityItems: [lease.fileURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = shareButton
        activity.popoverPresentationController?.sourceRect = shareButton.bounds
        activity.completionWithItemsHandler = { [weak self, lease] _, _, _, _ in
            DispatchQueue.main.async {
                if self?.activeShareLease === lease {
                    self?.activeShareLease = nil
                }
                lease.cleanup()
            }
        }
        present(activity, animated: true)
    }

    private func cancelExport() {
        exportGeneration = nil
        exportTask?.cancel()
        exportTask = nil
        if openInChatTask == nil,
           openInChatDismissalGeneration == nil,
           forwardTask == nil,
           deleteTask == nil,
           isViewLoaded
        {
            setActionBusy(false)
        }
    }

    private func finishExport(generation: UUID) {
        guard exportGeneration == generation else { return }
        exportGeneration = nil
        exportTask = nil
        setActionBusy(false)
    }

    private func showActionStatus(_ message: String) {
        statusResetTask?.cancel()
        actionStatusText = message
        updateCounter()
        UIAccessibility.post(notification: .announcement, argument: message)
        statusResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, actionStatusText == message else { return }
            clearActionStatus()
        }
    }

    private func clearActionStatus() {
        statusResetTask?.cancel()
        statusResetTask = nil
        guard actionStatusText != nil else { return }
        actionStatusText = nil
        if isViewLoaded {
            updateCounter()
        }
    }

    private func presentExportError(
        _ error: Swift.Error,
        action: MediaGalleryExportAction,
    ) {
        let message = error.localizedDescription
        UIAccessibility.post(notification: .announcement, argument: message)
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: action == .share ? "Couldn't Share Media" : "Couldn't Save Media",
            message: message,
            preferredStyle: .alert,
        )
        if (error as? MediaGallerySaveError)?.shouldOfferSettings == true,
           let settingsURL = URL(string: UIApplication.openSettingsURLString)
        {
            alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
                UIApplication.shared.open(settingsURL)
            })
        }
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    private func cancelOpenInChat() {
        openInChatGeneration = nil
        openInChatDismissalGeneration = nil
        openInChatTask?.cancel()
        openInChatTask = nil
        if exportTask == nil, forwardTask == nil, deleteTask == nil, isViewLoaded {
            setActionBusy(false)
        }
    }

    private func finishOpenInChat(generation: UUID) {
        guard openInChatGeneration == generation else { return }
        openInChatGeneration = nil
        if openInChatDismissalGeneration == generation {
            openInChatDismissalGeneration = nil
        }
        openInChatTask = nil
        setActionBusy(false)
    }

    private func setActionBusy(
        _ busy: Bool,
        source: MediaGalleryActionButton? = nil,
    ) {
        moreButton.isEnabled = !busy
        shareButton.isEnabled = !busy
        collectionView.isScrollEnabled = !busy
        moreButton.imageView?.alpha = busy && source == .more ? 0 : 1
        shareButton.imageView?.alpha = busy && source == .share ? 0 : 1
        if busy, source == .more {
            moreActivityIndicator.startAnimating()
        } else {
            moreActivityIndicator.stopAnimating()
        }
        if busy, source == .share {
            shareActivityIndicator.startAnimating()
        } else {
            shareActivityIndicator.stopAnimating()
        }
    }

    private func presentOpenInChatError(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Message Unavailable",
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func selectedGalleryCell() -> MediaGalleryCell? {
        guard messages.indices.contains(selectedIndex) else { return nil }
        loadViewIfNeeded()
        view.layoutIfNeeded()
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        if collectionView.cellForItem(at: indexPath) == nil {
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
            collectionView.layoutIfNeeded()
        }
        return collectionView.cellForItem(at: indexPath) as? MediaGalleryCell
    }

    private func visibleSelectedGalleryCell() -> MediaGalleryCell? {
        guard messages.indices.contains(selectedIndex) else { return nil }
        return collectionView.cellForItem(
            at: IndexPath(item: selectedIndex, section: 0),
        ) as? MediaGalleryCell
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
        guard hasCurrentContext, !didReleasePlaybackOwners else { return cell }
        let message = messages[indexPath.item]
        cell.configure(message: message, videoPlaybackOwner: playbackOwner(for: message))
        return cell
    }
}

// MARK: - MediaGalleryTransitionController

private final class MediaGalleryTransitionController: NSObject, UIViewControllerTransitioningDelegate {
    private(set) var isInteractiveDismissalInProgress = false

    private var dismissalInteractionController: UIPercentDrivenInteractiveTransition?
    private var interactiveDismissalCompletion: ((Bool) -> Void)?

    func animationController(
        forPresented presented: UIViewController,
        presenting _: UIViewController,
        source _: UIViewController,
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        guard presented is MediaGalleryViewController else { return nil }
        return MediaGalleryTransitionAnimator(isPresenting: true)
    }

    func animationController(
        forDismissed dismissed: UIViewController,
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        guard dismissed is MediaGalleryViewController else { return nil }
        return MediaGalleryTransitionAnimator(isPresenting: false) { [weak self] completed in
            self?.dismissalTransitionEnded(completed: completed)
        }
    }

    func interactionControllerForDismissal(
        using _: any UIViewControllerAnimatedTransitioning,
    ) -> (any UIViewControllerInteractiveTransitioning)? {
        isInteractiveDismissalInProgress ? dismissalInteractionController : nil
    }

    func beginInteractiveDismissal(
        from gallery: MediaGalleryViewController,
        completion: @escaping (Bool) -> Void,
    ) -> Bool {
        guard !isInteractiveDismissalInProgress,
              gallery.presentingViewController != nil
        else { return false }
        let interactionController = UIPercentDrivenInteractiveTransition()
        interactionController.completionCurve = .easeOut
        interactionController.completionSpeed = 0.85
        dismissalInteractionController = interactionController
        interactiveDismissalCompletion = completion
        isInteractiveDismissalInProgress = true
        gallery.dismiss(animated: true)
        return true
    }

    func updateInteractiveDismissal(_ progress: CGFloat) {
        guard isInteractiveDismissalInProgress else { return }
        dismissalInteractionController?.update(min(1, max(0, progress)))
    }

    func finishInteractiveDismissal() {
        guard isInteractiveDismissalInProgress else { return }
        dismissalInteractionController?.finish()
    }

    func cancelInteractiveDismissal() {
        guard isInteractiveDismissalInProgress else { return }
        dismissalInteractionController?.cancel()
    }

    private func dismissalTransitionEnded(completed: Bool) {
        guard isInteractiveDismissalInProgress else { return }
        isInteractiveDismissalInProgress = false
        dismissalInteractionController = nil
        let completion = interactiveDismissalCompletion
        interactiveDismissalCompletion = nil
        completion?(completed)
    }
}

// MARK: - MediaGalleryTransitionCompletionGate

@MainActor private final class MediaGalleryTransitionCompletionGate {
    private var didFinish = false

    func finish(
        completed: Bool,
        commit: () -> Void,
        cleanup: () -> Void,
    ) {
        guard !didFinish else { return }
        didFinish = true
        if completed {
            commit()
        }
        cleanup()
    }
}

// MARK: - MediaGalleryTransitionAnimator

private final class MediaGalleryTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private static let duration = TimeInterval(0.38)

    private let isPresenting: Bool
    private let transitionEnded: ((Bool) -> Void)?

    init(isPresenting: Bool, transitionEnded: ((Bool) -> Void)? = nil) {
        self.isPresenting = isPresenting
        self.transitionEnded = transitionEnded
    }

    func transitionDuration(using _: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        Self.duration
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        if isPresenting {
            animatePresentation(using: transitionContext)
        } else {
            animateDismissal(using: transitionContext)
        }
    }

    func animationEnded(_ transitionCompleted: Bool) {
        transitionEnded?(transitionCompleted)
    }

    private func animatePresentation(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let gallery = transitionContext.viewController(forKey: .to) as? MediaGalleryViewController,
              let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }
        let container = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: gallery)
        container.addSubview(toView)
        toView.layoutIfNeeded()
        guard let target = gallery.transitionSource,
              let snapshot = target.snapshotView,
              let sourceFrame = target.frame(in: container),
              let destinationFrame = gallery.transitionContentFrame(in: container)
        else {
            animateFade(
                appearingView: toView,
                disappearingView: nil,
                transitionContext: transitionContext,
            ) { completed in
                if !completed {
                    gallery.presentationTransitionDidCancel()
                }
            }
            return
        }
        let sourceView = target.validatedSourceView
        let sourceWasHidden = sourceView?.isHidden ?? false
        sourceView?.isHidden = true
        snapshot.frame = sourceFrame
        snapshot.layer.cornerRadius = target.cornerRadius
        snapshot.layer.maskedCorners = target.maskedCorners
        snapshot.clipsToBounds = true
        container.addSubview(snapshot)
        toView.alpha = 0
        UIView.animate(
            withDuration: Self.duration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            toView.alpha = 1
            snapshot.frame = destinationFrame
            snapshot.layer.cornerRadius = 0
        } completion: { _ in
            let completed = !transitionContext.transitionWasCancelled
            if target.validatedSourceView === sourceView {
                sourceView?.isHidden = sourceWasHidden
            }
            snapshot.removeFromSuperview()
            if !completed {
                toView.removeFromSuperview()
            }
            transitionContext.completeTransition(completed)
            if !completed {
                gallery.presentationTransitionDidCancel()
            }
        }
    }

    private func animateDismissal(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let gallery = transitionContext.viewController(forKey: .from) as? MediaGalleryViewController,
              let toController = transitionContext.viewController(forKey: .to),
              let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }
        let container = transitionContext.containerView
        let completionGate = MediaGalleryTransitionCompletionGate()
        toView.frame = transitionContext.finalFrame(for: toController)
        container.insertSubview(toView, belowSubview: fromView)
        toView.layoutIfNeeded()
        let sourceTarget = gallery.isSelectedPictureInPictureRetained
            ? nil
            : gallery.currentTransitionTarget()
        let sourceView = sourceTarget?.validatedSourceView
        let sourceWasHidden = sourceView?.isHidden ?? false
        let snapshot = gallery.makeTransitionSnapshot()
        let sourceFrame = sourceTarget?.frame(in: container)
        let startFrame = gallery.transitionContentFrame(in: container)
        sourceView?.isHidden = true
        guard let snapshot, let sourceTarget, let sourceFrame, let startFrame else {
            if let snapshot, let startFrame {
                snapshot.frame = fromView.convert(startFrame, from: container)
                snapshot.clipsToBounds = true
                fromView.addSubview(snapshot)
            }
            animateFade(
                appearingView: toView,
                disappearingView: fromView,
                transitionContext: transitionContext,
            ) { completed in
                completionGate.finish(
                    completed: completed,
                    commit: { gallery.preparePlaybackOwnersForDismissalTransition() },
                    cleanup: {
                        if sourceTarget?.validatedSourceView === sourceView {
                            sourceView?.isHidden = sourceWasHidden
                        }
                        snapshot?.removeFromSuperview()
                    },
                )
            }
            return
        }
        snapshot.frame = startFrame
        snapshot.clipsToBounds = true
        snapshot.layer.cornerRadius = 0
        container.addSubview(snapshot)
        UIView.animate(
            withDuration: Self.duration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
        ) {
            fromView.alpha = 0
            snapshot.frame = sourceFrame
            snapshot.layer.cornerRadius = sourceTarget.cornerRadius
            snapshot.layer.maskedCorners = sourceTarget.maskedCorners
        } completion: { _ in
            let completed = !transitionContext.transitionWasCancelled
            if !completed {
                fromView.alpha = 1
            }
            transitionContext.completeTransition(completed)
            completionGate.finish(
                completed: completed,
                commit: { gallery.preparePlaybackOwnersForDismissalTransition() },
                cleanup: {
                    if sourceTarget.validatedSourceView === sourceView {
                        sourceView?.isHidden = sourceWasHidden
                    }
                    snapshot.removeFromSuperview()
                },
            )
        }
    }

    private func animateFade(
        appearingView: UIView,
        disappearingView: UIView?,
        transitionContext: any UIViewControllerContextTransitioning,
        completion: ((Bool) -> Void)? = nil,
    ) {
        appearingView.alpha = 0
        UIView.animate(
            withDuration: Self.duration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
        ) {
            appearingView.alpha = 1
            disappearingView?.alpha = 0
        } completion: { _ in
            let completed = !transitionContext.transitionWasCancelled
            if !completed {
                appearingView.alpha = 0
                disappearingView?.alpha = 1
            }
            transitionContext.completeTransition(completed)
            completion?(completed)
        }
    }
}

// MARK: - GallerySampleBufferPictureInPictureAdapter

final class GallerySampleBufferPictureInPictureAdapter: NSObject,
    AVPictureInPictureSampleBufferPlaybackDelegate,
    @unchecked Sendable
{
    private struct Snapshot {
        let currentTime: TimeInterval
        let duration: TimeInterval
        let isPaused: Bool
    }

    private let lock = NSLock()
    private weak var controller: AVPictureInPictureController?
    private weak var owner: GalleryVideoPlaybackOwner?
    private var snapshot = Snapshot(currentTime: 0, duration: 0, isPaused: true)

    init(owner: GalleryVideoPlaybackOwner) {
        self.owner = owner
    }

    func update(
        controller: AVPictureInPictureController?,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPaused: Bool,
    ) {
        lock.lock()
        self.controller = controller
        snapshot = Snapshot(
            currentTime: currentTime.isFinite ? max(0, currentTime) : 0,
            duration: duration.isFinite ? max(0, duration) : 0,
            isPaused: isPaused,
        )
        lock.unlock()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool,
    ) {
        guard matches(pictureInPictureController) else { return }
        Task { @MainActor [weak owner] in
            owner?.setSampleBufferPictureInPicturePlaying(playing)
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController,
    ) -> CMTimeRange {
        guard let snapshot = snapshot(for: pictureInPictureController),
              snapshot.duration > 0
        else { return .invalid }
        let upperBound = max(snapshot.duration, snapshot.currentTime + 0.001)
        return CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: upperBound, preferredTimescale: 600),
        )
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController,
    ) -> Bool {
        snapshot(for: pictureInPictureController)?.isPaused ?? true
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions,
    ) {
        guard matches(pictureInPictureController) else { return }
        Task { @MainActor [weak owner] in
            owner?.setSampleBufferPictureInPictureRenderSize(newRenderSize)
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping @Sendable () -> Void,
    ) {
        guard matches(pictureInPictureController), skipInterval.seconds.isFinite else {
            completionHandler()
            return
        }
        Task { @MainActor [weak owner] in
            guard let owner else {
                completionHandler()
                return
            }
            owner.skipSampleBufferPictureInPicture(
                by: skipInterval.seconds,
                completion: completionHandler,
            )
        }
    }

    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ pictureInPictureController: AVPictureInPictureController,
    ) -> Bool {
        !matches(pictureInPictureController)
    }

    private func matches(_ controller: AVPictureInPictureController) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.controller === controller
    }

    private func snapshot(
        for controller: AVPictureInPictureController,
    ) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard self.controller === controller else { return nil }
        return snapshot
    }
}

// MARK: - GalleryVideoPlaybackOwner

@MainActor final class GalleryVideoPlaybackOwner: NSObject,
    @preconcurrency AVPictureInPictureControllerDelegate
{
    // MARK: Internal

    let messageID: Int64
    let chatID: Int64
    let tdlib: TDLib
    weak var galleryController: MediaGalleryViewController?
    var onPermanentDeletion: ((GalleryVideoPlaybackOwner) -> Void)?
    var onReturnToInline: ((GalleryVideoPlaybackOwner) -> Bool)?
    private(set) var isDeleted = false

    // MARK: Private

    private let mediaView = GalleryFilePlayerView()
    private lazy var sampleBufferPictureInPictureAdapter =
        GallerySampleBufferPictureInPictureAdapter(owner: self)
    private let allowsPictureInPicture: Bool
    private var pictureInPictureController: AVPictureInPictureController?
    private var pictureInPictureSourceIdentity: GalleryPictureInPictureSourceIdentity?
    private var pictureInPicturePossibleCancellable: AnyCancellable?
    private var pendingPictureInPictureSkipCompletion: (() -> Void)?
    private var pictureInPictureSkipGeneration = UInt64.zero
    private var pictureInPictureSkipTimeout: DispatchWorkItem?
    private var isInvalidated = false
    private var isPlaybackVisible = false
    private var isPictureInPictureStartRequested = false
    private var isPictureInPictureActive = false
    private var ignoresPictureInPictureControllerActiveState = false
    private var pendingInvalidationAfterPictureInPicture = false
    private var pictureInPictureAudioSessionToken: UUID?
    private var pictureInPictureStartTimeout: DispatchWorkItem?
    private var pictureInPictureStopTimeout: DispatchWorkItem?
    private var isPictureInPictureStopRequested = false
    private var rejectsLatePictureInPictureStart = false
    private var mediaTakeoverCancellable: AnyCancellable?
    private var tdUpdateCancellables = Set<AnyCancellable>()
    private weak var attachmentContainer: UIView?
    private var attachmentToken: VideoPlaybackAttachmentToken?
    private var attachmentContext: VideoPlaybackAttachmentContext?

    var isPictureInPictureRetained: Bool {
        isPictureInPictureStartRequested
            || isPictureInPictureActive
            || isPictureInPictureStopRequested
            || !ignoresPictureInPictureControllerActiveState
            && pictureInPictureController?.isPictureInPictureActive == true
    }

    var isBorrowedFromInline: Bool {
        onReturnToInline != nil
    }

    var isAttachedToGallery: Bool {
        galleryController != nil || attachmentContext == .fullscreen || isPictureInPictureRetained
    }

    init?(
        message: Message,
        tdlib: TDLib,
        deferPlaybackUntilVisible: Bool = false,
    ) {
        guard case .messageVideo(let video) = message.content else { return nil }
        self.tdlib = tdlib
        self.chatID = message.chatId
        self.messageID = message.id
        self.allowsPictureInPicture = !video.isSecret
        super.init()
        mediaView.configure(
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
            vodRanges: tdlib.vodRanges,
            deferPlaybackUntilVisible: deferPlaybackUntilVisible,
        )
        configurePictureInPicture()
        observeMessageDeletion()
    }

    #if DEBUG
        private init(
            probeMessageID: Int64,
            videoFile: File? = nil,
            vodRanges: TDLibVODRangeCoordinator = TDLib.shared.vodRanges,
            mimeType: String = "video/mp4",
            fileName: String = "inline-handoff-probe.mp4",
            supportsStreaming: Bool = false,
        ) {
            self.tdlib = .shared
            self.chatID = 0
            self.messageID = probeMessageID
            self.allowsPictureInPicture = true
            super.init()
            if let videoFile {
                mediaView.configure(
                    file: videoFile,
                    thumbnail: nil,
                    minithumbnail: nil,
                    canPlay: true,
                    loops: false,
                    mimeType: mimeType,
                    fileName: fileName,
                    supportsStreaming: supportsStreaming,
                    vodRanges: vodRanges,
                    deferPlaybackUntilVisible: true,
                )
            }
            configurePictureInPicture()
            observeMessageDeletion()
        }
    #endif

    #if DEBUG
        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-gallery-owner") else { return }
            Task { @MainActor in await runDebugProbe() }
        }
    #endif

    #if DEBUG
        private static func runDebugProbe() async {
            let result: String
            var probeFailed = false
            let probeURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-inline-handoff-probe.mp4")
            try? FileManager.default.removeItem(at: probeURL)
            let owner: GalleryVideoPlaybackOwner
            let vodBackend: TDLibVODProbeBackend?
            do {
                _ = try await VideoNoteAssetWriter.makeDebugSegment(
                    outputURL: probeURL,
                    duration: 30,
                    frameSeed: 930,
                )
                let attributes = try FileManager.default.attributesOfItem(atPath: probeURL.path)
                guard let size = (attributes[.size] as? NSNumber)?.int64Value,
                      size > TDLibVODRangeSource.normalFetchSize
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let network = TDLibVODProbeNetwork(available: true)
                let backend = TDLibVODProbeBackend(
                    fileURL: probeURL,
                    fileSize: size,
                    network: network,
                )
                await backend.setAutoFulfill(true)
                await backend.setDownloadDelay(.seconds(2))
                let vodRanges = TDLibVODRangeCoordinator(
                    accountID: "probe-inline-handoff",
                    client: backend.client,
                    requestTimeout: .seconds(3),
                )
                owner = await GalleryVideoPlaybackOwner(
                    probeMessageID: 9001,
                    videoFile: backend.file(expectedSize: size * 2),
                    vodRanges: vodRanges,
                    supportsStreaming: true,
                )
                vodBackend = backend
            } catch {
                owner = GalleryVideoPlaybackOwner(probeMessageID: 9001)
                vodBackend = nil
            }
            let firstContainer = UIView()
            let secondContainer = UIView()
            let viewIdentifier = ObjectIdentifier(owner.mediaView)

            let inlineToken = owner.attach(to: firstContainer, context: .inline)
            let startsPaused = inlineToken != nil
                && !owner.isPlaybackVisible
                && owner.mediaView.superview === firstContainer
                && owner.mediaView.debugIsInlinePresentation
            if let inlineToken {
                owner.setPlaybackVisible(true, attachment: inlineToken)
            }
            let becameVisible = owner.isPlaybackVisible
            let inlinePlaybackReady = await waitUntil {
                owner.mediaView.debugCurrentItemIdentifier != nil
                    && owner.mediaView.debugPlaybackTime >= 0.1
                    && owner.mediaView.debugIsMuted
            }
            let inlineItemIdentifier = owner.mediaView.debugCurrentItemIdentifier
            let inlinePlaybackTime = owner.mediaView.debugPlaybackTime
            let transferCancelBaseline: Int =
 if let vodBackend {
                await vodBackend.completedCancelCount
            } else {
                -1
            }
            let fullscreenToken = owner.attach(to: secondContainer, context: .fullscreen)
            if let inlineToken {
                owner.setPlaybackVisible(false, attachment: inlineToken)
                owner.detach(attachment: inlineToken)
            }
            let staleInlineCallbacksIgnored = owner.isPlaybackVisible
                && owner.mediaView.superview === secondContainer
                && !owner.mediaView.debugIsInlinePresentation
            let reusedExactView = ObjectIdentifier(owner.mediaView) == viewIdentifier
                && owner.mediaView.superview === secondContainer
            try? await Task<Never, Never>.sleep(for: .milliseconds(120))
            let itemAndPlayheadContinuous = inlinePlaybackReady
                && inlineItemIdentifier != nil
                && owner.mediaView.debugCurrentItemIdentifier == inlineItemIdentifier
                && owner.mediaView.debugPlaybackTime >= inlinePlaybackTime
                && !owner.mediaView.debugIsMuted
            let returnGallery = MediaGalleryViewController(messages: [], selection: 0)
            owner.galleryController = returnGallery
            owner.onReturnToInline = { _ in true }
            let borrowedOwnerReturned = owner.returnToInlineIfAvailable()
            let detachedWithoutInvalidation = borrowedOwnerReturned
                && !owner.isInvalidated
                && !owner.isPlaybackVisible
                && owner.mediaView.superview == nil
            let returnedInlineToken = owner.attach(to: firstContainer, context: .inline)
            if let returnedInlineToken {
                owner.setPlaybackVisible(true, attachment: returnedInlineToken)
            }
            if let fullscreenToken {
                owner.setPlaybackVisible(false, attachment: fullscreenToken)
                owner.detach(attachment: fullscreenToken)
            }
            try? await Task<Never, Never>.sleep(for: .milliseconds(80))
            let returnedInlineContinuity = borrowedOwnerReturned
                && returnedInlineToken != nil
                && owner.isPlaybackVisible
                && owner.mediaView.superview === firstContainer
                && owner.mediaView.debugIsInlinePresentation
                && owner.mediaView.debugIsMuted
                && owner.mediaView.debugCurrentItemIdentifier == inlineItemIdentifier
                && owner.mediaView.debugPlaybackTime >= inlinePlaybackTime
            let vodTransferContinuous: Bool
            if let vodBackend {
                let downloadCalls = await vodBackend.downloadCalls
                let completedCancelCount = await vodBackend.completedCancelCount
                vodTransferContinuous = !downloadCalls.isEmpty
                    && downloadCalls.allSatisfy { !$0.isFullDownload }
                    && completedCancelCount == transferCancelBaseline
            } else {
                vodTransferContinuous = false
            }
            let readinessGated = owner.mediaView.pictureInPictureControlIsHidden
            var terminalRequestActive = false
            let terminalCancelBaseline: Int
            if let vodBackend {
                terminalRequestActive = await waitUntilAsync(timeout: .seconds(1)) {
                    await vodBackend.activeDownloadCount > 0
                }
                if !terminalRequestActive {
                    owner.mediaView.debugForceVODSeek(to: 25)
                    terminalRequestActive = await waitUntilAsync {
                        await vodBackend.activeDownloadCount > 0
                    }
                }
                terminalCancelBaseline = await vodBackend.completedCancelCount
            } else {
                terminalCancelBaseline = -1
            }
            owner.invalidate()
            let terminalLeaseCancelled: Bool =
 if let vodBackend, terminalRequestActive {
                await waitUntilAsync {
                    await vodBackend.completedCancelCount == terminalCancelBaseline + 1
                }
            } else {
                false
            }
            try? FileManager.default.removeItem(at: probeURL)
            let invalidatedCleanly = owner.isInvalidated
                && !owner.isPlaybackVisible
                && owner.mediaView.superview == nil

            let controlsOwner = GalleryVideoPlaybackOwner(probeMessageID: 9004)
            controlsOwner.performPlaybackCommand(.jump(-15))
            controlsOwner.performPlaybackCommand(.jump(15))
            controlsOwner.performPlaybackCommand(.togglePlayback)
            let commandRouting = controlsOwner.mediaView.debugPlaybackCommandProbePassed
            let accessibleControls = controlsOwner.mediaView.debugPlaybackControlsLayoutProbePassed
            let autoHidePolicy = controlsOwner.mediaView.debugControlsAutoHidePolicyProbePassed
            controlsOwner.invalidate()

            let transferredOwner = GalleryVideoPlaybackOwner(probeMessageID: 9002)
            let probeGallery = MediaGalleryViewController(messages: [], selection: 0)
            let coordinator = GalleryPictureInPictureCoordinator.shared
            let preparedTransfer = coordinator.prepare(
                owner: transferredOwner,
                gallery: probeGallery,
                messages: [],
            )
            coordinator.galleryWillDismiss(probeGallery)
            let retainedAcrossDismissal = preparedTransfer && coordinator.isRetaining(transferredOwner)
            coordinator.didFail(owner: transferredOwner)
            let transferCleanedUp = transferredOwner.isInvalidated && coordinator.activeOwner == nil

            let pendingStartOwner = GalleryVideoPlaybackOwner(probeMessageID: 9005)
            let pendingStartGallery = MediaGalleryViewController(messages: [], selection: 0)
            let preparedPendingStart = coordinator.prepare(
                owner: pendingStartOwner,
                gallery: pendingStartGallery,
                messages: [],
            )
            coordinator.galleryWillDismiss(pendingStartGallery)
            pendingStartOwner.isPictureInPictureStartRequested = true
            pendingStartOwner.cancelPendingPictureInPictureStart(rejectLateStart: true)
            let pendingStartRetained = preparedPendingStart
                && coordinator.isRetaining(pendingStartOwner)
                && pendingStartOwner.isPictureInPictureStopRequested
                && !pendingStartOwner.mediaView.debugPictureInPictureControlIsEnabled
            pendingStartOwner.togglePictureInPicture()
            let pendingRestartRejected = pendingStartOwner.isPictureInPictureStopRequested
                && !pendingStartOwner.isPictureInPictureStartRequested
            pendingStartOwner.completePictureInPictureStop()
            let pendingStartReleased = pendingStartOwner.isInvalidated
                && coordinator.activeOwner == nil

            let deletedOwner = GalleryVideoPlaybackOwner(probeMessageID: 9003)
            deletedOwner.handlePermanentDeletion()
            let deletionRevoked = deletedOwner.isDeleted && deletedOwner.isInvalidated
            let ffmpegRouting = await runFFmpegRoutingProbe()

            if startsPaused,
               becameVisible,
               detachedWithoutInvalidation,
               staleInlineCallbacksIgnored,
               reusedExactView,
               itemAndPlayheadContinuous,
               returnedInlineContinuity,
               vodTransferContinuous,
               terminalLeaseCancelled,
               readinessGated,
               commandRouting,
               accessibleControls,
               autoHidePolicy,
               invalidatedCleanly,
               retainedAcrossDismissal,
               transferCleanedUp,
               pendingStartRetained,
               pendingRestartRejected,
               pendingStartReleased,
               deletionRevoked,
               ffmpegRouting.passed
            {
                result = "Gallery playback owner probe: same-view=true, inline-handoff=true, "
                    + "same-item=true, playhead-continuous=true, inline-muted=true, "
                    + "borrowed-return=true, vod-session-continuous=true, no-full-download=true, "
                    + "transfer-cancel-delta=0/final-cancel-delta=1, "
                    + "stale-attachment-ignored=true, detach-retains-session=true, "
                    + "central-visibility=true, transfer-retains=true, pending-start-retains=true, "
                    + "stop-barrier=true, delete-revokes=true, "
                    + "commands=back15+forward15+toggle, controls=two-row+44pt+auto-hide4s, "
                    + "\(ffmpegRouting.summary), "
                    + "pip-supported=\(AVPictureInPictureController.isPictureInPictureSupported()), "
                    + "readiness-gated=true, invalidate=true"
            } else {
                probeFailed = true
                result = "Gallery playback owner probe failed: startsPaused=\(startsPaused), "
                    + "becameVisible=\(becameVisible), detached=\(detachedWithoutInvalidation), "
                    + "staleIgnored=\(staleInlineCallbacksIgnored), reused=\(reusedExactView), "
                    + "itemContinuity=\(itemAndPlayheadContinuous), "
                    + "returnContinuity=\(returnedInlineContinuity), "
                    + "vodContinuity=\(vodTransferContinuous), transferCancelBaseline=\(transferCancelBaseline), "
                    + "terminalRequest=\(terminalRequestActive), terminalCancelBaseline=\(terminalCancelBaseline), "
                    + "finalCancel=\(terminalLeaseCancelled), "
                    + "readinessGated=\(readinessGated), "
                    + "commands=\(commandRouting), "
                    + "accessibleControls=\(accessibleControls), "
                    + "autoHide=\(autoHidePolicy), "
                    + "invalidated=\(invalidatedCleanly), transfer=\(retainedAcrossDismissal), "
                    + "transferCleanup=\(transferCleanedUp), pendingRetained=\(pendingStartRetained), "
                    + "pendingRestartRejected=\(pendingRestartRejected), pendingReleased=\(pendingStartReleased), "
                    + "deletion=\(deletionRevoked), "
                    + "\(ffmpegRouting.summary)"
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            if let documentsURL = documents.first {
                try? Data(result.utf8).write(
                    to: documentsURL.appendingPathComponent("gallery-playback-owner-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
            if probeFailed {
                assertionFailure(result)
            }
        }

        private static func runFFmpegRoutingProbe() async -> (passed: Bool, summary: String) {
            let fixtureURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-gallery-routing-probe.webm")
            try? FileManager.default.removeItem(at: fixtureURL)
            do {
                try FFmpegVODProbeFixture.write(to: fixtureURL)
                let attributes = try FileManager.default.attributesOfItem(atPath: fixtureURL.path)
                guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let network = TDLibVODProbeNetwork(available: true)
                let backend = TDLibVODProbeBackend(
                    fileURL: fixtureURL,
                    fileSize: size,
                    network: network,
                )
                await backend.setAutoFulfill(true)
                let vodRanges = TDLibVODRangeCoordinator(
                    accountID: "probe-gallery-ffmpeg-routing",
                    client: backend.client,
                    requestTimeout: .seconds(3),
                )
                let probeFile = await backend.file(expectedSize: size)
                let owner = GalleryVideoPlaybackOwner(
                    probeMessageID: 9010,
                    videoFile: probeFile,
                    vodRanges: vodRanges,
                    mimeType: "video/webm",
                    fileName: "gallery-routing-probe.webm",
                    supportsStreaming: true,
                )
                let inlineContainer = UIView()
                let fullscreenContainer = UIView()
                let inlineToken = owner.attach(to: inlineContainer, context: .inline)
                if let inlineToken {
                    owner.setPlaybackVisible(true, attachment: inlineToken)
                }
                let becameReady = await waitUntil(timeout: .seconds(15)) {
                    owner.mediaView.debugUsesFFmpegPlayback
                        && owner.mediaView.debugPlaybackSurfaceIsReady
                        && owner.mediaView.debugPlaybackTime >= 0.1
                }
                let itemIdentifier = owner.mediaView.debugCurrentItemIdentifier
                let inlineTime = owner.mediaView.debugPlaybackTime
                let fullscreenToken = owner.attach(to: fullscreenContainer, context: .fullscreen)
                if let fullscreenToken {
                    owner.setPlaybackVisible(true, attachment: fullscreenToken)
                }
                if let inlineToken {
                    owner.setPlaybackVisible(false, attachment: inlineToken)
                    owner.detach(attachment: inlineToken)
                }
                let transferContinuous = await waitUntil {
                    owner.mediaView.debugUsesFFmpegPlayback
                        && owner.mediaView.debugCurrentItemIdentifier == itemIdentifier
                        && owner.mediaView.debugPlaybackTime >= inlineTime
                        && !owner.mediaView.debugIsMuted
                }
                if let fullscreenToken {
                    owner.setPlaybackVisible(false, attachment: fullscreenToken)
                }
                let offscreenIntentPreserved = owner.mediaView.isPlaybackRequested
                if let fullscreenToken {
                    owner.setPlaybackVisible(true, attachment: fullscreenToken)
                }
                let resumedSameController = await waitUntil {
                    owner.mediaView.debugCurrentItemIdentifier == itemIdentifier
                        && owner.mediaView.debugPlaybackTime >= inlineTime
                }
                let sampleBufferPictureInPicture = await runSampleBufferPictureInPictureProbe(
                    owner: owner,
                    backend: backend,
                    itemIdentifier: itemIdentifier,
                )
                let downloadCalls = await backend.downloadCalls
                let finiteRangesOnly = !downloadCalls.isEmpty
                    && downloadCalls.allSatisfy { !$0.isFullDownload }
                owner.invalidate()
                await owner.mediaView.debugWaitForFFmpegClose()
                let backendIsIdle = await backend.activeDownloadCount == 0
                let invalidated = owner.isInvalidated
                    && owner.mediaView.superview == nil
                    && backendIsIdle
                try? FileManager.default.removeItem(at: fixtureURL)
                let passed = inlineToken != nil
                    && fullscreenToken != nil
                    && becameReady
                    && transferContinuous
                    && offscreenIntentPreserved
                    && resumedSameController
                    && sampleBufferPictureInPicture.passed
                    && finiteRangesOnly
                    && invalidated
                return (
                    passed,
                    "ffmpeg-route=\(becameReady), same-controller=\(transferContinuous && resumedSameController), "
                        + "offscreen-intent=\(offscreenIntentPreserved), finite-ranges=\(finiteRangesOnly), "
                        + "\(sampleBufferPictureInPicture.summary), "
                        + "ffmpeg-invalidate=\(invalidated)",
                )
            } catch {
                try? FileManager.default.removeItem(at: fixtureURL)
                return (false, "ffmpeg-route-error=\(error)")
            }
        }

        private final class PictureInPictureProbeCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var storedValue = 0

            var value: Int {
                lock.lock()
                defer { lock.unlock() }
                return storedValue
            }

            func increment() {
                lock.lock()
                storedValue += 1
                lock.unlock()
            }
        }

        private static func runSampleBufferPictureInPictureProbe(
            owner: GalleryVideoPlaybackOwner,
            backend: TDLibVODProbeBackend,
            itemIdentifier: ObjectIdentifier?,
        ) async -> (passed: Bool, summary: String) {
            guard !AVPictureInPictureController.isPictureInPictureSupported(),
                  owner.pictureInPictureController == nil,
                  owner.mediaView.pictureInPictureSourceKind == .sampleBufferDisplayLayer,
                  let displayLayer = owner.mediaView.debugSampleBufferPictureInPictureDisplayLayer,
                  let contentSource = owner.mediaView.makePictureInPictureContentSource(
                      playbackDelegate: owner.sampleBufferPictureInPictureAdapter,
                  )
            else {
                return (false, "sample-pip-probe-environment=false")
            }
            let adapter = owner.sampleBufferPictureInPictureAdapter
            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = owner
            controller.requiresLinearPlayback = false
            owner.pictureInPictureController = controller
            owner.pictureInPictureSourceIdentity = owner.mediaView.pictureInPictureSourceIdentity
            owner.isPictureInPictureStartRequested = true
            owner.isPictureInPictureStopRequested = true
            owner.rejectsLatePictureInPictureStart = true
            owner.pictureInPictureControllerWillStartPictureInPicture(controller)
            let lateStartRejected = !owner.isPictureInPictureStartRequested
                && !owner.isPictureInPictureActive
                && owner.isPictureInPictureStopRequested
            owner.isPictureInPictureStopRequested = false
            owner.rejectsLatePictureInPictureStart = false
            owner.isPictureInPictureActive = true
            owner.mediaView.setPictureInPictureActive(true)
            owner.applyEffectivePlaybackVisibility()
            owner.refreshSampleBufferPictureInPicturePlaybackState()
            owner.mediaView.setSampleBufferPictureInPicturePlaying(true)
            let playbackActive = await waitUntil {
                owner.mediaView.debugPlaybackState == .playing
            }
            owner.refreshSampleBufferPictureInPicturePlaybackState()

            let exactLayer = contentSource.sampleBufferDisplayLayer === displayLayer
            let exactDelegate = contentSource.sampleBufferPlaybackDelegate === adapter
            let range = adapter.pictureInPictureControllerTimeRangeForPlayback(controller)
            let currentTime = CMTime(
                seconds: owner.mediaView.debugPlaybackTime,
                preferredTimescale: 600,
            )
            let rangeContainsCurrent = range.isValid && CMTimeRangeContainsTime(range, time: currentTime)
            let initiallyPlaying = !adapter.pictureInPictureControllerIsPlaybackPaused(controller)
            let commandCancelBaseline = await backend.completedCancelCount

            adapter.pictureInPictureController(controller, setPlaying: false)
            let paused = await waitUntil {
                owner.mediaView.debugPlaybackState == .paused
                    && adapter.pictureInPictureControllerIsPlaybackPaused(controller)
            }
            adapter.pictureInPictureController(controller, setPlaying: true)
            let resumed = await waitUntil {
                owner.mediaView.debugPlaybackState == .playing
                    && !adapter.pictureInPictureControllerIsPlaybackPaused(controller)
            }

            let firstSkip = PictureInPictureProbeCounter()
            adapter.pictureInPictureController(
                controller,
                skipByInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                completion: { firstSkip.increment() },
            )
            let firstSkipCompleted = await waitUntil { firstSkip.value == 1 }

            let supersededSkip = PictureInPictureProbeCounter()
            let newestSkip = PictureInPictureProbeCounter()
            adapter.pictureInPictureController(
                controller,
                skipByInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                completion: { supersededSkip.increment() },
            )
            adapter.pictureInPictureController(
                controller,
                skipByInterval: CMTime(seconds: -0.05, preferredTimescale: 600),
                completion: { newestSkip.increment() },
            )
            let supersessionCompleted = await waitUntil {
                supersededSkip.value == 1 && newestSkip.value == 1
            }

            let timeoutCompletion = PictureInPictureProbeCounter()
            owner.pictureInPictureSkipGeneration &+= 1
            let timeoutGeneration = owner.pictureInPictureSkipGeneration
            owner.pendingPictureInPictureSkipCompletion = { timeoutCompletion.increment() }
            owner.schedulePictureInPictureSkipTimeout(generation: timeoutGeneration)
            owner.pictureInPictureSkipTimeout?.perform()
            let timeoutCompletedOnce = timeoutCompletion.value == 1

            let pastEndSkip = PictureInPictureProbeCounter()
            adapter.pictureInPictureController(
                controller,
                skipByInterval: CMTime(
                    seconds: owner.mediaView.sampleBufferPictureInPictureDuration + 1,
                    preferredTimescale: 600,
                ),
                completion: { pastEndSkip.increment() },
            )
            let pastEndPolicy = await waitUntil {
                pastEndSkip.value == 1
                    && owner.mediaView.debugPlaybackTime < 0.05
                    && owner.mediaView.debugPlaybackState == .paused
            }

            let renderSize = CMVideoDimensions(width: 320, height: 180)
            adapter.pictureInPictureController(controller, didTransitionToRenderSize: renderSize)
            let renderSizeForwarded = await waitUntil {
                owner.mediaView.debugSampleBufferPictureInPictureRenderSize?.width == 320
                    && owner.mediaView.debugSampleBufferPictureInPictureRenderSize?.height == 180
            }
            let backgroundAudioAllowed = !adapter
                .pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(controller)
            let samePlayer = owner.mediaView.debugCurrentItemIdentifier == itemIdentifier
            let sameLayer = owner.mediaView.debugSampleBufferPictureInPictureDisplayLayer === displayLayer
            let commandCancelDelta = await backend.completedCancelCount - commandCancelBaseline

            owner.mediaView.debugSimulateFFmpegOfflineFailure()
            let deferredFailureHeldLayer = owner.mediaView.debugHasDeferredPictureInPictureFailureResolution
                && owner.mediaView.debugSampleBufferPictureInPictureDisplayLayer === displayLayer
                && owner.mediaView.debugSampleBufferPictureInPictureLayerIsVisible
                && owner.mediaView.debugCurrentItemIdentifier == itemIdentifier
            let stopTimeout = owner.pictureInPictureStopTimeout
            owner.refreshPictureInPictureConfiguration()
            let stopRequestIsIdempotent = owner.isPictureInPictureStopRequested
                && owner.pictureInPictureStopTimeout === stopTimeout
            owner.completePictureInPictureStop()
            await owner.mediaView.debugWaitForFFmpegClose()
            let deferredFailureReleasedAfterStop = !owner.mediaView.debugHasDeferredPictureInPictureFailureResolution
                && !owner.mediaView.debugUsesFFmpegPlayback

            owner.reconcilePictureInPictureContentSourceAfterStop()

            let nativeSource = owner.mediaView.makePictureInPictureContentSource(
                playbackDelegate: adapter,
            )
            let nativeFactoryRoute = nativeSource?.playerLayer === owner.mediaView.pictureInPicturePlayerLayer
            let nativeOwnerReconciled = owner.pictureInPictureSourceIdentity
                == owner.mediaView.pictureInPictureSourceIdentity
            let nativeControllerRoute = controller.contentSource?.playerLayer
                === owner.mediaView.pictureInPicturePlayerLayer
            let controllerRetiredOnUnsupportedPlatform = !AVPictureInPictureController
                .isPictureInPictureSupported()
                && owner.pictureInPictureController == nil
            let nativeRoute = nativeFactoryRoute
                && (controllerRetiredOnUnsupportedPlatform
                    || nativeOwnerReconciled && nativeControllerRoute)
            owner.completePictureInPictureStop(retiringController: true)
            let staleTimeoutCallbackRejected: Bool
            if let nativeSource {
                let replacementController = AVPictureInPictureController(contentSource: nativeSource)
                replacementController.delegate = owner
                owner.pictureInPictureController = replacementController
                owner.pictureInPictureSourceIdentity = owner.mediaView.pictureInPictureSourceIdentity
                owner.pictureInPictureControllerDidStopPictureInPicture(controller)
                staleTimeoutCallbackRejected = owner.pictureInPictureController === replacementController
                replacementController.delegate = nil
            } else {
                staleTimeoutCallbackRejected = false
            }
            owner.finishPictureInPictureSkip()
            adapter.update(controller: nil, currentTime: 0, duration: 0, isPaused: true)
            owner.pictureInPictureController = nil
            owner.pictureInPictureSourceIdentity = nil

            let passed = exactLayer
                && exactDelegate
                && lateStartRejected
                && playbackActive
                && rangeContainsCurrent
                && initiallyPlaying
                && paused
                && resumed
                && firstSkipCompleted
                && firstSkip.value == 1
                && supersessionCompleted
                && supersededSkip.value == 1
                && newestSkip.value == 1
                && timeoutCompletedOnce
                && pastEndPolicy
                && renderSizeForwarded
                && backgroundAudioAllowed
                && samePlayer
                && sameLayer
                && commandCancelDelta == 0
                && deferredFailureHeldLayer
                && stopRequestIsIdempotent
                && deferredFailureReleasedAfterStop
                && nativeRoute
                && staleTimeoutCallbackRejected
            return (
                passed,
                "sample-pip-source=\(exactLayer), delegate=\(exactDelegate), range=\(rangeContainsCurrent), "
                    + "late-start-rejected=\(lateStartRejected), "
                    + "play-pause=\(paused && resumed), skip-once=\(firstSkip.value == 1), "
                    + "supersession=\(supersessionCompleted), timeout-once=\(timeoutCompletedOnce), "
                    + "past-end=\(pastEndPolicy), render-size=\(renderSizeForwarded), "
                    + "same-player-layer=\(samePlayer && sameLayer), cancel-delta=\(commandCancelDelta), "
                    + "deferred-teardown=\(deferredFailureHeldLayer && deferredFailureReleasedAfterStop), "
                    + "stop-idempotent=\(stopRequestIsIdempotent), "
                    + "native-route=\(nativeRoute)/factory=\(nativeFactoryRoute)/owner=\(nativeOwnerReconciled)"
                    + "/controller=\(nativeControllerRoute)/retired=\(controllerRetiredOnUnsupportedPlatform), "
                    + "stale-timeout=\(staleTimeoutCallbackRejected), "
                    + "pip-supported=false",
            )
        }

        private static func waitUntil(
            timeout: Duration = .seconds(5),
            condition: @escaping @MainActor () -> Bool,
        ) async -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while clock.now < deadline {
                if condition() {
                    return true
                }
                try? await Task<Never, Never>.sleep(for: .milliseconds(20))
            }
            return condition()
        }

        private static func waitUntilAsync(
            timeout: Duration = .seconds(5),
            condition: @escaping () async -> Bool,
        ) async -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while clock.now < deadline {
                if await condition() {
                    return true
                }
                try? await Task<Never, Never>.sleep(for: .milliseconds(20))
            }
            return await condition()
        }
    #endif

    @discardableResult func attach(
        to container: UIView,
        context: VideoPlaybackAttachmentContext = .fullscreen,
    ) -> VideoPlaybackAttachmentToken? {
        let token = VideoPlaybackAttachmentToken()
        guard !isInvalidated,
              context != .inline || galleryController == nil && !isPictureInPictureRetained
        else { return nil }
        attachmentToken = token
        attachmentContext = context
        attachmentContainer = container
        mediaView.setPresentationContext(context)
        if mediaView.superview !== container {
            mediaView.removeFromSuperview()
            mediaView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(mediaView)
            NSLayoutConstraint.activate([
                mediaView.topAnchor.constraint(equalTo: container.topAnchor),
                mediaView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                mediaView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                mediaView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        applyEffectivePlaybackVisibility()
        updatePictureInPictureControl()
        return token
    }

    func detach(attachment token: VideoPlaybackAttachmentToken) {
        guard attachmentToken == token else { return }
        attachmentToken = nil
        attachmentContext = nil
        attachmentContainer = nil
        isPlaybackVisible = false
        applyEffectivePlaybackVisibility()
        mediaView.removeFromSuperview()
        updatePictureInPictureControl()
    }

    func setPlaybackVisible(
        _ isVisible: Bool,
        attachment token: VideoPlaybackAttachmentToken,
    ) {
        guard attachmentToken == token else { return }
        setPlaybackVisible(isVisible)
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        guard !isInvalidated, isPlaybackVisible != isVisible else { return }
        isPlaybackVisible = isVisible
        applyEffectivePlaybackVisibility()
        updatePictureInPictureControl()
        if !isVisible, !isPictureInPictureRetained {
            releasePictureInPictureAudioSession()
        }
    }

    func performPlaybackCommand(_ command: GalleryPlaybackCommand) {
        guard !isInvalidated else { return }
        mediaView.performPlaybackCommand(command)
    }

    func setGalleryChromeController(_ visibilityChanged: ((Bool) -> Void)?) {
        guard !isInvalidated else { return }
        mediaView.setGalleryChromeController(visibilityChanged)
    }

    func setGalleryChromeVisible(_ isVisible: Bool, animated: Bool) {
        guard !isInvalidated else { return }
        mediaView.setGalleryChromeVisible(isVisible, animated: animated)
    }

    func setGalleryChromeBottomInset(_ inset: CGFloat) {
        guard !isInvalidated else { return }
        mediaView.setGalleryChromeBottomInset(inset)
    }

    func setGalleryChromeInteractionActive(_ isActive: Bool) {
        guard !isInvalidated else { return }
        mediaView.setGalleryChromeInteractionActive(isActive)
    }

    func canBeginInteractiveDismissal(at point: CGPoint, in coordinateSpace: UIView) -> Bool {
        guard !isInvalidated,
              !isPictureInPictureRetained,
              attachmentContext == .fullscreen
        else { return false }
        return mediaView.canBeginInteractiveDismissal(at: mediaView.convert(point, from: coordinateSpace))
    }

    func setInteractiveDismissalActive(_ isActive: Bool) {
        guard !isInvalidated else { return }
        mediaView.setInteractiveDismissalActive(isActive)
    }

    func makeTransitionSnapshot(contentMode: UIView.ContentMode) -> UIView? {
        mediaView.makeTransitionSnapshot(contentMode: contentMode)
    }

    func detachFromGallery() {
        guard attachmentContext == .fullscreen else { return }
        attachmentToken = nil
        attachmentContext = nil
        attachmentContainer = nil
        isPlaybackVisible = false
        applyEffectivePlaybackVisibility()
        mediaView.removeFromSuperview()
        updatePictureInPictureControl()
    }

    func returnToInlineIfAvailable() -> Bool {
        guard !isDeleted,
              let onReturnToInline
        else { return false }
        galleryController = nil
        detachFromGallery()
        return onReturnToInline(self)
    }

    func confirmPermanentDeletionFromGallery() {
        handlePermanentDeletion(notifyGallery: false)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        if isPictureInPictureStartRequested {
            pendingInvalidationAfterPictureInPicture = true
            cancelPendingPictureInPictureStart(rejectLateStart: true)
            return
        }
        if isPictureInPictureRetained {
            pendingInvalidationAfterPictureInPicture = true
            requestPictureInPictureStop()
            return
        }
        finishInvalidation()
    }

    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController,
    ) {
        guard self.pictureInPictureController === pictureInPictureController else { return }
        cancelPictureInPictureStartTimeout()
        if rejectsLatePictureInPictureStart {
            isPictureInPictureStartRequested = false
            requestPictureInPictureStop()
            return
        }
        isPictureInPictureStartRequested = false
        isPictureInPictureActive = true
        ignoresPictureInPictureControllerActiveState = false
        isPictureInPictureStopRequested = false
        mediaView.setPictureInPictureActive(true)
        applyEffectivePlaybackVisibility()
        updatePictureInPictureControl()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Swift.Error,
    ) {
        guard self.pictureInPictureController === pictureInPictureController else { return }
        cancelPictureInPictureStartTimeout()
        cancelPictureInPictureStopTimeout()
        finishPictureInPictureSkip()
        rejectsLatePictureInPictureStart = false
        log("Gallery Picture in Picture failed: \(error.localizedDescription)")
        isPictureInPictureStartRequested = false
        isPictureInPictureActive = false
        ignoresPictureInPictureControllerActiveState = true
        isPictureInPictureStopRequested = false
        mediaView.setPictureInPictureActive(false)
        applyEffectivePlaybackVisibility()
        releasePictureInPictureAudioSession()
        updatePictureInPictureControl()
        GalleryPictureInPictureCoordinator.shared.didFail(owner: self)
        if pendingInvalidationAfterPictureInPicture {
            finishInvalidation()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController,
    ) {
        guard self.pictureInPictureController === pictureInPictureController else { return }
        cancelPictureInPictureStartTimeout()
        cancelPictureInPictureStopTimeout()
        completePictureInPictureStop()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void,
    ) {
        guard self.pictureInPictureController === pictureInPictureController else {
            completionHandler(false)
            return
        }
        GalleryPictureInPictureCoordinator.shared.restore(
            owner: self,
            completion: completionHandler,
        )
    }

    func setSampleBufferPictureInPicturePlaying(_ playing: Bool) {
        guard isPictureInPictureRetained,
              !isPictureInPictureStopRequested,
              pictureInPictureSourceIdentity?.kind == .sampleBufferDisplayLayer
        else { return }
        mediaView.setSampleBufferPictureInPicturePlaying(playing)
        refreshSampleBufferPictureInPicturePlaybackState()
    }

    func setSampleBufferPictureInPictureRenderSize(_ newRenderSize: CMVideoDimensions) {
        guard isPictureInPictureRetained,
              !isPictureInPictureStopRequested,
              pictureInPictureSourceIdentity?.kind == .sampleBufferDisplayLayer
        else { return }
        mediaView.setSampleBufferPictureInPictureRenderSize(newRenderSize)
    }

    func skipSampleBufferPictureInPicture(
        by interval: TimeInterval,
        completion completionHandler: @escaping @Sendable () -> Void,
    ) {
        let previousCompletion = pendingPictureInPictureSkipCompletion
        pendingPictureInPictureSkipCompletion = nil
        previousCompletion?()
        pictureInPictureSkipGeneration &+= 1
        let generation = pictureInPictureSkipGeneration
        pendingPictureInPictureSkipCompletion = completionHandler
        schedulePictureInPictureSkipTimeout(generation: generation)
        guard isPictureInPictureRetained,
              !isPictureInPictureStopRequested,
              pictureInPictureSourceIdentity?.kind == .sampleBufferDisplayLayer,
              interval.isFinite
        else {
            finishPictureInPictureSkip(generation: generation)
            return
        }
        mediaView.skipSampleBufferPictureInPicture(by: interval) { [weak self] in
            guard let self, pictureInPictureSkipGeneration == generation else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, pictureInPictureSkipGeneration == generation else { return }
                refreshSampleBufferPictureInPicturePlaybackState()
                finishPictureInPictureSkip(generation: generation)
            }
        }
    }

    private func completePictureInPictureStop(retiringController: Bool = false) {
        cancelPictureInPictureStartTimeout()
        cancelPictureInPictureStopTimeout()
        finishPictureInPictureSkip()
        if retiringController {
            retirePictureInPictureController()
        }
        rejectsLatePictureInPictureStart = false
        isPictureInPictureStartRequested = false
        isPictureInPictureActive = false
        isPictureInPictureStopRequested = false
        ignoresPictureInPictureControllerActiveState = true
        mediaView.setPictureInPictureActive(false)
        applyEffectivePlaybackVisibility()
        if !retiringController {
            reconcilePictureInPictureContentSourceAfterStop()
        }
        releasePictureInPictureAudioSession(
            keepForGalleryPlayback: isPlaybackVisible && mediaView.isPlaybackRequested,
        )
        updatePictureInPictureControl()
        GalleryPictureInPictureCoordinator.shared.didStop(owner: self)
        if pendingInvalidationAfterPictureInPicture {
            finishInvalidation()
        } else if !isInvalidated, retiringController {
            refreshPictureInPictureConfiguration()
        }
    }

    private func retirePictureInPictureController() {
        pictureInPicturePossibleCancellable?.cancel()
        pictureInPicturePossibleCancellable = nil
        sampleBufferPictureInPictureAdapter.update(
            controller: nil,
            currentTime: 0,
            duration: 0,
            isPaused: true,
        )
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil
        pictureInPictureSourceIdentity = nil
    }

    private func reconcilePictureInPictureContentSourceAfterStop() {
        guard let pictureInPictureController,
              let contentSource = mediaView.makePictureInPictureContentSource(
                  playbackDelegate: sampleBufferPictureInPictureAdapter,
              )
        else { return }
        let desiredIdentity = mediaView.pictureInPictureSourceIdentity
        if pictureInPictureSourceIdentity != desiredIdentity {
            pictureInPictureController.contentSource = contentSource
            pictureInPictureSourceIdentity = desiredIdentity
        }
        refreshSampleBufferPictureInPicturePlaybackState()
    }

    private func finishPictureInPictureSkip(generation: UInt64? = nil) {
        if let generation, generation != pictureInPictureSkipGeneration { return }
        pictureInPictureSkipTimeout?.cancel()
        pictureInPictureSkipTimeout = nil
        pictureInPictureSkipGeneration &+= 1
        let completion = pendingPictureInPictureSkipCompletion
        pendingPictureInPictureSkipCompletion = nil
        completion?()
    }

    private func schedulePictureInPictureSkipTimeout(generation: UInt64) {
        pictureInPictureSkipTimeout?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishPictureInPictureSkip(generation: generation)
        }
        pictureInPictureSkipTimeout = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func configurePictureInPicture() {
        mediaView.onPictureInPictureToggle = { [weak self] in self?.togglePictureInPicture() }
        mediaView.onPictureInPictureEligibilityChanged = { [weak self] in
            self?.refreshPictureInPictureConfiguration()
        }
        mediaView.onPlaybackIntentChanged = { [weak self] in
            guard let self,
                  !isPictureInPictureRetained,
                  !mediaView.isPlaybackRequested
            else { return }
            releasePictureInPictureAudioSession()
        }
        mediaTakeoverCancellable = Media.shared
            .$savedMediaPath
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                guard let self,
                      !path.isEmpty,
                      pictureInPictureAudioSessionToken != nil
                else { return }
                if let pictureInPictureAudioSessionToken {
                    GalleryPlaybackAudioSessionCoordinator.shared.relinquish(
                        token: pictureInPictureAudioSessionToken,
                    )
                    self.pictureInPictureAudioSessionToken = nil
                }
                mediaView.pauseForAudioTakeover()
            }
        refreshPictureInPictureConfiguration()
    }

    private func refreshPictureInPictureConfiguration() {
        if isPictureInPictureRetained,
           mediaView.sampleBufferPictureInPictureHasTerminalFailure
        {
            refreshSampleBufferPictureInPicturePlaybackState()
            finishPictureInPictureSkip()
            if isPictureInPictureStartRequested {
                rejectsLatePictureInPictureStart = true
            }
            requestPictureInPictureStop()
            updatePictureInPictureControl()
            return
        }
        let desiredIdentity = mediaView.pictureInPictureSourceIdentity
        if isPictureInPictureRetained, pictureInPictureSourceIdentity != desiredIdentity {
            finishPictureInPictureSkip()
            if isPictureInPictureStartRequested {
                rejectsLatePictureInPictureStart = true
            }
            requestPictureInPictureStop()
            updatePictureInPictureControl()
            return
        }
        if pictureInPictureSourceIdentity?.kind == .sampleBufferDisplayLayer {
            refreshSampleBufferPictureInPicturePlaybackState()
        }
        guard allowsPictureInPicture,
              AVPictureInPictureController.isPictureInPictureSupported()
              || pictureInPictureController != nil
        else {
            updatePictureInPictureControl()
            return
        }
        guard let contentSource = mediaView.makePictureInPictureContentSource(
            playbackDelegate: sampleBufferPictureInPictureAdapter,
        ) else {
            updatePictureInPictureControl()
            return
        }
        if let pictureInPictureController {
            if pictureInPictureSourceIdentity != desiredIdentity {
                pictureInPictureController.contentSource = contentSource
                pictureInPictureSourceIdentity = desiredIdentity
            }
        } else {
            let controller: AVPictureInPictureController
            switch desiredIdentity.kind {
            case .playerLayer:
                guard let nativeController = AVPictureInPictureController(
                    playerLayer: mediaView.pictureInPicturePlayerLayer,
                ) else {
                    updatePictureInPictureControl()
                    return
                }
                controller = nativeController
            case .sampleBufferDisplayLayer:
                controller = AVPictureInPictureController(contentSource: contentSource)
            }
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            controller.requiresLinearPlayback = false
            pictureInPictureController = controller
            pictureInPictureSourceIdentity = desiredIdentity
            pictureInPicturePossibleCancellable = controller.publisher(
                for: \.isPictureInPicturePossible,
                options: [.initial, .new],
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak controller] _ in
                guard let self, pictureInPictureController === controller else { return }
                updatePictureInPictureControl()
            }
        }
        refreshSampleBufferPictureInPicturePlaybackState()
        updatePictureInPictureControl()
    }

    private func refreshSampleBufferPictureInPicturePlaybackState() {
        let controller = pictureInPictureSourceIdentity?.kind == .sampleBufferDisplayLayer
            ? pictureInPictureController
            : nil
        sampleBufferPictureInPictureAdapter.update(
            controller: controller,
            currentTime: mediaView.sampleBufferPictureInPictureCurrentTime,
            duration: mediaView.sampleBufferPictureInPictureDuration,
            isPaused: mediaView.sampleBufferPictureInPictureIsPaused,
        )
        controller?.invalidatePlaybackState()
    }

    private func observeMessageDeletion() {
        tdlib.deleteMessageUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self,
                      !update.fromCache,
                      update.isPermanent,
                      update.chatId == chatID,
                      update.messageIds.contains(messageID)
                else { return }
                handlePermanentDeletion()
            }
            .store(in: &tdUpdateCancellables)
    }

    private func handlePermanentDeletion(notifyGallery: Bool = true) {
        guard !isDeleted else { return }
        isDeleted = true
        onPermanentDeletion?(self)
        GalleryPictureInPictureCoordinator.shared.messageWasDeleted(owner: self)
        if notifyGallery {
            galleryController?.playbackOwnerWasDeleted(self)
        }
        if isPictureInPictureStartRequested {
            pendingInvalidationAfterPictureInPicture = true
            cancelPendingPictureInPictureStart(rejectLateStart: true)
        } else if isPictureInPictureRetained {
            pendingInvalidationAfterPictureInPicture = true
            requestPictureInPictureStop()
        } else {
            finishInvalidation()
        }
    }

    private func togglePictureInPicture() {
        guard let pictureInPictureController else { return }
        guard !isPictureInPictureStopRequested else { return }
        if isPictureInPictureStartRequested {
            cancelPendingPictureInPictureStart(rejectLateStart: true)
            return
        }
        if isPictureInPictureActive || pictureInPictureController.isPictureInPictureActive {
            requestPictureInPictureStop()
            return
        }
        guard isPlaybackVisible,
              pictureInPictureSourceIdentity == mediaView.pictureInPictureSourceIdentity,
              mediaView.isPictureInPictureReady,
              pictureInPictureController.isPictureInPicturePossible,
              galleryController?.preparePictureInPicture(for: self) == true
        else { return }
        guard activatePictureInPictureAudioSession() else {
            GalleryPictureInPictureCoordinator.shared.didFail(owner: self)
            return
        }
        rejectsLatePictureInPictureStart = false
        isPictureInPictureStopRequested = false
        ignoresPictureInPictureControllerActiveState = false
        isPictureInPictureStartRequested = true
        applyEffectivePlaybackVisibility()
        updatePictureInPictureControl()
        pictureInPictureController.startPictureInPicture()
        schedulePictureInPictureStartTimeout()
    }

    private func applyEffectivePlaybackVisibility() {
        mediaView.setPictureInPictureRetained(isPictureInPictureRetained)
        mediaView.setPlaybackVisible(isPlaybackVisible || isPictureInPictureRetained)
    }

    private func updatePictureInPictureControl() {
        let isPossible = pictureInPictureController?.isPictureInPicturePossible == true
        let isReady = mediaView.isPictureInPictureReady
        let sourceMatchesPlayback = pictureInPictureSourceIdentity == mediaView.pictureInPictureSourceIdentity
        let isVisible = allowsPictureInPicture
            && !isDeleted
            && isPlaybackVisible
            && !rejectsLatePictureInPictureStart
            && sourceMatchesPlayback
            && (isPictureInPictureRetained || isPossible && isReady)
        mediaView.setPictureInPictureControl(
            visible: isVisible,
            enabled: !isPictureInPictureStopRequested
                && (isPictureInPictureActive || !isPictureInPictureStartRequested && isPossible && isReady),
            active: isPictureInPictureRetained,
        )
    }

    private func activatePictureInPictureAudioSession() -> Bool {
        if pictureInPictureAudioSessionToken != nil {
            return true
        }
        pictureInPictureAudioSessionToken = GalleryPlaybackAudioSessionCoordinator.shared.acquire(for: self)
        return pictureInPictureAudioSessionToken != nil
    }

    private func releasePictureInPictureAudioSession(keepForGalleryPlayback: Bool = false) {
        guard let pictureInPictureAudioSessionToken else { return }
        GalleryPlaybackAudioSessionCoordinator.shared.release(
            token: pictureInPictureAudioSessionToken,
            keepActive: keepForGalleryPlayback,
        )
        if !keepForGalleryPlayback {
            self.pictureInPictureAudioSessionToken = nil
        }
    }

    private func schedulePictureInPictureStartTimeout() {
        cancelPictureInPictureStartTimeout()
        let controller = pictureInPictureController
        let sourceIdentity = pictureInPictureSourceIdentity
        let workItem = DispatchWorkItem { [weak self, weak controller] in
            guard let self,
                  pictureInPictureController === controller,
                  pictureInPictureSourceIdentity == sourceIdentity,
                  isPictureInPictureStartRequested
            else { return }
            if let controller, controller.isPictureInPictureActive {
                pictureInPictureControllerWillStartPictureInPicture(controller)
                return
            }
            cancelPendingPictureInPictureStart(rejectLateStart: true)
        }
        pictureInPictureStartTimeout = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func cancelPictureInPictureStartTimeout() {
        pictureInPictureStartTimeout?.cancel()
        pictureInPictureStartTimeout = nil
    }

    private func requestPictureInPictureStop() {
        guard !isPictureInPictureStopRequested else { return }
        isPictureInPictureStopRequested = true
        pictureInPictureController?.stopPictureInPicture()
        schedulePictureInPictureStopTimeout()
    }

    private func schedulePictureInPictureStopTimeout() {
        cancelPictureInPictureStopTimeout()
        let controller = pictureInPictureController
        let sourceIdentity = pictureInPictureSourceIdentity
        let workItem = DispatchWorkItem { [weak self, weak controller] in
            guard let self,
                  pictureInPictureController === controller,
                  pictureInPictureSourceIdentity == sourceIdentity
            else { return }
            guard isPictureInPictureActive
                || controller?.isPictureInPictureActive == true
                || isPictureInPictureStopRequested
                || pendingInvalidationAfterPictureInPicture
            else { return }
            controller?.stopPictureInPicture()
            if controller?.isPictureInPictureActive == true {
                schedulePictureInPictureStopTimeout()
                return
            }
            completePictureInPictureStop(retiringController: true)
        }
        pictureInPictureStopTimeout = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func cancelPictureInPictureStopTimeout() {
        pictureInPictureStopTimeout?.cancel()
        pictureInPictureStopTimeout = nil
    }

    private func cancelPendingPictureInPictureStart(rejectLateStart: Bool) {
        guard isPictureInPictureStartRequested else { return }
        cancelPictureInPictureStartTimeout()
        finishPictureInPictureSkip()
        isPictureInPictureStartRequested = false
        isPictureInPictureActive = false
        isPictureInPictureStopRequested = true
        rejectsLatePictureInPictureStart = rejectLateStart
        pictureInPictureController?.stopPictureInPicture()
        applyEffectivePlaybackVisibility()
        schedulePictureInPictureStopTimeout()
        releasePictureInPictureAudioSession()
        updatePictureInPictureControl()
    }

    private func finishInvalidation() {
        guard !isInvalidated else { return }
        isInvalidated = true
        isPlaybackVisible = false
        pendingInvalidationAfterPictureInPicture = false
        rejectsLatePictureInPictureStart = false
        isPictureInPictureStopRequested = false
        ignoresPictureInPictureControllerActiveState = true
        cancelPictureInPictureStartTimeout()
        cancelPictureInPictureStopTimeout()
        finishPictureInPictureSkip()
        mediaTakeoverCancellable?.cancel()
        mediaTakeoverCancellable = nil
        tdUpdateCancellables.removeAll()
        retirePictureInPictureController()
        attachmentToken = nil
        attachmentContext = nil
        attachmentContainer = nil
        onPermanentDeletion = nil
        onReturnToInline = nil
        releasePictureInPictureAudioSession()
        mediaView.removeFromSuperview()
        mediaView.prepareForReuse()
    }
}

// MARK: - GalleryPlaybackAudioSessionCoordinator

@MainActor final class GalleryPlaybackAudioSessionCoordinator {
    // MARK: Private

    private struct Snapshot {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    private struct Ownership {
        weak var owner: GalleryVideoPlaybackOwner?
        let snapshot: Snapshot
        let token: UUID
    }

    // MARK: Internal

    static let shared = GalleryPlaybackAudioSessionCoordinator()

    private var ownership: Ownership?

    private init() {}

    func acquire(for owner: GalleryVideoPlaybackOwner) -> UUID? {
        if let ownership, ownership.owner != nil {
            return ownership.owner === owner ? ownership.token : nil
        }
        ownership = nil
        let audioSession = AVAudioSession.sharedInstance()
        let snapshot = Snapshot(
            category: audioSession.category,
            mode: audioSession.mode,
            options: audioSession.categoryOptions,
        )
        do {
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                policy: .default,
                options: [.allowAirPlay, .allowBluetoothA2DP],
            )
            try audioSession.setActive(true)
        } catch {
            try? audioSession.setCategory(
                snapshot.category,
                mode: snapshot.mode,
                options: snapshot.options,
            )
            log("Gallery Picture in Picture audio session failed: \(error.localizedDescription)")
            return nil
        }
        Media.shared.stop()
        let token = UUID()
        ownership = Ownership(owner: owner, snapshot: snapshot, token: token)
        return token
    }

    func release(token: UUID, keepActive: Bool) {
        guard let ownership, ownership.token == token else { return }
        if keepActive {
            return
        }
        self.ownership = nil
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.category == .playback, audioSession.mode == .moviePlayback else {
            return
        }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        try? audioSession.setCategory(
            ownership.snapshot.category,
            mode: ownership.snapshot.mode,
            options: ownership.snapshot.options,
        )
    }

    func relinquish(token: UUID) {
        guard ownership?.token == token else { return }
        ownership = nil
    }
}

// MARK: - GalleryPictureInPictureCoordinator

@MainActor final class GalleryPictureInPictureCoordinator {
    // MARK: Internal

    static let shared = GalleryPictureInPictureCoordinator()

    private(set) var activeOwner: GalleryVideoPlaybackOwner?

    // MARK: Private

    private weak var galleryController: MediaGalleryViewController?
    private weak var presentingViewController: UIViewController?
    private var restorationMessages = [Message]()

    private init() {}

    func prepare(
        owner: GalleryVideoPlaybackOwner,
        gallery: MediaGalleryViewController,
        messages: [Message],
    ) -> Bool {
        guard !owner.isDeleted else { return false }
        if let activeOwner, activeOwner !== owner {
            return false
        }
        activeOwner = owner
        galleryController = gallery
        presentingViewController = gallery.presentingViewController
        restorationMessages = messages
        return true
    }

    func galleryWillDismiss(_ gallery: MediaGalleryViewController) {
        guard galleryController === gallery else { return }
        galleryController = nil
        activeOwner?.galleryController = nil
    }

    func isRetaining(_ owner: GalleryVideoPlaybackOwner) -> Bool {
        activeOwner === owner
    }

    func restore(
        owner: GalleryVideoPlaybackOwner,
        completion: @escaping (Bool) -> Void,
    ) {
        guard activeOwner === owner,
              !owner.isDeleted,
              restorationMessages.contains(where: {
                  $0.chatId == owner.chatID && $0.id == owner.messageID
              })
        else {
            completion(false)
            return
        }
        if let galleryController,
           !galleryController.isBeingDismissed,
           galleryController.viewIfLoaded?.window != nil
        {
            galleryController.restorePictureInPicture(owner: owner, completion: completion)
            return
        }
        guard let presentingViewController,
              presentingViewController.viewIfLoaded?.window != nil,
              !restorationMessages.isEmpty
        else {
            completion(false)
            return
        }
        presentRestoredGallery(
            owner: owner,
            presenter: presentingViewController,
            retriesRemaining: 20,
            completion: completion,
        )
    }

    func didFail(owner: GalleryVideoPlaybackOwner) {
        finish(owner: owner)
    }

    func didStop(owner: GalleryVideoPlaybackOwner) {
        finish(owner: owner)
    }

    func messageWasDeleted(owner: GalleryVideoPlaybackOwner) {
        restorationMessages.removeAll {
            $0.chatId == owner.chatID && $0.id == owner.messageID
        }
    }

    private func presentRestoredGallery(
        owner: GalleryVideoPlaybackOwner,
        presenter: UIViewController,
        retriesRemaining: Int,
        completion: @escaping (Bool) -> Void,
    ) {
        guard activeOwner === owner else {
            completion(false)
            return
        }
        guard !owner.isDeleted else {
            completion(false)
            return
        }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed else {
            completion(false)
            return
        }
        if presenter.presentedViewController != nil {
            guard retriesRemaining > 0 else {
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak owner, weak presenter] in
                guard let self, let owner, let presenter else {
                    completion(false)
                    return
                }
                presentRestoredGallery(
                    owner: owner,
                    presenter: presenter,
                    retriesRemaining: retriesRemaining - 1,
                    completion: completion,
                )
            }
            return
        }
        let gallery = MediaGalleryViewController(
            messages: restorationMessages,
            selection: owner.messageID,
            tdlib: owner.tdlib,
            transferredPlaybackOwner: owner,
        )
        galleryController = gallery
        owner.galleryController = gallery
        presenter.present(gallery, animated: true) { [weak self, weak gallery, weak owner] in
            guard let self,
                  let gallery,
                  let owner,
                  activeOwner === owner
            else {
                completion(false)
                return
            }
            galleryController = gallery
            gallery.restorePictureInPicture(owner: owner, completion: completion)
        }
    }

    private func finish(owner: GalleryVideoPlaybackOwner) {
        guard activeOwner === owner else { return }
        let gallery = galleryController
        activeOwner = nil
        galleryController = nil
        presentingViewController = nil
        restorationMessages.removeAll()
        if let gallery, !gallery.isBeingDismissed {
            owner.galleryController = gallery
            gallery.pictureInPictureDidFinish(for: owner)
        } else {
            owner.galleryController = nil
            if !owner.returnToInlineIfAvailable() {
                owner.invalidate()
            }
        }
    }
}

// MARK: - MediaGalleryCell

final class MediaGalleryCell: UICollectionViewCell {
    static let reuseIdentifier = "MediaGalleryCell"

    private var contentMediaView: (UIView & GalleryMediaView)?

    private weak var videoPlaybackOwner: GalleryVideoPlaybackOwner?
    private var videoPlaybackAttachmentToken: VideoPlaybackAttachmentToken?
    private var transitionMediaSize: CGSize?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        unbindGalleryChrome()
        if let videoPlaybackAttachmentToken {
            videoPlaybackOwner?.detach(attachment: videoPlaybackAttachmentToken)
        }
        videoPlaybackAttachmentToken = nil
        videoPlaybackOwner = nil
        transitionMediaSize = nil
        contentMediaView?.prepareForReuse()
        contentMediaView?.removeFromSuperview()
        contentMediaView = nil
    }

    private static func mediaSize(for message: Message) -> CGSize? {
        switch message.content {
        case .messagePhoto(let photo):
            guard let size = photo.photo.sizes.max(by: {
                $0.width * $0.height < $1.width * $1.height
            }) else { return nil }
            return CGSize(width: max(1, size.width), height: max(1, size.height))
        case .messageAnimation(let animation):
            return CGSize(width: max(1, animation.animation.width), height: max(1, animation.animation.height))
        case .messageSticker(let sticker):
            return CGSize(width: max(1, sticker.sticker.width), height: max(1, sticker.sticker.height))
        case .messageVideo(let video):
            return CGSize(width: max(1, video.video.width), height: max(1, video.video.height))
        default:
            return nil
        }
    }

    func configure(message: Message, videoPlaybackOwner: GalleryVideoPlaybackOwner? = nil) {
        prepareForReuse()
        transitionMediaSize = Self.mediaSize(for: message)
        if let videoPlaybackOwner {
            self.videoPlaybackOwner = videoPlaybackOwner
            videoPlaybackAttachmentToken = videoPlaybackOwner.attach(
                to: contentView,
                context: .fullscreen,
            )
            return
        }
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
        case .messageVideo:
            view = ZoomableGalleryImageView()
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
        view.setPlaybackVisible(false)
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        if let videoPlaybackOwner, let videoPlaybackAttachmentToken {
            videoPlaybackOwner.setPlaybackVisible(
                isVisible,
                attachment: videoPlaybackAttachmentToken,
            )
        } else {
            contentMediaView?.setPlaybackVisible(isVisible)
        }
    }

    func performPlaybackCommand(_ command: GalleryPlaybackCommand) {
        if let videoPlaybackOwner {
            videoPlaybackOwner.performPlaybackCommand(command)
        } else {
            contentMediaView?.performPlaybackCommand(command)
        }
    }

    func bindGalleryChrome(
        isVisible: Bool,
        visibilityChanged: @escaping (Bool) -> Void,
    ) {
        if let videoPlaybackOwner {
            videoPlaybackOwner.setGalleryChromeController(visibilityChanged)
            videoPlaybackOwner.setGalleryChromeVisible(isVisible, animated: false)
        } else {
            contentMediaView?.setGalleryChromeController(visibilityChanged)
            contentMediaView?.setGalleryChromeVisible(isVisible, animated: false)
        }
    }

    func unbindGalleryChrome() {
        videoPlaybackOwner?.setGalleryChromeController(nil)
        contentMediaView?.setGalleryChromeController(nil)
    }

    func setGalleryChromeVisible(_ isVisible: Bool, animated: Bool) {
        if let videoPlaybackOwner {
            videoPlaybackOwner.setGalleryChromeVisible(isVisible, animated: animated)
        } else {
            contentMediaView?.setGalleryChromeVisible(isVisible, animated: animated)
        }
    }

    func setGalleryChromeBottomInset(_ inset: CGFloat) {
        if let videoPlaybackOwner {
            videoPlaybackOwner.setGalleryChromeBottomInset(inset)
        } else {
            contentMediaView?.setGalleryChromeBottomInset(inset)
        }
    }

    func setGalleryChromeInteractionActive(_ isActive: Bool) {
        if let videoPlaybackOwner {
            videoPlaybackOwner.setGalleryChromeInteractionActive(isActive)
        } else {
            contentMediaView?.setGalleryChromeInteractionActive(isActive)
        }
    }

    func canBeginInteractiveDismissal(at point: CGPoint) -> Bool {
        if let videoPlaybackOwner {
            return videoPlaybackOwner.canBeginInteractiveDismissal(at: point, in: contentView)
        }
        guard let contentMediaView else { return false }
        return contentMediaView.canBeginInteractiveDismissal(
            at: contentMediaView.convert(point, from: contentView),
        )
    }

    func setInteractiveDismissalActive(_ isActive: Bool) {
        if let videoPlaybackOwner {
            videoPlaybackOwner.setInteractiveDismissalActive(isActive)
        } else {
            contentMediaView?.setInteractiveDismissalActive(isActive)
        }
    }

    func transitionContentFrame(in coordinateSpace: UIView) -> CGRect? {
        guard let transitionMediaSize,
              transitionMediaSize.width > 0,
              transitionMediaSize.height > 0,
              contentView.bounds.width > 0,
              contentView.bounds.height > 0
        else { return nil }
        let contentFrame = AVMakeRect(aspectRatio: transitionMediaSize, insideRect: contentView.bounds)
        return contentView.convert(contentFrame, to: coordinateSpace)
    }

    func makeTransitionSnapshot() -> UIView? {
        if let videoPlaybackOwner {
            return videoPlaybackOwner.makeTransitionSnapshot(contentMode: .scaleAspectFit)
        }
        guard let transitionMediaSize else { return contentView.snapshotView(afterScreenUpdates: false) }
        let contentFrame = AVMakeRect(aspectRatio: transitionMediaSize, insideRect: contentView.bounds)
        return contentView.resizableSnapshotView(
            from: contentFrame,
            afterScreenUpdates: false,
            withCapInsets: .zero,
        ) ?? contentView.snapshotView(afterScreenUpdates: false)
    }
}

// MARK: - GalleryMediaView

protocol GalleryMediaView: AnyObject {
    func canBeginInteractiveDismissal(at point: CGPoint) -> Bool
    func performPlaybackCommand(_ command: GalleryPlaybackCommand)
    func prepareForReuse()
    func setGalleryChromeController(_ visibilityChanged: ((Bool) -> Void)?)
    func setGalleryChromeBottomInset(_ inset: CGFloat)
    func setGalleryChromeVisible(_ isVisible: Bool, animated: Bool)
    func setGalleryChromeInteractionActive(_ isActive: Bool)
    func setInteractiveDismissalActive(_ isActive: Bool)
    func setPlaybackVisible(_ isVisible: Bool)
}

extension GalleryMediaView {
    func canBeginInteractiveDismissal(at _: CGPoint) -> Bool { true }
    func performPlaybackCommand(_: GalleryPlaybackCommand) {}
    func setGalleryChromeController(_: ((Bool) -> Void)?) {}
    func setGalleryChromeBottomInset(_: CGFloat) {}
    func setGalleryChromeVisible(_: Bool, animated _: Bool) {}
    func setGalleryChromeInteractionActive(_: Bool) {}
    func setInteractiveDismissalActive(_: Bool) {}
    func setPlaybackVisible(_: Bool) {}
}

// MARK: - TGSStickerView + GalleryMediaView

extension TGSStickerView: GalleryMediaView {}

// MARK: - AnimatedWebPView + GalleryMediaView

extension AnimatedWebPView: GalleryMediaView {}

// MARK: - FFmpegAnimatedVideoView + GalleryMediaView

extension FFmpegAnimatedVideoView: GalleryMediaView {}

// MARK: - ZoomableGalleryImageView

final class ZoomableGalleryImageView: UIScrollView, UIScrollViewDelegate, GalleryMediaView {
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

    func canBeginInteractiveDismissal(at _: CGPoint) -> Bool {
        zoomScale <= minimumZoomScale + 0.001
            && !isZooming
            && !isZoomBouncing
            && !isDecelerating
    }

    func setInteractiveDismissalActive(_ isActive: Bool) {
        panGestureRecognizer.isEnabled = !isActive
        pinchGestureRecognizer?.isEnabled = !isActive
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

final class GalleryFilePlayerView: UIView, GalleryMediaView, UIGestureRecognizerDelegate {
    // MARK: Private

    private struct VODConfiguration {
        let fileName: String
        let mimeType: String
        let supportsStreaming: Bool
        let usesFFmpeg: Bool
        var startTimestamp: TimeInterval
    }

    private enum RetryMode {
        case fullDownload
        case vod
    }

    private static let controlsAutoHideDelay = TimeInterval(4)

    var onPictureInPictureToggle: (() -> Void)?
    var onPictureInPictureEligibilityChanged: (() -> Void)?
    var onPlaybackIntentChanged: (() -> Void)?

    private let preview = TDImageLoadingView()
    private let videoSurface = LocalVideoSurfaceView(frame: .zero)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private let controlsView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let controlsStack = UIStackView()
    private let scrubberStack = UIStackView()
    private let transportStack = UIStackView()
    private let transportSpacer = UIView()
    private let networkStatusLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let jumpBackwardButton = UIButton(type: .system)
    private let jumpForwardButton = UIButton(type: .system)
    private let timeLabel = UILabel()
    private let seekSlider = GalleryBufferedSlider()
    private let muteButton = UIButton(type: .system)
    private let rateButton = UIButton(type: .system)
    private let pictureInPictureButton = UIButton(type: .system)
    private let player = LocalMediaPlayer()
    private var controlsBottomConstraint: NSLayoutConstraint!
    private var ffmpegPlayer: TDLibVODFFmpegSampleBufferPlayer?
    private var ffmpegCloseTask: Task<Void, Never>?
    private var fileID: Int?
    private var task: Task<Void, Never>?
    private var playbackCancellable: AnyCancellable?
    private var timeCancellable: AnyCancellable?
    private var durationCancellable: AnyCancellable?
    private var bufferedRangesCancellable: AnyCancellable?
    private var streamingStatusCancellable: AnyCancellable?
    private var voiceOverCancellable: AnyCancellable?
    private var displayCancellable: AnyCancellable?
    private var ffmpegFailureCancellable: AnyCancellable?
    private var ffmpegReadyCancellable: AnyCancellable?
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
    private var usesFFmpegVOD = false
    private var currentPlaybackState = LocalMediaPlayer.State.idle
    private var isSeeking = false
    private var resumeAfterSeeking = false
    private var isUserPaused = false
    private var isMuted = false
    private var playbackRate: Float = 1
    private var currentPlaybackTime = TimeInterval.zero
    private var playbackDuration = TimeInterval.zero
    private var bufferedRanges = [LocalMediaPlayer.BufferedRange]()
    private var currentStreamingStatus = TDLibVODResourceLoaderStatus.idle
    private var currentFFmpegFailure: TDLibVODFFmpegSampleBufferPlayer.Failure?
    private var playbackBindingGeneration = UInt64.zero
    private var isPictureInPictureActive = false
    private var isPictureInPictureRetainedByOwner = false
    private var deferredPictureInPictureFailureResolution: (() -> Void)?
    private var sampleBufferPictureInPictureRenderSize: CMVideoDimensions?
    private var vodRanges = TDLib.shared.vodRanges
    private var controlsAreVisible = false
    private var controlsAutoHideWorkItem: DispatchWorkItem?
    private var controlsTapGesture: UITapGestureRecognizer?
    private var onGalleryChromeVisibilityChanged: ((Bool) -> Void)?
    private var galleryChromeInteractionIsActive = false
    private var isInlinePresentation = false
    private var mutedBeforeInlinePresentation: Bool?
    private var waitsForInitialPlaybackVisibility = false
    private var vodConfiguration: VODConfiguration?
    private var retryMode: RetryMode?
    private var retryStatusText: String?
    #if DEBUG
        private var debugPlaybackCommands = [GalleryPlaybackCommand]()
    #endif

    // MARK: Internal

    var pictureInPicturePlayerLayer: AVPlayerLayer {
        videoSurface.playerLayer
    }

    var pictureInPictureSourceKind: GalleryPictureInPictureSourceKind {
        usesFFmpegVOD && ffmpegPlayer?.pictureInPictureDisplayLayer != nil
            ? .sampleBufferDisplayLayer
            : .playerLayer
    }

    var pictureInPictureSourceIdentity: GalleryPictureInPictureSourceIdentity {
        if pictureInPictureSourceKind == .sampleBufferDisplayLayer,
           let displayLayer = ffmpegPlayer?.pictureInPictureDisplayLayer
        {
            return GalleryPictureInPictureSourceIdentity(
                kind: .sampleBufferDisplayLayer,
                layerIdentifier: ObjectIdentifier(displayLayer),
            )
        }
        return GalleryPictureInPictureSourceIdentity(
            kind: .playerLayer,
            layerIdentifier: ObjectIdentifier(pictureInPicturePlayerLayer),
        )
    }

    var sampleBufferPictureInPictureTimeRange: CMTimeRange {
        guard pictureInPictureSourceKind == .sampleBufferDisplayLayer,
              playbackDuration.isFinite,
              playbackDuration > 0
        else { return .invalid }
        let upperBound = max(playbackDuration, playbackCurrentTime + 0.001)
        return CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: upperBound, preferredTimescale: 600),
        )
    }

    var sampleBufferPictureInPictureCurrentTime: TimeInterval {
        playbackCurrentTime
    }

    var sampleBufferPictureInPictureDuration: TimeInterval {
        playbackDuration
    }

    var sampleBufferPictureInPictureIsPaused: Bool {
        currentPlaybackState != .playing
    }

    var sampleBufferPictureInPictureHasTerminalFailure: Bool {
        currentPlaybackState == .failed || currentFFmpegFailure != nil
    }

    var isPictureInPictureReady: Bool {
        guard !loopsPlayback, isSurfaceReady else { return false }
        switch pictureInPictureSourceKind {
        case .playerLayer:
            guard player.hasItem else { return false }
        case .sampleBufferDisplayLayer:
            guard ffmpegPlayer?.hasItem == true,
                  playbackDuration > 0
            else { return false }
        }
        return switch currentPlaybackState {
        case .buffering, .ended, .paused, .playing:
            true
        case .failed, .idle, .preparing:
            false
        }
    }

    var isPlaybackRequested: Bool {
        playbackIsRequested
    }

    #if DEBUG
        var pictureInPictureControlIsHidden: Bool {
            pictureInPictureButton.isHidden
        }

        var debugPictureInPictureControlIsEnabled: Bool {
            pictureInPictureButton.isEnabled
        }

        var debugPlaybackCommandProbePassed: Bool {
            let commandsPassed = debugPlaybackCommands == [
                .jump(-15),
                .jump(15),
                .togglePlayback,
            ]
            let backward = Self.resolveJump(current: 3, duration: 20, interval: -15)
            let pastEnd = Self.resolveJump(current: 9, duration: 20, interval: 15)
            return commandsPassed
                && backward.time == 0
                && !backward.shouldPauseAtStart
                && pastEnd.time == 0
                && pastEnd.shouldPauseAtStart
        }

        var debugPlaybackControlsLayoutProbePassed: Bool {
            let transportButtons = [
                jumpBackwardButton,
                playButton,
                jumpForwardButton,
                muteButton,
                rateButton,
                pictureInPictureButton,
            ]
            let fixedTransportWidth = CGFloat(transportButtons.count * 44)
                + CGFloat((transportStack.arrangedSubviews.count - 1) * 4)
            seekSlider.bufferedRanges = [0...0.25, 0.5...0.75]
            seekSlider.layoutIfNeeded()
            return controlsStack.axis == .vertical
                && controlsStack.arrangedSubviews.first === networkStatusLabel
                && scrubberStack.arrangedSubviews == [timeLabel, seekSlider]
                && transportButtons.allSatisfy { button in
                    button.constraints.contains { $0.firstAttribute == .width && $0.constant == 44 }
                        && button.constraints.contains { $0.firstAttribute == .height && $0.constant == 44 }
                }
                && fixedTransportWidth <= 296
                && seekSlider.debugBufferedSegmentCount == 2
        }

        var debugControlsAutoHidePolicyProbePassed: Bool {
            Self.controlsAutoHideDelay == 4
                && Self.shouldAutoHideControls(
                    state: .playing,
                    isSeeking: false,
                    isPlaybackVisible: true,
                    isPictureInPictureActive: false,
                    isVoiceOverRunning: false,
                )
                && !Self.shouldAutoHideControls(
                    state: .paused,
                    isSeeking: false,
                    isPlaybackVisible: true,
                    isPictureInPictureActive: false,
                    isVoiceOverRunning: false,
                )
                && !Self.shouldAutoHideControls(
                    state: .playing,
                    isSeeking: true,
                    isPlaybackVisible: true,
                    isPictureInPictureActive: false,
                    isVoiceOverRunning: false,
                )
                && !Self.shouldAutoHideControls(
                    state: .playing,
                    isSeeking: false,
                    isPlaybackVisible: true,
                    isPictureInPictureActive: false,
                    isVoiceOverRunning: true,
                )
        }

        var debugIsInlinePresentation: Bool {
            isInlinePresentation
        }

        var debugCurrentItemIdentifier: ObjectIdentifier? {
            playbackItemIdentifier
        }

        var debugPlaybackTime: TimeInterval {
            playbackCurrentTime
        }

        var debugIsMuted: Bool {
            playbackIsMuted
        }

        var debugUsesFFmpegPlayback: Bool {
            usesFFmpegVOD && ffmpegPlayer != nil
        }

        var debugSampleBufferPictureInPictureDisplayLayer: AVSampleBufferDisplayLayer? {
            ffmpegPlayer?.pictureInPictureDisplayLayer
        }

        var debugSampleBufferPictureInPictureLayerIsVisible: Bool {
            ffmpegPlayer?.surfaceView.isHidden == false
        }

        var debugSampleBufferPictureInPictureRenderSize: CMVideoDimensions? {
            sampleBufferPictureInPictureRenderSize
        }

        var debugHasDeferredPictureInPictureFailureResolution: Bool {
            deferredPictureInPictureFailureResolution != nil
        }

        var debugPlaybackState: LocalMediaPlayer.State {
            currentPlaybackState
        }

        var debugPlaybackSurfaceIsReady: Bool {
            isSurfaceReady
        }

        func debugForceVODSeek(to time: TimeInterval) {
            playbackPlay(from: time)
        }

        func debugSimulateFFmpegOfflineFailure() {
            guard usesFFmpegVOD, sourceFile != nil else { return }
            currentStreamingStatus = .offline
            render(state: .failed)
        }

        func debugWaitForFFmpegClose() async {
            await ffmpegCloseTask?.value
        }
    #endif

    private var canSeekPlayback: Bool {
        playbackDuration > 0 && currentPlaybackState != .failed
    }

    private var hasBlockingStreamingStatus: Bool {
        usesLegacyDownload
            || retryStatusText != nil
            || currentStreamingStatus == .failed
            || currentStreamingStatus == .offline
            || currentStreamingStatus == .retrying
    }

    private var currentFFmpegFailureIsRetryable: Bool {
        switch currentFFmpegFailure {
        case .offline, .retryable:
            true
        case .decoding, nil, .renderer, .terminal:
            false
        }
    }

    private var playbackIsRequested: Bool {
        ffmpegPlayer?.isPlaybackRequested ?? player.isPlaybackRequested
    }

    private var playbackItemIdentifier: ObjectIdentifier? {
        ffmpegPlayer?.currentItemIdentifier ?? player.currentItemIdentifier
    }

    private var playbackCurrentTime: TimeInterval {
        ffmpegPlayer?.currentTime ?? player.currentTime
    }

    private var playbackIsMuted: Bool {
        ffmpegPlayer?.isMuted ?? player.isMuted
    }

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
        configurePlaybackControls()
        let controlsTapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleControlsVisibility))
        controlsTapGesture.cancelsTouchesInView = false
        controlsTapGesture.delegate = self
        self.controlsTapGesture = controlsTapGesture
        addGestureRecognizer(controlsTapGesture)
        addSubview(preview)
        addSubview(videoSurface)
        addSubview(spinner)
        addSubview(retryButton)
        addSubview(controlsView)
        self.controlsBottomConstraint = controlsView.bottomAnchor.constraint(
            equalTo: safeAreaLayoutGuide.bottomAnchor,
            constant: -50,
        )
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
            controlsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsBottomConstraint,
            controlsView.heightAnchor.constraint(equalToConstant: 136),
            controlsStack.leadingAnchor.constraint(equalTo: controlsView.contentView.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: controlsView.contentView.trailingAnchor, constant: -12),
            controlsStack.topAnchor.constraint(equalTo: controlsView.contentView.topAnchor, constant: 8),
            controlsStack.bottomAnchor.constraint(equalTo: controlsView.contentView.bottomAnchor, constant: -8),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
            networkStatusLabel.heightAnchor.constraint(equalToConstant: 20),
            scrubberStack.heightAnchor.constraint(equalToConstant: 36),
            jumpBackwardButton.widthAnchor.constraint(equalToConstant: 44),
            jumpBackwardButton.heightAnchor.constraint(equalToConstant: 44),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            jumpForwardButton.widthAnchor.constraint(equalToConstant: 44),
            jumpForwardButton.heightAnchor.constraint(equalToConstant: 44),
            muteButton.widthAnchor.constraint(equalToConstant: 44),
            muteButton.heightAnchor.constraint(equalToConstant: 44),
            rateButton.widthAnchor.constraint(equalToConstant: 44),
            rateButton.heightAnchor.constraint(equalToConstant: 44),
            pictureInPictureButton.widthAnchor.constraint(equalToConstant: 44),
            pictureInPictureButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func shouldAutoHideControls(
        state: LocalMediaPlayer.State,
        isSeeking: Bool,
        isPlaybackVisible: Bool,
        isPictureInPictureActive: Bool,
        isVoiceOverRunning: Bool,
    ) -> Bool {
        state == .playing
            && !isSeeking
            && isPlaybackVisible
            && !isPictureInPictureActive
            && !isVoiceOverRunning
    }

    private static func resolveJump(
        current: TimeInterval,
        duration: TimeInterval,
        interval: TimeInterval,
    ) -> (time: TimeInterval, shouldPauseAtStart: Bool) {
        let target = max(0, current + interval)
        if interval > 0, duration > 0, target >= duration {
            return (0, true)
        }
        return (target, false)
    }

    func makePictureInPictureContentSource(
        playbackDelegate: any AVPictureInPictureSampleBufferPlaybackDelegate,
    ) -> AVPictureInPictureController.ContentSource? {
        switch pictureInPictureSourceKind {
        case .playerLayer:
            return AVPictureInPictureController.ContentSource(
                playerLayer: pictureInPicturePlayerLayer,
            )
        case .sampleBufferDisplayLayer:
            guard let displayLayer = ffmpegPlayer?.pictureInPictureDisplayLayer else { return nil }
            return AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: playbackDelegate,
            )
        }
    }

    func makeTransitionSnapshot(contentMode: UIView.ContentMode) -> UIView? {
        if preview.image != nil {
            return preview.makeImageSnapshot(contentMode: contentMode)
        }
        if let ffmpegSurface = ffmpegPlayer?.surfaceView,
           !ffmpegSurface.isHidden,
           let snapshot = ffmpegSurface.snapshotView(afterScreenUpdates: false)
        {
            return snapshot
        }
        if !videoSurface.isHidden,
           let snapshot = videoSurface.snapshotView(afterScreenUpdates: false)
        {
            return snapshot
        }
        return preview.snapshotView(afterScreenUpdates: false)
    }

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
        vodRanges: TDLibVODRangeCoordinator = TDLib.shared.vodRanges,
        deferPlaybackUntilVisible: Bool = false,
    ) {
        prepareForReuse()
        fileID = file.id
        sourceFile = file
        startPlaybackTimestamp = startTimestamp
        self.vodRanges = vodRanges
        loopsPlayback = loops
        if let mimeType,
           let fileName
        {
            let usesFFmpeg = telegramVideoUsesFFmpeg(
                mimeType: mimeType,
                fileName: fileName,
            )
            let allowsRangeStreaming = supportsStreaming && !isSecret
            if allowsRangeStreaming || usesFFmpeg {
                vodConfiguration = VODConfiguration(
                    fileName: fileName,
                    mimeType: mimeType,
                    supportsStreaming: allowsRangeStreaming,
                    usesFFmpeg: usesFFmpeg,
                    startTimestamp: startTimestamp,
                )
            }
        }
        videoSurface.isHidden = true
        if let thumbnail {
            preview.load(file: thumbnail.file, placeholderData: minithumbnail?.data)
        } else {
            preview.loadPlaceholder(data: minithumbnail?.data)
        }
        guard canPlay, UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true else { return }
        spinner.startAnimating()
        retryButton.isHidden = true
        controlsAreVisible = !loops
        controlsView.alpha = 1
        controlsView.isHidden = loops
        isUserPaused = false
        isMuted = false
        playbackRate = 1
        isSeeking = false
        resumeAfterSeeking = false
        currentPlaybackTime = 0
        playbackDuration = 0
        seekSlider.value = 0
        seekSlider.isEnabled = false
        updatePlaybackTime(0)
        updateControlIcons()
        configureVoiceOverObservation()
        bindLocalPlaybackPublishers()
        waitsForInitialPlaybackVisibility = deferPlaybackUntilVisible
        if deferPlaybackUntilVisible {
            spinner.stopAnimating()
        } else {
            beginInitialPlayback(file: file)
        }
    }

    func prepareForReuse() {
        cancelControlsAutoHide()
        controlsView.layer.removeAllAnimations()
        setPictureInPictureActive(false)
        cancelControlsAutoHide()
        onPictureInPictureToggle = nil
        onPictureInPictureEligibilityChanged = nil
        onPlaybackIntentChanged = nil
        onGalleryChromeVisibilityChanged = nil
        galleryChromeInteractionIsActive = false
        loadIdentifier = nil
        sourceFile = nil
        usesLegacyDownload = false
        usesVOD = false
        usesFFmpegVOD = false
        player.stop()
        stopFFmpegPlayback()
        task?.cancel()
        task = nil
        playbackCancellable?.cancel()
        playbackCancellable = nil
        timeCancellable?.cancel()
        timeCancellable = nil
        durationCancellable?.cancel()
        durationCancellable = nil
        bufferedRangesCancellable?.cancel()
        bufferedRangesCancellable = nil
        streamingStatusCancellable?.cancel()
        streamingStatusCancellable = nil
        ffmpegReadyCancellable?.cancel()
        ffmpegReadyCancellable = nil
        ffmpegFailureCancellable?.cancel()
        ffmpegFailureCancellable = nil
        voiceOverCancellable?.cancel()
        voiceOverCancellable = nil
        preview.cancel()
        spinner.stopAnimating()
        retryButton.isHidden = true
        controlsView.isHidden = true
        controlsView.alpha = 1
        controlsAreVisible = false
        controlsTapGesture?.isEnabled = true
        isInlinePresentation = false
        mutedBeforeInlinePresentation = nil
        waitsForInitialPlaybackVisibility = false
        videoSurface.playerLayer.videoGravity = .resizeAspect
        videoSurface.playerLayer.player = nil
        videoSurface.isHidden = true
        fileID = nil
        isPlaybackVisible = false
        isSurfaceReady = false
        loopsPlayback = false
        loadedPath = nil
        vodConfiguration = nil
        retryMode = nil
        retryStatusText = nil
        currentStreamingStatus = .idle
        currentFFmpegFailure = nil
        startPlaybackTimestamp = 0
        surfaceItemIdentifier = nil
        currentPlaybackState = .idle
        isSeeking = false
        resumeAfterSeeking = false
        isUserPaused = false
        isMuted = false
        isPictureInPictureActive = false
        isPictureInPictureRetainedByOwner = false
        deferredPictureInPictureFailureResolution = nil
        sampleBufferPictureInPictureRenderSize = nil
        playbackRate = 1
        currentPlaybackTime = 0
        playbackDuration = 0
        bufferedRanges = []
        seekSlider.value = 0
        seekSlider.bufferedRanges = []
        seekSlider.isEnabled = false
        updatePlaybackTime(0)
        updateControlIcons()
        renderStreamingStatus(.idle)
        updatePictureInPictureEligibility()
    }

    func setPresentationContext(_ context: VideoPlaybackAttachmentContext) {
        let shouldPresentInline = context == .inline
        guard isInlinePresentation != shouldPresentInline else { return }
        isInlinePresentation = shouldPresentInline
        controlsTapGesture?.isEnabled = !shouldPresentInline && onGalleryChromeVisibilityChanged == nil
        videoSurface.playerLayer.videoGravity = shouldPresentInline ? .resizeAspectFill : .resizeAspect
        ffmpegPlayer?.surfaceView.videoGravity = shouldPresentInline ? .resizeAspectFill : .resizeAspect
        if shouldPresentInline {
            mutedBeforeInlinePresentation = isMuted
            isMuted = true
            playbackSetMuted(true)
            setControlsVisible(false, animated: false)
        } else {
            isMuted = mutedBeforeInlinePresentation ?? isMuted
            mutedBeforeInlinePresentation = nil
            playbackSetMuted(isMuted)
            if !loopsPlayback {
                setControlsVisible(true, animated: false)
                scheduleControlsAutoHideIfNeeded()
            }
        }
        updateControlIcons()
    }

    func setGalleryChromeController(_ visibilityChanged: ((Bool) -> Void)?) {
        onGalleryChromeVisibilityChanged = visibilityChanged
        controlsTapGesture?.isEnabled = !isInlinePresentation && visibilityChanged == nil
    }

    func setGalleryChromeBottomInset(_ inset: CGFloat) {
        controlsBottomConstraint.constant = -max(0, inset)
    }

    func setGalleryChromeInteractionActive(_ isActive: Bool) {
        guard galleryChromeInteractionIsActive != isActive else { return }
        galleryChromeInteractionIsActive = isActive
        if isActive {
            cancelControlsAutoHide()
            setControlsVisible(true, animated: true)
        } else {
            scheduleControlsAutoHideIfNeeded()
        }
    }

    func setGalleryChromeVisible(_ isVisible: Bool, animated: Bool) {
        guard !loopsPlayback, !isInlinePresentation else { return }
        let isVisible = UIAccessibility.isVoiceOverRunning ? true : isVisible
        setControlsVisible(isVisible, animated: animated)
        if isVisible {
            scheduleControlsAutoHideIfNeeded()
        }
    }

    func canBeginInteractiveDismissal(at point: CGPoint) -> Bool {
        guard !isSeeking,
              !isPictureInPictureActive,
              !isPictureInPictureRetainedByOwner,
              deferredPictureInPictureFailureResolution == nil
        else { return false }
        if !retryButton.isHidden, retryButton.frame.contains(point) {
            return false
        }
        if !controlsView.isHidden,
           controlsView.alpha > 0.01,
           controlsView.frame.contains(point)
        {
            return false
        }
        return true
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        if !isVisible, isSeeking {
            isSeeking = false
            resumeAfterSeeking = false
            seekSlider.value = Float(min(playbackDuration, currentPlaybackTime))
            updateTimeLabel(current: currentPlaybackTime)
        }
        isPlaybackVisible = isVisible
        if isVisible, waitsForInitialPlaybackVisibility, let sourceFile {
            waitsForInitialPlaybackVisibility = false
            spinner.startAnimating()
            beginInitialPlayback(file: sourceFile)
        }
        if !isVisible {
            cancelControlsAutoHide()
        }
        if isPictureInPictureActive {
            return
        }
        playbackSetVisible(isVisible)
        if isVisible, !isUserPaused {
            playbackPlay()
        } else if isVisible || ffmpegPlayer == nil {
            playbackPause()
        }
    }

    func setPictureInPictureActive(_ isActive: Bool) {
        guard isPictureInPictureActive != isActive else { return }
        isPictureInPictureActive = isActive
        if isActive {
            cancelControlsAutoHide()
        }
        if !usesFFmpegVOD {
            player.setExternalPlaybackControlActive(isActive)
        }
        if !isActive {
            isUserPaused = !playbackIsRequested
            if isPlaybackVisible, !isUserPaused {
                playbackPlay()
            } else if !isPlaybackVisible {
                playbackPause()
            }
            scheduleControlsAutoHideIfNeeded()
        }
        updateControlIcons()
        onPlaybackIntentChanged?()
    }

    func setPictureInPictureRetained(_ isRetained: Bool) {
        guard isPictureInPictureRetainedByOwner != isRetained else { return }
        isPictureInPictureRetainedByOwner = isRetained
        guard !isRetained else { return }
        let resolution = deferredPictureInPictureFailureResolution
        deferredPictureInPictureFailureResolution = nil
        resolution?()
    }

    func setSampleBufferPictureInPicturePlaying(_ playing: Bool) {
        guard pictureInPictureSourceKind == .sampleBufferDisplayLayer else { return }
        isUserPaused = !playing
        if playing {
            playbackSetVisible(true)
            playbackPlay()
        } else {
            playbackPause()
        }
        updateControlIcons()
        updatePictureInPictureEligibility()
        onPlaybackIntentChanged?()
    }

    func skipSampleBufferPictureInPicture(
        by interval: TimeInterval,
        completion: @escaping () -> Void,
    ) {
        guard interval.isFinite,
              let ffmpegPlayer,
              ffmpegPlayer.hasItem,
              playbackDuration > 0
        else {
            completion()
            return
        }
        let requestedTarget = max(0, playbackCurrentTime + interval)
        let skipsPastEnd = interval > 0 && requestedTarget >= playbackDuration
        let target = skipsPastEnd ? 0 : min(playbackDuration, requestedTarget)
        if skipsPastEnd {
            isUserPaused = true
            ffmpegPlayer.pause()
        }
        currentPlaybackTime = target
        ffmpegPlayer.seek(to: target, completion: completion)
        updateTimeLabel(current: target)
        updateControlIcons()
        updatePictureInPictureEligibility()
        onPlaybackIntentChanged?()
    }

    func setSampleBufferPictureInPictureRenderSize(_ renderSize: CMVideoDimensions) {
        sampleBufferPictureInPictureRenderSize = renderSize
    }

    func setPictureInPictureControl(visible: Bool, enabled: Bool, active: Bool) {
        pictureInPictureButton.isHidden = !visible
        pictureInPictureButton.isEnabled = enabled
        pictureInPictureButton.alpha = enabled ? 1 : 0.45
        pictureInPictureButton.setImage(
            UIImage(systemName: active ? "pip.exit" : "pip.enter"),
            for: .normal,
        )
        pictureInPictureButton.accessibilityLabel = active
            ? "Stop Picture in Picture"
            : "Start Picture in Picture"
    }

    func performPlaybackCommand(_ command: GalleryPlaybackCommand) {
        #if DEBUG
            debugPlaybackCommands.append(command)
        #endif
        switch command {
        case .jump(let interval):
            guard canSeekPlayback else { return }
            jumpPlayback(by: interval)
        case .togglePictureInPicture:
            togglePictureInPicture()
        case .togglePlayback:
            guard currentPlaybackState != .failed else { return }
            togglePlayback()
        }
    }

    func pauseForAudioTakeover() {
        isUserPaused = true
        playbackPause()
        updateControlIcons()
        onPlaybackIntentChanged?()
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !loopsPlayback else { return false }
        if let touchedView = touch.view,
           touchedView.isDescendant(of: controlsView) || touchedView.isDescendant(of: retryButton)
        {
            return false
        }
        return true
    }

    private func playbackPlay() {
        if let ffmpegPlayer {
            ffmpegPlayer.play()
        } else {
            player.play()
        }
    }

    private func playbackPause() {
        if let ffmpegPlayer {
            ffmpegPlayer.pause()
        } else {
            player.pause()
        }
    }

    private func playbackPlay(from time: TimeInterval) {
        if let ffmpegPlayer {
            ffmpegPlayer.play()
            ffmpegPlayer.seek(to: time)
        } else {
            player.play(from: time)
        }
    }

    private func playbackSeek(to time: TimeInterval, tolerance: TimeInterval = 0.05) {
        if let ffmpegPlayer {
            ffmpegPlayer.seek(to: time)
        } else {
            player.seek(to: time, tolerance: tolerance)
        }
    }

    private func playbackSetMuted(_ muted: Bool) {
        if let ffmpegPlayer {
            ffmpegPlayer.setMuted(muted)
        } else {
            player.setMuted(muted)
        }
    }

    private func playbackSetRate(_ rate: Float) {
        if let ffmpegPlayer {
            ffmpegPlayer.setRate(rate)
        } else {
            player.setRate(rate)
        }
    }

    private func playbackSetVisible(_ isVisible: Bool) {
        if let ffmpegPlayer {
            ffmpegPlayer.setPlaybackVisible(isVisible)
        }
    }

    private func cancelPlaybackPublishers() {
        playbackBindingGeneration &+= 1
        playbackCancellable?.cancel()
        playbackCancellable = nil
        timeCancellable?.cancel()
        timeCancellable = nil
        durationCancellable?.cancel()
        durationCancellable = nil
        bufferedRangesCancellable?.cancel()
        bufferedRangesCancellable = nil
        streamingStatusCancellable?.cancel()
        streamingStatusCancellable = nil
        ffmpegReadyCancellable?.cancel()
        ffmpegReadyCancellable = nil
        ffmpegFailureCancellable?.cancel()
        ffmpegFailureCancellable = nil
    }

    private func bindLocalPlaybackPublishers() {
        cancelPlaybackPublishers()
        currentFFmpegFailure = nil
        let generation = playbackBindingGeneration
        playbackCancellable = player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self,
                      playbackBindingGeneration == generation,
                      ffmpegPlayer == nil
                else { return }
                render(state: state)
            }
        timeCancellable = player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self,
                      playbackBindingGeneration == generation,
                      ffmpegPlayer == nil
                else { return }
                updatePlaybackTime(time)
            }
        durationCancellable = player.durationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self,
                      playbackBindingGeneration == generation,
                      ffmpegPlayer == nil
                else { return }
                updatePlaybackDuration(duration)
            }
        bufferedRangesCancellable = player.bufferedRangesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ranges in
                guard let self,
                      playbackBindingGeneration == generation,
                      ffmpegPlayer == nil
                else { return }
                updateBufferedRanges(ranges)
            }
        streamingStatusCancellable = player.streamingStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self,
                      playbackBindingGeneration == generation,
                      ffmpegPlayer == nil
                else { return }
                renderStreamingStatus(status)
            }
    }

    private func bindFFmpegPlaybackPublishers(_ ffmpegPlayer: TDLibVODFFmpegSampleBufferPlayer) {
        cancelPlaybackPublishers()
        currentFFmpegFailure = nil
        let generation = playbackBindingGeneration
        playbackCancellable = ffmpegPlayer.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self,
                      playbackBindingGeneration == generation,
                      self.ffmpegPlayer === ffmpegPlayer
                else { return }
                render(state: state)
            }
        timeCancellable = ffmpegPlayer.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self,
                      playbackBindingGeneration == generation,
                      self.ffmpegPlayer === ffmpegPlayer
                else { return }
                updatePlaybackTime(time)
            }
        durationCancellable = ffmpegPlayer.durationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self,
                      playbackBindingGeneration == generation,
                      self.ffmpegPlayer === ffmpegPlayer
                else { return }
                updatePlaybackDuration(duration)
            }
        bufferedRangesCancellable = ffmpegPlayer.bufferedRangesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ranges in
                guard let self,
                      playbackBindingGeneration == generation,
                      self.ffmpegPlayer === ffmpegPlayer
                else { return }
                updateBufferedRanges(ranges)
            }
        streamingStatusCancellable = ffmpegPlayer.streamingStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self,
                      playbackBindingGeneration == generation,
                      self.ffmpegPlayer === ffmpegPlayer
                else { return }
                renderStreamingStatus(status)
            }
        ffmpegFailureCancellable = ffmpegPlayer.failurePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] failure in
                guard let self,
                      playbackBindingGeneration == generation,
                      self.ffmpegPlayer === ffmpegPlayer
                else { return }
                currentFFmpegFailure = failure
            }
        ffmpegReadyCancellable = ffmpegPlayer.readyForDisplayPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                guard let self,
                      playbackBindingGeneration == generation,
                      self.ffmpegPlayer === ffmpegPlayer
                else { return }
                isSurfaceReady = isReady
                refreshPlaybackSurfaceVisibility()
            }
    }

    private func stopFFmpegPlayback() {
        guard let ffmpegPlayer else { return }
        self.ffmpegPlayer = nil
        ffmpegReadyCancellable?.cancel()
        ffmpegReadyCancellable = nil
        ffmpegFailureCancellable?.cancel()
        ffmpegFailureCancellable = nil
        currentFFmpegFailure = nil
        ffmpegPlayer.surfaceView.removeFromSuperview()
        ffmpegCloseTask = Task { @MainActor [weak self] in
            await ffmpegPlayer.close()
            self?.updatePictureInPictureEligibility()
        }
    }

    private func configurePlaybackControls() {
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.isHidden = true
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.axis = .vertical
        controlsStack.alignment = .fill
        controlsStack.spacing = 4
        controlsView.contentView.addSubview(controlsStack)
        scrubberStack.axis = .horizontal
        scrubberStack.alignment = .center
        scrubberStack.spacing = 8
        transportStack.axis = .horizontal
        transportStack.alignment = .center
        transportStack.spacing = 4
        transportSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        transportSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        networkStatusLabel.font = .preferredFont(forTextStyle: .caption2)
        networkStatusLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        networkStatusLabel.textAlignment = .center
        networkStatusLabel.adjustsFontForContentSizeCategory = true
        networkStatusLabel.adjustsFontSizeToFitWidth = true
        networkStatusLabel.minimumScaleFactor = 0.7
        networkStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        networkStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        playButton.tintColor = .white
        playButton.accessibilityLabel = "Play"
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        jumpBackwardButton.tintColor = .white
        jumpBackwardButton.setImage(UIImage(systemName: "gobackward.15"), for: .normal)
        jumpBackwardButton.accessibilityLabel = "Back 15 seconds"
        jumpBackwardButton.addTarget(self, action: #selector(jumpPlaybackBackward), for: .touchUpInside)
        jumpForwardButton.tintColor = .white
        jumpForwardButton.setImage(UIImage(systemName: "goforward.15"), for: .normal)
        jumpForwardButton.accessibilityLabel = "Forward 15 seconds"
        jumpForwardButton.addTarget(self, action: #selector(jumpPlaybackForward), for: .touchUpInside)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        timeLabel.text = "0:00 / 0:00"
        seekSlider.minimumValue = 0
        seekSlider.maximumValue = 1
        seekSlider.minimumTrackTintColor = .white
        seekSlider.maximumTrackTintColor = .clear
        seekSlider.isEnabled = false
        seekSlider.accessibilityLabel = "Video position"
        seekSlider.accessibilityHint = "Swipe up or down to seek"
        seekSlider.addTarget(self, action: #selector(beginSeeking), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(seekValueChanged), for: .valueChanged)
        seekSlider.addTarget(
            self,
            action: #selector(endSeeking),
            for: [.touchUpInside, .touchUpOutside, .touchCancel],
        )
        muteButton.tintColor = .white
        muteButton.accessibilityLabel = "Mute"
        muteButton.addTarget(self, action: #selector(toggleMuted), for: .touchUpInside)
        rateButton.setTitle("1×", for: .normal)
        rateButton.setTitleColor(.white, for: .normal)
        rateButton.accessibilityLabel = "Playback speed"
        rateButton.accessibilityHint = "Cycles through available playback speeds"
        rateButton.addTarget(self, action: #selector(cyclePlaybackRate), for: .touchUpInside)
        pictureInPictureButton.tintColor = .white
        pictureInPictureButton.isHidden = true
        pictureInPictureButton.accessibilityLabel = "Start Picture in Picture"
        pictureInPictureButton.addTarget(
            self,
            action: #selector(togglePictureInPicture),
            for: .touchUpInside,
        )

        scrubberStack.addArrangedSubview(timeLabel)
        scrubberStack.addArrangedSubview(seekSlider)
        transportStack.addArrangedSubview(jumpBackwardButton)
        transportStack.addArrangedSubview(playButton)
        transportStack.addArrangedSubview(jumpForwardButton)
        transportStack.addArrangedSubview(transportSpacer)
        transportStack.addArrangedSubview(muteButton)
        transportStack.addArrangedSubview(rateButton)
        transportStack.addArrangedSubview(pictureInPictureButton)
        controlsStack.addArrangedSubview(networkStatusLabel)
        controlsStack.addArrangedSubview(scrubberStack)
        controlsStack.addArrangedSubview(transportStack)
        updateControlIcons()
    }

    private func beginInitialPlayback(file: File) {
        guard file.id == fileID else { return }
        if let vodConfiguration, vodConfiguration.usesFFmpeg {
            if file.local.isDownloadingCompleted || vodConfiguration.supportsStreaming {
                startVOD(
                    file: file,
                    mimeType: vodConfiguration.mimeType,
                    fileName: vodConfiguration.fileName,
                    startTimestamp: vodConfiguration.startTimestamp,
                )
            } else {
                startLegacyDownload(file: file)
            }
        } else if file.local.isDownloadingCompleted {
            update(file: file)
        } else if let vodConfiguration {
            startVOD(
                file: file,
                mimeType: vodConfiguration.mimeType,
                fileName: vodConfiguration.fileName,
                startTimestamp: vodConfiguration.startTimestamp,
            )
        } else {
            startLegacyDownload(file: file)
        }
    }

    private func startVOD(
        file: File,
        mimeType: String,
        fileName: String,
        startTimestamp: TimeInterval,
    ) {
        if telegramVideoUsesFFmpeg(mimeType: mimeType, fileName: fileName) {
            startFFmpegVOD(file: file, startTimestamp: startTimestamp)
            return
        }
        usesVOD = true
        usesFFmpegVOD = false
        retryMode = nil
        retryStatusText = nil
        renderStreamingStatus(.loading)
        let identifier = UUID()
        loadIdentifier = identifier
        let rangeCoordinator = vodRanges
        task = Task { [weak self] in
            let lease = await rangeCoordinator.acquire(file: file)
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
                self.bindLocalPlaybackPublishers()
                self.player.load(
                    vodSession: session,
                    autoplay: self.isPlaybackVisible && !self.isUserPaused,
                    loops: self.loopsPlayback,
                    initialTime: startTimestamp,
                )
                self.player.setMuted(self.isMuted)
                self.player.setRate(self.playbackRate)
                self.bindSurfaceToCurrentItem()
            }
        }
    }

    private func startFFmpegVOD(file: File, startTimestamp: TimeInterval) {
        usesVOD = true
        usesFFmpegVOD = true
        retryMode = nil
        retryStatusText = nil
        renderStreamingStatus(.loading)
        let identifier = UUID()
        loadIdentifier = identifier
        let rangeCoordinator = vodRanges
        task?.cancel()
        task = Task { @MainActor [weak self] in
            let lease = await rangeCoordinator.acquire(file: file)
            guard !Task.isCancelled else {
                await lease.invalidate()
                return
            }
            guard let self,
                  !Task.isCancelled,
                  loadIdentifier == identifier,
                  fileID == file.id
            else {
                await lease.invalidate()
                return
            }
            task = nil
            prepareSurfaceForNewItem()
            usesVOD = true
            usesFFmpegVOD = true
            let ffmpegPlayer = TDLibVODFFmpegSampleBufferPlayer(lease: lease)
            self.ffmpegPlayer = ffmpegPlayer
            let surfaceView = ffmpegPlayer.surfaceView
            surfaceView.translatesAutoresizingMaskIntoConstraints = false
            surfaceView.videoGravity = isInlinePresentation ? .resizeAspectFill : .resizeAspect
            surfaceView.isHidden = true
            insertSubview(surfaceView, aboveSubview: preview)
            NSLayoutConstraint.activate([
                surfaceView.topAnchor.constraint(equalTo: topAnchor),
                surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
                surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
                surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            bindFFmpegPlaybackPublishers(ffmpegPlayer)
            ffmpegPlayer.setMuted(isMuted)
            ffmpegPlayer.setRate(playbackRate)
            ffmpegPlayer.setPlaybackVisible(isPlaybackVisible)
            ffmpegPlayer.prepare(
                autoplay: isPlaybackVisible && !isUserPaused,
                initialTime: startTimestamp,
            )
            surfaceItemIdentifier = ffmpegPlayer.currentItemIdentifier
            updatePictureInPictureEligibility()
        }
    }

    private func startLegacyDownload(file: File) {
        guard file.id == fileID, !usesLegacyDownload else { return }
        spinner.startAnimating()
        retryButton.isHidden = true
        usesLegacyDownload = true
        usesVOD = false
        retryMode = nil
        retryStatusText = nil
        renderStreamingStatus(.loading)
        let identifier = UUID()
        loadIdentifier = identifier
        task?.cancel()
        let rangeCoordinator = vodRanges
        task = Task { [weak self] in
            let lease = await rangeCoordinator.acquire(
                file: file,
                requiresFullDownload: true,
            )
            let downloaded: File
            do {
                downloaded = try await lease.source.completedFile()
            } catch {
                let statusText = (error as? TDLibVODRangeError) == .offline
                    ? "Offline"
                    : "Couldn't load video"
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
                    self.showRetryState(statusText: statusText, retryMode: .fullDownload)
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
                self.usesLegacyDownload = false
                self.renderStreamingStatus(.idle)
                self.update(file: downloaded)
            }
        }
    }

    private func prepareSurfaceForNewItem() {
        let replacedFFmpegPlayer = ffmpegPlayer != nil
        stopFFmpegPlayback()
        if replacedFFmpegPlayer {
            cancelPlaybackPublishers()
        }
        usesFFmpegVOD = false
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
        updatePictureInPictureEligibility()
    }

    private func refreshSurfaceReady() {
        guard let surfaceItemIdentifier,
              player.currentItemIdentifier == surfaceItemIdentifier
        else { return }
        isSurfaceReady = videoSurface.playerLayer.isReadyForDisplay
        refreshPlaybackSurfaceVisibility()
    }

    private func refreshPlaybackSurfaceVisibility() {
        let canShowSurface: Bool =
            switch currentPlaybackState {
            case .ended, .paused, .playing:
                isSurfaceReady
            case .buffering, .failed, .idle, .preparing:
                false
            }
        videoSurface.isHidden = usesFFmpegVOD || !canShowSurface
        let keepsSampleBufferLayerVisible = usesFFmpegVOD && isPictureInPictureRetainedByOwner
        ffmpegPlayer?.surfaceView.isHidden = !usesFFmpegVOD
            || !canShowSurface && !keepsSampleBufferLayerVisible
        if canShowSurface {
            spinner.stopAnimating()
        } else if currentPlaybackState != .failed, currentPlaybackState != .idle {
            spinner.startAnimating()
        }
        updatePictureInPictureEligibility()
    }

    private func update(file: File) {
        guard file.id == fileID,
              file.local.isDownloadingCompleted,
              loadedPath != file.local.path
        else { return }
        sourceFile = file
        loadedPath = file.local.path
        if let vodConfiguration, vodConfiguration.usesFFmpeg {
            startVOD(
                file: file,
                mimeType: vodConfiguration.mimeType,
                fileName: vodConfiguration.fileName,
                startTimestamp: vodConfiguration.startTimestamp,
            )
            return
        }
        prepareSurfaceForNewItem()
        bindLocalPlaybackPublishers()
        player.load(
            url: URL(fileURLWithPath: file.local.path),
            autoplay: isPlaybackVisible && !isUserPaused,
            loops: loopsPlayback,
            initialTime: startPlaybackTimestamp,
        )
        player.setMuted(isMuted)
        player.setRate(playbackRate)
        bindSurfaceToCurrentItem()
    }

    private func render(state: LocalMediaPlayer.State) {
        currentPlaybackState = state
        switch state {
        case .idle:
            spinner.stopAnimating()
        case .buffering, .preparing:
            spinner.startAnimating()
        case .ended, .paused, .playing:
            break
        case .failed:
            spinner.stopAnimating()
            if usesVOD, let sourceFile {
                let failedWithFFmpeg = usesFFmpegVOD
                let retriesVOD = currentStreamingStatus == .offline
                    || currentStreamingStatus == .retrying
                    || failedWithFFmpeg && currentFFmpegFailureIsRetryable
                let resolution: () -> Void = { [weak self] in
                    guard let self else { return }
                    resolveVODPlaybackFailure(
                        sourceFile: sourceFile,
                        failedWithFFmpeg: failedWithFFmpeg,
                        retriesVOD: retriesVOD,
                    )
                }
                if failedWithFFmpeg, isPictureInPictureRetainedByOwner {
                    deferredPictureInPictureFailureResolution = resolution
                } else {
                    resolution()
                }
            } else if usesLegacyDownload || sourceFile != nil {
                usesLegacyDownload = false
                showRetryState(statusText: "Couldn't load video", retryMode: .fullDownload)
            }
        }
        refreshPlaybackSurfaceVisibility()
        updateControlIcons()
        onPlaybackIntentChanged?()
        updatePictureInPictureEligibility()
        renderStreamingStatus(currentStreamingStatus)
        switch state {
        case .playing:
            scheduleControlsAutoHideIfNeeded()
        case .buffering, .ended, .failed, .paused, .preparing:
            cancelControlsAutoHide()
            setControlsVisible(true, animated: true)
        case .idle:
            cancelControlsAutoHide()
        }
    }

    private func resolveVODPlaybackFailure(
        sourceFile: File,
        failedWithFFmpeg: Bool,
        retriesVOD: Bool,
    ) {
        vodConfiguration?.startTimestamp = currentPlaybackTime
        usesVOD = false
        if !retriesVOD {
            startPlaybackTimestamp = currentPlaybackTime
        }
        prepareSurfaceForNewItem()
        player.stop()
        if retriesVOD {
            let statusText = currentStreamingStatus == .offline ? "Offline" : "Stream timed out"
            showRetryState(statusText: statusText, retryMode: .vod)
        } else if failedWithFFmpeg, sourceFile.local.isDownloadingCompleted {
            showRetryState(statusText: "Couldn't decode video", retryMode: .vod)
        } else {
            startLegacyDownload(file: sourceFile)
        }
        updatePictureInPictureEligibility()
    }

    private func showRetryState(statusText: String, retryMode: RetryMode) {
        currentPlaybackState = .failed
        self.retryMode = retryMode
        retryStatusText = statusText
        spinner.stopAnimating()
        videoSurface.isHidden = true
        retryButton.isHidden = false
        updateControlIcons()
        renderStreamingStatus(currentStreamingStatus)
    }

    @objc private func togglePlayback() {
        guard currentPlaybackState != .failed else { return }
        revealControlsAndReschedule()
        let playbackWasRequested = isSeeking ? resumeAfterSeeking : playbackIsRequested
        if playbackWasRequested {
            isUserPaused = true
            resumeAfterSeeking = false
            playbackPause()
        } else {
            isUserPaused = false
            if isSeeking {
                resumeAfterSeeking = true
            } else if isPlaybackVisible {
                playbackPlay()
            }
        }
        updateControlIcons()
    }

    @objc private func jumpPlaybackBackward() {
        jumpPlayback(by: -15)
    }

    @objc private func jumpPlaybackForward() {
        jumpPlayback(by: 15)
    }

    @objc private func beginSeeking() {
        guard seekSlider.isEnabled else { return }
        setControlsVisible(true, animated: false)
        cancelControlsAutoHide()
        isSeeking = true
        resumeAfterSeeking = !isUserPaused && playbackIsRequested
        playbackPause()
        updateControlIcons()
    }

    @objc private func seekValueChanged() {
        let time = TimeInterval(seekSlider.value)
        guard isSeeking else {
            let shouldResume = !isUserPaused && playbackIsRequested
            playbackPause()
            commitSeek(to: time, shouldResume: shouldResume)
            return
        }
        updateTimeLabel(current: time)
    }

    @objc private func endSeeking() {
        guard isSeeking else { return }
        let target = TimeInterval(seekSlider.value)
        let shouldResume = resumeAfterSeeking && !isUserPaused
        isSeeking = false
        resumeAfterSeeking = false
        commitSeek(to: target, shouldResume: shouldResume)
        scheduleControlsAutoHideIfNeeded()
    }

    @objc private func toggleMuted() {
        revealControlsAndReschedule()
        isMuted.toggle()
        playbackSetMuted(isMuted)
        updateControlIcons()
    }

    @objc private func cyclePlaybackRate() {
        revealControlsAndReschedule()
        playbackRate =
            switch playbackRate {
            case ..<1:
                1
            case ..<1.5:
                1.5
            case ..<2:
                2
            default:
                0.5
            }
        playbackSetRate(playbackRate)
        updateControlIcons()
    }

    @objc private func togglePictureInPicture() {
        revealControlsAndReschedule()
        onPictureInPictureToggle?()
    }

    @objc private func toggleControlsVisibility() {
        guard !loopsPlayback, !isInlinePresentation else { return }
        if UIAccessibility.isVoiceOverRunning {
            setControlsVisible(true, animated: false)
            cancelControlsAutoHide()
            return
        }
        setControlsVisible(!controlsAreVisible, animated: true)
        if controlsAreVisible {
            scheduleControlsAutoHideIfNeeded()
        }
    }

    private func updateControlIcons() {
        let playbackRequested = isSeeking ? resumeAfterSeeking : playbackIsRequested
        let showsPause = playbackRequested && currentPlaybackState != .ended && currentPlaybackState != .failed
        playButton.setImage(UIImage(systemName: showsPause ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = showsPause ? "Pause" : "Play"
        playButton.isEnabled = currentPlaybackState != .failed
        let canSeek = canSeekPlayback
        seekSlider.isEnabled = canSeek
        jumpBackwardButton.isEnabled = canSeek
        jumpForwardButton.isEnabled = canSeek
        jumpBackwardButton.alpha = canSeek ? 1 : 0.45
        jumpForwardButton.alpha = canSeek ? 1 : 0.45

        muteButton.setImage(
            UIImage(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"),
            for: .normal,
        )
        muteButton.accessibilityLabel = isMuted ? "Unmute" : "Mute"
        muteButton.accessibilityValue = isMuted ? "Muted" : "Sound on"

        let rateTitle =
            switch playbackRate {
            case 0.5: "0.5×"
            case 1.5: "1.5×"
            case 2: "2×"
            default: "1×"
            }
        rateButton.setTitle(rateTitle, for: .normal)
        rateButton.accessibilityValue = rateTitle
    }

    private func revealControlsAndReschedule() {
        setControlsVisible(true, animated: true)
        scheduleControlsAutoHideIfNeeded()
    }

    private func configureVoiceOverObservation() {
        voiceOverCancellable?.cancel()
        voiceOverCancellable = NotificationCenter.default
            .publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if UIAccessibility.isVoiceOverRunning {
                    cancelControlsAutoHide()
                    setControlsVisible(true, animated: false)
                } else {
                    scheduleControlsAutoHideIfNeeded()
                }
            }
    }

    private func setControlsVisible(_ isVisible: Bool, animated: Bool) {
        guard !loopsPlayback, !isInlinePresentation else {
            controlsAreVisible = false
            controlsView.isHidden = true
            return
        }
        let visibilityChanged = controlsAreVisible != isVisible
        controlsAreVisible = isVisible
        if visibilityChanged {
            onGalleryChromeVisibilityChanged?(isVisible)
        }
        if !isVisible {
            cancelControlsAutoHide()
        }
        if isVisible {
            controlsView.isHidden = false
        }
        let changes = { self.controlsView.alpha = isVisible ? 1 : 0 }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, controlsAreVisible == isVisible else { return }
            controlsView.isHidden = !isVisible
        }
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: changes,
                completion: completion,
            )
        } else {
            changes()
            completion(true)
        }
    }

    private func scheduleControlsAutoHideIfNeeded() {
        cancelControlsAutoHide()
        guard !hasBlockingStreamingStatus,
              !galleryChromeInteractionIsActive,
              controlsAreVisible,
              Self.shouldAutoHideControls(
                  state: currentPlaybackState,
                  isSeeking: isSeeking,
                  isPlaybackVisible: isPlaybackVisible,
                  isPictureInPictureActive: isPictureInPictureActive,
                  isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
              )
        else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !hasBlockingStreamingStatus,
                  !galleryChromeInteractionIsActive,
                  Self.shouldAutoHideControls(
                      state: currentPlaybackState,
                      isSeeking: isSeeking,
                      isPlaybackVisible: isPlaybackVisible,
                      isPictureInPictureActive: isPictureInPictureActive,
                      isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
                  )
            else { return }
            setControlsVisible(false, animated: true)
        }
        controlsAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.controlsAutoHideDelay,
            execute: workItem,
        )
    }

    private func cancelControlsAutoHide() {
        controlsAutoHideWorkItem?.cancel()
        controlsAutoHideWorkItem = nil
    }

    private func commitSeek(to target: TimeInterval, shouldResume: Bool) {
        currentPlaybackTime = target
        if shouldResume, isPlaybackVisible {
            playbackPlay(from: target)
        } else {
            playbackSeek(to: target)
            playbackPause()
        }
        updateTimeLabel(current: target)
        updateControlIcons()
    }

    private func jumpPlayback(by interval: TimeInterval) {
        guard canSeekPlayback else { return }
        revealControlsAndReschedule()
        let resolution = Self.resolveJump(
            current: currentPlaybackTime,
            duration: playbackDuration,
            interval: interval,
        )
        if resolution.shouldPauseAtStart {
            isUserPaused = true
            currentPlaybackTime = 0
            playbackSeek(to: 0, tolerance: 0)
            playbackPause()
            seekSlider.value = 0
            updateTimeLabel(current: 0)
            updateControlIcons()
            onPlaybackIntentChanged?()
            return
        }
        let shouldResume = !isUserPaused && playbackIsRequested
        playbackPause()
        commitSeek(to: resolution.time, shouldResume: shouldResume)
    }

    private func updatePictureInPictureEligibility() {
        onPictureInPictureEligibilityChanged?()
    }

    private func updatePlaybackTime(_ time: TimeInterval) {
        guard time.isFinite else { return }
        currentPlaybackTime = max(0, time)
        guard !isSeeking else { return }
        seekSlider.value = Float(min(playbackDuration, currentPlaybackTime))
        updateTimeLabel(current: currentPlaybackTime)
    }

    private func updatePlaybackDuration(_ duration: TimeInterval) {
        playbackDuration = duration.isFinite ? max(0, duration) : 0
        seekSlider.maximumValue = Float(max(1, playbackDuration))
        seekSlider.isEnabled = playbackDuration > 0
        if !isSeeking {
            seekSlider.value = Float(min(playbackDuration, currentPlaybackTime))
            updateTimeLabel(current: currentPlaybackTime)
        }
        refreshBufferedSliderRanges()
        updateControlIcons()
        updatePictureInPictureEligibility()
    }

    private func updateBufferedRanges(_ ranges: [LocalMediaPlayer.BufferedRange]) {
        bufferedRanges = ranges
        refreshBufferedSliderRanges()
    }

    private func renderStreamingStatus(_ status: TDLibVODResourceLoaderStatus) {
        let wasBlockingStreamingStatus = hasBlockingStreamingStatus
        currentStreamingStatus = status
        let text =
            if let retryStatusText {
                retryStatusText
            } else if usesLegacyDownload {
                "Downloading…"
            } else {
                switch status {
                case .offline:
                    "Offline"
                case .retrying:
                    "Retrying…"
                case .failed:
                    "Couldn't stream"
                case .loading:
                    if currentPlaybackState == .buffering || currentPlaybackState == .preparing {
                        "Buffering…"
                    } else {
                        ""
                    }
                case .idle, .ready:
                    currentPlaybackState == .buffering ? "Buffering…" : ""
                }
            }
        networkStatusLabel.text = text
        networkStatusLabel.accessibilityLabel = text.isEmpty ? nil : "Video status"
        networkStatusLabel.accessibilityValue = text.isEmpty ? nil : text
        networkStatusLabel.accessibilityElementsHidden = text.isEmpty
        if hasBlockingStreamingStatus || currentPlaybackState == .buffering {
            cancelControlsAutoHide()
            setControlsVisible(true, animated: true)
        } else if wasBlockingStreamingStatus {
            scheduleControlsAutoHideIfNeeded()
        }
    }

    private func refreshBufferedSliderRanges() {
        guard playbackDuration > 0 else {
            seekSlider.bufferedRanges = []
            return
        }
        let duration = Float(playbackDuration)
        seekSlider.bufferedRanges = bufferedRanges.compactMap { range in
            let lowerBound = min(1, max(0, Float(range.start) / duration))
            let upperBound = min(1, max(0, Float(range.end) / duration))
            guard upperBound > lowerBound else { return nil }
            return lowerBound...upperBound
        }
    }

    private func updateTimeLabel(current: TimeInterval) {
        let boundedCurrent = playbackDuration > 0
            ? min(playbackDuration, max(0, current))
            : max(0, current)
        let elapsed = formatPlaybackTime(boundedCurrent)
        let duration = formatPlaybackTime(playbackDuration)
        timeLabel.text = "\(elapsed) / \(duration)"
        seekSlider.accessibilityValue = "\(elapsed) of \(duration)"
    }

    private func formatPlaybackTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    @objc private func retryPlayback() {
        guard let sourceFile else { return }
        let retryMode = retryMode
        self.retryMode = nil
        retryStatusText = nil
        retryButton.isHidden = true
        loadedPath = nil
        switch retryMode {
        case .vod:
            guard let vodConfiguration else {
                startLegacyDownload(file: sourceFile)
                return
            }
            spinner.startAnimating()
            startVOD(
                file: sourceFile,
                mimeType: vodConfiguration.mimeType,
                fileName: vodConfiguration.fileName,
                startTimestamp: vodConfiguration.startTimestamp,
            )
        case .fullDownload, nil:
            startLegacyDownload(file: sourceFile)
        }
    }
}

// MARK: - GalleryBufferedSlider

final class GalleryBufferedSlider: UISlider {
    // MARK: Internal

    var bufferedRanges = [ClosedRange<Float>]() {
        didSet {
            setNeedsLayout()
        }
    }

    // MARK: Private

    private let backgroundTrackLayer = CALayer()
    private var bufferedTrackLayers = [CALayer]()

    #if DEBUG
        var debugBufferedSegmentCount: Int {
            bufferedTrackLayers.count
        }
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundTrackLayer.backgroundColor = UIColor.white.withAlphaComponent(0.2).cgColor
        backgroundTrackLayer.cornerRadius = 2.5
        layer.insertSublayer(backgroundTrackLayer, at: 0)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let rect = super.trackRect(forBounds: bounds)
        return CGRect(x: rect.minX, y: rect.midY - 2.5, width: rect.width, height: 5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let track = trackRect(forBounds: bounds)
        while bufferedTrackLayers.count < bufferedRanges.count {
            let bufferedLayer = CALayer()
            bufferedLayer.backgroundColor = UIColor.white.withAlphaComponent(0.45).cgColor
            bufferedLayer.cornerRadius = 2.5
            layer.insertSublayer(bufferedLayer, above: backgroundTrackLayer)
            bufferedTrackLayers.append(bufferedLayer)
        }
        while bufferedTrackLayers.count > bufferedRanges.count {
            bufferedTrackLayers.removeLast().removeFromSuperlayer()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundTrackLayer.frame = track
        for (range, bufferedLayer) in zip(bufferedRanges, bufferedTrackLayers) {
            let lowerBound = CGFloat(min(1, max(0, range.lowerBound)))
            let upperBound = CGFloat(min(1, max(0, range.upperBound)))
            bufferedLayer.frame = CGRect(
                x: track.minX + track.width * lowerBound,
                y: track.minY,
                width: track.width * max(0, upperBound - lowerBound),
                height: track.height,
            )
        }
        CATransaction.commit()
    }
}
