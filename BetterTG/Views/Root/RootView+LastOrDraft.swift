// RootView+LastOrDraft.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func lastOrDraftMessage(for customChat: CustomChat) -> some View {
        Group {
            if let draftMessage = customChat.draftMessage {
                draftMessageView(for: draftMessage)
            } else if let lastMessage = customChat.lastMessage {
                lastMessageView(for: lastMessage)
            }
        }
        .foregroundStyle(.gray)
        .lineLimit(1)
        .allowsHitTesting(false)
    }
    
    @ViewBuilder func draftMessageView(for draftMessage: DraftMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Draft: ")
                .foregroundStyle(.red)
            
            if draftMessage.replyTo != nil {
                Text("reply ")
                    .foregroundStyle(.white)
            }
            
            if case .inputMessageText(let inputMessageText) = draftMessage.inputMessageText {
                Text(getAttributedString(from: inputMessageText.text, .gray))
            }
        }
    }
    
    @ViewBuilder func lastMessageView(for lastMessage: Message) -> some View {
        switch lastMessage.content {
            case .messagePhoto(let messagePhoto):
                HStack(alignment: .center, spacing: 5) {
                    makePhotoPreview(from: messagePhoto)
                    
                    if messagePhoto.caption.text.isEmpty {
                        Text("Photo")
                    } else {
                        Text(getAttributedString(from: messagePhoto.caption, .gray))
                    }
                }
            case .messageVoiceNote(let messageVoiceNote):
                HStack(alignment: .bottom, spacing: 0) {
                    Text("Voice")
                        .foregroundStyle(.white)
                    
                    if !messageVoiceNote.caption.text.isEmpty {
                        Text(": ")
                            .foregroundStyle(.white)
                        
                        Text(getAttributedString(from: messageVoiceNote.caption, .gray))
                    }
                }
            case .messageText(let messageText):
                Text(getAttributedString(from: messageText.text, .gray))
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}
