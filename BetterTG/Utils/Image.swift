// Image.swift

import UIKit

func writeImage(_ image: UIImage?, withSaving saving: Bool = false) -> SelectedImage? {
    guard let image, let data = image.jpegData(compressionQuality: 0.92) else { return nil }
    if saving {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).jpeg")
    do {
        try data.write(to: url, options: .atomic)
        return SelectedImage(image: image, url: url)
    } catch {
        log("Error writing selected image: \(error)")
        return nil
    }
}
