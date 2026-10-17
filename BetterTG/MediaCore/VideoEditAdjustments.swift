// VideoEditAdjustments.swift

import CoreMedia
import Foundation
import ImageIO
import UIKit

// MARK: - VideoEditAdjustments

/// What TGVideoEditAdjustments keeps for a picked video in the attachment sheet: the trimmed part, `sendAsGif`,
/// which mutes the video and sends it as a GIF that autoplays and loops, and the crop with its quarter turns and
/// mirroring, and the painting. The cover TGMediaEditingContext keeps beside them goes with them here.
struct VideoEditAdjustments: Equatable {
    /// `TGVideoScrubberMinimumTrimDuration`: the shortest part a trim keeps.
    static let minimumTrimDuration = 1.0
    /// `TGVideoEditMinimumTrimmableDuration`: shorter videos aren't trimmed.
    static let minimumTrimmableDuration = 1.5
    /// `TGMediaVideoConversionPresetAnimation`'s bitrate (`_videoBitrateKbpsForPreset:`'s default).
    static let animationVideoBitrateKbps = 900

    /// The kept part in seconds of the original; nil sends the whole video.
    var trimRange: ClosedRange<Double>?
    /// `sendAsGif`: the video goes without sound as a GIF.
    var sendsAsGIF = false
    /// `cropRect`, `cropOrientation`, `cropMirrored` and `cropLockedAspectRatio`, measured in the displayed
    /// video's pixels; nil leaves the frame as it is. The straightening angle stays zero for a video: Telegram's
    /// video crop has no dial (`hasArbitraryRotation`). A Live Photo's motion takes the still's angle
    /// (MediaEditorValues' `cropRotation` from the patched Live Photo adjustments).
    var crop: PhotoCropAdjustments?
    /// TGMediaEditingContext's `coverPositionForItem:`: the frame chosen as the cover, in seconds of the original;
    /// nil sends no cover. It is chosen only where Telegram offers it (`hasCoverButton`), and it changes neither the
    /// conversion nor the grid's frame.
    var coverTime: Double?
    /// TGMediaEditingContext's `setCoverImage:position:nil`: a gallery photo edited in the video's shape
    /// (MediaEditorScreen's `coverEditor`) and stored as the cover's JPEG; it replaces `coverTime`.
    var coverImageURL: URL?
    /// TGVideoEditAdjustments' `paintingData`: the strokes and entities over the whole displayed frame, kept
    /// editable for the editor (`entitiesData`).
    var drawing: PhotoDrawing?
    /// `paintingData.imagePath`: the painting flattened at its own size, which TGMediaVideoConverter lays over
    /// every frame. The conversion names it, so a generation TDLib restarts keeps it.
    var paintingImageURL: URL?

    /// `isDefaultValues`: nothing to apply.
    var isDefault: Bool {
        trimRange == nil && !sendsAsGIF && crop == nil && coverTime == nil && coverImageURL == nil && drawing == nil
            && paintingImageURL == nil
    }

    /// The sent length of a video `duration` seconds long.
    func sentDuration(of duration: Double) -> Double {
        guard let trimRange else { return duration }
        return max(0, min(trimRange.upperBound, duration) - min(trimRange.lowerBound, duration))
    }

    /// TGMediaVideoConverter's range of a track `duration` long: the trim, ending with the track when it reaches
    /// past it, or the whole track.
    func timeRange(in duration: CMTime) -> CMTimeRange {
        let whole = CMTimeRange(start: .zero, duration: duration)
        guard let trimRange else { return whole }
        let start = CMTime(seconds: trimRange.lowerBound, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        guard start < duration else { return whole }
        let end = trimRange.upperBound < duration.seconds
            ? CMTime(seconds: trimRange.upperBound, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            : duration
        return CMTimeRange(start: start, end: end)
    }

    /// The crop measured in a displayed frame of `size`, which a library video's current version may give in other
    /// units than the editor read.
    func crop(inFrameOf size: CGSize) -> PhotoCropAdjustments? {
        crop?.videoCrop(inFrameOf: size)
    }
}

// MARK: - Conversion

extension VideoEditAdjustments {
    private static let trimPrefix = "trim="
    private static let gifFlag = "gif"
    private static let cropPrefix = "crop="
    private static let turnPrefix = "turn="
    private static let mirrorFlag = "mirror"
    private static let rotationPrefix = "rot="
    private static let paintPrefix = "paint="

    /// TDLib restarts an unfinished generation with its original path and conversion, so the conversion carries the
    /// edit after the preset's name: `bettertg-video-medium-v1;trim=1.500-9.250;gif`, and a crop as its rectangle
    /// and frame size, quarter turns, mirroring and a Live Photo's straightening in radians:
    /// `crop=0.00,140.00,720.00,720.00,1280.00,720.00;turn=1;mirror;rot=0.13963`, and the painting's file in
    /// VideoEditPainting's folder: `paint=6F9619FF-8B86-D011-B42D-00C04FC964FF.png`.
    func conversion(for preset: VideoSendPreset) -> String {
        var parts = [preset.conversion]
        if let trimRange {
            parts.append(Self.trimPrefix + String(format: "%.3f-%.3f", trimRange.lowerBound, trimRange.upperBound))
        }
        if sendsAsGIF {
            parts.append(Self.gifFlag)
        }
        if let crop {
            let rect = crop.cropRect
            let values = [
                rect.minX,
                rect.minY,
                rect.width,
                rect.height,
                crop.originalSize.width,
                crop.originalSize.height,
            ]
            parts.append(Self.cropPrefix + values.map { String(format: "%.2f", $0) }.joined(separator: ","))
            if crop.orientation != .up {
                parts.append(Self.turnPrefix + String(crop.orientation.rawValue))
            }
            if crop.isMirrored {
                parts.append(Self.mirrorFlag)
            }
            if abs(crop.rotation) > .ulpOfOne {
                parts.append(Self.rotationPrefix + String(format: "%.5f", crop.rotation))
            }
        }
        if let paintingImageURL {
            parts.append(Self.paintPrefix + paintingImageURL.lastPathComponent)
        }
        return parts.joined(separator: ";")
    }

    /// The preset and edit a conversion names, the edit nil for an unedited video; nil for a conversion that isn't
    /// the app's.
    static func parse(conversion: String) -> (preset: VideoSendPreset, edit: VideoEditAdjustments?)? {
        let parts = conversion.components(separatedBy: ";")
        guard let name = parts.first, let preset = VideoSendPreset(conversion: name) else { return nil }
        var edit = VideoEditAdjustments()
        var orientation = PhotoCropOrientation.up
        var isMirrored = false
        var rotation: CGFloat = 0
        for part in parts.dropFirst() {
            if part == gifFlag {
                edit.sendsAsGIF = true
            } else if part == mirrorFlag {
                isMirrored = true
            } else if part.hasPrefix(trimPrefix) {
                let bounds = part.dropFirst(trimPrefix.count).components(separatedBy: "-").compactMap(Double.init)
                guard bounds.count == 2, bounds[0] >= 0, bounds[1] > bounds[0] else { return nil }
                edit.trimRange = bounds[0]...bounds[1]
            } else if part.hasPrefix(cropPrefix) {
                let values = part.dropFirst(cropPrefix.count).components(separatedBy: ",").compactMap(Double.init)
                guard values.count == 6, values[2] > 0, values[3] > 0, values[4] > 0, values[5] > 0 else { return nil }
                var crop = PhotoCropAdjustments(originalSize: CGSize(width: values[4], height: values[5]))
                crop.cropRect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
                edit.crop = crop
            } else if part.hasPrefix(turnPrefix) {
                guard let rawValue = Int(part.dropFirst(turnPrefix.count)),
                      let turn = PhotoCropOrientation(rawValue: rawValue)
                else { return nil }
                orientation = turn
            } else if part.hasPrefix(rotationPrefix) {
                guard let value = Double(part.dropFirst(rotationPrefix.count)),
                      abs(value) <= Double(PhotoCropAdjustments.maximumRotation) + 0.001
                else { return nil }
                rotation = CGFloat(value)
            } else if part.hasPrefix(paintPrefix) {
                guard let url = VideoEditPainting.url(named: String(part.dropFirst(paintPrefix.count))) else {
                    return nil
                }
                edit.paintingImageURL = url
            } else {
                return nil
            }
        }
        if edit.crop == nil, orientation != .up || isMirrored || rotation != 0 {
            return nil
        }
        edit.crop?.orientation = orientation
        edit.crop?.isMirrored = isMirrored
        edit.crop?.rotation = rotation
        return (preset, edit.isDefault ? nil : edit)
    }
}

// MARK: - PhotoCropAdjustments + Video

extension PhotoCropAdjustments {
    /// TGMediaVideoConverter's `CGRectIntegral(cropRect)` inside the frame, straightened for a Live Photo's motion,
    /// or the whole frame for an empty crop.
    var videoCropRect: CGRect {
        let frame = CGRect(origin: .zero, size: rotatedContentSize)
        let rect = cropRect.standardized.integral.intersection(frame)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return frame }
        return rect
    }

    /// `videoCropRect`'s size after the quarter turns.
    var videoCroppedSize: CGSize {
        let rect = videoCropRect
        return orientation.isSideward ? CGSize(width: rect.height, height: rect.width) : rect.size
    }

    /// The crop measured in a frame of `size`, kept inside it; the frame's own size returns it as it is.
    func videoCrop(inFrameOf size: CGSize) -> PhotoCropAdjustments {
        guard size.width > 0, size.height > 0 else { return self }
        var result = scaled(to: size)
        let frame = CGRect(origin: .zero, size: result.rotatedContentSize)
        let rect = result.cropRect.standardized.intersection(frame)
        result.cropRect = rect.isNull || rect.width < 1 || rect.height < 1 ? frame : rect
        return result
    }

    /// TGMediaVideoConverter's layer transform (`TGVideoTransformForOrientation` then `TGVideoTransformForCrop`):
    /// the displayed frame, `originalSize` with its origin at the top left, mirrored, straightened about its center
    /// into `rotatedContentSize` as `TGPhotoEditorCrop` draws a photo, cut to `videoCropRect`, turned a quarter at
    /// a time about the crop's center, and scaled to fill `renderSize`. The crop is measured in the mirrored frame,
    /// as the crop view shows it.
    func videoTransform(renderSize: CGSize) -> CGAffineTransform {
        let rect = videoCropRect
        let turned = videoCroppedSize
        let mirroring = isMirrored
            ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: originalSize.width, ty: 0)
            : .identity
        var straightening = CGAffineTransform.identity
        if abs(rotation) > .ulpOfOne {
            let content = rotatedContentSize
            straightening = CGAffineTransform(translationX: -originalSize.width / 2, y: -originalSize.height / 2)
                .concatenating(CGAffineTransform(rotationAngle: rotation))
                .concatenating(CGAffineTransform(translationX: content.width / 2, y: content.height / 2))
        }
        return mirroring
            .concatenating(straightening)
            .concatenating(CGAffineTransform(translationX: -rect.midX, y: -rect.midY))
            .concatenating(orientation.quarterTurn)
            .concatenating(CGAffineTransform(translationX: turned.width / 2, y: turned.height / 2))
            .concatenating(CGAffineTransform(
                scaleX: renderSize.width / max(1, turned.width),
                y: renderSize.height / max(1, turned.height),
            ))
    }

    /// TGMediaPickerGalleryVideoItemView's `_layoutPlayerViewWithCropRect:` for a view showing the whole displayed
    /// frame (bounds of `originalSize`): its center and transform inside a box of `size` that shows the crop turned
    /// and mirrored, `size` having the crop's turned aspect.
    func contentPlacement(in size: CGSize) -> (center: CGPoint, transform: CGAffineTransform) {
        let turned = orientation.isSideward ? CGSize(width: cropRect.height, height: cropRect.width) : cropRect.size
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        guard turned.width > 0, turned.height > 0 else { return (center, .identity) }
        let scale = size.width / turned.width
        let turn = orientation.quarterTurn
        let content = rotatedContentSize
        let offset = CGPoint(x: content.width / 2 - cropRect.midX, y: content.height / 2 - cropRect.midY)
            .applying(turn)
        let transform = (isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(turn)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        return (CGPoint(x: center.x + offset.x * scale, y: center.y + offset.y * scale), transform)
    }
}

// MARK: - PhotoCropOrientation + Video

extension PhotoCropOrientation {
    /// `TGRotationForOrientation` as an exact quarter turn.
    var quarterTurn: CGAffineTransform {
        let cosine = cos(angle).rounded()
        let sine = sin(angle).rounded()
        return CGAffineTransform(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }
}

// MARK: - VideoSendPreset + Crop

extension VideoSendPreset {
    /// `dimensionsFor:adjustments:preset:`: the crop fitted into the preset with its sides rounded to the encoder's
    /// blocks, then turned; a video of displayed `size` without a crop as it is.
    func outputDimensions(for size: CGSize, crop: PhotoCropAdjustments?) -> CGSize {
        guard let crop else { return outputDimensions(for: size) }
        let measured = crop.videoCrop(inFrameOf: size)
        let dimensions = outputDimensions(for: measured.videoCropRect.size)
        return measured.orientation.isSideward ? CGSize(width: dimensions.height, height: dimensions.width) : dimensions
    }
}

// MARK: - SelectedVideo + Edit

extension SelectedVideo {
    /// Muted videos go as GIFs (`LegacyMediaPickers` adds `.Animated` for `sendAsGif`).
    var sendsAsGIF: Bool {
        edit?.sendsAsGIF == true
    }

    /// The length after the trim.
    var sentDuration: Double {
        edit?.sentDuration(of: duration) ?? duration
    }

    /// The conversion TDLib hands back to `VideoSendGenerationCoordinator`.
    var conversion: String {
        edit?.conversion(for: preset) ?? preset.conversion
    }

    /// The sent size, cropped: a GIF renders at `TGMediaVideoConversionPresetAnimation`'s 848 px, which Medium
    /// shares.
    var sentDimensions: CGSize {
        (sendsAsGIF ? VideoSendPreset.medium : preset).outputDimensions(for: presentationSize, crop: edit?.crop)
    }

    /// `estimatedSizeForPreset:duration:hasAudio:` for what goes: a GIF at the Animation preset's bitrate without
    /// sound.
    var estimatedSize: Int64 {
        guard sendsAsGIF else { return preset.estimatedSize(duration: sentDuration, hasAudio: hasAudio) }
        return Int64(Double(VideoEditAdjustments.animationVideoBitrateKbps * 1000 / 8) * max(0, sentDuration))
    }
}

// MARK: - SelectedImage + Live Photo

extension SelectedImage {
    /// The conversion of a Live Photo's motion, which TDLib hands back to `VideoSendGenerationCoordinator`.
    /// LegacyMediaPickers converts the motion at CompressedMedium with its sound, and an edited still gives it the
    /// still's crop, quarter turns, straightening and mirroring (`TGMediaAssetsPatchedLivePhotoAdjustments`).
    var livePhotoConversion: String {
        var edit = VideoEditAdjustments()
        if let livePhotoCrop, !livePhotoCrop.hasDefaultCropping {
            edit.crop = livePhotoCrop
        }
        return edit.conversion(for: .medium)
    }
}

// MARK: - VideoEditPainting

/// TGPaintingData's file for a video: the painting flattened at its own size as a PNG in a temporary folder, as
/// TGMediaEditingContext stores `paintingImagePath`, and laid over the frames as TGMediaVideoConverter does.
enum VideoEditPainting {
    static let directory = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("bettertg-video-paintings", isDirectory: true)

    /// The painting file a conversion names; nil for a name that isn't a PNG in the folder.
    static func url(named name: String) -> URL? {
        guard name.hasSuffix(".png"), !name.hasPrefix("."), !name.contains("/") else { return nil }
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    /// Writes the strokes and entities flattened over a transparent painting of their own size.
    static func write(_ drawing: PhotoDrawing) -> URL? {
        guard let image = drawing.overlayImage(size: drawing.size, transform: .identity),
              let data = UIImage(cgImage: image).pngData()
        else { return nil }
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            log("Could not write the video's painting: \(error)")
            return nil
        }
        return url
    }

    /// TGMediaVideoConverter's `overlayImage`: the painting at `url` over an output frame of `dimensions`, placed as
    /// `crop` cuts, straightens and turns the displayed frame of `presentedSize`, without its mirroring
    /// (`TGMirrorSidewardOrientation`); nil when the file can't be read.
    static func overlay(
        at url: URL,
        crop: PhotoCropAdjustments?,
        presentedSize: CGSize,
        dimensions: CGSize,
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let painting = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        var placement = crop ?? PhotoCropAdjustments(originalSize: presentedSize)
        placement.cropRect = placement.videoCropRect
        let paintingSize = CGSize(width: painting.width, height: painting.height)
        let transform = placement.paintingTransform(paintingSize: paintingSize, outputSize: dimensions)
        return PhotoDrawing(size: paintingSize, strokes: painting).overlayImage(size: dimensions, transform: transform)
    }
}
