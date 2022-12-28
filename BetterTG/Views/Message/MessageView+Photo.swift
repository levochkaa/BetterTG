// MessageView+Photo.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto, with message: Message) -> some View {
        if let size = messagePhoto.photo.sizes.getSize(.wBox) {
            AsyncTdImage(id: size.photo.id) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .if(openedPhotoNamespace != nil) {
                        $0
                            .matchedGeometryEffect(
                                id: "\(message.id)",
                                in: openedPhotoNamespace!,
                                properties: .frame
                            )
                    }
                    .onTapGesture {
                        withAnimation {
                            hideKeyboard()
                            self.openedPhotoInfo = OpenedPhotoInfo(
                                openedPhotoMessageId: message.id,
                                openedPhoto: image
                            )
                        }
                    }
            } placeholder: {
                placeholder(with: size)
            }
            .background {
                AsyncTdImage(id: size.photo.id) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .overlay {
                            Color.clear
                                .background(.ultraThinMaterial)
                        }
                } placeholder: {
                    placeholder(with: size)
                }
            }
        }
    }
    
    @ViewBuilder func placeholder(with size: PhotoSize) -> some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(Color.gray6)
            .frame(
                width: Utils.maxMessageContentWidth,
                height: Utils.maxMessageContentWidth * (
                    CGFloat(size.height) / CGFloat(size.width)
                )
            )
    }
}
