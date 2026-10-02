// ChatUpdateDeliveryProbe.swift

#if DEBUG
    import Combine
    import Foundation
    import TDLibKitDynamic

    @MainActor enum ChatUpdateDeliveryProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private final class Owner {
            let location: ChatLocation
            var isCurrent = true
            var received = [String]()
            var authorities = [ChatUpdateDeliveryAuthority]()

            init(location: ChatLocation) { self.location = location }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-chat-update-delivery") else { return }
            Task { @MainActor in
                let result: String
                do {
                    try await verify()
                    result = "Chat update delivery probe passed: production-observer/scoped-source=true; "
                        + "queued-old-client/account-collision/unscoped-rejected=true; "
                        + "post-hydration-client/account/retired-owner/route-fences=true; "
                        + "current-delivery-and-legacy-transport-preserved=true; "
                        + "same-epoch-message-ordering-not-covered; server-reads/sends/account-stores=0"
                } catch {
                    result = "Chat update delivery probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("chat-update-delivery-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verify() async throws {
            let center = NotificationCenter()
            var subscriptions = Set<AnyCancellable>()
            defer { subscriptions.removeAll() }
            let sourceA1 = TdUpdateSource(accountID: UUID(), clientID: 11)
            let sourceA2 = TdUpdateSource(accountID: sourceA1.accountID, clientID: 12)
            let sourceA3 = TdUpdateSource(accountID: sourceA1.accountID, clientID: 13)
            let sourceB = TdUpdateSource(accountID: UUID(), clientID: 22)
            var currentSource: TdUpdateSource? = sourceA1
            let ownerA1 = Owner(location: .init(accountID: sourceA1.accountID, chatID: 100, clientID: 11, topic: nil))
            let ownerA2 = Owner(location: .init(accountID: sourceA2.accountID, chatID: 100, clientID: 12, topic: nil))
            let ownerB = Owner(location: .init(accountID: sourceB.accountID, chatID: 100, clientID: 22, topic: nil))
            var rawDeliveryCount = 0
            center.publisher(&subscriptions, for: .updateChatTitle) { _ in rawDeliveryCount += 1 }

            func observe(_ owner: Owner) {
                ChatUpdateDeliveryAuthority.observe(
                    .updateChatTitle, center: center, subscriptions: &subscriptions, location: owner.location,
                    currentLocation: { owner.location }, currentSource: { currentSource },
                    ownerIsCurrent: { owner.isCurrent },
                    perform: { value, authority in
                        owner.received.append(value.title)
                        owner.authorities.append(authority)
                    },
                )
            }
            func post(_ title: String, source: TdUpdateSource?) {
                update(
                    .updateChatTitle(.init(chatId: 100, title: title)), source: source,
                    notificationCenter: center,
                )
            }

            observe(ownerA1)
            post("accepted A1", source: sourceA1)
            await drainMainQueue()
            try require(ownerA1.received == ["accepted A1"], "current source was rejected")
            let authority = ownerA1.authorities[0]
            try require(
                authority.permits(
                    currentLocation: ownerA1.location,
                    currentSource: currentSource,
                    ownerIsCurrent: true,
                ),
                "current hydration completion was rejected",
            )

            // Queue an accepted update and a previously accepted hydration
            // continuation, then replace the client before either UI delivery.
            post("queued A1", source: sourceA1)
            var lateHydrationApplied = false
            DispatchQueue.main.async {
                lateHydrationApplied = authority.permits(
                    currentLocation: ownerA1.location, currentSource: currentSource, ownerIsCurrent: ownerA1.isCurrent,
                )
            }
            currentSource = sourceA2
            observe(ownerA2)
            post("old A1 after replacement", source: sourceA1)
            post("accepted A2", source: sourceA2)
            post("missing source", source: nil)
            await drainMainQueue()
            try require(
                ownerA1.received == ["accepted A1"] && ownerA2.received == ["accepted A2"]
                    && !lateHydrationApplied && rawDeliveryCount == 5,
                "queued/unscoped/old-client update or hydration reached replacement UI",
            )

            let authorityA2 = ownerA2.authorities[0]
            currentSource = sourceB
            observe(ownerB)
            post("foreign A2", source: sourceA2)
            post("accepted B", source: sourceB)
            await drainMainQueue()
            try require(
                ownerB.received == ["accepted B"] && ownerA2.received == ["accepted A2"]
                    && !authorityA2.permits(
                        currentLocation: ownerA2.location, currentSource: currentSource, ownerIsCurrent: true,
                    ),
                "colliding IDs from another account passed",
            )
            currentSource = sourceA3
            post("return to A old client", source: sourceA2)
            await drainMainQueue()
            try require(
                ownerA1.received == ["accepted A1"] && ownerA2.received == ["accepted A2"]
                    && !authorityA2.permits(
                        currentLocation: ownerA2.location, currentSource: currentSource, ownerIsCurrent: true,
                    ),
                "A to B to A rebound an old hydration authority",
            )

            // Restore the isolated identity only to exercise owner and route
            // barriers independently; no real client or account is switched.
            currentSource = sourceA2
            ownerA2.isCurrent = false
            post("retired A2", source: sourceA2)
            await drainMainQueue()
            try require(
                ownerA2.received == ["accepted A2"]
                    && !authorityA2.permits(
                        currentLocation: ownerA2.location, currentSource: currentSource, ownerIsCurrent: false,
                    ),
                "retired owner accepted an update or hydration",
            )
            let otherChat = ChatLocation(accountID: sourceA2.accountID, chatID: 101, clientID: 12, topic: nil)
            let otherTopic = ownerA2.location.withForumTopic(id: 7)
            for location in [otherChat, otherTopic] {
                try require(
                    !authorityA2.permits(currentLocation: location, currentSource: currentSource, ownerIsCurrent: true),
                    "delivery authority crossed the captured chat/topic route",
                )
            }
            try require(
                !authorityA2.permits(currentLocation: nil, currentSource: sourceA2, ownerIsCurrent: true)
                    && !authorityA2.permits(
                        currentLocation: ownerA2.location, currentSource: nil, ownerIsCurrent: true,
                    )
                    && ChatUpdateDeliveryAuthority(source: nil, location: ownerA2.location) == nil
                    && ChatUpdateDeliveryAuthority(source: sourceB, location: ownerA2.location) == nil
                    && rawDeliveryCount == 9,
                "missing origin/owner/bootstrap accepted or shared transport changed",
            )
        }

        private static func drainMainQueue() async {
            // All receive(on:) deliveries above precede this bounded FIFO barrier.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
#endif
