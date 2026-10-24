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
    let text: FormattedText?

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
                text: plain(L10n.telegram("Message.Animation")),
            )
        case .messageVideoNote(let content):
            guard !content.isSecret else { return nil }
            return Self(
                file: stillFile(content.videoNote.thumbnail),
                minithumbnail: content.videoNote.minithumbnail?.data,
                isRound: true,
                showsPlay: false,
                text: plain(L10n.telegram("Message.VideoMessage")),
            )
        case .messageText(let content):
            return content.linkPreview.flatMap { linkPreview($0.type) }
        default:
            return nil
        }
    }

    static func plain(_ text: String) -> FormattedText {
        FormattedText(entities: [], text: text)
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

    private static func caption(_ caption: FormattedText, label: String) -> FormattedText {
        caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? plain(label) : caption
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

// MARK: - ChatListMediaPreviews

/// ChatListItem's contentImageSpecs over the last message's album: up to three thumbnails, oldest first, 2 pt apart,
/// and the text chatListItemStrings gives the group, its first caption or else the last message's.
struct ChatListMediaPreviews: Equatable {
    static let limit = 3
    static let spacing = CGFloat(2)

    let items: [ChatListMediaPreview]
    let text: FormattedText?

    var width: CGFloat {
        CGFloat(items.count) * ChatListMediaPreview.side + CGFloat(max(0, items.count - 1)) * Self.spacing
    }

    static func make(for messages: [Message], inSecretChat: Bool) -> Self? {
        let previews = messages.compactMap { ChatListMediaPreview.make(for: $0, inSecretChat: inSecretChat) }
        guard let last = previews.last else { return nil }
        let caption = messages.lazy.compactMap(captionText).first
        return Self(items: Array(previews.prefix(limit)), text: caption ?? last.text)
    }

    private static func captionText(_ message: Message) -> FormattedText? {
        let caption: FormattedText
        switch message.content {
        case .messagePhoto(let content): caption = content.caption
        case .messageVideo(let content): caption = content.caption
        default: return nil
        }
        return caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption
    }
}

// MARK: - ChatListAlbumMessages

/// The rest of a last message's album, which TDLib's chat leaves out, for the row's thumbnails; kept for the
/// current TDLib client only.
@MainActor final class ChatListAlbumMessages {
    private struct Key: Hashable {
        let chatID: Int64
        let albumID: Int64
    }

    static let shared = ChatListAlbumMessages()

    private var clientID: Int32?
    private var albums = [Key: [Message]]()
    private var waiters = [Key: [() -> Void]]()

    /// The album ending with `last`, oldest first; `[last]` alone until the rest lands, when `completion` runs.
    func messages(endingWith last: Message, client: TDLibClient, completion: @escaping () -> Void) -> [Message] {
        guard last.mediaAlbumId != 0 else { return [last] }
        if clientID != client.id {
            clientID = client.id
            albums.removeAll()
            waiters.removeAll()
        }
        let key = Key(chatID: last.chatId, albumID: Int64(last.mediaAlbumId))
        if let album = albums[key], album.last?.id == last.id { return album }
        let isFirstWaiter = waiters[key] == nil
        waiters[key, default: []].append(completion)
        guard isFirstWaiter else { return [last] }
        let requestClientID = client.id
        Task { [weak self] in
            let history = try? await client.getChatHistory(
                chatId: last.chatId,
                fromMessageId: last.id,
                limit: 10,
                offset: 0,
                onlyLocal: false,
            )
            guard let self, clientID == requestClientID else { return }
            let completions = waiters.removeValue(forKey: key) ?? []
            var byID = [last.id: last]
            for message in history?.messages ?? []
                where message.mediaAlbumId == last.mediaAlbumId && message.id <= last.id
            {
                byID[message.id] = message
            }
            albums[key] = byID.values.sorted { $0.id < $1.id }
            if byID.count > 1 { completions.forEach { $0() } }
        }
        return [last]
    }
}

extension NSAttributedString.Key {
    /// Marks the gap ChatListItem's textLeftCutout leaves in a row's text for its type icon and media thumbnail.
    static let chatListMediaPreviewGap = NSAttributedString.Key("BetterTGChatListMediaPreviewGap")
}

// MARK: - ChatListMessageTypeIcon

/// ChatListItem's messageTypeIcon before the text: a forward, a story reply, or the kind of a voice message, music,
/// poll, checklist, game, location or call, in the mute icon's grey.
enum ChatListMessageTypeIcon: Equatable {
    case forward
    case story
    case voiceMessage
    case audio
    case poll
    case todo
    case game
    case location
    case call(video: Bool, incoming: Bool)

    /// ChatListItem's forwardedIconSpacing before a thumbnail, and the 4 pt before the text without one.
    static let spacingBeforePreview = CGFloat(6)
    static let spacingBeforeText = CGFloat(4)

    /// PresentationResourcesChatList's icons; the poll and location ones fit a 20 pt square as Telegram draws them.
    var image: UIImage? {
        switch self {
        case .forward: Self.asset("ForwardedIcon")
        case .story: Self.asset("StoryReplyIcon")
        case .voiceMessage: Self.asset("VoiceMessageIcon")
        case .audio: Self.asset("AudioIcon")
        case .poll: Self.fitted("PollBadgeIcon", inset: 2)
        case .todo: Self.asset("TodoIcon")
        case .game: Self.asset("GameIcon")
        case .location: Self.fitted("LocationIcon", inset: 0)
        case .call(let video, let incoming):
            Self.asset(video
                ? (incoming ? "CallVideoIncomingIcon" : "CallVideoOutgoingIcon")
                : (incoming ? "CallIncomingIcon" : "CallOutgoingIcon"))
        }
    }

    /// ChatListItem's currentMessageTypeIconOffset.
    var offsetY: CGFloat {
        switch self {
        case .forward: 3
        case .location: -1 - 1 / 3
        case .audio,
             .game,
             .poll,
             .todo,
             .voiceMessage: -1
        case .call,
             .story: 0
        }
    }

    static func make(for message: Message) -> Self? {
        // The Verification Codes account forwards every code; Telegram marks none of them.
        if message.forwardInfo != nil, message.chatId != 489_000 { return .forward }
        if case .messageReplyToStory = message.replyTo { return .story }
        switch message.content {
        case .messageVoiceNote: return .voiceMessage
        case .messageAudio: return .audio
        case .messagePoll: return .poll
        case .messageChecklist: return .todo
        case .messageGame: return .game
        case .messageLiveLocation,
             .messageLocation,
             .messageVenue: return .location
        case .messageCall(let call): return .call(video: call.isVideo, incoming: !message.isOutgoing)
        default: return nil
        }
    }

    /// chatListItemStrings with `enableMediaEmoji` off, where the icon names the kind: a poll's question alone, and a
    /// voice message's or music's caption alone.
    static func text(for message: Message) -> FormattedText? {
        switch message.content {
        case .messagePoll(let content):
            content.poll.question
        case .messageVoiceNote(let content):
            captionText(content.caption)
        case .messageAudio(let content):
            captionText(content.caption)
        default:
            nil
        }
    }

    /// The width the icon and its spacing take from the start of the text.
    static func gapWidth(icon: Self?, previews: ChatListMediaPreviews?) -> CGFloat {
        var width = CGFloat.zero
        if let image = icon?.image {
            width += image.size.width + (previews != nil ? spacingBeforePreview : spacingBeforeText)
        }
        if let previews { width += previews.width + ChatListMediaPreview.spacingAfter }
        return width
    }

    /// The gap in the text, after which the row's text continues.
    static func gap(icon: Self?, previews: ChatListMediaPreviews?) -> NSAttributedString {
        let attachment = NSTextAttachment(image: UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in
        })
        attachment.bounds = CGRect(x: 0, y: 0, width: gapWidth(icon: icon, previews: previews), height: 1)
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttribute(.chatListMediaPreviewGap, value: true, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func captionText(_ caption: FormattedText) -> FormattedText? {
        caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption
    }

    private static func asset(_ name: String) -> UIImage? {
        UIImage(named: "ChatList/\(name)")?.withRenderingMode(.alwaysTemplate)
    }

    private static func fitted(_ name: String, inset: CGFloat) -> UIImage? {
        guard let source = UIImage(named: "ChatList/\(name)") else { return nil }
        let size = CGSize(width: 20, height: 20)
        return UIGraphicsImageRenderer(size: size)
            .image { _ in
                source.draw(in: CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset))
            }
            .withRenderingMode(.alwaysTemplate)
    }
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

// MARK: - ChatListPreviewText

/// ChatListItem's message text: stringWithAppliedEntities with bold, code and links left plain, italic, underline and
/// strikethrough kept, spoilers hidden under dust, and line breaks folded into spaces (foldLineBreaks).
enum ChatListPreviewText {
    static func attributed(_ text: FormattedText, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text.text, attributes: [.foregroundColor: color])
        let length = result.length
        let italicFont = font.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: 0) }
        for entity in text.entities {
            guard entity.offset >= 0, entity.length > 0, entity.offset < length else { continue }
            let range = NSRange(location: entity.offset, length: min(entity.length, length - entity.offset))
            switch entity.type {
            case .textEntityTypeItalic:
                if let italicFont { result.addAttribute(.font, value: italicFont, range: range) }
            case .textEntityTypeUnderline:
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .textEntityTypeStrikethrough:
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .textEntityTypeSpoiler:
                result.addAttributes([.chatListSpoiler: true, .foregroundColor: UIColor.clear], range: range)
            case .textEntityTypeCustomEmoji(let emoji):
                result.addAttribute(.chatListCustomEmoji, value: NSNumber(value: emoji.customEmojiId), range: range)
            default:
                break
            }
        }
        return folded(result)
    }

    /// The text VoiceOver reads: each spoiler as the word, without the gap's attachment character.
    static func accessibilityText(_ text: NSAttributedString) -> String {
        let result = NSMutableString(string: text.string)
        var spoilers = [NSRange]()
        text.enumerateAttribute(.chatListSpoiler, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value != nil { spoilers.append(range) }
        }
        for range in spoilers.reversed() {
            result.replaceCharacters(in: range, with: L10n.betterTG("Message.Spoiler"))
        }
        return (result as String).replacing("\u{FFFC}", with: "")
    }

    /// foldLineBreaks: each run of line breaks and the spaces around it becomes one space, and the ends are trimmed.
    private static func folded(_ text: NSMutableAttributedString) -> NSAttributedString {
        guard let expression = try? NSRegularExpression(pattern: "[ \\t]*[\\r\\n\\u2028\\u2029]+[\\s]*")
        else { return text }
        let matches = expression.matches(in: text.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            text.replaceCharacters(in: match.range, with: " ")
        }
        let string = text.string as NSString
        var start = 0
        var end = string.length
        while start < end, string.character(at: start) == 32 {
            start += 1
        }
        while end > start, string.character(at: end - 1) == 32 {
            end -= 1
        }
        return text.attributedSubstring(from: NSRange(location: start, length: end - start))
    }
}

extension NSAttributedString.Key {
    /// Text the row hides under spoiler dust.
    static let chatListSpoiler = NSAttributedString.Key("BetterTGChatListSpoiler")
    /// A custom emoji's identifier over the emoji TDLib gives in its place.
    static let chatListCustomEmoji = NSAttributedString.Key("BetterTGChatListCustomEmoji")
    /// Marks the room an activity's text leaves for its indicator.
    static let chatListActivityGap = NSAttributedString.Key("BetterTGChatListActivityGap")
}
