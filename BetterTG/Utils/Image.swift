// Image.swift

func writeImage(_ uiImage: UIImage, withSaving saving: Bool = false) -> SelectedImage? {
    guard let data = uiImage.jpegData(compressionQuality: 1) else { return nil }
    
    if saving {
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
    }
    
    let imageUrl = URL(filePath: NSTemporaryDirectory())
        .appending(path: "\(UUID().uuidString).jpeg")
    
    do {
        try data.write(to: imageUrl, options: .atomic)
        return SelectedImage(image: Image(uiImage: uiImage), url: imageUrl)
    } catch {
        log("Error getting data for an image: \(error)")
        return nil
    }
}
