// PushNotificationRoute.swift

import Foundation

struct PushNotificationRoute: Hashable {
    // MARK: Internal

    enum PeerType: String, Hashable {
        case privateChat = "private"
        case basicGroup
        case supergroup
    }

    let accountID: Int64?
    let peerType: PeerType
    let peerID: Int64
    let serverMessageID: Int64?
    let topServerMessageID: Int64?
    let event: String?
    let maxID: Int64?
    let deletedMessageIDs: Set<Int64>

    var tdlibMessageID: Int64? {
        Self.tdlibMessageID(from: serverMessageID)
    }

    var tdlibTopMessageID: Int64? {
        Self.tdlibMessageID(from: topServerMessageID)
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let data = userInfo["tg"] as? [String: Any],
              let peerTypeValue = data["peer_type"] as? String,
              let peerType = PeerType(rawValue: peerTypeValue),
              let peerID = Self.int64(data["peer_id"])
        else { return nil }

        self.peerType = peerType
        self.peerID = peerID
        self.accountID = Self.int64(data["account"])
        self.serverMessageID = Self.int64(data["message_id"])
        self.topServerMessageID = Self.int64(data["top_message_id"])
        self.event = data["event"] as? String
        self.maxID = Self.int64(data["max_id"])
        self.deletedMessageIDs = Set(
            (data["messages"] as? String)?
                .split(separator: ",")
                .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) } ?? [],
        )
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

    private static func tdlibMessageID(from serverMessageID: Int64?) -> Int64? {
        guard let serverMessageID,
              serverMessageID > 0,
              serverMessageID <= Int64.max >> 20
        else { return nil }
        return serverMessageID << 20
    }

    func refersToSameConversation(as other: Self) -> Bool {
        accountID == other.accountID && peerType == other.peerType && peerID == other.peerID
    }
}
