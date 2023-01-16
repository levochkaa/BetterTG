// Chat+draft.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func setDraft(_ draftMessage: DraftMessage) async {
        if !text.isEmpty || replyMessage != nil { return }
        
        if case .inputMessageText(let inputMessageText) = draftMessage.inputMessageText {
            await MainActor.run {
                text = inputMessageText.text.text
            }
        }
        
        let customMessage = await getCustomMessage(fromId: draftMessage.replyToMessageId)
        
        await MainActor.run {
            withAnimation {
                replyMessage = customMessage
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
                        entities: [],
                        text: text
                    )
                )
            ),
            replyToMessageId: replyMessage?.message.id ?? 0
        )
        
        await tdSetChatDraftMessage(draftMessage)
    }
}
