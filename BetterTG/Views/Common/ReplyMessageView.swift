// ReplyMessageView.swift

import SwiftUI
import TDLibKit

struct ReplyMessageView: View {
    let customMessage: CustomMessage
    let type: ReplyMessageType
    let onTap: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Capsule()
                .fill(.white)
                .frame(width: 2, height: 30)
            
            HStack(alignment: .center, spacing: 5) {
                Group {
                    switch type {
                        case .replied:
                            if let replyToMessage = customMessage.replyToMessage {
                                inlineMessageContent(for: replyToMessage)
                            }
                        case .edit, .reply:
                            inlineMessageContent(for: customMessage.message)
                    }
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    switch type {
                        case .edit, .reply:
                            Text(type == .edit ? "Edit message" : customMessage.senderUser?.firstName ?? "Name")
                            inlineMessageContentText(from: customMessage.message)
                        case .replied:
                            if let replyUser = customMessage.replyUser,
                                let replyToMessage = customMessage.replyToMessage {
                                Text(replyUser.firstName)
                                inlineMessageContentText(from: replyToMessage)
                            }
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            
            if type != .replied {
                Spacer()
            }
        }
        .padding(.horizontal, 5)
        .contentShape(.rect(cornerRadius: 15))
        .padding(5)
        .onTapGesture {
            withAnimation {
                onTap()
            }
        }
    }
    
    @ViewBuilder func inlineMessageContent(for message: Message) -> some View {
        switch message.content {
            case .messagePhoto(let messagePhoto):
                TdImage(photo: messagePhoto.photo, size: .mBox, contentMode: .fit)
                    .frame(width: 30, height: 30)
            default:
                EmptyView()
        }
    }
    
    @ViewBuilder func inlineMessageContentText(from message: Message) -> some View {
        switch message.content {
            case .messageText(let messageText):
                Text(getAttributedString(from: messageText.text))
            case .messagePhoto(let messagePhoto):
                if messagePhoto.caption.text.isEmpty {
                    Text("Photo")
                } else {
                    Text(getAttributedString(from: messagePhoto.caption))
                }
            case .messageVoiceNote(let messageVoiceNote):
                HStack(alignment: .bottom, spacing: 0) {
                    Text("Voice")
                        .foregroundStyle(.white)
                    
                    if !messageVoiceNote.caption.text.isEmpty {
                        Text(": ")
                            .foregroundStyle(.white)
                        
                        Text(getAttributedString(from: messageVoiceNote.caption))
                    }
                }
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}
