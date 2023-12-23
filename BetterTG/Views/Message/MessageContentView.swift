// MessageContentView.swift

import SwiftUI
import TDLibKit

struct MessageContentView: View {
    @Binding var customMessage: CustomMessage
    
    @Environment(ChatViewModel.self) var viewModel
    
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
                            makeMessagePhoto(from: messagePhoto, albumMessage: albumMessage)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
        }
        .padding(1)
    }
    
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto, albumMessage: Message? = nil) -> some View {
        if let size = messagePhoto.photo.sizes.getSize(.yBox) {
            AsyncTdImage(id: size.photo.id) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .onTapGesture {
                        if customMessage.album.isEmpty {
                            viewModel.shownAlbum = .init(
                                photos: [customMessage.message],
                                selection: customMessage.message.id
                            )
                        } else if let albumMessage {
                            viewModel.shownAlbum = .init(photos: customMessage.album, selection: albumMessage.id)
                        }
                    }
            } placeholder: {
                makeMessagePhotoPlaceholder(from: messagePhoto)
            }
        } else {
            makeMessagePhotoPlaceholder(from: messagePhoto)
        }
    }
    
    @ViewBuilder func makeMessagePhotoPlaceholder(from messagePhoto: MessagePhoto) -> some View {
        if let size = messagePhoto.photo.sizes.first(.iString) {
            Image(file: size.photo)
                .resizable()
                .scaledToFill()
                .blur(radius: 5)
        }
    }
}
