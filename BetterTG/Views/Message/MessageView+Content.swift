// MessageView+Content.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder var messageContent: some View {
        if !customMessage.album.isEmpty {
            MediaAlbum {
                ForEach(customMessage.album, id: \.id) { albumMessage in
                    if case .messagePhoto(let messagePhoto) = albumMessage.content {
                        makeMessagePhoto(from: messagePhoto, with: albumMessage)
                    }
                }
            }
        } else {
            switch customMessage.message.content {
                case .messagePhoto(let messagePhoto):
                    makeMessagePhoto(from: messagePhoto, with: customMessage.message)
                        .scaledToFit()
                case .messageVoiceNote(let messageVoiceNote):
                    makeMessageVoiceNote(from: messageVoiceNote.voiceNote, with: customMessage.message)
                default:
                    EmptyView()
            }
        }
    }
}
