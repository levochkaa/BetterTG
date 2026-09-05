// SelectedImage.swift

import UIKit

struct SelectedImage: Identifiable, Equatable, @unchecked Sendable {
    let id = UUID()
    let image: UIImage
    let url: URL
    var livePhotoVideoURL: URL?
    var isLivePhotoEnabled = true

    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.url == rhs.url && lhs.livePhotoVideoURL == rhs.livePhotoVideoURL && lhs.isLivePhotoEnabled == rhs
            .isLivePhotoEnabled
    }
}
