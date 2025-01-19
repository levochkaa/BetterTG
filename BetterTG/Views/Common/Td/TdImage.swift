// TdImage.swift

import SwiftUI
import TDLibKit

struct TdImage: View {
    let photo: Photo
    let size: PhotoSizeType
    let contentMode: ContentMode
    var onLoad: (PhotoSize, File) -> Void = { _, _ in }
    
    var body: some View {
        if let size = photo.sizes.getSize(size) {
            AsyncTdImage(id: size.photo.id) { image, file in
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .onAppear { onLoad(size, file) }
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }
    
    var placeholder: some View {
        Group {
            if let size = photo.sizes.first {
                Image(file: size.photo)
                    .resizable()
            } else if let thumbnail = photo.minithumbnail {
                Image(data: thumbnail.data)?
                    .resizable()
            }
        }
        .aspectRatio(contentMode: contentMode)
        .blur(radius: 5)
    }
}
