// VideoEditAdjustments.swift

import CoreMedia
import Foundation

// MARK: - VideoEditAdjustments

/// What TGVideoEditAdjustments keeps for a picked video in the attachment sheet: the trimmed part and `sendAsGif`,
/// which mutes the video and sends it as a GIF that autoplays and loops.
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

    /// `isDefaultValues`: nothing to apply.
    var isDefault: Bool {
        trimRange == nil && !sendsAsGIF
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
}

// MARK: - Conversion

extension VideoEditAdjustments {
    private static let trimPrefix = "trim="
    private static let gifFlag = "gif"

    /// TDLib restarts an unfinished generation with its original path and conversion, so the conversion carries the
    /// edit after the preset's name: `bettertg-video-medium-v1;trim=1.500-9.250;gif`.
    func conversion(for preset: VideoSendPreset) -> String {
        var parts = [preset.conversion]
        if let trimRange {
            parts.append(Self.trimPrefix + String(format: "%.3f-%.3f", trimRange.lowerBound, trimRange.upperBound))
        }
        if sendsAsGIF {
            parts.append(Self.gifFlag)
        }
        return parts.joined(separator: ";")
    }

    /// The preset and edit a conversion names, the edit nil for an unedited video; nil for a conversion that isn't
    /// the app's.
    static func parse(conversion: String) -> (preset: VideoSendPreset, edit: VideoEditAdjustments?)? {
        let parts = conversion.components(separatedBy: ";")
        guard let name = parts.first, let preset = VideoSendPreset(conversion: name) else { return nil }
        var edit = VideoEditAdjustments()
        for part in parts.dropFirst() {
            if part == gifFlag {
                edit.sendsAsGIF = true
            } else if part.hasPrefix(trimPrefix) {
                let bounds = part.dropFirst(trimPrefix.count).components(separatedBy: "-").compactMap(Double.init)
                guard bounds.count == 2, bounds[0] >= 0, bounds[1] > bounds[0] else { return nil }
                edit.trimRange = bounds[0]...bounds[1]
            } else {
                return nil
            }
        }
        return (preset, edit.isDefault ? nil : edit)
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

    /// The sent size: a GIF renders at `TGMediaVideoConversionPresetAnimation`'s 848 px, which Medium shares.
    var sentDimensions: CGSize {
        (sendsAsGIF ? VideoSendPreset.medium : preset).outputDimensions(for: presentationSize)
    }

    /// `estimatedSizeForPreset:duration:hasAudio:` for what goes: a GIF at the Animation preset's bitrate without
    /// sound.
    var estimatedSize: Int64 {
        guard sendsAsGIF else { return preset.estimatedSize(duration: sentDuration, hasAudio: hasAudio) }
        return Int64(Double(VideoEditAdjustments.animationVideoBitrateKbps * 1000 / 8) * max(0, sentDuration))
    }
}
