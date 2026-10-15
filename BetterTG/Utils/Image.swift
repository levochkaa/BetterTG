// Image.swift

import ImageIO
import UIKit
import UniformTypeIdentifiers

// MARK: - PhotoSendPreset

/// How Telegram sends a picked photo (`LegacyMediaPickers`, `fetchPhotoLibraryResource`): scaled to fit 1280 px
/// (2560 px when the picker's HD option is on, which BetterTG does not offer) and compressed by `compressJPEGData`
/// (mozjpeg at quality 72, progressive). ImageIO has no mozjpeg; its 0.72 is the nearest quality.
enum PhotoSendPreset {
    static let maximumSide = 1280
    static let jpegQuality: CGFloat = 0.72
}

// MARK: - Selected photo files

/// Writes the photo at `url` as the JPEG Telegram sends. ImageIO decodes only the scaled size and applies the EXIF
/// orientation, so the file is upright without an orientation tag. Call off the main thread.
func writeImage(contentsOf url: URL, maximumSide: Int = PhotoSendPreset.maximumSide) -> SelectedImage? {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
        log("Error reading selected image: \(url.lastPathComponent)")
        return nil
    }
    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumSide,
        kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
        log("Error scaling selected image: \(url.lastPathComponent)")
        return nil
    }
    let image = UIImage(cgImage: thumbnail)
    return writeScaledImage(image, pixelSize: CGSize(width: thumbnail.width, height: thumbnail.height))
}

/// Writes a decoded photo, such as a camera capture, as the JPEG Telegram sends. Call off the main thread.
func writeImage(_ image: UIImage?, maximumSide: Int = PhotoSendPreset.maximumSide) -> SelectedImage? {
    guard let image else { return nil }
    let width = image.size.width * image.scale
    let height = image.size.height * image.scale
    guard width > 0, height > 0 else { return nil }
    // `aspectFittedOrSmaller`: a smaller photo keeps its size.
    let factor = min(1, CGFloat(maximumSide) / max(width, height))
    let pixelSize = CGSize(
        width: max(1, (width * factor).rounded(.down)),
        height: max(1, (height * factor).rounded(.down)),
    )
    return writeScaledImage(image, pixelSize: pixelSize)
}

/// Draws the photo upright into an opaque 8-bit sRGB image of `pixelSize`, as Telegram draws it into a device RGB
/// context before compressing, then writes the JPEG into the attachment store.
private func writeScaledImage(_ image: UIImage, pixelSize: CGSize) -> SelectedImage? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    format.preferredRange = .standard
    let rendered = UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: pixelSize))
        image.draw(in: CGRect(origin: .zero, size: pixelSize))
    }
    guard let cgImage = rendered.cgImage else { return nil }
    do {
        let url = try SelectedDocumentFileStore.makeFileURL(named: "photo.jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        )
        else { throw CocoaError(.fileWriteUnknown) }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: PhotoSendPreset.jpegQuality,
            kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: true] as [CFString: Any],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
        return SelectedImage(image: displayPreview(of: rendered), url: url)
    } catch {
        log("Error writing selected image: \(error)")
        return nil
    }
}

/// A decoded copy no larger than a chat bubble decodes (`TDImageLoadingView`, 960 px). The composer shows it, and the
/// bubble of the message that sends it draws it until the uploaded file decodes.
private func displayPreview(of image: UIImage) -> UIImage {
    let limit: CGFloat = 960
    let width = image.size.width * image.scale
    let height = image.size.height * image.scale
    let factor = min(1, limit / max(width, height, 1))
    let size = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
    return image.preparingThumbnail(of: size) ?? image
}
