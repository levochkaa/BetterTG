// MessageView+Menu.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder var contextMenu: some View {
        Button("Reply", systemImage: "arrowshape.turn.up.left") {
            if replyMessage != nil {
                withAnimation {
                    replyMessage = nil
                }
                Task.main(delay: 0.4) {
                    withAnimation {
                        replyMessage = customMessage
                    }
                }
            } else {
                withAnimation {
                    replyMessage = customMessage
                }
            }
        }
        
        if customMessage.properties.canBeEdited {
            Button("Edit", systemImage: "square.and.pencil") {
                if editCustomMessage != nil {
                    withAnimation {
                        editCustomMessage = nil
                    }
                    Task.main(delay: 0.4) {
                        withAnimation {
                            editCustomMessage = customMessage
                        }
                    }
                } else {
                    withAnimation {
                        editCustomMessage = customMessage
                    }
                }
            }
        }
        
        if let formattedText = getFormattedText(from: customMessage.message.content) {
            Button("Copy", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                UIPasteboard.setFormattedText(formattedText)
            }
        }
        
        Divider()
        
        if customMessage.properties.canBeDeletedOnlyForSelf, !customMessage.properties.canBeDeletedForAllUsers {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteMessage(customMessage.message.id, false)
            }
        }
        
        if customMessage.properties.canBeDeletedForAllUsers, !customMessage.properties.canBeDeletedOnlyForSelf {
            Button("Delete for both", systemImage: "trash.fill", role: .destructive) {
                deleteMessage(customMessage.message.id, true)
            }
        }
        
        if customMessage.properties.canBeDeletedOnlyForSelf, customMessage.properties.canBeDeletedForAllUsers {
            Menu("Delete") {
                Button("Delete only for me", systemImage: "trash", role: .destructive) {
                    deleteMessage(customMessage.message.id, false)
                }

                Button("Delete for both", systemImage: "trash.fill", role: .destructive) {
                    deleteMessage(customMessage.message.id, true)
                }
            }
        }
    }
    
    func getFormattedText(from content: MessageContent) -> FormattedText? {
        switch content {
            case .messageText(let messageText):
                guard !messageText.text.text.isEmpty else { return nil }
                return messageText.text
            case .messagePhoto(let messagePhoto):
                guard !messagePhoto.caption.text.isEmpty else { return nil }
                return messagePhoto.caption
            case .messageVoiceNote(let messageVoiceNote):
                guard !messageVoiceNote.caption.text.isEmpty else { return nil }
                return messageVoiceNote.caption
            default:
                return nil
        }
    }
}
