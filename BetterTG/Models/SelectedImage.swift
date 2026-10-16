// SelectedImage.swift

import UIKit

// MARK: - ComposerMediaSendMode

/// How the composer's photos and videos go, as MediaPickerScreen's menu offers: albums of up to ten, one message each
/// (Send Without Grouping) or as files (Send as File).
enum ComposerMediaSendMode {
    case grouped
    case separately
    case files
}

// MARK: - SelectedVideo

/// A video picked for sending. `url` is the app's copy of the library file, which TDLib converts when it asks for
/// the generated upload (`VideoSendGenerationCoordinator`).
struct SelectedVideo: Equatable {
    let url: URL
    let duration: Double
    /// Pixel size as displayed, after the track's preferred transform.
    let presentationSize: CGSize
    let thumbnailSize: CGSize
    let hasAudio: Bool
    /// The gallery's quality for this video, already capped at its own size.
    var preset = VideoSendPreset.medium
}

// MARK: - MediaSelfDestructTimer

/// LegacyMessageInputPanel's media timer for a single photo or video in a private chat: View Once
/// (`viewOnceTimeout`) or deletion a few seconds after opening.
enum MediaSelfDestructTimer: Equatable {
    case viewOnce
    case seconds(Int)

    /// presentTimeoutSetup's values.
    static let secondsValues = [3, 10, 30]
}

// MARK: - SelectedImage

/// A picked photo or video. For a video, `image` is its first frame and `url` its JPEG thumbnail.
struct SelectedImage: Identifiable, Equatable, @unchecked Sendable {
    let id = UUID()
    let image: UIImage
    let url: URL
    var livePhotoVideoURL: URL?
    var isLivePhotoEnabled = true
    var video: SelectedVideo?
    /// Telegram's Hide With Spoiler for this item (`hasSpoiler`).
    var hasSpoiler = false
    /// MediaPickerScreen's timer for a single photo or video in a private chat.
    var selfDestructTimer: MediaSelfDestructTimer?

    /// Every file the app keeps for this item in `SelectedDocumentFileStore`.
    var fileURLs: [URL] {
        [url] + [livePhotoVideoURL, video?.url].compactMap(\.self)
    }

    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.url == rhs.url && lhs.livePhotoVideoURL == rhs.livePhotoVideoURL && lhs.isLivePhotoEnabled == rhs
            .isLivePhotoEnabled && lhs.video == rhs.video && lhs.hasSpoiler == rhs.hasSpoiler
            && lhs.selfDestructTimer == rhs.selfDestructTimer
    }
}
