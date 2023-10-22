// ImageAsset.swift

import SwiftUI
import PhotosUI

struct ImageAsset: Identifiable {
    let id = UUID()
    let image: Image
    let url: URL
    var selected = false
    
    func deselected() -> ImageAsset {
        ImageAsset(image: image, url: url, selected: false)
    }
}

extension ImageAsset {
    init(from selectedImage: SelectedImage) {
        self.image = selectedImage.image
        self.url = selectedImage.url
    }
}
