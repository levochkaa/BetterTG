// SelectedImage.swift

import SwiftUIX
import TDLibKit

struct SelectedImage: Identifiable, Equatable, Transferable {
    var id = UUID()
    var image: Image
    var url: URL
    
    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.url == rhs.url
    }
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = Image(data: data)
            else { throw Error(code: 0, message: "Error loading Image from data") }
            
            let imageURL = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).png")
            try data.write(to: imageURL)
            
            return SelectedImage(image: image, url: imageURL)
        }
    }
}
