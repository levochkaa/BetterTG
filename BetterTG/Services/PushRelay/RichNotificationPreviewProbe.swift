// RichNotificationPreviewProbe.swift

#if DEBUG
    import Foundation
    import TDLibKitDynamic

    @MainActor enum RichNotificationPreviewProbe {
        private typealias Models = RichNotificationMediaPrewarmerProbe
        private typealias Policy = RichNotificationPreviewPolicy
        private typealias Lifetime = RichNotificationSessionLifetime<RichNotificationPreview>
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Gate {
            private var pending: CheckedContinuation<Void, Never>?
            private var observer: CheckedContinuation<Bool, Never>?
            private var entered = false
            private var opened = false

            func hold() async {
                guard !opened else { return }
                await withCheckedContinuation { continuation in
                    pending = continuation
                    entered = true
                    observer?.resume(returning: true)
                    observer = nil
                }
            }

            func wait() async -> Bool {
                if entered { return true }
                return await withCheckedContinuation { continuation in
                    observer = continuation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.observer?.resume(returning: false)
                        self?.observer = nil
                    }
                }
            }

            func open() {
                opened = true
                let receipt = pending
                pending = nil
                receipt?.resume()
            }
        }

        private static let target = RichNotificationTarget(
            accountID: 101, peer: .init(kind: .privateChat, id: 7), serverMessageID: 88,
        )!
        private static let bytes = Data([7, 8, 9])

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-notification-preview") else { return }
            Task {
                let report: String
                do {
                    try await verifySelection()
                    try verifyBatches()
                    try await verifyRevocation()
                    report = "PASS: production preview policy/conditional lifetime/native TDLib models; "
                        + "full-message evidence required despite push thumbnail; ordinary media/body and nonmedia preserved; "
                        + "hidden/showPreview/secret/spoiler/self-destruct denied; denied/unresolved omit bytes/body; "
                        + "whole-batch both orders, bound replacement, exact client/chat/raw isolation; "
                        + "held fetch/download revoked by content/edit/delete/hidden, late publish/finish refused; "
                        + "actual NSE/builder/donation/TDLib/durable cache-only restoration=unverified; RPC/donations=0"
                } catch { report = "FAIL: \(error)" }
                log(report)
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(report.utf8).write(
                        to: documents.appendingPathComponent("notification-preview-probe.txt"), options: .atomic,
                    )
                }
            }
        }

        private static func verifySelection() async throws {
            for kind: Models.Kind in [.photo, .video, .animation, .videoNote, .document, .sticker] {
                let message = Models.message(Models.content(kind))
                var fetches = 0
                let selected = await Policy.select(
                    notification: full(message), target: target, chatID: 7, isCurrent: { true },
                    fetch: { fetches += 1
                    return nil
                    },
                )
                try require(
                    fetches == 0 && selected.preview(data: bytes) == .allowed(bytes),
                    "ordinary full media denied",
                )
                try require(
                    selected.preview(data: nil) == .allowed(nil)
                        && selected.preview(data: nil).bodyOverride("caption") == "caption",
                    "verified no-thumbnail body permission lost",
                )
            }
            let ordinary = Models.message(Models.content(.photo))
            let noThumbnail = Models.message(.messagePhoto(.init(
                caption: .init(entities: [], text: "caption"), hasSpoiler: false, isSecret: false,
                photo: .init(hasStickers: false, minithumbnail: nil, sizes: []),
                showCaptionAboveMedia: false, video: nil,
            )))
            let noThumbnailSelection = await Policy.select(
                notification: full(noThumbnail), target: target, chatID: 7, isCurrent: { true }, fetch: { nil },
            )
            try require(
                noThumbnailSelection.preview(data: nil) == .allowed(nil)
                        && noThumbnailSelection.preview(data: nil).bodyOverride("caption") == "caption",
                "full message without media candidate lost body permission",
            )
            let withThumbnail = pushPhoto()
            var fetches = 0
            let selected = await Policy.select(
                notification: withThumbnail, target: target, chatID: 7, isCurrent: { true },
                fetch: { fetches += 1
                return ordinary
                },
            )
            try require(
                fetches == 1 && selected.preview(data: bytes) == .allowed(bytes),
                "push bypassed full-message fetch",
            )
            let concealed: [Message] = [
                Models.message(Models.content(.photo, secret: true)),
                Models.message(Models.content(.photo, spoiler: true)),
                Models.message(Models.content(.video, secret: true)),
                Models.message(Models.content(.video, spoiler: true)),
                Models.message(Models.content(.animation, secret: true)),
                Models.message(Models.content(.animation, spoiler: true)),
                Models.message(Models.content(.videoNote, secret: true)),
                Models.message(Models.content(.photo), destruction: .messageSelfDestructTypeImmediately),
                Models.message(
                    Models.content(.photo),
                    destruction: .messageSelfDestructTypeTimer(.init(selfDestructTime: 30)),
                ),
                Models.message(Models.content(.photo), destructionIn: 2),
            ]
            for message in concealed {
                let direct = await Policy.select(
                    notification: full(message), target: target, chatID: 7, isCurrent: { true },
                    fetch: { fetches += 1
                    return ordinary
                    },
                )
                let fetched = await Policy.select(
                    notification: withThumbnail, target: target, chatID: 7, isCurrent: { true }, fetch: { message },
                )
                try require(
                    direct.preview(data: bytes) == .denied && fetched.preview(data: bytes) == .denied,
                    "concealed full envelope admitted",
                )
            }
            try require(fetches == 1, "denied full message performed a fetch")
            for notification in [hidden(), full(ordinary, showPreview: false), pushPhoto(secret: true)] {
                let denied = await Policy.select(
                    notification: notification, target: target, chatID: 7, isCurrent: { true },
                    fetch: { fetches += 1
                    return ordinary
                    },
                )
                try require(
                    denied.preview(data: bytes) == .denied && fetches == 1,
                    "explicit denial fetched or admitted",
                )
            }
            for response in [
                nil,
                Models.message(Models.content(.photo), chatID: 8),
                Models.message(Models.content(.photo), id: target.messageID + 1),
            ] as [Message?] {
                let unresolved = await Policy.select(
                    notification: withThumbnail, target: target, chatID: 7, isCurrent: { true }, fetch: { response },
                )
                try require(
                    unresolved.preview(data: bytes) == .unresolved,
                    "unresolved/wrong identity promoted push media",
                )
            }
            let nonMedia = await Policy.select(
                notification: full(MessageDeliveryProbe.fixture(id: target.messageID, chatID: 7)),
                target: target, chatID: 7, isCurrent: { true }, fetch: { fetches += 1
                return ordinary
                },
            )
            guard case .nonMedia = nonMedia else { throw Failure(description: "ordinary text treated as concealed") }
            let expiring = await Policy.select(
                notification: full(Models.message(Models.content(.photo), autoDeleteIn: 30)),
                target: target, chatID: 7, isCurrent: { true }, fetch: { nil },
            )
            try require(expiring.preview(data: bytes) == .allowed(bytes), "ordinary chat auto-delete treated as secret")
            for decision: RichNotificationPreview in [.denied, .unresolved] {
                try require(
                    decision.attachmentData == nil && decision.bodyOverride("private caption") == nil,
                    "denied/unresolved allowed bytes or generated body",
                )
            }
        }

        private static func verifyBatches() throws {
            for notifications in [[hidden(id: 1), pushPhoto(id: 2)], [pushPhoto(id: 1), hidden(id: 2)]] {
                let lifetime = Lifetime()
                var results = [RichNotificationPreview?]()
                var observation = Policy.Observation()
                try require(lifetime.begin { results.append($0) } && lifetime.createClient { 11 }, "batch not armed")
                try require(lifetime.finish(.denied, clientID: 11, when: {
                    observation.revokes(group(notifications), target: target)
                }), "whole batch denial lost")
                try require(
                    lifetime.reserve(.resolve, clientID: 11) == nil && !lifetime.finish(nil)
                            && results == [.denied],
                    "denied batch reopened or nil overwrote result",
                )
            }
            var observation = Policy.Observation()
            let replacement = Update.updateNotification(.init(notification: hidden(), notificationGroupId: 5))
            try require(!observation.revokes(replacement, target: target), "unbound replacement admitted")
            try require(
                !observation.revokes(group([pushPhoto()], chatID: 8), target: target)
                        && !observation.revokes(replacement, target: target),
                "wrong chat bound replacement",
            )
            try require(
                !observation.revokes(group([pushPhoto()]), target: target)
                        && observation.revokes(replacement, target: target),
                "exact later replacement denial missed",
            )
            try require(
                !observation.revokes(
                    .updateNotification(.init(notification: pushPhoto(), notificationGroupId: 5)),
                    target: target,
                ),
                "ordinary bound replacement denied",
            )
            try require(!observation.revokes(.updateNotification(.init(
                notification: full(Models.message(Models.content(.photo), chatID: 8), showPreview: false),
                notificationGroupId: 5,
            )), target: target), "bound group accepted a different full-message chat")
            try require(!observation.revokes(
                .updateNotification(.init(notification: hidden(), notificationGroupId: 6)),
                target: target,
            ), "wrong group revoked")
        }

        private static func verifyRevocation() async throws {
            let ordinary = Models.message(Models.content(.photo))
            let changes: [Update] = [
                group([hidden()]),
                group([full(ordinary, showPreview: false)]),
                .updateNotification(.init(notification: hidden(), notificationGroupId: 5)),
                .updateMessageContent(.init(
                    chatId: 7,
                    messageId: target.messageID,
                    newContent: Models.content(.photo, spoiler: true),
                )),
                .updateMessageEdited(.init(chatId: 7, editDate: 1, messageId: target.messageID, replyMarkup: nil)),
                .updateDeleteMessages(.init(
                    chatId: 7,
                    fromCache: false,
                    isPermanent: true,
                    messageIds: [target.messageID],
                )),
            ]
            for duringFetch in [true, false] {
                for update in changes {
                    let lifetime = Lifetime()
                    let gate = Gate()
                    var results = [RichNotificationPreview?]()
                    var observation = Policy.Observation()
                    var publications = 0
                    var fetches = 0
                    try require(
                        lifetime.begin { results.append($0) } && lifetime.createClient { 11 },
                        "held fixture not armed",
                    )
                    try require(!lifetime.finish(.denied, clientID: 11, when: {
                        observation.revokes(group([pushPhoto()]), target: target)
                    }), "ordinary batch denied")
                    guard let ticket = lifetime.reserve(.resolve, clientID: 11)
                        else { throw Failure(description: "no resolver") }
                    let task = Task {
                        let selection = await Policy.select(
                            notification: pushPhoto(), target: target, chatID: 7,
                            isCurrent: { lifetime.isCurrent(ticket) }, fetch: {
                                fetches += 1
                                if duringFetch { await gate.hold() }
                                return ordinary
                            },
                        )
                        if !duringFetch { await gate.hold() }
                        _ = lifetime.publish(ticket) { publications += 1 }
                        lifetime.finish(selection.preview(data: bytes), ticket: ticket)
                        lifetime.complete(ticket)
                    }
                    lifetime.install(task, for: ticket)
                    defer { gate.open()
                    lifetime.finish(nil)
                    }
                    let entered = await gate.wait()
                    try require(entered && fetches == 1 && lifetime.isCurrent(ticket), "exact async stage not held")
                    try require(!lifetime.finish(.denied, clientID: 22, when: {
                        observation.revokes(update, target: target)
                    }) && lifetime.isCurrent(ticket), "wrong client revoked")
                    try require(lifetime.finish(.denied, clientID: 11, when: {
                        observation.revokes(update, target: target)
                    }), "matching observed denial failed")
                    try require(
                        !lifetime.finish(nil) && !lifetime.finish(.allowed(bytes), ticket: ticket),
                        "denial overwritten",
                    )
                    gate.open()
                    await task.value
                    try require(
                        results == [.denied] && publications == 0,
                        "late async work published or replaced denial",
                    )
                }
            }
            let lifetime = Lifetime()
            var results = [RichNotificationPreview?]()
            var observation = Policy.Observation()
            var publications = 0
            try require(
                lifetime.begin { results.append($0) } && lifetime.createClient { 11 },
                "positive lifetime absent",
            )
            guard let ticket = lifetime.reserve(.resolve, clientID: 11)
                else { throw Failure(description: "positive resolver absent") }
            for update in [
                group([hidden()], chatID: 8),
                .updateMessageEdited(.init(chatId: 7, editDate: 1, messageId: target.messageID + 1, replyMarkup: nil)),
                .updateDeleteMessages(.init(
                    chatId: 8,
                    fromCache: false,
                    isPermanent: true,
                    messageIds: [target.messageID],
                )),
            ] {
                try require(!lifetime.finish(.denied, clientID: 11, when: {
                    observation.revokes(update, target: target)
                }), "unrelated identity revoked positive resolver")
            }
            try require(
                lifetime.publish(ticket) { publications += 1 }
                        && lifetime.finish(.allowed(bytes), ticket: ticket)
                        && publications == 1 && results == [.allowed(bytes)],
                "ordinary publication/finish broken",
            )
        }

        private static func full(_ message: Message, showPreview: Bool = true) -> TDLibKitDynamic.Notification {
            .init(date: 1, id: 1, isSilent: false, type: .notificationTypeNewMessage(.init(
                message: message, showPreview: showPreview,
            )))
        }

        private static func hidden(id: Int = 1) -> TDLibKitDynamic.Notification {
            push(.pushMessageContentHidden(.init(isPinned: false)), id: id)
        }

        private static func pushPhoto(secret: Bool = false, id: Int = 2) -> TDLibKitDynamic.Notification {
            guard case .messagePhoto(let value) = Models.content(.photo) else { preconditionFailure() }
            return push(.pushMessageContentPhoto(.init(
                caption: "caption",
                isPinned: false,
                isSecret: secret,
                photo: value.photo,
            )), id: id)
        }

        private static func push(_ content: PushMessageContent, id: Int) -> TDLibKitDynamic.Notification {
            .init(date: 1, id: id, isSilent: false, type: .notificationTypeNewPushMessage(.init(
                content: content, isOutgoing: false, messageId: target.messageID,
                senderId: .messageSenderUser(.init(userId: 7)), senderName: "Probe",
            )))
        }

        private static func group(_ notifications: [TDLibKitDynamic.Notification], chatID: Int64 = 7) -> Update {
            .updateNotificationGroup(.init(
                addedNotifications: notifications, chatId: chatID, notificationGroupId: 5,
                notificationSettingsChatId: chatID, notificationSoundId: 0,
                removedNotificationIds: [], totalCount: notifications.count, type: .notificationGroupTypeMessages,
            ))
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            if !condition { throw Failure(description: detail) }
        }
    }
#endif
