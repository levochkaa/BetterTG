// ReplyMessageView.swift

import SwiftUI
@preconcurrency import TDLibKit

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
}
