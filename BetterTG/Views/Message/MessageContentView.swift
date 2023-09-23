// MessageContentView.swift

import TDLibKit

struct MessageContentView: View {
    let customMessage: CustomMessage
    let textWidth: Int
    
    @Environment(RootViewModel.self) var rootViewModel
    
    var body: some View {
        Group {
            if customMessage.album.isEmpty {
                switch customMessage.message.content {
                    case .messagePhoto(let messagePhoto):
                        makeMessagePhoto(from: messagePhoto)
                            .scaledToFit()
                    case .messageVoiceNote(let messageVoiceNote):
                        MessageVoiceNoteView(voiceNote: messageVoiceNote.voiceNote, message: customMessage.message)
                    default:
                        EmptyView()
                }
            } else {
                MediaAlbum {
                    ForEach(customMessage.album, id: \.id) { albumMessage in
                        if case .messagePhoto(let messagePhoto) = albumMessage.content {
                            makeMessagePhoto(from: messagePhoto)
                        }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if textWidth == .zero, customMessage.messageVoiceNote == nil {
                messageOverlayDate(customMessage.formattedMessageDate)
                    .padding(5)
            }
        }
        .padding(1)
    }
    
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto) -> some View {
        let size = messagePhoto.photo.sizes.forceSize(.wBox)
        AsyncTdImage(id: size.photo.id) { image in
            image
                .resizable()
                .scaledToFill()
                .matchedGeometryEffect(id: "\(size.photo.id)", in: rootViewModel.namespace)
                .onTapGesture {
                    withAnimation {
                        hideKeyboard()
                        rootViewModel.openedItem = OpenedItem(
                            id: "\(size.photo.id)",
                            image: image,
                            url: URL(string: size.photo.local.path)!
                        )
                    }
                }
        } placeholder: {
            Image(file: messagePhoto.photo.sizes.forceSize(.iString).photo)
                .resizable()
                .scaledToFill()
                .blur(radius: 5)
        }
    }
}