// OpenedItems.swift

import SwiftUI
import TDLibKit

struct OpenedItems {
    var images: [IdentifiableImage]
    var index: Int
    
    init(images: [IdentifiableImage], index: Int) {
        self.images = images
        self.index = index
    }
    
    init(_ displayedImages: [SelectedImage], _ id: String) {
        let items = displayedImages.map { IdentifiableImage(id: "\($0.id)", image: $0.image) }
        let index = items.firstIndex(where: { $0.id == id }) ?? 0
        self.init(images: items, index: index)
    }
    
    init(_ album: [Message], _ id: String) {
        let items = album.compactMap {
            if case .messagePhoto(let messagePhoto) = $0.content,
               let size = messagePhoto.photo.sizes.getSize(.wBox) {
                return IdentifiableImage(
                    id: "\(size.photo.id)",
                    image: Image(file: size.photo)
                )
            }
            return nil
        }
        let index = items.firstIndex(where: { $0.id == id }) ?? 0
        self.init(images: items, index: index)
    }
}

struct IdentifiableImage: Identifiable {
    var id = UUID().uuidString
    var image: Image
}
