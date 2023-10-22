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
            let customMessage = await getCustomMessage(fromId: draftMessage.replyToMessageId)
            
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
                    disableWebPagePreview: true,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string
                    )
                )
            ),
            replyToMessageId: replyMessage?.message.id ?? 0
        )
        
        await tdSetChatDraftMessage(draftMessage)
    }
}
