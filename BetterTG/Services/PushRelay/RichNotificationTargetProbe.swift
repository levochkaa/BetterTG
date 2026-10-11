// RichNotificationTargetProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    @MainActor enum RichNotificationTargetProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-notification-target") else { return }
            let result: String
            do {
                try verifyIdentity()
                try verifySelection()
                result = "PASS: production target helper/native TDLib models; exact nonnil account and peer kind/ID; "
                    + "chat response and message chat validated; cloud ID bounds and low-bit variants; "
                    + "matching notification retained before unrelated-last, unrelated-only rejected; "
                    + "preview permission remains separate; actual NSE/RPC/cache publication/session lifetime=unverified; "
                    + "RPC/account-stores/notifications/donations=0"
            } catch { result = "FAIL: \(error)" }
            log(result)
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("notification-target-probe.txt"), options: .atomic,
                )
            }
        }

        private static func verifyIdentity() throws {
            let peer = RichNotificationPeerReference(kind: .privateChat, id: 77)
            for account: Int64? in [nil, 0, -1] {
                try require(
                    RichNotificationTarget(accountID: account, peer: peer, serverMessageID: 88) == nil,
                    "invalid account admitted",
                )
            }
            for message: Int64? in [nil, 0, -1, Int64(Int32.max) + 1, Int64.max] {
                try require(
                    RichNotificationTarget(accountID: 101, peer: peer, serverMessageID: message) == nil,
                    "invalid cloud message ID admitted",
                )
            }
            for peerID: Int64 in [0, -77] {
                try require(
                    RichNotificationTarget(
                        accountID: 101, peer: .init(kind: .privateChat, id: peerID), serverMessageID: 88,
                    ) == nil, "invalid peer admitted",
                )
            }
            let target = RichNotificationTarget(accountID: 101, peer: peer, serverMessageID: 88)!
            try require(
                target.messageID == 88 << 20
                    && RichNotificationTarget(accountID: 101, peer: peer, serverMessageID: Int64(Int32.max))?
                    .messageID == Int64(Int32.max) << 20,
                "valid cloud ID conversion failed",
            )
            try require(
                target.matches(accountUserID: 101) && !target.matches(accountUserID: nil)
                    && !target.matches(accountUserID: 202), "account isolation failed",
            )
            let variants: [(RichNotificationPeerKind, ChatType, Int64)] = [
                (.privateChat, .chatTypePrivate(.init(userId: 77)), 77),
                (.basicGroup, .chatTypeBasicGroup(.init(basicGroupId: 77)), -77),
                (.supergroup, .chatTypeSupergroup(.init(supergroupId: 77, isChannel: false)), -1_000_000_000_077),
                (.supergroup, .chatTypeSupergroup(.init(supergroupId: 77, isChannel: true)), -1_000_000_000_077),
            ]
            for (kind, type, chatID) in variants {
                let current = RichNotificationTarget(
                    accountID: 101, peer: .init(kind: kind, id: 77), serverMessageID: 88,
                )!
                let wrongPeer = RichNotificationTarget(
                    accountID: 101, peer: .init(kind: kind, id: 78), serverMessageID: 88,
                )!
                try require(
                    current.expectedChatID == chatID
                        && current.matches(chatID: chatID, type: type, requestedChatID: chatID)
                        && !current.matches(chatID: chatID + 1, type: type, requestedChatID: chatID)
                        && !current.matches(chatID: 0, type: type, requestedChatID: 0)
                        && !wrongPeer.matches(chatID: chatID, type: type, requestedChatID: chatID),
                    "chat response or peer identity mismatch admitted",
                )
                for (otherKind, otherType, _) in variants where otherKind != kind {
                    try require(
                        !current.matches(chatID: chatID, type: otherType, requestedChatID: chatID),
                        "peer kind collision admitted",
                    )
                }
                try require(
                    !current.matches(
                        chatID: chatID, type: .chatTypeSecret(.init(secretChatId: 1, userId: 77)),
                        requestedChatID: chatID,
                    ), "secret chat admitted as cloud peer",
                )
            }
            try require(
                RichNotificationTarget(
                    accountID: 101, peer: .init(kind: .supergroup, id: 2_000_000_000_000), serverMessageID: 88,
                )?.expectedChatID == -3_000_000_000_000
                    && RichNotificationTarget(
                        accountID: 101, peer: .init(kind: .supergroup, id: Int64.max), serverMessageID: 88,
                    )?.expectedChatID == nil,
                "monoforum mapping or overflow guard failed",
            )
            try require(
                target.matches(messageID: target.messageID, messageChatID: 77, chatID: 77)
                    && !target.matches(messageID: target.messageID, messageChatID: 78, chatID: 77)
                    && !target.matches(messageID: target.messageID, messageChatID: 0, chatID: 0),
                "message chat mismatch admitted",
            )
            for wrongID in [0, target.messageID + 1, target.messageID + 4, 89 << 20] {
                try require(
                    !target.matches(messageID: wrongID, messageChatID: 77, chatID: 77),
                    "nonexact raw message ID admitted",
                )
            }
        }

        private static func verifySelection() throws {
            let target = RichNotificationTarget(
                accountID: 101, peer: .init(kind: .privateChat, id: 77), serverMessageID: 88,
            )!
            let matchingPush = push(id: 1, messageID: target.messageID)
            let unrelatedLast = push(id: 2, messageID: target.messageID + (1 << 20))
            let localVariant = push(id: 3, messageID: target.messageID + 1)
            try require(
                target.notification(in: [matchingPush, unrelatedLast], groupChatID: 77)?.id == matchingPush.id
                    && target.notification(in: [unrelatedLast, localVariant], groupChatID: 77) == nil
                    && target.notification(in: [], groupChatID: 77) == nil
                    && target.notification(in: [matchingPush], groupChatID: 0) == nil
                    && target.notification(in: [matchingPush], groupChatID: 78) == nil
                    && target.notification(in: [matchingPush], groupChatID: -77) == nil
                    && target.notification(in: [matchingPush], groupChatID: -1_000_000_000_077) == nil,
                "notification selection used unrelated-last or low-bit fallback",
            )
            let fullMessage = TDNativeNotification(
                id: 4,
                date: 1,
                isSilent: false,
                type: .notificationTypeNewMessage(.init(
                    message: MessageDeliveryProbe.fixture(id: target.messageID, chatID: 77), showPreview: true,
                )),
            )
            let hiddenMessage = TDNativeNotification(
                id: 5,
                date: 1,
                isSilent: false,
                type: .notificationTypeNewMessage(.init(
                    message: MessageDeliveryProbe.fixture(id: target.messageID, chatID: 77), showPreview: false,
                )),
            )
            let wrongChat = TDNativeNotification(
                id: 6,
                date: 1,
                isSilent: false,
                type: .notificationTypeNewMessage(.init(
                    message: MessageDeliveryProbe.fixture(id: target.messageID, chatID: 78), showPreview: true,
                )),
            )
            try require(
                target.notification(in: [fullMessage, wrongChat, unrelatedLast], groupChatID: 77)?.id == fullMessage.id
                    && target.notification(in: [wrongChat], groupChatID: 77) == nil
                    && target.notification(in: [fullMessage], groupChatID: 78) == nil,
                "full notification message accepted for wrong group chat",
            )
            // Identity must identify a denial too; visibility is a separate resolver decision.
            try require(
                target.matches(notification: hiddenMessage, groupChatID: 77),
                "showPreview denial lost exact identity",
            )
        }

        private static func push(id: Int, messageID: Int64) -> TDNativeNotification {
            .init(
                id: id,
                date: 1,
                isSilent: false,
                type: .notificationTypeNewPushMessage(.init(
                    messageId: messageID,
                    senderId: .messageSenderUser(.init(userId: 77)),
                    senderName: "Probe",
                    isOutgoing: false,
                    content: .pushMessageContentText(.init(text: "probe", isPinned: false)),
                )),
            )
        }

        private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure(description: message) }
        }
    }
#endif
