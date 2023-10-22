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
        .overlay(alignment: .bottomTrailing) {
            if textWidth == .zero {
                if customMessage.messageVoiceNote == nil {
                    captionText(from: customMessage.formattedMessageDate)
                        .padding(3)
                        .background(.gray6)
                        .cornerRadius(15)
                        .padding(5)
                } else {
                    captionText(from: customMessage.formattedMessageDate)
                        .padding(.horizontal, 3)
                        .padding(.bottom, 2)
                        .opacity(0.8)
                }
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
