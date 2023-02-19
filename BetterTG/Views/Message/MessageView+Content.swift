// MessageView+Content.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder var messageContent: some View {
        Group {
            if settings.showAlbums, !customMessage.album.isEmpty {
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
        .if(textWidth == .zero) {
            $0.overlay(alignment: .bottomTrailing) {
                if case .messageVoiceNote = customMessage.message.content {
                    EmptyView()
                } else if settings.showAlbums {
                    messageOverlayDate
                        .padding(5)
                }
            }
        }
    }
    
    @ViewBuilder var simpleMessageContent: some View {
        switch customMessage.message.content {
            case .messagePhoto(let messagePhoto):
                if settings.showPhotos {
                    makeMessagePhoto(from: messagePhoto, with: customMessage.message)
                        .scaledToFit()
                }
            case .messageVoiceNote(let messageVoiceNote):
                if settings.showVoiceNotes {
                    makeMessageVoiceNote(from: messageVoiceNote.voiceNote, with: customMessage.message)
                }
            default:
                EmptyView()
        }
    }
}
