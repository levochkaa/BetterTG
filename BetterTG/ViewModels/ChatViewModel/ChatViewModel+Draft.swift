// ChatViewModel+Draft.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func setDraft(_ draftMessage: DraftMessage) {
        guard text.characters.isEmpty, replyMessage == nil else { return }
        
        if case .inputMessageText(let inputMessageText) = draftMessage.inputMessageText {
            text = getAttributedString(from: inputMessageText.text)
        }
        
        Task {
            let customMessage = await getInputReplyToMessage(draftMessage.replyTo)
            
            await MainActor.run {
                withAnimation {
                    replyMessage = customMessage
                }
            }
        }
    }
    
    func updateDraft() async {
        let draftMessage = DraftMessage(
            date: Int(Date.now.timeIntervalSince1970),
            inputMessageText: .inputMessageText(
                .init(
                    clearDraft: true,
                    linkPreviewOptions: nil,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string
                    )
                )
            ),
            replyTo: getMessageReplyTo(from: replyMessage)
        )
        
        await tdSetChatDraftMessage(draftMessage)
    }
}
