// TelegramMediaLayout.swift

import UIKit

// MARK: - TelegramMediaLayout

/// Message media sizes from Telegram-iOS: `ChatMessageInteractiveMediaNode` with the compact
/// `ChatMessageItemLayoutConstants` (images up to 300x380 and at least 170x74, videos up to 250 pt tall in landscape
/// and 360 pt in portrait), `ChatMessageStickerItemNode` (a 184 pt box) and the mosaic bound of
/// `ChatMessageBubbleItemNode`. `maximumWidth` is the widest media the bubble allows, Telegram's constrained width.
enum TelegramMediaLayout {
    enum Kind {
        case image
        case video
        case animation
        case sticker
    }

    static let imageMaximumSize = CGSize(width: 300, height: 380)
    static let imageMinimumSize = CGSize(width: 170, height: 74)
    static let stickerSize = CGSize(width: 184, height: 184)

    static func displaySize(pixelSize: CGSize, kind: Kind, maximumWidth: CGFloat) -> CGSize {
        // Telegram's mosaic substitutes 256x256 for media without dimensions.
        let pixelSize = pixelSize.width > 1 && pixelSize.height > 1 ? pixelSize : CGSize(width: 256, height: 256)
        if kind == .sticker {
            return pixelSize.telegramAspectFitted(stickerSize)
        }
        var unboundSize = CGSize(width: floor(pixelSize.width * 0.5), height: floor(pixelSize.height * 0.5))
        switch kind {
        case .image:
            unboundSize = CGSize(width: max(10, unboundSize.width), height: max(10, unboundSize.height))
        case .animation:
            unboundSize = unboundSize.telegramAspectFilled(CGSize(width: 480, height: 480))
        case .sticker, .video:
            break
        }
        let maximumSize = kind == .video
            ? CGSize(width: maximumWidth, height: unboundSize.width > unboundSize.height ? 250 : 360)
            : imageMaximumSize
        // A landscape item fills the constrained width and a portrait one is as tall as that width.
        let nativeSize = unboundSize.width > unboundSize.height
            ? unboundSize.telegramAspectFitted(CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
            : unboundSize.telegramAspectFitted(CGSize(width: .greatestFiniteMagnitude, height: maximumWidth))
        let fittedMaximum = nativeSize.telegramAspectFitted(maximumSize)
        let width = max(
            min(nativeSize.width, fittedMaximum.width, maximumWidth, maximumSize.width),
            imageMinimumSize.width,
        )
        let fittedSize = nativeSize.telegramFittedToWidthOrSmaller(width)
        let filledSize = fittedSize.telegramAspectFilled(CGSize(width: width, height: fittedSize.height))
        return CGSize(width: width, height: max(min(filledSize.height, maximumSize.height), imageMinimumSize.height))
    }

    static func albumMaximumSize(maximumWidth: CGFloat) -> CGSize {
        imageMaximumSize.telegramFittedToWidthOrSmaller(maximumWidth)
    }
}

private extension CGSize {
    func telegramAspectFitted(_ size: CGSize) -> CGSize {
        let scale = Swift.min(size.width / Swift.max(1, width), size.height / Swift.max(1, height))
        return CGSize(width: floor(width * scale), height: floor(height * scale))
    }

    func telegramAspectFilled(_ size: CGSize) -> CGSize {
        let scale = Swift.max(size.width / Swift.max(1, width), size.height / Swift.max(1, height))
        return CGSize(width: floor(width * scale), height: floor(height * scale))
    }

    func telegramFittedToWidthOrSmaller(_ maximumWidth: CGFloat) -> CGSize {
        let scale = Swift.min(1, maximumWidth / Swift.max(1, width))
        return CGSize(width: floor(width * scale), height: floor(height * scale))
    }
}
