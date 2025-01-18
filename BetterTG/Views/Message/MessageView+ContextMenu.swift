// MessageView+Menu.swift

import SwiftUI
import TDLibKit

extension MessageView {
    var contextMenuActions: [ContextMenuAction] {
        var actions = [ContextMenuAction]()
        actions.append(.button(title: "Reply", systemImage: "arrowshape.turn.up.left") {
            if chatVM.replyMessage != nil {
                withAnimation {
                    chatVM.replyMessage = nil
                }
                Task.main(delay: 0.4) {
                    withAnimation {
                        chatVM.replyMessage = customMessage
                    }
                }
            } else {
                withAnimation {
                    chatVM.replyMessage = customMessage
                }
            }
        })
        if customMessage.properties.canBeEdited {
            actions.append(.button(title: "Edit", systemImage: "square.and.pencil") {
                if chatVM.editCustomMessage != nil {
                    withAnimation {
                        chatVM.editCustomMessage = nil
                    }
                    Task.main(delay: 0.4) {
                        withAnimation {
                            chatVM.editCustomMessage = customMessage
                        }
                    }
                } else {
                    withAnimation {
                        chatVM.editCustomMessage = customMessage
                    }
                }
            })
        }
        if let formattedText = getFormattedText(from: customMessage.message.content) {
            actions.append(.button(title: "Copy", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                UIPasteboard.setFormattedText(formattedText)
            })
        }
        actions.append(.divider)
        if customMessage.properties.canBeDeletedOnlyForSelf, !customMessage.properties.canBeDeletedForAllUsers {
            actions.append(.button(title: "Delete", systemImage: "trash", attributes: .destructive) {
                chatVM.deleteMessage(id: customMessage.message.id, deleteForBoth: false)
            })
        }
        if customMessage.properties.canBeDeletedForAllUsers, !customMessage.properties.canBeDeletedOnlyForSelf {
            actions.append(.button(title: "Delete for both", systemImage: "trash.fill", attributes: .destructive) {
                chatVM.deleteMessage(id: customMessage.message.id, deleteForBoth: true)
            })
        }
        if customMessage.properties.canBeDeletedOnlyForSelf, customMessage.properties.canBeDeletedForAllUsers {
            actions.append(.menu(title: "Delete", children: [
                .button(title: "Delete only for me", systemImage: "trash", attributes: .destructive) {
                    chatVM.deleteMessage(id: customMessage.message.id, deleteForBoth: false)
                },
                .button(title: "Delete for both", systemImage: "trash.fill", attributes: .destructive) {
                    chatVM.deleteMessage(id: customMessage.message.id, deleteForBoth: true)
                }
            ]))
        }
        return actions
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
