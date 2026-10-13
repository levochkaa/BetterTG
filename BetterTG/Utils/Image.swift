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
        return SelectedImage(image: displayPreview(of: image), url: url)
    } catch {
        log("Error writing selected image: \(error)")
        return nil
    }
}

/// A decoded copy no larger than a chat bubble decodes (`TDImageLoadingView`, 960 px). The composer shows it, and the
/// bubble of the message that sends it draws it until the uploaded file decodes.
private func displayPreview(of image: UIImage) -> UIImage {
    let limit: CGFloat = 960
    let width = image.size.width * image.scale
    let height = image.size.height * image.scale
    let factor = min(1, limit / max(width, height, 1))
    let size = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
    return image.preparingThumbnail(of: size) ?? image
}
