// VideoEditCover.swift

import AVFoundation
import ImageIO
import UIKit

// MARK: - VideoEditCover

/// A video's cover as TGMediaPickerGalleryInterfaceView's Save Cover keeps it (`setCoverImage:position:`) and
/// LegacyMediaPickers sends it (`videoCover`): the frame at the cover's time read exactly, upright, at most 1280 px on
/// its longer side (TGMediaPickerGalleryVideoItemView's `screenImage`), stored fitted into 1280 × 1280 as a JPEG at
/// quality 0.87. The frame is cut, turned and mirrored as the video's crop says, so the cover shows what the video
/// shows.
enum VideoEditCover {
    /// TGMediaPickerGalleryInterfaceView's `canHaveCover`: videos of a minute or more (`originalDuration`).
    static let minimumDuration = 60.0
    /// `screenImage`'s `TGFitSize(videoDimensions, 1280×1280)` and LegacyMediaPickers' `maxSide`.
    static let maximumSide: CGFloat = 1280
    /// LegacyMediaPickers' `jpegData(compressionQuality: 0.87)`.
    static let quality: CGFloat = 0.87
    /// MediaEditorScreen's `requestCoverCompletion`: a gallery cover comes out in the video's shape fitted into
    /// 1080 × 1080.
    static let galleryCoverSide: CGFloat = 1080

    /// The frame at `time` of `asset` with `edit`'s crop, its longer side at most `maximumSide`. A crop is read
    /// from a larger frame so the cut part keeps its detail.
    static func image(
        at time: Double,
        of asset: AVAsset,
        edit: VideoEditAdjustments?,
        maximumSide: CGFloat = maximumSide,
    ) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var readSide = maximumSide
        if let crop = edit?.crop {
            let whole = max(crop.originalSize.width, crop.originalSize.height)
            let part = max(1, max(crop.cropRect.width, crop.cropRect.height))
            readSide = min(maximumSide * 4, max(maximumSide, maximumSide * whole / part))
        }
        generator.maximumSize = CGSize(width: readSide, height: readSide)
        let requested = CMTime(seconds: max(0, time), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        guard let frame = try? await generator.image(at: requested).image else { return nil }
        let frameSize = CGSize(width: frame.width, height: frame.height)
        let image = UIImage(cgImage: frame)
        guard let crop = edit?.crop(inFrameOf: frameSize) else { return image }
        return crop.render(image, sourcePixelSize: frameSize, maximumSide: maximumSide)
    }

    /// LegacyMediaPickers' cover file: the image `aspectFitted` into 1280 × 1280, then JPEG at 0.87.
    static func jpegData(for image: UIImage) -> Data? {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maximumSide / size.width, maximumSide / size.height)
        let fitted = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: fitted, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: fitted))
        }
        return scaled.jpegData(compressionQuality: quality)
    }

    /// A gallery photo for the cover editor: upright, its longer side at most `maximumSide`. Call off the main
    /// thread.
    static func editorImage(
        from data: Data,
        maximumSide: CGFloat = CGFloat(PhotoCropAdjustments.toolsResultSide),
    ) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// MediaEditorScreen's `requestCoverCompletion` for a gallery photo: the photo edited as `adjustments` say, in
    /// the video's shape fitted into 1080 × 1080, written as the cover's JPEG in a temporary folder. Call off the main
    /// thread.
    static func writeGalleryCover(_ image: UIImage, adjustments: PhotoCropAdjustments) -> URL? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard let rendered = adjustments.renderEdited(
            image,
            sourcePixelSize: pixelSize,
            maximumSide: galleryCoverSide,
        ),
            let data = jpegData(for: rendered)
        else { return nil }
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-video-covers", isDirectory: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            log("Could not write the gallery cover: \(error)")
            return nil
        }
        return url
    }
}
