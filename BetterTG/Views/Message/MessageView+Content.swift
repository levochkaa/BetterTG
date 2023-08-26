// MessageView+Content.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder var messageContent: some View {
        Group {
            if showAlbums, !customMessage.album.isEmpty {
                MediaAlbum {
                    ForEach(customMessage.album, id: \.id) { albumMessage in
                        if case .messagePhoto(let messagePhoto) = albumMessage.content {
                            makeMessagePhoto(from: messagePhoto, with: albumMessage)
                        }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 15))
            } else {
                simpleMessageContent
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if textWidth == .zero {
                if case .messageVoiceNote = customMessage.message.content {
                    EmptyView()
                } else if showAlbums {
                    messageOverlayDate
                        .padding(5)
                }
            }
        }
    }
    
    @ViewBuilder var simpleMessageContent: some View {
        switch customMessage.message.content {
            case .messagePhoto(let messagePhoto):
                if showPhotos {
                    makeMessagePhoto(from: messagePhoto, with: customMessage.message)
                        .scaledToFit()
                }
            case .messageVoiceNote(let messageVoiceNote):
                if showVoiceNotes {
                    makeMessageVoiceNote(from: messageVoiceNote.voiceNote, with: customMessage.message)
                }
            default:
                EmptyView()
        }
    }
}
