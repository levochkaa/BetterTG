// ChatListMediaPreview.swift

import TDLibKit
import UIKit

// MARK: - ChatListMediaPreview

/// ChatListItem's contentImageSpecs for TDLib's last message: the photo, video, GIF or round video, or a link
/// preview's picture, drawn as an 18 pt thumbnail before the row's text. Telegram leaves self-destructing media and
/// secret chats without one.
struct ChatListMediaPreview: Equatable {
    /// ChatListItem's contentImageSize: 18 pt at the default text size.
    static let side = CGFloat(18)
    static let spacingAfter = CGFloat(5)

    /// The picture to download, if TDLib has a still one small enough.
    let file: File?
    /// TDLib's inline blurred thumbnail, shown first and kept alone for media under a spoiler.
    let minithumbnail: Data?
    let isRound: Bool
    /// Telegram's MiniThumbnailPlay over a video, not over a GIF or a round video.
    let showsPlay: Bool
    /// The row's text in place of "Photo: caption", as the thumbnail names the media (chatListItemStrings with
    /// `enableMediaEmoji` off): the caption alone, or the kind's name without one.
    let text: String?

    static func make(for message: Message, inSecretChat: Bool) -> Self? {
        guard !inSecretChat, message.selfDestructType == nil else { return nil }
        switch message.content {
        case .messagePhoto(let content):
            guard !content.isSecret else { return nil }
            let label = L10n.telegram(content.video == nil ? "Message.Photo" : "Message.LivePhoto")
            return Self(
                file: content.hasSpoiler ? nil : smallestFile(of: content.photo),
                minithumbnail: content.photo.minithumbnail?.data,
                isRound: false,
                showsPlay: false,
                text: caption(content.caption, label: label),
            )
        case .messageVideo(let content):
            guard !content.isSecret else { return nil }
            return Self(
                file: content.hasSpoiler ? nil : stillFile(content.video.thumbnail),
                minithumbnail: content.video.minithumbnail?.data,
                isRound: false,
                showsPlay: true,
                text: caption(content.caption, label: L10n.telegram("Message.Video")),
            )
        case .messageAnimation(let content):
            guard !content.isSecret else { return nil }
            return Self(
                file: content.hasSpoiler ? nil : stillFile(content.animation.thumbnail),
                minithumbnail: content.animation.minithumbnail?.data,
                isRound: false,
                showsPlay: false,
                text: L10n.telegram("Message.Animation"),
            )
        case .messageVideoNote(let content):
            guard !content.isSecret else { return nil }
            return Self(
                file: stillFile(content.videoNote.thumbnail),
                minithumbnail: content.videoNote.minithumbnail?.data,
                isRound: true,
                showsPlay: false,
                text: L10n.telegram("Message.VideoMessage"),
            )
        case .messageText(let content):
            return content.linkPreview.flatMap { linkPreview($0.type) }
        default:
            return nil
        }
    }

    /// Telegram's web page image for the types it previews (photo, video, embed, gif, document, telegram_album);
    /// the row keeps the message's text.
    private static func linkPreview(_ type: LinkPreviewType) -> Self? {
        func photo(_ photo: Photo?, showsPlay: Bool = false) -> Self? {
            guard let photo else { return nil }
            return Self(
                file: smallestFile(of: photo),
                minithumbnail: photo.minithumbnail?.data,
                isRound: false,
                showsPlay: showsPlay,
                text: nil,
            )
        }
        func thumbnail(_ thumbnail: Thumbnail?, minithumbnail: Minithumbnail?, showsPlay: Bool) -> Self? {
            guard thumbnail != nil || minithumbnail != nil else { return nil }
            return Self(
                file: stillFile(thumbnail),
                minithumbnail: minithumbnail?.data,
                isRound: false,
                showsPlay: showsPlay,
                text: nil,
            )
        }
        switch type {
        case .linkPreviewTypePhoto(let value):
            return photo(value.photo)
        case .linkPreviewTypeVideo(let value):
            return thumbnail(value.video.thumbnail, minithumbnail: value.video.minithumbnail, showsPlay: true)
        case .linkPreviewTypeAnimation(let value):
            return thumbnail(value.animation.thumbnail, minithumbnail: value.animation.minithumbnail, showsPlay: false)
        case .linkPreviewTypeDocument(let value):
            return thumbnail(value.document.thumbnail, minithumbnail: value.document.minithumbnail, showsPlay: false)
        case .linkPreviewTypeEmbeddedVideoPlayer(let value):
            return photo(value.thumbnail)
        case .linkPreviewTypeEmbeddedAnimationPlayer(let value):
            return photo(value.thumbnail)
        case .linkPreviewTypeEmbeddedAudioPlayer(let value):
            return photo(value.thumbnail)
        case .linkPreviewTypeAlbum(let value):
            switch value.media.first {
            case .linkPreviewAlbumMediaPhoto(let media)?:
                return photo(media.photo)
            case .linkPreviewAlbumMediaVideo(let media)?:
                return thumbnail(media.video.thumbnail, minithumbnail: media.video.minithumbnail, showsPlay: true)
            case nil:
                return nil
            }
        default:
            return nil
        }
    }

    private static func caption(_ caption: FormattedText, label: String) -> String {
        let text = caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? label : MessageTextSpoilerPresentation(caption).accessibilityText()
    }

    /// mediaGridMessagePhoto at a 36 px fit: the smallest size still covering the thumbnail at 3×.
    private static func smallestFile(of photo: Photo) -> File? {
        let minimum = Int(side * 3)
        let sizes = photo.sizes.sorted { $0.width * $0.height < $1.width * $1.height }
        return (sizes.first { min($0.width, $0.height) >= minimum } ?? sizes.last)?.photo
    }

    /// A still thumbnail: TDLib gives some GIFs an MPEG-4 or GIF one, which the row leaves to the minithumbnail.
    private static func stillFile(_ thumbnail: Thumbnail?) -> File? {
        guard let thumbnail else { return nil }
        switch thumbnail.format {
        case .thumbnailFormatJpeg,
             .thumbnailFormatPng,
             .thumbnailFormatWebp:
            return thumbnail.file
        default:
            return nil
        }
    }
}

extension NSAttributedString.Key {
    /// Marks the gap ChatListItem's textLeftCutout leaves in a row's text for its media thumbnail.
    static let chatListMediaPreviewGap = NSAttributedString.Key("BetterTGChatListMediaPreviewGap")
}

// MARK: - ChatListMediaPreviewView

/// ChatListMediaPreviewNode: the thumbnail with 2 pt corners, or round for a round video, and the play mark over a
/// video.
final class ChatListMediaPreviewView: UIView {
    private let imageView = TDImageLoadingView()
    private let playView = UIImageView(image: UIImage(named: "ChatList/MiniThumbnailPlay"))
    private var preview: ChatListMediaPreview?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .tertiarySystemFill
        addSubview(imageView)
        addSubview(playView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        imageView.layer.cornerRadius = preview?.isRound == true ? bounds.width / 2 : 2
        if let image = playView.image {
            playView.frame = CGRect(
                x: floor((bounds.width - image.size.width) / 2),
                y: floor((bounds.height - image.size.height) / 2),
                width: image.size.width,
                height: image.size.height,
            )
        }
    }

    /// The gap in the text, after which the row's text continues: the thumbnail and its 5 pt.
    static func gap() -> NSAttributedString {
        let attachment = NSTextAttachment(image: UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in
        })
        attachment.bounds = CGRect(
            x: 0,
            y: 0,
            width: ChatListMediaPreview.side + ChatListMediaPreview.spacingAfter,
            height: 1,
        )
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttribute(.chatListMediaPreviewGap, value: true, range: NSRange(location: 0, length: result.length))
        return result
    }

    func configure(_ preview: ChatListMediaPreview, client: TDLibClient) {
        playView.isHidden = !preview.showsPlay
        guard preview != self.preview else { return }
        self.preview = preview
        setNeedsLayout()
        let pixels = Int(ChatListMediaPreview.side * 3)
        if let file = preview.file {
            imageView.load(file: file, placeholderData: preview.minithumbnail, maximumPixelSize: pixels, client: client)
        } else {
            imageView.loadPlaceholder(
                data: preview.minithumbnail,
                maximumPixelSize: pixels,
                origin: .captured(client: client),
            )
        }
    }

    func reset() {
        preview = nil
        imageView.cancel()
        imageView.image = nil
    }
}
