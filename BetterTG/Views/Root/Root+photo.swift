// RootView+Photo.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func chatsListPhoto(for chat: Chat) -> some View {
        Group {
            if let photo = chat.photo {
                AsyncTdImage(id: photo.small.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Group {
                        if let minithumbnail = photo.minithumbnail,
                           let image = Image(data: minithumbnail.data) {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            PlaceholderView(userId: chat.id, title: chat.title)
                        }
                    }
                }
            } else {
                PlaceholderView(userId: chat.id, title: chat.title)
            }
        }
        .clipShape(Circle())
        .frame(width: 64, height: 64)
    }
    
    @ViewBuilder func makePhotoPreview(from messagePhoto: MessagePhoto) -> some View {
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
        .frame(width: 20, height: 20)
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
