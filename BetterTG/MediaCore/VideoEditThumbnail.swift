// VideoEditThumbnail.swift

import AVFoundation
import UIKit

// MARK: - VideoEditThumbnail

/// The grid's picture of an edited video, which TGMediaEditingContext keeps for an edited item: the frame where the
/// trim starts (`trimStartValue`, as TGPhotoEditorController and TGMediaPickerGalleryVideoItemView take it), upright,
/// and cut, turned and mirrored as the crop says with the painting over it, the way an edited photo's cell shows its
/// edit. A video whose frame and trim start are unchanged keeps the library's thumbnail.
enum VideoEditThumbnail {
    /// The grid's thumbnails are 256 px squares, as PhotoCropViewController makes them.
    private static let side: CGFloat = 256
    /// TGPhotoEditorController's frame: `TGFitSize(videoDimensions, 1280×1280)`.
    private static let frameSide: CGFloat = 1280

    /// Whether the edit changes what the grid shows.
    static func isNeeded(for edit: VideoEditAdjustments?) -> Bool {
        guard let edit else { return false }
        return edit.crop != nil || (edit.trimRange?.lowerBound ?? 0) > 0 || edit.drawing != nil
    }

    /// The edited frame of `asset`, its shorter side at least the grid cell's.
    static func make(for edit: VideoEditAdjustments, of asset: AVAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: frameSide, height: frameSide)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: edit.trimRange?.lowerBound ?? 0, preferredTimescale: 600)
        guard let frame = try? await generator.image(at: time).image else { return nil }
        let frameSize = CGSize(width: frame.width, height: frame.height)
        var crop = edit.crop(inFrameOf: frameSize) ?? PhotoCropAdjustments(originalSize: frameSize)
        crop.drawing = edit.drawing
        let size = crop.croppedSize
        let shorter = min(size.width, size.height)
        guard shorter > 0 else { return nil }
        let longest = side * max(size.width, size.height) / shorter
        return crop.renderEdited(UIImage(cgImage: frame), sourcePixelSize: frameSize, maximumSide: min(longest, 1024))
    }
}
