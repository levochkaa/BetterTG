// CustomEmoji.swift

import TDLibKit
import UIKit

// MARK: - CustomEmojiStickerRepository

actor CustomEmojiStickerRepository {
    // MARK: Private

    private struct CacheKey: Hashable {
        let clientID: Int32
        let identifier: Int64
    }

    // MARK: Internal

    static let shared = CustomEmojiStickerRepository()

    private var stickersByKey = [CacheKey: Sticker]()
    private var missingKeys = Set<CacheKey>()

    func stickers(
        for identifiers: [Int64],
        client: TDLibClient,
    ) async -> [Int64: Sticker] {
        let uniqueIdentifiers = Array(Set(identifiers)).prefix(200)
        let keys = uniqueIdentifiers.map { CacheKey(clientID: client.id, identifier: $0) }
        let missingIdentifiers = uniqueIdentifiers.filter {
            let key = CacheKey(clientID: client.id, identifier: $0)
            return stickersByKey[key] == nil && !missingKeys.contains(key)
        }
        if !missingIdentifiers.isEmpty,
           let response = try? await client.getCustomEmojiStickers(customEmojiIds: Array(missingIdentifiers))
        {
            var foundIdentifiers = Set<Int64>()
            for sticker in response.stickers {
                guard case .stickerFullTypeCustomEmoji(let fullType) = sticker.fullType else { continue }
                let key = CacheKey(clientID: client.id, identifier: fullType.customEmojiId)
                stickersByKey[key] = sticker
                foundIdentifiers.insert(fullType.customEmojiId)
            }
            missingKeys.formUnion(
                Set(missingIdentifiers)
                    .subtracting(foundIdentifiers)
                    .map { CacheKey(clientID: client.id, identifier: $0) },
            )
        }
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            stickersByKey[key].map { (key.identifier, $0) }
        })
    }
}

// MARK: - CustomEmojiInlineView

final class CustomEmojiInlineView: UIView {
    // MARK: Private

    private static let accentPackIDs: Set<Int64> = [773_947_703_670_341_676, 2_964_141_614_563_343]

    // MARK: Internal

    var onFirstFrameReady: (() -> Void)?

    /// The Power Saving process the sticker or emoji follows, kept across configurations.
    var energySaving: EnergySavingRole? {
        didSet { contentView?.energySaving = energySaving }
    }

    /// The loops the emoji plays each time it is shown, kept across configurations; nil loops on.
    var loopLimit: Int? {
        didSet { contentView?.loopLimit = loopLimit }
    }

    /// InlineStickerItemLayer's dynamicColor, kept across configurations: the colour a template emoji (TDLib's
    /// `needs_repainting`) takes, as the text, list or button around it; other emoji keep their own colours.
    var templateColor: UIColor? {
        didSet { contentView?.templateColor = repaints ? templateColor : nil }
    }

    /// EmojiStatusComponent's and ReactionButtonComponent's accentTint: emoji from Telegram's two default status
    /// packs take the template colour as well.
    var repaintsAccentPacks = false

    private var contentView: (UIView & AnimatedFileView)?
    private var playbackVisible = false
    /// Whether the configured emoji takes the template colour.
    private var repaints = false

    func configure(sticker: Sticker, client: TDLibClient) {
        repaints =
            if case .stickerFullTypeCustomEmoji(let emoji) = sticker.fullType, emoji.needsRepainting {
                true
            } else {
                repaintsAccentPacks && Self.accentPackIDs.contains(sticker.setId)
            }
        let view: UIView & AnimatedFileView =
            switch sticker.format {
            case .stickerFormatTgs:
                TGSStickerView()
            case .stickerFormatWebp:
                AnimatedWebPView()
            case .stickerFormatWebm:
                FFmpegAnimatedVideoView()
            }
        install(view, file: sticker.sticker, thumbnail: sticker.thumbnail, client: client)
    }

    /// A sticker set's own thumbnail (ItemListStickerPackItem's StickerPackThumbnailItem); false for a JPEG, PNG, GIF
    /// or MPEG-4 one, which the caller replaces with the set's first sticker. `isTemplate` is the set's
    /// `needs_repainting`, which paints the thumbnail in the template colour.
    @discardableResult func configure(
        setThumbnail thumbnail: Thumbnail,
        client: TDLibClient,
        isTemplate: Bool = false,
    ) -> Bool {
        repaints = isTemplate
        let view: (UIView & AnimatedFileView)? =
            switch thumbnail.format {
            case .thumbnailFormatTgs: TGSStickerView()
            case .thumbnailFormatWebp: AnimatedWebPView()
            case .thumbnailFormatWebm: FFmpegAnimatedVideoView()
            default: nil
            }
        guard let view else { return false }
        install(view, file: thumbnail.file, thumbnail: nil, client: client)
        return true
    }

    func prepareForReuse() {
        contentView?.prepareForReuse()
        contentView?.removeFromSuperview()
        contentView = nil
        onFirstFrameReady = nil
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        contentView?.setPlaybackVisible(isVisible)
    }

    /// Reuses the decoded frame in a live view for a send's short fade. No UIKit snapshot, second download or
    /// decoder: the input may clear immediately, and the transition must already have the exact visible emoji.
    func makeSendTransitionView() -> UIView? {
        guard let contentView else { return nil }
        let result = UIView(frame: bounds)
        result.isUserInteractionEnabled = false
        for child in contentView.subviews where !child.isHidden && child.alpha > 0 {
            let copied: UIView
            if let frame = child as? AnimationFrameView, let image = frame.frameImage {
                let view = AnimationFrameView()
                view.templateColor = frame.templateColor
                view.show(image)
                copied = view
            } else if let frame = child as? TemplatableImageView, let image = frame.image {
                let view = TemplatableImageView()
                view.templateColor = frame.templateColor
                view.contentMode = frame.contentMode
                view.image = image
                copied = view
            } else {
                continue
            }
            copied.frame = child.convert(child.bounds, to: self)
            copied.alpha = child.alpha
            result.addSubview(copied)
        }
        return result.subviews.isEmpty ? nil : result
    }

    private func install(_ view: UIView & AnimatedFileView, file: File, thumbnail: Thumbnail?, client: TDLibClient) {
        let firstFrameReady = onFirstFrameReady
        prepareForReuse()
        onFirstFrameReady = firstFrameReady
        contentView = view
        view.energySaving = energySaving
        view.loopLimit = loopLimit
        view.templateColor = repaints ? templateColor : nil
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        view.configure(
            file: file,
            client: client,
            thumbnail: thumbnail,
            displaySize: nil,
            onTap: nil,
        )
        view.onFirstFrameReady = { [weak self] in self?.onFirstFrameReady?() }
        view.setPlaybackVisible(playbackVisible)
    }
}
