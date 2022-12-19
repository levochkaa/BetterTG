// MessageView+Content.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder var messageContent: some View {
        Group {
            if !customMessage.album.isEmpty {
                MediaAlbum {
                    ForEach(customMessage.album, id: \.id) { albumMessage in
                        if case let .messagePhoto(messagePhoto) = albumMessage.content {
                            makeMessagePhoto(from: messagePhoto, with: albumMessage)
                        }
                    }
                }
            } else {
                if case let .messagePhoto(messagePhoto) = customMessage.message.content {
                    makeMessagePhoto(from: messagePhoto, with: customMessage.message)
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}
