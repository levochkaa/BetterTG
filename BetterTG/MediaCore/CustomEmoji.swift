// CustomEmoji.swift

import TDLibKit
import UIKit

// MARK: - CustomEmojiStickerRepository

actor CustomEmojiStickerRepository {
    // MARK: Internal

    static let shared = CustomEmojiStickerRepository()

    func stickers(for identifiers: [TdInt64]) async -> [TdInt64: Sticker] {
        let uniqueIdentifiers = Array(Set(identifiers)).prefix(200)
        let missingIdentifiers = uniqueIdentifiers.filter {
            stickersByIdentifier[$0] == nil && !missingStickerIdentifiers.contains($0)
        }
        if !missingIdentifiers.isEmpty,
           let response = try? await td.getCustomEmojiStickers(customEmojiIds: Array(missingIdentifiers))
        {
            var foundIdentifiers = Set<TdInt64>()
            for sticker in response.stickers {
                guard case .stickerFullTypeCustomEmoji(let fullType) = sticker.fullType else { continue }
                stickersByIdentifier[fullType.customEmojiId] = sticker
                foundIdentifiers.insert(fullType.customEmojiId)
            }
            missingStickerIdentifiers.formUnion(Set(missingIdentifiers).subtracting(foundIdentifiers))
        }
        return Dictionary(uniqueKeysWithValues: uniqueIdentifiers.compactMap { identifier in
            stickersByIdentifier[identifier].map { (identifier, $0) }
        })
    }

    // MARK: Private

    private var stickersByIdentifier = [TdInt64: Sticker]()
    private var missingStickerIdentifiers = Set<TdInt64>()
}

// MARK: - CustomEmojiInlineView

final class CustomEmojiInlineView: UIView {
    // MARK: Internal

    var onFirstFrameReady: (() -> Void)?

    func configure(sticker: Sticker) {
        prepareForReuse()
        let view: UIView & AnimatedFileView =
            switch sticker.format {
            case .stickerFormatTgs:
                TGSStickerView()
            case .stickerFormatWebp:
                AnimatedWebPView()
            case .stickerFormatWebm:
                FFmpegAnimatedVideoView()
            }
        contentView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        view.configure(
            file: sticker.sticker,
            thumbnail: sticker.thumbnail,
            displaySize: nil,
            onTap: nil,
        )
        view.onFirstFrameReady = { [weak self] in self?.onFirstFrameReady?() }
        view.setPlaybackVisible(playbackVisible)
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

    // MARK: Private

    private var contentView: (UIView & AnimatedFileView)?
    private var playbackVisible = false
}
