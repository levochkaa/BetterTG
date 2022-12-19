// RootView+LastOrDraft.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func lastOrDraftMessage(for chat: Chat) -> some View {
        Group {
            if let draftMessage = chat.draftMessage {
                draftMessageView(for: draftMessage)
            } else if let lastMessage = chat.lastMessage {
                lastMessageView(for: lastMessage)
            }
        }
        .foregroundColor(.gray)
    }
    
    @ViewBuilder func draftMessageView(for draftMessage: DraftMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Draft: ")
                .foregroundColor(.red)
            
            if draftMessage.replyToMessageId != 0 {
                Text("reply ")
                    .foregroundColor(.white)
            }
            
            switch draftMessage.inputMessageText {
                case let .inputMessageText(inputMessageText):
                    Text(inputMessageText.text.text)
                default:
                    Text("BTG not supported")
            }
        }
    }
    
    @ViewBuilder func lastMessageView(for lastMessage: Message) -> some View {
        switch lastMessage.content {
            case let .messagePhoto(messagePhoto):
                HStack(alignment: .center, spacing: 5) {
                    makePhotoPreview(from: messagePhoto)
                    
                    Text(messagePhoto.caption.text.isEmpty ? "Photo" : messagePhoto.caption.text)
                }
            case let .messageText(messageText):
                Text(messageText.text.text)
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}
