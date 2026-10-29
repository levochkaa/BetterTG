// AttachmentMessageSequence.swift

import Foundation
import TDLibKit

/// ChatControllerOpenAttachmentMenu enqueues a contact comment before the cards, in the same topic.
/// Only the cards take the composer's reply. Splitting long comments keeps their UTF-16 entities intact.
enum AttachmentMessageSequence {
    struct Item {
        let content: InputMessageContent
        let repliesToComposer: Bool
    }

    static func items(contents: [InputMessageContent], comment: AttributedString) -> [Item] {
        guard !contents.isEmpty else { return [] }
        let comments = ComposerTextBreaker.messages(comment).map { part in
            Item(content: .inputMessageText(InputMessageText(
                clearDraft: false,
                linkPreviewOptions: nil,
                text: ComposerText.formatted(part),
            )), repliesToComposer: false)
        }
        return comments + contents.map { Item(content: $0, repliesToComposer: true) }
    }
}
