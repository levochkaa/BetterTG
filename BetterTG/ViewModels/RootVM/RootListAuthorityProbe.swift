// RootListAuthorityProbe.swift

#if DEBUG
    import Combine
    import Foundation
    import TDLibKit

    @MainActor enum RootListAuthorityProbe {
        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-root-list-authority") else { return }
            Task {
                let passed = await verify()
                let result = passed
                    ? "Root list authority probe passed: production-ticket/scoped-delivery=true; "
                        + "delayed-A-to-B/same-account-new-client/unscoped=fenced; "
                        + "A-B-A-request-epoch/owner-account=fenced; current-update-once=true; "
                        + "RootVM/RPC-client-wiring=source-reviewed; real-account-switch/RPC=unverified; server-writes=0"
                    : "Root list authority probe failed"
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("root-list-authority-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func verify() async -> Bool {
            let authority = RootListAuthority()
            let first = TdUpdateSource(accountID: UUID(), clientID: 1)
            let other = TdUpdateSource(accountID: UUID(), clientID: 2)
            let replacement = TdUpdateSource(accountID: first.accountID, clientID: 3)
            var current: TdUpdateSource? = first
            var owner: UUID? = first.accountID
            func accepts(_ source: TdUpdateSource) -> Bool {
                authority.accepts(source, ownerAccountID: owner, activeSource: current)
            }
            func accepts(_ ticket: RootListAuthority.Ticket) -> Bool {
                authority.accepts(ticket, ownerAccountID: owner, activeSource: current)
            }
            guard let initial = authority.capture(ownerAccountID: owner, activeSource: current),
                  accepts(initial), accepts(first), !accepts(other) else { return false }
            let center = NotificationCenter()
            var subscriptions = Set<AnyCancellable>()
            var titles = [String]()
            center.scopedPublisher(&subscriptions, for: .updateChatTitle) { event in
                guard accepts(event.source) else { return }
                titles.append(event.value.title)
            }
            // Freeze the source before delayed main-queue delivery, as the
            // generated TD dispatcher does. Colliding numeric chat ID is deliberate.
            center.postTdUpdate(
                name: .updateChatTitle,
                object: UpdateChatTitle(chatId: 7, title: "old-A"),
                source: first,
            )
            current = other
            owner = other.accountID
            authority.invalidate()
            center.postTdUpdate(
                name: .updateChatTitle,
                object: UpdateChatTitle(chatId: 7, title: "current-B"),
                source: other,
            )
            center.post(name: .updateChatTitle, object: UpdateChatTitle(chatId: 7, title: "unscoped"))
            await drainMainQueue()
            guard titles == ["current-B"], !accepts(initial) else { return false }
            // Even an artificial A→B→A return with the same native ID cannot
            // revive a request ticket from the previous root ownership epoch.
            current = first
            owner = first.accountID
            authority.invalidate()
            guard accepts(first), !accepts(initial) else { return false }
            guard let returned = authority.capture(ownerAccountID: owner, activeSource: current) else { return false }
            center.postTdUpdate(
                name: .updateChatTitle,
                object: UpdateChatTitle(chatId: 7, title: "old-client"),
                source: first,
            )
            current = replacement
            authority.invalidate()
            center.postTdUpdate(
                name: .updateChatTitle,
                object: UpdateChatTitle(chatId: 7, title: "current-client"),
                source: replacement,
            )
            await drainMainQueue()
            guard titles == ["current-B", "current-client"], !accepts(returned) else { return false }
            owner = other.accountID
            guard !accepts(replacement), authority.capture(ownerAccountID: owner, activeSource: current) == nil else {
                return false
            }
            owner = replacement.accountID
            current = nil
            return !accepts(replacement) && authority.capture(ownerAccountID: owner, activeSource: current) == nil
        }

        private static func drainMainQueue() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
#endif
