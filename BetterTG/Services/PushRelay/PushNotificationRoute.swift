// PushNotificationRoute.swift

import Foundation

struct PushNotificationRoute: Hashable {
    // MARK: Internal

    enum PeerType: String, Hashable {
        case privateChat = "private"
        case basicGroup
        case supergroup
    }

    let accountId: Int64?
    let peerType: PeerType
    let peerId: Int64
    let serverMessageId: Int64?
    let event: String?
    let maxId: Int64?
    let deletedMessageIds: Set<Int64>

    var tdlibMessageId: Int64? {
        guard let serverMessageId,
              serverMessageId > 0,
              serverMessageId <= Int64.max >> 20
        else { return nil }
        return serverMessageId << 20
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let data = userInfo["tg"] as? [String: Any],
              let peerTypeValue = data["peer_type"] as? String,
              let peerType = PeerType(rawValue: peerTypeValue),
              let peerId = Self.int64(data["peer_id"])
        else { return nil }

        self.peerType = peerType
        self.peerId = peerId
        self.accountId = Self.int64(data["account"])
        self.serverMessageId = Self.int64(data["message_id"])
        self.event = data["event"] as? String
        self.maxId = Self.int64(data["max_id"])
        self.deletedMessageIds = Set(
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

    func refersToSameConversation(as other: Self) -> Bool {
        accountId == other.accountId && peerType == other.peerType && peerId == other.peerId
    }
}
