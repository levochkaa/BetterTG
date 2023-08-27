// ImageAsset.swift

import PhotosUI

struct ImageAsset: Identifiable {
    let id = UUID()
    var asset: PHAsset
    var uiImage: UIImage?
    var thumbnail: Image?
    var url: URL?
    var selected: Bool = false
    
    func deselected() -> ImageAsset {
        ImageAsset(asset: asset, thumbnail: thumbnail, url: url, selected: false)
    }
}
