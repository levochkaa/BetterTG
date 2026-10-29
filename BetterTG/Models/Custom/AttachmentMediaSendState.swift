// AttachmentMediaSendState.swift

import TDLibKit
import UIKit

/// The sheet's send-time values survive Photos reads and TDLib preparation without borrowing a newer draft.
@MainActor final class AttachmentMediaSendState {
    let images: [SelectedImage]
    let caption: AttributedString
    let initialText: AttributedString
    let initialRevision: UInt64?
    let captionIsAbove: Bool
    let context: ResolvedSendContext
    let reply: CustomMessage?
    let forward: PendingMessageForward?
    private(set) var acceptedCount = 0

    var remainingAssetIDs: Set<String> {
        Set(images.dropFirst(acceptedCount).compactMap(\.sourceAssetIdentifier))
    }

    init(
        images: [SelectedImage], caption: AttributedString, initialText: AttributedString, initialRevision: UInt64?,
        captionIsAbove: Bool, context: ResolvedSendContext, reply: CustomMessage?, forward: PendingMessageForward?,
    ) {
        self.images = images
        self.caption = caption
        self.initialText = initialText
        self.initialRevision = initialRevision
        self.captionIsAbove = captionIsAbove
        self.context = context
        self.reply = reply
        self.forward = forward
    }

    /// Revisions belong to a VM. Only an unchanged source draft may be consumed in its replacement.
    static func transferredDraftRevision(
        initialText: AttributedString, initialRevision: UInt64?, currentText: AttributedString,
        currentRevision: UInt64, replacementRevision: UInt64,
    ) -> UInt64? {
        initialText == currentText && initialRevision == currentRevision ? replacementRevision : nil
    }

    func accepted(_ count: Int) { acceptedCount += count }

    func consumesDraft(_ text: AttributedString, revision: UInt64) -> Bool {
        text == initialText && revision == initialRevision
    }
}
