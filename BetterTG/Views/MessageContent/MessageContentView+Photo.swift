// MessageContentView+Photo.swift

import SwiftUI
import TDLibKit

extension MessageContentView {
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
        } else {
            let _ = logger.log("nosize", messagePhoto.photo.sizes)
        }
    }
    
    @ViewBuilder func placeholder(with size: PhotoSize) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(customMessage.message.isOutgoing ? .blue : .white)
            .frame(width: width, height: placeholderHeight(from: size))
    }
    
    func placeholderHeight(from size: PhotoSize) -> CGFloat {
        width * (CGFloat(size.height) / CGFloat(size.width))
    }
}
