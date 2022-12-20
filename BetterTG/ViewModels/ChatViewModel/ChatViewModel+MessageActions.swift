// ChatViewModel+MessageActions.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func sendMessage() async {
        if (bottomAreaState == .message || bottomAreaState == .reply) && text.isEmpty { return }
        
        if displayedPhotos.isEmpty {
            await tdSendMessage(with:
                    .inputMessageText(
                        .init(
                            clearDraft: true,
                            disableWebPagePreview: true,
                            text: FormattedText(
                                entities: [],
                                text: text
                            )
                        )
                    )
            )
        } else if displayedPhotos.count == 1, let photo = displayedPhotos.first {
            await tdSendMessage(with: makeInputMessageContent(for: photo.url))
        } else {
            let messageContents = displayedPhotos.map {
                makeInputMessageContent(for: $0.url)
            }
            await tdSendMessageAlbum(with: messageContents)
        }
        
        await MainActor.run {
            bottomAreaState = .message
        }
    }
    
    func editMessage() async {
        guard let editMessage = self.editMessage?.message else { return }
        
        switch editMessage.content {
            case .messageText:
                await tdEditMessageText(editMessage)
            case .messagePhoto:
                await tdEditMessageCaption(editMessage)
            default:
                logger.log("Unsupported edit message type")
        }
        
        await MainActor.run {
            bottomAreaState = .message
        }
    }
    
    func setEditMessageText(from message: Message?) {
        withAnimation {
            switch message?.content {
                case let .messageText(messageText):
                    editMessageText = messageText.text.text
                case let .messagePhoto(messagePhoto):
                    editMessageText = messagePhoto.caption.text
                default:
                    break
            }
        }
    }
    
    func deleteMessage(id: Int64, deleteForBoth: Bool) async {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        
        if customMessage.album.isEmpty {
            await tdDeleteMessages(ids: [id], deleteForBoth: deleteForBoth)
        } else {
            let ids = customMessage.album.map { $0.id }
            await tdDeleteMessages(ids: ids, deleteForBoth: deleteForBoth)
        }
    }
}
