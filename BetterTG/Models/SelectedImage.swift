// SelectedImage.swift

import UIKit

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

    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.url == rhs.url && lhs.livePhotoVideoURL == rhs.livePhotoVideoURL && lhs.isLivePhotoEnabled == rhs
            .isLivePhotoEnabled && lhs.video == rhs.video
    }
}
