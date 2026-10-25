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
    // MARK: Internal

    var onFirstFrameReady: (() -> Void)?

    /// The Power Saving process the sticker or emoji follows, kept across configurations.
    var energySaving: EnergySavingRole? {
        didSet { contentView?.energySaving = energySaving }
    }

    // MARK: Private

    private var contentView: (UIView & AnimatedFileView)?
    private var playbackVisible = false

    func configure(sticker: Sticker, client: TDLibClient) {
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
    /// or MPEG-4 one, which the caller replaces with the set's first sticker.
    @discardableResult func configure(setThumbnail thumbnail: Thumbnail, client: TDLibClient) -> Bool {
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

    private func install(_ view: UIView & AnimatedFileView, file: File, thumbnail: Thumbnail?, client: TDLibClient) {
        let firstFrameReady = onFirstFrameReady
        prepareForReuse()
        onFirstFrameReady = firstFrameReady
        contentView = view
        view.energySaving = energySaving
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
