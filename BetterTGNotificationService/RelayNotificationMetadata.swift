// RelayNotificationMetadata.swift

import Foundation

struct RelayNotificationMetadata {
    // MARK: Lifecycle

    init?(userInfo: [AnyHashable: Any]) {
        guard let data = userInfo["tg"] as? [String: Any],
              let peerKindValue = data["peer_type"] as? String,
              let peerKind = RichNotificationPeerKind(rawValue: peerKindValue),
              let peerID = Self.int64(data["peer_id"])
        else { return nil }

        self.accountID = Self.int64(data["account"])
        self.peer = RichNotificationPeerReference(kind: peerKind, id: peerID)
        self.sender =
            if let senderKindValue = data["sender_type"] as? String,
            let senderKind = RichNotificationPeerKind(rawValue: senderKindValue),
            let senderID = Self.int64(data["sender_id"]) {
                RichNotificationPeerReference(kind: senderKind, id: senderID)
            } else {
                peer
            }
        self.serverMessageID = Self.int64(data["message_id"])
        self.event = data["event"] as? String
        self.senderName = data["sender_name"] as? String
        self.conversationTitle = data["conversation_title"] as? String
        self.notificationPayloadToken = data["notification_payload_token"] as? String
    }

    // MARK: Internal

    let accountID: Int64?
    let peer: RichNotificationPeerReference
    let sender: RichNotificationPeerReference
    let serverMessageID: Int64?
    let event: String?
    let senderName: String?
    let conversationTitle: String?
    let notificationPayloadToken: String?

    var messageReference: RichNotificationMessageReference? {
        guard let serverMessageID else { return nil }
        return RichNotificationMessageReference(peer: peer, serverMessageID: serverMessageID)
    }

    // MARK: Private

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let string as String: Int64(string)
        case let number as NSNumber: number.int64Value
        case let integer as Int64: integer
        default: nil
        }
    }
}
