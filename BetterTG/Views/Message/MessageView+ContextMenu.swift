// MessageView+Menu.swift

import SwiftUI
import TDLibKit

extension MessageView {
    var contextMenuActions: [ContextMenuAction?] {
        [
            .button(title: "Reply", systemImage: "arrowshape.turn.up.left") {
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
            },
            customMessage.properties.canBeEdited
            ? .button(title: "Edit", systemImage: "square.and.pencil") {
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
            } : nil,
            getFormattedText(from: customMessage.message.content) != nil
            ? .button(title: "Copy", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                if let formattedText = getFormattedText(from: customMessage.message.content) {
                    UIPasteboard.setFormattedText(formattedText)
                }
            } : nil,
            .divider,
            customMessage.properties.canBeDeletedOnlyForSelf && !customMessage.properties.canBeDeletedForAllUsers
            ? .button(title: "Delete", systemImage: "trash", attributes: .destructive) {
                deleteMessage(customMessage.message.id, false)
            } : nil,
            customMessage.properties.canBeDeletedForAllUsers && !customMessage.properties.canBeDeletedOnlyForSelf
            ? .button(title: "Delete for both", systemImage: "trash.fill", attributes: .destructive) {
                deleteMessage(customMessage.message.id, true)
            } : nil,
            customMessage.properties.canBeDeletedOnlyForSelf && customMessage.properties.canBeDeletedForAllUsers
            ? .menu(title: "Delete", children: [
                .button(title: "Delete only for me", systemImage: "trash", attributes: .destructive) {
                    deleteMessage(customMessage.message.id, false)
                },
                .button(title: "Delete for both", systemImage: "trash.fill", attributes: .destructive) {
                    deleteMessage(customMessage.message.id, true)
                }
            ]) : nil
        ]
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
