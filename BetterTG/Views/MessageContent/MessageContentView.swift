// MessageContentView.swift

import SwiftUI
import TDLibKit

struct MessageContentView: View {
    
    @State var customMessage: CustomMessage
    let width = Utils.size.width * 0.8 - 32
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var openedPhotoNamespace: Namespace.ID?
    
    let logger = Logger(label: "MessageContent")
    let nc: NotificationCenter = .default
    
    var body: some View {
        Group {
            if !customMessage.album.isEmpty {
                MediaAlbum {
                    ForEach(customMessage.album, id: \.id) { albumMessage in
                        if case let .messagePhoto(messagePhoto) = albumMessage.content {
                            makeMessagePhoto(from: messagePhoto, with: albumMessage)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                switch customMessage.message.content {
                    case let .messagePhoto(messagePhoto):
                        makeMessagePhoto(from: messagePhoto, with: customMessage.message)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    default:
                        EmptyView()
                }
            }
        }
    }
}
