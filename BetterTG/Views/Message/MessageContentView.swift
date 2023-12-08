// MessageContentView.swift

import SwiftUI
import TDLibKit

struct MessageContentView: View {
    @Binding var customMessage: CustomMessage
    
    @Environment(RootViewModel.self) var rootViewModel
    
    var body: some View {
        Group {
            if customMessage.album.isEmpty {
                switch customMessage.message.content {
                    case .messagePhoto(let messagePhoto):
                        makeMessagePhoto(from: messagePhoto)
                            .scaledToFit()
                    case .messageVoiceNote(let messageVoiceNote):
                        MessageVoiceNoteView(voiceNote: messageVoiceNote.voiceNote)
                    default:
                        EmptyView()
                }
            } else {
                MediaAlbum {
                    ForEach(customMessage.album) { albumMessage in
                        if case .messagePhoto(let messagePhoto) = albumMessage.content {
                            makeMessagePhoto(from: messagePhoto)
                        }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }
        }
        .padding(1)
    }
    
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto) -> some View {
        if let size = messagePhoto.photo.sizes.getSize(.wBox) {
            AsyncTdImage(id: size.photo.id) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .matchedGeometryEffect(id: "\(size.photo.id)", in: rootViewModel.namespace)
                    .onTapGesture {
                        guard let url = URL(string: size.photo.local.path) else { return }
                        withAnimation {
                            hideKeyboard()
                            rootViewModel.openedItem = OpenedItem(
                                id: "\(size.photo.id)",
                                image: image,
                                url: url
                            )
                        }
                    }
            } placeholder: {
                if let size = messagePhoto.photo.sizes.getSize(.iString) {
                    Image(file: size.photo)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 5)
                }
            }
        }
    }
}
