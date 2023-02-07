// Message+photo.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto, with message: Message) -> some View {
        if let size = messagePhoto.photo.sizes.getSize(.wBox) {
            AsyncTdImage(id: size.photo.id) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .onTapGesture {
                        withAnimation {
                            hideKeyboard()
                        }
                    }
            } placeholder: {
                placeholder(with: size)
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
