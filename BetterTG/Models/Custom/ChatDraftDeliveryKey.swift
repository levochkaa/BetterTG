// ChatDraftDeliveryKey.swift

import Foundation
import TDLibKitDynamic

// MARK: - ChatDraftDeliveryKey

/// A send's frozen TDLib destination, distinct from the composer route that owns its draft.
struct ChatDraftDeliveryKey: Hashable {
    let accountID: UUID?
    let chatID: Int64
    let topic: MessageTopic?

    var legacyBaseRoute: ChatDraftKey {
        ChatDraftKey(accountID: accountID, chatID: chatID, topic: nil)
    }

    func candidate<Draft: ChatDraftSendScoped>(
        in drafts: [Draft],
        temporaryMessageID: Int64,
    ) -> Draft? {
        let matching = drafts.filter { $0.deliveryKey == self }
        let registered = matching.filter { $0.temporaryMessageID == temporaryMessageID }
        if !registered.isEmpty {
            return registered.count == 1 ? registered[0] : nil
        }
        let enqueueing = matching.filter { $0.enqueueStartedAt != nil && $0.temporaryMessageID == nil }
        return enqueueing.count == 1 ? enqueueing[0] : nil
    }
}

// MARK: - ChatDraftSendScoped

protocol ChatDraftSendScoped: ChatDraftScoped {
    var enqueueStartedAt: Foundation.Date? { get }
    var sendTopic: MessageTopic? { get }
    var temporaryMessageID: Int64? { get }
}

extension ChatDraftSendScoped {
    var deliveryKey: ChatDraftDeliveryKey {
        ChatDraftDeliveryKey(
            accountID: resolvedDestination.accountID,
            chatID: chatID,
            topic: sendTopic ?? destination?.topic,
        )
    }
}
