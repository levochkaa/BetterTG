// SelectedImage.swift

import UIKit

struct SelectedImage: Identifiable, Equatable, @unchecked Sendable {
    let id = UUID()
    let image: UIImage
    let url: URL

    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.url == rhs.url
    }
}
