// InlineMessageContent+Photo.swift

import SwiftUIX
import TDLibKit

extension InlineMessageContentView {
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto) -> some View {
        Group {
            if let size = messagePhoto.photo.sizes.getSize(.mBox) {
                AsyncTdImage(id: size.photo.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    photoPlaceholder(for: messagePhoto.photo)
                }
            } else {
                photoPlaceholder(for: messagePhoto.photo)
            }
        }
        .frame(width: type == .last ? 20 : 30, height: type == .last ? 20 : 30)
    }
    
    @ViewBuilder func photoPlaceholder(for photo: Photo) -> some View {
        if let minithumbnail = photo.minithumbnail,
           let image = Image(data: minithumbnail.data) {
            image
                .resizable()
                .scaledToFit()
        }
    }
}
