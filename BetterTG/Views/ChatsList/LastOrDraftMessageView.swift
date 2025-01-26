// LastOrDraftMessageView.swift

import SwiftUI
import TDLibKit

struct LastOrDraftMessageView: View {
    @State var customChat: CustomChat
    
    var body: some View {
        ZStack {
            if let draftMessage = customChat.draftMessage {
                DraftMessageView(draftMessage: draftMessage)
            } else if let lastMessage = customChat.lastMessage {
                HStack(spacing: 3) {
                    if lastMessage.forwardInfo != nil {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                    }
                    
                    LastMesssageView(lastMessage: lastMessage)
                }
            }
        }
        .foregroundStyle(.gray)
        .lineLimit(1)
        .allowsHitTesting(false)
    }
}

private struct DraftMessageView: View {
    let draftMessage: DraftMessage
    
    var body: some View {
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
}

private struct LastMesssageView: View {
    let lastMessage: Message
    
    var body: some View {
        switch lastMessage.content {
            case .messagePhoto(let messagePhoto):
                HStack(alignment: .center, spacing: 3) {
                    TdImage(photo: messagePhoto.photo, size: .mBox, contentMode: .fit)
                        .frame(width: 20, height: 20)
                    
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
