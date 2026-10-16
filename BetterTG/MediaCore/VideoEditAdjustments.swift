// VideoEditAdjustments.swift

import CoreMedia
import Foundation

// MARK: - VideoEditAdjustments

/// What TGVideoEditAdjustments keeps for a picked video in the attachment sheet: the trimmed part, `sendAsGif`,
/// which mutes the video and sends it as a GIF that autoplays and loops, and the crop with its quarter turns and
/// mirroring. The cover TGMediaEditingContext keeps beside them goes with them here.
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
    /// video's pixels; nil leaves the frame as it is. The straightening angle stays zero: Telegram's video crop has
    /// no dial (`hasArbitraryRotation`).
    var crop: PhotoCropAdjustments?
    /// TGMediaEditingContext's `coverPositionForItem:`: the frame chosen as the cover, in seconds of the original;
    /// nil sends no cover. It is chosen only where Telegram offers it (`hasCoverButton`), and it changes neither the
    /// conversion nor the grid's frame.
    var coverTime: Double?

    /// `isDefaultValues`: nothing to apply.
    var isDefault: Bool {
        trimRange == nil && !sendsAsGIF && crop == nil && coverTime == nil
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

    /// TDLib restarts an unfinished generation with its original path and conversion, so the conversion carries the
    /// edit after the preset's name: `bettertg-video-medium-v1;trim=1.500-9.250;gif`, and a crop as its rectangle
    /// and frame size, quarter turns and mirroring: `crop=0.00,140.00,720.00,720.00,1280.00,720.00;turn=1;mirror`.
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
            } else {
                return nil
            }
        }
        if edit.crop == nil, orientation != .up || isMirrored {
            return nil
        }
        edit.crop?.orientation = orientation
        edit.crop?.isMirrored = isMirrored
        return (preset, edit.isDefault ? nil : edit)
    }
}

// MARK: - PhotoCropAdjustments + Video

extension PhotoCropAdjustments {
    /// TGMediaVideoConverter's `CGRectIntegral(cropRect)` inside the frame, or the whole frame for an empty crop.
    var videoCropRect: CGRect {
        let frame = CGRect(origin: .zero, size: originalSize)
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
        let frame = CGRect(origin: .zero, size: size)
        let rect = result.cropRect.standardized.intersection(frame)
        result.cropRect = rect.isNull || rect.width < 1 || rect.height < 1 ? frame : rect
        return result
    }

    /// TGMediaVideoConverter's layer transform (`TGVideoTransformForOrientation` then `TGVideoTransformForCrop`):
    /// the displayed frame, `originalSize` with its origin at the top left, mirrored, cut to `videoCropRect`,
    /// turned a quarter at a time about the crop's center, and scaled to fill `renderSize`. The crop is measured in
    /// the mirrored frame, as the crop view shows it.
    func videoTransform(renderSize: CGSize) -> CGAffineTransform {
        let rect = videoCropRect
        let turned = videoCroppedSize
        let mirroring = isMirrored
            ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: originalSize.width, ty: 0)
            : .identity
        return mirroring
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
