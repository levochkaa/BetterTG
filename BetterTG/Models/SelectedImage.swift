// SelectedImage.swift

import SwiftUIX
import TDLibKit

struct SelectedImage: Identifiable {
    var id = UUID()
    var image: Image
    var url: URL
}

extension SelectedImage: Equatable {
    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.url == rhs.url
    }
}

extension SelectedImage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = Image(data: data)
            else { throw Error(code: 0, message: "Error loading Image from data") }
            
            let imageUrl = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).png")
            try data.write(to: imageUrl, options: .atomic)
            
            return SelectedImage(image: image, url: imageUrl)
        }
    }
}
