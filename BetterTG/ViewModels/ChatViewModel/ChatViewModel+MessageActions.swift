// ChatViewModel+MessageActions.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func sendMessagePhotos() async {
        if displayedPhotos.count == 1, let photo = displayedPhotos.first {
            await tdSendMessage(with: makeInputMessageContent(for: photo.url))
        } else {
            let messageContents = displayedPhotos.map {
                makeInputMessageContent(for: $0.url)
            }
            toBeSentPhotosCount = displayedPhotos.count
            await tdSendMessageAlbum(with: messageContents)
        }
    }
    
    func sendMessageText() async {
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
    }
    
    func sendMessageVoiceNote(duration: Int, waveform: Data) async {
        await tdSendMessage(with:
                .inputMessageVoiceNote(
                    .init(
                        caption: FormattedText(
                            entities: [],
                            text: text
                        ),
                        duration: duration,
                        voiceNote: .inputFileLocal(.init(path: savedVoiceNoteUrl.path())),
                        waveform: waveform
                    )
                )
        )
    }
    
    func editMessage() async {
        guard let editMessage = self.editMessage?.message else { return }
        
        switch editMessage.content {
            case .messageText:
                await tdEditMessageText(editMessage)
            case .messagePhoto, .messageVoiceNote:
                await tdEditMessageCaption(editMessage)
            default:
                log("Unsupported edit message type")
        }
    }
    
    func setEditMessageText(from message: Message?) {
        withAnimation {
            switch message?.content {
                case .messageText(let messageText):
                    editMessageText = messageText.text.text
                case .messagePhoto(let messagePhoto):
                    editMessageText = messagePhoto.caption.text
                case .messageVoiceNote(let messageVoiceNote):
                    editMessageText = messageVoiceNote.caption.text
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
